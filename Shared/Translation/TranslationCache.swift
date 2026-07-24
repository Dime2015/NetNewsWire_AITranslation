//
//  TranslationCache.swift
//  NetNewsWire — AI 翻译 fork
//
//  译文的本地缓存(内存 + 磁盘)。
//
//  为什么要有它:离开文章再回来,页面会重新渲染,译文就没了。
//  没有缓存的话,同一篇文章每看一次都要重新花钱、重新等待。
//
//  键的设计(2026-07-19 第二版):
//    键 = 文章 ID + 模型 + 提示词版本 —— **不含正文哈希**。
//    这样不用读网页就能判断"这篇有没有缓存",供翻译按钮显示灰底提示。
//    正文是否变过,由条目里存的 bodyHash 在取用时校验:对不上就当没缓存。
//
//    - 换了模型     → 键变了 → 重新翻(用户切模型就是想对比效果,有意的)
//    - 提示词大改   → generation +1 → 全部旧缓存作废(旧译文是按旧规则翻的)
//    - 文章内容更新 → bodyHash 对不上 → 重新翻(不拿旧译文冒充新内容)
//
//  磁盘位置在系统的 Caches 目录 —— 系统空间紧张时可能清掉,清掉就重翻,无害。
//
//  ⚠️ 没有碰 Modules/ArticlesDatabase(CLAUDE.md 的 C 级禁区):
//  缓存完全存在我们自己的文件里,和上游数据库零交集。
//
//  这个文件不属于上游 NetNewsWire,是本 fork 新增的。
//

import Foundation
import CryptoKit

/// 一篇文章的译文缓存。有两种形态:
/// - **完整缓存**:`bodyHTML` 非空 —— 整篇翻译成功,下次直接秒开
/// - **未完成缓存**:`bodyHTML` 为 nil,内容在 `groups` 里 —— 上次翻到一半被打断,
///   下次点翻译时已翻过的组直接复用,只翻剩下的,不重复花钱
struct CachedTranslation: Codable, Sendable {

	/// 存入时原文正文(纯文字)的指纹。取用前校验:文章内容更新过 → 视为没缓存。
	let bodyHash: String

	let titleHTML: String?

	/// 整篇成功的完整译文。nil 表示这是"未完成缓存",看 groups。
	let bodyHTML: String?

	/// 未完成缓存:组号(字符串形式)→ 该组译文。完整缓存时为 nil。
	/// 组号能对上的前提是两次切分一致 —— 由 bodyHash 指纹把关;
	/// 万一某组安不回页面,那一组自动降级为重新翻译,不会出错。
	let groups: [String: String]?
}

@MainActor
enum TranslationCache {

	/// 提示词/缓存格式的"代号"。**大改提示词或指纹算法时把它 +1**,旧缓存全部自动作废 ——
	/// 否则老译文(按旧规则翻的)会一直从缓存里跳出来,新规则永远轮不到生效。
	/// 版本史:1=初版;2=专有名词一律保留英文(2026-07-19);
	/// 3=指纹从 HTML 改为纯文字,旧指纹全部无效(2026-07-19,见 L18);
	/// 4=提示词 v2(重写式翻译 + 反翻译腔指令 + 示范)+ 温度 0.45(2026-07-24);
	/// 5=先导块 500→750,组边界全部挪动 —— 旧的按组存的未完成缓存套到新边界会丢内容(2026-07-24);
	/// 6=切分器学会剥单子元素的壳(阅读模式整篇一组的 bug)—— 阅读模式文章的组边界全变(2026-07-24)。
	private nonisolated static let promptGeneration = "6"

	/// 磁盘上最多留多少篇。超了删最旧的。
	private nonisolated static let maxEntries = 50

	/// 内存缓存:本次运行期间命中最快。
	private static var memory: [String: CachedTranslation] = [:]

	/// 缓存键。纯函数,任何线程都能调。
	nonisolated static func articleKey(articleID: String, model: String) -> String {
		hash(articleID + "|" + model + "|" + promptGeneration)
	}

	/// 算一段内容的哈希(用于 bodyHash 校验)。
	nonisolated static func contentHash(_ content: String) -> String {
		hash(content)
	}

	/// 查缓存:先看内存,再看磁盘。都没有返回 nil。
	/// ⚠️ 调用方必须自己校验返回条目的 bodyHash。
	static func lookup(key: String) async -> CachedTranslation? {

		if let hit = memory[key] {
			return hit
		}

		let url = fileURL(for: key)
		let fromDisk = await Task.detached { () -> CachedTranslation? in
			guard let data = try? Data(contentsOf: url) else {
				return nil
			}
			return try? JSONDecoder().decode(CachedTranslation.self, from: data)
		}.value

		if let fromDisk {
			memory[key] = fromDisk
		}
		return fromDisk
	}

	/// 存缓存:内存立即生效,磁盘在后台慢慢写。
	static func store(key: String, _ value: CachedTranslation) {

		memory[key] = value

		Task.detached {
			try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
			if let data = try? JSONEncoder().encode(value) {
				try? data.write(to: fileURL(for: key), options: .atomic)
			}
			pruneIfNeeded()
		}
	}

	// MARK: - 磁盘

	private nonisolated static var directoryURL: URL {
		FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
			.appendingPathComponent("NNWTranslation", isDirectory: true)
	}

	private nonisolated static func fileURL(for key: String) -> URL {
		directoryURL.appendingPathComponent(key).appendingPathExtension("json")
	}

	private nonisolated static func hash(_ input: String) -> String {
		let digest = SHA256.hash(data: Data(input.utf8))
		return digest.map { String(format: "%02x", $0) }.joined()
	}

	/// 超过上限时删最旧的文件,免得缓存无限膨胀。
	private nonisolated static func pruneIfNeeded() {

		let fileManager = FileManager.default
		guard let files = try? fileManager.contentsOfDirectory(at: directoryURL,
															   includingPropertiesForKeys: [.contentModificationDateKey]),
			  files.count > maxEntries else {
			return
		}

		let sorted = files.sorted { a, b in
			let dateA = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
			let dateB = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
			return dateA < dateB
		}

		for url in sorted.prefix(files.count - maxEntries) {
			try? fileManager.removeItem(at: url)
		}
	}
}
