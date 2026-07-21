//
//  YouTubeFeedResolver.swift
//  NetNewsWire
//
//  [发现] 本 fork 新增,上游没有这个文件。
//

import Foundation
import os

/// 把 YouTube 频道的各种网址变成官方 RSS 地址。
///
/// YouTube **有官方 RSS**,一直没关:
///     https://www.youtube.com/feeds/videos.xml?channel_id=UCxxxxxxxx
/// 实测(2026-07-21)返回 15 条最新视频,带标题、链接、缩略图和简介。
///
/// 麻烦在于这个地址要的是 `channel_id`(UC 开头那一串),
/// 而用户手里拿到的通常是 `@handle` 这种好记的名字。两者之间没有公式,
/// 只能拉一次频道页把 id 抠出来。
enum YouTubeFeedResolver {

	private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "FeedDiscovery")

	/// 抓频道页时假装成桌面浏览器。
	///
	/// 这里**故意不用 app 自己的 User-Agent**,和 Reddit 那边的做法相反 ——
	/// 因为这不是在抓 feed,而是抓一个普通网页,YouTube 对非浏览器 UA 会返回
	/// 精简版页面,里面可能没有我们要的那个 id。
	/// (抓 feed 才必须和 app 用同一个 UA,原因见 NOTES-lessons L33。)
	private static let browserUserAgent =
		"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

	/// 用户可能输入的东西 → 可订阅地址。
	///
	/// 认这些写法:
	///   https://www.youtube.com/channel/UCxxxx     ← 不用联网,直接拼
	///   https://www.youtube.com/@veritasium        ← 要拉一次页面
	///   https://www.youtube.com/c/名字   /user/名字  ← 要拉一次页面
	///   @veritasium  或  veritasium                 ← 当成 handle
	static func resolve(_ input: String) async throws -> FeedSearchResult {

		let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !text.isEmpty else {
			throw FeedSearchError.emptyInput
		}

		// 最省的一条路:网址里直接带着 channel_id,不用联网
		if let channelID = channelIDInText(text) {
			logger.info("[发现] YouTube:直接从输入里拿到 channelId")
			return result(channelID: channelID, title: nil)
		}

		// 否则拼出频道页地址,拉一次把 id 抠出来
		let pageURL = try channelPageURL(from: text)

		var request = URLRequest(url: pageURL)
		request.timeoutInterval = 25
		request.setValue(browserUserAgent, forHTTPHeaderField: "User-Agent")

		let data: Data
		let response: URLResponse
		do {
			(data, response) = try await URLSession.shared.data(for: request)
		} catch {
			throw FeedSearchError.network(error)
		}

		if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
			logger.warning("[发现] YouTube:频道页返回 \(http.statusCode)")
			throw FeedSearchError.youTubeChannelNotFound
		}

		guard let html = String(data: data, encoding: .utf8),
			  let channelID = channelIDInText(html) else {
			throw FeedSearchError.youTubeChannelNotFound
		}

		logger.info("[发现] YouTube:从频道页解析出 channelId")
		return result(channelID: channelID, title: pageTitle(in: html))
	}

	// MARK: - 内部

	private static func result(channelID: String, title: String?) -> FeedSearchResult {
		FeedSearchResult(
			kind: .youtube,
			title: title ?? "YouTube 频道 \(channelID)",
			subtitle: "youtube.com · \(channelID)",
			feedURL: "https://www.youtube.com/feeds/videos.xml?channel_id=\(channelID)",
			homePageURL: "https://www.youtube.com/channel/\(channelID)")
	}

	/// 从任意文本里找 UC 开头的频道 id。
	///
	/// 频道页里这个 id 会以好几种形式出现("channelId":"UC…"、/channel/UC…、
	/// externalId 等),这里按由准到松的顺序试,取第一个命中的。
	private static func channelIDInText(_ text: String) -> String? {

		let patterns = [
			#""channelId"\s*:\s*"(UC[A-Za-z0-9_-]{20,})""#,
			#""externalId"\s*:\s*"(UC[A-Za-z0-9_-]{20,})""#,
			#"channel/(UC[A-Za-z0-9_-]{20,})"#
		]

		for pattern in patterns {
			guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
			let range = NSRange(text.startIndex..., in: text)
			if let match = regex.firstMatch(in: text, range: range),
			   let idRange = Range(match.range(at: 1), in: text) {
				return String(text[idRange])
			}
		}
		return nil
	}

	/// 把用户输入变成一个能打开的频道页地址
	private static func channelPageURL(from text: String) throws -> URL {

		if text.lowercased().hasPrefix("http"), let url = URL(string: text) {
			return url
		}

		// 不是网址,就当成 handle。@ 可有可无。
		var handle = text
		if handle.hasPrefix("@") {
			handle = String(handle.dropFirst())
		}

		let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
		guard !handle.isEmpty, handle.unicodeScalars.allSatisfy({ allowed.contains($0) }),
			  let url = URL(string: "https://www.youtube.com/@\(handle)") else {
			throw FeedSearchError.youTubeChannelNotFound
		}
		return url
	}

	/// 顺手取一下页面标题当频道名。取不到不影响订阅 —— 订阅后 feed 里也有名字。
	private static func pageTitle(in html: String) -> String? {
		guard let start = html.range(of: "<title>"),
			  let end = html.range(of: "</title>", range: start.upperBound..<html.endIndex) else {
			return nil
		}
		var title = String(html[start.upperBound..<end.lowerBound])
			.trimmingCharacters(in: .whitespacesAndNewlines)
		// YouTube 的页面标题都带这个后缀,去掉更干净
		for suffix in [" - YouTube", " – YouTube"] where title.hasSuffix(suffix) {
			title = String(title.dropLast(suffix.count))
		}
		return title.isEmpty ? nil : title
	}
}
