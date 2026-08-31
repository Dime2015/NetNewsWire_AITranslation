//
//  NNWTitleTranslationStore.swift
//  NetNewsWire — AI 翻译 fork
//
//  [翻译] 本 fork 新增,上游没有这个文件。标题翻译(T32①)的两份存储:
//
//  1. `NNWTitleTranslationStore` —— **哪些源打开了「标题翻译成中文」**。
//     存 UserDefaults,键 = "账户ID|源ID"。
//     ⚠️ 键必须带账户前缀 —— FeedOrderStore 没带,结果两个账户里同名的东西共用设置,
//     那是本项目留过案底的反面教材(见 NOTES-todo T32 的设计说明)。
//
//  2. `NNWTitleTranslationCache` —— **翻好的标题**,磁盘 + 内存。
//     键 = 提示词代号 | 文章ID | 模型 | 标题指纹:
//     - 换模型 → 键变 → 重翻(用户切模型就是想对比效果)
//     - 文章标题被源更新 → 指纹变 → 重翻(不拿旧译文冒充新标题)
//     - 提示词大改 → 代号 +1 → 全部作废
//     磁盘放系统 Caches 目录:被系统清掉就重翻,无害。
//     上限 4000 条,超了砍最老的 —— 标题很短,4000 条也就几百 KB。
//
//  ⚠️ 没有碰 Modules/Account 与 ArticlesDatabase(A/C 级禁区):
//  开关和译文全部存在我们自己的地方,上游数据零交集。
//

import Foundation
import CryptoKit

// MARK: - 哪些源开了标题翻译

@MainActor final class NNWTitleTranslationStore {

	static let shared = NNWTitleTranslationStore()

	private static let defaultsKey = "nnwTitleTranslationFeeds"

	/// "账户ID|源ID" 的集合。源被删掉后键会留下来 —— 无害(不会再有它的文章),
	/// 重新订阅同一个源时设置还在,反而是符合直觉的。
	private var enabledKeys: Set<String>

	private init() {
		enabledKeys = Set(UserDefaults.standard.stringArray(forKey: Self.defaultsKey) ?? [])
	}

	private static func key(accountID: String, feedID: String) -> String {
		"\(accountID)|\(feedID)"
	}

	func isEnabled(accountID: String, feedID: String) -> Bool {
		enabledKeys.contains(Self.key(accountID: accountID, feedID: feedID))
	}

	func setEnabled(_ flag: Bool, accountID: String, feedID: String) {
		let key = Self.key(accountID: accountID, feedID: feedID)
		if flag {
			enabledKeys.insert(key)
		} else {
			enabledKeys.remove(key)
		}
		UserDefaults.standard.set(Array(enabledKeys).sorted(), forKey: Self.defaultsKey)
	}

	/// 有没有任何一个源开着 —— 都没开的话,列表那条路可以一分钱判断都不花
	var hasAnyEnabled: Bool {
		!enabledKeys.isEmpty
	}
}

// MARK: - 翻好的标题

@MainActor final class NNWTitleTranslationCache {

	static let shared = NNWTitleTranslationCache()

	/// 提示词的"代号"。大改提示词时 +1,旧缓存全部自动作废(和 TranslationCache 同一套路)。
	private static let promptGeneration = "1"

	private static let maxEntries = 4000
	/// 超限时一次砍掉这么多最老的 —— 免得每加一条就砍一条,反复搬数组
	private static let evictionBatch = 500
	private static let writeQueue = DispatchQueue(label: "com.netnewswire.title-translation-cache", qos: .utility)

	/// 键 → 译文。顺序由 `order` 记(先进先出,近似 LRU 够用了 —— 老文章会自然淡出列表)
	private var entries: [String: String] = [:]
	private var order: [String] = []
	private var loaded = false

	private init() {}

	func preload() {
		loadIfNeeded()
	}

	private static var fileURL: URL {
		let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
		return caches.appendingPathComponent("nnw-title-translations.json")
	}

	private static func key(articleID: String, title: String, model: String) -> String {
		let digest = SHA256.hash(data: Data(title.utf8))
		let hash8 = digest.map { String(format: "%02x", $0) }.joined().prefix(8)
		return "\(promptGeneration)|\(articleID)|\(model)|\(hash8)"
	}

	func translation(articleID: String, title: String, model: String) -> String? {
		loadIfNeeded()
		return entries[Self.key(articleID: articleID, title: title, model: model)]
	}

	func store(_ translated: String, articleID: String, title: String, model: String) {
		loadIfNeeded()
		let key = Self.key(articleID: articleID, title: title, model: model)
		if entries[key] == nil {
			order.append(key)
		}
		entries[key] = translated
		if entries.count > Self.maxEntries {
			let toEvict = order.prefix(Self.evictionBatch)
			for old in toEvict {
				entries.removeValue(forKey: old)
			}
			order.removeFirst(min(Self.evictionBatch, order.count))
		}
	}

	/// 写盘。调用方在**一批翻译全部入库后**调一次,不必每条都写。
	func flush() {
		loadIfNeeded()
		let pairs = order.compactMap { key -> [String]? in
			guard let value = entries[key] else { return nil }
			return [key, value]
		}
		guard let data = try? JSONSerialization.data(withJSONObject: pairs) else { return }
		let url = Self.fileURL
		Self.writeQueue.async {
			try? data.write(to: url, options: .atomic)
		}
	}

	private func loadIfNeeded() {
		guard !loaded else { return }
		loaded = true
		guard let data = try? Data(contentsOf: Self.fileURL),
			  let pairs = try? JSONSerialization.jsonObject(with: data) as? [[String]] else {
			return
		}
		for pair in pairs where pair.count == 2 {
			if entries[pair[0]] == nil {
				order.append(pair[0])
			}
			entries[pair[0]] = pair[1]
		}
	}
}
