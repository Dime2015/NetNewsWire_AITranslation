//
//  NNWTimelineScrollMemory.swift
//  NetNewsWire — AI 翻译 fork
//
//  [阅读位置] 本 fork 新增,上游没有这个文件。
//
//  ## 这是干什么的(用户 2026-08-08 的第 3 件)
//
//  「每个订阅源各自记住自己滚到哪了」—— 从 A 源翻到 B 源再翻回 A 源,
//  A 源应该还停在刚才那一篇,而不是弹回最顶上。
//
//  ## ⚠️ 存的是**文章 ID**,不是像素偏移(这一条是设计的核心,别改回去)
//
//  像素偏移在这个 app 里必然错位,三个原因都能单独把它毁掉:
//  1. 行高不是固定的(标题几行、有没有缩略图、动态字体大小都会变);
//  2. 列表内容会变(新文章插到最前面、已读被过滤掉),同一个 y 坐标下一次是另一篇;
//  3. 「只看未读 / 全部 / ★」三档会整片换掉列表。
//  存文章 ID 则天然免疫:找得到那篇就滚到它,找不到(被读掉了/被过滤了)就老实回顶。
//
//  ## 存哪儿
//
//  UserDefaults,键 = 侧栏项标识(账户ID|源ID)。跨次启动也记得。
//  上限 300 条,超了砍最老的 —— 一条也就几十字节,300 个源足够任何人用。
//
//  ⚠️ 没有碰 Modules/Account 与 ArticlesDatabase(A/C 级禁区):
//  这里只**读**文章 ID 当字符串用,一个上游的存储都没动。
//

#if os(iOS)

import Foundation
import UIKit
import Account

@MainActor final class NNWTimelineScrollMemory {

	static let shared = NNWTimelineScrollMemory()

	private static let defaultsKey = "nnwTimelineScrollPositions"
	/// 记录上限。超了从最老的开始砍。
	private static let maxEntries = 300

	/// 侧栏项键 → 停在哪一篇的文章 ID
	private var positions: [String: String] = [:]
	/// 写入顺序(近似 LRU)。最后一个是最新写的。
	private var order: [String] = []
	/// 有没有还没写盘的改动
	private var dirty = false

	/// 「点顶栏回顶」之前停在哪一篇。**只活在本次会话里**,不写盘 ——
	/// 它是一次交互中间的临时状态,重启之后再回顶应该是"干净的一次"。
	private var topTapReturn: [String: String] = [:]

	private init() {
		if let saved = UserDefaults.standard.array(forKey: Self.defaultsKey) as? [[String]] {
			for pair in saved where pair.count == 2 {
				if positions[pair[0]] == nil {
					order.append(pair[0])
				}
				positions[pair[0]] = pair[1]
			}
		}
		// 退到后台时统一写盘 —— 滚动时每帧写 UserDefaults 是纯浪费。
		NotificationCenter.default.addObserver(self, selector: #selector(flush),
											   name: UIApplication.didEnterBackgroundNotification, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(flush),
											   name: UIApplication.willResignActiveNotification, object: nil)
	}

	// MARK: - 键

	/// 把侧栏项标识变成一个稳定的字符串键。
	///
	/// ⚠️ **不要用 `SidebarItemIdentifier.description`** —— 上游那个实现里
	/// `"(typeName): ..."` 少了 `\`,三种类型打出来的前缀是同一个字面量,
	/// 拿它当键会让「智能源」和「文件夹」有机会撞车。自己写一份最省心。
	static func key(for sidebarItem: SidebarItem?) -> String? {
		guard let identifier = sidebarItem?.sidebarItemID else { return nil }
		switch identifier {
		case .smartFeed(let id):					return "smart|\(id)"
		case .feed(let accountID, let feedID):		return "feed|\(accountID)|\(feedID)"
		case .folder(let accountID, let name):		return "folder|\(accountID)|\(name)"
		}
	}

	// MARK: - 停在哪一篇

	func rememberedArticleID(for key: String) -> String? {
		positions[key]
	}

	/// 记下这个源当前停在哪一篇。传 nil = 忘掉(比如滚回了最顶上)。
	func remember(_ articleID: String?, for key: String) {
		if let articleID {
			guard positions[key] != articleID else { return }
			if positions[key] == nil {
				order.append(key)
			}
			positions[key] = articleID
		} else {
			guard positions[key] != nil else { return }
			positions.removeValue(forKey: key)
			order.removeAll { $0 == key }
		}
		if positions.count > Self.maxEntries {
			let overflow = positions.count - Self.maxEntries
			for old in order.prefix(overflow) {
				positions.removeValue(forKey: old)
			}
			order.removeFirst(min(overflow, order.count))
		}
		dirty = true
	}

	// MARK: - 点顶栏的那一来一回

	/// 第一次点顶栏:记下"原位",之后系统把列表滚到顶。
	func setTopTapReturn(_ articleID: String?, for key: String) {
		topTapReturn[key] = articleID
	}

	/// 只看一眼,不清掉(排查用)。
	func peekTopTapReturn(for key: String) -> String? {
		topTapReturn[key]
	}

	/// 第二次点顶栏:取出"原位"并清掉(只回去一次)。
	func takeTopTapReturn(for key: String) -> String? {
		defer { topTapReturn[key] = nil }
		return topTapReturn[key]
	}

	// MARK: - 「正在恢复」这段时间

	/// 正在给哪个源恢复位置。**在这段时间里不许记录新位置** ——
	///
	/// ⚠️ 这不是保险,是必需的(2026-08-08 第一版就死在这):
	/// 换源时列表会先被清空再填上,`contentOffset` 归零 → `scrollViewDidScroll` 触发 →
	/// 我们把"停在最顶上"记下去,**刚要恢复的那条记录当场被自己抹掉**。
	private var restoringKey: String?

	func isRestoring(_ key: String) -> Bool { restoringKey == key }

	func beginRestore(_ key: String) { restoringKey = key }

	func endRestore(_ key: String) {
		if restoringKey == key { restoringKey = nil }
	}

	// MARK: - 写盘

	@objc func flush() {
		guard dirty else { return }
		dirty = false
		let pairs = order.compactMap { key -> [String]? in
			guard let value = positions[key] else { return nil }
			return [key, value]
		}
		UserDefaults.standard.set(pairs, forKey: Self.defaultsKey)
	}
}

#endif
