//
//  NNWArticlePaging.swift
//  NetNewsWire — AI 翻译 fork
//
//  [阅读] 本 fork 新增,上游没有这个文件。用户 2026-08-08 第 4 件:
//  **右滑回列表、左滑下一篇未读**;左滑到头时给一个彩蛋页「没有下一篇啦!」。
//
//  ## 改了什么(和上游的行为差别)
//
//  | 手势 | 上游 | 现在 |
//  |---|---|---|
//  | 左滑 | 列表里的**下一篇**(不管读没读过) | **下一篇未读**;没有了 → 彩蛋页 |
//  | 右滑 | 列表里的**上一篇** | **回文章列表** |
//
//  这一条是用户拍板的阅读流:进来一篇篇往左滑,读完就走,不用回列表挑。
//  上下一篇的老入口一个没丢 —— 底部 dock 上的箭头、键盘快捷键都还在。
//
//  ## ⚠️ 右滑为什么要自己做一个手势
//
//  「前一页返回 nil」只做到了**不再翻页**,并不等于**会返回** ——
//  系统的返回手势(`interactivePopGestureRecognizer`)是**屏幕左边缘**那一条,
//  从屏幕中间往右滑它根本不参与。所以这里补一个覆盖全宽的 pan:
//  只在「明显是往右的横向滑动」时才开始,竖着滚正文、往左翻页都不受影响。
//
//  判据来自 L120:排查"手势没反应"先问"我的 hitTest / shouldBegin 被调用了没有" ——
//  所以这个手势挂在**本页自己的 view** 上(触摸一定先到这一层),
//  并且允许与 WebView、翻页容器的手势**同时识别**,不去和它们抢。
//

#if os(iOS)

import UIKit
import os
import Articles

// MARK: - 彩蛋页

/// 左滑到头时露出来的那一页。**不是** WebViewController,所以上游那些
/// `viewControllers?.first as? WebViewController` 的判断会自然得到 nil 并提前返回 ——
/// 这正是我们要的:这一页没有文章,任何针对"当前文章"的动作都不该发生。
@MainActor final class NNWNoMoreArticlesViewController: UIViewController {

	/// 点「回到列表」时调用。由 ArticleViewController 装上。
	var onBackToList: (() -> Void)?

	override func viewDidLoad() {
		super.viewDidLoad()

		view.backgroundColor = AppAppearance.paperBackground

		let icon = UIImageView(image: UIImage(systemName: "cup.and.saucer"))
		icon.tintColor = NNWSoftMaterial.accent
		icon.contentMode = .scaleAspectFit
		icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 56, weight: .light)

		let title = UILabel()
		title.text = "没有下一篇啦!"
		title.font = .preferredFont(forTextStyle: .title2).bold()
		title.adjustsFontForContentSizeCategory = true
		title.textAlignment = .center
		title.numberOfLines = 0

		let subtitle = UILabel()
		subtitle.text = "这个列表里的未读都读完了。\n右滑回到列表。"
		subtitle.font = .preferredFont(forTextStyle: .subheadline)
		subtitle.adjustsFontForContentSizeCategory = true
		subtitle.textColor = .secondaryLabel
		subtitle.textAlignment = .center
		subtitle.numberOfLines = 0

		var config = UIButton.Configuration.plain()
		config.title = "回到列表"
		config.baseForegroundColor = NNWSoftMaterial.accent
		let button = UIButton(configuration: config)
		button.addTarget(self, action: #selector(backToListTapped), for: .touchUpInside)

		let stack = UIStackView(arrangedSubviews: [icon, title, subtitle, button])
		stack.axis = .vertical
		stack.alignment = .center
		stack.spacing = 14
		stack.setCustomSpacing(24, after: subtitle)
		stack.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(stack)

		NSLayoutConstraint.activate([
			stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
			// 略高于正中 —— 正中会显得往下坠(和长图预览页同一个取值)
			stack.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -40),
			stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
			stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32)
		])
	}

	@objc private func backToListTapped() {
		onBackToList?()
	}
}

// MARK: - 翻页规则 + 右滑返回

extension ArticleViewController {

	/// 当前翻页容器正在显示哪一页。
	///
	/// ⚠️ `pageViewController` 在上游是 `private`,外部文件够不着 ——
	/// 所以从 `children` 里现找。它是 `addChild` 进来的,一辈子就一个。
	private var nnwCurrentPage: UIViewController? {
		children.compactMap { $0 as? UIPageViewController }.first?.viewControllers?.first
	}

