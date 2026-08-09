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

		// 这一头有没有下一站 —— 没有就别给假承诺(到头了还画个箭头,松手却什么都不发生)
		guard nnwHasDestination(for: over.edge) else { return }

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
		nnwSetContentPushBack(edge: over.edge, distance: max(visualGap - over.alreadyMoved, 0))
		hint.update(edge: over.edge, progress: shaped,
					gap: max(visualGap, over.alreadyMoved), in: view)

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
		let armed = raw >= 1
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
	private func nnwHasDestination(for edge: NNWScrollEdge) -> Bool {
		guard let coordinator, nnwCurrentPage is WebViewController else { return false }
		switch edge {
		case .bottom:
			// 没有下一篇未读时仍然算"有"—— 那一站是彩蛋页,松手会翻到它
			return true
		case .top:
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

		// ③ 最后的退路:交给上游。⚠️ 它靠"当前选中在时间线的第几行",也可能落空,
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

		pageViewController.setViewControllers([page],
											  direction: forward ? .forward : .reverse,
											  animated: true) { [weak self] finished in
			container?.layer.speed = 1
			guard let self else { return }
			self.pageViewController(pageViewController,
									didFinishAnimating: finished,
									previousViewControllers: previous,
									transitionCompleted: finished)
		}
	}

	/// 翻页动画的时间流速。1 = 系统原速,越小越慢。嫌快嫌慢**只改这一个数**。
	private static var nnwPageTurnSpeed: Float { 0.7 }
}

/// 正文超出了哪一头。
enum NNWScrollEdge: String {
	case top
	case bottom
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
	private static func path(progress: CGFloat, in size: CGSize, pointingDown: Bool) -> CGPath {

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
		path.move(to: CGPoint(x: left, y: ends))
		path.addLine(to: CGPoint(x: size.width / 2, y: tip))
		path.addLine(to: CGPoint(x: right, y: ends))
		return path.cgPath
	}

	/// 按当前进度更新。
	///
	/// - Parameters:
	///   - progress: 0…1,到 1 就是"松手会翻页"(= 完整的箭头)
	///   - gap: 内容被推开让出来的空间有多高。箭头就摆在这块空间的正中。
	func update(edge: NNWScrollEdge, progress: CGFloat, gap: CGFloat, in host: UIView) {

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
		shape.path = Self.path(progress: progress, in: bounds.size, pointingDown: edge == .bottom)
		let style = traitCollection.userInterfaceStyle
		if strokeStyle != style {
			strokeStyle = style
			// 和底栏 dock 图标同一个墨色(深浅色自动对)
			shape.strokeColor = NNWSoftMaterial.ink.resolvedColor(with: traitCollection).cgColor
		}
		CATransaction.commit()

		// ⚠️ **深浅不再表达进度**,所以这里恒为 1(用户明确要求 discard 掉那个过程)
		alpha = 1
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
