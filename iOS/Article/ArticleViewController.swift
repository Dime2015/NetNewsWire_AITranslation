//
//  ArticleViewController.swift
//  NetNewsWire
//
//  Created by Maurice Parker on 4/8/19.
//  Copyright © 2019 Ranchero Software. All rights reserved.
//

import UIKit
import os
import SafariServices
import WebKit
import RSCore
import Account
import Articles

final class ArticleViewController: UIViewController {

	typealias State = (extractedArticle: ExtractedArticle?,
		isShowingExtractedArticle: Bool,
		articleExtractorButtonState: ArticleExtractorButtonState,
		windowScrollY: Int)

	@IBOutlet private weak var nextUnreadBarButtonItem: UIBarButtonItem!
	@IBOutlet private weak var prevArticleBarButtonItem: UIBarButtonItem!
	@IBOutlet private weak var nextArticleBarButtonItem: UIBarButtonItem!
	@IBOutlet private weak var readBarButtonItem: UIBarButtonItem!
	@IBOutlet private weak var starBarButtonItem: UIBarButtonItem!
	@IBOutlet private weak var actionBarButtonItem: UIBarButtonItem!

	@IBOutlet private var searchBar: ArticleSearchBar!
	@IBOutlet private var searchBarBottomConstraint: NSLayoutConstraint!
	private var defaultControls: [UIBarButtonItem]?

	private var pageViewController: UIPageViewController!
	private var isPageTransitionInProgress = false
	private var pendingSetViewController: WebViewController?

	private var currentWebViewController: WebViewController? {
		return pageViewController?.viewControllers?.first as? WebViewController
	}

