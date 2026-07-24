//
//  WebViewController+ReadingBar.swift
//  NetNewsWire — AI 翻译 fork
//
//  [外观] 文章页顶部「阅读栏」—— **方案 C:每一页各自带一份**(2026-07-23 用户选定)。
//
//  ## 为什么从"整页共享一层"改成"每页一份"
//
//  阅读栏(大标题/源/头像/进度环)最初是**一层浮层**,盖在整个文章页
//  (ArticleViewController.view)上,每翻一页就"重新绑到新页、重算 inset、重藏表头"。
//  这套在真机上反复出问题(标题滞留、老表头闪现、最后甚至标题和正文叠成一团)——
//  根子是:**翻页时正文跟着页面滑,而那层浮层钉在原地,靠事后重新同步补救,时序不可靠**。
//
//  方案 C 把阅读栏做成**每个 WebViewController 自己的一部分**(贴在它自己的 view 上、
//  盯它自己的 webView.scrollView)。于是:
//  - **横滑**:每一页(连同它的阅读栏)作为一个整体一起滑进滑出 → **标题和正文天然同步**,
//    不再需要"翻页结束后重新对齐"这种事后补救。
//  - **竖滑**:阅读栏在它自己那一页里飞上去缩小 → **飞行动画一点没丢**。
//  - **藏网页表头 / 算 inset**:各页管各页的,**没有跨页重绑**,那类竞态从根上消失。
//
//  这个类本身(`ArticleHeaderBarController`)几乎没动 —— 它只用 `host.view`
//  (宽度、安全区、加子视图),不碰 navigationItem,所以宿主换成 WebViewController 即可。
//
//  ## 挂在哪几个时机(都在 WebViewController 里)
//
//  1. `renderPage` 之后:网页开始装载,这时 scrollView 已在、文章元数据已有,
//     阅读栏可以立刻出现并把正文往下推(**早出现**,不再等 didFinish,治"老表头闪现")。
//  2. `didFinish`:网页彻底加载完,再对齐一次(保险)。
//  3. `viewDidLayoutSubviews`:宽度确定 / 转屏 —— 标题行数会变,要重量高度。
//
//  三个时机都调同一个 `nnwUpdateReadingBar()`,它内部幂等(见 ArticleHeaderBarController.update)。
//

#if os(iOS)

import UIKit
import Account

extension WebViewController {

	private static var nnwReadingBarKey: UInt8 = 0
	private static var nnwModeCaptureKey: UInt8 = 0

	/// 这一页该不该有阅读栏:**只有关掉「全屏阅读」时才有**。
	///
	/// ⚠️ **值在本页开始装载时定格一次,中途不实时读**(2026-07-24):
	/// 那个「全屏」标记会被上游 `hideBars()` **临时写成 true**(它把"栏藏着"持久化,
	/// 详见 nnwToggleBars 里的说明)。实时读的话,下滑藏栏那一刻这里变 false →
	/// `nnwUpdateReadingBar` 把阅读栏整个 detach —— 正是用户截图里"顶栏消失 + 位置乱跳"。
	/// 定格后,模式只在换文章(重新装载)时重读;在设置里切换「全屏阅读」,
	/// 对**已经打开的这一篇**要翻页或重进才生效 —— 这是有意的取舍。
	var nnwReadingBarEnabled: Bool {
		if let captured = objc_getAssociatedObject(self, &Self.nnwModeCaptureKey) as? Bool {
			return captured
		}
		let mode = traitCollection.userInterfaceIdiom == .phone && !AppDefaults.shared.logicalArticleFullscreenEnabled
		objc_setAssociatedObject(self, &Self.nnwModeCaptureKey, mode, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
		return mode
	}

	/// 重新定格模式(换文章、重新装载时调 —— 那时读到的才是用户真正的设置)。
	private func nnwRecaptureReadingBarMode() {
		objc_setAssociatedObject(self, &Self.nnwModeCaptureKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
	}

	/// [翻译] 把标题的译文喂给本页的阅读栏(nil = 还原成文章原标题)。
	/// 由翻译的桥接(`nnwTranslationApplyTitle` / `nnwTranslationRestore`)调用。
	/// 栏还没建(沉浸模式 / 页面还没就绪)就什么都不做 —— 建的时候 applyContent 会用原标题,
	/// 而翻译的 applyTitle 在页面就绪后才可能发生,顺序天然是对的。
	func nnwSetReadingBarTitleOverride(_ text: String?) {
		nnwReadingBar?.setTitleOverride(text)
	}

	/// 本页自己的阅读栏(没建过就是 nil)。
	private var nnwReadingBar: ArticleHeaderBarController? {
		get { objc_getAssociatedObject(self, &Self.nnwReadingBarKey) as? ArticleHeaderBarController }
		set { objc_setAssociatedObject(self, &Self.nnwReadingBarKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
	}

	/// 装 / 更新本页的阅读栏。**幂等**,可以随便多调。
	///
	/// `contentSettled`:网页装载完没有 —— 装载期间 WebKit 会自己重置滚动位置,
	/// 阅读栏在那段时间要按"停在顶部"画,不能信中途的偏移(详见 ArticleHeaderBar 里的说明)。
	/// renderPage(开始装)传 false;didFinish(装完)传 true;布局变化传 nil(状态不变)。
	func nnwUpdateReadingBar(contentSettled: Bool? = nil) {

		// 开始装载新内容 = 重新定格一次模式(这时藏栏的临时标记不在,读到的是真设置)
		if contentSettled == false {
			nnwRecaptureReadingBarMode()
		}

		// 沉浸模式(全屏阅读):不要阅读栏,建过的话摘掉(它会把 contentInset 还回去)。
		guard nnwReadingBarEnabled else {
			nnwReadingBar?.detach()
			return
		}

		// 还没准备好就先不动:没有滚动视图没法绑,宽度为 0 时量高度不准(会等下一次布局再来)。
		guard let scrollView = nnwContentScrollView, view.bounds.width > 0 else { return }

		let controller: ArticleHeaderBarController
		if let existing = nnwReadingBar {
			controller = existing
		} else {
			controller = ArticleHeaderBarController()
			nnwReadingBar = controller
		}

		controller.update(article: article, host: self, scrollView: scrollView, contentSettled: contentSettled)
	}
}

#endif
