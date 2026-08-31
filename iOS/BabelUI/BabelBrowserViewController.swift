//
//  BabelBrowserViewController.swift
//  NetNewsWire
//

import UIKit
import WebKit

/// Babel's in-app source browser. It is pushed on the same navigation stack as
/// the article so the shell's interactive right-swipe returns directly to the
/// rendered article instead of dismissing an unrelated modal browser.
final class BabelBrowserViewController: UIViewController, WKNavigationDelegate, WKUIDelegate {

	private let initialURL: URL
	private let articleTitle: String
	private let header = UIView()
	private let toolbar = UIView()
	private let titleLabel = UILabel()
	private let hostLabel = UILabel()
	private let progressView = UIProgressView(progressViewStyle: .bar)
	private let webView: WKWebView
	private let backButton = UIButton(type: .custom)
	private let forwardButton = UIButton(type: .custom)
	private let reloadButton = UIButton(type: .custom)
	private let shareButton = UIButton(type: .custom)
	private let errorLabel = UILabel()
	private var observations = [NSKeyValueObservation]()

	init(url: URL, articleTitle: String) {
		initialURL = url
		self.articleTitle = articleTitle
		let configuration = WKWebViewConfiguration()
		configuration.websiteDataStore = .default()
		configuration.defaultWebpagePreferences.allowsContentJavaScript = true
		webView = WKWebView(frame: .zero, configuration: configuration)
		super.init(nibName: nil, bundle: nil)
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		configureView()
		observeWebView()
		webView.load(URLRequest(url: initialURL))
	}

