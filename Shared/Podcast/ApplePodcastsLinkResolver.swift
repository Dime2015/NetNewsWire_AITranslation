//
//  ApplePodcastsLinkResolver.swift
//  NetNewsWire
//
//  [播客] 本 fork 新增,上游没有这个文件。
//

import Foundation
import Articles
import os

/// 算出「在『播客』app 里打开这一期」的链接。
///
/// ## 思路
///
/// 苹果的 iTunes 接口能按节目 ID 列出所有单集,而且**每一集都带 `episodeGuid`** ——
/// 那正是 RSS 里的 guid,也就是 `Article.uniqueID`。所以能精确对到具体某一期,
/// 而不是只能跳到节目主页。实测(2026-07-21):
///
///     lookup?id=<节目ID>&entity=podcastEpisode
///       → episodeGuid = https://sharptech.fm/member/episode/...   ← 和 guid 对得上
///         trackId     = 1000777202240                            ← 拼深链要它
///
/// ## 为什么音频不从这里拿
///
/// 同一份返回里还有 `episodeUrl`,看着像是音频地址,**但它是试听片段**
/// (实测返回的是 `..._preview.mp3?access_token=…`)。付费播客的完整音频
/// 只存在于用户自己订阅的那个 feed 里。
/// 所以分工是:**音频走 feed(见 PodcastEpisodeLocator),跳转走这里。**
///
/// ## 失败就退回节目主页
///
/// 整条链路(搜节目 → 匹配 feed 地址 → 列单集 → 匹配 guid)每一步都可能落空:
/// 私人 feed 根本不在苹果目录里、节目改过名、单集太老不在最近 200 集里。
/// 所以每一步失败都**降级**而不是报错:能跳到这一集最好,不能就跳节目主页,
/// 再不能才说找不到。
///
/// ## 实现说明
///
/// 注意这里是 `@MainActor final class` 而不是 `enum` ——
/// 因为要存缓存(可变状态)。Swift 6 的并发检查不允许裸的可变全局变量,
/// 所以按本项目已有的做法(PodcastEpisodeLocator)收进一个单例里。
@MainActor final class ApplePodcastsLinkResolver {

	static let shared = ApplePodcastsLinkResolver()

	private nonisolated static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "Podcast")

	/// 一个节目在苹果目录里的信息,查到后缓存,避免重复请求
	private struct Show {
		let collectionID: String
		/// guid → 单集的 trackId
		let episodeIDsByGUID: [String: String]
	}

	/// feed 地址 → 结果。值为 nil 表示「查过了,苹果目录里没有」,即负缓存。
	private var showCache = [String: Show?]()

	private init() {}

	/// 返回可以直接 open 的链接。找不到就返回 nil。
	func link(for article: Article, feedTitle: String?) async -> URL? {

		let feedURLString = article.feedID

		if let cached = showCache[feedURLString] {
			guard let cached else { return nil } // 查过,没找到
			return Self.url(from: cached, guid: article.uniqueID)
		}

		guard let title = feedTitle, !title.isEmpty else {
			return nil
		}

		guard let show = await Self.lookUpShow(feedURLString: feedURLString, title: title) else {
			showCache[feedURLString] = Show?.none
			return nil
		}
		showCache[feedURLString] = show
		return Self.url(from: show, guid: article.uniqueID)
	}

	// MARK: - 拼链接

	private nonisolated static func url(from show: Show, guid: String) -> URL? {
		// 能对上具体这一集就带上 ?i=,「播客」app 会直接打开这一期
		if let episodeID = show.episodeIDsByGUID[guid] {
			return URL(string: "https://podcasts.apple.com/podcast/id\(show.collectionID)?i=\(episodeID)")
		}
		// 对不上就退回节目主页
		return URL(string: "https://podcasts.apple.com/podcast/id\(show.collectionID)")
	}

	// MARK: - 查苹果目录

	private nonisolated static func lookUpShow(feedURLString: String, title: String) async -> Show? {

		guard let collectionID = await findCollectionID(feedURLString: feedURLString, title: title) else {
			return nil
		}
		let episodes = await findEpisodes(collectionID: collectionID)
		return Show(collectionID: collectionID, episodeIDsByGUID: episodes)
	}

	/// 按节目名搜,**用 feed 地址来确认是不是同一个节目**。
	/// 光比名字不够 —— 同名节目很多,比 feed 地址才是准的。
	private nonisolated static func findCollectionID(feedURLString: String, title: String) async -> String? {

		var components = URLComponents(string: "https://itunes.apple.com/search")!
		components.queryItems = [
			URLQueryItem(name: "term", value: title),
			URLQueryItem(name: "entity", value: "podcast"),
			URLQueryItem(name: "limit", value: "25")
		]
		guard let url = components.url,
			  let root = await fetchJSON(url),
			  let results = root["results"] as? [[String: Any]] else {
			return nil
		}

		let target = normalized(feedURLString)
		for item in results {
			guard let feedURL = item["feedUrl"] as? String, normalized(feedURL) == target else {
				continue
			}
			if let id = item["collectionId"] as? Int { return String(id) }
			if let id = item["collectionId"] as? String { return id }
		}

		logger.info("[播客] 苹果目录里没有匹配 feed 地址的节目:\(feedURLString)")
		return nil
	}

	private nonisolated static func findEpisodes(collectionID: String) async -> [String: String] {

		var components = URLComponents(string: "https://itunes.apple.com/lookup")!
		components.queryItems = [
			URLQueryItem(name: "id", value: collectionID),
			URLQueryItem(name: "entity", value: "podcastEpisode"),
			URLQueryItem(name: "limit", value: "200")
		]
		guard let url = components.url,
			  let root = await fetchJSON(url),
			  let results = root["results"] as? [[String: Any]] else {
			return [:]
		}

		var map = [String: String]()
		for item in results {
			guard let guid = item["episodeGuid"] as? String, !guid.isEmpty else {
				continue // 第一条是节目本身,没有 episodeGuid
			}
			if let trackID = item["trackId"] as? Int {
				map[guid] = String(trackID)
			} else if let trackID = item["trackId"] as? String {
				map[guid] = trackID
			}
		}
		return map
	}

	private nonisolated static func fetchJSON(_ url: URL) async -> [String: Any]? {
		var request = URLRequest(url: url)
		request.timeoutInterval = 20
		guard let (data, _) = try? await URLSession.shared.data(for: request) else {
			return nil
		}
		return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
	}

	/// 比对 feed 地址时忽略协议头和结尾斜杠 —— 同一个 feed 常有 http/https 两种写法
	private nonisolated static func normalized(_ urlString: String) -> String {
		var text = urlString.lowercased()
		for prefix in ["https://", "http://"] where text.hasPrefix(prefix) {
			text = String(text.dropFirst(prefix.count))
		}
		while text.hasSuffix("/") {
			text.removeLast()
		}
		return text
	}

}
