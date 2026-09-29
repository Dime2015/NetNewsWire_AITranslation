import UIKit
import WebKit
import CryptoKit

/// Babel 2.0 内置浏览器（Slice 5 第 3 步，ADR-021）。
///
/// 设计稿没有浏览器画面，版式沿用阅读页（用户 2026-09-25 同意）：
/// - 顶栏 58pt：左 ✕ 回到文章（x=32，中心 y=22）；中间两行 = 网页标题（14pt 半粗，ADR-033）+ 域名（11pt 浅灰）
/// - 顶栏下方 2pt 中性灰加载进度线；加载失败显示原因 + 重试
/// - 底栏 72pt（0.5pt 分隔线），五格与阅读页同位置：后退 / 前进 / 刷新 / 分享 / 在 Safari 中打开
/// - 回到文章：左边缘右滑（沿用统一的返回手势）或点 ✕
/// - 右上角「•••」（ADR-047）：翻译此页（把正文抽出来开一个阅读页并自动翻译）/ 去广告（默认开，可对当前页面临时关掉）
///
/// 这是真正的网页，所以用独立的网页控件、不加阅读页那套「禁止页面脚本」的安全策略；
/// 浏览器自己的前进后退历史只留在这里，不影响阅读页。
/// 放在网页控件专用目录（边界测试规定只有这里能出现网页控件）。
@MainActor
/// 只认左边缘返回（ADR-042）：网页里常有左右滑的轮播图、地图，整页右滑会抢它们的手势。
final class Babel2BrowserViewController: UIViewController, WKNavigationDelegate, Babel2EdgeOnlyBackGesture {
	/// 「翻译此页」抽出来的正文（ADR-047）。
	struct PageContent: Equatable {
		let url: URL
		let title: String
		/// Readability 抽出的正文 HTML（网页里的脚本产出，Swift 不解析、不改动）
		let html: String
		let byline: String?

