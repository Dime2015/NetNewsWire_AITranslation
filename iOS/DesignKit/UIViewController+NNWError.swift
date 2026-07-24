//
//  UIViewController+NNWError.swift
//  NetNewsWire — AI 翻译 fork
//
//  [外观] 本 fork 新增,上游没有这个文件。
//
//  把全 app 的「错误提示弹窗」换成自绘品牌卡片(NNWMenu 的居中形态)。
//
//  ## 原理:同签名"遮蔽"(这是本文件的全部魔法,必须看懂再动)
//
//  上游的错误弹窗都汇到 RSCore 模块的
//  `UIViewController.presentError(title:message:dismiss:)`(一个系统白 alert)。
//  RSCore 是上游的模块,按项目规矩不改它。但 Swift 有一条决议规则:
//  **调用点所在模块里如果有同签名的方法,优先用本模块的**。
//  所以在 app 自己这边(本文件)定义一个一模一样签名的 presentError,
//  app 里 15 处调用点(设置页、订阅页、主题导入……)就会**全部自动改走这里** ——
//  上游一行都不用改,合并永远不冲突。
//
//  ⚠️ 代价(记着):RSCore **模块内部**若有代码自己调 presentError,走的仍是它原来的白 alert
//  (遮蔽只对 app 模块的调用点生效)。查过:RSCore 内部没有人调它,放心。
//  ⚠️ 若上游将来改了 RSCore 那边的签名,这里不会自动跟上 —— 合并后 ⌘F 搜一下
//  「presentError(title:」确认调用点还指到这里(编译不过反而是好事,会逼你看)。
//

#if os(iOS)

import UIKit

extension UIViewController {

	/// 错误 / 提示卡片:居中的暖纸卡,标题 + 说明 + 一个「好」。
	/// 签名与 RSCore 的完全一致(title / message / dismiss),这是遮蔽生效的前提,别改。
	func presentError(title: String, message: String, dismiss: (() -> Void)? = nil) {
		NNWMenu.show(in: self, anchor: .center, title: title, message: message, sections: [[
			NNWMenu.Item(title: NSLocalizedString("OK", comment: "OK button"), icon: nil) {
				dismiss?()
			}
		]], onCancel: dismiss)		// 点卡片外面关掉也算"看完了",dismiss 回调不能丢
	}
}

#endif
