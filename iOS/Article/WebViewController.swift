//
//  WebViewController.swift
//  NetNewsWire-iOS
//
//  Created by Maurice Parker on 12/28/19.
//  Copyright © 2019 Ranchero Software. All rights reserved.
//

import UIKit
@preconcurrency import WebKit
import RSCore
import RSWeb
import Account
import Articles
import SafariServices
import MessageUI
import Images

@MainActor protocol WebViewControllerDelegate: AnyObject {
	func webViewController(_: WebViewController, articleExtractorButtonStateDidUpdate: ArticleExtractorButtonState)
}

final class WebViewController: UIViewController {

	private struct MessageName {
		static let imageWasClicked = "imageWasClicked"
		static let imageWasShown = "imageWasShown"
		static let showFeedInspector = "showFeedInspector"
	}

	private var topShowBarsView: UIView!
	private var bottomShowBarsView: UIView!
	private var topShowBarsViewConstraint: NSLayoutConstraint!
	private var bottomShowBarsViewConstraint: NSLayoutConstraint!

	private var webView: PreloadedWebView? {
		return view.subviews[0] as? PreloadedWebView
	}

	private lazy var contextMenuInteraction = UIContextMenuInteraction(delegate: self)
	private var isFullScreenAvailable: Bool {
		return AppDefaults.shared.articleFullscreenAvailable && traitCollection.userInterfaceIdiom == .phone
	}
	private lazy var articleIconSchemeHandler = ArticleIconSchemeHandler(coordinator: coordinator)
	private lazy var transition = ImageTransition(controller: self)
	private var clickedImageCompletion: (() -> Void)?

	// [阅读视图] 由上游的 ArticleExtractor 换成本 fork 的 ReaderViewExtractor
	// (上游那个依赖 Feedbin 付费服务 + 我们没有的密钥,从来就跑不起来)。
	// 新类刻意做成同样的形状(state / articleLink / process() / cancel()),
	// 所以本文件里其余 18 处引用一行都不用改。
	private var articleExtractor: ReaderViewExtractor?
	var extractedArticle: ExtractedArticle? {
		didSet {
			windowScrollY = 0
		}
	}
	var isShowingExtractedArticle = false {
		didSet {
			if AppDefaults.shared.isShowingExtractedArticle != isShowingExtractedArticle {
				AppDefaults.shared.isShowingExtractedArticle = isShowingExtractedArticle
			}
		}
	}

	var articleExtractorButtonState: ArticleExtractorButtonState = .off {
		didSet {
			delegate?.webViewController(self, articleExtractorButtonStateDidUpdate: articleExtractorButtonState)
		}
	}

	weak var coordinator: SceneCoordinator!
	weak var delegate: WebViewControllerDelegate?

	private(set) var article: Article?

	let scrollPositionQueue = CoalescingQueue(name: "Article Scroll Position", interval: 0.3, maxInterval: 0.3)
	var windowScrollY = 0 {
		didSet {
			if windowScrollY != AppDefaults.shared.articleWindowScrollY {
				AppDefaults.shared.articleWindowScrollY = windowScrollY
			}
		}
	}
	private var restoreWindowScrollY: Int?

	override func viewDidLoad() {
		super.viewDidLoad()

		NotificationCenter.default.addObserver(self, selector: #selector(feedIconDidBecomeAvailable(_:)), name: .feedIconDidBecomeAvailable, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(avatarDidBecomeAvailable(_:)), name: .AvatarDidBecomeAvailable, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(faviconDidBecomeAvailable(_:)), name: .FaviconDidBecomeAvailable, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(currentArticleThemeDidChangeNotification(_:)), name: .CurrentArticleThemeDidChangeNotification, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(handleSceneDidEnterBackground(_:)), name: UIScene.didEnterBackgroundNotification, object: nil)

		// Configure the tap zones
		configureTopShowBarsView()
		configureBottomShowBarsView()

		loadWebView()
	}

	override func viewSafeAreaInsetsDidChange() {
		super.viewSafeAreaInsetsDidChange()
		if isFullScreenAvailable && AppDefaults.shared.logicalArticleFullscreenEnabled {
			updateBottomSafeAreaForFullScreen()
		}
	}

	// [外观] 阅读栏(方案 C:每页一份)。放在布局回调里,是为了兜住一种情形:
	// UIPageViewController 预载的相邻页,在**变可见、拿到真实尺寸**之前 renderPage/didFinish
	// 可能都已经跑过(那时 view.bounds 还是 0,挂栏被跳过)。等它真正被滑到、这里一定会触发,
	// 保证栏能挂上。nnwUpdateReadingBar 幂等,重复调无害。实现在 WebViewController+ReadingBar.swift。
	override func viewDidLayoutSubviews() {
		super.viewDidLayoutSubviews()
		nnwUpdateReadingBar()
	}

	override func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)
		// Pause in-flight media before the view goes away. Leaving a video playing during
		// dismissal lets WebKit's full-screen entry continuation fire on a stale view
		// hierarchy and trip a RELEASE_ASSERT in WebFullScreenManagerProxy on iOS 26.
		stopWebViewActivity()
	}

	// MARK: Notifications

	@objc func handleSceneDidEnterBackground(_ notification: Notification) {
		// The share sheet is a popover on iPad. Opening the article in another browser
		// from it backgrounds NetNewsWire mid-presentation, orphaning the popover so it
		// can't be dismissed by tapping outside on return. Dismiss it on backgrounding. (#4269)
		if presentedViewController is UIActivityViewController {
			dismiss(animated: false)
		}
	}

	@objc func feedIconDidBecomeAvailable(_ note: Notification) {
		reloadArticleImage()
	}

	@objc func avatarDidBecomeAvailable(_ note: Notification) {
		reloadArticleImage()
	}

	@objc func faviconDidBecomeAvailable(_ note: Notification) {
		reloadArticleImage()
	}

	@objc func currentArticleThemeDidChangeNotification(_ note: Notification) {
		loadWebView()
	}

	// MARK: Actions

	@objc func showBars(_ sender: Any) {
		showBars()
	}

	// MARK: API

	func setArticle(_ article: Article?, updateView: Bool = true) {
		stopArticleExtractor()

		if article != self.article {
			self.article = article
			if updateView {
				// [状态记忆] item③:除了上游「按订阅源总是用阅读视图」,
				// 再加一条「这篇上次开着阅读模式」也自动进阅读视图。
				if article?.feed?.readerViewAlwaysEnabled == true || nnwShouldRestoreReaderMode(article) {
					startArticleExtractor()
				}
				windowScrollY = 0
				loadWebView()
			}
		}
	}

	func setScrollPosition(isShowingExtractedArticle: Bool, articleWindowScrollY: Int) {
		if isShowingExtractedArticle {
			switch articleExtractor?.state {
			case .ready:
				restoreWindowScrollY = articleWindowScrollY
				startArticleExtractor()
			case .complete:
				windowScrollY = articleWindowScrollY
				loadWebView()
			case .processing:
				restoreWindowScrollY = articleWindowScrollY
			default:
				restoreWindowScrollY = articleWindowScrollY
				startArticleExtractor()
			}
		} else {
			windowScrollY = articleWindowScrollY
			loadWebView()
		}
	}

	func focus() {
		webView?.becomeFirstResponder()
	}

	func canScrollDown() -> Bool {
		guard let webView = webView else { return false }
		return webView.scrollView.contentOffset.y < finalScrollPosition(scrollingUp: false)
	}

	func canScrollUp() -> Bool {
		guard let webView = webView else { return false }
		return webView.scrollView.contentOffset.y > finalScrollPosition(scrollingUp: true)
	}

	private func scrollPage(up scrollingUp: Bool) {
		guard let webView, let windowScene = webView.window?.windowScene else {
			return
		}

		let overlap = 2 * UIFont.systemFont(ofSize: UIFont.systemFontSize).lineHeight * windowScene.screen.scale
		let scrollToY: CGFloat = {
			let scrollDistance = webView.scrollView.layoutMarginsGuide.layoutFrame.height - overlap
			let fullScroll = webView.scrollView.contentOffset.y + (scrollingUp ? -scrollDistance : scrollDistance)
			let final = finalScrollPosition(scrollingUp: scrollingUp)
			return (scrollingUp ? fullScroll > final : fullScroll < final) ? fullScroll : final
		}()

		let convertedPoint = self.view.convert(CGPoint(x: 0, y: 0), to: webView.scrollView)
		let scrollToPoint = CGPoint(x: convertedPoint.x, y: scrollToY)
		webView.scrollView.setContentOffset(scrollToPoint, animated: true)
	}

	func scrollPageDown() {
		scrollPage(up: false)
	}

	func scrollPageUp() {
		scrollPage(up: true)
	}

	func hideClickedImage() {
		webView?.evaluateJavaScript("hideClickedImage();")
	}

	func showClickedImage(completion: @escaping () -> Void) {
		clickedImageCompletion = completion
		webView?.evaluateJavaScript("showClickedImage();")
	}

	func fullReload() {
		loadWebView(replaceExistingWebView: true)
	}

	func showBars(animated: Bool = true) {
		AppDefaults.shared.articleFullscreenEnabled = false
		coordinator.showStatusBar()
		topShowBarsViewConstraint?.constant = 0
		bottomShowBarsViewConstraint?.constant = 0
		navigationController?.setNavigationBarHidden(false, animated: animated)
		navigationController?.setToolbarHidden(false, animated: animated)
		additionalSafeAreaInsets.bottom = 0
		setBottomScrollEdgeEffectHidden(false)
		configureContextMenuInteraction()
	}

	func hideBars() {
		if isFullScreenAvailable {
			AppDefaults.shared.articleFullscreenEnabled = true
			coordinator.hideStatusBar()
			topShowBarsViewConstraint?.constant = -44.0
			bottomShowBarsViewConstraint?.constant = 44.0
			navigationController?.setNavigationBarHidden(true, animated: true)
			navigationController?.setToolbarHidden(true, animated: true)
			setBottomScrollEdgeEffectHidden(true)
			configureContextMenuInteraction()
		}
	}

	func toggleArticleExtractor() {

		guard let article = article else {
			return
		}

		guard articleExtractor?.state != .processing else {
			stopArticleExtractor()
			loadWebView()
			return
		}

		guard !isShowingExtractedArticle else {
			isShowingExtractedArticle = false
			loadWebView()
			articleExtractorButtonState = .off
			return
		}

		if let articleExtractor = articleExtractor {
			if article.preferredLink == articleExtractor.articleLink {
				isShowingExtractedArticle = true
				loadWebView()
				articleExtractorButtonState = .on
			}
		} else {
			startArticleExtractor()
		}

	}

	func stopArticleExtractorIfProcessing() {
		if articleExtractor?.state == .processing {
			stopArticleExtractor()
		}
	}

	func stopWebViewActivity() {
		if let webView = webView {
			stopMediaPlayback(webView)
			cancelImageLoad(webView)
		}
	}

	func showActivityDialog(popOverBarButtonItem: UIBarButtonItem? = nil) {
		guard let url = article?.preferredURL else { return }
		let activityViewController = UIActivityViewController(url: url, title: article?.title, applicationActivities: [FindInArticleActivity(), OpenInBrowserActivity()])
		activityViewController.popoverPresentationController?.barButtonItem = popOverBarButtonItem
		present(activityViewController, animated: true)
	}

	func openInAppBrowser() {
		guard let url = article?.preferredURL else { return }
		if AppDefaults.shared.useSystemBrowser {
			UIApplication.shared.open(url, options: [:])
		} else {
			openURLInSafariViewController(url)
		}
	}
}

