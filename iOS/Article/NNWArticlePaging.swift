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

	/// 装上「从任意位置右滑 = 回列表」。在 viewDidLoad 里调用一次。
	func nnwInstallBackToListSwipe() {
		let pan = UIPanGestureRecognizer(target: self, action: #selector(nnwHandleBackToListPan(_:)))
		pan.delegate = nnwBackSwipeDelegate
		// ⚠️ 两句都不能少:我们只是**旁听**这条 pan,不打断正文里正在发生的事
		// (不设的话,一旦我们识别成功,落在 WebView 上的触摸会被取消 —— 选中的文字、
		//  按住的链接会莫名其妙失效)。
		pan.cancelsTouchesInView = false
		pan.delaysTouchesBegan = false
		view.addGestureRecognizer(pan)
	}

	@objc func nnwHandleBackToListPan(_ recognizer: UIPanGestureRecognizer) {
		guard recognizer.state == .ended else { return }
		let translation = recognizer.translation(in: view)
		let velocity = recognizer.velocity(in: view)
		NNWArticlePagingLog.logger.info(
			"[阅读] 右滑结束 dx=\(translation.x, privacy: .public) dy=\(translation.y, privacy: .public) vx=\(velocity.x, privacy: .public)")
		// 滑够远,或者甩得够快 —— 两个条件满足一个就返回(和系统返回手势的手感对齐)
		guard translation.x > 90 || (translation.x > 30 && velocity.x > 700) else { return }
		nnwBackToTimeline()
	}
}

enum NNWArticlePagingLog {
	static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "NNWArticlePaging")
}

// MARK: - 右滑手势的开始条件

extension ArticleViewController {

	/// 关联对象的键。⚠️ 用 `nonisolated(unsafe)` —— 它只是一个取地址用的哨兵,
	/// 从头到尾没人读写它的值,和并发安全无关(全仓其他关联对象也是这个写法)。
	private static nonisolated(unsafe) var nnwBackSwipeDelegateKey: UInt8 = 0

	fileprivate var nnwBackSwipeDelegate: NNWBackSwipeGestureDelegate {
		if let existing = objc_getAssociatedObject(self, &Self.nnwBackSwipeDelegateKey) as? NNWBackSwipeGestureDelegate {
			return existing
		}
		let delegate = NNWBackSwipeGestureDelegate()
		objc_setAssociatedObject(self, &Self.nnwBackSwipeDelegateKey, delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
		return delegate
	}
}

/// 只在「明显往右的横向滑动」时才让手势开始。
///
/// - 竖向滑动(读正文)→ 不开始,滚动完全不受影响
/// - 往左滑(翻下一篇)→ 不开始,翻页容器照常工作
/// - 往右滑 → 开始,但**允许别人同时识别** —— 我们不抢,只是多听一份;
///   翻页容器那边因为"前一页 = nil"本来就不会往右翻,两边不打架。
private final class NNWBackSwipeGestureDelegate: NSObject, UIGestureRecognizerDelegate {

	func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
		guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
		// ⚠️ 判方向用 **translation 而不是 velocity**:`shouldBegin` 是在手指刚动了几个点时问的,
		// 那一刻 velocity 可能还是 0(模拟器注入的拖拽尤其如此,2026-08-08 第一版就栽在这:
		// 手势从来没 begin 过,表现是"右滑毫无反应")。translation 在这一刻一定已经有值了。
		let translation = pan.translation(in: pan.view)
		let began = translation.x > 0 && abs(translation.x) > abs(translation.y)
		NNWArticlePagingLog.logger.info(
			"[阅读] 右滑 shouldBegin=\(began, privacy: .public) dx=\(translation.x, privacy: .public) dy=\(translation.y, privacy: .public)")
		return began
	}

	func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
						   shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
		true
	}
}

#endif
