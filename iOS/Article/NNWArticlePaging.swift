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
import WebKit

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
		icon.tintColor = NNWSoftMaterial.ink
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
		config.baseForegroundColor = NNWSoftMaterial.ink
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

		guard let index = articles.firstIndex(of: article) else {
			// 🔴 **当前这篇已经不在列表里了** —— 这在「全部未读」这类会把读过的移出去的列表里
			// **是常态**:你正在读的这一篇一旦被标记已读,它就从列表里消失了。
			//
			// 原来这里直接 `return nil` → 判定"没有下一篇" → 弹彩蛋页。
			// 于是在「全部未读」里**明明还有几百篇未读,一拽却总是「没有下一篇啦!」**
			// (用户 2026-08-09 报的那个 bug 的第二个原因)。
			//
			// 📌 判据:**"我在列表里的位置"这个前提,在会自我删减的列表上随时会失效。**
			// 找不到自己时的正确退路不是"那就没有了",而是**退回列表里的第一篇未读**。
			return articles.first { !$0.status.read && $0.articleID != article.articleID }
		}

		for next in articles[(index + 1)...] where !next.status.read {
			return next
		}
		// ⚠️ **这里就该 nil,别顺手改成"从头再找一篇未读"**:
		// 找得到自己的位置、而后面确实没有未读了 —— 那就是真的读到底了,该出彩蛋页。
		// 绕回列表开头会让人莫名其妙("我明明读到最后了,怎么跳回开头")。
		// 上面那条退路只对"**找不到自己**"成立,两种情形不能混。
		return nil
	}

	/// [阅读] 彩蛋页正占着位置时,把它换成真正的文章页。
	///
	/// ## 🔴 这是 2026-08-09 用户报的那个 bug 的修法
	///
	/// **现象**:在「全部未读」里点开任何一篇文章,显示的都是「没有下一篇啦!」。
	///
	/// **病根**:`ArticleViewController.currentWebViewController` 的定义是
	/// `pageViewController.viewControllers.first as? WebViewController` ——
	/// **彩蛋页不是 `WebViewController`,所以它是 `nil`**。
	/// 而换文章那段写的是 `if let controller = currentWebViewController, controller.article != article`,
	/// 于是**彩蛋页一露出来,这个条件就永远不成立**,谁也换不掉它 —— 单向死胡同。
	///
	/// 📌 判据:**往一个"只装 A 类东西"的容器里塞了一个 B 类的东西,
	/// 就要回头查所有 `as? A` 的地方 —— 它们会静默地全部失效。**
	/// 这和 L114/L116 是一家:让某个东西存在时,先想清楚谁在假设它不存在。
	///
	/// ⚠️ 这里**不做动画**:这是"从列表点了另一篇",不是翻页,
	/// 加个方向不明的滑动反而奇怪。
	func nnwReplaceEasterEggPage(with article: Article) {
		guard let pageViewController = children.compactMap({ $0 as? UIPageViewController }).first else { return }
		let page = nnwMakeArticlePage(article)
		pageViewController.setViewControllers([page], direction: .forward, animated: false) { [weak self] _ in
			self?.nnwSyncFloatingDockVisibility()	// 离开彩蛋页,dock 要放回来
		}
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

		// 🗄️ 2026-08-11 封存:「到头再拽翻上/下一篇」这条手势用户很少用,先关掉入口。
		// 下面这条竖向 pan 是唯一的触发点 —— 不装它,箭头指示器、内容推开、
		// nnwGoToPreviousArticle/nnwGoToNextUnread 整条链路就都不会跑,
		// 但代码原样留着,方便以后要捡回来。排查过程、卡住的地方、可能方向见
		// `NOTES-archive-overscroll-paging.md`。
		//
		// let vertical = UIPanGestureRecognizer(target: self, action: #selector(nnwHandleVerticalPan(_:)))
		// vertical.delegate = nnwVerticalSwipeDelegate
		// vertical.cancelsTouchesInView = false
		// vertical.delaysTouchesBegan = false
		// view.addGestureRecognizer(vertical)
	}

	// MARK: 横向:右滑回列表 / 左滑开原文

	@objc func nnwHandleHorizontalPan(_ recognizer: UIPanGestureRecognizer) {

		// 🪦 2026-08-12:左滑不再中途接管呈现(交互式转场已拆,理由见下方墓碑注释),
		// 一切都在 `.ended` 里按位移/速度判定 —— 和右滑回列表同一套写法。
		guard recognizer.state == .ended else { return }

		let translation = recognizer.translation(in: view)
		let velocity = recognizer.velocity(in: view)
		NNWArticlePagingLog.logger.info(
			"[阅读] 横滑结束 dx=\(translation.x, privacy: .public) vx=\(velocity.x, privacy: .public)")

		// 右滑回列表 / 左滑(或快速一甩)开原文
		if translation.x > 90 || (translation.x > 30 && velocity.x > 700) {
			nnwBackToTimeline()
			return
		}
		if translation.x < -90 || (translation.x < -30 && velocity.x < -700) {
			nnwOpenOriginalLink()
		}
	}

	// MARK: 左滑开原文

	// 🪦 2026-08-12:**交互式呈现整条拆除**(此处原有约 90 行:跨过 24pt 门槛就
	// `present` + `UIPercentDrivenInteractiveTransition` 跟手,配套自定义转场
	// `.custom` + `NNWBrowserSlideTransition`)。
	//
	// ## 为什么拆(这是一次取舍,用户拍板)
	// 用户要"浏览器页右滑回文章"。真机五轮排查(L144–L146)证实:
	// `SFSafariViewController` 的内容住在**它自己的 window** 里,宿主侧盖任何
	// 覆盖层都拿不到触摸 —— 自己做右滑手势这条路在物理上不成立。
	// 而系统对**普通方式 present** 的 Safari 页**自带**左缘滑动关闭
	// (Reeder 就是这么"实现"的:什么都不做,白拿系统的),真机对照实测有效;
	// 一旦套上 `.custom` + 自定义转场,系统这套手势就被顶掉。
	//
	// **鱼和熊掌**:左滑"跟手滑入"的动画 vs 右滑返回,只能选一个。
	// 用户选了右滑返回 —— 于是左滑退回"松手判定 → 普通 present"(系统默认弹出动画),
	// `nnwHandleHorizontalPan` 里 `.ended` 的老规则就是全部逻辑。
	//
	// ⚠️ 想捡回跟手动画的人:先读 NOTES-lessons L144–L146,别再走覆盖层那条路。

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

	// MARK: 竖向:拽过头翻篇(像下拉刷新那样,有指示器)

	/// 「拽过头」要超出内容边界多少 pt 才算数。
	///
	/// ## 🔴 2026-08-09 重做:第一版的判据是错的,用户报「手感不好,而且不灵」
	///
	/// 第一版要求**手指位移 ≥110pt 且松手瞬间速度 ≥900**,而且"在不在边缘"
	/// **只在手势开始那一刻记一次**。三个后果,合起来就是用户说的"有时能翻有时不能":
	///
	/// 1. **拽住停一下再松手 → 速度接近 0 → 不触发。** 这是最常见的那种"明明有下一篇却翻不了" ——
	///    而"拽住看一眼再松手"恰恰是最自然的操作。
	/// 2. **一口气从中间滑到底、继续拽 → 开始那一刻不在边缘 → 整段作废。**
	/// 3. 到边缘之后是**橡皮筋阻尼**,手指走 110pt 内容才动一点点,实际门槛远高于看起来的。
	///
	/// **现在改成量"真的超出内容多少"**(不是手指位移),而且**每一帧都算**、松手时**不看速度**。
	/// 判据:**当一个手势的语义是"到头了还想继续",就该量"超出了多少",
	/// 而不是量手指走了多远** —— 后者被阻尼曲线和起手位置污染,前者不会。
	/// 🔴 2026-08-09 用户:「触发得稍微有点早」→ **56 → 84**。
	private static var nnwOverscrollThreshold: CGFloat { 84 }

	/// 正文最多被推开多远(pt)。配合下面那条缓动,越拽越难拽 —— 就是橡皮筋的手感。
	private static var nnwPushLimit: CGFloat { 72 }

	/// 拽出这么多才开始画那条线。**低于它什么都不显示** ——
	/// 贴着边缘是读到底/读到顶的常态,不该因此就挂一条线在那儿。
	private static var nnwHintMinPull: CGFloat { 8 }

	/// 拽的手感曲线:**先快后慢**。
	///
	/// 用户 2026-08-09:「动画和触发都不应该是纯线性的,在震动之前的形变但不触发翻页的部分,
	/// 应该比现在长一点」。
	///
	/// 纯线性的问题:一路匀速,既没有"一拽就有反应"的跟手感,也没有"快到了、再使点劲"的余味。
	/// `1 − (1−t)^1.8` 的形状是:**刚一拽就走掉一大半**(立刻看得见反应),
	/// **最后那一段越走越慢** —— 于是"看着快满了却还没到"的那一段被拉长,
	/// 正是用户要的那种"形变但还不触发"的过程。
	///
	/// ⚠️ **触发仍然只看没缓动过的原始比例**(`raw >= 1`),缓动只管**看起来**怎么走。
	/// 判据:**手感曲线和判定阈值要分开** —— 混在一起的话,一调曲线就把触发点也调跑了。
	private static func nnwEase(_ raw: CGFloat) -> CGFloat {
		let t = min(max(raw, 0), 1)
		return 1 - pow(1 - t, 1.8)
	}

	@objc func nnwHandleVerticalPan(_ recognizer: UIPanGestureRecognizer) {

		switch recognizer.state {
		case .began:
			nnwOverscrollHaptic = UIImpactFeedbackGenerator(style: .medium)
			nnwOverscrollHaptic?.prepare()
			nnwOverscrollArmedEdge = nil
			nnwOverscrollPeak = 0
			nnwPinnedEdge = nil
			nnwIsPullingToTurnPage = true
		case .changed:
			nnwUpdatePageTurnHint(translationY: recognizer.translation(in: view).y)
		case .ended:
			let armedEdge = nnwOverscrollArmedEdge
			nnwIsPullingToTurnPage = false
			nnwDismissPageTurnHint()
			nnwOverscrollHaptic = nil
			nnwOverscrollArmedEdge = nil
			nnwLogOverscrollDiagnostics(armedEdge: armedEdge)
			guard let armedEdge, !nnwIsShowingNoMoreArticlesPage else {
				nnwResetContentPushBack(animated: true)		// 不翻页 → 正文弹回原位
				return
			}
			// ⚠️ 翻页前**立即**复位(不带动画):翻页动画也要用这一层做位移,
			// 带着残留的 transform 进去,新页会从一个歪掉的位置滑进来。
			nnwResetContentPushBack(animated: false)
			switch armedEdge {
			case .bottom:	nnwGoToNextUnread()
			case .top:		nnwGoToPreviousArticle()
			}
		case .cancelled, .failed:
			nnwIsPullingToTurnPage = false
			nnwDismissPageTurnHint()
			nnwResetContentPushBack(animated: true)
			nnwOverscrollHaptic = nil
			nnwOverscrollArmedEdge = nil
		default:
			break
		}
	}

	/// ⚠️ 临时探针(2026-08-09,查完就删):松手那一刻,把滚动视图的真实数字全打出来。
	///
	/// 用户报:「进度已经到文章最下面、侧边条也到底了,继续下拉却不触发翻页」,
	/// 而截图里内容下方还有一大片空白 —— 说明**"视觉上的结尾"和"滚动视图真正的底"不是一回事**。
	/// 到底是哪一项对不上(contentSize 偏大?内边距没算对?找错了滚动视图?),
	/// **这不能猜**(L131:一天四次量错都是因为对准了别的东西),量一次就知道。
	private func nnwLogOverscrollDiagnostics(armedEdge: NNWScrollEdge?) {

		guard let scrollView = nnwArticleScrollView else {
			NNWArticlePagingLog.logger.info("[拽] 松手:**没找到滚动视图**")
			return
		}

		let inset = scrollView.adjustedContentInset
		let restTop = -inset.top
		let restBottom = max(scrollView.contentSize.height + inset.bottom - scrollView.bounds.height, restTop)
		let offset = scrollView.contentOffset.y

		NNWArticlePagingLog.logger.info("""
			[拽] 松手 拽够=\(armedEdge?.rawValue ?? "无", privacy: .public) \
			| 峰值=\(self.nnwOverscrollPeak, privacy: .public) \
			| 视图=\(String(describing: type(of: scrollView)), privacy: .public) \
			| offset=\(offset, privacy: .public) \
			| contentH=\(scrollView.contentSize.height, privacy: .public) \
			| boundsH=\(scrollView.bounds.height, privacy: .public) \
			| inset上=\(inset.top, privacy: .public) 下=\(inset.bottom, privacy: .public) \
			| 静止位 上=\(restTop, privacy: .public) 下=\(restBottom, privacy: .public) \
			| 超出下=\(offset - restBottom, privacy: .public) 超出上=\(restTop - offset, privacy: .public)
			""")

		// ⚠️ 临时探针(2026-08-09 第五轮,查完就删):**「上一篇」这一头到底为什么没反应。**
		//
		// 用户第四轮那份真机日志里,有 4 次「**峰值恰好 0.000000,而同一刻超出上已经 188pt**」。
		// 这两个数字不可能同时成立 —— 除非 `nnwUpdatePageTurnHint` 根本没走到记峰值那一行,
		// 而它前面唯一的早退就是 `guard nnwHasDestination(.top)`。
		//
		// 那一问最终落到上游的 `isPrevArticleAvailable`,而它是
		// `articles.firstIndex(of: currentArticle)` —— **正是 T55 第 4 条那个
		// "在会自我删减的列表里找自己"的老坑**(`nnwGoToPreviousArticle` 已经用来路栈治好了,
		// 但**守门的这一问还走在老路上**)。
		//
		// 所以这一行要一次分清三种完全不同的情况,不能靠推:
		// - **真的是第一篇**(我这页在第 0 行)→ 不是 bug,缺的是"到头了"的反馈
		// - **协调器找不到自己**(第= 找不到)→ 老坑复发,守门那一问要换来路栈
		// - **两边认的不是同一篇**(我这页 ≠ 协调器认的)→ 翻页收尾没同步,又是另一回事
		//
		// ⚠️ 另外顺手对一下**门和路是不是同一套条件**:
		// `nnwGoToPreviousArticle` 有三条退路(来路栈 / 列表前一篇 / 上游 selectPrev),
		// 而门只问了 `isPrevArticleAvailable` 一条 —— **门比路窄,就会挡掉本来走得通的翻页。**
		if let coordinator {
			let mine = (nnwCurrentPage as? WebViewController)?.article
			let myRow = mine.flatMap { coordinator.articles.firstIndex(of: $0) }
			let coordRow = coordinator.currentArticle.flatMap { coordinator.articles.firstIndex(of: $0) }
			// ⚠️ **2026-08-09 第五轮改名:上一版这里标着「门=」,打的却是
			// `coordinator.isPrevArticleAvailable` —— 那只是四条路里的最后一条,不是门本身。**
			// 于是日志里出现「门=false 而来路栈=1」这种自相矛盾的行,得靠人肉推算真正的闸门。
			// 📌 又一次 L123:**「我量到了」≠「我量的是它」。探针的名字必须就是它量的那个量。**
			// 现在闸门和它的四条路各占一栏,一眼就能看出是哪一条放的行。
			NNWArticlePagingLog.logger.info("""
				[拽] 上一篇 闸门=\(self.nnwHasDestination(for: .top), privacy: .public) \
				| 来路栈=\(self.nnwPageBackStack.count, privacy: .public) 条 \
				| 我这页在第=\(myRow.map { String($0) } ?? "找不到", privacy: .public) 行 \
				| 进门锚=\(self.nnwAnchoredPreviousArticle == nil ? "无" : (self.nnwEntryNeighborByDate ? "有(按日期兜底)" : "有(列表相邻)"), privacy: .public) \
				| 画的线=\(String(describing: self.nnwHintState(for: .top)), privacy: .public) \
				| 上游=\(coordinator.isPrevArticleAvailable, privacy: .public) \
				| 协调器认的在第=\(coordRow.map { String($0) } ?? "找不到", privacy: .public) 行 \
				| 列表共=\(coordinator.articles.count, privacy: .public) 篇 \
				| 本页是正文页=\(self.nnwCurrentPage is WebViewController, privacy: .public)
				""")
		} else {
			// ⚠️ 沉默必须是有含义的:没有协调器也要说一声,否则少一行日志会被误读成"没拽"。
			NNWArticlePagingLog.logger.info("[拽] 上一篇:**没有协调器**,这一问根本没法答")
		}
	}

	/// 正文此刻**贴住/超出**了哪一头,以及"到头之后还拉了多少"。
	/// 中间(还能正常滚)就是 nil。
	///
	/// ## 🔴 2026-08-09 重做:第一版只量"超出",而这个 WebView **在底部根本不回弹**
	///
	/// 埋探针实测(SIM27,连拽六次):
	/// ```
	/// 峰值=0.000000  offset=4526.000000  静止位下=4526.000000  超出下=0.000000
	/// ```
	/// **一次都没超出去过** —— `contentOffset` 精确卡死在极限值。
	/// (顶部却能超出 209pt,两头行为不对称。)
	/// 也就是说:我一直在量一件**在这个页面上不会发生的事**,
	/// 难怪"模拟器上怎么拽都没反应"。
	///
	/// 📌 判据:**"到头了还想继续"这个意图,不一定表现为"内容超出了边界"** ——
	/// 会不会回弹取决于滚动视图和网页的设置(`bounces`、CSS `overscroll-behavior`…),
	/// 那不是我们能控制的。**能控制的是"手指在贴住之后还走了多少"。**
	///
	/// 所以现在**两种量法取大的**:
	/// - **超出量**:真的橡皮筋出去了多少(会回弹的地方,这个最跟手)
	/// - **贴住后的手指位移**:从"贴住那一刻"算起手指又拉了多远,**打五折**
	///   (回弹时内容位移大约是手指的一半,打折是为了让两种量法的手感对齐)
	///
	/// 这样不管回不回弹都能用,而且回弹的地方观感不变。
	private func nnwOverscrollEdge(translationY: CGFloat? = nil)
		-> (edge: NNWScrollEdge, amount: CGFloat, alreadyMoved: CGFloat)? {

		guard let scrollView = nnwArticleScrollView else { return nil }

		let restTop = -scrollView.adjustedContentInset.top
		let restBottom = max(scrollView.contentSize.height + scrollView.adjustedContentInset.bottom
							 - scrollView.bounds.height, restTop)
		let offset = scrollView.contentOffset.y

		/// 判"贴住"的容差:内边距和内容高都是小数,精确相等靠不住
		let slack: CGFloat = 1
		/// 手指**反向**回退超过这个数,才认为"不拽了",解锁
		let releaseSlack: CGFloat = 30

		// 🔴 **一旦贴住某一头就锁住,之后不再重新问"我还在不在边缘"**
		//
		// 真机日志(2026-08-09)钉死的病根:**沉浸阅读的栏会在拽的过程中冒出来** ——
		// ```
		// 峰值=219.5  offset=19719  静止位下=19865  超出下=-145  inset下=96   拽够=无 ❌
		// 峰值=162.8  offset=19930  静止位下=19769  超出下=+161  inset下=0    拽够=bottom ✅
		// ```
		// 栏一出现,`inset下` 从 0 跳到 96 →「底」抬高 96pt,UIKit 还会跟着重新夹紧偏移量 ——
		// **用户原地没动,却突然离底 200 多点**,于是"我还在不在边缘"这一问答案变成"不在",
		// 已经拽够的状态被当场清掉。峰值 142~219(门槛才 56)全部白拽。
		//
		// 📌 判据:**当一个状态的判定依赖于"会被别人改动的量"(这里是内边距),
		// 就不能每一帧重新判 —— 要在它第一次成立时锁住,再定义一个明确的解锁条件。**
		// 这里的解锁条件是**手指反向**:那是用户的动作,不会被系统的排版变化伪造。
		if let pinned = nnwPinnedEdge, let translationY {
			let fingerPull = pinned == .bottom
				? nnwPinnedTranslationY - translationY
				: translationY - nnwPinnedTranslationY
			if fingerPull < -releaseSlack {			// 手指明显往回走了 → 真的不拽了
				nnwPinnedEdge = nil
				return nil
			}
			let offsetOver = pinned == .bottom ? max(offset - restBottom, 0) : max(restTop - offset, 0)
			return (pinned, max(offsetOver, max(fingerPull, 0) * 0.5), offsetOver)
		}

		let atBottom = offset >= restBottom - slack
		let atTop = offset <= restTop + slack

		let edge: NNWScrollEdge
		if atBottom, atTop {
			// 🔴 **两头同时成立** —— 这在**内容比屏幕还矮的短文章**里是常态
			// (`restBottom` 被 `max(..., restTop)` 夹成了 `restTop`,首尾是同一个点)。
			// 用户 2026-08-09 截图报的正是这种页面:一条 `—` 一直挂在那儿。
			//
			// 这时"我贴的是哪一头"只能由**手指往哪边拉**来定:
			// 往上拉 = 想往后走 = 底;往下拉 = 想往前走 = 顶。
			// 📌 判据:**位置说不清的时候,问意图。**
			guard let translationY, abs(translationY) > 0.5 else { return nil }
			edge = translationY < 0 ? .bottom : .top
		} else if atBottom {
			edge = .bottom
		} else if atTop {
			edge = .top
		} else {
			return nil
		}

		// 真的超出去了多少(不回弹的地方恒为 0)
		let offsetOver = edge == .bottom ? max(offset - restBottom, 0) : max(restTop - offset, 0)

		guard let translationY else {
			return offsetOver > 0 ? (edge, offsetOver, offsetOver) : nil
		}

		// 刚贴上这一头 → 记下此刻的手指位移,之后的量都从这儿算
		nnwPinnedEdge = edge
		nnwPinnedTranslationY = translationY
		return (edge, offsetOver, offsetOver)
	}

	/// 当前这一页正文的滚动视图。
	///
	/// ⚠️ `WebViewController.webView` 是 `private`,扩展也够不着,所以从视图树里现找。
	/// 找的是**公开类型 `UIScrollView`**,不碰任何私有 API。
	private var nnwArticleScrollView: UIScrollView? {
		guard let page = nnwCurrentPage as? WebViewController else { return nil }
		@MainActor func find(_ view: UIView) -> UIScrollView? {
			// ⚠️ **先认 `WKWebView` 自己的那个** —— 只写 `as? UIScrollView` 的话,
			// 深度优先撞上的可能是别的滚动视图(2026-08-09:按类型找东西,
			// 前提是那个类型在树里唯一;不唯一时得说清楚要哪一个,L131 第 ④ 条)。
			if let web = view as? WKWebView { return web.scrollView }
			if let scrollView = view as? UIScrollView { return scrollView }
			for sub in view.subviews {
				if let found = find(sub) { return found }
			}
			return nil
		}
		return find(page.view)
	}

	// MARK: 翻页指示器

	/// 按当前的"拽过头"程度更新指示器。**每一帧都调**。
	private func nnwUpdatePageTurnHint(translationY: CGFloat) {

		guard !nnwIsShowingNoMoreArticlesPage,
			  let over = nnwOverscrollEdge(translationY: translationY) else {
			nnwDismissPageTurnHint()
			nnwResetContentPushBack(animated: true)		// 离开边缘 → 正文弹回原位
			// 手指反向回拽到脱离边缘了 —— 那就是明确的"不翻了",取消。
			nnwOverscrollArmedEdge = nil
			return
		}

		// 这一头有没有下一站。
		//
		// 🔴 **2026-08-09 第五轮改:没有下一站时不再"什么都不做"。**
		//
		// 原来这里是 `guard … else { return }` —— **静默早退**。真机日志钉死了它的代价:
		// 用户在列表第一篇上往下拽,`超出上` 到过 **245pt**,而 `峰值=0.000000`
		// (根本没走到记峰值那一行)—— 不出线、不震、不翻,
		// **可正文照样橡皮筋弹出去 250pt**。用户看到的是"动了但没翻",像功能坏了。
		//
		// 📌 判据:**"没有下一站"是一个要**告诉**用户的事实,不是一个可以沉默的分支。**
		// 那 250pt 的位移不是我们画的(是 WebView 自己的橡皮筋),我们管不了它动不动,
		// 但我们能决定它动的时候屏幕上写着什么。
		//
		// 用户 2026-08-09 拍板的做法:**线照出,但它是"到头"的样子** ——
		// 不弯(永远是 `—`)、淡一档、松手不翻、不震。
		// 🔴 第十三轮:不再只问"有没有下一站",而是问"是哪一种没有" —— 见 `NNWPageTurnHintState`。
		let hintState = nnwHintState(for: over.edge)
		let hasDestination = (hintState == .ready)

		// 🔴 **拽了才出现,不是贴到边就出现**(用户 2026-08-09:
		// 「下方这个形变之前的 `—` 会一直存在,而不是触发才出现」)。
		//
		// 原来只要贴住边缘就画一条 `—`,而**贴住边缘是读到底/读到顶的常态** ——
		// 短文章更极端:内容比屏幕矮,首尾是同一个点,**一动就贴着**,那条线就一直挂在那儿。
		// 📌 判据:**指示器要表达的是"你正在做这件事",不是"你有资格做这件事"。**
		guard over.amount >= Self.nnwHintMinPull else {
			nnwDismissPageTurnHint()
			nnwResetContentPushBack(animated: true)
			nnwOverscrollArmedEdge = nil
			return
		}

		/// 没缓动过的原始比例 —— **判定只看它**
		let raw = over.amount / Self.nnwOverscrollThreshold
		/// 缓动过的比例 —— **画面只看它**(先快后慢,见 `nnwEase`)
		let shaped = Self.nnwEase(raw)

		let hint = nnwPageTurnHint ?? {
			let created = NNWPageTurnHintView()
			view.addSubview(created)
			nnwPageTurnHint = created
			return created
		}()

		// [阅读] 2026-08-09 用户:「让标题部分同时被下拉,把给 ^ 的位置让出来」。
		//
		// 屏幕上该让出来的总空隙 = 缓动比例 × 上限。**越拽越难拽,就是橡皮筋的手感。**
		//
		// ⚠️ **只补滚动视图自己没让出来的那一部分**:
		// 顶部会橡皮筋、内容本来就跟着走了;底部不回弹、一点没动。
		// 不减这一刀的话,顶部就会**动两次**(内容自己走一段、我们再推一段),位移翻倍。
		// 📌 判据:**做"补偿"之前,先问系统已经替你做了多少。**
		let visualGap = shaped * Self.nnwPushLimit
		// ⚠️ **到头的时候不推正文** —— 推开是"给新的一页让位",而这一头根本没有新的一页。
		// 让出一块空隙却什么都不进来,比不让更让人以为出了故障。
		// (顶部本来就会橡皮筋,`alreadyMoved` 常常已经上百点,这一刀多数时候本来也是 0。)
		nnwSetContentPushBack(edge: over.edge,
							  distance: hasDestination ? max(visualGap - over.alreadyMoved, 0) : 0)
		hint.update(edge: over.edge, progress: shaped,
					gap: hasDestination ? max(visualGap, over.alreadyMoved) : over.alreadyMoved,
					state: hintState, in: view)

		// ⚠️ 临时探针(2026-08-09):记下这一拽**到过的最大值**。
		nnwOverscrollPeak = max(nnwOverscrollPeak, over.amount)

		// 🔴 **每一帧按当前状态重算"够不够",拽回去就取消**(2026-08-09 用户:
		// 「触发之后如果手在往回拽然后放开,依然会翻页……不应该翻页」)。
		//
		// 上一版为了对抗"内边距跳变把量抹掉"而写成了**只锁不退**,那是**在错误的层面上打补丁** ——
		// 真正的病根在量法里,已经用"贴住就锁边、只认手指反向"治好了(见 `nnwOverscrollEdge`),
		// `amount` 现在是**跟着手指走的量**,不会被系统的排版变化伪造。
		// 前提修好了,这里就该回到最自然的规则:**当下够不够,就是够不够。**
		//
		// 📌 判据:**一个补丁如果要求"状态只能单向变化",先回头看是不是量错了** ——
		// 单向锁死是掩盖测量问题的典型手法,代价是把用户的反悔一起锁掉了。
		// ⚠️ **到头的那一头永远不算"拽够"** ——
		// 不震、松手也不翻。震动是"松手就成"的承诺,这一头兑现不了,就不能给。
		let armed = raw >= 1 && hasDestination
		if armed, nnwOverscrollArmedEdge == nil {
			nnwOverscrollHaptic?.impactOccurred()	// 跨过门槛的那一下 —— "手感"多半就是这一下
		}
		nnwOverscrollArmedEdge = armed ? over.edge : nil
	}

	/// 这一头到底有没有"下一站"。没有就不该出指示器。
	///
	/// 🔴 **2026-08-09 修**:原来"上一篇"这一头写的是
	/// `articles.firstIndex(of: current)`,找不到就 `return false`。
	/// 而**读过的文章会从「全部未读」这类列表里消失** —— 于是"找自己"必然失败,
	/// 箭头不出、也永远翻不了页。
	/// 实测日志:**超出上 209pt(门槛才 56),仍然判定"没拽够"**。
	///
	/// 📌 这和同一天修的 `nnwFindNextUnreadArticle` 是**同一个根**,
	/// 我上一轮只修了那一处、漏了这一处。判据:
	/// **"在列表里找自己"这个动作在会自我删减的列表上随时失效 ——
	/// 一旦发现某处这么写,就要把同一个文件里所有这么写的地方一起查。**
	///
	/// 现在改成问**上游自己**(`isPrevArticleAvailable`)—— 那是 dock 上「上一篇」
	/// 那颗键的可用状态用的同一个来源,它比我们自己数索引可靠。
	/// [阅读] 趁列表还认得当前这篇,把「列表里排在它前面的那一篇」存进**进门锚**。
	///
	/// 由 `ArticleViewController.article` 的 `didSet` 每次调用 —— 也就是**每次换文章**
	/// (从列表点进来、翻页、恢复现场)都刷新一次。为什么必须在那一刻记,见 `nnwEntryNeighbor`。
	///
	/// ⚠️ 三条分支都要有明确交代,**不能"查不到就悄悄留着上一次的值"**:
	/// - 找得到自己且**前面还有** → 记下来
	/// - 找得到自己且**自己就是第一篇** → **清掉**(它是真的到头了,留着旧值会造出一个假的"上一篇")
	/// - **找不到自己** → 保持不动。锚是带着"给谁用"一起存的,对不上时自然不会被用,
	///   而这一篇之前存下的那个锚正是我们要救的东西。
	func nnwRememberListNeighbor() {
		guard let coordinator, let article else { return }

		if let index = coordinator.articles.firstIndex(of: article) {
			nnwEntryNeighbor = index > 0 ? [article, coordinator.articles[index - 1]] : nil
			nnwEntryNeighborByDate = false
			return
		}

		// 🔴 **找不到自己:原来到这里就 return,于是锚"根本没建起来"**(2026-08-09 第十三轮修)。
		//
		// 上面那条注释写着「找不到自己 → 保持不动,这一篇之前存下的锚正是我们要救的东西」——
		// 那句话有个**没说出来的前提:它之前确实存过一个**。真机日志钉死了不成立的那种:
		// **启动时状态恢复进来的第一篇**,上次读完就已经是已读,压根不在「全部未读」里,
		// 从来没有"列表认得它"的那一刻 → 锚永远是空的 → 四条路全落空 →
		// 用户拽了 190~220pt 却看到一条"到头"的线(日志里 5 次,形状一模一样)。
		//
		// 📌 判据:**"趁它还成立的时候存下来"这个办法,前提是"那一刻确实存在过"。**
		//
		// 用户拍板的补法 (a):这时**按日期在列表里找紧挨着我的那一篇**当锚。
		// ⚠️ 只在"这一篇还没有自己的锚"时补 —— 已经有的说明它曾经是列表里的一员,那个更准。
		if let pair = nnwEntryNeighbor, pair.count == 2, pair[0] == article { return }

		let byDate = nnwPreviousArticleByDate(for: article, coordinator: coordinator)
		if let byDate {
			nnwEntryNeighbor = [article, byDate]
			nnwEntryNeighborByDate = true
		}

		// ⚠️ 临时探针(第十三轮,查完就删):**这条兜底藏在两层 guard 后面,
		// 不打一行日志就没法证明它被走到过** —— L124/L132 那个"钩子挂在不成立的分支上"
		// 的错误,这个项目里一天之内犯过三次。所以**无条件打**,补不上也打。
		NNWArticlePagingLog.logger.info("""
			[拽] 进门锚 列表里找不到这一篇 \(article.articleID.prefix(8), privacy: .public) \
			| 按日期兜底=\(byDate == nil ? "🔴没找到" : "找到了", privacy: .public) \
			| 按源分组=\(coordinator.groupByFeed, privacy: .public) \
			| 最新在前=\(coordinator.sortDirection == .orderedDescending, privacy: .public) \
			| 列表共=\(coordinator.articles.count, privacy: .public) 篇
			""")
	}

	/// [阅读] 按**日期**在列表里找"排在我前面的那一篇"。只给 `nnwRememberListNeighbor` 兜底用。
	///
	/// ## 为什么放在这里算,而不是等要用的时候再算
	/// 闸门 `nnwHasDestination` 是**每一帧**都要问的(拽的过程中)。
	/// 列表有 7700 篇,每帧扫一遍就是自己制造卡顿 —— 而抖动正是这一轮要查的东西,
	/// **探针绝不能自己成为病因**。所以只在**换文章那一刻**算一次,结果存进同一个进门锚。
	/// 顺带白拿一个好处:**门和路读的是同一个锚,天然是同一套条件**,
	/// 不会再出现第五轮那种「门比路窄,白白挡掉合法操作」。
	///
	/// ## 不假设排序方向
	/// 「上一篇」= 列表里排在我前面的那一篇。它到底"更新"还是"更旧",由用户的排序设置决定,
	/// 所以这里**读 `coordinator.sortDirection`**,不靠猜(L123 的老账:先问这两个值平时谁大)。
	/// - 最新在前 → 上一篇 = 比我新的那些里面**最旧**的一篇(离我最近的那个)
	/// - 最旧在前 → 上一篇 = 比我旧的那些里面**最新**的一篇
	///
	/// ⚠️ **按源分组时直接放弃**(返回 nil):那种排法下"相邻"由源决定,和日期没关系,
	/// 硬按日期挑会给出一篇根本不相邻的文章 —— **张冠李戴的"上一篇"比没有更难查**(L123)。
	/// 这种情况留给 (c) 那条「这里断了」的线去诚实表达。
	private func nnwPreviousArticleByDate(for article: Article, coordinator: SceneCoordinator) -> Article? {

		guard !coordinator.groupByFeed else { return nil }

		let mine = article.logicalDatePublished
		let newestFirst = coordinator.sortDirection == .orderedDescending

		return coordinator.articles.reduce(nil) { (best: Article?, candidate: Article) -> Article? in
			let date = candidate.logicalDatePublished
			// 只看"排在我前面"那一侧的候选
			guard newestFirst ? date > mine : date < mine else { return best }
			guard let best else { return candidate }
			// 在那一侧里挑离我最近的
			return newestFirst
				? (date < best.logicalDatePublished ? candidate : best)
				: (date > best.logicalDatePublished ? candidate : best)
		}
	}

	/// 进门锚里给**当前这一篇**准备的"上一篇"。对不上就当没有。
	private var nnwAnchoredPreviousArticle: Article? {
		guard let current = (nnwCurrentPage as? WebViewController)?.article,
			  let pair = nnwEntryNeighbor, pair.count == 2, pair[0] == current else { return nil }
		return pair[1]
	}

	/// 🔴 **2026-08-09 第五轮再修:门必须和路是同一套条件。**
	///
	/// 上一版这里只问 `isPrevArticleAvailable` 一条,而真正干活的
	/// `nnwGoToPreviousArticle` 有**三条**路(来路栈 / 列表前一篇 / 上游)。
	/// **门比路窄** —— 只要"来路栈里有东西、而协调器在列表里找不到自己",
	/// 门就会挡掉一次本来走得通的翻页,表现为**动画放了、就是不换页**。
	///
	/// 这个坑第五轮的真机日志里**没有暴露**,因为用户当时没开"隐藏已读"
	/// (`smartFeedsHidingReadArticles: []`),列表不自我删减,`firstIndex(of:)` 不会落空。
	/// **也就是说它是潜伏的,不是不存在的** —— 一旦打开"隐藏已读",
	/// 往下翻几篇后读过的从列表消失,`门=false` 而来路栈明明有货,老症状立刻回来。
	///
	/// 📌 判据:**守门的条件必须和干活的条件是同一套。门比路窄 = 白白挡掉合法操作。**
	/// 所以下面三条**和 `nnwGoToPreviousArticle` 里的三条一一对应**,改一边就要改另一边。
	/// [阅读] 这一头是「有下一站」「确认到头」还是「失联」(2026-08-09 第十三轮,用户拍板的 (c))。
	///
	/// ⚠️ **闸门仍然只有 `nnwHasDestination` 一个** —— 这里只是在"没有下一站"之后
	/// 再分一次类,决定**画哪一种线**。不新增放行条件,所以不会又搞出"门和路不是同一套"。
	private func nnwHintState(for edge: NNWScrollEdge) -> NNWPageTurnHintState {

		if nnwHasDestination(for: edge) { return .ready }
		// 底部永远有下一站(没有下一篇未读时是彩蛋页),照理走不到这儿
		guard edge == .top else { return .atEnd }

		guard let coordinator,
			  let current = (nnwCurrentPage as? WebViewController)?.article else { return .lost }

		if let index = coordinator.articles.firstIndex(of: current) {
			// 找得到自己:第 0 行 = 真的到头(事实);不是第 0 行却无路可走 = 不该发生,当失联报
			return index == 0 ? .atEnd : .lost
		}
		// 列表里找不到我,而且按日期也没能补出锚(按源分组时会这样)—— 我不知道上一篇是谁
		return .lost
	}

	private func nnwHasDestination(for edge: NNWScrollEdge) -> Bool {
		guard let coordinator, nnwCurrentPage is WebViewController else { return false }
		switch edge {
		case .bottom:
			// 没有下一篇未读时仍然算"有"—— 那一站是彩蛋页,松手会翻到它
			return true
		case .top:
			// ① 来路栈:我从哪儿来就能回哪儿去,最可靠
			if !nnwPageBackStack.isEmpty { return true }
			// ② 列表里排在前面那一篇
			if let current = (nnwCurrentPage as? WebViewController)?.article,
			   let index = coordinator.articles.firstIndex(of: current), index > 0 { return true }
			// ③ 进门锚 —— 列表已经把这一篇删掉了,但打开它的那一刻我们记下了它前面是谁
			if nnwAnchoredPreviousArticle != nil { return true }
			// ④ 交给上游 —— ⚠️ 这里**不能**无条件算"有":上游的 `selectPrevArticle()`
			//    自己就卡在 `isPrevArticleAvailable` 上,它为假时那条路同样什么都不会发生。
			return coordinator.isPrevArticleAvailable
		}
	}

	/// [阅读] 把正文整体推开,给箭头让出位置(底部拽 → 内容上移;顶部拽 → 内容下移)。
	///
	/// ⚠️ **用 `transform` 平移,绝不碰 `contentOffset` / `contentInset`** ——
	/// 那两个一动就会反过来触发滚动回调、改变"到没到底"的判定,
	/// 和我们正在读的那套量法成环(L63/L73 那一族的老账)。
	/// `transform` 是画上去的位移,滚动状态一个字节都不变。
	///
	/// ⚠️ 推的是**翻页容器**那一层,不是 WebView 自己 —— 让出来的缝里露出的是
	/// 文章页的底色,而不是网页内部的白边。
	private func nnwSetContentPushBack(edge: NNWScrollEdge, distance: CGFloat) {
		guard let container = children.compactMap({ $0 as? UIPageViewController }).first?.view else { return }
		let shift = edge == .bottom ? -distance : distance
		container.transform = distance > 0.5 ? CGAffineTransform(translationX: 0, y: shift) : .identity
	}

	/// 松手/取消时把推开的正文放回去。
	///
	/// ⚠️ **必须在翻页动画开始之前复位**:翻页那一下也要用这一层做位移,
	/// 带着残留的 transform 进去,新页会从一个歪掉的位置滑进来。
	private func nnwResetContentPushBack(animated: Bool) {
		guard let container = children.compactMap({ $0 as? UIPageViewController }).first?.view,
			  container.transform != .identity else { return }
		guard animated else {
			container.transform = .identity
			return
		}
		UIView.animate(withDuration: 0.22, delay: 0,
					   options: [.allowUserInteraction, .beginFromCurrentState]) {
			container.transform = .identity
		}
	}

	private func nnwDismissPageTurnHint() {
		guard let hint = nnwPageTurnHint else { return }
		// ⚠️ **引用立刻断开,不等淡出动画结束**。
		// 原来是在动画的 completion 里才置 nil —— 那期间如果又有一帧 `update` 进来,
		// 它会拿到这个正在淡出的实例、把 alpha 设回 1,而那条 completion 随后照样
		// 把它从视图树里摘掉(或者反过来:摘掉之后引用还在)。两种时序都能留下一个
		// **谁也管不着的孤儿视图**,那正是"那条线一直挂在那儿"的另一种成因。
		// 📌 判据:**"我不再用它了"要立刻生效;收尾动画是它自己的事,别让别人等它。**
		nnwPageTurnHint = nil
		hint.dismiss { }
	}

	// ⚠️ 这里原本有个 `nnwCurrentScrollEdge()`,用上游的 `canScrollUp/Down` 判"在不在边缘"。
	// 2026-08-09 重做时删掉了:那两个方法回答的是**"还能不能翻一页"**(整页滚动那个语义),
	// 不是"超出了多少" —— 拿它只能得到一个"在/不在"的布尔值,做不出**渐进**的指示器。
	// 现在统一走 `nnwOverscrollEdge()`(直接读滚动视图的偏移),一个来源同时给出方向和量。

	/// [阅读] 去列表里的下一篇未读;没有了就露出彩蛋页。
	///
	/// 语义和原来"左滑翻页"时完全一样(**只在当前这个列表里找**,不跨源),
	/// 只是触发方式从左滑换成了"在底部再拽一把"。
	private func nnwGoToNextUnread() {

		guard let current = (nnwCurrentPage as? WebViewController)?.article else { return }

		if let next = nnwFindNextUnreadArticle(after: current) {
			nnwTurnPage(to: next, forward: true)
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

	/// 造一页装着某篇文章的 `WebViewController`。
	///
	/// ⚠️ **上游有一个一模一样的 `createWebViewController`,但它住在 `private extension` 里,
	/// 别的文件够不着。** 与其把那个扩展从 `private` 改成内部(那会一次性放开十来个方法的可见性,
	/// 平白扩大对上游文件的改动面),不如在这儿照抄这四行 —— 它只用到公开的东西。
	/// 📌 代价说清楚:**以后上游若给那个工厂加了新的初始化步骤,这里不会自动跟上。**
	/// 那个函数三年没动过,风险可接受;真要改的话这条注释就是线索。
	private func nnwMakeArticlePage(_ article: Article) -> WebViewController {
		let controller = WebViewController()
		controller.coordinator = coordinator
		controller.delegate = self
		controller.setArticle(article)
		return controller
	}

	/// [阅读] 回到**刚才那一篇**。
	///
	/// 🔴 优先走**来路栈**(见 `nnwPageBackStack`)—— 用户 2026-08-09 报
	/// 「向下翻篇后,再往上翻篇就只能触发动画,但翻不动」,病根就是原来只会
	/// `articles.firstIndex(of: 当前这篇)` 再取前一个:
	/// 在「全部未读」这类会自我删减的列表里,刚读过的那几篇随时消失,找不到自己就落空。
	///
	/// 退路仍然保留(第一次进来、栈是空的时候要用):列表里的前一篇 → 上游的 `selectPrevArticle()`。
	private func nnwGoToPreviousArticle() {

		guard let coordinator else { return }

		// ① 来路栈:我从哪儿来,就回哪儿去。**最可靠,而且正是用户心里的"上一篇"**
		if let previous = nnwPageBackStack.popLast() {
			nnwTurnPage(to: previous, forward: false, remembersCurrent: false)
			return
		}

		// ② 栈是空的(直接从列表点进来的第一篇)→ 退回"列表里排在前面那一篇"
		if let current = (nnwCurrentPage as? WebViewController)?.article,
		   let index = coordinator.articles.firstIndex(of: current), index > 0 {
			nnwTurnPage(to: coordinator.articles[index - 1], forward: false, remembersCurrent: false)
			return
		}

		// ③ 进门锚:列表已经不认得这一篇了(读过就被移出「全部未读」),
		//    但打开它的那一刻我们记下了它前面是谁。见 `nnwEntryNeighbor`。
		if let anchored = nnwAnchoredPreviousArticle {
			nnwTurnPage(to: anchored, forward: false, remembersCurrent: false)
			return
		}

		// ④ 最后的退路:交给上游。⚠️ 它靠"当前选中在时间线的第几行",也可能落空,
		// 但**宁可少一个动画,也不要什么都不发生**。
		coordinator.selectPrevArticle()
	}

	/// [阅读] 2026-08-09:**带垂直翻页动画**地换到另一篇文章。
	///
	/// ## 为什么要单独做这件事(用户:「动画很生硬」)
	///
	/// 原来两个方向都是直接 `coordinator.selectArticle(...)`。那条路最终会走到
	/// `ArticleViewController.article` 的 `didSet`,而它是**复用同一个 `WebViewController`**、
	/// 把内容就地换掉的(`controller.setArticle(article)` 后
	/// `setViewControllers([controller], animated: false)`)——
	/// **同一个视图、内容一瞬间换掉**,当然没有任何过渡可言。
	///
	/// ## 做法:给目标文章**造一页新的**,让翻页容器自己动
	///
	/// 容器已经改成竖向(见 `ArticleViewController` 里那处 `.vertical`),
	/// 所以 `setViewControllers(direction:animated: true)` 给出来的就是
	/// **两页一起走的整页竖向推移** —— 这是系统在动真视图,不是我自己画一段位移糊弄。
	///
	/// ⚠️ **动画结束后直接调上游那个 `didFinishAnimating`**,不自己抄一遍收尾:
	/// 那里有六件事(通知协调器换选中、刷新提取按钮状态、重置翻译按钮、重新盯滚动、
	/// 收放 dock、停掉旧页的 WebView 活动)。抄一遍必然漏,而且以后上游加一件我们不会跟。
	/// 判据:**能复用同一个收尾入口就别复制它**(这一族的账在本项目吃过好几次)。
	///
	/// ⚠️ 收尾里的 `coordinator.selectArticle` 会再触发一次 `article` 的 `didSet` ——
	/// 但那里有 `controller.article != article` 的守卫,此刻已经相等,**不会再换一次视图**。
	/// - Parameter remembersCurrent: 往**后**翻时为 true —— 把当前这篇压进来路栈,
	///   这样"上一篇"永远能原路返回。往前翻(从栈里弹出来的)时为 false,否则会左右横跳。
	private func nnwTurnPage(to article: Article, forward: Bool, remembersCurrent: Bool = true) {

		guard let pageViewController = children.compactMap({ $0 as? UIPageViewController }).first else {
			coordinator?.selectArticle(article, animations: [.select, .scroll, .navigation])
			return
		}

		// 🔴 **上一次翻页的动画还没放完 → 直接不理这一次**(2026-08-09 第七轮真机日志)。
		//
		// 日志里「翻页中」这个状态**横跨了五次松手** —— 用户在动画进行中又拽了好几把,
		// 每一把都又发起一次转场,**几次转场叠在同一个容器上**。伴随的症状很明显:
		// - 量到的滚动视图是 `inset上=0 contentH=874 offset=0`(一个还没排过版的新页)
		// - `我这页在第=7 行` 而 `协调器认的在第=8 行`(两边对不上,收尾还没跑)
		//
		// 上游自己也怕这个:`ArticleViewController` 里那段 `isPageTransitionInProgress`
		// 的注释写着「转场进行中调 setViewControllers 会踩 UIPageViewController 的内部断言并崩溃」。
		//
		// 📌 判据:**一个带动画的状态机,必须自己拒绝在动画期间被重新发起** ——
		// 指望调用方"别按那么快"是靠不住的。
		guard !nnwIsTurningPage else {
			NNWArticlePagingLog.logger.info("[拽] 翻页请求被忽略:上一次的动画还没放完")
			return
		}

		if remembersCurrent, let current = (nnwCurrentPage as? WebViewController)?.article {
			var stack = nnwPageBackStack
			stack.append(current)
			// 只留最近 30 条 —— 再多也没人往回翻那么远,白占内存
			if stack.count > 30 { stack.removeFirst(stack.count - 30) }
			nnwPageBackStack = stack
		}

		let previous = pageViewController.viewControllers ?? []
		let page = nnwMakeArticlePage(article)

		// [阅读] 用户 2026-08-09:「**稍微慢一点**的翻页动画」。
		//
		// ⚠️ `setViewControllers(animated:)` 的时长是系统写死的,没有参数可调。
		// 唯一干净的旋钮是**把这一层图层树的时间流速调慢** —— `layer.speed` 就是干这个的
		// (CoreAnimation 的时间系统本来就支持每层不同的流速,不是 hack,更不是私有 API)。
		//
		// ⚠️ **必须在结束时还原**,否则这一页之后所有动画都会一直慢着 ——
		// 这正是本项目最怕的"隐性状态"(L119 那一族:一次性写进去、没人负责收回来)。
		// 所以还原写在 completion 里,而且**先还原再做收尾**,免得中途 return 漏掉。
		let container = pageViewController.view
		container?.layer.speed = Self.nnwPageTurnSpeed

		// [外观] 竖起"正在翻页"的牌子 —— `ArticleHeaderBar` 看到它就把飞行进度冻住。
		// ⚠️ **必须在结束时放倒**,和上面那个 `layer.speed` 是同一类隐性状态(L119)。
		nnwTurnToken &+= 1
		let token = nnwTurnToken
		nnwIsTurningPage = true

		// 🔴🔴 **收尾必须有两条路,而且只有先到的那条算数**(2026-08-09 第九轮真机日志)。
		//
		// 实测:`setViewControllers(animated:)` 的 **completion 有时根本不回调** ——
		// 日志里 `翻页中` 从某一刻起**再也没放倒**,证据是
		// `我这页在第=3 行` 而 `协调器认的在第=4 行`(收尾里的 `selectArticle` 从没跑)。
		//
		// 代价有多大:这一轮我在这个牌子上挂了两样东西,牌子一卡就**双双变成硬故障** ——
		// - 重入守卫 → **之后所有翻页永远被拒绝**
		// - 冻结飞行进度 → **标题永远停在大标题态、不再跟随滚动**(用户截图:大标题压在正文上)
		//
		// 📌 判据(L119 那一族最贵的一条,这次是自己踩的):
		// **凡是"写进去要靠某个回调收回来"的状态,先问一句"那个回调保证会来吗"。
		// 不保证 → 必须自带兜底,否则你就是把一个隐藏缺陷升级成了硬故障。**
		//
		// ⚠️ 我加守卫的那一轮,日志里其实**已经**有"翻页中横跨五次松手"的证据了 ——
		// 当时它只是让画面抖一下;是我的守卫把它变成了永久锁死。
		// **判据:给一个状态加"拒绝"语义之前,先确认这个状态一定会被解除。**
		let finishTurn: (Bool, Bool) -> Void = { [weak self] finished, viaTimeout in
			guard let self, self.nnwTurnToken == token else { return }
			self.nnwTurnToken &+= 1			// 推走令牌 → 另一条路自动作废
			container?.layer.speed = 1
			self.nnwIsTurningPage = false
			// 牌子放倒之后主动叫一次排版:动画期间飞行进度是冻住的,
			// 这一下让它用**落定后的真实几何**重算一遍。
			page.view.setNeedsLayout()
			NNWArticlePagingLog.logger.info(
				"[拽] 翻页收尾 \(viaTimeout ? "🔴超时兜底" : "系统回调", privacy: .public) finished=\(finished, privacy: .public)")
			self.pageViewController(pageViewController,
									didFinishAnimating: finished,
									previousViewControllers: previous,
									transitionCompleted: finished)
		}

		pageViewController.setViewControllers([page],
											  direction: forward ? .forward : .reverse,
											  animated: true) { finished in
			finishTurn(finished, false)
		}

		// 兜底:动画名义时长约 0.35 秒,0.7 倍速下约 0.5 秒。给到 0.9 秒还没回调就自己收尾。
		DispatchQueue.main.asyncAfter(deadline: .now() + Self.nnwTurnTimeout) {
			finishTurn(true, true)
		}
	}

	/// 翻页收尾的兜底时限(秒)。**宁可早一点收,也不要卡住** ——
	/// 收早了最多是标题提前恢复跟随滚动,收不了就是整个翻页功能锁死。
	private static var nnwTurnTimeout: TimeInterval { 0.9 }

	/// 翻页动画的时间流速。1 = 系统原速,越小越慢。嫌快嫌慢**只改这一个数**。
	private static var nnwPageTurnSpeed: Float { 0.7 }
}

/// 正文超出了哪一头。
enum NNWScrollEdge: String {
	case top
	case bottom
}

/// [阅读] 这一头此刻是什么状况 —— 🔴 **「到头」和「失联」必须分开**
///(2026-08-09 第十三轮,用户拍板的 (c);第十二轮的代码把这两件当成同一件,都画"到头")。
///
/// 判据:**前者是一个事实,后者是我不知道。** 拿"到头"去表达"我不知道",
/// 是给用户一个**明确但错误的承诺** —— 屏幕上写着"上面没有了",而上面明明还有文章。
enum NNWPageTurnHintState {
	/// 有下一站,松手就翻
	case ready
	/// **确认**到头:我就在列表第 0 行,上面确实没有了
	case atEnd
	/// **失联**:列表里找不到我,按日期也补不出锚(例如按源分组)。**我不知道上一篇是谁。**
	case lost
}

// MARK: - 「松手就翻页」的箭头

/// [阅读] 2026-08-09 用户要求:「滑到一定程度,屏幕的下方或者上方就有一个 v 或者 ^,
/// 提示要翻页,然后松手之后,就显示一个垂直的翻页动画」。
///
/// ## 用户 2026-08-09 定下的四条(**都别改回去**)
///
/// 1. **箭头指的是"新文章从哪一头来",不是"手指往哪拽"。**
///    在底部往上拽 → 下一篇从下面来 → **`v`**;在顶部往下拽 → 上一篇在上面 → **`^`**。
///    ⚠️ 我第一版做反了(按"手指方向"),用户当场指出。
///    判据:**箭头是"路标",指向要去的地方;它不是对手势的复述** ——
///    手势用户自己正在做,不需要被告知。
/// 2. **无边框、无背景**,就是一个光秃秃的箭头。**别再套 `NNWSoftGlassButton`** ——
///    第一版套了圆钮,用户:「不要是按钮形式」。它是提示,不是可以点的东西。
/// 3. **比文章页右上角那对上下箭头大 1.5 倍**(那两颗是上游的
///    `prevArticleBarButtonItem` / `nextArticleBarButtonItem`,系统默认字号,画出来约 19pt)。
/// 4. **颜色用 `NNWSoftMaterial.ink`** —— 也就是底栏 dock 图标那个墨色。
///    ⚠️ 用户的原话是「不用适配主题色,用简单的黑色」:
///    **主题色**(可换色的那个橙)确实不该用;但这个墨色**必须跟深浅色走**
///    (深色下自动变浅),否则深色模式里黑箭头直接看不见。
///    两个要求不冲突 —— `ink` 正是"和底栏控件相同"的那一个。
///
/// ⚠️ 它**不接触摸**(`isUserInteractionEnabled = false`):收下触摸只会挡住正文。
@MainActor final class NNWPageTurnHintView: UIView {

	/// 箭头本体。**用图形层画,不生成图片** —— 形状每一帧都在变(`—` 弯成 `^`),
	/// 逐帧渲染位图太浪费,改路径几乎不要钱。
	private let shape = CAShapeLayer()
	/// 上次解析描边色时的深浅色。`CGColor` 不跟深浅色走(L119),变了才重解析。
	private var strokeStyle: UIUserInterfaceStyle?

	// MARK: 形状(三个数各自独立,嫌不对只改对应那一个)

	/// 静止(progress 0)时那条 `—` 有多宽
	private static let dashWidth: CGFloat = 44
	/// 拽够(progress 1)时那个 `v` 有多宽
	private static let chevronWidth: CGFloat = 72
	/// 拽够时的"落差"(两端到尖的高度差)。越小越扁
	private static let chevronDrop: CGFloat = 13
	/// 笔画粗细。参考 dock 那套手绘图标(24 画布上 2.1pt),按这个宽度放大
	private static let lineWidth: CGFloat = 3.5

	/// 画布高度(留足落差 + 线宽,免得圆头被切平)
	private static var canvasHeight: CGFloat { chevronDrop + lineWidth * 2 }

	override init(frame: CGRect) {
		super.init(frame: frame)
		isUserInteractionEnabled = false
		backgroundColor = .clear
		shape.fillColor = UIColor.clear.cgColor
		shape.lineWidth = Self.lineWidth
		shape.lineCap = .round
		shape.lineJoin = .round
		layer.addSublayer(shape)

		// 深浅色变了 → 清记号,下一帧重解析描边色
		registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: NNWPageTurnHintView, _) in
			view.strokeStyle = nil
			view.setNeedsLayout()
		}
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { fatalError("不从故事板加载") }

	/// 按进度算出那条线的形状:**progress 0 是一条平的 `—`,1 是完整的 `^` / `v`**,中间连续过渡。
	///
	/// ⚠️ 用户 2026-08-09:「应该是一个从 `—` 变成 `^` 或者 `v` 的过程
	/// (discard 掉之前那个由浅变深的过程)」。
	/// 所以**深浅不再表达进度**(alpha 恒为 1),进度全部由**形状**表达 ——
	/// 宽度从 44 张到 72、落差从 0 长到 13。
	/// 📌 判据:**一个视觉量只表达一件事。** 之前拿 alpha 同时表达"在不在"和"够不够",
	/// 两件事挤在一个通道里,哪件都说不清楚。
	private static func path(progress: CGFloat, in size: CGSize, pointingDown: Bool,
							 broken: Bool = false) -> CGPath {

		let t = min(max(progress, 0), 1)
		let width = dashWidth + (chevronWidth - dashWidth) * t
		let drop = chevronDrop * t

		let left = (size.width - width) / 2
		let right = left + width
		// 尖端始终落在画布正中,两端随落差往反方向抬 —— 这样"弯"起来是对称的,不会整体上下窜
		let mid = size.height / 2
		let ends = pointingDown ? mid - drop / 2 : mid + drop / 2
		let tip = pointingDown ? mid + drop / 2 : mid - drop / 2

		let path = UIBezierPath()

		// 「失联」:同样是一条平线,但**中间缺一口**。
		// 它和"到头"那条完整的平线**一眼分得开**,而语义正好对上:
		// 到头 = 上面没有了(线是连着的、只是不弯);失联 = 这里断了,我不知道上一篇是谁。
		// (broken 只在 progress 被按死成 0 时用,所以宽度就是那条 `—` 的宽度。)
		if broken {
			path.move(to: CGPoint(x: left, y: mid))
			path.addLine(to: CGPoint(x: size.width / 2 - brokenGap / 2, y: mid))
			path.move(to: CGPoint(x: size.width / 2 + brokenGap / 2, y: mid))
			path.addLine(to: CGPoint(x: right, y: mid))
			return path.cgPath
		}

		path.move(to: CGPoint(x: left, y: ends))
		path.addLine(to: CGPoint(x: size.width / 2, y: tip))
		path.addLine(to: CGPoint(x: right, y: ends))
		return path.cgPath
	}

	/// 「失联」那条线中间缺口有多宽。取到"一眼看得出是断的",又不至于变成两个小点。
	private static let brokenGap: CGFloat = 12

	/// 按当前进度更新。
	///
	/// 到头(这一头没有下一篇)时,那条线淡到多少。
	///
	/// ⚠️ 这**不违反**上面「深浅不再表达进度」那一条:
	/// 形状表达的是**"够不够"**,透明度现在表达的是**"这一头有没有东西"** ——
	/// 两个视觉量各说一件事,没有挤在同一个通道里。
	/// 📌 判据还是那句:**一个视觉量只表达一件事**;它反对的是"一个通道说两件事",
	/// 不是"不许用透明度"。
	private static let deadEndAlpha: CGFloat = 0.4

	/// 按当前进度更新。
	///
	/// - Parameters:
	///   - progress: 0…1,到 1 就是"松手会翻页"(= 完整的箭头)
	///   - gap: 内容被推开让出来的空间有多高。箭头就摆在这块空间的正中。
	///   - isDeadEnd: 这一头**没有下一篇**(2026-08-09 用户拍板的样子:
	///     线照出,但**永远不弯**、淡一档)。它说的是"你可以拽,但这头到底了",
	///     而不是把功能藏起来假装无事发生。
	func update(edge: NNWScrollEdge, progress: CGFloat, gap: CGFloat,
				state: NNWPageTurnHintState = .ready, in host: UIView) {

		// 「到头」和「失联」都不会翻页,所以**都不弯、都淡一档**;
		// 两者的区别由**线本身的形状**表达:到头是完整的 `—`,失联是中间缺一口的 `- -`。
		let isDeadEnd = (state != .ready)

		let height = Self.canvasHeight
		let width = Self.chevronWidth
		// 让出来的那块空间的正中;空间还不够高时,先贴着边缘放,别跑到内容上面去
		let centerOffset = max(gap / 2, height / 2)
		let centerY = edge == .bottom
			? host.bounds.height - host.safeAreaInsets.bottom - centerOffset
			: host.safeAreaInsets.top + centerOffset

		frame = CGRect(x: ((host.bounds.width - width) / 2).rounded(),
					   y: (centerY - height / 2).rounded(),
					   width: width, height: height)

		// ⚠️ 关掉隐式动画:路径每帧都在变,不关的话每次变化都被排成 0.25 秒的动画,箭头会拖在手指后面
		CATransaction.begin()
		CATransaction.setDisableActions(true)
		shape.frame = bounds
		// 到头时**把进度按死在 0** —— 于是它恒是一条平的 `—`,一点都不会弯成 `^`。
		// 形状本身就是承诺:弯 = 松手会翻;不弯 = 这头没有了。
		shape.path = Self.path(progress: isDeadEnd ? 0 : progress,
							   in: bounds.size, pointingDown: edge == .bottom,
							   broken: state == .lost)
		let style = traitCollection.userInterfaceStyle
		if strokeStyle != style {
			strokeStyle = style
			// 和底栏 dock 图标同一个墨色(深浅色自动对)
			shape.strokeColor = NNWSoftMaterial.ink.resolvedColor(with: traitCollection).cgColor
		}
		CATransaction.commit()

		// ⚠️ **深浅不表达进度**(用户明确要求 discard 掉那个过程),所以随进度恒为 1;
		// 只有"这一头到底了"才淡下去 —— 见 `deadEndAlpha` 上面那段。
		alpha = isDeadEnd ? Self.deadEndAlpha : 1
	}

	/// 松手/取消:淡出后由调用方丢掉。
	func dismiss(completion: @escaping () -> Void) {
		UIView.animate(withDuration: 0.18, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
			self.alpha = 0
		} completion: { _ in
			self.removeFromSuperview()
			completion()
		}
	}
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
	private static nonisolated(unsafe) var nnwOverscrollArmedKey: UInt8 = 0
	private static nonisolated(unsafe) var nnwOverscrollHapticKey: UInt8 = 0
	private static nonisolated(unsafe) var nnwPageTurnHintKey: UInt8 = 0
	private static nonisolated(unsafe) var nnwOverscrollPeakKey: UInt8 = 0
	private static nonisolated(unsafe) var nnwPinnedEdgeKey: UInt8 = 0
	private static nonisolated(unsafe) var nnwPinnedTranslationKey: UInt8 = 0
	private static nonisolated(unsafe) var nnwBackStackKey: UInt8 = 0
	private static nonisolated(unsafe) var nnwPullingKey: UInt8 = 0
	private static nonisolated(unsafe) var nnwEntryNeighborKey: UInt8 = 0
	private static nonisolated(unsafe) var nnwEntryNeighborByDateKey: UInt8 = 0
	private static nonisolated(unsafe) var nnwTurningKey: UInt8 = 0
	private static nonisolated(unsafe) var nnwTurnTokenKey: UInt8 = 0
	// 🪦 nnwBrowserInteractorKey / nnwBrowserDelegateKey / nnwBrowserBackSwipeKey /
	// nnwBrowserTravelWidthKey 已随交互式呈现一起拆除(2026-08-12,见"左滑开原文"墓碑注释)

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

	/// **已经拽够了的那一头**(nil = 还没拽够)。松手时照它翻页。
	///
	/// ⚠️ **必须在"拽够的那一刻"把方向记下来,不能等松手时再问一遍** ——
	/// 松手那一瞬滚动视图可能已经弹回边界内了,再问就是 nil,于是"明明拉够了却不翻"。
	var nnwOverscrollArmedEdge: NNWScrollEdge? {
		get { (objc_getAssociatedObject(self, &Self.nnwOverscrollArmedKey) as? String).flatMap(NNWScrollEdge.init(rawValue:)) }
		set { objc_setAssociatedObject(self, &Self.nnwOverscrollArmedKey, newValue?.rawValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
	}

	/// 触觉反馈器。⚠️ 手势开始时**要 `prepare()`** —— 不预热第一下会迟到 100ms 上下,
	/// 那正好是"手感"最要命的地方。
	var nnwOverscrollHaptic: UIImpactFeedbackGenerator? {
		get { objc_getAssociatedObject(self, &Self.nnwOverscrollHapticKey) as? UIImpactFeedbackGenerator }
		set { objc_setAssociatedObject(self, &Self.nnwOverscrollHapticKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
	}

	/// ⚠️ 临时探针(2026-08-09,查完就删):这一拽超出边界的**峰值**。
	var nnwOverscrollPeak: CGFloat {
		get { objc_getAssociatedObject(self, &Self.nnwOverscrollPeakKey) as? CGFloat ?? 0 }
		set { objc_setAssociatedObject(self, &Self.nnwOverscrollPeakKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
	}

	/// 正文此刻**贴住**了哪一头(贴住 ≠ 超出:不回弹的 WebView 只会贴住,永远不超出)。
	var nnwPinnedEdge: NNWScrollEdge? {
		get { (objc_getAssociatedObject(self, &Self.nnwPinnedEdgeKey) as? String).flatMap(NNWScrollEdge.init(rawValue:)) }
		set { objc_setAssociatedObject(self, &Self.nnwPinnedEdgeKey, newValue?.rawValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
	}

	/// **刚贴住那一刻**手指的位移。之后手指又走了多少,就是"贴住之后还在拉"的量。
	var nnwPinnedTranslationY: CGFloat {
		get { objc_getAssociatedObject(self, &Self.nnwPinnedTranslationKey) as? CGFloat ?? 0 }
		set { objc_setAssociatedObject(self, &Self.nnwPinnedTranslationKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
	}

	/// **来路** —— 每次往后翻一篇就把当前这篇压进来,往前翻就弹出来。
	///
	/// ## 🔴 为什么不能只靠"在列表里找上一篇"(2026-08-09 用户:
	/// 「向下翻篇后,再往上翻篇就只能触发动画,但翻不动」)
	///
	/// 原来是 `articles.firstIndex(of: 当前这篇)` 再取前一个。
	/// 而在「全部未读」这类**会自我删减的列表**里,你刚读过的那几篇随时会消失 ——
	/// 找不到自己 → 退回 `coordinator.selectPrevArticle()` → 那条路也要靠"当前选中在第几行",
	/// 同样可能落空 → **动画放了、震也震了,就是不换页。**
	///
	/// 📌 判据:**"上一篇"在用户心里是"我刚才那一篇",不是"列表里排在前面那一篇"。**
	/// 前者我们自己记得住,后者依赖一份随时会变的外部列表。记来路,别去查表。
	var nnwPageBackStack: [Article] {
		get { objc_getAssociatedObject(self, &Self.nnwBackStackKey) as? [Article] ?? [] }
		set { objc_setAssociatedObject(self, &Self.nnwBackStackKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
	}

	/// **进门锚**:`[这一篇, 打开它那一刻列表里排在它前面的那一篇]`。
	///
	/// ## 为什么非要在"打开的那一刻"记(2026-08-09 第五轮真机日志逼出来的)
	///
	/// 「全部未读」这类智能源**只装未读文章**。你一打开某篇,它立刻被标为已读,
	/// 列表下一次重拉时**它自己就从列表里消失了** —— 于是
	/// `articles.firstIndex(of: 当前这篇)` 从此永远是 nil。
	/// 真机日志里 `我这页在第=找不到 行` 大片出现,`列表共` 也从 7723 一路掉到 7720,
	/// **这不是偶发,是常态**(而且**不需要**用户打开"隐藏已读")。
	///
	/// 后果:来路栈一空(刚从列表点进来的第一篇就是这种情况),
	/// 就会判成"到头了"并画那条到头的线 —— **可上面明明还有文章。假的到头比没反馈更糟。**
	///
	/// 📌 判据(T53/T55 那条的又一次,这次带上解法):
	/// **"我在列表里的位置"这个前提在会自我删减的列表上随时失效 ——
	/// 那就别等到要用的时候才去查,在它还成立的那一刻把答案存下来。**
	///
	/// ⚠️ **连着"这个答案是给谁的"一起存**(数组第 0 个就是那一篇):
	/// 只有当前这一篇和它对得上才用,否则宁可没有 ——
	/// 一个张冠李戴的"上一篇"比没有更难查(L123)。
	var nnwEntryNeighbor: [Article]? {
		get { objc_getAssociatedObject(self, &Self.nnwEntryNeighborKey) as? [Article] }
		set { objc_setAssociatedObject(self, &Self.nnwEntryNeighborKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
	}

	/// 当前这个锚是**按日期兜底算出来的**(而不是"列表里真的排在前面")。
	///
	/// ⚠️ 只为一件事存在:**让日志说清楚锚是从哪来的**。
	/// 不然验收时看到 `进门锚=有`,分不清是老路子生效了还是第十三轮新加的兜底生效了 ——
	/// 又一次 L123:**「我量到了」≠「我量的是它」。**
	var nnwEntryNeighborByDate: Bool {
		get { objc_getAssociatedObject(self, &Self.nnwEntryNeighborByDateKey) as? Bool ?? false }
		set { objc_setAssociatedObject(self, &Self.nnwEntryNeighborByDateKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
	}

	/// 此刻**翻页动画正在放**吗。
	///
	/// ## 为什么需要它(2026-08-09 用户:「往上翻的时候,标题和正文还在抖动」)
	///
	/// 翻页容器换页时,新那一页是**从屏幕外滑进来**的。
	/// 而**一个视图只要有一部分在窗口顶边之外,它自己的 `safeAreaInsets.top`
	/// 就会变成「真实状态栏高度 + 露在外面那一截」** —— 滑动过程中每帧都不一样。
	///
	/// `ArticleHeaderBar` 的 `safeTop` 同时决定三样东西:停靠带的位置、
	/// 头区容器的高度、以及 `applyGeometry` 的全部几何;而头区高度一变又会去改
	/// 正文的 `contentInset`/`contentOffset`。**所以 `safeTop` 每帧变一次,
  ///	标题和正文就一起抖一次。**
	///
	/// 📌 **这正好解释了用户说的"只有往上翻会抖"**:
	/// 往**下**翻时新页从屏幕**下方**来,压根不碰窗口顶边,`hostSafeTop` 是 0,
	/// `max(host, window)` 取窗口那个稳定值 —— 一点都不抖。
	/// 往**上**翻时新页从**上方**来,`hostSafeTop` 一路从很大扫回 62。
	///
	/// 📌 判据(T24 那条的射程再往外推一格):
	/// **视图被人为位移的期间,它自己的安全区是"当下的几何事实",不是"这一页该用的排版基准"。**
	/// 谁在动它就该由谁负责,而窗口的安全区在整个过程中都是对的。
	var nnwIsTurningPage: Bool {
		get { objc_getAssociatedObject(self, &Self.nnwTurningKey) as? Bool ?? false }
		set { objc_setAssociatedObject(self, &Self.nnwTurningKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
	}

	/// 翻页的**代际令牌**:每发起一次翻页 +1,收尾时再 +1。
	///
	/// 用途是让「系统回调」和「超时兜底」这两条收尾路**只有先到的那条算数** ——
	/// 谁跑完就把令牌推走,另一条一看对不上就自动作废。
	/// 判据:**两条路都可能先到、也都可能不到时,别用布尔值当锁,用一个只增不减的号。**
	var nnwTurnToken: Int {
		get { objc_getAssociatedObject(self, &Self.nnwTurnTokenKey) as? Int ?? 0 }
		set { objc_setAssociatedObject(self, &Self.nnwTurnTokenKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
	}

	/// 此刻正在"拽过头翻页"吗。
	/// ⚠️ `ArticleHeaderBar` 的 T24 安全区自愈要读它 —— 拽的时候我们给容器加了位移,
	/// 那会**合法地**改变安全区,自愈机制不让路就会每帧请求重排,表现为标题和正文一直抖。
	var nnwIsPullingToTurnPage: Bool {
		get { objc_getAssociatedObject(self, &Self.nnwPullingKey) as? Bool ?? false }
		set { objc_setAssociatedObject(self, &Self.nnwPullingKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
	}

	/// 屏幕上下那个「松手就翻页」的箭头。
	var nnwPageTurnHint: NNWPageTurnHintView? {
		get { objc_getAssociatedObject(self, &Self.nnwPageTurnHintKey) as? NNWPageTurnHintView }
		set { objc_setAssociatedObject(self, &Self.nnwPageTurnHintKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
	}

	// 🪦 nnwBrowserInteractor / nnwBrowserTravelWidth 已随交互式呈现一起拆除
	// (2026-08-12,见"左滑开原文"墓碑注释)
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