	/// 现在露在外面的是不是彩蛋页。
	var nnwIsShowingNoMoreArticlesPage: Bool {
		nnwCurrentPage is NNWNoMoreArticlesViewController
	}

	/// 列表里排在这篇后面的**第一篇未读**。没有就返回 nil。
	///
	/// ⚠️ 只在**当前这个列表**里找,不跨源找下一个源 ——
	/// 跨源是底部 dock 上「下一篇未读」那颗键的事(`coordinator.selectNextUnread`),
	/// 两者故意分工:滑动只在本列表内走,不会把用户莫名其妙带到别的源去。
	func nnwFindNextUnreadArticle(after article: Article) -> Article? {
		guard let coordinator else { return nil }
		let articles = coordinator.articles
		guard let index = articles.firstIndex(of: article) else { return nil }
		for next in articles[(index + 1)...] where !next.status.read {
			return next
		}
		return nil
	}

	/// 造一页彩蛋页(每次都新造一个 —— UIPageViewController 不允许同一个子控制器同时出现两次)。
	func nnwMakeNoMoreArticlesPage() -> NNWNoMoreArticlesViewController {
		let page = NNWNoMoreArticlesViewController()
		page.onBackToList = { [weak self] in
			self?.nnwBackToTimeline()
		}
		return page
	}

	/// 回文章列表。
	///
	/// ⚠️ **不能对 `navigationController` 出栈**(2026-08-08 埋日志才查出来):
	/// 文章页自己住在一个**只有它一个**的导航控制器里(故事板里 secondary 那一列),
	/// 真正装着「列表 → 文章」那个栈的是**它的父导航控制器**。
	/// 对自己那个栈出栈 = 栈里只有一个,什么都不会发生 —— 手势明明识别了却毫无反应。
	/// (上游 `PoppableGestureRecognizerDelegate` 的接法也是取 `navigationController?.parent`,
	///  见 `viewDidAppear`。同一个事实,两处都要遵守。)
	func nnwBackToTimeline() {
		guard let target = nnwPopTargetNavigationController, target.viewControllers.count > 1 else { return }
		target.popViewController(animated: true)
	}

	/// 该对谁出栈:优先父导航控制器(真正的「列表 → 文章」栈),没有就退回自己的。
	private var nnwPopTargetNavigationController: UINavigationController? {
		if let parent = navigationController?.parent as? UINavigationController, parent.viewControllers.count > 1 {
			return parent
		}
		return navigationController
	}

