//
//  WebsiteFeedResolver.swift
//  NetNewsWire
//
//  [发现] 本 fork 新增,上游没有这个文件。
//

import Foundation

/// 普通网站:把用户输入的网址整理成可以交给订阅流程的样子。
///
/// ⚠️ **这里刻意什么都不做。**
///
/// 「给一个网站首页,找出它的 RSS 地址」这件事,上游 `FeedFinder` 已经做得很全了:
///   1. 先看这个地址本身是不是 feed
///   2. 不是的话,解析 HTML 的 `<head>`,找 `<link rel="alternate">`
///   3. 还会试一批常见路径
/// 而 `Account.createFeed(..., validateFeed: true)` 内部就会跑这一整套。
///
/// 所以我们这一层**只负责把地址补全**(用户常常只输 `stratechery.com`,
/// 少了 `https://`),剩下的交给上游。自己再写一遍发现逻辑只会是个更差的
/// 复制品,而且要多打一次网络请求 —— 这是 L33 的同一个道理。
enum WebsiteFeedResolver {

	/// 把用户输入变成一条待订阅的结果。**不发任何网络请求。**
	///
	/// 地址对不对、有没有 feed,都留到按下订阅时由上游去判断并报错。
	static func candidate(for input: String) -> FeedSearchResult {

		let normalized = normalizedURLString(input)
		let host = URL(string: normalized)?.host ?? normalized

		return FeedSearchResult(
			kind: .website,
			title: host,
			subtitle: normalized,
			feedURL: normalized,
			homePageURL: normalized)
	}

	/// 补全协议头。`stratechery.com` → `https://stratechery.com`
	private static func normalizedURLString(_ input: String) -> String {

		var text = input.trimmingCharacters(in: .whitespacesAndNewlines)

		// 有些人会连 @ 或者引号一起粘进来
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
