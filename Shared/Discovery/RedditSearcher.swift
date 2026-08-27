//
//  RedditSearcher.swift
//  NetNewsWire
//
//  [发现] 本 fork 新增,上游没有这个文件。
//

import Foundation
import RSWeb
import os

/// 用 Reddit 官方 API 按关键词搜版块。
///
/// ## 为什么 `RedditFeedBuilder`(拼地址那个)解决不了这件事
///
/// `reddit.com/subreddits/search.json` 那个**不需要登录**的接口实测 403,
/// 已经对匿名请求关闭(详见 `RedditFeedBuilder` 开头的注释)。
/// 真正能用的搜索接口在 `oauth.reddit.com` 下面,**需要一个 OAuth token** ——
/// 但不需要用户登录 Reddit 账号,Reddit 支持「应用级」的
/// `client_credentials` 授权(官方叫 *Application Only OAuth*),
/// 只要有一对免费申请的 `client_id`/`secret` 就能换到 token,足够查公开数据。
///
/// 申请地址:reddit.com/prefs/apps → 创建一个 **script** 类型的应用,
/// 不需要真实网站、不需要过审,当场就能拿到 `client_id`(应用名下面那串)和
/// `secret`。填法见设置页 `DiscoveryAPIKeysViewController`。
@MainActor final class RedditSearcher {

	static let shared = RedditSearcher()

	private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "FeedDiscovery")

	/// 缓存的 token 和它的过期时刻。提前 60 秒判过期,免得请求路上真的过期了。
	private var cachedToken: (value: String, expiresAt: Date)?

	private init() {}

	static func search(_ term: String) async throws -> [FeedSearchResult] {
		try await shared.performSearch(term)
	}

	private func performSearch(_ term: String) async throws -> [FeedSearchResult] {

		let keyword = term.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !keyword.isEmpty else {
			throw FeedSearchError.emptyInput
		}

		guard FeedDiscoveryKeychain.hasRedditCredentials else {
			throw FeedSearchError.missingCredentials(service: "Reddit")
		}

		let token = try await accessToken()

		var components = URLComponents(string: "https://oauth.reddit.com/subreddits/search")!
		components.queryItems = [
			URLQueryItem(name: "q", value: keyword),
			URLQueryItem(name: "limit", value: "20")
		]
		guard let url = components.url else {
			throw FeedSearchError.emptyInput
		}

		var request = URLRequest(url: url)
		request.timeoutInterval = 20
		request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
		request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")

		let data: Data
		let response: URLResponse
		do {
			(data, response) = try await URLSession.shared.data(for: request)
		} catch {
			throw FeedSearchError.network(error)
		}

		if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
			// token 可能刚好过期或被撤销:清掉缓存,下次重新换一个,不在这次请求里重试
			// (重试逻辑放这么深容易把一次简单的搜索拖成好几个网络往返,划不来)。
			if let http = response as? HTTPURLResponse, http.statusCode == 401 {
				cachedToken = nil
			}
			throw FeedSearchError.reddit(statusCode: http.statusCode)
		}

		return Self.parse(data)
	}

	// MARK: - Application Only OAuth

	/// 拿一个可用的 token。缓存命中就直接用,没有或过期了才真的去换。
	private func accessToken() async throws -> String {

		if let cached = cachedToken, cached.expiresAt > Date() {
			return cached.value
		}

		guard let clientID = FeedDiscoveryKeychain.redditClientID,
			  let secret = FeedDiscoveryKeychain.redditClientSecret else {
			throw FeedSearchError.missingCredentials(service: "Reddit")
		}

		var request = URLRequest(url: URL(string: "https://www.reddit.com/api/v1/access_token")!)
		request.httpMethod = "POST"
		request.timeoutInterval = 20
		request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
		request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

		// app-only 授权:Basic 认证放 client_id:secret,body 只需要 grant_type。
		let credentials = "\(clientID):\(secret)"
		guard let credentialsData = credentials.data(using: .utf8) else {
			throw FeedSearchError.missingCredentials(service: "Reddit")
		}
		request.setValue("Basic \(credentialsData.base64EncodedString())", forHTTPHeaderField: "Authorization")
		request.httpBody = "grant_type=client_credentials".data(using: .utf8)

		let data: Data
		let response: URLResponse
		do {
			(data, response) = try await URLSession.shared.data(for: request)
		} catch {
			throw FeedSearchError.network(error)
		}

		if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
			Self.logger.warning("[发现] Reddit 换 token 失败:状态码 \(http.statusCode)")
			throw FeedSearchError.reddit(statusCode: http.statusCode)
		}

		guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
			  let token = root["access_token"] as? String else {
			throw FeedSearchError.badResponse(0)
		}

		let expiresIn = (root["expires_in"] as? Double) ?? 3600
		cachedToken = (token, Date().addingTimeInterval(max(expiresIn - 60, 30)))
		return token
	}

	/// Reddit 要求调用方带一个能识别身份的 User-Agent,默认 UA 会被拒绝。
	/// 复用 app 抓 feed 时用的那个标识串,不用另外编一个。
	private static var userAgent: String {
		UserAgent.fromInfoPlist() ?? "NetNewsWire-iOS-Fork/1.0"
	}

	// MARK: - 解析

	/// 防御式解析:Reddit 的字段哪天变了也不该让我们崩。
	private static func parse(_ data: Data) -> [FeedSearchResult] {

		guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
			  let dataDict = root["data"] as? [String: Any],
			  let children = dataDict["children"] as? [[String: Any]] else {
			logger.warning("[发现] Reddit 搜索:返回的不是预期的 JSON 结构")
			return []
		}

		var found = [FeedSearchResult]()
		var seenNames = Set<String>()

		for child in children {

			guard let itemData = child["data"] as? [String: Any],
				  let name = itemData["display_name"] as? String, !name.isEmpty else {
				continue
			}
			// 同一个版块只留一条(理论上不会重复,防御一下)
			let key = name.lowercased()
			guard !seenNames.contains(key) else { continue }
			seenNames.insert(key)

			var subtitleParts = [String]()
			if let subscribers = itemData["subscribers"] as? Int, subscribers > 0 {
				subtitleParts.append("\(subscribers) 订阅")
			}
			if let description = itemData["public_description"] as? String,
			   !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
				subtitleParts.append(description.trimmingCharacters(in: .whitespacesAndNewlines))
			}

			// 图标:community_icon 比 icon_img 更常有值,而且两个字段都会把
			// URL 里的 "&" 转义成 "&amp;",不还原的话这个地址下不了图。
			let rawIcon = (itemData["community_icon"] as? String).flatMap { $0.isEmpty ? nil : $0 }
				?? (itemData["icon_img"] as? String).flatMap { $0.isEmpty ? nil : $0 }
			let iconURL = rawIcon?.replacingOccurrences(of: "&amp;", with: "&")

			found.append(FeedSearchResult(
				kind: .reddit,
				title: "r/\(name)",
				subtitle: subtitleParts.isEmpty ? nil : subtitleParts.joined(separator: " · "),
				// 搜索结果统一给「实时热门」这一种排序——四选一是给"我已经知道版块名"那条老路用的,
				// 混进搜索结果列表会让每个版块占四行,列表被稀释得很难扫。
				feedURL: "https://www.reddit.com/r/\(name)/hot/.rss",
				homePageURL: "https://www.reddit.com/r/\(name)/",
				iconURL: iconURL))
		}

		logger.info("[发现] Reddit 搜索:返回 \(children.count) 条,可订阅 \(found.count) 条")
		return found
	}
}
