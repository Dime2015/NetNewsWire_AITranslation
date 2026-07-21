//
//  WebsiteFeedResolver.swift
//  NetNewsWire
//
//  [发现] 本 fork 新增,上游没有这个文件。
//

import Foundation
import RSParser
import os

/// 普通网站:从一个网址找出它的 RSS 地址。
///
/// ## 这里改过一次,原因值得记下来
///
/// **初版什么都不做**,只把 `https://` 补全,然后把网址原样交给
/// `Account.createFeed(..., validateFeed: true)`,指望上游的 `FeedFinder`
/// 在订阅时自己去发现。理由当时听起来很对:「上游已经做得很全了,
/// 自己再写一遍只会是更差的复制品」。
///
/// **实测结果是:用户试了好几个网站,一个都订不上。**
/// 我犯的错不是「选择复用上游」,而是**从来没有端到端验证过这条路**——
/// 那句「上游会处理」自始至终是个未经检验的假设。
///
/// ## 现在的做法
///
/// **把发现提前到搜索阶段**,而不是等到订阅那一刻:
///   1. 抓一次网页,用上游 `RSParser` 的 `HTMLMetadataParser` 读出 `<link rel="alternate">`
///      —— 这是上游自己解析 HTML 的正规工具,**不是正则**(CLAUDE.md 第 5 节)
///   2. 网页里没声明,就自己探几个最常见的地址(`/feed/`、`/rss`、`/index.xml` …)
///
/// ⚠️ 为什么不直接调上游的 `FeedFinder.find(url:)`(它其实做了同样的事):
/// **`FeedFinder` 模块没有被链接进 app target**(project.pbxproj 里出现 0 次),
/// 只有 Account 模块在用它。要链进来就得改 .xcodeproj —— 那是第 8 节禁止的。
/// 所以改用同样是上游出品、而且 app 已经链接了的 `RSParser`。
///
/// 顺带的好处:`HTMLMetadata` 里连 favicon 也一并解析好了,
/// 结果行左边的小图标就有了来源。
///
/// 这样做有三个好处,而且都是初版拿不到的:
///   · **订阅时交出去的是一个确定的 feed 地址**,不再依赖订阅那一刻的再次发现
///   · 用户在搜索结果里**当场就能看到找到了什么**,而不是点了订阅才知道成不成
///   · 找到的是真正的 feed,所以能顺带拿到它的标题
enum WebsiteFeedResolver {