	private var articleExtractorButton: ArticleExtractorButton = {
		let button = ArticleExtractorButton(type: .system)
		button.frame = CGRect(x: 0, y: 0, width: 44.0, height: 44.0)
		button.setImage(Assets.Images.articleExtractorOff, for: .normal)
		if #unavailable(iOS 26) {
			button.tintColor = NNWAccentPalette.live
		} else {
			button.tintColor = .label
		}
		return button
	}()

	// [翻译] 本 fork 新增:翻译功能的状态与按钮都由它管。具体实现在 Shared/Translation/
	private lazy var translationController = TranslationController { [weak self] in
		self?.currentWebViewController
	}

	weak var coordinator: SceneCoordinator!

	private let poppableDelegate = PoppableGestureRecognizerDelegate()
	private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "ArticleViewController")

	var article: Article? {
		didSet {
			Self.logger.debug("ArticleViewController: article didSet: \(self.article?.accountID ?? "nil") \(self.article?.articleID ?? "nil") \(self.article?.title ?? "nil")")

			// [阅读] 趁列表还认得这篇文章,先把「列表里排在它前面的那一篇」记下来。
			// 「全部未读」只装未读文章 —— 你一打开它就被标为已读,列表下次重拉时它就没了,
			// 之后再问"我在第几行"永远是"找不到"。实现在 NNWArticlePaging.swift。
			nnwRememberListNeighbor()

			if let controller = currentWebViewController, controller.article != article {
				controller.setArticle(article)
				if isPageTransitionInProgress {
					// Calling setViewControllers during an active page transition trips a UIPageViewController
					// internal assertion (NSInternalInconsistencyException) and crashes the app. Stash the
					// controller and flush it from didFinishAnimating once the transition has ended.
					pendingSetViewController = controller
				} else {
					DispatchQueue.main.async {
						// You have to set the view controller to clear out the UIPageViewController child controller cache.
						// You also have to do it in an async call or you will get a strange assertion error.
						// Re-check the transition state: a user swipe between enqueue and execution can flip
						// isPageTransitionInProgress to true, and calling setViewControllers then would crash.
						if self.isPageTransitionInProgress {
							self.pendingSetViewController = controller
						} else {
							self.pageViewController.setViewControllers([controller], direction: .forward, animated: false, completion: nil)
						}
					}
				}
			} else if nnwIsShowingNoMoreArticlesPage, let article {
				// [阅读] 加一行(2026-08-09,修用户报的 bug):**彩蛋页占着位置时,
				// `currentWebViewController` 是 nil,上面那个分支进不去** ——
				// 于是从列表点任何一篇文章都换不掉它,每篇都显示「没有下一篇啦!」。
				// 彩蛋页成了单向的死胡同。实现在 NNWArticlePaging.swift。
				nnwReplaceEasterEggPage(with: article)
			}
			// [翻译] 本 fork 新增:换文章时重置翻译按钮图标。
			// 挂在这里是因为**所有**切换文章的入口(手指滑动、右上角上下箭头、
			// 底部下一篇未读、列表点选)最终都会走到这个 didSet。
			if oldValue != article {
				translationController.resetForNewArticle()
			}

			updateUI()
		}
	}

	var restoreScrollPosition: (isShowingExtractedArticle: Bool, articleWindowScrollY: Int)? {
		didSet {
			if let rsp = restoreScrollPosition {
				currentWebViewController?.setScrollPosition(isShowingExtractedArticle: rsp.isShowingExtractedArticle, articleWindowScrollY: rsp.articleWindowScrollY)
			}
		}
	}

	var currentState: State? {
		guard let controller = currentWebViewController else { return nil}
		return State(extractedArticle: controller.extractedArticle,
					 isShowingExtractedArticle: controller.isShowingExtractedArticle,
					 articleExtractorButtonState: controller.articleExtractorButtonState,
					 windowScrollY: controller.windowScrollY)
	}

	var restoreState: State?

	private let keyboardManager = KeyboardManager(type: .detail)
	override var keyCommands: [UIKeyCommand]? {
		return keyboardManager.keyCommands
	}

	override func viewDidLoad() {
		super.viewDidLoad()

		NotificationCenter.default.addObserver(self, selector: #selector(unreadCountDidChange(_:)), name: .UnreadCountDidChange, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(statusesDidChange(_:)), name: .StatusesDidChange, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(contentSizeCategoryDidChange(_:)), name: UIContentSizeCategory.didChangeNotification, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(willEnterForeground(_:)), name: UIApplication.willEnterForegroundNotification, object: nil)

		let appearance = UINavigationBarAppearance()
		appearance.configureWithDefaultBackground()
		navigationItem.standardAppearance = appearance
		navigationItem.scrollEdgeAppearance = appearance
		navigationItem.compactAppearance = appearance
		nnwInstallNavigationBarAppearanceUpdater()	// [外观] 让上面这套颜色跟随深浅色更新(实现在本文件末尾扩展)

		let fullScreenTapZone = UIView()
		NSLayoutConstraint.activate([
			fullScreenTapZone.widthAnchor.constraint(equalToConstant: 150),
			fullScreenTapZone.heightAnchor.constraint(equalToConstant: 44)
		])
		// [外观] 去掉"点导航栏切换全屏"的点击手势 —— 改为滚动方向驱动藏/现栏(用户 2026-07-23)。
		// fullScreenTapZone 仍作为 titleView 占位(空 view,无副作用),只是不再挂点击。
		navigationItem.titleView = fullScreenTapZone

		articleExtractorButton.addTarget(self, action: #selector(toggleArticleExtractor(_:)), for: .touchUpInside)
		let articleExtractorBarButtonItem = UIBarButtonItem(customView: articleExtractorButton)

		if #available(iOS 26, *) {
			toolbarItems?.insert(articleExtractorBarButtonItem, at: 5)
		} else {
			let flex = { UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil) }
			toolbarItems = [
				readBarButtonItem,
				flex(),
				starBarButtonItem,
				flex(),
				nextUnreadBarButtonItem,
				flex(),
				articleExtractorBarButtonItem,
				flex(),
				actionBarButtonItem
			]
		}

		installTranslationButton()	// [翻译] 本 fork 新增
		nnwInstallReadingGestures()	// [阅读] 本 fork 新增:右滑回列表 / 左滑开原文 / 到头再拽翻篇(实现在 NNWArticlePaging.swift)

		// [阅读] 2026-08-09 一处换一处:`.horizontal` → **`.vertical`**(用户:「上下翻页的动画很生硬,
		// 能否上下整体翻页、垂直地自然过渡」)。翻篇改由 `nnwTurnPage` 用
		// `setViewControllers(animated: true)` 驱动,竖向的容器给出来的就是**竖向的整页推移**。
		//
		// ⚠️ **改朝向不会影响手势**:本 fork 的 `viewControllerBefore/After` **恒返回 nil**
		// (翻页早就改由我们自己的手势触发了),所以这个容器里**永远只有一页** ——
		// 它内部那个滚动视图的 contentSize 等于自身大小、根本滚不动,
		// 不会和正文的竖向滚动抢触摸。横向那会儿也是同一个道理。
		pageViewController = UIPageViewController(transitionStyle: .scroll, navigationOrientation: .vertical, options: [:])
		pageViewController.delegate = self
		pageViewController.dataSource = self

		// This code is to disallow paging if we scroll from the left edge.  If this code is removed
		// PoppableGestureRecognizerDelegate will allow us to both navigate back and page back at the
		// same time. That is really weird when it happens.
		let panGestureRecognizer = UIPanGestureRecognizer()
		panGestureRecognizer.delegate = self
		pageViewController.scrollViewInsidePageControl?.addGestureRecognizer(panGestureRecognizer)

		pageViewController.view.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(pageViewController.view)
		addChild(pageViewController!)
		NSLayoutConstraint.activate([
			view.leadingAnchor.constraint(equalTo: pageViewController.view.leadingAnchor),
			view.trailingAnchor.constraint(equalTo: pageViewController.view.trailingAnchor),
			view.topAnchor.constraint(equalTo: pageViewController.view.topAnchor),
			view.bottomAnchor.constraint(equalTo: pageViewController.view.bottomAnchor)
		])

		let controller: WebViewController
		if let state = restoreState {
			controller = createWebViewController(article, updateView: false)
			controller.extractedArticle = state.extractedArticle
			controller.isShowingExtractedArticle = state.isShowingExtractedArticle
			controller.articleExtractorButtonState = state.articleExtractorButtonState
			controller.windowScrollY = state.windowScrollY
		} else {
			controller = createWebViewController(article, updateView: true)
		}

		if let rsp = restoreScrollPosition {
			controller.setScrollPosition(isShowingExtractedArticle: rsp.isShowingExtractedArticle, articleWindowScrollY: rsp.articleWindowScrollY)
		}

		articleExtractorButton.buttonState = controller.articleExtractorButtonState

		self.pageViewController.setViewControllers([controller], direction: .forward, animated: false, completion: nil)
		if AppDefaults.shared.logicalArticleFullscreenEnabled {
			controller.hideBars()
		}

		// Search bar
		searchBar.translatesAutoresizingMaskIntoConstraints = false
		NotificationCenter.default.addObserver(self, selector: #selector(beginFind(_:)), name: .FindInArticle, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(endFind(_:)), name: .EndFindInArticle, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillChangeFrame(_:)), name: UIWindow.keyboardWillChangeFrameNotification, object: nil)
		searchBar.delegate = self
		view.bringSubviewToFront(searchBar)

		updateUI()
	}

	override func viewWillAppear(_ animated: Bool) {
		// [外观] 进文章时**总是先显示栏**,之后由滚动方向决定藏/现(见 WebViewController 末尾扩展)。
		// 原来这里按持久的全屏状态,上次退出时藏着的话一进来就藏 —— 那是"点击切全屏"时代的语义;
		// 现在改成滚动驱动,一进来该看到标题栏和工具栏,往下读才沉浸。
		currentWebViewController?.showBars()
		nnwUseFloatingToolbar(true)		// [外观] dock 浮起来:抹掉系统工具栏的底(离开时还原)
		super.viewWillAppear(animated)
	}

	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(true)
		if #available(iOS 26, *) {
			navigationController?.navigationBar.topItem?.subtitle = nil
		}
		coordinator.isArticleViewControllerPending = false
		searchBar.shouldBeginEditing = true
		if let parentNavController = navigationController?.parent as? UINavigationController {
			poppableDelegate.navigationController = parentNavController
			parentNavController.interactivePopGestureRecognizer?.delegate = poppableDelegate
		}
	}

	override func viewWillDisappear(_ animated: Bool) {
		nnwUseFloatingToolbar(false)	// [外观] 工具栏是整个导航栈共用的,必须还原
		super.viewWillDisappear(animated)
		if searchBar != nil && !searchBar.isHidden {
			endFind()
			searchBar.shouldBeginEditing = false
		}
		// Pass animated: false — animating the nav bar / toolbar visibility change during the
		// disappear transition triggers an Auto Layout assertion (NSISEngine) and crashes.
		currentWebViewController?.showBars(animated: false)
	}

	override func viewSafeAreaInsetsDidChange() {
		// This will animate if the show/hide bars animation is happening.
		view.layoutIfNeeded()
		nnwUpdateFloatingDockPosition()	// [外观] 浮动 dock 按真安全区重新贴底
		nnwSyncFloatingDockVisibility()	// [外观] 浮动 dock 跟着栏一起藏/现
	}

	func updateUI() {

		// [外观] 底部控件板跟着一起刷。defer = 不管从哪条路退出(包括下面"没有文章"的
		// 提前 return)都会执行 —— 板子的状态只从这一个口进(L74)。
		// 下面往老按钮(readBarButtonItem 等)写状态的上游代码故意原样保留:
		// 那些按钮已不在工具栏上,写了无害,不改=零合并冲突。
		defer { nnwUpdateControlBoard() }

		guard let article = article else {
			articleExtractorButton.isEnabled = false
			nextUnreadBarButtonItem.isEnabled = false
			prevArticleBarButtonItem.isEnabled = false
			nextArticleBarButtonItem.isEnabled = false
			readBarButtonItem.isEnabled = false
			starBarButtonItem.isEnabled = false
			actionBarButtonItem.isEnabled = false
			return
		}

		nextUnreadBarButtonItem.isEnabled = coordinator.isNextUnreadAvailable
		prevArticleBarButtonItem.isEnabled = coordinator.isPrevArticleAvailable
		nextArticleBarButtonItem.isEnabled = coordinator.isNextArticleAvailable
		readBarButtonItem.isEnabled = true
		starBarButtonItem.isEnabled = true

		let permalinkPresent = article.preferredLink != nil
		// [阅读视图] 原本这里还有 `&& !AppDefaults.shared.isDeveloperBuild`。
		// 那半句的唯一理由是「开发版没有 Feedbin/Mercury 的密钥,点了也白点」。
		// 本 fork 已改为在本机跑 Readability.js,不需要任何密钥,前提消失 ——
		// 不去掉的话,装到真机(我们用 DEVELOPER_ENTITLEMENTS = -dev)按钮会一直是灰的。
		articleExtractorButton.isEnabled = permalinkPresent
		actionBarButtonItem.isEnabled = permalinkPresent

		if article.status.read {
			readBarButtonItem.image = Assets.Images.circleOpen
			readBarButtonItem.isEnabled = article.isAvailableToMarkUnread
			readBarButtonItem.accLabelText = NSLocalizedString("Mark Article Unread", comment: "Mark Article Unread")
		} else {
			readBarButtonItem.image = Assets.Images.circleClosed
			readBarButtonItem.isEnabled = true
			readBarButtonItem.accLabelText = NSLocalizedString("Selected - Mark Article Unread", comment: "Selected - Mark Article Unread")
		}

		if article.status.starred {
			starBarButtonItem.image = Assets.Images.starClosed
			starBarButtonItem.accLabelText = NSLocalizedString("Selected - Star Article", comment: "Selected - Star Article")
		} else {
			starBarButtonItem.image = Assets.Images.starOpen
			starBarButtonItem.accLabelText = NSLocalizedString("Star Article", comment: "Star Article")
		}
	}

	// MARK: Notifications

	@objc dynamic func unreadCountDidChange(_ notification: Notification) {
		updateUI()
	}

	@objc func statusesDidChange(_ note: Notification) {
		guard let articleIDs = note.userInfo?[Account.UserInfoKey.articleIDs] as? Set<String> else {
			return
		}
		guard let article = article else {
			return
		}
		if articleIDs.contains(article.articleID) {
			updateUI()
		}
	}

	@objc func contentSizeCategoryDidChange(_ note: Notification) {
		currentWebViewController?.fullReload()
	}

	@objc func willEnterForeground(_ note: Notification) {
		// The toolbar will come back on you if you don't hide it again
		if AppDefaults.shared.logicalArticleFullscreenEnabled {
			currentWebViewController?.hideBars()
		}
	}

	// MARK: Actions

	@objc func didTapNavigationBar() {
		currentWebViewController?.hideBars()
	}

	@objc func showBars(_ sender: Any) {
		currentWebViewController?.showBars()
	}

	@IBAction func toggleArticleExtractor(_ sender: Any) {
		currentWebViewController?.toggleArticleExtractor()
	}

	@IBAction func nextUnread(_ sender: Any) {
		coordinator.selectNextUnread()
	}

	@IBAction func prevArticle(_ sender: Any) {
		coordinator.selectPrevArticle()
	}

	@IBAction func nextArticle(_ sender: Any) {
		coordinator.selectNextArticle()
	}

	@IBAction func toggleRead(_ sender: Any) {
		coordinator.toggleReadForCurrentArticle()
	}

	@IBAction func toggleStar(_ sender: Any) {
		coordinator.toggleStarredForCurrentArticle()
	}

	@IBAction func showActivityDialog(_ sender: Any) {
		// [外观] 2026-07-25:分享键已搬进控件板。老锚点(actionBarButtonItem)不在工具栏上了,
		// iPad 气泡锚一个不在界面上的按钮会崩 —— 改锚到板上的分享键(此方法现在只剩快捷键会走)。
		currentWebViewController?.nnwShowActivityDialog(sourceView: nnwControlBoard?.shareAnchorView ?? view)
	}

	@objc func toggleReaderView(_ sender: Any?) {
		currentWebViewController?.toggleArticleExtractor()
	}

	// MARK: Keyboard Shortcuts

	@objc func navigateToTimeline(_ sender: Any?) {
		coordinator.navigateToTimeline()
	}

	// MARK: API

	func focus() {
		currentWebViewController?.focus()
	}

	func canScrollDown() -> Bool {
		return currentWebViewController?.canScrollDown() ?? false
	}

	func canScrollUp() -> Bool {
		return currentWebViewController?.canScrollUp() ?? false
	}

	func scrollPageDown() {
		currentWebViewController?.scrollPageDown()
	}

	func scrollPageUp() {
		currentWebViewController?.scrollPageUp()
	}

	func stopArticleExtractorIfProcessing() {
		currentWebViewController?.stopArticleExtractorIfProcessing()
	}

	func openInAppBrowser() {
		currentWebViewController?.openInAppBrowser()
	}

	func setScrollPosition(isShowingExtractedArticle: Bool, articleWindowScrollY: Int) {
		currentWebViewController?.setScrollPosition(isShowingExtractedArticle: isShowingExtractedArticle, articleWindowScrollY: articleWindowScrollY)
	}
}

