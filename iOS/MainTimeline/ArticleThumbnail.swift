//
//  ArticleThumbnail.swift
//  NetNewsWire-iOS
//
//  [界面] 本 fork 新增,上游没有这个文件。
//

import UIKit
import Articles
import Images
import RSCore
import RSParser

/// 只扫正文开头这么多字节。
/// 首图几乎必然在文章开头,而 Michael Tsai / Daring Fireball 这类
/// 引用型博客的正文可以有几十上百 KB —— 全扫会拖慢滚动。
private let maxBytesToScan = 100_000

/// 图片的宽/高属性小于这个值就认为不是配图(追踪像素、表情、小图标)。
private let minimumUsefulDimension = 64

/// 给文章列表提供「正文里的第一张图」当缩略图。
///
/// ## 为什么要自己抽图
///
/// 直觉上文章数据里应该有图片地址,`Article` 也确实有个 `imageURL` 字段 ——
/// **但它对普通 RSS/Atom 源永远是空的**:解析器
/// (`Modules/RSParser/.../XML/RSSItem.swift`)在构造 ParsedItem 时
/// 直接给 `imageURL` 传了 `nil`,只有 JSON Feed 才会填。
/// 所以首图只能从 `contentHTML` 里取。
///
/// ## 规则边界(重要)
///
/// CLAUDE.md 第 5 节原本规定「Swift 侧永远不解析 HTML」。
/// 2026-07-21 用户确认为「只读提取」开了一个边界明确的口子,本文件是它的唯一用途。
/// 必须守住:
/// - **只读**,不修改、不拼接、不生成任何 HTML,不把结果写回网页
/// - 用上游自带的 `HTMLScanner`,**不许用正则去匹配 HTML**
///
/// ## 取不到图怎么办
///
/// 安静地返回 nil,列表把文字铺满整宽即可。
/// 缩略图是锦上添花,**绝不能因为没图就让布局出错**。
@MainActor final class ArticleThumbnail {

	static let shared = ArticleThumbnail()

	/// 已解析过的文章 → 首图地址。
	/// 值为 nil 表示「已经找过了,确实没有图」—— 负缓存同样重要,
	/// 否则每次滚动都会把没有图的长文重新扫一遍。
	private var imageURLCache = [String: String?]()

	init() {
		// 跟上游 ArticleStringFormatter / ImageDownloader 一样的清缓存时机。
		NotificationCenter.default.addObserver(self, selector: #selector(emptyCaches), name: .appDidGoToBackground, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(emptyCaches), name: .lowMemory, object: nil)
	}

	@objc func emptyCaches() {
		imageURLCache.removeAll()
	}

	/// 这篇文章的缩略图。没有图、或图还没下载好,都返回 nil。
	///
	/// 图下载完成后 `ImageDownloader` 会发 `.imageDidBecomeAvailable` 通知,
	/// 列表收到后重新加载可见行,那时再调用本方法就能拿到图了。
	func thumbnail(for article: Article) -> UIImage? {
		guard let urlString = firstImageURL(for: article) else {
			return nil
		}
		guard let data = ImageDownloader.shared.image(for: urlString) else {
			return nil // 还没下好;下好会发通知
		}
		return UIImage(data: data)
	}

	/// 文章正文里第一张「看起来像配图」的图片地址。
	func firstImageURL(for article: Article) -> String? {
		let key = "\(article.accountID)/\(article.articleID)"
		if let cached = imageURLCache[key] {
			return cached // 注意:这里 cached 是 String?,nil 表示确认没有图
		}

		let result = Self.scanForFirstImageURL(html: article.contentHTML, baseURLString: article.rawLink)
		imageURLCache[key] = result
		return result
	}
}

// MARK: - 解析

private extension ArticleThumbnail {

	static func scanForFirstImageURL(html: String?, baseURLString: String?) -> String? {
		guard let html, !html.isEmpty else {
			return nil
		}

		var bytes = Array(html.utf8)
		if bytes.count > maxBytesToScan {
			bytes = Array(bytes[0..<maxBytesToScan])
		}

		let baseURL = baseURLString.flatMap { URL(string: $0) }
		let delegate = FirstImageDelegate(baseURL: baseURL)
		let scanner = HTMLScanner(delegate: delegate)
		scanner.parse(bytes)
		return delegate.imageURLString
	}
}

// MARK: - HTMLScanner 委托
//
// 写法完全照抄上游自己的 HTMLLinkParser(它用同一个 scanner 抽 <a>),
// 只是把目标从 <a href> 换成 <img src>。

private final class FirstImageDelegate: HTMLScannerDelegate {

	private let baseURL: URL?
	private(set) var imageURLString: String?

	init(baseURL: URL?) {
		self.baseURL = baseURL
	}

	func htmlScanner(_ scanner: HTMLScanner,
					 didStartTag name: ArraySlice<UInt8>,
					 attributes: HTMLAttributes,
					 selfClosing: Bool) {

		guard imageURLString == nil, isImageTag(name) else {
			return // 已经找到第一张了,后面的不管
		}

		// 明确标了尺寸而且很小的,是追踪像素 / 表情 / 小图标,跳过继续找。
		if isTooSmall(attributes) {
			return
		}

		guard let src = attributes["src"], !src.isEmpty else {
			return
		}

		// 相对地址要按文章链接补全,否则下载不了。
		guard let absolute = URL(string: src, relativeTo: baseURL)?.absoluteString else {
			return
		}

		// ImageDownloader 只认 http(s);data: 内联图直接跳过。
		guard absolute.hasPrefix("http://") || absolute.hasPrefix("https://") else {
			return
		}

		imageURLString = absolute
	}

	// MARK: 辅助

	private func isImageTag(_ name: ArraySlice<UInt8>) -> Bool {
		// "img" / "IMG",逐字节比,避免为每个标签建 String
		guard name.count == 3 else {
			return false
		}
		let i = name.startIndex
		return (name[i] | 0x20) == UInt8(ascii: "i")
			&& (name[i + 1] | 0x20) == UInt8(ascii: "m")
			&& (name[i + 2] | 0x20) == UInt8(ascii: "g")
	}

	/// 只在**显式写了**宽或高、且明显偏小时才判定为"不是配图"。
	/// 没写尺寸的一律放行 —— 宁可放过,不可错杀(大多数正常配图不写尺寸)。
	private func isTooSmall(_ attributes: HTMLAttributes) -> Bool {
		for attributeName in ["width", "height"] {
			if let raw = attributes[attributeName],
			   let value = Int(raw.trimmingCharacters(in: .whitespaces)),
			   value > 0,
			   value < minimumUsefulDimension {
				return true
			}
		}
		return false
	}
}
