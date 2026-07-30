//
//  NNWTitleTranslationController.swift
//  NetNewsWire — AI 翻译 fork
//
//  [翻译] 本 fork 新增,上游没有这个文件。标题翻译(T32①)的调度中枢。
//
//  ## 工作方式:挂在"每一行装配数据"的必经之路上,自己攒批
//
//  时间线给每一行装配显示数据时都会来问一次 `displayArticle(for:)`:
//  - 这个源没开「标题翻译」→ 原样返回,一分钱判断都不花
//  - 开了、缓存里有译文     → 返回一个**换了标题的内存副本**(Article 是纯数据对象,
//    公开构造器;换标题不碰数据库、不碰上游任何状态)
//  - 开了、还没有译文       → 原样返回(先显示原文),同时把它记进待翻名单
//
//  待翻名单不会来一条翻一条 —— 那是最费 token 的方式(每条都要重复付一遍系统提示词)。
//  攒 0.4 秒(一屏 cell 的装配在一两帧内全会到齐),再按批(≤40 条)打包成**一次**请求。
//  翻完写缓存、发通知,时间线收到通知刷新可见行,原文原地变中文。
//
//  ## 为什么智能源(今天/未读/星标)天然被覆盖
//  它们和单源列表走的是同一个装配入口,文章自己带着 accountID/feedID ——
//  开没开开关是按**文章所属的源**判断的,和当前列表是谁无关。
//
//  ## 失败怎么办
//  整批失败(断网、key 没配)→ 这批文章记进"本次运行别再试"名单,列表保持原文。
//  重启 app 或重进列表(名单是内存的)会再试。**不弹任何错误** ——
//  标题翻译是锦上添花,不该为它打断阅读;正文翻译那边的错误提示已经够用户定位配置问题了。
//

import Foundation
import Account	// 预翻译要听 .AccountDidDownloadArticles(它自带新文章集合)
import Articles
import os
#if os(iOS)
import UIKit
#endif

extension Notification.Name {
	/// 有新的标题译文入库了(或开关变了)。时间线收到后刷新可见行。
	static let nnwTitleTranslationDidUpdate = Notification.Name("nnwTitleTranslationDidUpdate")
}

@MainActor final class NNWTitleTranslationController {

	static let shared = NNWTitleTranslationController()

