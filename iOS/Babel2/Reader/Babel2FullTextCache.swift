import Foundation
import CryptoKit
import Babel2Core

/// 阅读模式全文缓存（2026-09-27 用户反馈：开过阅读模式的文章，下次打开不该每次重新抓网页）。
///
/// 以前每次打开都在后台重新打开原网页、用 Readability 抽一遍正文（最多等 20 秒，没网就失败）。
/// 还有两个看不见的代价：网页只要变了一点点（「3 小时前」变「4 小时前」、文中推荐换了），
/// 抽出来的正文指纹就对不上，已经翻好的整篇译文会被当成「没有缓存」而重翻、重新花钱；
/// 按段落记下的阅读位置也可能对不准。
///
/// 现在：第一次抽成功就存下来，之后打开 / 再开阅读模式直接用存的，不联网、不等待。
/// - 只存抽成功的正文（文字 + 图片地址，不存图片本身），一篇通常十几到一百多 KB；单篇超过 2 MB 不存。
/// - 最多 300 篇，超过了删最久没用过的（用一次就算「用过」）。
/// - 放在系统的 Caches 目录：手机空间紧张时系统可能清掉，清掉了就重新抓，无害。
/// - 文章网址变了（同一篇文章换了地址）就当没缓存。
@MainActor
final class Babel2FullTextCache {
	static let shared = Babel2FullTextCache(directory: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
		.appendingPathComponent("Babel2FullText", isDirectory: true))

	static let maxEntries = 300
	static let maxEntryBytes = 2 * 1024 * 1024

	private struct Entry: Codable {
		var url: String
		var html: String
		var savedAt: Date
	}

	private let directory: URL
	private var didCheckReset = false

	init(directory: URL) {
		self.directory = directory
	}

	/// 取存着的全文；没有、网址对不上、读不出来都返回 nil。取到就把它标为「刚用过」。
	func html(for id: ArticleSnapshot.ID, url: URL) -> String? {
		resetIfRequested()
		let file = fileURL(for: id)
		guard let data = try? Data(contentsOf: file),
			  let entry = try? JSONDecoder().decode(Entry.self, from: data),
			  entry.url == url.absoluteString, !entry.html.isEmpty else { return nil }
		try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: file.path)
		return entry.html
	}

	/// 存下抽成功的全文。
	func store(_ html: String, for id: ArticleSnapshot.ID, url: URL) {
		resetIfRequested()
		guard !html.isEmpty else { return }
		let entry = Entry(url: url.absoluteString, html: html, savedAt: Date())
		guard let data = try? JSONEncoder().encode(entry), data.count <= Self.maxEntryBytes else { return }
		try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		try? data.write(to: fileURL(for: id), options: .atomic)
		trim()
	}

	/// 超过上限：删最久没用过的。
	private func trim() {
		let keys: [URLResourceKey] = [.contentModificationDateKey]
		guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys),
			  files.count > Self.maxEntries else { return }
		func date(_ url: URL) -> Date {
			(try? url.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? .distantPast
		}
		let sorted = files.sorted { date($0) < date($1) }
		for file in sorted.prefix(files.count - Self.maxEntries) {
			try? FileManager.default.removeItem(at: file)
		}
	}

	/// 文件名 = 文章编号的哈希（编号里可能有斜杠等不能当文件名的字符）。
	private func fileURL(for id: ArticleSnapshot.ID) -> URL {
		let key = "\(id.accountID)|\(id.feedID)|\(id.articleID)"
		let digest = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
		return directory.appendingPathComponent(digest + ".json")
	}

	/// 仅供自动测试：启动时带 BABEL2_RESET_READING_POSITIONS=1（清空记住的位置那个开关）时一并清空，
	/// 让真实数据 UI 测试每次都从「没存过全文」开始。
	private func resetIfRequested() {
		guard !didCheckReset else { return }
		didCheckReset = true
		if ProcessInfo.processInfo.environment["BABEL2_RESET_READING_POSITIONS"] == "1" {
			try? FileManager.default.removeItem(at: directory)
		}
	}
}