// MARK: ArticleExtractorDelegate

extension WebViewController: ArticleExtractorDelegate {

	func articleExtractionDidFail(with: Error) {
		stopArticleExtractor()
		articleExtractorButtonState = .error
		loadWebView()
	}

	func articleExtractionDidComplete(extractedArticle: ExtractedArticle) {
		if articleExtractor?.state != .cancelled {
			self.extractedArticle = extractedArticle
			if let restoreWindowScrollY = restoreWindowScrollY {
				windowScrollY = restoreWindowScrollY
			}
			isShowingExtractedArticle = true
			loadWebView()
			articleExtractorButtonState = .on
		}
	}

}

// MARK: UIContextMenuInteractionDelegate

extension WebViewController: UIContextMenuInteractionDelegate {
    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {

		return UIContextMenuConfiguration(identifier: nil, previewProvider: contextMenuPreviewProvider) { [weak self] _ in
			guard let self = self else { return nil }

			var menus = [UIMenu]()

			var navActions = [UIAction]()
			if let action = self.prevArticleAction() {
				navActions.append(action)
			}
			if let action = self.nextArticleAction() {
				navActions.append(action)
			}
			if !navActions.isEmpty {
				menus.append(UIMenu(title: "", options: .displayInline, children: navActions))
			}

			var toggleActions = [UIAction]()
			if let action = self.toggleReadAction() {
				toggleActions.append(action)
			}
			toggleActions.append(self.toggleStarredAction())
			menus.append(UIMenu(title: "", options: .displayInline, children: toggleActions))

			if let action = self.nextUnreadArticleAction() {
				menus.append(UIMenu(title: "", options: .displayInline, children: [action]))
			}

			menus.append(UIMenu(title: "", options: .displayInline, children: [self.toggleArticleExtractorAction()]))
			menus.append(UIMenu(title: "", options: .displayInline, children: [self.shareAction()]))

			return UIMenu(title: "", children: menus)
        }
    }

	func contextMenuInteraction(_ interaction: UIContextMenuInteraction, willPerformPreviewActionForMenuWith configuration: UIContextMenuConfiguration, animator: UIContextMenuInteractionCommitAnimating) {
		coordinator.showBrowserForCurrentArticle()
	}

}

// MARK: WKNavigationDelegate

extension WebViewController: WKNavigationDelegate {

	/// 网页刚开始渲染就来一次 —— 比 didFinish 早得多(didFinish 要等图片等子资源全到齐)。
	func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
		nnwMarkReadingBar()	// [外观] 沉浸模式下尽早摘掉阅读栏的标记类
	}

	func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
		for (index, view) in view.subviews.enumerated() {
			if index != 0, let oldWebView = view as? PreloadedWebView {
				oldWebView.removeFromSuperview()
			}
		}
		nnwMediaEnhanceIfNeeded() // [播客][YouTube] 按内容类型补上语音条 / 视频简介,实现在本文件末尾
		nnwRecordAndAutoRestoreOnDidFinish() // [状态记忆] item③ 记住阅读模式 + 按需自动恢复译文,实现在本文件末尾
		nnwHandOffScrollViewToNavigationBar() // [外观] 把本页滚动交给顶栏跟踪(顶部透明↔滚动毛玻璃),实现在本文件末尾
		nnwMarkReadingBar() // [外观] 打标记类,让注入样式把网页里的标题/头像藏掉,实现在本文件末尾
		nnwUpdateReadingBar(contentSettled: true) // [外观] 阅读栏(方案 C):装载完了,从这一刻起滚动偏移可信
	}

	func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {

		if navigationAction.navigationType == .linkActivated {
			guard let url = navigationAction.request.url else {
				decisionHandler(.allow)
				return
			}

			let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
			if components?.scheme == "http" || components?.scheme == "https" {
				decisionHandler(.cancel)
				if AppDefaults.shared.useSystemBrowser {
					UIApplication.shared.open(url, options: [:])
				} else {
					UIApplication.shared.open(url, options: [.universalLinksOnly: true]) { didOpen in
						guard didOpen == false else {
							return
						}
						self.openURLInSafariViewController(url)
					}
				}

			} else if components?.scheme == "mailto" {
				decisionHandler(.cancel)

				guard let emailAddress = url.percentEncodedEmailAddress else {
					return
				}

				if UIApplication.shared.canOpenURL(emailAddress) {
					UIApplication.shared.open(emailAddress, options: [.universalLinksOnly: false], completionHandler: nil)
				} else {
					let alert = UIAlertController(title: NSLocalizedString("Error", comment: "Error"), message: NSLocalizedString("This device cannot send emails.", comment: "This device cannot send emails."), preferredStyle: .alert)
					alert.addAction(.init(title: NSLocalizedString("Dismiss", comment: "Dismiss"), style: .cancel, handler: nil))
					self.present(alert, animated: true, completion: nil)
				}
			} else if components?.scheme == "tel" {
				decisionHandler(.cancel)

				if UIApplication.shared.canOpenURL(url) {
					UIApplication.shared.open(url, options: [.universalLinksOnly: false], completionHandler: nil)
				}

			} else {
				decisionHandler(.allow)
			}
		} else {
			decisionHandler(.allow)
		}
	}

	func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
		fullReload()
	}

}