	private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "TitleTranslation")

	/// 一批最多多少条。40 条标题连提示词也就一两千 token,单次请求很稳。
	private static let batchLimit = 40
	/// 攒批的时间窗:一屏 cell 的装配在一两帧内到齐,0.4 秒绰绰有余
	private static let coalesceSeconds: UInt64 = 400_000_000

	/// 待翻:文章 ID → 文章(去重靠字典键)
	private var pending: [String: Article] = [:]
	/// 已经发出去在翻的
	private var inFlight: Set<String> = []
	/// 本次运行里翻失败的,别反复撞同一堵墙
	private var failedThisRun: Set<String> = []
	private var drainScheduled = false
	private var draining = false

	private init() {
		#if os(iOS)
		// 回前台时给失败的一个再试的机会 —— 断网多半发生在离开 app 的那段时间
		NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification,
											   object: nil, queue: .main) { _ in
			Task { @MainActor in
				NNWTitleTranslationController.shared.resetFailures()
			}
		}
		#endif

		// [翻译] 预翻译(T34 尾巴,2026-07-30 用户要求):刷新拉回**新文章**时就地入队翻标题,
		// 用户进列表时译文多半已经在缓存里 —— "先原文几秒再变中文"那一下也省掉。
		// 这个通知自带新文章集合,零数据库查询;只挑"开了开关的源"的文章。
		// ⚠️ 单例是懒加载的,这个观察者要在启动刷新前就位 —— AppDelegate 启动时摸一下本单例。
		NotificationCenter.default.addObserver(forName: .AccountDidDownloadArticles,
											   object: nil, queue: .main) { note in
			let newArticles = note.userInfo?[Account.UserInfoKey.newArticles] as? Set<Article>
			Task { @MainActor in
				NNWTitleTranslationController.shared.preTranslate(newArticles)
			}
		}
	}

	/// 一次刷新通知最多预翻多少条。刷新通常只带回几条新文章,远够;
	/// 首次订阅(或重订老源 —— 开关退订后是保留的)会一口气带回全部历史,
	/// 那种场景没必要把从来不会被看到的老标题也翻了 —— 超出的留给滚动时按需翻。
	private static let preTranslateCapPerNotification = 50

	/// 刷新拉回的新文章:属于已开启源、还没有译文的,入队(走同一条攒批管线)。
	/// ⚠️ 和"进列表现翻"相比,预翻会把**从未被滚到的**标题也翻了 —— 这是花钱换体验,
	/// 靠上面的单次上限兜底(独立审查建议 2:别写"成本不变"这种不诚实的话)。
	private func preTranslate(_ newArticles: Set<Article>?) {
		guard let newArticles, !newArticles.isEmpty,
			  NNWTitleTranslationStore.shared.hasAnyEnabled else { return }

		let model = TranslationConfigStore.selectedModel
		var count = 0
		// 新的优先(上限截断时,被留下的应该是最老、最不会被看的)
		let sorted = newArticles.sorted { $0.logicalDatePublished > $1.logicalDatePublished }
		for article in sorted {
			guard count < Self.preTranslateCapPerNotification else { break }
			guard let title = article.title, !title.isEmpty,
				  NNWTitleTranslationStore.shared.isEnabled(accountID: article.accountID,
															feedID: article.feedID),
				  !Self.looksChinese(title),
				  NNWTitleTranslationCache.shared.translation(articleID: article.articleID,
															  title: title,
															  model: model) == nil else {
				continue
			}
			enqueue(article)
			count += 1
		}
		if count > 0 {
			Self.logger.info("[翻译] 预翻译:刷新带来 \(count) 条新标题,已入队")
		}
	}

	/// 清空"本次运行别再试"名单。切源/回前台/改配置时调 ——
	/// 失败多是一时的(断网、限流),换个时机就该重试,不能一错定终身(独立审查必修 1)。
	func resetFailures() {
		failedThisRun.removeAll()
	}

	/// 配置变了(填了 key、换了模型):清失败名单,并通知列表刷新 ——
	/// 可见行会重新装配、重新入队,屏上的标题不用等用户滚动就能翻出来。
	func retryAfterConfigChange() {
		resetFailures()
		NotificationCenter.default.post(name: .nnwTitleTranslationDidUpdate, object: nil)
	}

	// MARK: - 时间线的唯一入口

	/// 给这一行挑该显示的文章:开了标题翻译且有译文 → 换了标题的副本;否则原样。
	/// 顺带把"该翻还没翻"的记进待翻名单。
	func displayArticle(for article: Article) -> Article {

		guard NNWTitleTranslationStore.shared.hasAnyEnabled else { return article }
		guard let title = article.title, !title.isEmpty else { return article }
		guard NNWTitleTranslationStore.shared.isEnabled(accountID: article.accountID,
														feedID: article.feedID) else {
			return article
		}
		// 本来就是中文的标题不翻 —— 中文源被顺手打开开关时,一分钱都不花
		guard !Self.looksChinese(title) else { return article }

		let model = TranslationConfigStore.selectedModel
		if let translated = NNWTitleTranslationCache.shared.translation(articleID: article.articleID,
																		title: title,
																		model: model) {
			return translated == title ? article : article.nnwReplacingTitle(translated)
		}

		enqueue(article)
		return article
	}

	/// **只查缓存,不入队**:有译文(且这个源开了开关)就返回它,否则 nil。
	/// 文章内容页用 —— 那一页不会自动刷新,入了队也白入,还可能造成意外花费。
	func cachedTranslatedTitle(for article: Article) -> String? {
		guard NNWTitleTranslationStore.shared.hasAnyEnabled,
			  let title = article.title, !title.isEmpty,
			  NNWTitleTranslationStore.shared.isEnabled(accountID: article.accountID,
														feedID: article.feedID),
			  !Self.looksChinese(title) else {
			return nil
		}
		guard let translated = NNWTitleTranslationCache.shared.translation(articleID: article.articleID,
																		   title: title,
																		   model: TranslationConfigStore.selectedModel),
			  translated != title else {
			return nil
		}
		return translated
	}

	/// 只用缓存换标题的版本(不入队),给文章内容页的渲染用。
	func cachedDisplayArticle(for article: Article) -> Article {
		guard let translated = cachedTranslatedTitle(for: article) else { return article }
		return article.nnwReplacingTitle(translated)
	}

	// MARK: - 攒批与翻译

	private func enqueue(_ article: Article) {
		let id = article.articleID
		guard pending[id] == nil, !inFlight.contains(id), !failedThisRun.contains(id) else { return }
		// ⚠️ 这里刻意**不查**配置(isFullyConfigured 要同步读一次 Keychain,
		// 而本方法在每行装配的热路径上,滚一屏就是几十次 —— 独立审查建议 3)。
		// 配置检查统一放在 drain() 里,一批只查一次;没配 key 时那边整批标失败,
		// 等 retryAfterConfigChange 再放行。
		pending[id] = article
		scheduleDrain()
	}

	private func scheduleDrain() {
		guard !drainScheduled, !draining else { return }
		drainScheduled = true
		Task { [weak self] in
			try? await Task.sleep(nanoseconds: Self.coalesceSeconds)
			guard let self else { return }
			self.drainScheduled = false
			await self.drain()
		}
	}

	private func drain() async {
		guard !draining else { return }
		draining = true
		defer { draining = false }

		while !pending.isEmpty {
			// 取一批。排序只为了日志和调试稳定,模型不在乎顺序
			let batch = Array(pending.values.prefix(Self.batchLimit))
			let ids = batch.map { $0.articleID }
			for id in ids {
				pending.removeValue(forKey: id)
				inFlight.insert(id)
			}

			guard let config = TranslationConfigStore.config else {
				// 配置中途没了(比如刚删掉 key):这批标记失败,剩下的也不用试了
				failedThisRun.formUnion(ids)
				inFlight.subtract(ids)
				failedThisRun.formUnion(pending.keys)
				pending.removeAll()
				break
			}
			let model = TranslationConfigStore.selectedModel
			let titles = batch.map { $0.title ?? "" }

			do {
				let translated = try await NNWTitleBatchTranslator.translate(titles, config: config, model: model)
				for (article, chinese) in zip(batch, translated) {
					// 空译文不入库(模型偶尔漏答)—— 视为没翻过,下次装配时重试(独立审查建议 6)
					let trimmed = chinese.trimmingCharacters(in: .whitespacesAndNewlines)
					guard !trimmed.isEmpty else { continue }
					NNWTitleTranslationCache.shared.store(trimmed,
														  articleID: article.articleID,
														  title: article.title ?? "",
														  model: model)
				}
				NNWTitleTranslationCache.shared.flush()
				inFlight.subtract(ids)
				Self.logger.info("[翻译] 标题批量翻译成功:\(ids.count) 条(模型 \(model, privacy: .public))")
				NotificationCenter.default.post(name: .nnwTitleTranslationDidUpdate, object: nil)
			} catch {
				// 一批失败,剩下的批也别发了 —— 断网时逐批撞 60 秒超时是连环无效请求
				// (独立审查建议 4)。全部记入失败名单,等切源/回前台/改配置时再放行。
				inFlight.subtract(ids)
				failedThisRun.formUnion(ids)
				failedThisRun.formUnion(pending.keys)
				pending.removeAll()
				Self.logger.error("[翻译] 标题批量翻译失败:\(ids.count) 条 — \(error.localizedDescription, privacy: .public)")
				break
			}
		}
	}

	/// 粗判"已经是中文":CJK 字符占比超过三成就不用翻了。
	/// ⚠️ 日文标题也大量用汉字 —— 但只要出现**假名**就一定不是中文,优先按这个否掉
	/// (「東京五輪開幕」这种纯汉字日文标题仍会漏判,可接受:翻出来也不算错;独立审查建议 5)。
	private static func looksChinese(_ text: String) -> Bool {
		var cjk = 0, total = 0
		for scalar in text.unicodeScalars {
			guard !scalar.properties.isWhitespace else { continue }
			if (0x3040...0x30FF).contains(scalar.value) {	// 平假名 / 片假名 → 是日文
				return false
			}
			total += 1
			if (0x4E00...0x9FFF).contains(scalar.value) {
				cjk += 1
			}
		}
		guard total > 0 else { return false }
		return Double(cjk) / Double(total) > 0.3
	}
}

