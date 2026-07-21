//
//  MainFeedCollectionViewController+Discovery.swift
//  NetNewsWire
//
//  [发现] 本 fork 新增,上游没有这个文件。
//
//  把「搜索订阅源」这一项挂进订阅列表页右下角「+」按钮的操作单里。
//
//  ⚠️ **为什么入口做在这个操作单里,而不是在工具栏上加一个按钮**
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

	/// 往「+」的操作单里加一项「搜索订阅源」。
	///
	/// 由上游 `add(_:)` 方法里的一行调用。**必须在 cancel 那一项加进去之前调用** ——
	/// UIAlertController 会按加入顺序排列,取消项要留在最后。
	@objc func addDiscoveryAction(to alertController: UIAlertController) {

		let action = UIAlertAction(title: "搜索订阅源", style: .default) { [weak self] _ in
			self?.showFeedDiscovery()
		}
		alertController.addAction(action)
	}

	private func showFeedDiscovery() {

		let discoveryViewController = FeedDiscoveryViewController(style: .insetGrouped)
		let navController = UINavigationController(rootViewController: discoveryViewController)

		// 和上游添加订阅页保持一致的呈现方式:iPad 上用 formSheet,iPhone 上全屏
		navController.modalPresentationStyle = .formSheet
		navController.preferredContentSize = AddFeedViewController.preferredContentSizeForFormSheetDisplay

		present(navController, animated: true)
	}
}

#endif
