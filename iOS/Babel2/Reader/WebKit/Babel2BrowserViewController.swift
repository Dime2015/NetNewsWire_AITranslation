import UIKit
import WebKit

/// Babel 2.0 内置浏览器（Slice 5 第 3 步，ADR-021）。
///
/// 设计稿没有浏览器画面，版式沿用阅读页（用户 2026-09-25 同意）：
/// - 顶栏 58pt：左 ✕ 回到文章（x=32，中心 y=22）；中间两行 = 网页标题（14pt 半粗，ADR-033）+ 域名（11pt 浅灰）
/// - 顶栏下方 2pt 中性灰加载进度线；加载失败显示原因 + 重试
/// - 底栏 72pt（0.5pt 分隔线），五格与阅读页同位置：后退 / 前进 / 刷新 / 分享 / 在 Safari 中打开
/// - 回到文章：左边缘右滑（沿用统一的返回手势）或点 ✕
///
/// 这是真正的网页，所以用独立的网页控件、不加阅读页那套「禁止页面脚本」的安全策略；
/// 浏览器自己的前进后退历史只留在这里，不影响阅读页。
/// 放在网页控件专用目录（边界测试规定只有这里能出现网页控件）。
@MainActor
final class Babel2BrowserViewController: UIViewController, WKNavigationDelegate {
	private let initialURL: URL
	private let openExternally: (URL) -> Void
	private let webView = WKWebView(frame: .zero)
	private let titleLabel = UILabel()
	private let hostLabel = UILabel()
	private let progressLine = UIView()
	private var progressWidth: NSLayoutConstraint?
	private let errorStack = UIStackView()
	private let errorLabel = UILabel()
	private let backButton = UIButton(type: .system)
	private let forwardButton = UIButton(type: .system)
	private let reloadButton = UIButton(type: .system)
	private let shareButton = UIButton(type: .system)
	private let safariButton = UIButton(type: .system)
	private var observations = [NSKeyValueObservation]()
	private var didStartLoading = false

	init(url: URL, openExternally: @escaping (URL) -> Void) {
		initialURL = url
		self.openExternally = openExternally
		super.init(nibName: nil, bundle: nil)
		restorationIdentifier = "babel2.browser"
	}

	required init?(coder: NSCoder) { nil }

	/// 手势跟手之前就要准备好：页面结构和加载占位先建好，网络加载在后台开始（MOTION-CONTRACT §7）。
	func prepare() {
		loadViewIfNeeded()
		startLoadingIfNeeded()
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		view.backgroundColor = BabelPalette.background
		let topBar = configureTopBar()
		let toolbar = configureToolbar()
		configureWebView(below: topBar, above: toolbar)
		configureProgress(below: topBar)
		configureError()
		observations = [
			webView.observe(\.estimatedProgress, options: [.new]) { [weak self] _, _ in
				MainActor.assumeIsolated { self?.updateProgress() }
			},
			webView.observe(\.title, options: [.new]) { [weak self] _, _ in
				MainActor.assumeIsolated { self?.updateTitle() }
			},
			webView.observe(\.url, options: [.new]) { [weak self] _, _ in
				MainActor.assumeIsolated { self?.updateTitle() }
			},
			webView.observe(\.canGoBack, options: [.new]) { [weak self] _, _ in
				MainActor.assumeIsolated { self?.updateNavigationButtons() }
			},
			webView.observe(\.canGoForward, options: [.new]) { [weak self] _, _ in
				MainActor.assumeIsolated { self?.updateNavigationButtons() }
			}
		]
		updateTitle()
		updateNavigationButtons()
		startLoadingIfNeeded()
	}

	private func startLoadingIfNeeded() {
		guard isViewLoaded, !didStartLoading else { return }
		didStartLoading = true
		webView.load(URLRequest(url: initialURL))
	}

	/// 手势取消时丢弃：停止加载，不留网络请求。
	func discard() {
		webView.stopLoading()
	}

	// MARK: - 顶栏