// MARK: - 换标题的内存副本

private extension Article {

	/// 造一份除标题外逐字段相同的副本。**纯内存操作**:Article 是不可变的数据对象,
	/// 这份副本只喂给"行显示数据"的构造,不进数据库、不进任何上游集合。
	func nnwReplacingTitle(_ newTitle: String) -> Article {
		Article(accountID: accountID,
				articleID: articleID,
				feedID: feedID,
				uniqueID: uniqueID,
				title: newTitle,
				contentHTML: contentHTML,
				contentText: contentText,
				markdown: markdown,
				url: rawLink,
				externalURL: rawExternalLink,
				summary: summary,
				imageURL: rawImageLink,
				datePublished: datePublished,
				dateModified: dateModified,
				authors: authors,
				status: status)
	}
}

// MARK: - 批量翻译请求(一次请求翻一批标题)

/// 和正文翻译(OpenAICompatibleTranslator)同一个端点、同一套请求头、同一个模型,
/// 只是提示词换成"翻标题",输入输出都是 JSON 字符串数组。
/// 不复用那个 struct 是因为它的接口单位是"一个 HTML 片段",硬套反而绕。
enum NNWTitleBatchTranslator {

	private static let requestTimeout: TimeInterval = 60

	private static let systemPrompt = """
	你是 RSS 阅读器的标题翻译引擎。用户消息是一个 JSON 字符串数组,每个元素是一条文章标题。\
	把每条标题翻译成简体中文,要求:像中文媒体的标题一样自然、简洁;\
	人名、公司名、产品名、专有缩写保留原文;已经是中文的原样返回。\
	只输出一个 JSON 字符串数组,元素个数与输入完全一致、顺序一一对应。\
	不要输出解释、编号、代码块标记或任何数组之外的内容。
	"""