// MARK: Find in Article
public extension Notification.Name {
	static let FindInArticle = Notification.Name("FindInArticle")
	static let EndFindInArticle = Notification.Name("EndFindInArticle")
}

extension ArticleViewController: SearchBarDelegate {

	func searchBar(_ searchBar: ArticleSearchBar, textDidChange searchText: String) {
		currentWebViewController?.searchText(searchText) { found in
			searchBar.resultsCount = found.count

			if let index = found.index {
				searchBar.selectedResult = index + 1
			}
		}
	}

	func doneWasPressed(_ searchBar: ArticleSearchBar) {
		NotificationCenter.default.post(name: .EndFindInArticle, object: nil)
	}

	func nextWasPressed(_ searchBar: ArticleSearchBar) {
		if searchBar.selectedResult < searchBar.resultsCount {
			currentWebViewController?.selectNextSearchResult()
			searchBar.selectedResult += 1
		}
	}

	func previousWasPressed(_ searchBar: ArticleSearchBar) {
		if searchBar.selectedResult > 1 {
			currentWebViewController?.selectPreviousSearchResult()
			searchBar.selectedResult -= 1
		}
	}
}

extension ArticleViewController {

	@objc func beginFind(_ _: Any? = nil) {
		searchBar.isHidden = false
		navigationController?.setToolbarHidden(true, animated: true)
		nnwSyncFloatingDockVisibility()	// [外观] 只藏工具栏不藏导航栏 → 安全区不变、回调不来,得显式叫一次
		currentWebViewController?.additionalSafeAreaInsets.bottom = searchBar.frame.height
		searchBar.becomeFirstResponder()
	}

