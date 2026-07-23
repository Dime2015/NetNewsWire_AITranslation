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
		nnwPush(FolderManagerViewController())
	}

	/// 把页面**推进当前的导航栈**(而不是弹一张卡片)。
	///
	/// ⚠️ 2026-07-23 用户要求:这两个页面都从「卡片式弹出」改成「进入新页面」。
	/// 理由是它们都不是"填个东西就走"的小表单 —— 发现页要反复搜索、管理页要长时间整理,
	/// 卡片那种"临时浮在上面"的观感和实际用法不符,而且卡片顶部还压掉一截可视高度。
	///
	/// 改成推入之后连带三件事(都已处理,别改回去):
	///   ① 两个页面各自的「取消 / 完成」按钮都去掉了 —— 用系统返回按钮回上一页
	///   ② 管理页编辑模式的底部操作条走导航控制器的工具栏,
	///      离开时不用自己恢复:主列表页在 `viewWillAppear` 里本来就会把工具栏设回来
	///   ③ 主列表页一定在导航栈里(故事板决定的),所以这里不会拿到 nil
	private func nnwPush(_ viewController: UIViewController) {
		navigationController?.pushViewController(viewController, animated: true)
	}

	/// 打开订阅发现页。
	func showFeedDiscovery() {
		nnwPush(FeedDiscoveryViewController(style: .insetGrouped))
	}
}

#endif
