//
//  TranslationController.swift
//  NetNewsWire — AI 翻译 fork
//
//  Phase 2:翻译按钮 + 点击后的整套流程编排。
//
//  这个文件不属于上游 NetNewsWire,是本 fork 新增的。
//

// ⚠️ 为什么整个文件包在 #if os(iOS) 里:
// Shared/ 目录会同时被 macOS 版和 iOS 版编译。本文件用到 UIKit,
// 而 macOS 上没有 UIKit —— 不加这个开关,macOS 版会编译失败。
// (CLAUDE.md 第 1 节:本次只做 iOS,但不能因此弄坏 macOS 的编译。)
#if os(iOS)

import UIKit
import os

// MARK: - 翻译按钮

/// 按钮当前该显示成什么样。
enum TranslationButtonState {
	/// 正在显示原文,点一下会翻译(联网请求)。
	case original
	/// 正在显示原文,但本地已有这篇的译文缓存 —— 点一下瞬间显示,零请求。灰底提示。
	case cachedAvailable
	/// 正在翻译中,转圈,不可点(再点一下 = 取消)。
	case working
	/// 正在显示译文,点一下切回原文。
	case translated
	/// 上次翻译失败了(或部分段落失败)。
	case failed
}

/// 工具栏上那个翻译按钮。
///
/// 做法完全照抄项目里现成的"阅读视图"按钮(`iOS/Article/ArticleExtractorButton.swift`),
/// 因为它已经解决了"按钮里怎么放一个转圈动画"这个问题。
final class TranslationButton: UIButton {

	private let activityIndicator: UIActivityIndicatorView = {
		let indicator = UIActivityIndicatorView(style: .medium)
		indicator.hidesWhenStopped = true
		indicator.translatesAutoresizingMaskIntoConstraints = false
		return indicator
	}()

	var displayState: TranslationButtonState = .original {
		didSet {
			guard displayState != oldValue else { return }
			applyDisplayState()
		}
	}

	override init(frame: CGRect) {
		super.init(frame: frame)
		// 44×44 的按钮,圆角一半 = 圆形灰底(仅"有缓存"状态时可见)
		layer.cornerRadius = 22
		clipsToBounds = true
		setUpActivityIndicator()
		applyDisplayState()
	}

	required init?(coder: NSCoder) {
		super.init(coder: coder)
		layer.cornerRadius = 22
		clipsToBounds = true
		setUpActivityIndicator()
		applyDisplayState()
	}

	private func setUpActivityIndicator() {
		addSubview(activityIndicator)
		NSLayoutConstraint.activate([
			activityIndicator.centerXAnchor.constraint(equalTo: centerXAnchor),
			activityIndicator.centerYAnchor.constraint(equalTo: centerYAnchor)
		])
	}

	private func applyDisplayState() {
		// 灰底只属于"有缓存"状态,进入任何其他状态都要先清掉
		backgroundColor = .clear
		switch displayState {
		case .original:
			activityIndicator.stopAnimating()
			isUserInteractionEnabled = true
			setImage(UIImage(systemName: "character.bubble"), for: .normal)
		case .cachedAvailable:
			activityIndicator.stopAnimating()
			isUserInteractionEnabled = true
			setImage(UIImage(systemName: "character.bubble"), for: .normal)
			backgroundColor = .systemGray5
		case .working:
			setImage(nil, for: .normal)
			activityIndicator.startAnimating()
			isUserInteractionEnabled = false
		case .translated:
			activityIndicator.stopAnimating()
			isUserInteractionEnabled = true
			setImage(UIImage(systemName: "character.bubble.fill"), for: .normal)
		case .failed:
			activityIndicator.stopAnimating()
			isUserInteractionEnabled = true
			setImage(UIImage(systemName: "exclamationmark.bubble"), for: .normal)
		}
	}