// MARK: WKUIDelegate

extension WebViewController: WKUIDelegate {

	func webView(_ webView: WKWebView, contextMenuForElement elementInfo: WKContextMenuElementInfo, willCommitWithAnimator animator: UIContextMenuInteractionCommitAnimating) {
		// We need to have at least an unimplemented WKUIDelegate assigned to the WKWebView.  This makes the
		// link preview launch Safari when the link preview is tapped.  In theory, you should be able to get
		// the link from the elementInfo above and transition to SFSafariViewController instead of launching
		// Safari.  As the time of this writing, the link in elementInfo is always nil.  ¯\_(ツ)_/¯
	}

	func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
		guard let url = navigationAction.request.url else {
			return nil
		}

		openURL(url)
		return nil
	}

}

// MARK: WKScriptMessageHandler

extension WebViewController: WKScriptMessageHandler {

	func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
		switch message.name {
		case MessageName.imageWasShown:
			clickedImageCompletion?()
		case MessageName.imageWasClicked:
			imageWasClicked(body: message.body as? String)
		case MessageName.showFeedInspector:
			if let feed = article?.feed {
				coordinator.showFeedInspector(for: feed)
			}
		default:
			return
		}
	}

}

// MARK: UIViewControllerTransitioningDelegate

extension WebViewController: UIViewControllerTransitioningDelegate {

	func animationController(forPresented presented: UIViewController, presenting: UIViewController, source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
		transition.presenting = true
		return transition
	}

	func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
		transition.presenting = false
		return transition
	}
}

// MARK:

extension WebViewController: UIScrollViewDelegate {

	func scrollViewDidScroll(_ scrollView: UIScrollView) {
		nnwUpdateBarsForScroll(scrollView)	// [外观] 滚动方向驱动藏/现栏(沉浸阅读),实现在本文件末尾扩展
		scrollPositionQueue.add(self, #selector(scrollPositionDidChange))
	}

	@objc func scrollPositionDidChange() {
		webView?.evaluateJavaScript("window.scrollY") { (scrollY, error) in
			guard error == nil else { return }
			let javascriptScrollY = scrollY as? Int ?? 0
			// I don't know why this value gets returned sometimes, but it is in error
			guard javascriptScrollY != 33554432 else { return }
			self.windowScrollY = javascriptScrollY
		}
	}
}

// MARK: JSON

private struct ImageClickMessage: Codable {
	let x: Float
	let y: Float
	let width: Float
	let height: Float
	let imageTitle: String?
	let imageURL: String
}

// MARK: Private

private extension WebViewController {

	func loadWebView(replaceExistingWebView: Bool = false) {
		guard isViewLoaded else { return }

		if !replaceExistingWebView, let webView = webView {
			self.renderPage(webView)
			return
		}

		coordinator.webViewProvider.dequeueWebView { webView in

			webView.ready {

				// Add the webview
				webView.translatesAutoresizingMaskIntoConstraints = false
				self.view.insertSubview(webView, at: 0)
				NSLayoutConstraint.activate([
					self.view.leadingAnchor.constraint(equalTo: webView.leadingAnchor),
					self.view.trailingAnchor.constraint(equalTo: webView.trailingAnchor),
					self.view.topAnchor.constraint(equalTo: webView.topAnchor),
					self.view.bottomAnchor.constraint(equalTo: webView.bottomAnchor)
				])

				// UISplitViewController reports the wrong size to WKWebView which can cause horizontal
				// rubberbanding on the iPad.  This interferes with our UIPageViewController preventing
				// us from easily swiping between WKWebViews.  This hack fixes that.
				webView.scrollView.contentInset = UIEdgeInsets(top: 0, left: -1, bottom: 0, right: 0)

				self.nnwUseUIKitPaperBackground(webView)	// [外观] 纸色底改由 UIKit 画、WebView 透明(实现在本文件末尾扩展)

				webView.scrollView.setZoomScale(1.0, animated: false)

				self.view.setNeedsLayout()
				self.view.layoutIfNeeded()

				// Configure the webview
				webView.navigationDelegate = self
				webView.uiDelegate = self
				webView.scrollView.delegate = self
				self.configureContextMenuInteraction()

				// Remove possible existing message handlers
				webView.configuration.userContentController.removeScriptMessageHandler(forName: MessageName.imageWasClicked)
				webView.configuration.userContentController.removeScriptMessageHandler(forName: MessageName.imageWasShown)
				webView.configuration.userContentController.removeScriptMessageHandler(forName: MessageName.showFeedInspector)

				// Add handlers
				webView.configuration.userContentController.add(WrapperScriptMessageHandler(self), name: MessageName.imageWasClicked)
				webView.configuration.userContentController.add(WrapperScriptMessageHandler(self), name: MessageName.imageWasShown)
				webView.configuration.userContentController.add(WrapperScriptMessageHandler(self), name: MessageName.showFeedInspector)

				self.renderPage(webView)
			}
		}
	}

	func renderPage(_ webView: PreloadedWebView?) {
		guard let webView = webView else { return }

		let theme = ArticleThemesManager.shared.currentTheme
		let rendering: ArticleRenderer.Rendering

		if let articleExtractor = articleExtractor, articleExtractor.state == .processing {
			rendering = ArticleRenderer.loadingHTML(theme: theme)
		} else if let articleExtractor = articleExtractor, articleExtractor.state == .failedToParse, let article = article {
			rendering = ArticleRenderer.articleHTML(article: article, theme: theme)
		} else if let article = article, let extractedArticle = extractedArticle {
			if isShowingExtractedArticle {
				rendering = ArticleRenderer.articleHTML(article: article, extractedArticle: extractedArticle, theme: theme)
			} else {
				rendering = ArticleRenderer.articleHTML(article: article, theme: theme)
			}
		} else if let article = article {
			rendering = ArticleRenderer.articleHTML(article: article, theme: theme)
		} else {
			rendering = ArticleRenderer.noSelectionHTML(theme: theme)
		}

		let substitutions = [
			"title": rendering.title,
			"baseURL": rendering.baseURL,
			"style": rendering.style,
			"body": rendering.html,
			"windowScrollY": String(windowScrollY)
		]

		var html = try! MacroProcessor.renderedText(withTemplate: ArticleRenderer.page.html, substitutions: substitutions)
		html = ArticleRenderingSpecialCases.filterHTMLIfNeeded(baseURL: rendering.baseURL, html: html)

		// Uncomment when you want to debug HTML and CSS for an article.
		// If you’re running in the simulator, this will write the file to a location on your Mac.
//		let debugFolderURL = AppConfig.dataSubfolder(named: "debug")
//		let fileURL = debugFolderURL.appendingPathComponent("article.html")
//		try? html.write(to: fileURL, atomically: true, encoding: .utf8)
//		print("article.html written to \(fileURL.path)")

		WebViewConfiguration.addContentBlockingRules(to: webView)
		webView.loadHTMLString(html, baseURL: Self.nnwAdjustedBaseURL(rendering.baseURL)) // [YouTube] 见文件末尾

		// [外观] 阅读栏(方案 C:每页一份)—— 网页刚开始装载就把栏挂上、正文往下推,
		// 不等 didFinish(治「老式表头闪现十几秒」)。contentSettled: false =
		// 装载期间按"停在顶部"画,别信 WebKit 装载中的滚动偏移。实现在 WebViewController+ReadingBar.swift。
		nnwUpdateReadingBar(contentSettled: false)
	}