		/// 这个网址固定对应一个编号：同一页再翻译时直接用上次的译文缓存。
		var articleID: String {
			"web-" + SHA256.hash(data: Data(url.absoluteString.utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
		}
	}

	private let initialURL: URL
	private let openExternally: (URL) -> Void
	/// 装配层接走抽出来的正文、打开阅读页（没有注入时菜单里不出现「翻译此页」）。
	private let onTranslatePage: ((PageContent) -> Void)?
	/// 去广告：默认开；「•••」里可以对当前页面临时关掉（不记住）。
	private(set) var isAdBlockOn = true
	private var adBlockList: WKContentRuleList?
	private let moreButton = UIButton(type: .system)
	private let extractingIndicator = UIActivityIndicatorView(style: .medium)
	private var extractTask: Task<Void, Never>?
	private var initialLoadTask: Task<Void, Never>?
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

	init(url: URL, openExternally: @escaping (URL) -> Void, onTranslatePage: ((PageContent) -> Void)? = nil) {
		initialURL = url
		self.openExternally = openExternally
		self.onTranslatePage = onTranslatePage
		super.init(nibName: nil, bundle: nil)
		restorationIdentifier = "babel2.browser"
	}

	deinit {
		extractTask?.cancel()
		initialLoadTask?.cancel()
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

	/// 先装好去广告规则再开始加载（规则每次启动只编译一次，之后是现成的，几乎不耽误）；编译失败就照常打开。
	private func startLoadingIfNeeded() {
		guard isViewLoaded, !didStartLoading else { return }
		didStartLoading = true
		initialLoadTask = Task { @MainActor [weak self] in
			let list = await Babel2AdBlocker.ruleList()
			guard let self, !Task.isCancelled else { return }
			self.adBlockList = list
			if self.isAdBlockOn, let list {
				self.webView.configuration.userContentController.add(list)
			}
			self.webView.load(URLRequest(url: self.initialURL))
		}
	}

	/// 手势取消时丢弃：停止加载，不留网络请求。
	func discard() {
		initialLoadTask?.cancel()
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
		close.setImage(Babel2Icon.close.image(size: Babel2Icon.Size.top), for: .normal)
		close.tintColor = Babel2Icon.tint
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
		configureMoreButton(in: bar, alignedWith: close)
		return bar
	}

	/// 右上角「•••」：与阅读页顶栏同一个图标，位置与 ✕ 左右对称（x = 屏宽 − 32）。抽正文期间换成小转圈。
	private func configureMoreButton(in bar: UIView, alignedWith close: UIView) {
		moreButton.setImage(Babel2Icon.more.image(size: Babel2Icon.Size.top), for: .normal)
		moreButton.tintColor = Babel2Icon.tint
		moreButton.accessibilityLabel = Babel2Localization.text(.more)
		moreButton.accessibilityIdentifier = "babel2.browser.more"
		moreButton.addTarget(self, action: #selector(moreTapped), for: .touchUpInside)
		moreButton.translatesAutoresizingMaskIntoConstraints = false
		Babel2Motion.addPressFeedback(to: moreButton)
		bar.addSubview(moreButton)
		extractingIndicator.color = BabelPalette.mutedInk
		extractingIndicator.hidesWhenStopped = true
		extractingIndicator.translatesAutoresizingMaskIntoConstraints = false
		bar.addSubview(extractingIndicator)
		NSLayoutConstraint.activate([
			moreButton.centerXAnchor.constraint(equalTo: bar.trailingAnchor, constant: -32),
			moreButton.centerYAnchor.constraint(equalTo: close.centerYAnchor),
			moreButton.widthAnchor.constraint(equalToConstant: 44),
			moreButton.heightAnchor.constraint(equalToConstant: 44),
			extractingIndicator.centerXAnchor.constraint(equalTo: moreButton.centerXAnchor),
			extractingIndicator.centerYAnchor.constraint(equalTo: moreButton.centerYAnchor)
		])
	}

	// MARK: - 「•••」：翻译此页 / 去广告（ADR-047）

	@objc private func moreTapped() {
		Babel2GlassMenu.present(sections: makeMoreMenuSections(), from: moreButton, in: view)
	}

	func makeMoreMenuSections() -> [[Babel2MenuItem]] {
		var translate = [Babel2MenuItem]()
		if onTranslatePage != nil {
			translate.append(Babel2MenuItem(title: Babel2Localization.text(.translatePage), image: Babel2Icon.translate.image(size: Babel2Icon.Size.menu),
				identifier: "babel2.browser.translate-page", isEnabled: extractTask == nil && webView.url != nil) { [weak self] in
				self?.translatePage()
			})
		}
		let adBlock = [Babel2MenuItem(title: Babel2Localization.text(.blockAds), image: Babel2Icon.shield.image(size: Babel2Icon.Size.menu),
			identifier: "babel2.browser.adblock", isOn: isAdBlockOn, isEnabled: adBlockList != nil) { [weak self] in
			self?.setAdBlock(!(self?.isAdBlockOn ?? true))
		}]
		return [translate, adBlock]
	}

	/// 临时开关去广告：换上 / 拿掉规则后重新载入当前页面。
	func setAdBlock(_ on: Bool) {
		guard on != isAdBlockOn else { return }
		isAdBlockOn = on
		let controller = webView.configuration.userContentController
		if on, let adBlockList {
			controller.add(adBlockList)
		} else {
			controller.removeAllContentRuleLists()
		}
		if webView.url != nil {
			webView.reload()
		}
	}

	/// 「翻译此页」：在当前网页里用 Readability（与阅读模式同一个库）把正文抽出来，交给装配层开阅读页并自动翻译。
	/// 在隔离的脚本环境里跑（不碰网页自己的脚本、也不被它干扰）；抽不出正文（首页、列表页、登录页）时说明原因。
	private func translatePage() {
		guard extractTask == nil, let onTranslatePage else { return }
		moreButton.isHidden = true
		extractingIndicator.startAnimating()
		extractTask = Task { @MainActor [weak self] in
			let page = await self?.extractPage()
			guard let self else { return }
			self.extractTask = nil
			self.extractingIndicator.stopAnimating()
			self.moreButton.isHidden = false
			guard !Task.isCancelled else { return }
			if let page {
				onTranslatePage(page)
			} else {
				let alert = UIAlertController(title: nil, message: Babel2Localization.text(.unableToExtractPage), preferredStyle: .alert)
				alert.addAction(UIAlertAction(title: Babel2Localization.text(.ok), style: .default))
				self.present(alert, animated: true)
			}
		}
	}

	/// 抽正文：Readability.js（打进 app 包里的那一份）和解析脚本放在同一段里执行，结果是 JSON 字符串。
	func extractPage() async -> PageContent? {
		guard let url = webView.url, let library = Self.readabilitySource else { return nil }
		let raw = try? await webView.callAsyncJavaScript(library + "\n" + Self.parseScript, arguments: [:], in: nil, contentWorld: .defaultClient)
		guard let json = raw as? String, let data = json.data(using: .utf8),
			let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
			let html = object["content"] as? String, !html.isEmpty else { return nil }
		let extractedTitle = (object["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
		let pageTitle = webView.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
		let title = !extractedTitle.isEmpty ? extractedTitle : (!pageTitle.isEmpty ? pageTitle : (url.host ?? url.absoluteString))
		let byline = (object["byline"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
		return PageContent(url: url, title: title, html: html, byline: byline?.isEmpty == false ? byline : nil)
	}

	/// 打进 app 包里的 Readability.js（Mozilla，与阅读模式同一份，不改动）。只读一次。
	private static let readabilitySource: String? = {
		guard let url = Bundle.main.url(forResource: "Readability", withExtension: "js") else { return nil }
		return try? String(contentsOf: url, encoding: .utf8)
	}()

	/// 在当前网页上抽正文（做法与阅读模式的提取器一致）：先把用户本来就看不见的元素（被隐藏的浮层、
	/// aria-hidden）从副本里去掉，懒加载图归位，再交给 Readability；Readability 会改动传进去的文档，所以只给副本。
	/// 真实页面上只临时打一个标记、用完就撤，网页本身不受影响。
	/// 抽出来的字不到 80 个、或六成以上的字都在链接里（首页、列表页），当作「没有正文」。
	static let parseScript = """
	try {
		if (typeof Readability !== "function") { return null; }
		var marked = [];
		var all = document.body ? document.body.querySelectorAll("*") : [];
		for (var h = 0; h < all.length; h++) {
			var node = all[h];
			var hidden = node.getAttribute("aria-hidden") === "true";
			if (!hidden) {
				var style = window.getComputedStyle(node);
				hidden = style && (style.display === "none" || style.visibility === "hidden");
			}
			if (hidden) { node.setAttribute("data-babel2-hidden", "1"); marked.push(node); }
		}
		var work = document.cloneNode(true);
		for (var c = 0; c < marked.length; c++) { marked[c].removeAttribute("data-babel2-hidden"); }
		var doomed = work.querySelectorAll("[data-babel2-hidden]");
		for (var r = doomed.length - 1; r >= 0; r--) {
			if (doomed[r].parentNode) { doomed[r].parentNode.removeChild(doomed[r]); }
		}
		var lazyAttributes = ["data-src", "data-original", "data-lazy-src", "data-actualsrc"];
		var images = work.querySelectorAll("img");
		for (var i = 0; i < images.length; i++) {
			for (var a = 0; a < lazyAttributes.length; a++) {
				var real = images[i].getAttribute(lazyAttributes[a]);
				if (real && real !== images[i].getAttribute("src")) { images[i].setAttribute("src", real); break; }
			}
			var realSet = images[i].getAttribute("data-srcset");
			if (realSet) { images[i].setAttribute("srcset", realSet); }
		}
		var article = new Readability(work).parse();
		if (!article || !article.content) { return null; }
		// Readability 在没有正文的页面（首页、列表页）上也会交回一堆链接：字太少、或大部分字都在链接里，就算没有正文
		var text = (article.textContent || "").replace(/\\s+/g, " ").trim();
		var parsed = new DOMParser().parseFromString(article.content, "text/html");
		var linkText = 0;
		var links = parsed.querySelectorAll("a");
		for (var l = 0; l < links.length; l++) { linkText += (links[l].textContent || "").replace(/\\s+/g, " ").trim().length; }
		if (text.length < 80 || linkText > text.length * 0.6) { return null; }
		return JSON.stringify({ title: article.title || "", content: article.content, byline: article.byline || null });
	} catch (e) {
		return null;
	}
	"""

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

		let items: [(UIButton, Babel2Icon, Babel2LocalizationKey, String, Selector)] = [
			(backButton, .back, .browserBack, "babel2.browser.back", #selector(backTapped)),
			(forwardButton, .forward, .browserForward, "babel2.browser.forward", #selector(forwardTapped)),
			(reloadButton, .refresh, .browserReload, "babel2.browser.reload", #selector(reloadTapped)),
			(shareButton, .share, .share, "babel2.browser.share", #selector(shareTapped)),
			(safariButton, .browser, .openInSafari, "babel2.browser.safari", #selector(safariTapped))
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
		for ((button, icon, key, identifier, action), center) in zip(items, centers) {
			// 统一图标集（ADR-065），与阅读页底栏同样 21pt、同一图标色
			button.setImage(icon.image(size: Babel2Icon.Size.bar), for: .normal)
			button.tintColor = Babel2Icon.tint
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
	var isAdBlockReadyForTesting: Bool { adBlockList != nil }
	/// 仅供自动化测试：直接给网页控件一段 HTML（当作来自 baseURL 的页面）。
	func loadHTMLForTesting(_ html: String, baseURL: URL) {
		loadViewIfNeeded()
		initialLoadTask?.cancel()
		webView.loadHTMLString(html, baseURL: baseURL)
	}
	var isPageLoadingForTesting: Bool { webView.isLoading }
	/// 仅供自动化测试：走「翻译此页」同一条路径。
	func translatePageForTesting() { translatePage() }
	var isExtractingForTesting: Bool { extractTask != nil }
}

extension Babel2BrowserViewController: Babel2PreparableRoute {}
