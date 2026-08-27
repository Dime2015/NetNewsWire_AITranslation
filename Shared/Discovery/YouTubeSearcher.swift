//
//  YouTubeSearcher.swift
//  NetNewsWire
//
//  [发现] 本 fork 新增,上游没有这个文件。
//

import Foundation
import os

/// 用 YouTube 官方 Data API v3 按关键词搜频道。
///
/// ## 为什么 `YouTubeFeedResolver`(抓频道页那个)解决不了这件事
///
/// 那个类只会做一件事:把一个**已经知道的**频道地址/handle 换成 channel id。
/// 关键词搜索(“输入一个名字,列出候选频道”)YouTube 没有免费的非官方入口,
/// 只有官方 Data API 的 `search.list` 支持——需要一个免费申请的 API Key
/// (Google Cloud Console → 启用 "YouTube Data API v3" → 创建 API Key,
/// 不需要绑定信用卡)。
///
/// ⚠️ 免费额度很小:`search.list` 每次调用扣 100 个配额单位,
/// 默认每天总配额 10000,也就是**约 100 次关键词搜索/天**。
/// 用完了当天会 403,次日太平洋时间午夜重置。
enum YouTubeSearcher {

	private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "FeedDiscovery")

	static func search(_ term: String) async throws -> [FeedSearchResult] {

		let keyword = term.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !keyword.isEmpty else {
			throw FeedSearchError.emptyInput
		}

		guard let apiKey = FeedDiscoveryKeychain.youTubeAPIKey, !apiKey.isEmpty else {
			throw FeedSearchError.missingCredentials(service: "YouTube")
		}

		var components = URLComponents(string: "https://www.googleapis.com/youtube/v3/search")!
		components.queryItems = [
			URLQueryItem(name: "part", value: "snippet"),
			URLQueryItem(name: "type", value: "channel"),
			URLQueryItem(name: "q", value: keyword),
			URLQueryItem(name: "maxResults", value: "20"),
			URLQueryItem(name: "key", value: apiKey)
		]
		guard let url = components.url else {
			throw FeedSearchError.emptyInput
		}

		var request = URLRequest(url: url)
		request.timeoutInterval = 20

		let data: Data
		let response: URLResponse
		do {
			(data, response) = try await URLSession.shared.data(for: request)
		} catch {
			throw FeedSearchError.network(error)
		}

		if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
			logger.warning("[发现] YouTube 搜索:返回状态码 \(http.statusCode)")
			throw FeedSearchError.youtube(statusCode: http.statusCode)
		}

		return parse(data)
	}

	/// 防御式解析:Google 哪天多加/改名一个字段都不该让我们崩。
	private static func parse(_ data: Data) -> [FeedSearchResult] {

		guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
			  let items = root["items"] as? [[String: Any]] else {
			logger.warning("[发现] YouTube 搜索:返回的不是预期的 JSON 结构")
			return []
		}

		var found = [FeedSearchResult]()
		var seenChannelIDs = Set<String>()

		for item in items {

			guard let idDict = item["id"] as? [String: Any],
				  let channelID = idDict["channelId"] as? String, !channelID.isEmpty,
				  let snippet = item["snippet"] as? [String: Any] else {
				continue
			}
			guard !seenChannelIDs.contains(channelID) else { continue }
			seenChannelIDs.insert(channelID)

			let title = (snippet["title"] as? String) ?? "YouTube 频道 \(channelID)"

			var description = (snippet["description"] as? String)?
				.trimmingCharacters(in: .whitespacesAndNewlines)
			if description?.isEmpty == true { description = nil }

			// 头像:搜索结果本来就带,不需要为了取图标再单独抓一次频道页
			// (和 YouTubeFeedResolver 抓页面取头像是两条不同的路,这里更省)。
			let thumbnails = snippet["thumbnails"] as? [String: Any]
			let iconURL = ((thumbnails?["default"] as? [String: Any])?["url"] as? String)
				?? ((thumbnails?["medium"] as? [String: Any])?["url"] as? String)

			found.append(FeedSearchResult(
				kind: .youtube,
				title: title,
				subtitle: description,
				feedURL: "https://www.youtube.com/feeds/videos.xml?channel_id=\(channelID)",
				homePageURL: "https://www.youtube.com/channel/\(channelID)",
				iconURL: iconURL))
		}

		logger.info("[发现] YouTube 搜索:返回 \(items.count) 条,可订阅 \(found.count) 条")
		return found
	}
}