	func finalScrollPosition(scrollingUp: Bool) -> CGFloat {
		guard let webView = webView else { return 0 }

		if scrollingUp {
			return -webView.scrollView.safeAreaInsets.top
		} else {
			return webView.scrollView.contentSize.height - webView.scrollView.bounds.height + webView.scrollView.safeAreaInsets.bottom
		}
	}

	func startArticleExtractor() {
		guard articleExtractor == nil else { return }
		// [阅读视图] hostView 传自己的 view:隐藏的提取用 WebView 要挂进视图层级才稳
		if let link = article?.preferredLink, let extractor = ReaderViewExtractor(link, delegate: self, hostView: view) {
			extractor.process()
			articleExtractor = extractor
			articleExtractorButtonState = .animated
		}
	}

	func stopArticleExtractor() {
		articleExtractor?.cancel()
		articleExtractor = nil
		isShowingExtractedArticle = false
		articleExtractorButtonState = .off
	}

	func reloadArticleImage() {
		guard let article = article else { return }

		var components = URLComponents()
		components.scheme = ArticleRenderer.imageIconScheme
		components.path = article.articleID

		if let imageSrc = components.string {
			webView?.evaluateJavaScript("reloadArticleImage(\"\(imageSrc)\")")
		}
	}

	func imageWasClicked(body: String?) {
		guard let webView, let body else { return }

		let data = Data(body.utf8)
		guard let clickMessage = try? JSONDecoder().decode(ImageClickMessage.self, from: data) else {
			return
		}

		guard let imageURL = URL(string: clickMessage.imageURL) else { return }

		Downloader.shared.download(imageURL) { [weak self] downloadResponse, error in
			guard let self, let data = downloadResponse.data, error == nil, !data.isEmpty,
				  let image = UIImage(data: data) else {
				return
			}
			self.showFullScreenImage(image: image, clickMessage: clickMessage, webView: webView)
		}
	}

	private func showFullScreenImage(image: UIImage, clickMessage: ImageClickMessage, webView: WKWebView) {

		let y = CGFloat(clickMessage.y) + webView.safeAreaInsets.top
		let rect = CGRect(x: CGFloat(clickMessage.x), y: y, width: CGFloat(clickMessage.width), height: CGFloat(clickMessage.height))
		transition.originFrame = webView.convert(rect, to: nil)

		if navigationController?.navigationBar.isHidden ?? false {
			transition.maskFrame = webView.convert(webView.frame, to: nil)
		} else {
			transition.maskFrame = webView.convert(webView.safeAreaLayoutGuide.layoutFrame, to: nil)
		}

		transition.originImage = image

		coordinator.showFullScreenImage(image: image, imageTitle: clickMessage.imageTitle, transitioningDelegate: self)
	}

	func stopMediaPlayback(_ webView: WKWebView) {
		webView.evaluateJavaScript("stopMediaPlayback();")
	}

	func cancelImageLoad(_ webView: WKWebView) {
		webView.evaluateJavaScript("cancelImageLoad();")
	}

	func configureTopShowBarsView() {
		topShowBarsView = UIView()
		topShowBarsView.backgroundColor = .clear
		topShowBarsView.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(topShowBarsView)

		if AppDefaults.shared.logicalArticleFullscreenEnabled {
			topShowBarsViewConstraint = view.topAnchor.constraint(equalTo: topShowBarsView.bottomAnchor, constant: -44.0)
		} else {
			topShowBarsViewConstraint = view.topAnchor.constraint(equalTo: topShowBarsView.bottomAnchor, constant: 0.0)
		}

		NSLayoutConstraint.activate([
			topShowBarsViewConstraint,
			view.leadingAnchor.constraint(equalTo: topShowBarsView.leadingAnchor),
			view.trailingAnchor.constraint(equalTo: topShowBarsView.trailingAnchor),
			topShowBarsView.heightAnchor.constraint(equalToConstant: 44.0)
		])
		topShowBarsView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(showBars(_:))))
	}

	func configureBottomShowBarsView() {
		bottomShowBarsView = UIView()
		bottomShowBarsView.backgroundColor = .clear
		bottomShowBarsView.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(bottomShowBarsView)
		if AppDefaults.shared.logicalArticleFullscreenEnabled {
			bottomShowBarsViewConstraint = view.bottomAnchor.constraint(equalTo: bottomShowBarsView.topAnchor, constant: 44.0)
		} else {
			bottomShowBarsViewConstraint = view.bottomAnchor.constraint(equalTo: bottomShowBarsView.topAnchor, constant: 0.0)
		}
		NSLayoutConstraint.activate([
			bottomShowBarsViewConstraint,
			view.leadingAnchor.constraint(equalTo: bottomShowBarsView.leadingAnchor),
			view.trailingAnchor.constraint(equalTo: bottomShowBarsView.trailingAnchor),
			bottomShowBarsView.heightAnchor.constraint(equalToConstant: 44.0)
		])
		bottomShowBarsView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(showBars(_:))))
	}

	func updateBottomSafeAreaForFullScreen() {
		let rawBottom = view.safeAreaInsets.bottom - additionalSafeAreaInsets.bottom
		additionalSafeAreaInsets.bottom = -rawBottom
	}

	/// Hide or show the toolbar scroll edge effect at the bottom of the web view.
	///
	/// Hidden when entering fullscreen so a residual effect doesn't obscure the
	/// bottom of the article.
	///
	/// <https://github.com/Ranchero-Software/NetNewsWire/issues/5298>
	func setBottomScrollEdgeEffectHidden(_ hidden: Bool) {
		guard #available(iOS 26, *) else {
			return
		}
		guard let scrollView = webView?.scrollView else {
			return
		}
		scrollView.bottomEdgeEffect.isHidden = hidden
	}

	func configureContextMenuInteraction() {
		if isFullScreenAvailable {
			if navigationController?.isNavigationBarHidden ?? false {
				webView?.addInteraction(contextMenuInteraction)
			} else {
				webView?.removeInteraction(contextMenuInteraction)
			}
		}
	}

	func contextMenuPreviewProvider() -> UIViewController {
		let previewProvider = UIStoryboard.main.instantiateController(ofType: ContextMenuPreviewViewController.self)
		previewProvider.article = article
		return previewProvider
	}

	func prevArticleAction() -> UIAction? {
		guard coordinator.isPrevArticleAvailable else { return nil }
		let title = NSLocalizedString("Previous Article", comment: "Previous Article")
		return UIAction(title: title, image: Assets.Images.prevArticle) { [weak self] _ in
			self?.coordinator.selectPrevArticle()
		}
	}

	func nextArticleAction() -> UIAction? {
		guard coordinator.isNextArticleAvailable else { return nil }
		let title = NSLocalizedString("Next Article", comment: "Next Article")
		return UIAction(title: title, image: Assets.Images.nextArticle) { [weak self] _ in
			self?.coordinator.selectNextArticle()
		}
	}

	func toggleReadAction() -> UIAction? {
		guard let article = article, !article.status.read || article.isAvailableToMarkUnread else { return nil }

		let title = article.status.read ? NSLocalizedString("Mark as Unread", comment: "Command") : NSLocalizedString("Mark as Read", comment: "Command")
		let readImage = article.status.read ? Assets.Images.circleClosed : Assets.Images.circleOpen
		return UIAction(title: title, image: readImage) { [weak self] _ in
			self?.coordinator.toggleReadForCurrentArticle()
		}
	}

	func toggleStarredAction() -> UIAction {
		let starred = article?.status.starred ?? false
		let title = starred ? NSLocalizedString("Mark as Unstarred", comment: "Command") : NSLocalizedString("Mark as Starred", comment: "Command")
		let starredImage = starred ? Assets.Images.starOpen : Assets.Images.starClosed
		return UIAction(title: title, image: starredImage) { [weak self] _ in
			self?.coordinator.toggleStarredForCurrentArticle()
		}
	}

	func nextUnreadArticleAction() -> UIAction? {
		guard coordinator.isNextUnreadAvailable else { return nil }
		let title = NSLocalizedString("Next Unread Article", comment: "Next Unread Article")
		return UIAction(title: title, image: Assets.Images.nextUnread) { [weak self] _ in
			self?.coordinator.selectNextUnread()
		}
	}

	func toggleArticleExtractorAction() -> UIAction {
		let extracted = articleExtractorButtonState == .on
		let title = extracted ? NSLocalizedString("Show Feed Article", comment: "Show Feed Article") : NSLocalizedString("Show Reader View", comment: "Show Reader View")
		let extractorImage = extracted ? Assets.Images.articleExtractorOff : Assets.Images.articleExtractorOn
		return UIAction(title: title, image: extractorImage) { [weak self] _ in
			self?.toggleArticleExtractor()
		}
	}

	func shareAction() -> UIAction {
		let title = NSLocalizedString("Share", comment: "Share button")
		return UIAction(title: title, image: Assets.Images.share) { [weak self] _ in
			self?.showActivityDialog()
		}
	}

	// If the resource cannot be opened with an installed app, present the web view.
	func openURL(_ url: URL) {
		UIApplication.shared.open(url, options: [.universalLinksOnly: true]) { didOpen in
			assert(Thread.isMainThread)
			guard didOpen == false else {
				return
			}
			self.openURLInSafariViewController(url)
		}
	}

	func openURLInSafariViewController(_ url: URL) {
		guard let viewController = SFSafariViewController.safeSafariViewController(url) else {
			return
		}
		present(viewController, animated: true)
	}
}

