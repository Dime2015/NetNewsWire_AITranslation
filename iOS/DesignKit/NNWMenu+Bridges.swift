//
//  NNWMenu+Bridges.swift
//  NetNewsWire — AI 翻译 fork
//
//  [外观] 本 fork 新增,上游没有这个文件。
//
//  NNWMenu 和上游各处对接的"桥":上游文件里只留一行调用,内容都住在这里。
//  (改动通道原则:实现住我们自己的文件,上游 diff 越小越好。)
//

#if os(iOS)

import UIKit
import Account

extension NNWMenu {

	/// 账户类型 → 图标:iCloud 用云、本机账户用手机、其余同步服务用地球。
	/// 文件夹管理页「在哪个账户下新建」、设置页 OPML 导入/导出选账户,共用这一处。
	/// (@MainActor:账户的属性是主线程隔离的,读它必须在主线程 —— 反正只有界面代码会调这里)
	@MainActor
	static func accountIcon(for account: Account) -> String {
		switch account.type {
		case .cloudKit: return "icloud"
		case .onMyMac: return "iphone"		// 枚举名是历史遗留,在 iPhone 上就是「我的 iPhone」账户
		default: return "globe"
		}
	}

	/// 「标记为已读」确认卡(替代上游 MarkAsReadAlertController 里的系统动作单)。
	///
	/// 上游那个确认框全 app 多处共用(时间线右滑「更多」里的三个标已读、工具栏全部标已读……),
	/// 文案与三个选项(确认 / 打开设置 / 取消)原样保留,只是换成品牌卡片。
	/// sourceType 沿用上游的约定(UIView / CGRect / UIBarButtonItem 都可能传进来):
	/// 是 UIView 就从它旁边弹,其余两种拿不到可靠的屏幕位置,居中弹(确认框居中本来也自然)。
	@MainActor
	static func showMarkAsReadConfirm<T>(in host: UIViewController,
										 coordinator: SceneCoordinator,
										 confirmTitle: String,
										 sourceType: T,
										 cancelCompletion: (() -> Void)?,
										 completion: @escaping () -> Void) where T: MarkAsReadAlertControllerSourceType {

		let title = NSLocalizedString("Mark As Read", comment: "Mark As Read")
		let message = NSLocalizedString("You can turn this confirmation off in Settings.",
										comment: "You can turn this confirmation off in Settings.")
		let cancelTitle = NSLocalizedString("Cancel", comment: "Cancel button")
		let settingsTitle = NSLocalizedString("Open Settings", comment: "Open Settings button")

		let anchor: NNWMenu.Anchor
		if let sourceView = sourceType as? UIView {
			anchor = .view(sourceView)
		} else {
			anchor = .center
		}

		NNWMenu.show(in: host, anchor: anchor, title: title, message: message, sections: [
			[NNWMenu.Item(title: confirmTitle, icon: "checkmark.circle") {
				completion()
			},
			NNWMenu.Item(title: settingsTitle, icon: "gearshape") {
				Task { @MainActor in
					coordinator.showSettings(scrollToArticlesSection: true)
				}
			}],
			[NNWMenu.Item(title: cancelTitle, icon: "xmark") {
				cancelCompletion?()
			}]
		], onCancel: cancelCompletion)		// 点卡片外面 = 取消,收尾回调(收回滑开的行)不能丢
	}
}

#endif
