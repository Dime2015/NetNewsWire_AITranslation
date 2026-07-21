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
				if article?.feed?.readerViewAlwaysEnabled == true {
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

	func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
		for (index, view) in view.subviews.enumerated() {
			if index != 0, let oldWebView = view as? PreloadedWebView {
				oldWebView.removeFromSuperview()
			}
		}
		nnwPodcastInstallPlayerIfNeeded() // [播客] 是播客单集就装语音条,实现在本文件末尾
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
		webView.loadHTMLString(html, baseURL: URL(string: rendering.baseURL))
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
