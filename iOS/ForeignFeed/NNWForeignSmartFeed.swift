//
//  NNWForeignSmartFeed.swift
//  NetNewsWire — AI 翻译 fork
//
//  [外文] 本 fork 新增,上游没有这个文件。用户 2026-08-08 第 5 件:
//  智能 Feed 那一组里多一个「**外文**」—— 一眼看到所有外文源的文章(它们才需要翻译)。
//
//  ## ⚠️ 这一条最要紧的是:**`Shared/SmartFeeds/` 一行都没改**
//
//  那是 CLAUDE.md 的 A 级禁区(绝对不碰)。能绕开是因为上游留了两个口子:
//
//  ```swift
//  var smartFeeds = [SidebarItem]()          // ← 是 var,不是 let
//  protocol SmartFeedDelegate: ...           // ← 是协议,谁都能实现
//  ```
//
//  于是做法变成:**在我们自己的文件里实现那个协议,启动时把一个 `SmartFeed` 追加进数组**。
//  上游的树(`SidebarTreeControllerDelegate`)每次都是现读 `smartFeeds` 造节点的,
//  所以追加完什么都不用通知,它自然就出现了。零改动、零 merge 冲突。
//
//  ## 文章是怎么取的
//
//  `FetchType` 里没有"若干个源"这一档(只有单个源 / 文件夹 / 星标 / 未读 / 今天),
//  所以这里**逐个外文源取一遍再并起来** —— 也就是协议默认实现的那条路走不通,
//  必须由本类型自己实现 `fetchArticles()` 那四个方法(协议要求 → 动态派发到我们这份)。
//
//  `fetchType` 那个属性仍要给一个值(协议必填),给的是 `.articleIDs([])`
//  —— **一个永远取不到东西的空查询**。它只有在有人绕过我们直接读 `fetchType` 时才会被用到,
//  给空集比给 `.unread` 安全:宁可什么都不返回,也不要悄悄返回一份错的。
//
//  ## 已知的两处小缺(都不致命,记在这儿免得以后当成 bug 查)
//
//  1. `SmartFeedsController.find(by:)` 认不出我们的标识(那个方法在禁区里,不能改)——
//     后果:**冷启动时"上次选中的是外文"这个状态恢复不了**,会退回默认页。
//  2. `SmartFeedHeaderCatalog` 没有它的头图 —— 这一页没有顶部大图,和文件夹页一样。
//

#if os(iOS)

import Foundation
import UIKit
import Account
import Articles
import ArticlesDatabase
import RSCore
import Images

@MainActor struct NNWForeignFeedDelegate: SmartFeedDelegate {

	var sidebarItemID: SidebarItemIdentifier? {
		SidebarItemIdentifier.smartFeed(String(describing: NNWForeignFeedDelegate.self))
	}

	let nameForDisplay = "外文"

	/// 见文件头:这是个**永远取不到东西的空查询**,真正取文章走下面四个方法。
	let fetchType: FetchType = .articleIDs(Set<String>())

	var smallIcon: IconImage? {
		guard let image = UIImage(systemName: "character.book.closed") else { return nil }
		return IconImage(image, isSymbol: true, isBackgroundSuppressed: true,
						 preferredColor: NNWAccentPalette.live)
	}

	func fetchUnreadCount(account: Account) async -> Int {
		// 源自己的未读数是账户一直在维护的,直接加起来就行 —— 不用再查一次库。
		NNWForeignFeedStore.shared.foreignFeeds(in: account).reduce(0) { $0 + $1.unreadCount }
	}

	// MARK: - 取文章(覆盖协议默认实现,理由见文件头)

	func fetchArticles() -> Set<Article> {
		var result = Set<Article>()
		for feed in NNWForeignFeedStore.shared.foreignFeeds() {
			result.formUnion(feed.fetchArticles())
		}
		return result
	}

	func fetchArticlesAsync() async -> Set<Article> {
		var result = Set<Article>()
		for feed in NNWForeignFeedStore.shared.foreignFeeds() {
			result.formUnion(await feed.fetchArticlesAsync())
		}
		return result
	}

	func fetchUnreadArticles() -> Set<Article> {
		var result = Set<Article>()
		for feed in NNWForeignFeedStore.shared.foreignFeeds() {
			result.formUnion(feed.fetchUnreadArticles())
		}
		return result
	}

	func fetchUnreadArticlesAsync() async -> Set<Article> {
		var result = Set<Article>()
		for feed in NNWForeignFeedStore.shared.foreignFeeds() {
			result.formUnion(await feed.fetchUnreadArticlesAsync())
		}
		return result
	}
}

// MARK: - 装配

@MainActor enum NNWForeignSmartFeed {

	/// 追加进去的那一个,留着做身份比对(`===`)。
	private(set) static var feed: SmartFeed?

	/// 启动时叫一次。**幂等** —— 叫第二次是空操作(L113)。
	///
	/// ⚠️ 必须在**侧栏第一次造树之前**叫。放在 `AppDelegate.didFinishLaunching` 里,
	/// 那时 scene 还没连上,`SceneCoordinator` 也还没建 —— 稳稳早于造树。
	static func install() {

		guard feed == nil else { return }

		let smartFeed = SmartFeed(delegate: NNWForeignFeedDelegate())
		feed = smartFeed
		SmartFeedsController.shared.smartFeeds.append(smartFeed)

		// 判定结果变了 → 未读数要重算(源的集合变了)。
		// `SmartFeed` 自己只听 `.UnreadCountDidChange`,听不到我们这条,所以补一次。
		NotificationCenter.default.addObserver(forName: NNWForeignFeedStore.didChangeNotification,
											   object: nil, queue: .main) { _ in
			MainActor.assumeIsolated {
				smartFeed.fetchUnreadCounts()
			}
		}
	}
}

#endif
