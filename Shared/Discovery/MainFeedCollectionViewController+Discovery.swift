//
//  MainFeedCollectionViewController+Discovery.swift
//  NetNewsWire
//
//  [发现] 本 fork 新增,上游没有这个文件。
//
//  订阅列表页右下角「+」的行为:直接打开订阅发现页。
//
//  ## 演进过程(2026-07-21 一天之内改了两次,记下来免得有人改回去)
//
//  第一版:`+` 弹一个操作单,里面三项 —— 添加订阅 / 添加文件夹 / 搜索订阅源。
//  用户反馈这套很啰嗦。拆开看确实站不住:
//    · 「添加文件夹」是**整理**动作,不是**添加内容源**,混在一起本身就不对
//      → 已移到账户分组头右侧的按钮上(见 iOS/MainFeed/AddFolderHeaderButton.swift)
//    · 「添加订阅」和「搜索订阅源」**根本是同一件事** ——
//      粘一个网址本来就是搜索的一种,发现页两种输入都收
//  于是操作单只剩一项,存在的意义就没有了 → `+` 直接进发现页。
//
//  ⚠️ **为什么入口不是在工具栏上加一个按钮**
//
//  底部工具栏在故事板里正好是 3 项:[设置] ⟷ [+]。
//  而上游的 configureToolbarWithProgressView() 里写着:
//
//      let expectedItemCount = 3
//      guard var items = toolbarItems, items.count == expectedItemCount else { return }
//
//  往工具栏加第 4 个按钮 → 这个守卫直接返回 → **刷新进度条永远装不上**。
//  不报错、不崩溃,静默消失 —— 正是 L19 那类「一旦发生就再也不恢复」的坑。
//
//  改挂进操作单之后:上游文件的改动只有一行(调用下面这个方法),
//  而且完全没有碰任何数量不变量。用户已于 2026-07-21 确认此方案。
//

#if os(iOS)

import UIKit

extension MainFeedCollectionViewController {

	/// [界面] 账户分组头上那个「新建文件夹」按钮的动作。
	///
	/// 直接复用上游现成的流程 —— 和原来 `+` 菜单里那一项走的是同一个入口,
	/// 只是换了个地方点。所以行为完全一致,不需要另写一套。
	@objc func nnwAddFolderTapped() {
		coordinator.showAddFolder()
	}

	/// 打开订阅发现页。由上游 `add(_:)`(右下角的 `+`)直接调用。
	func showFeedDiscovery() {

		let discoveryViewController = FeedDiscoveryViewController(style: .insetGrouped)
		let navController = UINavigationController(rootViewController: discoveryViewController)

		// 和上游添加订阅页保持一致的呈现方式:iPad 上用 formSheet,iPhone 上全屏
		navController.modalPresentationStyle = .formSheet
		navController.preferredContentSize = AddFeedViewController.preferredContentSizeForFormSheetDisplay

		present(navController, animated: true)
	}
}

#endif
