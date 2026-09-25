import UIKit
import WebKit

/// 阅读页的正文显示面。
///
/// 整个 Babel 2.0 里，只有 `iOS/Babel2/Reader/WebKit/` 这个目录允许使用网页控件
/// （由 Babel2BoundaryTests 强制检查）。阅读页控制器本身不直接碰网页控件，只通过这个类。
///
/// 工作方式：
/// 1. 先加载一个我们自己写的固定外壳页（只有样式和一个空的 `<article>` 容器）；
/// 2. 再把文章原文作为「参数」交给页内脚本，由浏览器自带的解析器排版。
/// Swift 这边从不拼接、不改动文章的 HTML —— 结构完整性由浏览器保证。
///
/// 安全：外壳页的内容安全策略禁止执行任何页面脚本，所以文章里自带的 `<script>`、
/// `onerror=` 之类都不会运行。我们自己的排版脚本跑在隔离的脚本环境里，不受影响。
@MainActor
final class Babel2ReaderContentView: UIView, WKNavigationDelegate {
	enum RenderState: String {
		case idle
		case loadingShell
		case rendering
		case rendered
		case failed
	}

	/// 一次排版的结果：正文字数和图片数。两者都是 0 说明文章没有正文。
	struct RenderResult: Equatable {
		let textLength: Int
		let imageCount: Int

		var isEmpty: Bool { textLength == 0 && imageCount == 0 }
	}

	/// 点击正文里的链接时的去向判断（抽成纯函数，方便自动化测试）。
	enum LinkDecision: Equatable {
		case allow
		case cancel
		case cancelAndOpenExternally(URL)
	}

	private let webView: WKWebView
	var scrollView: UIScrollView { webView.scrollView }
	/// 给翻译桥（同目录的页面宿主扩展）用：翻译引擎要直接对这个网页控件执行脚本。
	var pageWebView: WKWebView { webView }
	/// 用户点了正文里的链接，交给外面决定怎么打开。
	var onLinkActivated: ((URL) -> Void)?
	/// 网页内容进程意外退出（系统内存紧张时会发生），外面应显示错误并允许重试。
	var onContentProcessTerminated: (() -> Void)?
	/// 滚动位置或正文长度变了（图片加载完正文会变长）。阅读页据此更新紧凑标题栏和进度圆环。
	var onScrollGeometryChange: (() -> Void)?
	private(set) var renderState: RenderState = .idle
	/// 正文实际高度（pt）。网页文档至少有一屏高，短文也一样，所以不能用滚动区的内容高度代替；
	/// 这里由页内脚本直接测量正文容器，图片加载后变长会再次上报。nil = 还没测到。
	private(set) var articleHeight: CGFloat?

	private var shellBaseURL: URL?
	private var isShellLoaded = false
	private var shellWaiters = [CheckedContinuation<Bool, Never>]()
	private var scrollObservations = [NSKeyValueObservation]()
	private static let heightMessageName = "babel2ArticleHeight"