	private func configureTopBar() -> UIView {
		let statusBackdrop = UIView()
		let bar = UIView()
		[statusBackdrop, bar].forEach {
			$0.backgroundColor = BabelPalette.background
			$0.translatesAutoresizingMaskIntoConstraints = false
			view.addSubview($0)
		}
		let close = UIButton(type: .system)
		close.setImage(Babel2Type.icon(UIImage(named: "Babel2ReaderClose"), side: Babel2Type.readerTopIcon)?.withRenderingMode(.alwaysTemplate), for: .normal)
		close.tintColor = BabelPalette.mutedInk
		close.accessibilityLabel = Babel2Localization.text(.back)
		close.accessibilityIdentifier = "babel2.browser.close"
		close.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
		close.translatesAutoresizingMaskIntoConstraints = false
		Babel2Motion.addPressFeedback(to: close)
		bar.addSubview(close)

		titleLabel.font = Babel2Type.browserTitle
		titleLabel.textColor = BabelPalette.ink
		titleLabel.textAlignment = .center
		titleLabel.lineBreakMode = .byTruncatingTail
		titleLabel.accessibilityIdentifier = "babel2.browser.title"
		hostLabel.font = .systemFont(ofSize: 11, weight: .regular)
		hostLabel.textColor = BabelPalette.tertiaryInk
		hostLabel.textAlignment = .center
		hostLabel.lineBreakMode = .byTruncatingMiddle
		hostLabel.accessibilityIdentifier = "babel2.browser.host"
		let titles = UIStackView(arrangedSubviews: [titleLabel, hostLabel])
		titles.axis = .vertical
		titles.spacing = 1
		titles.translatesAutoresizingMaskIntoConstraints = false
		bar.addSubview(titles)

		NSLayoutConstraint.activate([
			statusBackdrop.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			statusBackdrop.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			statusBackdrop.topAnchor.constraint(equalTo: view.topAnchor),
			statusBackdrop.bottomAnchor.constraint(equalTo: bar.topAnchor),
			bar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			bar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			bar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
			bar.heightAnchor.constraint(equalToConstant: 58),
			close.centerXAnchor.constraint(equalTo: bar.leadingAnchor, constant: 32),
			close.centerYAnchor.constraint(equalTo: bar.topAnchor, constant: 22),
			close.widthAnchor.constraint(equalToConstant: 44),
			close.heightAnchor.constraint(equalToConstant: 44),
			titles.centerXAnchor.constraint(equalTo: bar.centerXAnchor),
			titles.centerYAnchor.constraint(equalTo: close.centerYAnchor),
			titles.leadingAnchor.constraint(greaterThanOrEqualTo: close.trailingAnchor, constant: 8),
			titles.trailingAnchor.constraint(lessThanOrEqualTo: bar.trailingAnchor, constant: -60)
		])
		return bar
	}

	// MARK: - 底栏