	static func translate(_ titles: [String], config: TranslationConfig, model: String) async throws -> [String] {

		guard !titles.isEmpty else { return [] }
		guard let url = config.chatCompletionsURL else {
			throw TranslationError.notConfigured("baseURL 不是合法网址:\(config.baseURL)")
		}

		let inputJSON = String(data: try JSONEncoder().encode(titles), encoding: .utf8) ?? "[]"

		var request = URLRequest(url: url)
		request.httpMethod = "POST"
		request.timeoutInterval = requestTimeout
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
		// OpenRouter 建议带的来源标识(和正文翻译一致)
		request.setValue("https://github.com/Dime2015/NetNewsWire_AITranslation", forHTTPHeaderField: "HTTP-Referer")
		request.setValue("NetNewsWire AI Translation", forHTTPHeaderField: "X-Title")

		let provider: Provider? = config.baseURL.lowercased().contains("openrouter")
			? Provider(sort: "throughput") : nil
		let body = Request(model: model,
						   messages: [Message(role: "system", content: systemPrompt),
									  Message(role: "user", content: inputJSON)],
						   temperature: 0.3,
						   provider: provider)
		request.httpBody = try JSONEncoder().encode(body)

		let data: Data
		let response: URLResponse
		do {
			(data, response) = try await URLSession.shared.data(for: request)
		} catch {
			throw TranslationError.networkFailure(underlying: error)
		}

		if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
			throw TranslationError.serverError(status: http.statusCode,
											   message: OpenAICompatibleTranslator.errorMessage(from: data))
		}

		guard let decoded = try? JSONDecoder().decode(Response.self, from: data),
			  let content = decoded.choices.first?.message.content else {
			throw TranslationError.invalidResponse
		}

		let translated = try parseArray(from: content)
		// 条数对不上 = 模型没守约,整批作废重来(调用方会记失败),绝不错位配对
		guard translated.count == titles.count else {
			throw TranslationError.invalidResponse
		}
		return translated
	}

	/// 从模型输出里抠出 JSON 数组:容忍代码块围栏和数组前后的废话。
	private static func parseArray(from raw: String) throws -> [String] {
		guard let start = raw.firstIndex(of: "["),
			  let end = raw.lastIndex(of: "]"),
			  start < end else {
			throw TranslationError.invalidResponse
		}
		let slice = String(raw[start...end])
		guard let parsed = try? JSONDecoder().decode([String].self, from: Data(slice.utf8)) else {
			throw TranslationError.invalidResponse
		}
		return parsed
	}

	// MARK: 请求/响应的最小结构(与 OpenAI 兼容格式对应)

	private struct Request: Encodable {
		let model: String
		let messages: [Message]
		let temperature: Double
		let provider: Provider?
	}

	private struct Message: Encodable {
		let role: String
		let content: String
	}

	private struct Provider: Encodable {
		let sort: String
	}

	private struct Response: Decodable {
		struct Choice: Decodable {
			struct ChoiceMessage: Decodable {
				let content: String?
			}
			let message: ChoiceMessage
		}
		let choices: [Choice]
	}
}
