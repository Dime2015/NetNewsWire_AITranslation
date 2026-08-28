//
//  NNWSoftGlassBackButton.swift
//  NetNewsWire — AI 翻译 fork
//
//  [外观] 本 fork 新增(2026-08-09)。把导航栏左上角那颗**系统返回键**换成我们自己的玻璃圆钮。
//
//  ## 为什么要换
//
//  用户 2026-08-09:「上下部分的各个控件……圆形控件的大小,都不太一致」。
//  盘点下来,这一页我们自己画的控件(右上胶囊、底部三档、底部两颗圆钮)**全部读同一个
//  尺寸真源** `NNWSoftMaterial.controlDiameter`(40pt),是一致的;
//  **唯一不归这个真源管的就是返回键** —— 它是系统画的,大小和材质我们一个都碰不到。
//  换成我们自己的,那条"唯一真源"才真的覆盖整屏。
//
//  ## ⚠️ 换掉之后必须自己把「边缘侧滑返回」捡回来
//
//  UIKit 有一条不写在明面上的规矩:**一旦设了自定义的 `leftBarButtonItem`,
//  `interactivePopGestureRecognizer` 就不再工作** —— 它的默认 delegate 会一直说 no
//  (系统的想法是"你都自己接管返回了,我不知道你还认不认得侧滑")。
//  不管这件事的话,用户会发现"从左边缘往右滑返回"突然失灵,而且**没有任何报错**,
//  正是本项目最怕的那种静默退化(L19 那一族)。
//
//  修法是给那个手势换一个我们自己的 delegate,规则只有一条:**栈里不止一页才允许**。
//  这和系统默认行为完全一致 —— 栈底自然不该能返回,上面那些就该能。
//
//  ## 🔴 2026-08-09:第一版**静默失效了整整一轮**,病根记在 `nnwBackPopTarget` 上
//
//  一句话:**"我的导航控制器"不等于"那个真正在推页面的栈"** ——
//  文章列表页住在分栏控制器自己那一列的导航控制器里,那个栈只有它一个,
//  真正的「列表 → 文章」栈是**父导航控制器**。守卫写成"自己那个栈够深"就恒不成立,
//  而屏幕上还有系统那颗返回键顶着,**看起来像是做好了**。
//  所以出栈、接管侧滑手势,统统要对 `nnwBackPopTarget` 来。
//
//  ⚠️ `UIGestureRecognizer.delegate` 是 **weak** 的 —— delegate 对象必须有人强引用住,
//  否则设完就被释放,手势会退回"没有 delegate"(那等于永远允许,在栈底滑一下能把
//  导航栈搞卡死)。这里把它挂在导航控制器身上的关联对象里。
//

#if os(iOS)

import UIKit

extension UIViewController {

	private static var nnwPopGestureDelegateKey: UInt8 = 0

	/// 该对**谁**出栈 —— 也是"能不能返回"的判据。
	///
	/// 🔴 **这里是 2026-08-09 那个静默失效的病根**(埋日志才查出来,L124 同一个形状):
	/// 原来写的是 `navigationController.viewControllers.count > 1`,而实测(iOS 27):
	///
	/// ```
	/// nav=UINavigationController  栈深=1  父=UINavigationController
	/// ```
	///
	/// 文章列表页住在**分栏控制器自己那一列的导航控制器**里,那个栈**只有它一个** ——
	/// 真正装着「列表 → 文章」的是**父导航控制器**。于是那个守卫恒不成立,
	/// 返回键**一次都没装上**,而屏幕上那颗是系统画的,看起来"好像没坏"。
	///
	/// 📌 **文章页早就知道这件事**(`NNWArticlePaging.nnwPopTargetNavigationController`
	/// 逐字写着同一个事实),我当时没照着做。判据:
	/// **本工程里"我的导航控制器"从来不等于"那个真正在推页面的栈",两处都要问一遍父。**
	private var nnwBackPopTarget: UINavigationController? {
		guard let nav = navigationController else { return nil }
		if nav.viewControllers.count > 1 { return nav }
		if let parent = nav.parent as? UINavigationController, parent.viewControllers.count > 1 { return parent }
		return nil
	}

