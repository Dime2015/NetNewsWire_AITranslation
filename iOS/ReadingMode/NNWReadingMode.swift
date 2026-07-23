//
//  NNWReadingMode.swift
//  NetNewsWire — AI 翻译 fork
//
//  [阅读档] 本 fork 新增,上游没有这个概念。
//
//  ## 这是什么
//
//  借鉴 Reeder:底部工具栏正中放一个**三档切换**(★星标 / 未读 / 全部),
//  它是一个**全局档位** —— 决定订阅列表里显示哪些源、每行显示什么数字、
//  点进去之后看到哪些文章。用户 2026-07-23 拍板。
//
//  ## 为什么要有这么一个「全局档」
//
//  上游本来的做法是**每个源各记一份**「只看未读」(`HidingReadArticlesState`),
//  而且默认值还不统一:文件夹默认只看未读、单个源默认看全部、
//  「全部未读」智能源强制只看未读且不许改。
//  用户要的是一拨全变,所以这里加一个总闸,**盖过**上游那张每源一份的表。
//
//  上游那个「漏斗」按钮(文章列表页右上角、订阅列表页右上角)管的是同一件事,
//  两个开关并存必然打架 → **按用户要求拿掉漏斗**(见 `showsPerFeedFilterButton`)。
//
//  ## 分阶段(2026-07-23)
//
//  - **Phase 1(当前)**:控件 + 未读 / 全部两档 + 拿掉行左滑 + 左右滑切换。
//    ★ 档**先摆在那里但点不动**(`starredEnabled = false`)。
//  - Phase 2:★ 档打通(每个源的星标数、只留有星标的源、点进去只看星标、
//    智能组换成一行「全部星标」)。
//  - Phase 3:三个档各自一张头图,切档时交叉淡入。
//

#if os(iOS)

import Foundation
import Account

// ⚠️ 档位本身(`NNWReadingMode`)和「左右滑该落到哪一档」那条规则住在
// **`ReadingModeRules.swift`** —— 那个文件不依赖 UIKit / Account,
// 所以能被 `tools/sim-readingmode.swift` 原样编译、离线跑决策表(L63 的纪律)。
// 本文件放的是需要依赖 app 环境的部分:持久化、通知、各处要问的问题。

extension NNWReadingMode {

	/// Phase 1 里点不动的档(★)。Phase 2 打开。
	var isAvailable: Bool {
		self != .starred || NNWReadingModeStore.starredEnabled
	}
}

/// 档位的存放处 + 通知中心。
@MainActor final class NNWReadingModeStore {

	static let shared = NNWReadingModeStore()

	/// 档位变了。订阅列表、文章列表都靠它刷新。
	static let didChangeNotification = Notification.Name("NNWReadingModeDidChange")

	/// ★ 档能不能用。**2026-07-23 Phase 2 已打开。**
	/// 配套的三件事都做好了才敢开:每个源的星标数(`NNWStarredIndex`)、
	/// 订阅列表只留有星标的行、文章列表只取星标(`FetchRequestOperation` 里的钩子)。
	/// (`nonisolated` 是因为 `NNWReadingMode.isAvailable` 在非主线程环境下也要读它;
	/// Bool 常量本身没有线程安全问题。)
	nonisolated static let starredEnabled = true

	/// 要不要显示上游那个「漏斗」按钮(每个源各自的只看未读)。
	/// **用户 2026-07-23 要求拿掉** —— 它和底部档位是同一件事,两个开关并存必然打架。
	/// 想还原成上游行为:把这里改成 true。
	nonisolated static let showsPerFeedFilterButton = false

	private static let defaultsKey = "nnwReadingMode"

	private(set) var mode: NNWReadingMode

	private init() {
		let saved = UserDefaults.standard.string(forKey: Self.defaultsKey) ?? ""
		let restored = NNWReadingMode(rawValue: saved) ?? .unread
		// 上次退出时停在★,而这一版★还没做完 → 回落到未读,免得开机就是个死档
		mode = restored.isAvailable ? restored : .unread
	}

	/// 换档。**同一个档重复设不会发通知**(避免白刷一遍列表)。
	@discardableResult
	func setMode(_ newMode: NNWReadingMode) -> Bool {
		guard newMode.isAvailable, newMode != mode else { return false }
		mode = newMode
		UserDefaults.standard.set(newMode.rawValue, forKey: Self.defaultsKey)
		NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
		return true
	}

	/// 相邻的下一档(左右滑用)。规则本体在 `ReadingModeRules.swift`,这里只负责喂"哪些档能用"。
	func neighbourMode(after current: NNWReadingMode, forward: Bool) -> NNWReadingMode? {
		NNWReadingMode.neighbour(after: current, forward: forward, isAvailable: { $0.isAvailable })
	}

	// MARK: - 各处要问的三个问题

	/// 订阅列表里**要不要藏掉没有未读的源**。
	/// (「未读」档 = 藏;「全部」档 = 不藏。★ 档 Phase 2 再说。)
	var hidesFullyReadFeeds: Bool {
		mode == .unread
	}

	/// 文章列表**要不要只取未读**。
	/// 返回 nil = 本档不表态,回落到上游每个源各自的记忆。
	var hidesReadArticles: Bool? {
		switch mode {
		case .unread:	return true
		case .all:		return false
		case .starred:	return nil		// Phase 2:改成"只取星标"
		}
	}

	/// 订阅列表每一行右边显示的数字。**0 = 那个标签自己会藏起来**(上游 cell 的行为)。
	///
	/// 用户 2026-07-23:「全部」档**不显示任何数字**,就是一份最完整的源列表。
	///
	/// ⚠️ **上游一共有 5 个地方会写这个数字**,漏一个就会出现"切到全部档、数字过一会儿自己回来"
	/// (装机实测撞到过:后台同步一完成,未读数变化的通知回调把数字又写了回去)。
	/// 五处:两个 `configure(...)`、`unreadCountDidChange` 里的两处、账户分组头。
	func displayedCount(for sidebarItem: SidebarItem) -> Int {
		switch mode {
		case .unread:	return sidebarItem.unreadCount
		case .all:		return 0
		case .starred:	return NNWStarredIndex.shared.starredCount(for: sidebarItem)
		}
	}

	/// 同上,给"已经拿到未读数、但手上没有 SidebarItem"的地方用(通知回调、账户分组头)。
	/// ★ 档下拿不到具体是哪个源 → 退回 0(= 不显示),
	/// 真正带 SidebarItem 的那条路会把星标数画上去。
	func displayedCount(unreadCount: Int) -> Int {
		switch mode {
		case .unread:	return unreadCount
		case .all:		return 0
		case .starred:	return 0
		}
	}

	/// 账户分组头上的数字(★ 档下是这个账户的星标总数)。
	func displayedAccountCount(for account: Account) -> Int {
		switch mode {
		case .unread:	return account.unreadCount
		case .all:		return 0
		case .starred:	return NNWStarredIndex.shared.starredCount(for: account)
		}
	}

	/// 订阅列表里这一行**该不该出现**。
	///
	/// - 未读 / 全部档:交给上游那套(「隐藏没有未读的源」由 `toggleReadFeedsFilter` 管),这里一律放行
	/// - ★ 档:只留有星标的源和文件夹;**星标数还没数完之前一律放行**(见 `NNWStarredIndex`)
	func shouldShowInFeedList(_ sidebarItem: SidebarItem) -> Bool {
		guard mode == .starred else { return true }
		return NNWStarredIndex.shared.shouldShowInStarredMode(sidebarItem)
	}
}

#endif