	@objc func endFind(_ _: Any? = nil) {
		searchBar.resignFirstResponder()
		searchBar.isHidden = true
		navigationController?.setToolbarHidden(false, animated: true)
		nnwSyncFloatingDockVisibility()	// [外观] 同上,查找结束把 dock 放回来
		currentWebViewController?.additionalSafeAreaInsets.bottom = 0
		currentWebViewController?.endSearch()
	}

	@objc func keyboardWillChangeFrame(_ notification: Notification) {
		if !searchBar.isHidden,
			let duration = notification.userInfo?[UIWindow.keyboardAnimationDurationUserInfoKey] as? Double,
			let curveRaw = notification.userInfo?[UIWindow.keyboardAnimationCurveUserInfoKey] as? UInt,
			let frame = notification.userInfo?[UIWindow.keyboardFrameEndUserInfoKey] as? CGRect {

			let curve = UIView.AnimationOptions(rawValue: curveRaw)
			let newHeight = view.safeAreaLayoutGuide.layoutFrame.maxY - frame.minY
			currentWebViewController?.additionalSafeAreaInsets.bottom = newHeight + searchBar.frame.height + 10
			self.searchBarBottomConstraint.constant = newHeight
			UIView.animate(withDuration: duration, delay: 0, options: curve, animations: {
				self.view.layoutIfNeeded()
			})
		}
	}

}