	/// 装上本页那两条自定义手势。在 viewDidLoad 里调用一次。
	///
	/// [阅读] 2026-08-09 用户重排了这一页的手势,现在是**两条 pan 各管一个方向**:
	///
	/// | 手势 | 做什么 |
	/// |---|---|
	/// | 右滑 | 回文章列表(没变) |
	/// | 左滑 | **打开原文**(app 内浏览器)—— 原来是"下一篇未读" |
	/// | 已经在**底部**,再用力上拽 | **下一篇未读**;没有了 → 彩蛋页 |
	/// | 已经在**顶部**,再用力下拽 | **上一篇** |
	///
	/// ⚠️ 横竖分成两条 pan、各自一个 delegate,而不是一条 pan 里判方向:
	/// `shouldBegin` 里"这一下是横还是竖"要在手指刚动几个点时就定下来,
	/// 一条 pan 只能给一个答案 —— 两条各自只认自己那个方向,谁都不会把对方的活抢走。
	func nnwInstallReadingGestures() {

		// ⚠️ 三句都不能少:我们只是**旁听**,不打断正文里正在发生的事
		// (不设的话,一旦我们识别成功,落在 WebView 上的触摸会被取消 ——
		//  选中的文字、按住的链接会莫名其妙失效;竖向那条更要命,会把滚动打断)。
		let horizontal = UIPanGestureRecognizer(target: self, action: #selector(nnwHandleHorizontalPan(_:)))
		horizontal.delegate = nnwHorizontalSwipeDelegate
		horizontal.cancelsTouchesInView = false
		horizontal.delaysTouchesBegan = false
		view.addGestureRecognizer(horizontal)

		let vertical = UIPanGestureRecognizer(target: self, action: #selector(nnwHandleVerticalPan(_:)))
		vertical.delegate = nnwVerticalSwipeDelegate
		vertical.cancelsTouchesInView = false
		vertical.delaysTouchesBegan = false
		view.addGestureRecognizer(vertical)
	}

	// MARK: 横向:右滑回列表 / 左滑开原文

	@objc func nnwHandleHorizontalPan(_ recognizer: UIPanGestureRecognizer) {

		guard recognizer.state == .ended else { return }
		let translation = recognizer.translation(in: view)
		let velocity = recognizer.velocity(in: view)
		NNWArticlePagingLog.logger.info(
			"[阅读] 横滑结束 dx=\(translation.x, privacy: .public) vx=\(velocity.x, privacy: .public)")

		// 滑够远,或者甩得够快 —— 两个条件满足一个就算(和系统返回手势的手感对齐)
		if translation.x > 90 || (translation.x > 30 && velocity.x > 700) {
			nnwBackToTimeline()
			return
		}
		if translation.x < -90 || (translation.x < -30 && velocity.x < -700) {
			nnwOpenOriginalLink()
		}
	}

	/// [阅读] 左滑:用 app 内浏览器打开这篇文章的原始链接。
	///
	/// 复用上游现成的 `showBrowserForCurrentArticle()`(它内部就是 `SFSafariViewController`,
	/// 也是「更多」菜单里「在浏览器中打开」走的同一条路)—— 不自己造第二条。
	///
	/// ⚠️ 彩蛋页上没有文章,别开。
	func nnwOpenOriginalLink() {
		guard !nnwIsShowingNoMoreArticlesPage else { return }
		coordinator?.showBrowserForCurrentArticle()
	}

	// MARK: 竖向:拽过头翻篇

	/// 拽过头要多远才算数(pt)。
	///
	/// ⚠️ 用户的原话是「**比较用力**的上滑」,所以距离和速度**两个都要满足**,不是满足一个就行 ——
	/// 竖向手势和"读正文"是同一个动作,门槛松一点就会在读到底时莫名其妙跳到下一篇。
	/// 横向那两条可以松(横滑本来就不是阅读动作),竖向必须紧。
	private static var nnwOverscrollDistance: CGFloat { 110 }
	private static var nnwOverscrollVelocity: CGFloat { 900 }

	@objc func nnwHandleVerticalPan(_ recognizer: UIPanGestureRecognizer) {

		switch recognizer.state {
		case .began:
			// ⚠️ **到没到头要在手势开始的那一刻记下来**,不能等结束时再问。
			// 不然"从中间一路甩到底"也会在结束时量到"现在在底部",于是白白翻页 ——
			// 而用户要的是"已经在底部了,再拽一下"。
			// 这是 L124 那条判据的同族:**症状相同不等于原因相同,量的时机决定了量的是哪件事。**
			nnwOverscrollAnchor = nnwCurrentScrollEdge()
		case .ended:
			let anchor = nnwOverscrollAnchor
			nnwOverscrollAnchor = nil
			guard let anchor, !nnwIsShowingNoMoreArticlesPage else { return }

			let translation = recognizer.translation(in: view)
			let velocity = recognizer.velocity(in: view)
			NNWArticlePagingLog.logger.info(
				"[阅读] 竖拽结束 起点=\(anchor.rawValue, privacy: .public) dy=\(translation.y, privacy: .public) vy=\(velocity.y, privacy: .public)")

			let distance = Self.nnwOverscrollDistance
			let speed = Self.nnwOverscrollVelocity

			// 在底部,继续往上拽(dy 为负)→ 下一篇未读
			if anchor == .bottom, translation.y < -distance, velocity.y < -speed {
				nnwGoToNextUnread()
				return
			}
			// 在顶部,继续往下拽(dy 为正)→ 上一篇
			if anchor == .top, translation.y > distance, velocity.y > speed {
				coordinator?.selectPrevArticle()
			}
		case .cancelled, .failed:
			nnwOverscrollAnchor = nil
		default:
			break
		}
	}

	/// 手势开始时,正文停在哪一头(都不在就是 nil —— 中间,那一下就只是普通滚动)。
	private func nnwCurrentScrollEdge() -> NNWScrollEdge? {
		guard let page = nnwCurrentPage as? WebViewController else { return nil }
		// ⚠️ 用上游自己的 `canScrollUp/Down`,不自己拿 contentOffset 去算 ——
		// 它内部考虑了安全区和分页滚动的落点,我们再算一遍必然和它对不齐(L73 那一族)。
		if !page.canScrollDown() { return .bottom }
		if !page.canScrollUp() { return .top }
		return nil
	}

	/// [阅读] 去列表里的下一篇未读;没有了就露出彩蛋页。
	///
	/// 语义和原来"左滑翻页"时完全一样(**只在当前这个列表里找**,不跨源),
	/// 只是触发方式从左滑换成了"在底部再拽一把"。
	private func nnwGoToNextUnread() {

		guard let coordinator,
			  let current = (nnwCurrentPage as? WebViewController)?.article else { return }

		if let next = nnwFindNextUnreadArticle(after: current) {
			coordinator.selectArticle(next, animations: [.select, .scroll, .navigation])
			return
		}

		// 没有下一篇未读了 —— 换上彩蛋页。
		// ⚠️ 走 `setViewControllers` 而不是 `coordinator.selectArticle`:彩蛋页不是一篇文章,
		// 协调器那条路没有"显示一个不是文章的东西"这种概念。
		guard let pageViewController = children.compactMap({ $0 as? UIPageViewController }).first else { return }
		pageViewController.setViewControllers([nnwMakeNoMoreArticlesPage()],
											  direction: .forward, animated: true) { [weak self] _ in
			self?.nnwSyncFloatingDockVisibility()	// 翻页不改安全区,那条回调不会来,得自己叫一次
		}
	}
}

/// 手势开始时正文停在哪一头。
enum NNWScrollEdge: String {
	case top
	case bottom
}

enum NNWArticlePagingLog {
	static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "NNWArticlePaging")
}

// MARK: - 两条手势各自的开始条件

extension ArticleViewController {