// MARK: Find in Article

private struct FindInArticleOptions: Codable {
	var text: String
	var caseSensitive = false
	var regex = false
}

internal struct FindInArticleState: Codable {
	struct WebViewClientRect: Codable {
		let x: Double
		let y: Double
		let width: Double
		let height: Double
	}

	struct FindInArticleResult: Codable {
		let rects: [WebViewClientRect]
		let bounds: WebViewClientRect
		let index: UInt
		let matchGroups: [String]
	}

	let index: UInt?
	let results: [FindInArticleResult]
	let count: UInt
}

extension WebViewController {

	func searchText(_ searchText: String, completionHandler: @escaping (FindInArticleState) -> Void) {
		guard let json = try? JSONEncoder().encode(FindInArticleOptions(text: searchText)) else {
			return
		}
		let encoded = json.base64EncodedString()

		webView?.evaluateJavaScript("updateFind(\"\(encoded)\")") { (result, error) in
			guard error == nil,
				let b64 = result as? String,
				let rawData = Data(base64Encoded: b64),
				let findState = try? JSONDecoder().decode(FindInArticleState.self, from: rawData) else {
					return
			}

			completionHandler(findState)
		}
	}

	func endSearch() {
		webView?.evaluateJavaScript("endFind()")
	}

	func selectNextSearchResult() {
		webView?.evaluateJavaScript("selectNextResult()")
	}

	func selectPreviousSearchResult() {
		webView?.evaluateJavaScript("selectPreviousResult()")
	}

}

// MARK: - [翻译] 本 fork 新增,上游没有以下内容
//
// 为什么这段代码非得写在这个文件里(而不是放在 Shared/Translation/):
// 上面第 36 行的 `webView` 属性是 `private` 的 —— Swift 里 private 表示
// "只有同一个文件里的代码能访问"。翻译功能必须能对这个 webView 执行 JS,
// 所以只能把这段桥接代码放在本文件内。
//
// 为降低将来 `git pull upstream` 的冲突风险,这段全部是**追加在文件末尾的新行**,
// 上游原有代码一行都没有改动。

extension WebViewController {

	/// 读取当前页面里的文章正文 HTML。找不到正文容器时返回 nil。
	func nnwTranslationReadBody() async throws -> String? {
		try await nnwTranslationEnsureScriptInjected()
		return try await nnwTranslationEvaluateReturningString("window.nnwTranslation.readBody()")
	}

	/// 把页面里的正文替换成译文。返回 true 表示替换成功。
	func nnwTranslationApply(_ translatedHTML: String) async throws -> Bool {
		try await nnwTranslationEnsureScriptInjected()
		let literal = try nnwTranslationJavaScriptStringLiteral(translatedHTML)
		return try await nnwTranslationEvaluateReturningBool("window.nnwTranslation.apply(\(literal))")
	}

	/// 让网页把正文切成若干组,返回 JSON 字符串 [{"group":0,"html":"..."}, ...]。
	/// 找不到正文容器时返回 nil。
	///
	/// - Parameters:
	///   - leadChars: 第 0 组(先导块)的目标字符数。它单独先翻,让用户尽快有东西可读。
	///   - firstGroupChars: 第 1 组的目标字符数。之后逐组翻倍 —— 读者顺序阅读,
	///     越靠前的组越要小而快,越靠后的组越可以大而省。
	///   - maxGroupChars: 单组字符上限。超长文章会自动多分几组,避免单次输出被截断。
	func nnwTranslationSplitBody(leadChars: Int, firstGroupChars: Int, maxGroupChars: Int) async throws -> String? {
		try await nnwTranslationEnsureScriptInjected()
		return try await nnwTranslationEvaluateReturningString(
			"window.nnwTranslation.splitBody(\(leadChars), \(firstGroupChars), \(maxGroupChars))")
	}

	/// 某一组的译文回来了,替换掉这一组。
	func nnwTranslationApplyGroup(group: Int, translatedHTML: String) async throws -> Bool {
		try await nnwTranslationEnsureScriptInjected()
		let literal = try nnwTranslationJavaScriptStringLiteral(translatedHTML)
		return try await nnwTranslationEvaluateReturningBool("window.nnwTranslation.applyGroup(\(group), \(literal))")
	}

	/// 事后检查:哪些组还是英文、或者混进了英文原文,需要重翻。
	/// 纯本地判断,不发请求、不花钱。
	/// 返回 JSON 字符串 [{"group":3,"html":"<原文>"}, ...]。
	func nnwTranslationFindGroupsNeedingRetranslation() async throws -> String? {
		try await nnwTranslationEnsureScriptInjected()
		return try await nnwTranslationEvaluateReturningString("window.nnwTranslation.findGroupsNeedingRetranslation()")
	}

	/// 正文的稳定指纹(纯文字,不含 HTML)。用于缓存的"内容变没变"校验。
	func nnwTranslationBodyFingerprint() async throws -> String? {
		try await nnwTranslationEnsureScriptInjected()
		return try await nnwTranslationEvaluateReturningString("window.nnwTranslation.bodyFingerprint()")
	}

	/// 读取文章标题的 HTML。标题在正文容器外面,所以要单独取。
	func nnwTranslationReadTitle() async throws -> String? {
		try await nnwTranslationEnsureScriptInjected()
		return try await nnwTranslationEvaluateReturningString("window.nnwTranslation.readTitle()")
	}

	/// 把标题换成译文。
	func nnwTranslationApplyTitle(_ translatedHTML: String) async throws -> Bool {
		try await nnwTranslationEnsureScriptInjected()
		let literal = try nnwTranslationJavaScriptStringLiteral(translatedHTML)
		return try await nnwTranslationEvaluateReturningBool("window.nnwTranslation.applyTitle(\(literal))")
	}

	/// 把正文换回原文。
	func nnwTranslationRestore() async throws -> Bool {
		try await nnwTranslationEnsureScriptInjected()
		return try await nnwTranslationEvaluateReturningBool("window.nnwTranslation.restore()")
	}

	/// 当前页面显示的是译文还是原文。
	func nnwTranslationIsShowingTranslation() async throws -> Bool {
		try await nnwTranslationEnsureScriptInjected()
		return try await nnwTranslationEvaluateReturningBool("window.nnwTranslation.state().isShowingTranslation")
	}

	/// 把页面滚到顶部。点翻译后调用,方便从头读译文(item④)。
	func nnwTranslationScrollToTop() async throws -> Bool {
		try await nnwTranslationEnsureScriptInjected()
		return try await nnwTranslationEvaluateReturningBool("window.nnwTranslation.scrollToTop()")
	}
}

private extension WebViewController {

	/// 确保 translation.js 已经注入到当前页面。
	/// 脚本自身有幂等保护,重复注入是安全的,所以每次操作前都注入一遍最省事。
	func nnwTranslationEnsureScriptInjected() async throws {
		_ = try await nnwTranslationEvaluateReturningBool(TranslationScript.source)
	}