// MARK: WebViewControllerDelegate

extension ArticleViewController: WebViewControllerDelegate {

	func webViewController(_ webViewController: WebViewController, articleExtractorButtonStateDidUpdate buttonState: ArticleExtractorButtonState) {
		if webViewController === currentWebViewController {
			articleExtractorButton.buttonState = buttonState
		}
	}

}

// MARK: UIPageViewControllerDataSource

extension ArticleViewController: UIPageViewControllerDataSource {

	func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
		// [阅读] 一行换一行(用户 2026-08-08 第 4 件):**永远没有前一页**。
		// 右滑不再翻上一篇,而是交给「右滑回列表」那个手势(见 NNWArticlePaging.swift)。
		// 上一篇的入口没丢:底部 dock 的箭头和键盘快捷键照旧。
		return nil
	}

	func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
		// [阅读] 一行换一行。**2026-08-09 起也永远没有后一页。**
		//
		// 2026-08-08 这里是「后一页 = 下一篇未读」(左滑翻页)。
		// 用户 2026-08-09 把左滑改成了「打开原文」,「下一篇未读」搬到
		// **「已经在底部、再用力上拽」**上 —— 两者不能并存:左滑既翻页又开链接必然打架。
		//
		// ⚠️ 那套逻辑一行没丢,只是换了触发方式:`nnwGoToNextUnread()`(含彩蛋页)
		// 在 NNWArticlePaging.swift 里,仍然只在当前列表内找、找不到就露彩蛋页。
		return nil
	}

}

// MARK: UIPageViewControllerDelegate

extension ArticleViewController: UIPageViewControllerDelegate {

	func pageViewController(_ pageViewController: UIPageViewController, willTransitionTo pendingViewControllers: [UIViewController]) {
		isPageTransitionInProgress = true
	}

	func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
		isPageTransitionInProgress = false
		nnwSyncFloatingDockVisibility()	// [阅读] 加一行:翻到/翻离彩蛋页时 dock 跟着收放(翻页不改安全区,那条回调不会来)

		if let pending = pendingSetViewController {
			pendingSetViewController = nil
			pageViewController.setViewControllers([pending], direction: .forward, animated: false, completion: nil)
		}

		guard finished, completed else { return }
		guard let article = currentWebViewController?.article else { return }

		coordinator.selectArticle(article, animations: [.select, .scroll, .navigation])
		articleExtractorButton.buttonState = currentWebViewController?.articleExtractorButtonState ?? .off
		translationController.resetForNewArticle()	// [翻译] 本 fork 新增:滑动翻页后重置按钮图标
		nnwTrackCurrentArticleScrolling()	// [外观] 翻页后顶栏要改盯新这一页的滚动(实现在本文件末尾扩展)

		for viewController in previousViewControllers {
			if let webViewController = viewController as? WebViewController {
				webViewController.stopWebViewActivity()
			}
		}
	}
}

// MARK: UIGestureRecognizerDelegate

extension ArticleViewController: UIGestureRecognizerDelegate {

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
		let point = gestureRecognizer.location(in: nil)
		if point.x > 40 {
			return true
		}
		return false
    }

}

// MARK: Private

private extension ArticleViewController {

	func createWebViewController(_ article: Article?, updateView: Bool = true) -> WebViewController {
		let controller = WebViewController()
		controller.coordinator = coordinator
		controller.delegate = self
		controller.setArticle(article, updateView: updateView)
		return controller
	}

}

// MARK: - [翻译] 本 fork 新增,上游没有以下内容
//
// 为什么这段代码非得写在这个文件里(而不是放在 Shared/Translation/):
// 1. 底部工具栏(toolbarItems)属于本控制器,没有第二个入口能往里加按钮
// 2. 第 39 行的 `currentWebViewController` 是 `private`,只有本文件内的代码能访问
//
// 为降低将来 `git pull upstream` 的冲突风险,除了三处单行插入(已用 [翻译] 注释标出),
// 其余全部是追加在文件末尾的新行,上游原有代码没有被改写。

extension ArticleViewController {

	/// 把翻译按钮装到底部工具栏最后面。在 viewDidLoad 里调用。
	func installTranslationButton() {

		translationController.button.addTarget(self, action: #selector(toggleTranslation(_:)), for: .touchUpInside)

		// [翻译] item②:长按翻译键 —— 若这篇已有完整译文缓存,弹确认框问是否重翻全文。
		// 长按手势和单击(touchUpInside)可以并存:短按走翻译,长按走这里。
		let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleTranslationLongPress(_:)))
		translationController.button.addGestureRecognizer(longPress)

		// [翻译] 翻译失败/未配置时,把人话说明弹给用户看(以前只静默变感叹号)。
		translationController.presentError = { [weak self] message in
			self?.presentTranslationError(message)
		}

