//
//  NNWStarredIndex.swift
//  NetNewsWire — AI 翻译 fork
//
//  [阅读档] ★ 档要用的「每个源有几篇星标」。本 fork 新增,上游没有这个东西。
//
//  ## 上游为什么没有
//
//  上游只有「未读数」这一种计数(`UnreadCountProvider`),它是**账户层一直在维护**的。
//  星标没有对应的东西 —— 上游唯一和星标有关的是那个「已加星标」智能源,
//  它一次性把**全账户**的星标文章捞出来,从不按源分组。
//
//  ## 所以这里怎么做
//
//  一次 `account.fetchArticles(.starred())` 把全账户星标文章捞回来,**按 feedID 分组计数**。
//  代价可以接受:星标通常几十到几百篇(不是几万篇未读),一次查询的事,
//  而且**只在需要时才查**(切到★档、加/取消星标、刚启动)。
//  A 级禁区一行没碰 —— 只是调 Account 的公开取数接口。
//
//  ## ⚠️ 这是「异步到货的数据」,必须按 L53 的教训处理
//
//  第一次问它**必然是空的**(查询还没回来)。所以:
//  - 界面不能"问一次就算数",要在数据到货后**收到通知再画一遍**
//  - 反过来也不能"没数据就当作 0 篇星标"去过滤列表 —— 那会让★档一进去空空如也,
//    看起来像功能坏了。所以有 `hasLoaded`:**没装好之前不参与过滤**。
//

#if os(iOS)

import Foundation
import Account
import Articles

@MainActor final class NNWStarredIndex {

	static let shared = NNWStarredIndex()

	/// 星标数变了(重新数完了)。订阅列表收到就重画。
	static let didChangeNotification = Notification.Name("NNWStarredIndexDidChange")

	/// 数过一遍了没有。**没数过之前,★ 档不做任何过滤**(见文件头的说明)。
	private(set) var hasLoaded = false

	/// accountID → (feedID → 星标篇数)
	private var countsByFeed: [String: [String: Int]] = [:]

	/// 正在数。避免同一时间发起好几次(加星标时通知会连着来好几条)。
	private var isCounting = false
	/// 数的过程中又收到了"变了"的通知 → 这一轮结束后再数一遍。
	private var needsRecount = false

	private init() {
		// 星标状态变了就重新数。上游在加/取消星标时会发这条通知。
		NotificationCenter.default.addObserver(self, selector: #selector(statusesDidChange(_:)),
											   name: .StatusesDidChange, object: nil)
		// 账户增删、同步完成之后星标集合也可能变
		NotificationCenter.default.addObserver(self, selector: #selector(accountsDidChange(_:)),
											   name: .AccountStateDidChange, object: nil)
	}

	// MARK: - 查

	/// 这个源有几篇星标。没数过就返回 0(界面靠 `hasLoaded` 决定要不要信这个 0)。
	func starredCount(forFeedID feedID: String, accountID: String) -> Int {
		countsByFeed[accountID]?[feedID] ?? 0
	}

	/// 某个侧栏项要显示的星标数。
	/// - 源:它自己的
	/// - 文件夹:把里面的源加起来(**同一篇文章不会被算两次** —— 一个源只属于一个文件夹)
	/// - 账户 / 智能源:整个账户的合计
	func starredCount(for sidebarItem: SidebarItem) -> Int {
		guard let accountID = sidebarItem.account?.accountID else { return totalStarredCount() }

		if let feed = sidebarItem as? Feed {
			return starredCount(forFeedID: feed.feedID, accountID: accountID)
		}
		if let folder = sidebarItem as? Folder {
			return folder.topLevelFeeds.reduce(0) { $0 + starredCount(forFeedID: $1.feedID, accountID: accountID) }
		}
		return countsByFeed[accountID]?.values.reduce(0, +) ?? 0
	}

	/// 一个账户的星标合计(账户分组头上那个数)。
	func starredCount(for account: Account) -> Int {
		countsByFeed[account.accountID]?.values.reduce(0, +) ?? 0
	}

	func totalStarredCount() -> Int {
		countsByFeed.values.reduce(0) { $0 + $1.values.reduce(0, +) }
	}

	/// 这一项在★档下**该不该出现在订阅列表里**。
	/// 还没数完之前一律显示 —— 宁可多显示,也别让用户看到一片空白以为坏了。
	func shouldShowInStarredMode(_ sidebarItem: SidebarItem) -> Bool {
		guard hasLoaded else { return true }
		return starredCount(for: sidebarItem) > 0
	}

	// MARK: - 数

	@objc private func statusesDidChange(_ note: Notification) {
		// 只有星标相关的变化才值得重数。已读状态天天在变,跟着数纯属浪费。
		//
		// ⚠️ userInfo 里放的是 **`ArticleStatus.Key` 枚举本身**,不是字符串
		//(写第一版时我按字符串取,结果永远取不到 → 判断整个失效、每次已读变化都重数)。
		// 另外上游还有一处发这条通知时**根本没带 statusKey** —— 那种就老实重数一遍。
		if let key = note.userInfo?[Account.UserInfoKey.statusKey] as? ArticleStatus.Key, key != .starred {
			return
		}
		refresh()
	}

	@objc private func accountsDidChange(_ note: Notification) {
		refresh()
	}

	/// 重新数一遍。**并发保护**:正在数就记一笔,等这轮完了再数(L53:数据到货时机不可控)。
	func refresh() {

		guard !isCounting else {
			needsRecount = true
			return
		}
		isCounting = true

		Task { @MainActor in
			var result: [String: [String: Int]] = [:]

			for account in AccountManager.shared.activeAccounts {
				let starred = await account.fetchArticlesAsync(.starred(nil))
				var counts: [String: Int] = [:]
				for article in starred {
					counts[article.feedID, default: 0] += 1
				}
				result[account.accountID] = counts
			}

			countsByFeed = result
			hasLoaded = true
			isCounting = false

			NotificationCenter.default.post(name: Self.didChangeNotification, object: self)

			if needsRecount {
				needsRecount = false
				refresh()
			}
		}
	}
}

#endif
