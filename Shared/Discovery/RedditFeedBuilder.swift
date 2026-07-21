//
//  RedditFeedBuilder.swift
//  NetNewsWire
//
//  [发现] 本 fork 新增,上游没有这个文件。
//

import Foundation
import os

/// 把用户输入的东西变成 Reddit 子版的可订阅地址。
///
/// ⚠️ **为什么这里是「拼地址」而不是「搜索」**:
/// Reddit 的子版搜索接口 `reddit.com/subreddits/search.json` 实测返回 **403**,
/// 已经对未登录请求关闭了。所以做不了「输入关键词,发现有哪些子版」,
/// 只能做「你已经知道子版叫什么 → 我拼出订阅地址」。
/// (2026-07-21 实测并经用户确认接受。)
///
/// 好消息是 `.rss` 端点本身是通的,而且**帖子正文就在 feed 里**,
/// 所以订阅之后的阅读体验是完整的。
enum RedditFeedBuilder {

	private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "FeedDiscovery")

	/// 热门帖的排序方式。用户搜一个子版,我们把这几种都列出来让他挑。
	enum Sort: String, CaseIterable {
		case day
		case week
		case month
		case hot

		var displayName: String {
			switch self {
			case .day: return "每日热门"
			case .week: return "每周热门"
			case .month: return "每月热门"
			case .hot: return "实时热门"
			}
		}

		func feedURL(subreddit: String) -> String {
			switch self {
			case .hot:
				return "https://www.reddit.com/r/\(subreddit)/hot/.rss"
			default:
				return "https://www.reddit.com/r/\(subreddit)/top/.rss?t=\(rawValue)"
			}
		}
	}

	/// 从用户随便输入的东西里认出子版名。
	///
	/// 这几种写法都认:
	///   rss
	///   r/rss        /r/rss
	///   reddit.com/r/rss
	///   https://www.reddit.com/r/rss/comments/xxx/标题/    ← 直接粘一个帖子的链接也行
	static func subredditName(from input: String) -> String? {

		var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !text.isEmpty else {
			return nil
		}

		// 是个网址就把 /r/xxx 那一段挖出来
		if let range = text.range(of: "/r/", options: [.caseInsensitive]) {
			text = String(text[range.upperBound...])
		} else if text.lowercased().hasPrefix("r/") {
			text = String(text.dropFirst(2))
		}

		// 只取第一段(后面可能还跟着 /comments/... 或 ?查询参数)
		let name = text
			.split(whereSeparator: { $0 == "/" || $0 == "?" || $0 == "#" || $0 == " " })
			.first
			.map(String.init) ?? ""

		// Reddit 的子版名规则:字母数字下划线,2~21 个字符
		let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
		guard !name.isEmpty,
			  name.count <= 21,
			  name.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
			return nil
		}

		return name
	}

	/// 用户输入 → 四条可订阅的地址(每日/每周/每月/实时热门)。
	///
	/// ⚠️ **这一步一个网络请求都不发,全在本地拼地址。**
	///
	/// 原本这里会先拉一次 feed 去「验证版块存在」,2026-07-21 实测后删掉了。原因:
	///
	/// 1. Reddit 按 IP 限流,而且很紧。搜索发一次、订阅再发一次 = 一次操作打两枪,
	///    在配额紧张时**第二枪(也就是真正要紧的那次订阅)会挨 429**。
	/// 2. 更糟的是那次验证走的是 `URLSession.shared`,**绕过了 app 自己的 429 记账**
	///    (`DownloadSession.requestShouldBeDroppedDueToActive429`)——
	///    只消耗配额、不参与退避,是纯负收益。
	/// 3. 验证本来想解决的问题(版块名拼错)反正订阅时也会暴露,
	///    而 429 造成的假错误比拼错难查一百倍。
	///
	/// **教训**:对限流严格的服务,不要为了「提前给点反馈」而多打一次请求 ——
	/// 省下来的那一次,要留给真正必须成功的那一步。
	static func results(subreddit: String) -> [FeedSearchResult] {
		Sort.allCases.map { sort in
			FeedSearchResult(
				kind: .reddit,
				title: "r/\(subreddit) · \(sort.displayName)",
				subtitle: "reddit.com/r/\(subreddit)",
				feedURL: sort.feedURL(subreddit: subreddit),
				homePageURL: "https://www.reddit.com/r/\(subreddit)/")
		}
	}

	/// 订阅 Reddit 失败时,把上游那句误导人的错误换成说实话的。
	///
	/// **为什么需要这一层**:上游 `FeedFinder` 只判断「状态码不是 OK」就抛
	/// `feedNotFound`,文案是「The feed couldn't be found and can't be added.」。
	/// 但实测 429(限流)走的也是这条路 —— 于是「你被限流了,等一分钟」
	/// 被显示成了「这个 feed 不存在」,用户只会去反复检查根本没错的版块名。
	///
	/// FeedFinder 在 A 级禁区不能改,所以在我们自己这层把话说清楚。
	/// 拿不到具体状态码,就**把两种可能都说出来**,并给出各自该怎么办 ——
	/// 这比二选一猜错要有用。
	static func friendlyError(for underlying: Error, subreddit: String) -> Error {
		let message = """
			订阅 r/\(subreddit) 失败。两种可能:

			① Reddit 限制了访问频率(最常见)。等一两分钟再点一次就好 —— \
			app 在挨过限流后会自动停发一段时间,所以立刻重试还是会失败。

			② 版块名拼错了,或者这是个私密版块。

			如果多等几分钟仍然失败,再去检查版块名。
			"""
		return NSError(domain: "FeedDiscovery.Reddit", code: 429, userInfo: [
			NSLocalizedDescriptionKey: message,
			NSUnderlyingErrorKey: underlying
		])
	}
}