		// [翻译] 顺手修掉上游"阅读视图"按钮的同一个隐患(详见 NOTES-lessons L19)。
		//
		// articleExtractorButton 也是 UIBarButtonItem 的 customView,同样只设了 frame、
		// 没有尺寸约束;它在转圈状态会 setImage(nil),固有尺寸随之变成 0,
		// iOS 26 工具栏会把它算成 0 宽并永久塌掉 —— 表现为"阅读视图和翻译两个按钮一起消失,
		// 之后所有文章都没有"。加死约束后宽度不再依赖图标是否存在。
		//
		// 写在这里而不是改上游那段属性定义,是为了把改动集中在本 fork 自己的扩展里。
		articleExtractorButton.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			articleExtractorButton.widthAnchor.constraint(equalToConstant: 44),
			articleExtractorButton.heightAnchor.constraint(equalToConstant: 44)
		])

		// [外观] 2026-07-25(用户拍板):底部工具栏的 6 个系统按钮(iOS 26 上是两坨玻璃胶囊)
		// 整体换成一块自绘控件板 NNWArticleControlBoard(iOS/DesignKit/NNWControlBoard.swift)。
		// 布局:已读 星标 下一篇未读 ‖ 阅读视图 翻译 ‖ 长图 分享。
		//
		// 「换里子不动壳子」:工具栏这个容器、它的显示/隐藏、全屏机制一概没动,只换内容物 ——
		// 藏栏那片雷区(L73/L80~L84)完全不受影响。
		//
		// 阅读视图和翻译是**原按钮实例整体搬进板子**:它们的状态机(转圈/出错/角标)
		// 和已有的写入点写的还是同一个对象,零重接。其余 5 键的状态由 updateUI 末尾的
		// 钩子统一送进 board.apply(单一入口,L74 的病根从结构上锁死)。
		//
		// 老的 6 个 UIBarButtonItem 不在工具栏上了,但 updateUI 照旧往它们身上写状态 ——
		// 无害,而且**故意不改那段上游代码**(最小 diff)。
		let board = NNWArticleControlBoard(readerButton: articleExtractorButton,
										   translationButton: translationController.button)
		board.onToggleRead = { [weak self] in self?.coordinator.toggleReadForCurrentArticle() }
		board.onToggleStar = { [weak self] in self?.coordinator.toggleStarredForCurrentArticle() }
		board.onNextUnread = { [weak self] in self?.coordinator.selectNextUnread() }
		board.onShareLongImage = { [weak self] in self?.nnwShareLongImage() }
		board.onShare = { [weak self] sourceView in
			// 镜像上游 showActivityDialog,只是锚点从工具栏按钮换成板上的分享键(iPad 气泡用)
			self?.currentWebViewController?.nnwShowActivityDialog(sourceView: sourceView)
		}

		// ⚠️ 换数组之前,先让板子把旧按钮"收养"起来(L85):它们的 IBOutlet 全是 weak,
		// 一被换出数组就释放,上游 updateUI 往空按钮写状态会当场崩(2026-07-25 启动闪退)。
		board.legacyItemsKeptAlive = toolbarItems ?? []

		// [外观] 2026-08-05:dock **不再是工具栏里的一个按钮项**,改成浮在正文之上的视图。
		// 理由(iOS 26/27 的死结:内容穿过栏底 与 单层胶囊 不可兼得)详见
		// `NNWFloatingDock.swift` 的文件头 + NOTES-todo T40/T42。
		//
		// ⚠️ 工具栏这个**壳子留着不动**:它撑起底部安全区,沉浸阅读藏栏/现栏那一整套
		// (L73/L80~L84 的雷区)因此完全不受影响 —— 我们只是把内容物挪到它上面去画。
		// 数组清空(老的 6 个按钮已由 board 收养,见上面 legacyItemsKeptAlive)。
		toolbarItems = []
		nnwInstallFloatingDock(board)
	}

	/// [外观] 控件板的查找。dock 搬出工具栏后从关联对象取(见 NNWFloatingDock.swift)。
	private var nnwControlBoard: NNWArticleControlBoard? {
		nnwFloatingDock
	}

	/// [外观] 把当前文章状态整包送进控件板。**只允许 updateUI 调用**(单一入口,见 L74)。
	private func nnwUpdateControlBoard() {
		guard let board = nnwControlBoard else { return }
		// ⚠️ coordinator 必须按"可能还不存在"来读(L85 的教训,2026-07-25 启动闪退):
		// app 一启动,无障碍层会抢在 coordinator 赋值**之前**强制加载本页视图 → updateUI。
		// 上游代码没事,因为"没有文章"的分支提前 return,碰不到 coordinator;
		// 我们的钩子是 defer,**两条路都走** —— 执行路径比上游宽,上游没防的这里必须自己防。
		board.apply(NNWArticleControlBoard.State(
			hasArticle: article != nil,
			isRead: article?.status.read ?? false,
			canMarkUnread: article?.isAvailableToMarkUnread ?? false,
			isStarred: article?.status.starred ?? false,
			isNextUnreadAvailable: coordinator?.isNextUnreadAvailable ?? false,
			hasLink: article?.preferredLink != nil))
	}

	@objc func toggleTranslation(_ sender: Any) {
		translationController.toggle()
	}

	/// [翻译] item②:长按翻译键的处理。
	///
	/// 🔴 2026-08-12:判据从「有完整缓存」放宽到「有任何译文痕迹」(用户要求) ——
	/// **翻到一半停下**恰恰是最想重来的时刻(翻砸了 / 中途取消 / 部分组失败),
	/// 原来那时候长按毫无反应,像按键坏了。详见 `canOfferRetranslate`。
	/// 从来没翻过的文章仍然静默不响应 —— 那种情况直接点一下翻就行,不需要"重新"。
	@objc func handleTranslationLongPress(_ recognizer: UILongPressGestureRecognizer) {
		guard recognizer.state == .began else { return }
		Task { [weak self] in
			guard let self else { return }
			guard await self.translationController.canOfferRetranslate() else { return }

			// 长按确实触发了,给一下轻微触感反馈(没缓存的情况上面已提前返回,不会震)。
			UIImpactFeedbackGenerator(style: .medium).impactOccurred()

			// 🎛 2026-07-24 深夜:系统动作单换成自绘品牌选单,从翻译按钮头顶弹出。
			// 覆盖缓存是破坏性操作 → 红色 + 保留明确的「取消」行(点选单外面也能取消)。
			// 文案要跟状态走:半途停下时说"已有完整译文"是错的,会让人以为已经翻完了
			let hasFull = await self.translationController.hasFullCache()
			let message = hasFull
				? "这篇已有完整译文。重新翻译整篇吗?这会覆盖当前缓存的译文。"
				: "这篇只翻到一半。重新翻译整篇吗?这会丢掉已翻好的部分,从头再翻一遍。"

			NNWMenu.show(in: self, anchor: .view(self.translationController.button),
						 title: "重新翻译整篇",
						 message: message,
						 sections: [
							[NNWMenu.Item(title: "重新翻译全文", icon: "arrow.clockwise", isDestructive: true) { [weak self] in
								self?.translationController.forceRetranslate()
							}],
							[NNWMenu.Item(title: "取消", icon: "xmark") {}]
						 ])
		}
	}

	/// [状态记忆] item③:由 WebViewController.didFinish 转来 —— 页面渲染完成后,
	/// 若这篇被记为"上次翻过"且本地有完整缓存,自动秒显译文。具体判断在翻译层。
	func nnwAutoApplyTranslationFromCacheIfNeeded() {
		translationController.autoApplyTranslationFromCacheIfNeeded()
	}

	/// [翻译] 翻译失败/未配置时的提示弹窗。
	func presentTranslationError(_ message: String) {
		// 已经有别的弹窗(如长按的重翻确认)时不叠。
		guard presentedViewController == nil else { return }
		let alert = UIAlertController(title: "翻译", message: message, preferredStyle: .alert)
		alert.addAction(UIAlertAction(title: "好", style: .default))
		present(alert, animated: true)
	}
}

