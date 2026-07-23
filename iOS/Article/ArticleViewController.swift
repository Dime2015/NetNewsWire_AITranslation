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
			button.tintColor = Assets.Colors.primaryAccent
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

		pageViewController = UIPageViewController(transitionStyle: .scroll, navigationOrientation: .horizontal, options: [:])
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
	}

	func updateUI() {

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
		currentWebViewController?.showActivityDialog(popOverBarButtonItem: actionBarButtonItem)
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
		currentWebViewController?.additionalSafeAreaInsets.bottom = searchBar.frame.height
		searchBar.becomeFirstResponder()
	}

	@objc func endFind(_ _: Any? = nil) {
		searchBar.resignFirstResponder()
		searchBar.isHidden = true
		navigationController?.setToolbarHidden(false, animated: true)
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
		guard let webViewController = viewController as? WebViewController,
			let currentArticle = webViewController.article,
			let article = coordinator.findPrevArticle(currentArticle) else {
			return nil
		}
		return createWebViewController(article)
	}

	func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
		guard let webViewController = viewController as? WebViewController,
			let currentArticle = webViewController.article,
			let article = coordinator.findNextArticle(currentArticle) else {
			return nil
		}
		return createWebViewController(article)
	}

}

// MARK: UIPageViewControllerDelegate

extension ArticleViewController: UIPageViewControllerDelegate {

	func pageViewController(_ pageViewController: UIPageViewController, willTransitionTo pendingViewControllers: [UIViewController]) {
		isPageTransitionInProgress = true
	}

	func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
		isPageTransitionInProgress = false

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

		let translationItem = translationController.makeBarButtonItem()

		if #available(iOS 26, *) {
			// iOS 26 的 Liquid Glass 工具栏按 flexibleSpace 把按钮切成若干"玻璃胶囊",
			// 剩余宽度由这些弹性间隔平分。
			//
			// 上游原本是三组:[已读 星标] | [下一篇未读] | [阅读视图 分享]。
			// 我们加了第 6 个按钮之后,两个间隔各自只剩 40pt 出头,
			// 相邻胶囊的边缘几乎贴上 —— Liquid Glass 会把靠近的玻璃"融"在一起,
			// 看起来就是两坨粘成水滴(用户反馈的粘连问题)。
			//
			// 改成两组,剩余宽度全部给中间那一个间隔,分隔就清楚了:
			//   [已读 星标 下一篇未读] ⟷ [阅读视图 分享 翻译]
			// 左边是"这篇文章的状态和去向",右边是"拿这篇文章做点什么",语义上也说得通。
			let extractorItem = toolbarItems?.first { $0.customView === articleExtractorButton }

			var newItems: [UIBarButtonItem] = [readBarButtonItem, starBarButtonItem, nextUnreadBarButtonItem]
			newItems.append(UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil))
			if let extractorItem {
				newItems.append(extractorItem)
			}
			newItems.append(actionBarButtonItem)
			newItems.append(translationItem)

			toolbarItems = newItems
		} else {
			// 更早的系统上,上游那段代码是用 flexibleSpace 手工均匀撑开的,跟着补一个即可。
			var items = toolbarItems ?? []
			items.append(UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil))
			items.append(translationItem)
			toolbarItems = items
		}
	}

	@objc func toggleTranslation(_ sender: Any) {
		translationController.toggle()
	}

	/// [翻译] item②:长按翻译键的处理。
	/// 只在这篇**有完整译文缓存**时弹确认框;没有缓存则静默不作任何事
	/// (与需求一致 —— 重翻只对「已经翻过整篇」的文章才有意义)。
	@objc func handleTranslationLongPress(_ recognizer: UILongPressGestureRecognizer) {
		guard recognizer.state == .began else { return }
		Task { [weak self] in
			guard let self else { return }
			guard await self.translationController.hasFullCache() else { return }

			// 长按确实触发了,给一下轻微触感反馈(没缓存的情况上面已提前返回,不会震)。
			UIImpactFeedbackGenerator(style: .medium).impactOccurred()

			let alert = UIAlertController(title: "重新翻译整篇",
										  message: "这篇已有完整译文。重新翻译整篇吗?这会覆盖当前缓存的译文。",
										  preferredStyle: .actionSheet)
			alert.addAction(UIAlertAction(title: "重新翻译全文", style: .destructive) { [weak self] _ in
				self?.translationController.forceRetranslate()
			})
			alert.addAction(UIAlertAction(title: "取消", style: .cancel))

			// iPad 上 actionSheet 需要一个来源锚点,否则会崩。
			if let popover = alert.popoverPresentationController {
				popover.sourceView = self.translationController.button
				popover.sourceRect = self.translationController.button.bounds
			}
			self.present(alert, animated: true)
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
		// 留这行日志是为了将来排查"顶栏又不透了":它能一眼区分**没调用**(路径断了)
		// 和**调用了但没效果**(得换别的做法),不用靠肉眼猜。
		Self.logger.info("[外观] 顶栏跟踪已接上,内容偏移 \(scrollView.contentOffset.y, privacy: .public)")
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