	private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "FeedDiscovery")

	/// 上游没找到时,自己按顺序探这几个地址。
	/// 覆盖了绝大多数建站工具的默认设置:WordPress、Ghost、Hugo、Jekyll、Substack。
	private static let commonFeedPaths = [
		"/feed/",          // WordPress、Substack
		"/rss",            // Ghost 等
		"/feed.xml",       // Jekyll
		"/index.xml",      // Hugo
		"/rss.xml",
		"/atom.xml",
		"/feed/atom/"
	]

	/// 从一个网址找出可订阅的 feed。找不到就抛错。
	static func search(_ input: String) async throws -> [FeedSearchResult] {

		let normalized = normalizedURLString(input)
		guard let url = URL(string: normalized) else {
			throw FeedSearchError.notAFeed
		}
		let host = url.host ?? normalized

		// 第一步:抓一次网页,读它自己声明的 RSS 地址。
		var faviconURL: String?
		if let (data, _) = try? await fetch(url) {
			let metadata = HTMLMetadataParser.htmlMetadata(
				with: ParserData(url: normalized, data: data))
			faviconURL = metadata.favicons.compactMap { $0.urlString }.first

			let declared = metadata.feedLinks.compactMap { link -> FeedSearchResult? in
				guard let feedURLString = link.urlString, !feedURLString.isEmpty else {
					return nil
				}
				return FeedSearchResult(
					kind: .website,
					title: link.title ?? host,
					subtitle: feedURLString,
					feedURL: feedURLString,
					homePageURL: normalized,
					iconURL: faviconURL)
			}
			if !declared.isEmpty {
				logger.info("[发现] 网站:网页里声明了 \(declared.count) 个 feed")
				// 地址短的通常是主 feed(评论 feed 一般更长),排前面
				return declared.sorted { $0.feedURL.count < $1.feedURL.count }
			}
		}

		// 第二步:网页里没声明,自己探常见地址。
		// 逐个试而不是并发,是为了不对同一个站点同时打好几枪。
		//
		// 这一步是必需的,不是保险 —— 实测 stratechery.com 的 <head> 里
		// **一个 RSS 声明都没有**,但 /feed/ 确实是通的。只靠读网页会漏掉这类站。
		logger.info("[发现] 网站:网页里没有声明,改为探测常见地址")
		for path in commonFeedPaths {
			guard let candidate = URL(string: normalized.trimmedTrailingSlash + path) else {
				continue
			}
			if let title = await feedTitle(at: candidate) {
				logger.info("[发现] 网站:探测命中 \(path)")
				return [FeedSearchResult(
					kind: .website,
					title: title.isEmpty ? host : title,
					subtitle: candidate.absoluteString,
					feedURL: candidate.absoluteString,
					homePageURL: normalized,
					iconURL: faviconURL)]
			}
		}

		logger.warning("[发现] 网站:\(normalized) 没找到任何 feed")
		throw FeedSearchError.websiteFeedNotFound
	}

	/// 发一个请求,带上和 app 抓 feed 时同一个 User-Agent(见 L33)。
	/// 非 2xx 一律当失败。
	private static func fetch(_ url: URL) async throws -> (Data, HTTPURLResponse) {

		var request = URLRequest(url: url)
		request.timeoutInterval = 20
		if let userAgent = Bundle.main.object(forInfoDictionaryKey: "UserAgent") as? String {
			request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
		}

		let (data, response) = try await URLSession.shared.data(for: request)
		guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
			throw FeedSearchError.notAFeed
		}
		return (data, http)
	}

	/// 拉一个候选地址,确认它真的是 feed,顺带把标题取出来。
	/// 不是 feed 就返回 nil。
	private static func feedTitle(at url: URL) async -> String? {

		guard let (data, _) = try? await fetch(url) else {
			return nil
		}

		// 只看开头一小段就够判断是不是 feed —— 有些 feed 有好几百 KB
		let head = String(decoding: data.prefix(4096), as: UTF8.self).lowercased()
		guard head.contains("<rss") || head.contains("<feed") || head.contains("rdf:rdf") else {
			return nil
		}

		// 取第一个 <title>。取不到不影响订阅,订阅后 app 自己会更新名字。
		let text = String(decoding: data.prefix(64 * 1024), as: UTF8.self)
		guard let start = text.range(of: "<title>"),
			  let end = text.range(of: "</title>", range: start.upperBound..<text.endIndex) else {
			return ""
		}
		var title = String(text[start.upperBound..<end.lowerBound])
			.trimmingCharacters(in: .whitespacesAndNewlines)

		// ⚠️ 很多 feed 会把标题包在 CDATA 里(实测 jvns.ca 就是
		// `<![CDATA[Julia Evans]]>`)。不剥掉的话,这一整串会**原样变成订阅源的名字**。
		if title.hasPrefix("<![CDATA[") && title.hasSuffix("]]>") {
			title = String(title.dropFirst(9).dropLast(3))
				.trimmingCharacters(in: .whitespacesAndNewlines)
		}
		return title
	}

	/// 补全协议头。`stratechery.com` → `https://stratechery.com`
	private static func normalizedURLString(_ input: String) -> String {

		var text = input.trimmingCharacters(in: .whitespacesAndNewlines)

		// 有些人会连尖括号或引号一起粘进来
		while let first = text.first, first == "<" || first == "\"" || first == "'" {
			text.removeFirst()
		}
		while let last = text.last, last == ">" || last == "\"" || last == "'" {
			text.removeLast()
		}

		if text.lowercased().hasPrefix("http://") || text.lowercased().hasPrefix("https://") {
			return text
		}
		if text.hasPrefix("//") {
			return "https:" + text
		}
		return "https://" + text
	}
}

private extension String {
	/// 去掉结尾的斜杠,免得拼出 `https://a.com//feed/` 这种双斜杠
	var trimmedTrailingSlash: String {
		var text = self
		while text.hasSuffix("/") {
			text.removeLast()
		}
		return text
	}
}