// MARK: - [外观] 文章页导航栏跟随深浅色

extension ArticleViewController {

	/// 让文章页顶栏用「系统默认导航栏外观」(渐变透明毛玻璃 + 深浅自适应,和订阅列表页一样)。
	///
	/// ⚠️ 为什么需要这一段(2026-07-22 用户报告:深色模式下文章页顶端仍是浅色):
	/// 上游在 `viewDidLoad` 里设了一次 `appearance.configureWithDefaultBackground()` +
	/// 三个 appearance。`UINavigationBarAppearance` 会把**创建时的颜色/材质固化**成静态值,
	/// viewDidLoad 只跑一次 → 之后切深浅色不更新,顶栏停在首次创建时那套(浅色)。
	///
	/// 只调一次就够了 —— refresh 把三个 appearance 设成 nil、回落到系统内置默认,
	/// 那个是**永久深浅自适应**的,不需要"变了再重建"(实测 registerForTraitChanges
	/// 在"停在文章页切深浅色"时根本不触发,见 L59,所以本来也没法靠它重建)。
	func nnwInstallNavigationBarAppearanceUpdater() {
		nnwRefreshNavigationBarAppearance()	// 覆盖掉上游 viewDidLoad 设的那套固化外观
	}

	/// 按当前深浅色重建导航栏外观,用**系统毛玻璃**(和订阅列表页一样的渐变透明质感)。
	///
	/// 2026-07-23 用户要求文章页顶栏也做成订阅列表那种"渐变透明毛玻璃"。
	/// 那个效果就是系统默认的 `configureWithDefaultBackground()` —— 深浅色自适应、
	/// 内容在顶部时透、往下滚渐显毛玻璃。上游本来就是这个,所以这里用回它。
	///
	/// ⚠️ **本方法真正要解决的是"深浅色跟随"**(见 install 的说明):
	/// `UINavigationBarAppearance` 会把创建时的颜色固化,viewDidLoad 只跑一次 →
	/// 切深浅色不更新。所以必须在明暗变化时重建一次,这才是本方法存在的理由。
	/// (上一轮我还顺手把它改成了不透明纸色 —— 那是**过度修复**,把用户现在想要的
	///  毛玻璃透明质感给盖掉了,本轮撤回。)
	///
	/// 让顶栏跟踪**当前这一页文章**的滚动 —— 「顶部通透 / 往下滚渐显毛玻璃」的开关。
	///
	/// iOS 自带这个两态切换,订阅列表页什么都没写就有,是因为系统自己找得到那一页的滚动视图。
	/// 而这里的 WKWebView 藏在 `UIPageViewController` 的子页面里,系统找不到 →
	/// 只好一直按"已经滚起来了"处理 → **毛玻璃常驻,从来不给透明那一态**
	/// (这正是"文章页顶栏偏实、不够透"折腾多轮的真正原因)。
	/// `setContentScrollView` 是系统给的正规接口(iOS 15+,本工程最低 17),把线接上就行。
	///
	/// ⚠️ **前提是纸色底已经归 UIKit 管**(`WebViewController.nnwUseUIKitPaperBackground`)。
	/// 顶栏透明后露出的是背后的 WebView —— 当年正是因为网页自己画底、深浅色和 app 不同步,
	/// 浅色模式下顶栏透出网页的深色底、变成一片黑(L60)。两件事必须一起在,别只留一个。
	///
	/// 调用时机有两处,缺一不可:①网页加载完(本页第一次准备好);
	/// ②翻页动画结束(翻到的那页可能早就加载完了,不会再触发 ①)。
	/// 重复调用无害 —— 传同一个滚动视图进去,系统不会有额外动作。
	func nnwTrackCurrentArticleScrolling() {
		guard let scrollView = currentWebViewController?.nnwContentScrollView else {
			Self.logger.info("[外观] 顶栏跟踪:这一刻还没有 WebView,跳过(稍后网页加载完会再来一次)")
			return
		}
		setContentScrollView(scrollView)
		// [外观] 阅读栏（方案 C）已改成**每个 WebViewController 自己挂**(见 WebViewController+ReadingBar.swift),
		// 不再由这里的整页共享浮层负责 —— 那版翻页时会滞留/错位,已废弃。
		// 本方法现在只剩一件事:把当前页的滚动交给导航栏跟踪(顶部透明↔滚动毛玻璃)。
		// 留这行日志是为了将来排查"顶栏又不透了":它能一眼区分**没调用**(路径断了)
		// 和**调用了但没效果**(得换别的做法),不用靠肉眼猜。
		Self.logger.info("[外观] 顶栏跟踪已接上,内容偏移 \(scrollView.contentOffset.y, privacy: .public)")
		// [长图] 2026-07-25:这里原来给分享按钮装长按菜单(系统气泡)。控件板上线后
		// 长图有了自己的键,长按菜单已整体拿掉(用户拍板),什么都不用装了。
	}