	/// 把一段 HTML 变成可以安全嵌进 JS 代码里的字符串字面量。
	/// 用 JSON 编码来做转义 —— 引号、换行、反斜杠都会被正确处理。
	func nnwTranslationJavaScriptStringLiteral(_ string: String) throws -> String {
		let data = try JSONSerialization.data(withJSONObject: string, options: [.fragmentsAllowed])
		guard let literal = String(data: data, encoding: .utf8) else {
			throw TranslationError.invalidResponse
		}
		return literal
	}

	func nnwTranslationEvaluateReturningString(_ javaScript: String) async throws -> String? {
		guard let webView else { return nil }
		return try await withCheckedThrowingContinuation { continuation in
			webView.evaluateJavaScript(javaScript) { result, error in
				if let error {
					continuation.resume(throwing: error)
				} else {
					continuation.resume(returning: result as? String)
				}
			}
		}
	}

	func nnwTranslationEvaluateReturningBool(_ javaScript: String) async throws -> Bool {
		guard let webView else { return false }
		return try await withCheckedThrowingContinuation { continuation in
			webView.evaluateJavaScript(javaScript) { result, error in
				if let error {
					continuation.resume(throwing: error)
				} else {
					continuation.resume(returning: (result as? Bool) ?? false)
				}
			}
		}
	}
}

// MARK: - [播客] 本 fork 新增,上游没有以下内容
//
// 为什么这段代码非得写在这个文件里(而不是放在 Shared/Podcast/):
// 和上面 [翻译] 那段同一个原因 —— `webView` 属性是 `private` 的,
// Swift 里 private 表示「只有同一个文件里的代码能访问」。
// 要对这个 webView 执行 JS,只能把桥接代码放在本文件内。
//
// 这段全部是**追加在文件末尾的新行**,上游原有代码一行都没有改动。

extension WebViewController {

	/// 渲染文章时交给 `loadHTMLString(_:baseURL:)` 的 baseURL。
	/// **只对 YouTube 文章做替换,其它文章一律原样返回。**
	///
	/// ## 为什么需要这个
	///
	/// baseURL 决定了这个网页的"身份"(origin)。上游是拿文章链接当 baseURL 的,
	/// 而 YouTube 文章的链接正好是 `https://www.youtube.com/watch?v=…` ——
	/// 于是文章页**自称是 youtube.com**。
	///
	/// 嵌进去的 YouTube 播放器一校验"谁在嵌我",看到一个自称 YouTube、
	/// 却没有 YouTube 会话的页面,就拒绝播放,报「错误代码 152」。
	///
	/// ## 这不是猜的
	///
	/// 2026-07-21 做过一个对照实验:把**同一个视频**插进一篇非 YouTube 的文章
	/// (The Conversation,baseURL 是 theconversation.com)。同样的代码、
	/// 同样的视频,**唯一的变量是文章的身份** —— 结果那边能正常播放。
	/// 所以「换个身份就能播」是被证明的,不是推断。
	///
	/// ## 为什么改 baseURL 是安全的
	///
	/// baseURL 的正经用途是解析正文里的相对链接。而 YouTube 文章的
	/// `contentHTML` 长度是 **0**(官方 RSS 里没有 `<content>`,实测确认),
	/// **正文里根本没有相对链接可解析**,所以这个替换对 YouTube 文章没有副作用。
	/// 其它文章走的是原来的分支,一点不受影响。
	static func nnwAdjustedBaseURL(_ baseURLString: String) -> URL? {

		let original = URL(string: baseURLString)
		guard let host = original?.host?.lowercased() else {
			return original
		}

		let isYouTube = host == "youtube.com"
			|| host == "www.youtube.com"
			|| host == "m.youtube.com"
			|| host == "youtu.be"
		guard isYouTube else {
			return original
		}

		// 换成一个中性的身份。选 netnewswire.com 是为了和 app 自己已经
		// 对外声明的身份保持一致 —— Info.plist 里的 User-Agent 就是
		// 「NetNewsWire (RSS Reader; https://netnewswire.com/)」。
		// 这个地址会作为 Referer 发给 YouTube,所以选一个诚实的、
		// 确实代表这个 app 的值,而不是随便伪造一个域名。
		return URL(string: "https://netnewswire.com/") ?? original
	}

	/// 页面加载完成后的统一入口:按这篇文章的类型,补上上游没提供的东西。
	///
	/// 做成一个入口而不是挂两行,是为了让**上游文件的改动永远停在一行** ——
	/// 以后再加别的内容类型,也只改这个方法,不再动 `didFinish`。
	///
	/// 两件事都是「不是这类内容就什么都不做」,不弹任何提示。
	func nnwMediaEnhanceIfNeeded() {
		nnwPodcastInstallPlayerIfNeeded()
		nnwYouTubeLoadDescriptionIfNeeded()
	}

	/// YouTube 视频的简介。
	///
	/// 播放器由 `nnw_youtube.js` 自己从页面链接里认出来装好,不需要 Swift;
	/// 但**简介不在页面里** —— 上游的 Atom 解析器忽略所有带前缀的元素,
	/// `<media:description>` 压根没被解析过。所以只能重新拉一次 feed。
	///
	/// 非 YouTube 的源**一次请求都不会发**(靠 feed 地址就能认出来)。
	func nnwYouTubeLoadDescriptionIfNeeded() {

		guard let article else {
			return
		}

		Task { [weak self] in

			guard let text = await YouTubeDescriptionLoader.shared.description(for: article) else {
				return
			}
			// 拉取期间用户可能已经翻页了,写回界面前必须确认还是同一篇(L11)
			guard let self, self.article?.articleID == article.articleID else {
				return
			}
			let literal = Self.nnwPodcastJavaScriptStringLiteral(text)
			_ = try? await self.webView?.evaluateJavaScript(
				"window.nnwYouTube && window.nnwYouTube.setDescription(\(literal))")
		}
	}

	/// 页面加载完成后调用:如果这篇是播客单集,就在正文上方装一个语音条。
	///
	/// 整个过程是「悄悄进行」的 —— 不是播客就什么都不做,不弹任何提示。
	/// 判断依据是这篇文章所在的 feed 里到底有没有音频附件,
	/// 而这个判断结果会按 feed 缓存(**包括「不是播客」这个结论**),
	/// 所以普通文章最多只会让它的 feed 被拉取一次。
	func nnwPodcastInstallPlayerIfNeeded() {

		guard let article else {
			return
		}

		Task { [weak self] in

			// 先清掉上一篇留下的播放器。WebViewController 是复用的,
			// 不清的话上一篇的音频会挂在这一篇上(L14 同类问题)。
			_ = try? await self?.webView?.evaluateJavaScript("window.nnwPodcast && window.nnwPodcast.removePlayer()")

			guard let episode = await PodcastEpisodeLocator.shared.episode(for: article) else {
				return
			}
			// 拉取期间用户可能已经翻页了,写回界面前必须确认还是同一篇(L11)
			guard let self, self.article?.articleID == article.articleID else {
				return
			}

			let audioLiteral = Self.nnwPodcastJavaScriptStringLiteral(episode.audioURL)
			let duration = episode.durationInSeconds ?? 0
			_ = try? await self.webView?.evaluateJavaScript(
				"window.nnwPodcast.installPlayer(\(audioLiteral), \(duration))")

			// 语音条已经能听了,再去查「在播客中打开」的链接。
			// 这一步要访问苹果目录,比音频慢,所以放在后面单独做 ——
			// 查不到也不影响听。
			let feedTitle = article.feed?.nameForDisplay
			guard let link = await ApplePodcastsLinkResolver.shared.link(for: article, feedTitle: feedTitle) else {
				return
			}
			guard self.article?.articleID == article.articleID else {
				return
			}
			let isExactEpisode = link.absoluteString.contains("?i=")
			let linkLiteral = Self.nnwPodcastJavaScriptStringLiteral(link.absoluteString)
			_ = try? await self.webView?.evaluateJavaScript(
				"window.nnwPodcast.addAppleLink(\(linkLiteral), \(isExactEpisode))")
		}
	}

