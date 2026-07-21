//
//  YouTubeDescriptionLoader.swift
//  NetNewsWire
//
//  [YouTube] 本 fork 新增,上游没有这个文件。
//

import Foundation
import Articles
import os

/// 取出 YouTube 视频的简介。
///
/// ## 为什么要自己解析
///
/// YouTube 的 RSS 里**是有简介的**,在 `<media:group><media:description>` 里
/// (实测一条 684 字符)。但上游的 `AtomParser` 里写着:
///
///     if namespace.prefix != nil {
///         return // Prefixed article elements are ... otherwise ignored.
///     }
///
/// **所有带前缀的元素(`media:` `yt:` 等)都被明确忽略了。**
/// 所以走 `FeedParser` 永远拿不到它 —— 这和播客那边「解析了但没入库」不同,
/// 这里是**压根没解析**。
///
/// ## 用 XMLParser,不用正则
///
/// 用 Foundation 自带的 `XMLParser`(SAX 式的真解析器)。
/// 本项目一贯不用正则去匹配标记语言 —— 正则碰到嵌套、转义、CDATA 就会出错,
/// 而且错得很隐蔽(见 CLAUDE.md 第 5 节)。
///
/// ## 成本控制
///
/// 和播客那边最大的区别:**YouTube 的 feed 地址一眼就能认出来**
/// (`youtube.com/feeds/videos.xml`),所以非 YouTube 的源**一次请求都不会发**。
/// 播客那边做不到这一点,只能靠负缓存兜底。
@MainActor final class YouTubeDescriptionLoader {

	static let shared = YouTubeDescriptionLoader()

	private nonisolated static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "YouTube")

	/// feed 地址 → (文章 uniqueID → 简介)
	private var cache = [String: [String: String]]()
	private var inFlight = [String: Task<[String: String], Never>]()

	private init() {}

	/// 这篇文章的视频简介。不是 YouTube 就直接返回 nil,**不发任何请求**。
	func description(for article: Article) async -> String? {

		let feedURLString = article.feedID
		guard Self.isYouTubeFeed(feedURLString) else {
			return nil
		}

		if let cached = cache[feedURLString] {
			return cached[article.uniqueID]
		}
		if let running = inFlight[feedURLString] {
			return await running.value[article.uniqueID]
		}

		let task = Task<[String: String], Never> {
			await Self.download(feedURLString: feedURLString)
		}
		inFlight[feedURLString] = task

		let result = await task.value
		inFlight[feedURLString] = nil
		cache[feedURLString] = result

		Self.logger.info("[YouTube] \(feedURLString) 解析出 \(result.count) 条视频简介")
		return result[article.uniqueID]
	}

	/// 认不认这个 feed。判断放宽一点,YouTube 有好几种 feed 地址写法。
	private nonisolated static func isYouTubeFeed(_ urlString: String) -> Bool {
		let lower = urlString.lowercased()
		return lower.contains("youtube.com/feeds/videos.xml")
			|| lower.contains("youtube.com/feeds/api/videos")
	}

	private nonisolated static func download(feedURLString: String) async -> [String: String] {

		guard let url = URL(string: feedURLString) else {
			return [:]
		}

		var request = URLRequest(url: url)
		request.timeoutInterval = 25
		// 和 app 抓 feed 用同一个 UA(见 L33)
		if let userAgent = Bundle.main.object(forInfoDictionaryKey: "UserAgent") as? String {
			request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
		}

		guard let (data, _) = try? await URLSession.shared.data(for: request) else {
			logger.warning("[YouTube] 拉取 feed 失败:\(feedURLString)")
			return [:]
		}

		let collector = DescriptionCollector()
		let parser = XMLParser(data: data)
		parser.delegate = collector
		parser.parse()
		return collector.descriptionsByEntryID
	}
}

/// 从 YouTube 的 Atom feed 里挑出「每条 entry 的 id → media:description」。
///
/// 只关心三个标签,别的一概跳过:
///   `<entry>`               一条视频的开始/结束
///   `<id>`                  形如 yt:video:9w4sCnVSRJg,**正好等于 Article.uniqueID**
///   `<media:description>`   简介正文
///
/// ⚠️ `<id>` 在 feed 顶层也有一个(整个频道的 id),所以必须用 insideEntry
/// 把它挡掉,否则会把频道 id 当成某条视频的 id。
private final class DescriptionCollector: NSObject, XMLParserDelegate {

	var descriptionsByEntryID = [String: String]()

	private var insideEntry = false
	private var currentEntryID: String?
	private var currentDescription: String?
	/// 当前正在收集哪个标签的文字。nil 表示不收集。
	private var collecting: String?
	private var buffer = ""

	func parser(_ parser: XMLParser,
				didStartElement elementName: String,
				namespaceURI: String?,
				qualifiedName qName: String?,
				attributes attributeDict: [String: String]) {

		switch elementName {
		case "entry":
			insideEntry = true
			currentEntryID = nil
			currentDescription = nil
		case "id" where insideEntry:
			collecting = "id"
			buffer = ""
		case "media:description" where insideEntry:
			collecting = "media:description"
			buffer = ""
		default:
			break
		}
	}

	func parser(_ parser: XMLParser, foundCharacters string: String) {
		if collecting != nil {
			buffer += string
		}
	}

	/// 简介里常有网址和特殊字符,YouTube 会用 CDATA 包起来。
	/// XMLParser 走的是这个回调,不处理的话简介会缺一块。
	func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
		if collecting != nil, let text = String(data: CDATABlock, encoding: .utf8) {
			buffer += text
		}
	}

	func parser(_ parser: XMLParser,
				didEndElement elementName: String,
				namespaceURI: String?,
				qualifiedName qName: String?) {

		switch elementName {
		case "id" where collecting == "id":
			currentEntryID = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
			collecting = nil
		case "media:description" where collecting == "media:description":
			currentDescription = buffer
			collecting = nil
		case "entry":
			if let id = currentEntryID,
			   let description = currentDescription,
			   !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
				descriptionsByEntryID[id] = description
			}
			insideEntry = false
			currentEntryID = nil
			currentDescription = nil
		default:
			break
		}
		buffer = ""
	}
}