	// 同 TranslationService.swift 里的说明:故意不用 NSLocalizedString,
	// 避免 Xcode 自动往上游共用的 Shared/Localizable.xcstrings 里塞内容。
	override var accessibilityLabel: String? {
		get {
			switch displayState {
			case .original:
				return "翻译成中文"
			case .cachedAvailable:
				return "已有译文缓存,点击立即显示"
			case .working:
				return "正在翻译"
			case .translated:
				return "显示原文"
			case .failed:
				return "翻译失败,点击重试"
			}
		}
		set { super.accessibilityLabel = newValue }
	}
}

// MARK: - 网页脚本

/// 负责把 `translation.js` 的内容读出来。
///
/// 这个 js 文件放在 `Shared/Translation/` 下,编译时会被自动拷进 app 包
/// (已实测验证,见 NOTES-architecture.md)。
enum TranslationScript {

	static let source: String = {
		guard let url = Bundle.main.url(forResource: "translation", withExtension: "js"),
			  let text = try? String(contentsOf: url, encoding: .utf8) else {
			assertionFailure("translation.js 没有被打进 app 包,翻译功能无法工作")
			return ""
		}
		return text
	}()
}

// MARK: - 流程编排

/// 把"点按钮"到"屏幕上文字变了"这条链路串起来。
///
/// 它不认识具体的界面,只通过一个闭包去拿"当前这篇文章的网页"。
/// 这样将来换界面、加 macOS 版,这个类都不用改。
@MainActor final class TranslationController {

	private let currentWebViewController: @MainActor () -> WebViewController?

	/// 同时最多发几个请求。太多会被服务商限流。
	private static let maxConcurrentRequests = 4

	/// 单组最多重试几次。偶发的限流/超时靠它兜住。
	private static let maxRetries = 1

	// MARK: - 分组参数
	//
	// 为什么按组翻而不是一段一次:一段一次的话,系统提示词和上下文示范
	// 要随每个请求重复一遍,十几段下来的固定开销比正文本身还大;
	// 而且各段互相看不见,术语容易前后不一致。

	/// 先导块的目标字符数。约合英文 100 词,够读半分钟 ——
	/// 它单独先翻,让用户几秒内就有东西可读,不用干等全文。
	private static let leadChunkCharacters = 500

	/// 第 1 组的目标字符数,之后逐组翻倍(2000、4000……)。
	/// 为什么第 1 组要小:读者读完先导块马上就要读它,它必须最快回来。
	/// 之前所有组一样大(可达数千字符),第 1 组和最后一组一样慢,
	/// 读者读完先导块要干等一大块 —— 这就是"第一块显著更耗时"问题的由来。
	private static let firstGroupCharacters = 1000

	/// 单组字符上限。超长文章会自动多分几组,
	/// 避免一次要模型吐太多内容而被截断(截断会直接丢掉半篇文章)。
	private static let maxGroupCharacters = 4000

	/// 正在进行的翻译任务。换文章时要取消它,
	/// 否则还在飞的译文会替换到**下一篇文章**的页面上。
	private var runningTask: Task<Void, Never>?

