//
//  MainTimelineModernViewController+ReadingMode.swift
//  NetNewsWire — AI 翻译 fork
//
//  [阅读档] 把三档控件也装到**文章列表页**的底部工具栏上(2026-07-23 用户要求)。
//  本 fork 新增文件,上游没有。
//
//  ## 它占的是「搜索文章」原来的位置
//
//  iOS 26 上这一页的底部工具栏是:
//  ```
//  [全部标为已读]  ⟷  [搜索文章(输入框)]  ⟷  [下一条未读]
//  ```
//  中间那个是 `navigationItem.searchBarPlacementBarButtonItem` ——
//  iOS 26 的新玩法:把系统搜索框直接摆进工具栏。用户要把那块地方让给三档控件。
//
//  ## ⚠️ 搜索没有被删掉,是**换了个摆法**
//
//  搜索仍在,只是从"常驻输入框"变成**导航栏右上角一个放大镜按钮**
//  (`preferredSearchBarPlacement = .integratedButton`,iOS 26 才有的摆法,
//  已查过 SDK 头文件确认存在 —— L70 的教训:别凭印象用系统能力)。
//  点它就展开成输入框,搜完收起。
//
//  右上角原本是「漏斗」,已经被三档接管拿掉了,所以那儿正好空着 ——
//  **净变化为零:漏斗走了,放大镜来了。**
//
//  ## 这一页刻意**不做**左右滑切档
//
//  订阅列表页能做,是因为那一页的行左滑已经拿掉了。
//  而这一页的行左滑是「加星标 / 标为已读」—— 有用,用户也没要求拿掉。
//  两者共存必然打架,所以这一页只有控件,没有手势。
//

#if os(iOS)

import UIKit

extension MainTimelineModernViewController {

	/// 造本页那条三档控件的工具栏项。**由上游 `configureToolbar()` 里"一行换一行"调用**
	///(原来那行是 `navigationItem.searchBarPlacementBarButtonItem`)。
	@objc func nnwReadingModeToolbarItem() -> UIBarButtonItem {
		nnwReadingModeBarItem { [weak self] mode in
			self?.nnwSelectReadingMode(mode)
		}
	}

	/// 把搜索改成"右上角一个放大镜按钮"。
	///
	/// 为什么必须显式设:原来搜索是靠"工具栏里摆了 searchBarPlacementBarButtonItem"才落在底部的。
	/// 我们把那一项换掉之后,系统会按默认摆法处理 —— 多半是**压在标题下面那一条**,
	/// 而这一页的标题区被我们的头图和自绘标题占着,挤进去会打架。
	@objc func nnwUseCompactSearchPlacement() {
		if #available(iOS 26, *) {
			navigationItem.preferredSearchBarPlacement = .integratedButton
		}
	}

	private func nnwSelectReadingMode(_ mode: NNWReadingMode) {

		guard NNWReadingModeStore.shared.setMode(mode), let coordinator else { return }

		// 控件外观不用管 —— 两个页面的控件各自盯着通知
		NNWReadingModeApply.modeDidChange(coordinator: coordinator)

		// 文章整片换了,给一点过渡。
		// ⚠️ 只做淡入淡出,不碰 contentInset / contentOffset(L73:那两个是一对)。
		// 真正把文章换掉的是上面那句里的 refreshTimeline —— 它是**异步取数**,
		// 所以这层动画只是遮一下"旧的还在、新的还没到"的那一瞬。
		if let collectionView {
			UIView.transition(with: collectionView, duration: 0.22,
							  options: [.transitionCrossDissolve, .allowUserInteraction],
							  animations: {}, completion: nil)
		}
	}
}

#endif
