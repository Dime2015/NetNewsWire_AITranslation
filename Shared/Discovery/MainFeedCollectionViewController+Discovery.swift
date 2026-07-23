//
//  MainFeedCollectionViewController+Discovery.swift
//  NetNewsWire
//
//  [发现] 本 fork 新增,上游没有这个文件。
//
//  订阅列表页右下角「+」的行为:弹一个两项选单(文件夹管理 / 搜索订阅源)。
//
//  ## 演进过程(改过三次了,记下来免得有人绕回去)
//
//  **第一版**:`+` 弹三项操作单 —— 添加订阅 / 添加文件夹 / 搜索订阅源。用户嫌啰嗦。
//  拆开看确实站不住:「添加文件夹」是**整理**动作、不是**添加内容源**,混在一起本身就不对;
//  而「添加订阅」和「搜索订阅源」**根本是同一件事**(粘网址本来就是搜索的一种)。
//
//  **第二版**(2026-07-21):「添加文件夹」挪去账户分组头的按钮,剩下两项合并 →
//  操作单只剩一项、没有存在意义 → `+` 直接进发现页。
//
//  **第三版(当前,2026-07-23)**:做了文件夹管理页之后,`+` 底下重新有了**两件不同的事**:
//    · **整理**已有的(文件夹管理)
//    · **添加**新的(搜索订阅源)
//  这两件事量级相当、都不是彼此的子集,所以选单重新有了意义。
//  同时分组头那个「新建文件夹」按钮**已拿掉**(功能并入管理页),
//  上游文件的改动因此收敛回「`add(_:)` 里一处」。
//  ⚠️ 别再把「新建文件夹」塞回分组头 —— 那是第二版的做法,已被用户否掉。
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

	/// [管理] 右下角 `+` 的选单:整理已有的 / 添加新的。
	func nnwShowAddMenu(from sender: UIBarButtonItem) {

		let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
		// iPad 上操作单是气泡,必须告诉它从哪个按钮弹出来,否则会崩
		alert.popoverPresentationController?.barButtonItem = sender

		alert.addAction(UIAlertAction(title: "文件夹管理", style: .default) { [weak self] _ in
			self?.nnwShowFolderManager()
		})
		alert.addAction(UIAlertAction(title: "搜索订阅源", style: .default) { [weak self] _ in
			self?.showFeedDiscovery()
		})
		alert.addAction(UIAlertAction(title: "取消", style: .cancel))

		present(alert, animated: true)
	}

	/// [管理] 打开文件夹 / 订阅源管理页。
	func nnwShowFolderManager() {

		let managerViewController = FolderManagerViewController()
		let navController = UINavigationController(rootViewController: managerViewController)

		// 和发现页一致的呈现方式:iPad 上 formSheet,iPhone 上全屏
		navController.modalPresentationStyle = .formSheet
		navController.preferredContentSize = AddFeedViewController.preferredContentSizeForFormSheetDisplay

		present(navController, animated: true)
	}

	/// 打开订阅发现页。
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