	override init(frame: CGRect) {
		webView = WKWebView(frame: .zero)
		super.init(frame: frame)
		webView.navigationDelegate = self
		webView.isOpaque = false
		webView.backgroundColor = BabelPalette.background
		webView.underPageBackgroundColor = BabelPalette.background
		webView.scrollView.backgroundColor = BabelPalette.background
		webView.scrollView.alwaysBounceHorizontal = false
		webView.scrollView.showsHorizontalScrollIndicator = false
		webView.allowsLinkPreview = false
		webView.accessibilityIdentifier = "babel2.article.body"
		webView.translatesAutoresizingMaskIntoConstraints = false
		addSubview(webView)
		NSLayoutConstraint.activate([
			webView.leadingAnchor.constraint(equalTo: leadingAnchor),
			webView.trailingAnchor.constraint(equalTo: trailingAnchor),
			webView.topAnchor.constraint(equalTo: topAnchor),
			webView.bottomAnchor.constraint(equalTo: bottomAnchor)
		])
		// 页内脚本上报正文高度的通道（只在我们自己的隔离脚本环境里可用，文章内容碰不到）
		webView.configuration.userContentController.add(
			Babel2ReaderHeightMessageProxy(owner: self),
			contentWorld: .defaultClient,
			name: Self.heightMessageName
		)
		// 只观察、不接管滚动区的代理（代理归网页控件自己所有）
		let scrollView = webView.scrollView
		scrollObservations = [
			scrollView.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in
				MainActor.assumeIsolated { self?.onScrollGeometryChange?() }
			},
			scrollView.observe(\.contentSize, options: [.new]) { [weak self] _, _ in
				MainActor.assumeIsolated { self?.onScrollGeometryChange?() }
			}
		]
	}

	required init?(coder: NSCoder) { nil }

	/// 把文章原文排进页面。返回 nil 表示失败（外壳页没加载成功或脚本出错）。
	/// - title: 写进隐藏标题元素，只给翻译引擎读写（用户看到的是原生标题）。
	func render(body: String, baseURL: URL?, title: String = "") async -> RenderResult? {
		renderState = .loadingShell
		articleHeight = nil
		guard await loadShellIfNeeded(baseURL: baseURL) else {
			renderState = .failed
			return nil
		}
		renderState = .rendering
		do {
			let raw = try await webView.callAsyncJavaScript(
				Self.renderScript,
				arguments: ["body": body, "title": title],
				in: nil,
				contentWorld: .defaultClient
			)
			guard let values = raw as? [String: Any],
				let textLength = (values["textLength"] as? NSNumber)?.intValue,
				let imageCount = (values["imageCount"] as? NSNumber)?.intValue else {
				renderState = .failed
				return nil
			}
			renderState = .rendered
			if let height = (values["articleHeight"] as? NSNumber)?.doubleValue {
				updateArticleHeight(CGFloat(height))
			}
			return RenderResult(textLength: textLength, imageCount: imageCount)
		} catch {
			renderState = .failed
			return nil
		}
	}

	/// 仅供自动化测试：读出正文容器里的纯文字。
	func articleTextForTesting() async -> String? {
		try? await webView.callAsyncJavaScript(
			"const root = document.getElementById('babel2-article'); return root ? root.innerText.trim() : null;",
			arguments: [:],
			in: nil,
			contentWorld: .defaultClient
		) as? String
	}

	/// 仅供自动化测试：在正文容器里执行一段只读查询脚本。
	func evaluateForTesting(_ functionBody: String) async -> Any? {
		try? await webView.callAsyncJavaScript(functionBody, arguments: [:], in: nil, contentWorld: .defaultClient)
	}

	fileprivate func updateArticleHeight(_ height: CGFloat) {
		guard height.isFinite, height >= 0, height != articleHeight else { return }
		articleHeight = height
		onScrollGeometryChange?()
	}

	// MARK: - 外壳页

	private func loadShellIfNeeded(baseURL: URL?) async -> Bool {
		if isShellLoaded && shellBaseURL == baseURL { return true }
		return await withCheckedContinuation { continuation in
			let isAlreadyLoading = !shellWaiters.isEmpty
			shellWaiters.append(continuation)
			guard !isAlreadyLoading else { return }
			isShellLoaded = false
			shellBaseURL = baseURL
			webView.loadHTMLString(Self.shellHTML(), baseURL: baseURL)
		}
	}

	private func finishShellLoad(success: Bool) {
		isShellLoaded = success
		let waiters = shellWaiters
		shellWaiters.removeAll()
		waiters.forEach { $0.resume(returning: success) }
	}

	// MARK: - WKNavigationDelegate

	func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
		let decision = Self.linkDecision(
			isLinkActivation: navigationAction.navigationType == .linkActivated,
			isMainFrame: navigationAction.targetFrame?.isMainFrame ?? true,
			url: navigationAction.request.url,
			shellIsLoaded: isShellLoaded,
			shellBaseURL: shellBaseURL
		)
		switch decision {
		case .allow:
			decisionHandler(.allow)
		case .cancel:
			decisionHandler(.cancel)
		case .cancelAndOpenExternally(let url):
			decisionHandler(.cancel)
			onLinkActivated?(url)
		}
	}

	func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
		finishShellLoad(success: true)
	}

	func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
		finishShellLoad(success: false)
	}

	func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
		finishShellLoad(success: false)
	}

	func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
		isShellLoaded = false
		renderState = .failed
		finishShellLoad(success: false)
		onContentProcessTerminated?()
	}

	/// 链接去向规则：
	/// - 用户点击的链接：页内锚点（#xxx）照常跳转；其它一律不在正文里打开，交给外面
	/// - 外壳页加载完之后，页面自己发起的主框架跳转（如自动重定向）一律拦下
	/// - 其余（外壳页本身、正文里嵌入的视频框）放行
	static func linkDecision(
		isLinkActivation: Bool,
		isMainFrame: Bool,
		url: URL?,
		shellIsLoaded: Bool,
		shellBaseURL: URL?
	) -> LinkDecision {
		if isLinkActivation {
			guard let url else { return .cancel }
			if url.fragment != nil, isSameDocument(url, shellBaseURL) { return .allow }
			guard let scheme = url.scheme?.lowercased(), ["http", "https", "mailto"].contains(scheme) else { return .cancel }
			return .cancelAndOpenExternally(url)
		}
		if isMainFrame && shellIsLoaded {
			return .cancel
		}
		return .allow
	}

	private static func isSameDocument(_ url: URL, _ base: URL?) -> Bool {
		func stripped(_ url: URL?) -> String? {
			guard let url, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
			components.fragment = nil
			return components.string
		}
		// 没有原文地址时，外壳页的地址是 about:blank
		return stripped(url) == (stripped(base) ?? "about:blank")
	}

	// MARK: - 外壳页内容

	/// 外壳页：样式 + 空容器。配色取自 BabelPalette 的浅色 / 深色两套值，
	/// 由网页按系统外观（跟随 app 当前的浅色/深色）自动切换。
	static func shellHTML() -> String {
		let light = UITraitCollection(userInterfaceStyle: .light)
		let dark = UITraitCollection(userInterfaceStyle: .dark)
		func vars(_ traits: UITraitCollection) -> String {
			"""
			--bg: \(hex(BabelPalette.background, traits));
			--ink: \(hex(BabelPalette.ink, traits));
			--muted: \(hex(BabelPalette.mutedInk, traits));
			--tertiary: \(hex(BabelPalette.tertiaryInk, traits));
			--hairline: \(hex(BabelPalette.hairline, traits));
			--raised: \(hex(BabelPalette.raisedBackground, traits));
			"""
		}
		return """
		<!doctype html>
		<html>
		<head>
		<meta charset="utf-8">
		<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
		<meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src * data: blob:; media-src * data: blob:; frame-src *; style-src 'unsafe-inline'; font-src * data:">
		<style>
		:root { color-scheme: light dark; \(vars(light)) }
		@media (prefers-color-scheme: dark) { :root { \(vars(dark)) } }
		\(css)
		</style>
		</head>
		<body><h1 class="articleTitle" id="babel2-title" hidden></h1><article id="babel2-article"></article></body>
		</html>
		"""
	}

	/// 排版数值来自 Figma Drafts/BATCH-01-SPEC.md「04 · Reader」：
	/// 左右边距约 20pt，正文约 19pt、行高约 30pt；链接加粗 + 中性下划线（不用绿色）；
	/// 横图（脚本判定后加 babel2-bleed）贴满屏幕两边、直角；文字和图注保留边距。
	private static let css = """
	html { -webkit-text-size-adjust: 100%; background: var(--bg); }
	html, body { margin: 0; padding: 0; overflow-x: hidden; }
	body { background: var(--bg); color: var(--ink); font: 19px/30px -apple-system, system-ui, sans-serif; overflow-wrap: break-word; }
	#babel2-title { display: none; }
	#babel2-article { padding: 0 20px 48px; }
	#babel2-article > :first-child { margin-top: 0; }
	p { margin: 0 0 18px; }
	h1, h2, h3, h4, h5, h6 { font-weight: 700; line-height: 1.3; margin: 28px 0 12px; }
	h1 { font-size: 23px; } h2 { font-size: 21px; } h3 { font-size: 20px; } h4, h5, h6 { font-size: 19px; }
	a { color: var(--ink); font-weight: 600; text-decoration: underline; text-decoration-color: var(--tertiary); text-decoration-thickness: 1px; text-underline-offset: 3px; }
	img, video { display: block; max-width: 100%; height: auto; margin: 22px auto; border-radius: 0; }
	img.babel2-bleed { width: 100vw; max-width: 100vw; margin-left: calc(50% - 50vw); margin-right: calc(50% - 50vw); }
	img.babel2-hidden { display: none; }
	figure { margin: 22px 0; }
	figure img, figure video { margin-top: 0; margin-bottom: 0; }
	figcaption { font-size: 14px; line-height: 20px; color: var(--muted); margin-top: 8px; }
	blockquote { margin: 0 0 18px; padding-left: 16px; border-left: 3px solid var(--hairline); color: var(--muted); }
	pre { overflow-x: auto; font: 14px/20px ui-monospace, Menlo, monospace; background: var(--raised); padding: 12px; margin: 0 0 18px; }
	code { font-family: ui-monospace, Menlo, monospace; font-size: 0.85em; }
	ul, ol { padding-left: 24px; margin: 0 0 18px; }
	li { margin-bottom: 6px; }
	hr { border: 0; border-top: 1px solid var(--hairline); margin: 28px 0; }
	table { display: block; overflow-x: auto; border-collapse: collapse; font-size: 15px; line-height: 22px; margin: 0 0 18px; }
	td, th { border: 1px solid var(--hairline); padding: 6px 8px; }
	iframe { display: block; width: 100%; aspect-ratio: 16 / 9; height: auto; border: 0; margin: 22px 0; }
	"""

	/// 页内排版脚本（在隔离环境里运行，参数 body 是文章原文）。
	/// 做的事：用浏览器解析原文 → 去掉脚本、样式、表单和所有 on* 事件属性 →
	/// 补上懒加载图片的真实地址 → 放进容器 → 图片加载后按宽高比决定是否贴边。
	private static let renderScript = """
	const root = document.getElementById('babel2-article');
	if (!root) { return null; }
	// 隐藏标题：翻译引擎按 .articleTitle 找标题读写，避免误改正文里的 h1
	const titleElement = document.getElementById('babel2-title');
	if (titleElement) { titleElement.textContent = title; }
	const parsed = new DOMParser().parseFromString('<!doctype html><body></body>', 'text/html');
	const looksLikeHTML = /<[a-zA-Z!\\/]/.test(body);
	if (looksLikeHTML) {
		parsed.body.innerHTML = body;
	} else {
		for (const chunk of body.split(/\\n\\s*\\n/)) {
			const text = chunk.trim();
			if (!text) { continue; }
			const p = parsed.createElement('p');
			p.textContent = text;
			parsed.body.appendChild(p);
		}
	}
	parsed.body.querySelectorAll('script, noscript, style, link, meta, base, object, embed, form, input, button, textarea, select, template').forEach(node => node.remove());
	parsed.body.querySelectorAll('*').forEach(element => {
		for (const attribute of Array.from(element.attributes)) {
			const name = attribute.name.toLowerCase();
			if (name.startsWith('on') || name === 'style' || name === 'class') {
				element.removeAttribute(attribute.name);
			}
		}
		for (const name of ['href', 'src']) {
			const value = element.getAttribute(name);
			if (value && /^\\s*javascript:/i.test(value)) { element.removeAttribute(name); }
		}
	});
	parsed.body.querySelectorAll('img').forEach(img => {
		const lazy = img.getAttribute('data-src') || img.getAttribute('data-original') || img.getAttribute('data-lazy-src');
		if (lazy && (!img.getAttribute('src') || img.getAttribute('src').startsWith('data:'))) { img.setAttribute('src', lazy); }
		const lazySet = img.getAttribute('data-srcset');
		if (lazySet && !img.getAttribute('srcset')) { img.setAttribute('srcset', lazySet); }
	});
	root.replaceChildren(...Array.from(parsed.body.childNodes).map(node => document.importNode(node, true)));
	const classify = img => {
		const width = img.naturalWidth;
		const height = img.naturalHeight;
		if (width <= 2 && height <= 2) { img.classList.add('babel2-hidden'); return; }
		if (width >= 320 && width > height * 1.1) { img.classList.add('babel2-bleed'); }
	};
	const images = Array.from(root.querySelectorAll('img'));
	images.forEach(img => {
		if (img.complete && img.naturalWidth > 0) {
			classify(img);
		} else {
			img.addEventListener('load', () => classify(img), { once: true });
		}
	});
	// 正文高度：先量一次随结果返回；之后正文尺寸变化（图片加载、旋转）时再上报
	const measure = () => Math.ceil(root.getBoundingClientRect().bottom + window.scrollY);
	if (window.babel2HeightObserver) { window.babel2HeightObserver.disconnect(); }
	window.babel2HeightObserver = new ResizeObserver(() => {
		window.webkit.messageHandlers.babel2ArticleHeight.postMessage(measure());
	});
	window.babel2HeightObserver.observe(root);
	return { textLength: root.innerText.trim().length, imageCount: images.length, articleHeight: measure() };
	"""

	private static func hex(_ color: UIColor, _ traits: UITraitCollection) -> String {
		var red: CGFloat = 0
		var green: CGFloat = 0
		var blue: CGFloat = 0
		var alpha: CGFloat = 0
		color.resolvedColor(with: traits).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
		func byte(_ value: CGFloat) -> Int { Int((min(max(value, 0), 1) * 255).rounded()) }
		if alpha < 1 {
			return String(format: "rgba(%d, %d, %d, %.2f)", byte(red), byte(green), byte(blue), alpha)
		}
		return String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
	}
}

/// 转发页内上报的正文高度。单独一个弱引用小对象，避免网页控件和显示面互相强引用导致内存泄漏。
@MainActor
private final class Babel2ReaderHeightMessageProxy: NSObject, WKScriptMessageHandler {
	private weak var owner: Babel2ReaderContentView?

	init(owner: Babel2ReaderContentView) {
		self.owner = owner
	}

	func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
		guard let height = (message.body as? NSNumber)?.doubleValue else { return }
		owner?.updateArticleHeight(CGFloat(height))
	}
}
