//
//  PodcastEpisodeLocator.swift
//  NetNewsWire
//
//  [播客] 本 fork 新增,上游没有这个文件。
//

import Foundation
import Articles
import RSParser
import os

/// 一集播客里我们关心的东西
struct PodcastEpisode {
	/// 音频地址(来自 feed 的 enclosure)
	let audioURL: String
	/// 时长,秒。feed 里不一定有
	let durationInSeconds: Int?
}

/// 找出「当前这篇文章」对应的音频地址。
///
/// ## 为什么要绕这么一圈
///
/// 音频地址在 RSS 的 `<enclosure>` 里。上游的解析器**确实解析了它**
/// (`RSSParser.swift` 里 `article.attachments.insert(attachment)`),
/// 但是:
///   - `Article` 数据模型**没有 attachments 字段**
///   - `ArticlesDatabase` 的建库脚本里还有一句 `DROP TABLE if EXISTS attachments`
///
/// 也就是说,音频地址在**入库之前就被丢掉了**,数据库里根本没有。
///
/// 想在数据层加回来 = 改 `Modules/Articles` 和 `Modules/ArticlesDatabase`,
/// 那是 CLAUDE.md 的 **C 级禁区**,而且是 merge 冲突的高发区。
///
/// 所以改成:**要用的时候重新拉一次那个 feed**,用上游自己的解析器解出来,
/// 按 guid 找到这一集。数据层一行不改。
///
/// ## 代价与控制
///
/// 拉一次 feed 是有成本的(播客 feed 可能几百 KB)。所以:
///   - **按 feed 缓存**,一个 feed 一次会话只拉一次
///   - **连「这个源根本不是播客」也缓存**(负缓存)。否则每打开一篇普通文章
///     都会去拉一次它的 feed —— 那是灾难。这是 L28 里踩过的同一个坑。
@MainActor final class PodcastEpisodeLocator {

	static let shared = PodcastEpisodeLocator()

	// nonisolated:下面的 download 是脱离主线程跑的,也要能写日志
	private nonisolated static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "Podcast")

	/// feed 地址 → (这个 feed 里所有集的 guid → 音频)。
	/// 值为空字典表示「查过了,这个源没有音频」,即负缓存。
	private var cache = [String: [String: PodcastEpisode]]()

	/// 正在拉取中的 feed,避免同一个 feed 被并发拉好几次
	private var inFlight = [String: Task<[String: PodcastEpisode], Never>]()

	private init() {}

	/// 找出这篇文章对应的音频。不是播客就返回 nil。
	func episode(for article: Article) async -> PodcastEpisode? {

		let feedURLString = article.feedID
		guard !feedURLString.isEmpty, URL(string: feedURLString) != nil else {
			return nil
		}

		let episodes = await episodes(inFeed: feedURLString)
		return episodes[article.uniqueID]
	}

	// MARK: - 内部

	private func episodes(inFeed feedURLString: String) async -> [String: PodcastEpisode] {

		if let cached = cache[feedURLString] {
			return cached
		}
		if let running = inFlight[feedURLString] {
			return await running.value
		}

		let task = Task<[String: PodcastEpisode], Never> {
			await Self.download(feedURLString: feedURLString)
		}
		inFlight[feedURLString] = task

		let result = await task.value
		inFlight[feedURLString] = nil
		cache[feedURLString] = result // 空字典也要存 —— 这就是负缓存

		if result.isEmpty {
			Self.logger.info("[播客] \(feedURLString) 里没有音频,记下来不再重复拉取")
		} else {
			Self.logger.info("[播客] \(feedURLString) 解析出 \(result.count) 集音频")
		}
		return result
	}

	private nonisolated static func download(feedURLString: String) async -> [String: PodcastEpisode] {

		guard let url = URL(string: feedURLString) else {
			return [:]
		}

		var request = URLRequest(url: url)
		request.timeoutInterval = 30
		// 和 app 抓 feed 时用同一个 User-Agent —— 否则会出现
		// 「app 刷新拿得到、我们拿不到」这种极难查的不一致(见 L33)
		if let userAgent = Bundle.main.object(forInfoDictionaryKey: "UserAgent") as? String {
			request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
		}

		let data: Data
		do {
			(data, _) = try await URLSession.shared.data(for: request)
		} catch {
			logger.warning("[播客] 拉取 feed 失败:\(feedURLString) — \(error.localizedDescription)")
			return [:]
		}

		// 用上游自己的解析器,不自己写 XML 解析
		let parserData = ParserData(url: feedURLString, data: data)
		guard let parsedFeed = try? await FeedParser.parse(parserData) else {
			return [:]
		}

		var found = [String: PodcastEpisode]()
		for item in parsedFeed.items {
			guard let attachment = bestAudioAttachment(in: item.attachments) else {
				continue
			}
			found[item.uniqueID] = PodcastEpisode(
				audioURL: attachment.url,
				durationInSeconds: attachment.durationInSeconds)
		}
		return found
	}

	/// 一集可能挂好几个附件(音频、章节文件、封面图),挑出真正能播的那个。
	private nonisolated static func bestAudioAttachment(in attachments: Set<ParsedAttachment>?) -> ParsedAttachment? {

		guard let attachments, !attachments.isEmpty else {
			return nil
		}

		// 优先信 MIME 类型
		if let byMimeType = attachments.first(where: { ($0.mimeType ?? "").lowercased().hasPrefix("audio/") }) {
			return byMimeType
		}

		// 没写 MIME 类型就看扩展名。有些 feed 的 enclosure 是这样的。
		let audioExtensions = [".mp3", ".m4a", ".aac", ".ogg", ".opus", ".wav", ".flac"]
		return attachments.first { attachment in
			let lower = attachment.url.lowercased()
			return audioExtensions.contains { lower.contains($0) }
		}
	}
}
