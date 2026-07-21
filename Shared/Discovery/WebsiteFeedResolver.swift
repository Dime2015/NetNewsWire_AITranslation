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

		// ⚠️ 第 0 步:先问一句「你给我的这个地址,本身是不是就是 feed?」
		//
		// 这一步初版漏了,后果很严重:用户手里已经有一个现成的 RSS 地址
		// (最基本的用法)时,我们会拿它去当网页抓,然后在它后面接着探
		// `/feed/feed/`、`/feed/rss` …… 全部 404,最后告诉用户「没找到」。
		//
		// 上游 FeedFinder 的第一步就是这个判断(isFeed → 直接采用),
		// 我把后面几步都抄了,偏偏漏了最前面这步。
		//
		// ⚠️ 排查这个 bug 时,日志一片空白让我以为代码没执行 ——
		//    实际是 `log show` **默认不保留 info 级别**,要加 `--info` 才看得到。
		if let (data, _) = try? await fetch(url), isFeed(data) {
			logger.info("[发现] 网站:输入的地址本身就是 feed,直接采用")
			return [FeedSearchResult(
				kind: .website,
				title: feedTitle(in: data) ?? host,
				subtitle: normalized,
				feedURL: normalized,
				homePageURL: nil,
				iconURL: iconURL(forFeed: data, feedURL: url))]
		}

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
			if let (data, _) = try? await fetch(candidate), isFeed(data) {
				logger.info("[发现] 网站:探测命中 \(path)")
				let title = feedTitle(in: data)
				return [FeedSearchResult(
					kind: .website,
					title: (title?.isEmpty == false) ? title! : host,
					subtitle: candidate.absoluteString,
					feedURL: candidate.absoluteString,
					homePageURL: normalized,
					// 网页里读到的 favicon 优先(那是站点自己声明的,最准);
					// 网页没声明就退回 feed 自带的图标 / 猜 favicon.ico
					iconURL: faviconURL ?? iconURL(forFeed: data, feedURL: candidate))]
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

	/// 直接粘 feed 地址时,结果行左边那个小图标从哪来。
	///
	/// **两个来源都不额外发请求**:
	///   1. **feed 自己带的图标** —— RSS 的 `<image><url>`、
	///      播客的 `<itunes:image href>`、Atom 的 `<icon>`/`<logo>`。
	///      数据已经在手里了,白拿。(实测 Stratechery 有,Benedict Evans 和 jvns 没有)
	///   2. 没有的话,退回猜 `https://<域名>/favicon.ico`。
	///      **故意不去验证它存不存在** —— 交给 `ImageDownloader` 去取,
	///      取不到它自己会静默失败,界面就退回类型符号。
	///      为一个小图标专门发一次验证请求不值得。
	///
	/// (为什么不抓网站首页解析 `<link rel="icon">`:那要多一次几百 KB 的请求,
	///  而用户此时给的是 feed 地址,我们本来根本不需要碰那个网页。)
	private static func iconURL(forFeed data: Data, feedURL: URL) -> String? {

		let text = String(decoding: data.prefix(64 * 1024), as: UTF8.self)

		let patterns = [
			#"<itunes:image[^>]*href\s*=\s*["']([^"']+)["']"#,
			#"<image>\s*<url>\s*([^<]+?)\s*</url>"#,
			#"<icon>\s*([^<]+?)\s*</icon>"#,
			#"<logo>\s*([^<]+?)\s*</logo>"#
		]
		for pattern in patterns {
			guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
				continue
			}
			let range = NSRange(text.startIndex..., in: text)
			if let match = regex.firstMatch(in: text, range: range),
			   let valueRange = Range(match.range(at: 1), in: text) {
				let candidate = String(text[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
				if candidate.lowercased().hasPrefix("http") {
					return candidate
				}
			}
		}

		// feed 里没有图标,退回猜 favicon
		guard let scheme = feedURL.scheme, let host = feedURL.host else {
			return nil
		}
		return "\(scheme)://\(host)/favicon.ico"
	}

	/// 这段数据是不是一个 feed。
	/// 只看开头一小段就够 —— 有些 feed 有好几百 KB,没必要整个转成字符串。
	/// 认 RSS、Atom、RDF 三种,以及 JSON Feed。
	private static func isFeed(_ data: Data) -> Bool {
		let head = String(decoding: data.prefix(4096), as: UTF8.self).lowercased()
		if head.contains("<rss") || head.contains("<feed") || head.contains("rdf:rdf") {
			return true
		}
		// JSON Feed(Daring Fireball 之类会用),靠它的版本标识认
		return head.contains("https://jsonfeed.org/version/")
	}

	/// 从 feed 数据里取标题。取不到返回 nil,不影响订阅 —— 订阅后 app 自己会更新名字。
	private static func feedTitle(in data: Data) -> String? {

		let text = String(decoding: data.prefix(64 * 1024), as: UTF8.self)

		// JSON Feed 的标题格式不一样
		if text.lowercased().contains("https://jsonfeed.org/version/"),
		   let range = text.range(of: #""title"\s*:\s*"([^"]*)""#, options: .regularExpression) {
			let fragment = String(text[range])
			if let valueStart = fragment.range(of: "\"", options: .backwards, range: fragment.startIndex..<fragment.index(before: fragment.endIndex)) {
				return String(fragment[valueStart.upperBound..<fragment.index(before: fragment.endIndex)])
			}
		}

		guard let start = text.range(of: "<title>"),
			  let end = text.range(of: "</title>", range: start.upperBound..<text.endIndex) else {
			return nil
		}
		var title = String(text[start.upperBound..<end.lowerBound])
			.trimmingCharacters(in: .whitespacesAndNewlines)

		// ⚠️ 很多 feed 会把标题包在 CDATA 里(实测 jvns.ca 就是
		// `<![CDATA[Julia Evans]]>`)。不剥掉的话,这一整串会**原样变成订阅源的名字**。
		if title.hasPrefix("<![CDATA[") && title.hasSuffix("]]>") {
			title = String(title.dropFirst(9).dropLast(3))
				.trimmingCharacters(in: .whitespacesAndNewlines)
		}
		return title.isEmpty ? nil : title
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
