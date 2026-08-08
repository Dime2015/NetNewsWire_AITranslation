//
//  NNWFloatingDock.swift
//  NetNewsWire — AI 翻译 fork
//
//  [外观] 本 fork 新增(2026-08-05)。把文章页的 dock **从系统工具栏里搬出来**,
//  改成一块浮在正文之上的普通视图。
//
//  ## 为什么要搬出来
//
//  只要 dock 还是"工具栏里的一个按钮项",就绕不开 iOS 26/27 的这个死结
//  (完整实测记录见 NOTES-todo 的 T40 / T42,教训见 L116):
//
//  | dock 放在工具栏里,iOS 27 上 | 内容穿过栏底 | 单层 |
//  |---|---|---|
//  | 拆掉系统胶囊(`hidesSharedBackground`) | ❌ 硬切断 + 一条不透明黑带 | ✅ |
//  | 保留系统胶囊 | ✅ | ❌ 系统胶囊里套着我们的面板,两层 |
//
//  查过 SDK:`hidesSharedBackground` 是唯一相关的开关,**没有"保留行为、
//  只隐藏外观"的第三种接口**。所以"既要内容穿得过去、又要单层、还要我们自己的材质",
//  在"dock 是个栏按钮"这个前提下**不存在解**。
//
//  搬出来之后这三样同时成立:系统不再给它垫胶囊(**单层**)、
//  它只是块浮在上面的视图(**内容照旧铺满整屏、从它底下穿过去**)、
//  材质完全归我们(**玻璃质感自己调**)。而且 **iOS 26 和 27 行为一致**,
//  那处版本分叉(`systemDrawsBarCapsule`)也就不需要了。
//
//  ## ⚠️ 搬家时必须守住的三件事(都是这个项目上流过血的地方)
//
//  1. **老的 6 个 UIBarButtonItem 要有人抱着**(L85):它们的 IBOutlet 全是 weak,
//     一被换出 `toolbarItems` 数组就释放,而上游 `updateUI` 照旧往它们身上写状态 ——
//     写到空按钮上会**当场崩**。所以仍然由 board 的 `legacyItemsKeptAlive` 收养。
//  2. **工具栏本身不拆,留着当"占位"**:它撑起底部那段安全区,
//     正文的内边距、以及沉浸阅读藏栏/现栏那一整套(L73/L80~L84 那片雷区)
//     全都不用动 —— **我们只是把内容物挪到它上面去画,壳子一点没碰**。
//  3. **dock 的显隐要跟着栏走**:藏栏时安全区变化会触发
//     `viewSafeAreaInsetsDidChange`,在那里同步一次即可,不用另接手势或通知。
//

#if os(iOS)

import UIKit
import ObjectiveC

extension ArticleViewController {

	private static var nnwFloatingDockKey: UInt8 = 0