	override func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)
		if isMovingFromParent { webView.stopLoading() }
	}

	private func configureView() {
		view.backgroundColor = BabelPalette.background
		view.isOpaque = true
		navigationItem.largeTitleDisplayMode = .never

		header.backgroundColor = BabelPalette.background
		header.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(header)

		let closeButton = makeButton(symbol: "chevron.left", label: "返回文章", pointSize: 18)
		closeButton.accessibilityIdentifier = "babel.browser.back-to-article"
		closeButton.addTarget(self, action: #selector(closeBrowser), for: .touchUpInside)
		header.addSubview(closeButton)

		hostLabel.font = .systemFont(ofSize: 10, weight: .medium)
		hostLabel.textColor = BabelPalette.mutedInk
		hostLabel.textAlignment = .center
		hostLabel.text = initialURL.host?.uppercased()
		hostLabel.translatesAutoresizingMaskIntoConstraints = false
		header.addSubview(hostLabel)

		titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
		titleLabel.textColor = BabelPalette.ink
		titleLabel.textAlignment = .center
		titleLabel.lineBreakMode = .byTruncatingTail
		titleLabel.text = articleTitle
		titleLabel.translatesAutoresizingMaskIntoConstraints = false
		header.addSubview(titleLabel)

		let externalButton = makeButton(symbol: "safari", label: "在系统浏览器打开", pointSize: 17)
		externalButton.accessibilityIdentifier = "babel.browser.open-external"
		externalButton.addTarget(self, action: #selector(openExternally), for: .touchUpInside)
		header.addSubview(externalButton)

		progressView.tintColor = BabelPalette.mutedInk
		progressView.trackTintColor = .clear
		progressView.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(progressView)

		webView.navigationDelegate = self
		webView.uiDelegate = self
		webView.allowsBackForwardNavigationGestures = false
		webView.allowsLinkPreview = true
		webView.backgroundColor = BabelPalette.background
		webView.scrollView.backgroundColor = BabelPalette.background
		webView.accessibilityIdentifier = "babel.browser.web-content"
		webView.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(webView)

		toolbar.backgroundColor = BabelPalette.background
		toolbar.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(toolbar)

		let separator = UIView()
		separator.backgroundColor = BabelPalette.hairline
		separator.translatesAutoresizingMaskIntoConstraints = false
		toolbar.addSubview(separator)

		configureToolbarButton(backButton, symbol: "chevron.left", label: "网页后退", action: #selector(goBack))
		configureToolbarButton(forwardButton, symbol: "chevron.right", label: "网页前进", action: #selector(goForward))
		configureToolbarButton(reloadButton, symbol: "arrow.clockwise", label: "重新载入", action: #selector(reloadPage))
		configureToolbarButton(shareButton, symbol: "square.and.arrow.up", label: "分享网页", action: #selector(sharePage))
		let toolbarButtons = [backButton, forwardButton, reloadButton, shareButton]
		let toolbarStack = UIStackView(arrangedSubviews: toolbarButtons)
		toolbarStack.axis = .horizontal
		toolbarStack.alignment = .center
		toolbarStack.distribution = .fillEqually
		toolbarStack.translatesAutoresizingMaskIntoConstraints = false
		toolbar.addSubview(toolbarStack)

		errorLabel.font = .systemFont(ofSize: 15)
		errorLabel.textColor = BabelPalette.mutedInk
		errorLabel.textAlignment = .center
		errorLabel.numberOfLines = 0
		errorLabel.text = "网页加载失败\n点击重新载入"
		errorLabel.isHidden = true
		errorLabel.isUserInteractionEnabled = true
		errorLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(reloadPage)))
		errorLabel.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(errorLabel)

		NSLayoutConstraint.activate([
			header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
			header.heightAnchor.constraint(equalToConstant: 58),
			closeButton.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 10),
			closeButton.centerYAnchor.constraint(equalTo: header.centerYAnchor),
			closeButton.widthAnchor.constraint(equalToConstant: 44),
			closeButton.heightAnchor.constraint(equalToConstant: 44),
			externalButton.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -10),
			externalButton.centerYAnchor.constraint(equalTo: header.centerYAnchor),
			externalButton.widthAnchor.constraint(equalToConstant: 44),
			externalButton.heightAnchor.constraint(equalToConstant: 44),
			titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: closeButton.trailingAnchor, constant: 8),
			titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: externalButton.leadingAnchor, constant: -8),
			titleLabel.centerXAnchor.constraint(equalTo: header.centerXAnchor),
			titleLabel.topAnchor.constraint(equalTo: header.topAnchor, constant: 13),
			hostLabel.centerXAnchor.constraint(equalTo: titleLabel.centerXAnchor),
			hostLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
			hostLabel.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.leadingAnchor),
			hostLabel.trailingAnchor.constraint(lessThanOrEqualTo: titleLabel.trailingAnchor),
			progressView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			progressView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			progressView.topAnchor.constraint(equalTo: header.bottomAnchor),
			webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			webView.topAnchor.constraint(equalTo: header.bottomAnchor),
			webView.bottomAnchor.constraint(equalTo: toolbar.topAnchor),
			toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			toolbar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
			toolbar.heightAnchor.constraint(equalToConstant: BabelChromeMetrics.bottomToolbarHeight),
			separator.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor),
			separator.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor),
			separator.topAnchor.constraint(equalTo: toolbar.topAnchor),
			separator.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),
			toolbarStack.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor),
			toolbarStack.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor),
			toolbarStack.centerYAnchor.constraint(equalTo: toolbar.topAnchor, constant: BabelChromeMetrics.bottomControlCenterY),
			toolbarStack.heightAnchor.constraint(equalToConstant: 44),
			errorLabel.centerXAnchor.constraint(equalTo: webView.centerXAnchor),
			errorLabel.centerYAnchor.constraint(equalTo: webView.centerYAnchor),
			errorLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
			errorLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32)
		])

		updateNavigationState()
	}

	private func observeWebView() {
		observations.append(webView.observe(\.estimatedProgress, options: [.initial, .new]) { [weak self] webView, _ in
			Task { @MainActor in
				self?.progressView.progress = Float(webView.estimatedProgress)
				self?.progressView.isHidden = webView.estimatedProgress >= 1
			}
		})
		observations.append(webView.observe(\.canGoBack, options: [.initial, .new]) { [weak self] _, _ in
			Task { @MainActor in self?.updateNavigationState() }
		})
		observations.append(webView.observe(\.canGoForward, options: [.initial, .new]) { [weak self] _, _ in
			Task { @MainActor in self?.updateNavigationState() }
		})
		observations.append(webView.observe(\.title, options: [.new]) { [weak self] webView, _ in
			Task { @MainActor in
				if let title = webView.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
					self?.titleLabel.text = title
				}
				self?.hostLabel.text = webView.url?.host?.uppercased()
			}
		})
	}

	private func makeButton(symbol: String, label: String, pointSize: CGFloat) -> UIButton {
		let button = UIButton(type: .custom)
		button.setImage(UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)), for: .normal)
		button.tintColor = BabelPalette.ink
		button.accessibilityLabel = label
		button.translatesAutoresizingMaskIntoConstraints = false
		return button
	}

	private func configureToolbarButton(_ button: UIButton, symbol: String, label: String, action: Selector) {
		button.setImage(BabelChromeMetrics.bottomSymbol(symbol), for: .normal)
		button.tintColor = BabelPalette.ink
		button.accessibilityLabel = label
		button.addTarget(self, action: action, for: .touchUpInside)
		button.translatesAutoresizingMaskIntoConstraints = false
	}

	private func updateNavigationState() {
		backButton.isEnabled = webView.canGoBack
		forwardButton.isEnabled = webView.canGoForward
		backButton.alpha = webView.canGoBack ? 1 : 0.28
		forwardButton.alpha = webView.canGoForward ? 1 : 0.28
	}

	@objc private func closeBrowser() { navigationController?.popViewController(animated: true) }
	@objc private func goBack() { if webView.canGoBack { webView.goBack() } }
	@objc private func goForward() { if webView.canGoForward { webView.goForward() } }
	@objc private func reloadPage() {
		errorLabel.isHidden = true
		if webView.url == nil { webView.load(URLRequest(url: initialURL)) } else { webView.reload() }
	}
	@objc private func openExternally() {
		UIApplication.shared.open(webView.url ?? initialURL)
	}
	@objc private func sharePage() {
		let url = webView.url ?? initialURL
		present(UIActivityViewController(activityItems: [url], applicationActivities: nil), animated: true)
	}

	func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
		errorLabel.isHidden = true
		updateNavigationState()
	}

	func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
		guard (error as NSError).code != NSURLErrorCancelled else { return }
		errorLabel.isHidden = false
	}

	func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
		self.webView(webView, didFail: navigation, withError: error)
	}

	func webView(_ webView: WKWebView,
				 decidePolicyFor navigationAction: WKNavigationAction,
				 decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
		guard let url = navigationAction.request.url else {
			decisionHandler(.cancel)
			return
		}
		if navigationAction.targetFrame == nil {
			webView.load(navigationAction.request)
			decisionHandler(.cancel)
			return
		}
		let scheme = url.scheme?.lowercased()
		guard scheme == "http" || scheme == "https" || scheme == "about" else {
			UIApplication.shared.open(url)
			decisionHandler(.cancel)
			return
		}
		decisionHandler(.allow)
	}

	func webView(_ webView: WKWebView,
				 createWebViewWith configuration: WKWebViewConfiguration,
				 for navigationAction: WKNavigationAction,
				 windowFeatures: WKWindowFeatures) -> WKWebView? {
		if navigationAction.targetFrame == nil { webView.load(navigationAction.request) }
		return nil
	}
}

enum BabelOriginalLinkSwipePolicy {
	static func shouldBegin(
		hasOriginalURL: Bool,
		transitionInFlight: Bool,
		translation: CGPoint,
		velocity: CGPoint
	) -> Bool {
		guard hasOriginalURL, !transitionInFlight else { return false }
		let direction = abs(translation.x) + abs(translation.y) > 0.5 ? translation : velocity
		return direction.x < 0 && abs(direction.x) > abs(direction.y) * 1.08
	}

	static func shouldOpen(translationX: CGFloat, velocityX: CGFloat) -> Bool {
		translationX < -72 || (translationX < -24 && velocityX < -650)
	}
}
