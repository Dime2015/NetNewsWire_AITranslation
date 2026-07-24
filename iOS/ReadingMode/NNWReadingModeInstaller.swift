//
//  NNWReadingModeInstaller.swift
//  NetNewsWire — AI 翻译 fork
//
//  [阅读档] 两个页面共用的那点东西:造一条控件、换档之后该通知谁。
//  本 fork 新增,上游没有。
//
//  ## 为什么要有这个文件
//
//  三档控件现在**两个页面各有一条**(订阅源列表页 / 文章列表页,用户 2026-07-23 要求)。
//  ⚠️ 一个 UIView 只能有一个父视图,**两页不能共用同一条控件的实例** ——
//  必须一页造一条。造的过程和"换完档要做什么"是共同的,收在这里。
//
//  两条控件之间不用互相通知:每条自己盯着
//  `NNWReadingModeStore.didChangeNotification`,在哪边改的都能跟上。
//

#if os(iOS)

import UIKit

extension UIViewController {

	private static var nnwModeBarKey: UInt8 = 0

	/// 这个页面自己那条三档控件(没有就是还没装)。
	var nnwReadingModeBar: NNWReadingModeBar? {
		get { objc_getAssociatedObject(self, &Self.nnwModeBarKey) as? NNWReadingModeBar }
		set { objc_setAssociatedObject(self, &Self.nnwModeBarKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
	}

	/// 造(或取回)本页的三档控件,包成一个工具栏项。
	/// **同一个页面反复调只会造一次** —— 工具栏会被反复重建,不能每次都换一条新的。
	func nnwReadingModeBarItem(onSelect: @escaping (NNWReadingMode) -> Void) -> UIBarButtonItem {

		if let existing = nnwReadingModeBar {
			return UIBarButtonItem(customView: existing)
		}

		let bar = NNWReadingModeBar()
		bar.onSelect = onSelect
		nnwReadingModeBar = bar
		return UIBarButtonItem(customView: bar)
	}
}

/// 换完档之后,谁该跟着变。
@MainActor enum NNWReadingModeApply {

	/// **换档的唯一收尾入口**,两个页面都调它。
	///
	/// 做两件事,缺一件就会出现"在这一页切了档,另一页没跟上":
	/// 1. **订阅源列表**:让上游的「隐藏没有未读的源」跟档位对齐。
	///    上游只给了 `toggleReadFeedsFilter()`(切换)、没有 setter,所以是"不一致才切一下"。
	///    白拿它内部做的事:重建整棵树 + 存进 AppDefaults + 刷界面。
	/// 2. **文章列表**:重新取一次文章。
	///    ⚠️ 这条是**在文章列表页切档时的关键** —— 不重取的话,切了档屏幕上什么都不会变
	///    (取哪些文章是在取数那一刻决定的,已经在屏幕上的那批不会自己变)。
	///    上游自己的「漏斗」也是这么干的(`toggleReadArticlesFilter` 里紧跟着就 refresh)。
	static func modeDidChange(coordinator: SceneCoordinator) {

		// ★ 档要用「每个源有几篇星标」,进来时先催一次(异步,到货后会发通知,见下面的观察者)
		if NNWReadingModeStore.shared.mode == .starred {
			NNWStarredIndex.shared.refresh()
		}

		let wanted = NNWReadingModeStore.shared.hidesFullyReadFeeds
		if coordinator.isReadFeedsFiltered != wanted {
			coordinator.toggleReadFeedsFilter()		// 它内部会重建整棵树
		} else {
			// ⚠️ **这个 else 不能省**:未读↔全部 之外的切换(比如 全部→★)
			// 那个开关的目标值没变 → 不会切 → **也就不会重建** → ★ 档的行过滤永远不生效。
			// (第一版就漏了这个,切到★什么都不会变。)
			coordinator.nnwRebuildFeedList()
		}

		// resetScroll: false —— 换档不该把人拉回列表顶部,他多半正读到中间
		coordinator.refreshTimeline(resetScroll: false)
	}

	/// 换档时那一下过渡动画。**两个页面共用**,所以观感一致。
	///
	/// 2026-07-23 用户反馈「动画效果稍微再明显一点点」→ 从原地淡入淡出改成
	/// **跟着方向的横向滑入 + 淡入**:往右边那一档切,内容就从右边滑进来。
	/// 比纯淡入好在**有方向感** —— 和"我刚才往左滑了一下"对得上,
	/// 也让"这是换了一整屏内容"这件事说得更清楚。
	///
	/// ⚠️ **只动 transform 和 alpha,绝不碰 `contentInset` / `contentOffset`**(L73:
	/// 那两个是一对,动一个必须动另一个;而且滚动回调里改布局会成环,L63)。
	/// transform 是画上去的位移,滚动位置一点没变,所以这条路是安全的。
	///
	/// - Parameter forward: true = 切到右边那一档(手指往左滑)
	static func animateSwitch(_ view: UIView?, forward: Bool) {

		guard let view else { return }

		let travel: CGFloat = 34
		view.transform = CGAffineTransform(translationX: forward ? travel : -travel, y: 0)
		view.alpha = 0.15

		// `.beginFromCurrentState`:连着快滑好几下时,从当前位置接着动,不会跳回起点
		UIView.animate(withDuration: 0.34, delay: 0,
					   usingSpringWithDamping: 0.82, initialSpringVelocity: 0.4,
					   options: [.allowUserInteraction, .beginFromCurrentState]) {
			view.transform = .identity
			view.alpha = 1
		}
	}

	/// 从哪一档切到哪一档,是"往右"还是"往左"。
	static func isForward(from old: NNWReadingMode, to new: NNWReadingMode) -> Bool {
		let order = NNWReadingMode.allCases
		guard let a = order.firstIndex(of: old), let b = order.firstIndex(of: new) else { return true }
		return b > a
	}
}

#endif