	/// 把本页的返回键换成玻璃圆钮,并保住边缘侧滑返回。**幂等**,可以放心挂在会被反复调用的地方。
	///
	/// 没有可返回的地方时什么都不做 —— 首页就是这种情况。
	func nnwInstallSoftGlassBackButton() {

		guard NNWSoftMaterial.isEnabled, nnwBackPopTarget != nil else { return }

		// 幂等:已经装过就只把侧滑那条再确认一遍(转场之后系统可能把 delegate 换回去)
		if navigationItem.leftBarButtonItem?.customView is NNWSoftGlassButton {
			nnwKeepInteractivePopGesture()
			return
		}

		let icon = UIImage(systemName: "chevron.backward",
						   withConfiguration: UIImage.SymbolConfiguration(
							pointSize: NNWSoftMaterial.iconPointSize, weight: .medium)) ?? UIImage()

		let button = NNWSoftGlassButton(icon: icon)
		button.addTarget(self, action: #selector(nnwSoftGlassBackTapped), for: .touchUpInside)
		// ⚠️ **直接写中文,不走 `NSLocalizedString`** —— 那样 Xcode 会往上游的
		// `Shared/Localizable.xcstrings` 里自动加一条,平白给一个高频改动的上游文件
		// 增加冲突面(第 2 节:保持可 merge 是最高优先级)。
		// 本 fork 自己新增的控件一向直接写中文(「源信息与设置」「搜索文章」都是)。
		button.accessibilityLabel = "返回"

		let item = UIBarButtonItem(customView: button)
		item.nnwHideSystemGlassCapsule()
		item.accessibilityLabel = button.accessibilityLabel
		navigationItem.leftBarButtonItem = item
		// 双保险:有些路径下系统仍会自己塞一颗返回键进来,那样就成了两颗
		navigationItem.hidesBackButton = true

		nnwKeepInteractivePopGesture()
	}

	@objc private func nnwSoftGlassBackTapped() {
		// ⚠️ 对**父**导航栈出栈 —— 对自己那个只有一页的栈出栈什么都不会发生
		// (文章页的右滑手势 2026-08-08 就栽在这:手势识别了、日志也有,就是没反应)
		nnwBackPopTarget?.popViewController(animated: true)
	}

	/// 让「从屏幕左边缘往右滑 = 返回」在自定义返回键之后继续有效。
	private func nnwKeepInteractivePopGesture() {

		// ⚠️ 要接管的是**真正在推页面的那个栈**的手势,不是自己那一列的
		// (自己那个栈只有一页,它的手势本来就不该工作)。
		guard let nav = nnwBackPopTarget,
			  let gesture = nav.interactivePopGestureRecognizer else { return }

		// delegate 是 weak 的,得有人抱着 —— 挂在**导航控制器**身上(手势也是它的,生命周期对齐)
		let delegate: NNWPopGestureDelegate
		if let existing = objc_getAssociatedObject(nav, &Self.nnwPopGestureDelegateKey) as? NNWPopGestureDelegate {
			delegate = existing
		} else {
			delegate = NNWPopGestureDelegate()
			objc_setAssociatedObject(nav, &Self.nnwPopGestureDelegateKey, delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
		}
		delegate.navigationController = nav
		// 幂等:已经是我们的就别重复设(设 delegate 会让手势重置状态,滑到一半时会断)
		if gesture.delegate !== delegate {
			gesture.delegate = delegate
		}
	}
}

/// 边缘侧滑返回的开始条件:**栈里不止一页**。
///
/// 只有这一条规则,是刻意的 —— 系统默认行为就是这样,我们只是把"因为有自定义返回键
/// 所以一律不准"那条额外的限制去掉,不引入任何新规矩。
private final class NNWPopGestureDelegate: NSObject, UIGestureRecognizerDelegate {

	weak var navigationController: UINavigationController?

	func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
		(navigationController?.viewControllers.count ?? 0) > 1
	}

	/// ⚠️ **不允许和别人同时识别**(默认就是 false,这里写出来是为了讲清楚为什么不能改成 true):
	/// 这条手势驱动的是**导航栈的转场**。让它和列表滚动、行左滑一起识别,
	/// 就会出现"滑到一半又被别人接管"的半截转场 —— 那是本项目在 L121 反复吃过的
	/// 「半分最贵」。要么这一下是返回,要么不是。
	func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
						   shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
		false
	}
}

#endif
