//
//  WebsiteSearcher.swift
//  NetNewsWire
//
//  [发现] 本 fork 新增,上游没有这个文件。
//

import Foundation
import os

/// 用关键词搜普通网站/博客的 RSS 源。
///
/// ## 为什么是 Feedly,以及这条路的风险
///
/// 业界目前**没有**一个官方、免费、公开的"RSS 全网搜索"接口——Google 很早就砍掉了
/// Feed 相关的搜索产品(Google Reader 目录、FeedBurner 目录都已停运)。CLAUDE.md
/// 第 1 节 Phase C 当初就是因为这个原因把"关键词搜网站"标成"暂不列入计划"。
///
/// 唯一能用的路子是 Feedly 的 `cloud.feedly.com/v3/search/feeds`——**未公开、不用
/// 认证的接口**,它是 Feedly 自家客户端用来做订阅搜索的那个后端。
/// 2026-08-11 实测(curl):搜 "stratechery"、"xkcd" 都稳定返回 200,带标题、简介、
/// 图标、订阅数,`feedId` 就是可以直接订阅的 feed 地址(前面带 `feed/` 前缀要去掉)。
///
/// ⚠️ **这条接口没有 SLA,随时可能被限流或者下线**——它不是 Feedly 对外承诺的公开 API。
/// 所以这一类的失败要**优雅降级**(见 `FeedDiscoveryViewController.unifiedSearch`):
/// 这一类搜不到,不影响播客/Reddit/YouTube 三类照常出结果,只在这一组显示提示。
/// 如果哪天这条接口彻底不能用了,受影响的只是"全部 tab 关键词搜网站"这一项;
/// "粘网址自动发现"(`WebsiteFeedResolver`)完全不依赖它,不受影响。
enum WebsiteSearcher {

	private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "FeedDiscovery")

	static func search(_ term: String) async throws -> [FeedSearchResult] {

		let keyword = term.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !keyword.isEmpty else {
			throw FeedSearchError.emptyInput
		}

		var components = URLComponents(string: "https://cloud.feedly.com/v3/search/feeds")!
		components.queryItems = [
			URLQueryItem(name: "query", value: keyword),
			URLQueryItem(name: "count", value: "20")
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
			logger.warning("[发现] 网站搜索(Feedly):返回状态码 \(http.statusCode)")
			throw FeedSearchError.badResponse(http.statusCode)
		}

		return parse(data)
	}

	/// 防御式解析:这是一个未公开接口,字段哪天变了更不该让我们崩。
	private static func parse(_ data: Data) -> [FeedSearchResult] {

		guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
			  let items = root["results"] as? [[String: Any]] else {
			logger.warning("[发现] 网站搜索(Feedly):返回的不是预期的 JSON 结构")
			return []
		}

		var found = [FeedSearchResult]()
		var seenURLs = Set<String>()

		for item in items {

			guard let feedID = item["feedId"] as? String, !feedID.isEmpty else {
				continue
			}
			// feedId 形如 "feed/https://stratechery.com/feed/",把前缀去掉就是真正的地址。
			let feedURL = feedID.hasPrefix("feed/") ? String(feedID.dropFirst(5)) : feedID
			guard feedURL.hasPrefix("http://") || feedURL.hasPrefix("https://") else {
				continue // 极少数结果是 YouTube/播客的 feed,交叉重复,交给对应类别自己去搜
			}
			guard !seenURLs.contains(feedURL) else { continue }
			seenURLs.insert(feedURL)

			let title = (item["title"] as? String) ?? feedURL

			var subtitleParts = [String]()
			if let description = (item["description"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
			   !description.isEmpty {
				subtitleParts.append(description)
			}
			if let subscribers = item["subscribers"] as? Int, subscribers > 0 {
				subtitleParts.append("\(subscribers) 订阅")
			}

			found.append(FeedSearchResult(
				kind: .website,
				title: title,
				subtitle: subtitleParts.isEmpty ? nil : subtitleParts.joined(separator: " · "),
				feedURL: feedURL,
				homePageURL: item["website"] as? String,
				iconURL: item["iconUrl"] as? String))
		}

		logger.info("[发现] 网站搜索(Feedly):返回 \(items.count) 条,可订阅 \(found.count) 条")
		return found
	}
}