	/// 关联对象的键。⚠️ 用 `nonisolated(unsafe)` —— 它只是一个取地址用的哨兵,
	/// 从头到尾没人读写它的值,和并发安全无关(全仓其他关联对象也是这个写法)。
	private static nonisolated(unsafe) var nnwHorizontalSwipeDelegateKey: UInt8 = 0
	private static nonisolated(unsafe) var nnwVerticalSwipeDelegateKey: UInt8 = 0
	private static nonisolated(unsafe) var nnwOverscrollAnchorKey: UInt8 = 0

	fileprivate var nnwHorizontalSwipeDelegate: NNWAxisSwipeGestureDelegate {
		if let existing = objc_getAssociatedObject(self, &Self.nnwHorizontalSwipeDelegateKey) as? NNWAxisSwipeGestureDelegate {
			return existing
		}
		let delegate = NNWAxisSwipeGestureDelegate(axis: .horizontal)
		objc_setAssociatedObject(self, &Self.nnwHorizontalSwipeDelegateKey, delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
		return delegate
	}

	fileprivate var nnwVerticalSwipeDelegate: NNWAxisSwipeGestureDelegate {
		if let existing = objc_getAssociatedObject(self, &Self.nnwVerticalSwipeDelegateKey) as? NNWAxisSwipeGestureDelegate {
			return existing
		}
		let delegate = NNWAxisSwipeGestureDelegate(axis: .vertical)
		objc_setAssociatedObject(self, &Self.nnwVerticalSwipeDelegateKey, delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
		return delegate
	}

	/// 竖向手势**开始时**正文停在哪一头。手势结束时靠它判断"这一下算不算拽过头"。
	var nnwOverscrollAnchor: NNWScrollEdge? {
		get { (objc_getAssociatedObject(self, &Self.nnwOverscrollAnchorKey) as? String).flatMap(NNWScrollEdge.init(rawValue:)) }
		set { objc_setAssociatedObject(self, &Self.nnwOverscrollAnchorKey, newValue?.rawValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
	}
}

/// 只在「明显是这个方向」的滑动时才让手势开始。
///
/// [阅读] 2026-08-09:原来只有右滑一条,现在横竖各一条,规则同源,所以合成一个带轴向参数的类。
///
/// - 横向那条:只认横滑(左右都要),竖着读正文完全不受影响
/// - 竖向那条:只认竖拽,横滑时不参与
/// - 两条都**允许别人同时识别** —— 我们不抢,只是多听一份。
///   正文的滚动、WebView 的选字全部照常。
private final class NNWAxisSwipeGestureDelegate: NSObject, UIGestureRecognizerDelegate {

	enum Axis { case horizontal, vertical }

	private let axis: Axis

	init(axis: Axis) {
		self.axis = axis
		super.init()
	}

	func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
		guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
		// ⚠️ 判方向用 **translation 而不是 velocity**:`shouldBegin` 是在手指刚动了几个点时问的,
		// 那一刻 velocity 可能还是 0(模拟器注入的拖拽尤其如此,2026-08-08 第一版就栽在这:
		// 手势从来没 begin 过,表现是"右滑毫无反应")。translation 在这一刻一定已经有值了。
		let translation = pan.translation(in: pan.view)
		let began: Bool
		switch axis {
		case .horizontal:	began = abs(translation.x) > abs(translation.y)
		case .vertical:		began = abs(translation.y) > abs(translation.x)
		}
		return began
	}

	func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
						   shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
		true
	}
}

#endif