	private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "Translation")

	/// 每次翻译时现取,这样在设置里换了模型能立刻生效。
	private func makeService() throws -> TranslationService {
		if let problem = TranslationConfigStore.configurationProblem {
			throw TranslationError.notConfigured(problem)
		}
		guard let config = TranslationConfigStore.config else {
			throw TranslationError.notConfigured("配置文件读取失败。")
		}
		return OpenAICompatibleTranslator(config: config, model: TranslationConfigStore.selectedModel)
	}

	let button: TranslationButton = {
		let button = TranslationButton(type: .system)
		button.frame = CGRect(x: 0, y: 0, width: 44.0, height: 44.0)
		return button
	}()

	private(set) var state: TranslationButtonState = .original {
		didSet { button.displayState = state }
	}

	/// 最近一次失败的原因,用人话写的。翻译失败时弹给用户看。
	private(set) var lastErrorMessage: String?

	/// - Parameter currentWebViewController: 怎么拿到"当前正在看的那篇文章的网页"。
	init(currentWebViewController: @escaping @MainActor () -> WebViewController?) {
		self.currentWebViewController = currentWebViewController
	}

	/// 包成工具栏上能放的那种按钮。
	func makeBarButtonItem() -> UIBarButtonItem {
		UIBarButtonItem(customView: button)
	}

	/// 点了按钮。
	func toggle() {

		// 正在翻译时再点一下 = 取消,并回到原文。
		// (以前这里是直接 return,转圈期间点了没反应,用户没法中途停下。)
		if state == .working {
			runningTask?.cancel()
			runningTask = nil
			runningTask = Task {
				if let webViewController = currentWebViewController() {
					_ = try? await webViewController.nnwTranslationRestore()
				}
				state = .original
				refreshCacheHint()
			}
			return
		}

		runningTask?.cancel()
		runningTask = Task { await performToggle() }
	}

	/// 换到另一篇文章时调用,把按钮图标重置成"未翻译"。
	///
	/// 为什么可以直接重置、而不用去问网页:
	/// 换文章一定会导致网页重新加载(要么是新建的 WebViewController,
	/// 要么是同一个控制器调 setArticle 重新渲染),新页面里必然没有译文。
	/// 直接重置是同步的,不会出现"页面已经换了、图标过一会儿才跟上"的闪烁。
	func resetForNewArticle() {
		// 必须取消:否则上一篇文章还在飞的译文,会替换到这一篇的页面上。
		runningTask?.cancel()
		runningTask = nil
		state = .original
		refreshCacheHint()
	}

	/// 查一下当前文章有没有译文缓存,有就把按钮换成"灰底"外观提示用户。
	/// 纯本地检查,不发请求。
	private func refreshCacheHint() {
		guard let article = currentWebViewController()?.article else {
			return
		}
		let articleID = article.accountID + "|" + article.articleID
		let key = TranslationCache.articleKey(articleID: articleID,
											  model: TranslationConfigStore.selectedModel)
		Task { [weak self] in
			guard let self else { return }
			guard await TranslationCache.hasEntry(key: key) else { return }
			// 异步回来后要复核:用户可能已经切走文章、或已经点了翻译
			guard self.state == .original,
				  let current = self.currentWebViewController()?.article,
				  current.accountID + "|" + current.articleID == articleID else {
				return
			}
			self.state = .cachedAvailable
		}
	}

	private func performToggle() async {

		guard let webViewController = currentWebViewController() else {
			return
		}

		// 关键:不相信 Swift 这边记的状态,每次都先问网页当前真实显示的是什么。
		//
		// 为什么要这样:页面可能在我们不知情的情况下被重新渲染(比如切换阅读视图、
		// 改字号、换主题),那时译文已经没了,但 Swift 这边还以为在显示译文。
		// 图标可以短暂不准,但"点下去的行为"必须永远正确。
		let isShowingTranslation = (try? await webViewController.nnwTranslationIsShowingTranslation()) ?? false

		// 已经在看译文 → 切回原文。原文存在网页里,所以是瞬间的。
		if isShowingTranslation {
			let didRestore = (try? await webViewController.nnwTranslationRestore()) ?? false
			state = didRestore ? .original : .failed
			if didRestore {
				refreshCacheHint()	// 刚翻完的文章大概率有缓存了,按钮转为灰底提示
			}
			return
		}

		state = .working

		do {
			let service = try makeService()
			let model = TranslationConfigStore.selectedModel

			// 标题的翻译任务句柄。声明在这里、配合 defer,确保中途取消或出错时
			// 这个游离的小任务一定会被叫停 —— 不会在翻页之后把标题译文安到下一篇文章头上。
			var titleTask: Task<String?, Never>? = nil
			defer { titleTask?.cancel() }

			// 0. 先查本地缓存:同一篇文章 + 同一个模型 + 原文没变 → 秒开,零请求零花费。
			//    键只含 文章+模型(不用读正文就能做按钮的灰底提示);
			//    原文是否变过由条目里存的 bodyHash 校验 —— 文章更新过就当没缓存。
			var cacheKey: String?
			var currentBodyHash: String?
			if let article = webViewController.article {
				let key = TranslationCache.articleKey(articleID: article.accountID + "|" + article.articleID,
													  model: model)
				cacheKey = key
				// 指纹用**纯文字**而不是 HTML:页面脚本会异步改 HTML(图片装饰等),
				// HTML 每次不完全一样,拿它当指纹缓存会"时中时不中"(见 L18)。
				if let fingerprint = try await webViewController.nnwTranslationBodyFingerprint() {
					let bodyHash = TranslationCache.contentHash(fingerprint)
					currentBodyHash = bodyHash
					if let cached = await TranslationCache.lookup(key: key) {
						if cached.bodyHash == bodyHash {
							if let cachedTitle = cached.titleHTML {
								_ = try? await webViewController.nnwTranslationApplyTitle(cachedTitle)
							}
							_ = try await webViewController.nnwTranslationApply(cached.bodyHTML)
							state = .translated
							lastErrorMessage = nil
							Self.logger.debug("[翻译] 命中本地缓存,零请求")
							return
						}
						Self.logger.debug("[翻译] 有缓存条目但内容指纹不匹配,按未缓存处理并重新翻译")
					}
				}
			}

			// 1. 让网页把正文切成若干组(第 1 组最小、越往后越大,理由见参数注释)
			guard let chunksJSON = try await webViewController.nnwTranslationSplitBody(
				leadChars: Self.leadChunkCharacters,
				firstGroupChars: Self.firstGroupCharacters,
				maxGroupChars: Self.maxGroupCharacters) else {
				throw TranslationError.bodyNotFound
			}
			let chunks = try JSONDecoder().decode([TranslationChunk].self,
												  from: Data(chunksJSON.utf8))
			guard !chunks.isEmpty else {
				throw TranslationError.emptyContent
			}

			// 排查性能问题的关键日志:一眼看清每组多大
			let sizeSummary = chunks.map { "组\($0.group)=\($0.html.count)字符" }.joined(separator: " ")
			Self.logger.debug("[翻译] 切分完成:\(sizeSummary, privacy: .public)")

			var context = TranslationContext.initial(
				articleTitle: webViewController.article?.title,
				articleURL: webViewController.article?.preferredLink
			)

			// 2. 标题和先导块**同时**发出。
			//    标题最短、回得最快,最先变成中文 —— 让人立刻感觉到"开始了"。
			//    (之前标题排在所有正文组后面,并发槽一旦占满就轮不到它,
			//     表现为"标题很靠后才被翻译"。)
			if let titleHTML = try await webViewController.nnwTranslationReadTitle(),
			   !titleHTML.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
				let titleContext = context
				titleTask = Task { [weak webViewController] in
					// 失败自动重试一次,和正文组同等待遇
					var translated = try? await service.translate(htmlChunk: titleHTML, context: titleContext)
					if translated == nil, !Task.isCancelled {
						try? await Task.sleep(for: .milliseconds(600))
						translated = try? await service.translate(htmlChunk: titleHTML, context: titleContext)
					}
					guard !Task.isCancelled, let translated, let webViewController else {
						return nil
					}
					_ = try? await webViewController.nnwTranslationApplyTitle(translated)
					return translated
				}
			}

			// 3. 先导块单独先翻。它最先出现在屏幕上,你可以马上开始读;
			//    同时它的译文会作为"示范"传给后面所有组,压住术语漂移(方案 C)。
			let first = chunks[0]
			let leadStartedAt = Date()
			let firstTranslation = try await service.translate(htmlChunk: first.html, context: context)
			Self.logger.debug("[翻译] 先导块完成,耗时 \(String(format: "%.1f", Date().timeIntervalSince(leadStartedAt)), privacy: .public)s")
			try Task.checkCancellation()
			_ = try await webViewController.nnwTranslationApplyGroup(group: first.group,
																	 translatedHTML: firstTranslation)

			// 注意:这里**不**把按钮切成"已完成"。
			// 全文没翻完就显示完成,会让人以为翻译停了 —— 转圈要一直转到真的全部结束。
			context = context.withSample(original: first.html, translation: firstTranslation)

			// 4. 其余组并行翻,同时最多 4 个,谁先回来谁先替换。
			//    组是按"由小到大"切的,所以天然是靠前的组先回来 —— 正合顺序阅读的节奏。
			let work = chunks.dropFirst().map {
				TranslationWorkItem(target: .chunk($0.group), html: $0.html)
			}

			var failureCount = 0
			if !work.isEmpty {
				failureCount = await translateInParallel(work,
														 service: service,
														 context: context,
														 webViewController: webViewController)
			}

			try Task.checkCancellation()

			// 5. 事后自检:哪些组还是英文、或者混进了英文原文?
			//    这一步是**纯本地判断,不发请求、不花钱** —— 数一下中英文字符比例,
			//    再拿原文中段当探针查一下有没有被回显。查出来的重翻一次。
			let recheckFailures = await recheckAndRetranslate(service: service,
															 context: context,
															 webViewController: webViewController)

			// 6. 等标题翻完(它是最早发出的,通常此刻早已完成)
			var translatedTitle: String?
			if let titleTask {
				translatedTitle = await titleTask.value
			}

			try Task.checkCancellation()

			// 7. 真的全部结束了,现在才点亮按钮
			let totalFailures = failureCount + recheckFailures

			if totalFailures > 0 {
				state = .failed
				lastErrorMessage = "有 \(totalFailures) 组内容没能翻译成功,保持了原文。点一下回到原文,再点一次可以重新翻译整篇。"
				Self.logger.error("[翻译] 完成,但有 \(totalFailures) 组失败")
			} else {
				state = .translated
				lastErrorMessage = nil

				// 8. 全部成功才写缓存 —— 下次再看这篇文章就是秒开、零花费。
				//    部分失败的结果不缓存,免得把"带着英文残段"的版本固化下来。
				if let cacheKey, let currentBodyHash,
				   let translatedBody = try? await webViewController.nnwTranslationReadBody() {
					TranslationCache.store(key: cacheKey,
										   CachedTranslation(bodyHash: currentBodyHash,
															 titleHTML: translatedTitle,
															 bodyHTML: translatedBody))
				}
			}

		} catch is CancellationError {
			// 用户翻页了,正常情况,不算失败
			Self.logger.debug("[翻译] 已取消")
		} catch {
			Self.logger.error("[翻译] 失败:\(error.localizedDescription, privacy: .public)")
			lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
			state = .failed
		}
	}

	/// 全部翻完后再检查一遍,把没翻好的组重翻。返回重翻后仍然失败的组数。
	///
	/// 检查两种毛病(都由 JS 在本地判断,不发请求):
	///   ① 这一组还是英文 —— 请求失败过,或者模型把原文原样还回来了
	///   ② 这一组混进了英文原文 —— 模型做了中英对照
	///
	/// 只查一轮。查两轮的收益很小,却可能在模型持续不听话时反复烧钱。
	private func recheckAndRetranslate(service: TranslationService,
									   context: TranslationContext,
									   webViewController: WebViewController) async -> Int {

		guard let json = try? await webViewController.nnwTranslationFindGroupsNeedingRetranslation(),
			  let bad = try? JSONDecoder().decode([TranslationChunk].self, from: Data(json.utf8)),
			  !bad.isEmpty else {
			return 0
		}

		Self.logger.debug("[翻译] 自检发现 \(bad.count) 组需要重翻")

		let work = bad.map { TranslationWorkItem(target: .chunk($0.group), html: $0.html) }

		return await translateInParallel(work,
										 service: service,
										 context: context,
										 webViewController: webViewController)
	}

	/// 并行翻译,返回最终仍然失败的段数。
	///
	/// 用滑动窗口控制并发:同时最多 `maxConcurrentRequests` 个请求在飞,
	/// 有一个回来就补一个,而不是一口气把几十个请求全丢出去(那样会被服务商限流)。
	///
	/// 失败的段会**自动重试一次**。之前没有重试,导致偶发的限流/超时
	/// 直接表现为"某几段没翻",而且不告诉用户。
	private func translateInParallel(_ items: [TranslationWorkItem],
									 service: TranslationService,
									 context: TranslationContext,
									 webViewController: WebViewController) async -> Int {

		var failureCount = 0
		var pending = items
		var nextIndex = 0

		await withTaskGroup(of: (TranslationWorkItem, String?, TimeInterval).self) { group in

			func addNext() {
				guard nextIndex < pending.count else { return }
				let item = pending[nextIndex]
				nextIndex += 1
				group.addTask {
					// 重试前先等一下。被限流时立刻重试多半还是被拒。
					if item.attempt > 0 {
						try? await Task.sleep(for: .milliseconds(600))
					}
					let startedAt = Date()
					let translated = try? await service.translate(htmlChunk: item.html, context: context)
					return (item, translated, Date().timeIntervalSince(startedAt))
				}
			}

			for _ in 0..<min(Self.maxConcurrentRequests, pending.count) {
				addNext()
			}

			while let (item, translated, elapsed) = await group.next() {

				if Task.isCancelled {
					group.cancelAll()
					break
				}

				// ⚠️ 替换失败要和请求失败同等对待。
				// 以前这里写的是 `_ = try? ...`,替换失败被静默吞掉 ——
				// 那一组会一直显示原文,拖到最后的自检阶段才被救回来,
				// 表象就是"某一组总是最后才翻好"。
				var applied = false
				if let translated {
					switch item.target {
					case .chunk(let group):
						applied = (try? await webViewController.nnwTranslationApplyGroup(group: group,
																						 translatedHTML: translated)) ?? false
					case .title:
						applied = (try? await webViewController.nnwTranslationApplyTitle(translated)) ?? false
					}
				}

				let outcome = translated == nil ? "请求失败" : (applied ? "完成" : "替换失败")
				Self.logger.debug("[翻译] \(item.debugLabel, privacy: .public) 第\(item.attempt + 1)次:\(outcome, privacy: .public),耗时 \(String(format: "%.1f", elapsed), privacy: .public)s,原文 \(item.html.count) 字符")

				if !applied {
					if item.attempt < Self.maxRetries {
						// 排到队尾再试一次
						pending.append(item.retrying())
					} else {
						// 重试后仍然失败,这一组保持原文。不影响其他组。
						failureCount += 1
					}
				}

				addNext()
			}
		}

		return failureCount
	}
}

/// JS 切好的一组。对应 translation.js 里 splitBody() 返回的结构。
private struct TranslationChunk: Decodable, Sendable {
	let group: Int
	let html: String
}

/// 一件待翻译的活:正文的某一块,或者标题。
private struct TranslationWorkItem: Sendable {

	enum Target: Sendable {
		case chunk(Int)
		case title
	}

	let target: Target
	let html: String
	var attempt: Int = 0

	var debugLabel: String {
		switch target {
		case .chunk(let group):
			return "组\(group)"
		case .title:
			return "标题"
		}
	}

	func retrying() -> TranslationWorkItem {
		TranslationWorkItem(target: target, html: html, attempt: attempt + 1)
	}
}

#endif