	private func configureToolbar() -> UIView {
		let toolbar = UIView()
		toolbar.backgroundColor = BabelPalette.background
		toolbar.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(toolbar)
		let separator = UIView()
		separator.backgroundColor = BabelPalette.hairline
		separator.translatesAutoresizingMaskIntoConstraints = false
		toolbar.addSubview(separator)

		let items: [(UIButton, String, Babel2LocalizationKey, String, Selector)] = [
			(backButton, "chevron.left", .browserBack, "babel2.browser.back", #selector(backTapped)),
			(forwardButton, "chevron.right", .browserForward, "babel2.browser.forward", #selector(forwardTapped)),
			(reloadButton, "arrow.clockwise", .browserReload, "babel2.browser.reload", #selector(reloadTapped)),
			(shareButton, "square.and.arrow.up", .share, "babel2.browser.share", #selector(shareTapped)),
			(safariButton, "safari", .openInSafari, "babel2.browser.safari", #selector(safariTapped))
		]
		// 与阅读页底栏相同的五个中心位置（Babel2BarLayout：x = 32 / 116.5 / 201 / 285.5 / 370，中心 y = 24）
		let centers = Babel2BarLayout.slots
		var constraints = [
			toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			toolbar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
			toolbar.heightAnchor.constraint(equalToConstant: 72),
			separator.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor),
			separator.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor),
			separator.topAnchor.constraint(equalTo: toolbar.topAnchor),
			separator.heightAnchor.constraint(equalToConstant: 0.5)
		]
		for ((button, symbol, key, identifier, action), center) in zip(items, centers) {
			// 设计稿无浏览器图标：系统符号，按阅读页图标的灰度与视觉尺寸
			button.setImage(UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: Babel2Type.toolbarSymbol, weight: .medium)), for: .normal)
			button.tintColor = BabelPalette.mutedInk
			button.accessibilityLabel = Babel2Localization.text(key)
			button.accessibilityIdentifier = identifier
			button.addTarget(self, action: action, for: .touchUpInside)
			button.translatesAutoresizingMaskIntoConstraints = false
			Babel2Motion.addPressFeedback(to: button)
			toolbar.addSubview(button)
			constraints += [
				Babel2BarLayout.centerX(button, in: toolbar, slot: center),
				button.centerYAnchor.constraint(equalTo: toolbar.topAnchor, constant: Babel2BarLayout.centerY),
				button.widthAnchor.constraint(equalToConstant: 44),
				button.heightAnchor.constraint(equalToConstant: 44)
			]
		}
		NSLayoutConstraint.activate(constraints)
		return toolbar
	}

	// MARK: - 网页 / 进度 / 错误

	private func configureWebView(below topBar: UIView, above toolbar: UIView) {
		webView.navigationDelegate = self
		// 网页自带的左滑后退会和「左边缘返回文章」抢手势：关掉，后退用底栏按钮
		webView.allowsBackForwardNavigationGestures = false
		webView.accessibilityIdentifier = "babel2.browser.web"
		webView.translatesAutoresizingMaskIntoConstraints = false
		view.insertSubview(webView, at: 0)
		NSLayoutConstraint.activate([
			webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			webView.topAnchor.constraint(equalTo: topBar.bottomAnchor),
			webView.bottomAnchor.constraint(equalTo: toolbar.topAnchor)
		])
	}

	private func configureProgress(below topBar: UIView) {
		progressLine.backgroundColor = BabelPalette.mutedInk
		progressLine.accessibilityIdentifier = "babel2.browser.progress"
		progressLine.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(progressLine)
		let width = progressLine.widthAnchor.constraint(equalToConstant: 0)
		progressWidth = width
		NSLayoutConstraint.activate([
			progressLine.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			progressLine.topAnchor.constraint(equalTo: topBar.bottomAnchor),
			progressLine.heightAnchor.constraint(equalToConstant: 2),
			width
		])
	}

	private func configureError() {
		errorLabel.font = .preferredFont(forTextStyle: .body)
		errorLabel.textColor = BabelPalette.mutedInk
		errorLabel.numberOfLines = 0
		errorLabel.textAlignment = .center
		errorLabel.accessibilityIdentifier = "babel2.browser.error"
		var retry = UIButton.Configuration.plain()
		retry.title = Babel2Localization.text(.retry)
		retry.baseForegroundColor = BabelPalette.ink
		let retryButton = UIButton(configuration: retry)
		retryButton.accessibilityIdentifier = "babel2.browser.retry"
		retryButton.addTarget(self, action: #selector(reloadTapped), for: .touchUpInside)
		errorStack.axis = .vertical
		errorStack.alignment = .center
		errorStack.spacing = 8
		errorStack.addArrangedSubview(errorLabel)
		errorStack.addArrangedSubview(retryButton)
		errorStack.isHidden = true
		errorStack.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(errorStack)
		NSLayoutConstraint.activate([
			errorStack.centerXAnchor.constraint(equalTo: webView.centerXAnchor),
			errorStack.centerYAnchor.constraint(equalTo: webView.centerYAnchor),
			errorStack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
			errorStack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32)
		])
	}

	private func updateProgress() {
		let progress = webView.estimatedProgress
		let loading = webView.isLoading && progress < 1
		progressWidth?.constant = view.bounds.width * CGFloat(progress)
		UIView.animate(withDuration: 0.2) {
			self.progressLine.alpha = loading ? 1 : 0
			self.view.layoutIfNeeded()
		}
	}

	private func updateTitle() {
		let url = webView.url ?? initialURL
		let title = webView.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
		titleLabel.text = title.isEmpty ? (url.host ?? url.absoluteString) : title
		hostLabel.text = url.host
	}

	private func updateNavigationButtons() {
		backButton.isEnabled = webView.canGoBack
		forwardButton.isEnabled = webView.canGoForward
	}

	// MARK: - 按钮

	@objc private func closeTapped() {
		_ = (navigationController as? Babel2NavigationController)?.popBabel2(animated: true)
	}

	@objc private func backTapped() { webView.goBack() }
	@objc private func forwardTapped() { webView.goForward() }

	@objc private func reloadTapped() {
		errorStack.isHidden = true
		if webView.url == nil {
			webView.load(URLRequest(url: initialURL))
		} else {
			webView.reload()
		}
	}

	@objc private func shareTapped(_ sender: UIButton) {
		let activity = UIActivityViewController(activityItems: [webView.url ?? initialURL], applicationActivities: nil)
		activity.popoverPresentationController?.sourceView = sender
		activity.popoverPresentationController?.sourceRect = sender.bounds
		present(activity, animated: true)
	}

	@objc private func safariTapped() { openExternally(webView.url ?? initialURL) }

	// MARK: - WKNavigationDelegate

	func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
		errorStack.isHidden = true
		updateProgress()
	}

	func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
		updateProgress()
		updateTitle()
	}

	func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
		showError(error)
	}

	func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
		showError(error)
	}

	/// 网页里「在新窗口打开」的链接（没有目标框架）：就在当前浏览器里打开。
	/// 用导航决策来处理，而不用「新建窗口」回调——那个回调的参数类型名含边界测试禁用字样（LESSONS 30）。
	func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
		if navigationAction.targetFrame == nil {
			decisionHandler(.cancel)
			webView.load(navigationAction.request)
			return
		}
		decisionHandler(.allow)
	}

	private func showError(_ error: Error) {
		// 用户点了别的链接导致上一次加载被取消，不算失败
		if (error as NSError).code == NSURLErrorCancelled { return }
		updateProgress()
		errorLabel.text = Babel2Localization.text(.unableToLoadPage) + "\n" + error.localizedDescription
		errorStack.isHidden = false
	}

	/// 仅供自动化测试观察。
	var initialURLForTesting: URL { initialURL }
	var isShowingErrorForTesting: Bool { !errorStack.isHidden }
}

extension Babel2BrowserViewController: Babel2PreparableRoute {}