	/// 浮在正文之上的那块 dock。装过一次之后从关联对象里取(扩展不能加存储属性)。
	var nnwFloatingDock: NNWArticleControlBoard? {
		get { objc_getAssociatedObject(self, &Self.nnwFloatingDockKey) as? NNWArticleControlBoard }
		set { objc_setAssociatedObject(self, &Self.nnwFloatingDockKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
	}

	/// dock 底边离安全区底的距离。参考图里 dock 是"浮着"的,和屏幕边缘有一小段留白。
	private static var nnwDockBottomGap: CGFloat { 4 }

	private static var nnwDockConstraintKey: UInt8 = 0

	private var nnwDockBottomConstraint: NSLayoutConstraint? {
		get { objc_getAssociatedObject(self, &Self.nnwDockConstraintKey) as? NSLayoutConstraint }
		set { objc_setAssociatedObject(self, &Self.nnwDockConstraintKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
	}

	/// 按**真安全区**把 dock 摆到底部。真安全区 = 当前安全区 − 我们自己加的那一份。
	func nnwUpdateFloatingDockPosition() {
		guard let bottom = nnwDockBottomConstraint else { return }
		let rawBottom = view.safeAreaInsets.bottom - additionalSafeAreaInsets.bottom
		bottom.constant = -(max(rawBottom, 0) + Self.nnwDockBottomGap)
	}

	/// [外观] 把控件板装成浮层。**替代原来的 `toolbarItems = [flex, boardItem, flex]`**。
	///
	/// - Parameter board: 已经配好回调、也已经收养了老按钮的控件板
	func nnwInstallFloatingDock(_ board: NNWArticleControlBoard) {

		guard nnwFloatingDock !== board else { return }
		nnwFloatingDock?.removeFromSuperview()
		nnwFloatingDock = board

		board.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(board)

		// ⚠️ **不能把 dock 钉在 `safeAreaLayoutGuide` 上**(第二版栽在这):
		// 下面要用 `additionalSafeAreaInsets.bottom` 给正文让出 dock 的高度,
		// 而那个值也会把安全区往上抬 —— dock 跟着抬,就等于自己追自己,越描越高。
		//
		// 所以钉在 `view.bottomAnchor` 上,常量由**真安全区**(= 当前安全区减去我们自己加的
		// 那一份)算出来,在 `viewSafeAreaInsetsDidChange` 里更新。
		// 这个"减掉自己加的那份"的算法是照抄本工程 `updateBottomSafeAreaForFullScreen` 的做法。
		let bottom = board.bottomAnchor.constraint(equalTo: view.bottomAnchor)
		nnwDockBottomConstraint = bottom
		NSLayoutConstraint.activate([
			board.centerXAnchor.constraint(equalTo: view.centerXAnchor),
			bottom
		])

		// 给正文让出 dock 的高度,否则文章最后几行永远压在 dock 底下、滚不出来。
		additionalSafeAreaInsets.bottom = board.intrinsicContentSize.height + Self.nnwDockBottomGap * 2
		nnwUpdateFloatingDockPosition()

		// ⚠️ **必须置顶,而且要等这一轮布局跑完再置**(2026-08-05 第一版就栽在这:dock 看不见了)。
		// 装 dock 的 `installTranslationButton()` 在 `viewDidLoad` 的第 168 行,
		// 而承载正文的 `pageViewController.view` 是第 182 行才 addSubview 的 ——
		// **比我们晚**,于是正文那一层直接盖在 dock 上面。
		// 这是 L95 那类"我算的顺序和系统算的顺序不是一回事"的又一次。
		DispatchQueue.main.async { [weak self, weak board] in
			guard let self, let board, board.superview === self.view else { return }
			self.view.bringSubviewToFront(board)
		}
	}

	/// [外观] 让 dock 的显隐跟着系统栏走。**在 `viewSafeAreaInsetsDidChange` 里调**。
	///
	/// 沉浸阅读下滑藏栏时,上游会同时藏导航栏和工具栏 —— 那一刻安全区变化,
	/// 本方法被叫醒,把 dock 一起淡出;上滑现栏时反过来。
	/// 这样就不用去碰 `nnwToggleBars` 那段(那里有防栈溢出的闸门,别加东西,见 L80~L84)。
	///
	/// ⚠️ **这里有两个坑,都是 2026-08-05 用探针实测出来的,第一版两个都踩了。**
	///
	/// **坑一:工具栏藏不藏,底部安全区完全不动。**
	/// 工具栏被我们抹成了透明底 + `toolbarItems = []`,它对底部安全区的贡献是 **0** ——
	/// 实测藏栏前后 `safeAreaInsets.bottom` 都是 96.0(= 34 Home 条 + 62 我们给 dock 让的),
	/// 一个字节都没变。**所以"藏工具栏"根本不会触发安全区回调**;
	/// 唯一那次回调是**导航栏**藏起来(顶部 inset 变了)带来的。
	///
	/// **坑二:回调恰好插在上游那两句中间,所以工具栏的值一定是旧的。**
	/// 上游 `hideBars()` / `showBars()` 都是"先导航栏、后工具栏"两句,
	/// 而安全区回调在第一句里就同步发生了 —— 实测两个方向都读到旧值:
	///
	/// | | 回调时 navHidden | 回调时 toolbarHidden(旧值) |
	/// |---|---|---|
	/// | 下滑藏栏 | true | **false** |
	/// | 上滑现栏 | false | **true** |
	///
	/// 所以**推迟一轮 runloop 再读**,等两个值都落定。0.25s 的淡入淡出本来就和
	/// 栏的动画同步,晚一帧看不出来。
	///
	/// 两个都读:导航栏管沉浸阅读,工具栏管「文内查找」——
	/// 那条路只藏工具栏、不藏导航栏(见 `beginFind`,它会显式叫一次本方法)。
	func nnwSyncFloatingDockVisibility() {
		guard let dock = nnwFloatingDock else { return }
		// 每次栏变化都顺手置顶一次 —— 翻页容器换页时会重排子视图,不置顶会被盖回去
		if dock.superview === view { view.bringSubviewToFront(dock) }

		DispatchQueue.main.async { [weak self, weak dock] in
			guard let self, let dock, dock.superview === self.view else { return }
			let shouldHide = (self.navigationController?.isNavigationBarHidden ?? false)
				|| (self.navigationController?.isToolbarHidden ?? false)
				// [阅读] 2026-08-08:翻到彩蛋页(没有下一篇了)时也收起来 ——
				// 那一页没有文章,dock 上每一颗键都无从下手,留着只会误导。
				|| self.nnwIsShowingNoMoreArticlesPage
			let target: CGFloat = shouldHide ? 0 : 1
			guard dock.alpha != target else { return }
			UIView.animate(withDuration: 0.25) { dock.alpha = target }
			dock.isUserInteractionEnabled = !shouldHide
		}
	}
}

#endif