	/// 把字符串安全地拼进 JavaScript 里。
	/// 音频地址里常带 token 和各种查询参数,直接拼会出事。
	private static func nnwPodcastJavaScriptStringLiteral(_ value: String) -> String {
		guard let data = try? JSONSerialization.data(withJSONObject: [value]),
			  let json = String(data: data, encoding: .utf8) else {
			return "\"\""
		}
		// JSONSerialization 只能序列化数组/字典,所以包一层再把方括号去掉
		return String(json.dropFirst().dropLast())
	}
}

// MARK: - [状态记忆] 本 fork 新增,上游没有以下内容
//
// item③:按单篇文章记住「阅读模式 / 已翻译」,打开时自动恢复。
// 为什么非得写在这个文件里:要读私有的 articleExtractor 状态和私有的 isShowingExtractedArticle,
// 只有同一文件内的代码够得着。这段全是追加在文件末尾的新行,上游原有代码一行没动。

extension WebViewController {

	/// 打开这篇文章时,要不要自动进阅读模式?(供上面 setArticle 判断)
	func nnwShouldRestoreReaderMode(_ article: Article?) -> Bool {
		guard let article else { return false }
		return ArticleReadingStateStore.state(for: article.accountID + "|" + article.articleID).readerMode
	}

	/// 页面渲染完成时:记住这篇当前真实的阅读模式状态,并按需自动恢复译文。
	func nnwRecordAndAutoRestoreOnDidFinish() {

		// 阅读模式还在提取(此刻渲染的是 loading 占位页)时,什么都别做 ——
		// 等提取完成、渲染出最终内容那一次 didFinish 再处理。
		guard articleExtractor?.state != .processing else { return }
		guard let article else { return }
		let articleID = article.accountID + "|" + article.articleID

		// 记住当前真实显示的是不是阅读视图。
		// 提取失败时 isShowingExtractedArticle=false,会记成"不开阅读模式" ——
		// 这能避免下次对一个"抽不出正文"的源(如 YouTube,见 T11)反复做无用尝试。
		ArticleReadingStateStore.setReaderMode(isShowingExtractedArticle, for: articleID)

		// 若这篇被记为"上次翻过"且本地有匹配的完整缓存 → 自动秒显译文(交给翻译层判断)。
		(delegate as? ArticleViewController)?.nnwAutoApplyTranslationFromCacheIfNeeded()
	}
}

// MARK: - [外观] 滚动时自动隐藏/显示顶栏与底栏(沉浸阅读)
//
// 用户 2026-07-23 要求:读文章时下滑正文 → 顶栏 + 底栏一起消失(沉浸);
// 上滑 → 栏回来。取代原来"点导航栏切换全屏"的点击交互。
//
// 复用上游现成的 hideBars()/showBars()(它俩本就是顶底一起藏、还管状态栏和安全区),
// 本扩展只决定"根据滚动方向调用哪一个"。上游那两个方法一行未动。
//
// 判据不用系统的 hidesBarsOnSwipe —— 正文在 WKWebView 里,滚动发生在 web 的
// scrollView 内部,系统开关收不到;所以自己在 scrollViewDidScroll 里按方向判断。

/// 记录滚动累积距离的小状态盒(扩展不能加存储属性,用关联对象挂上去)。
private final class NNWScrollBarsHideState {
	var lastOffsetY: CGFloat = 0
	var accumulated: CGFloat = 0
	var primed = false

	/// 正在藏/现栏的过程中 —— 这段时间里**一切滚动回调都不作数**。
	///
	/// ⚠️ 没有这道闸门会**栈溢出崩溃**(2026-07-23 用户实测,栈里 28000 层递归)。
	/// 回路是这样闭合的:
	///   藏栏 → 导航栏收起 → 安全区变了 → 系统自动调整滚动位置 →
	///   位置变了又回调滚动 → 我们又判断方向 → 现栏 → 安全区又变 → …… 来回拉锯没有尽头。
	///
	/// 这个回路本来就存在,只是在把网页滚动视图交给导航栏跟踪
	/// (`setContentScrollView`,让顶栏能做"顶部通透/滚动毛玻璃")之后,
	/// 导航栏会**主动**去更新那个滚动视图的安全区,回路才闭合得又快又紧。
	/// 所以闸门和那个功能是配套的,**别删**。
	var isTogglingBars = false
}

extension WebViewController {

	private static var nnwScrollHideStateKey: UInt8 = 0
	private var nnwScrollHideState: NNWScrollBarsHideState {
		if let existing = objc_getAssociatedObject(self, &Self.nnwScrollHideStateKey) as? NNWScrollBarsHideState {
			return existing
		}
		let created = NNWScrollBarsHideState()
		objc_setAssociatedObject(self, &Self.nnwScrollHideStateKey, created, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
		return created
	}

	/// 同方向拖动累积超过这么多点(pt)才切换栏 —— 防止读时微调位置就闪来闪去。
	/// 觉得太灵敏就调大、太迟钝就调小。
	private static let nnwBarsToggleThreshold: CGFloat = 44

	/// 每次滚动回调时调,按滚动方向藏/现栏。
	func nnwUpdateBarsForScroll(_ scrollView: UIScrollView) {
		guard isFullScreenAvailable else { return }	// 功能没开就什么都不做

		// 📌 **和顶部「阅读栏」是分工,不是互斥**(2026-07-23 用户第二次调整后的方案)。
		//
		// 我一开始判断这两个功能互斥(栏都藏了,冻结的东西没地方待),于是让它们二选一。
		// 用户提出了更好的安排:**系统的栏是"导航"(返回、上/下一篇、底部工具条),
		// 读文章时该让路;我们那条是"阅读上下文"(在读谁的、什么文章、读到哪),该常驻。**
		// 于是:下滑 → 系统的栏全藏,只留阅读栏;上滑 → 全都回来。
		//
		// 所以这里**不再按阅读栏是否开启来拦**,两种模式下都照常藏/现栏。
		// (设置里的「全屏阅读」现在只决定**有没有那条阅读栏**:关 = 有,开 = 纯沉浸。)
		let state = nnwScrollHideState

		// ⚠️ 正在藏/现栏 → 这一轮的滚动是**系统自己调整安全区带来的**,不是用户在滑。
		// 必须原地返回,否则会无限套娃直到栈溢出(见 isTogglingBars 的说明)。
		// 放在最前面(连 lastOffsetY 都不记),因为切换结束后会重新取基准。
		guard !state.isTogglingBars else { return }

		let y = scrollView.contentOffset.y
		let topEdge = -scrollView.adjustedContentInset.top
		defer { state.lastOffsetY = y }

		// 第一帧只记基准,不判断(否则会拿一个巨大的初始 delta 乱触发)
		guard state.primed else {
			state.primed = true
			return
		}

		// 到顶:强制显示。否则栏藏着、又滚不动了,返回键就永远找不回来。
		if y <= topEdge + 4 {
			if navigationController?.isNavigationBarHidden == true {
				nnwToggleBars(hide: false)
			}
			state.accumulated = 0
			return
		}

		// 只在用户**主动拖动**时判断方向;惯性滑行、程序滚动都不切换,更稳。
		guard scrollView.panGestureRecognizer.state == .changed else { return }

		let delta = y - state.lastOffsetY
		// 方向一反转就把累积清零 —— 这样反向只要再拖 threshold 点就能切换,不迟钝。
		if (delta > 0) != (state.accumulated >= 0) {
			state.accumulated = 0
		}
		state.accumulated += delta

		let hidden = navigationController?.isNavigationBarHidden ?? false
		if state.accumulated > Self.nnwBarsToggleThreshold, !hidden {
			nnwToggleBars(hide: true)	// 内容上移(往下读)→ 藏栏
		} else if state.accumulated < -Self.nnwBarsToggleThreshold, hidden {
			nnwToggleBars(hide: false)	// 内容下移(往回看)→ 现栏
		}
	}

	/// 藏/现栏的**唯一入口** —— 把闸门落下、切换、再择机抬起。
	///
	/// ⚠️ **不要绕过它直接调 `hideBars()` / `showBars()`**,那样就没有闸门保护,
	/// 会重新炸出 28000 层递归的栈溢出(见 `isTogglingBars`)。
	///
	/// 闸门为什么要拖到下一轮 runloop 才抬起:切换栏引发的布局(安全区变化 →
	/// 滚动位置被系统调整 → 又回调滚动)是在**本轮同步**跑完的,必须整段罩住。
	/// 抬闸时顺手 `primed = false`:切换期间滚动位置被系统改过,
	/// 直接接着算方向会拿到一个混着"系统调整量"的假 delta,重新取一次基准最干净。
	private func nnwToggleBars(hide: Bool) {
		let state = nnwScrollHideState
		state.isTogglingBars = true
		state.accumulated = 0

		// ⚠️⚠️ **藏栏前先记住现在是不是「阅读栏模式」**(2026-07-24 修一串连环 bug 的钥匙):
		//
		// 上游 `hideBars()` 的第一行是 `AppDefaults.shared.articleFullscreenEnabled = true` ——
		// 它把"栏现在藏着"**持久化成了设置项**(上游语义:全屏开关 = 当前状态)。
		// 而阅读栏模式的判断读的正是这个值 → 一藏栏,阅读栏立刻被误判成"用户开了沉浸模式"
		// 而整个拆掉(用户截图:下滑到底顶栏全消失、位置乱跳)。
		// 更糟的是**藏着栏时杀掉 app,这个标记永久留在 true** —— 下次启动全 app 变沉浸模式。
		//
		// 所以:阅读栏模式下藏完栏,**立刻把标记写回 false**。上游那两个方法一行未动。
		let wasReadingBarMode = !AppDefaults.shared.logicalArticleFullscreenEnabled

		if hide {
			hideBars()
			if wasReadingBarMode {
				AppDefaults.shared.articleFullscreenEnabled = false
			}
		} else {
			showBars()
		}

		DispatchQueue.main.async { [weak self] in
			guard let self else { return }
			let state = self.nnwScrollHideState
			state.isTogglingBars = false
			state.primed = false		// 下一帧重新取基准
			state.accumulated = 0
		}
	}
}

// MARK: - [外观] 顶栏「渐变透明毛玻璃」的两块地基(2026-07-23 新增,本 fork)
//
// 目标:让文章内容页的顶栏和订阅列表页一样 —— **内容在顶部时通透、往下滚渐显毛玻璃、
// 深浅色自适应**。这件事此前折腾多轮没做成,原因和修法都写在这里,别再走回头路。
//
// 为什么以前做不成,两个原因,下面两个方法各解决一个:
//
// ① **透明不安全**:顶栏透明后,那一条露出的是背后的 WKWebView。而网页的深浅色走网页
//    自己的 `prefers-color-scheme`,不保证和 app 同步 —— 实测浅色模式下顶栏透出网页
//    的深色底,变成一片黑(L60)。
//    → `nnwUseUIKitPaperBackground` 把纸色底的所有权从网页收归 UIKit。
//
// ② **系统压根不给透明态**:iOS 的「顶部透明 ↔ 滚动毛玻璃」是系统自带的,但前提是
//    **导航栏知道该盯着哪个滚动视图**。订阅列表页背后就是普通列表,系统自己找得到;
//    而这里的 WKWebView 藏在 UIPageViewController 的子页面里,系统找不到 →
//    只好按"已经滚动了"处理 → 毛玻璃常驻,永远没有透明那一态。
//    → `nnwHandOffScrollViewToNavigationBar` 用系统正规接口把滚动视图指给导航栏。
//
// 两块缺一不可:只做 ① 没有透明态,只做 ② 就会复现 L60 的浅色顶栏变黑。

extension WebViewController {

