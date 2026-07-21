//
//  FeedQueryRouter.swift
//  NetNewsWire
//
//  [发现] 本 fork 新增,上游没有这个文件。
//

import Foundation

/// 把用户在搜索框里输入的**任意东西**,分派给合适的查找器。
///
/// ## 为什么要有这一层
///
/// 改造前,用户得先想清楚"我要找的是播客还是 Reddit 还是网站",选好 tab 再输入。
/// 但这个前置判断对用户是**多余的负担** —— 粘一个 youtube.com 的网址进来,
/// 它显然是 YouTube,不该还要求用户先去点一下 YouTube 那个 tab。
///
/// 所以「全部」这个默认 tab 会自己判断:
///   - 输入的是**网址** → 按域名认出类型(youtube / reddit / 其它网站)
///   - 输入的是**文字** → 当成关键词去搜播客(唯一支持关键词搜索的那类)
///
/// tab 的作用因此从「必须先选的前置步骤」降级为「缩小范围」。
enum FeedQueryRouter {

	/// 一次查询该走哪条路
	enum Route {
		case podcastKeyword(String)
		case reddit(String)          // 子版名
		case youtube(String)         // 原始输入,交给 YouTubeFeedResolver 解析
		case website(String)         // 原始输入
		/// 输入的是文字,但当前 tab 不支持关键词搜索
		case unsupportedKeyword(hint: String)
	}

	/// 「全部」tab:自己判断输入是什么。
	static func route(for input: String) -> Route {

		let text = input.trimmingCharacters(in: .whitespacesAndNewlines)

		guard looksLikeURL(text) else {
			// 不是网址 → 当关键词。目前只有播客支持关键词搜索
			// (Reddit 的搜索接口被封了,YouTube 关键词搜索要 API key,
			//  普通网站没有官方的关键词接口 —— 详见 CLAUDE.md 第 1 节的实测表)
			return .podcastKeyword(text)
		}

		switch hostKind(of: text) {
		case .youtube:
			return .youtube(text)
		case .reddit:
			// 从网址里把子版名抠出来;抠不到就当普通网站处理
			if let subreddit = RedditFeedBuilder.subredditName(from: text) {
				return .reddit(subreddit)
			}
			return .website(text)
		case .other:
			return .website(text)
		}
	}

	// MARK: - 判断

	private enum HostKind {
		case youtube
		case reddit
		case other
	}

	/// 看起来像网址吗。
	///
	/// 判断放宽松一点:用户常常只输 `stratechery.com`(没有 https://)。
	/// 规则:带协议头的一定是;否则「含点、不含空格、且点后面有东西」就算。
	private static func looksLikeURL(_ text: String) -> Bool {

		let lower = text.lowercased()
		if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
			return true
		}
		guard !text.contains(" ") else {
			return false
		}

		// ⚠️ 只看第一个 "/" 之前的域名部分。
		// 初版拿「整串里最后一个点」去判断,结果 `youtube.com/channel/UCxxx`
		// 取到的是 `com/channel/UCxxx`,含斜杠 → 被误判成关键词。
		// 这个 bug 是靠离线跑一批真实输入抓出来的,不是看代码看出来的。
		let hostPart = text.split(separator: "/", maxSplits: 1).first ?? ""
		guard let dotIndex = hostPart.lastIndex(of: ".") else {
			return false
		}

		// 点后面得有内容,且只允许字母(排除 "3.5" 这种数字、"什么什么." 这种空尾)
		let topLevelDomain = hostPart[hostPart.index(after: dotIndex)...]
		guard !topLevelDomain.isEmpty, topLevelDomain.count <= 24 else {
			return false
		}
		return topLevelDomain.allSatisfy { $0.isLetter }
	}

	private static func hostKind(of text: String) -> HostKind {

		var normalized = text
		if !normalized.lowercased().hasPrefix("http") {
			normalized = "https://" + normalized
		}
		guard let host = URL(string: normalized)?.host?.lowercased() else {
			return .other
		}

		// 去掉 www. 前缀再比,免得漏掉写法差异
		let bare = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host

		if bare == "youtube.com" || bare == "youtu.be" || bare == "m.youtube.com"
			|| bare == "youtube-nocookie.com" {
			return .youtube
		}
		if bare == "reddit.com" || bare == "old.reddit.com" || bare == "np.reddit.com" {
			return .reddit
		}
		return .other
	}
}