	/// ⚠️ **本方法末尾不许调用 install(或任何会再触发本方法的东西),否则无限递归(L58)。**
	func nnwRefreshNavigationBarAppearance() {
		// 顶栏要的是**两态**:内容在顶部 = 通透;往下滚 = 毛玻璃。所以两态要分开设,
		// 一个都不能少 ——
		//
		// ⚠️ **别图省事全设 nil**(2026-07-23 差点又栽在这):
		// iOS 15 起,普通标题栏的 `scrollEdgeAppearance` 若为 nil,会**直接回落成
		// `standardAppearance`** —— 于是"在顶部"和"滚动中"用的是同一套毛玻璃,
		// 永远不可能出现透明那一态。这正是文章页"顶栏偏实、怎么调都不够透"的真正原因。
		// (订阅列表页不用写这行是因为它开了大标题模式 `prefersLargeTitles`,
		//  那种模式下系统给的 scrollEdge 默认值本来就是透明 —— 场景不同,别照搬它的"零代码"。)
		//
		// ⚠️ 透明这一态曾经把浅色模式的顶栏变成一片黑(L60)。那不是"透明"的错,
		// 是当时**网页自己画底、深浅色和 app 不同步**,透出了错的东西。现在纸色底已归 UIKit
		// (`WebViewController.nnwUseUIKitPaperBackground`),透出来的一定是对的纸色。
		//
		// 深浅色安全性:透明外观里**没有任何写死的颜色**(背景透明、标题用系统 label 动态色),
		// 所以不存在 L59 那种"创建时固化、之后不跟随"的问题,设一次就永久自适应。
		let transparent = UINavigationBarAppearance()
		transparent.configureWithTransparentBackground()
		transparent.shadowColor = .clear	// 顶部不要那条分隔线,和暖纸无边界风格一致

		navigationItem.scrollEdgeAppearance = transparent	// 在顶部:通透,和正文连成一片
		navigationItem.standardAppearance = nil				// 滚起来:系统默认毛玻璃(自适应)
		navigationItem.compactAppearance = nil				// 横屏紧凑态:同上,保持毛玻璃
	}
}

// MARK: - [外观] 文章页顶部「阅读栏」
//
// 阅读栏已改成**每个 WebViewController 各自带一份**(方案 C,2026-07-23) ——
// 实现搬到了 `WebViewController+ReadingBar.swift`,由那一页自己的生命周期挂载。
// 原来这里那套"整页共享一层浮层、每翻一页重新绑"的做法翻页时会滞留/错位,已整体废弃。
// `ArticleHeaderBarController` 那个类本身仍在用,只是宿主从本控制器换成了 WebViewController。

// MARK: - [长图] 文章长图(T22,2026-07-24;2026-07-25 入口从「长按分享」改为控件板上的独立键)

extension ArticleViewController {

	func nnwShareLongImage() {

		guard let webViewController = currentWebViewController, webViewController.article != nil else { return }

		// 生成要一两秒,给个转圈提示(没有按钮 —— 过程很短,做取消得不偿失)
		// 🎛 2026-07-25:系统转圈弹窗换成自绘进度卡片(NNWProgressCard),失败提示也走品牌卡片
		let progress = NNWProgressCard.present(in: self, text: "正在生成长图…")

		Task { [weak self] in
			guard let self else { return }
			do {
				let image = try await ArticleLongImageExporter.export(from: webViewController)
				progress.finish {
					// 先预览再决定(2026-07-24 用户要求):预览页里有「保存到相册」和「分享」
					let preview = UINavigationController(rootViewController: LongImagePreviewViewController(image: image))
					preview.modalPresentationStyle = .fullScreen
					self.present(preview, animated: true)
				}
			} catch {
				progress.finish {
					// presentError 已被替换成品牌卡片(见 UIViewController+NNWError.swift)
					self.presentError(title: "生成长图失败", message: error.localizedDescription)
				}
			}
		}
	}
}