	/// 把正文的纸色底从「网页画」改成「UIKit 画」。
	///
	/// 做法:WebView 自己不画背景(透明),露出它的 superview —— 也就是本控制器的 view,
	/// 由它铺 `AppAppearance.paperBackground`。那是个 UIKit 动态色,深浅色由系统自动重解析,
	/// **不依赖任何"变化了通知我"的回调**(L59 的教训:能让系统自适应的就别自己监听重建,
	/// 何况 `registerForTraitChanges` 在 UIPageViewController 子树里实测根本不触发)。
	///
	/// 配套改动在 `Shared/Appearance/nnw_appearance.js`(把 html/body 背景设成 transparent),
	/// **两处必须同时在**:只改这里 → 网页自己的底盖在上面,白改;只改那边 → 正文变 WebView 默认白底。
	///
	/// `underPageBackgroundColor` 设成 `.clear` 是有意的:它是过度滚动(橡皮筋)那块的底色,
	/// 留着不透明的纸色也不难看,但那样纸色就有了**两个来源**、且其中一个在 WebView 里
	/// (深浅色重解析时机不受我们控制,正是 L60 那类风险)。收成一个来源更稳(L56)。
	func nnwUseUIKitPaperBackground(_ webView: PreloadedWebView) {
		webView.isOpaque = false					// 不画自己的底,露出下面的 UIKit 纸色
		webView.backgroundColor = .clear
		webView.scrollView.backgroundColor = .clear
		webView.underPageBackgroundColor = .clear	// 橡皮筋区域也交给 UIKit,纸色只留一个来源
		view.backgroundColor = AppAppearance.paperBackground	// ← 纸色的唯一来源(动态色,自适应深浅)
	}

	/// 告诉导航栏「请盯着本页的滚动视图」,这样系统才肯给出「顶部透明 / 滚动毛玻璃」两态。
	///
	/// 用的是系统正规接口 `setContentScrollView`(iOS 15+,本工程最低 iOS 17)。
	/// 设在 `ArticleViewController` 上 —— 顶栏归它管(navigationItem 在它身上),
	/// 本控制器只是它翻页容器里的一页。
	///
	/// ⚠️ 用 `as? ArticleViewController` 强转是**有意的**,照抄本文件已有的做法
	/// (见 `nnwRecordAndAutoRestoreOnDidFinish` 里对译文自动恢复的调用):
	/// 这样不用去动上游的 `WebViewControllerDelegate` 协议,merge 时少一个冲突点。
	func nnwHandOffScrollViewToNavigationBar() {
		(delegate as? ArticleViewController)?.nnwTrackCurrentArticleScrolling()
	}

	/// 本页的滚动视图(给上面那位跨控制器取用 —— `webView` 是 private,同文件内才够得着)。
	var nnwContentScrollView: UIScrollView? {
		webView?.scrollView
	}
}

// MARK: - [外观] 阅读栏的标记类

extension WebViewController {

	/// 给 `<html>` 打上 `nnw-reading-bar` 标记类。
	///
	/// 注入样式里那两条「藏掉网页标题与头像」的规则挂在这个类下面 ——
	/// **不这么做就会连 macOS 一起藏掉**(`nnw_appearance.js` 在 `Shared/` 下,两个平台共用),
	/// 而 macOS 没有那条 UIKit 阅读栏,藏了标题正文就没头没脑了。
	///
	/// 顺带白拿一件事:切回「沉浸模式」时不打这个标记,网页里的标题和头像**自动回来** ——
	/// 两种阅读模式各自完整,不需要另写一套还原逻辑。
	func nnwMarkReadingBar() {
		let enabled = traitCollection.userInterfaceIdiom == .phone
			&& !AppDefaults.shared.logicalArticleFullscreenEnabled
		// ⚠️ **打标记这件事已经交给注入脚本在 document start 做了**(见 nnw_appearance.js
		// 的 markReadingBarIfNeeded)。原因:这里是 didFinish,要等图片等子资源全部到齐,
		// 真机上可能晚好几秒 —— 那几秒里网页自己的表头照常显示,和阅读栏同时出现
		// (用户 2026-07-23 真机实测)。
		//
		// 所以这里现在**只负责一件事:沉浸模式下把它摘掉**。
		// 常规路径(有阅读栏)一个 JS 都不用发,自然也就没有竞态。
		guard !enabled else { return }
		webView?.evaluateJavaScript("document.documentElement.classList.remove('nnw-reading-bar')")
	}
}
