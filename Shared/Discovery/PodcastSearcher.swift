//
//  PodcastSearcher.swift
//  NetNewsWire
//
//  [发现] 本 fork 新增,上游没有这个文件。
//

import Foundation
import os

/// 用苹果官方的 iTunes Search API 搜播客。
///
/// 为什么用它:**播客本质就是 RSS**,Apple Podcasts 自己也只是个 RSS 阅读器。
/// 这个接口是苹果公开的、不要 key、不要注册,而且**直接返回原始 feed 地址**——
/// 搜到就能订,中间不需要任何猜测或抓页面。
///
/// 实测(2026-07-21):搜 "stratechery" 返回 Sharp Tech / Exponent / Sharp China,
/// 每条都带 feedUrl 和 collectionId。
enum PodcastSearcher {

	private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "FeedDiscovery")

	static func search(_ term: String) async throws -> [FeedSearchResult] {

		let keyword = term.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !keyword.isEmpty else {
			throw FeedSearchError.emptyInput
		}

		var components = URLComponents(string: "https://itunes.apple.com/search")!
		components.queryItems = [
			URLQueryItem(name: "term", value: keyword),
			URLQueryItem(name: "entity", value: "podcast"),
			URLQueryItem(name: "limit", value: "25")
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
			throw FeedSearchError.badResponse(http.statusCode)
		}

		return parse(data)
	}

	/// 防御式解析:苹果哪天多加/改名一个字段都不该让我们崩。
	/// 缺 feedUrl 的条目直接跳过 —— 没有地址的结果对用户毫无意义,
	/// 与其显示一条点了没反应的,不如不显示。
	private static func parse(_ data: Data) -> [FeedSearchResult] {

		guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
			  let results = root["results"] as? [[String: Any]] else {
			logger.warning("[发现] 播客搜索:返回的不是预期的 JSON 结构")
			return []
		}

		var found = [FeedSearchResult]()
		var seenURLs = Set<String>()

		for item in results {

			guard let feedURL = item["feedUrl"] as? String, !feedURL.isEmpty else {
				continue
			}
			// 同一个 feed 只留一条
			guard !seenURLs.contains(feedURL) else {
				continue
			}
			seenURLs.insert(feedURL)

			let title = (item["collectionName"] as? String)
				?? (item["trackName"] as? String)
				?? feedURL

			// 副标题:作者 + 集数,能给多少给多少,一个都没有就留空
			var subtitleParts = [String]()
			if let artist = item["artistName"] as? String, !artist.isEmpty {
				subtitleParts.append(artist)
			}
			if let count = item["trackCount"] as? Int, count > 0 {
				subtitleParts.append("\(count) 期")
			}

			var collectionID: String?
			if let id = item["collectionId"] as? Int {
				collectionID = String(id)
			} else if let id = item["collectionId"] as? String {
				collectionID = id
			}

			// 封面图。搜索返回里本来就带,**不需要为它多发一次请求**。
			// 优先 100 尺寸:列表里显示成 40pt 见方,在 3x 屏上正好够清晰,
			// 用 600 那档只是白白多下载。
			let artwork = (item["artworkUrl100"] as? String)
				?? (item["artworkUrl60"] as? String)
				?? (item["artworkUrl30"] as? String)

			found.append(FeedSearchResult(
				kind: .podcast,
				title: title,
				subtitle: subtitleParts.isEmpty ? nil : subtitleParts.joined(separator: " · "),
				feedURL: feedURL,
				homePageURL: item["collectionViewUrl"] as? String,
				appleCollectionID: collectionID,
				iconURL: artwork))
		}

		logger.info("[发现] 播客搜索:返回 \(results.count) 条,可订阅 \(found.count) 条")
		return found
	}
}
