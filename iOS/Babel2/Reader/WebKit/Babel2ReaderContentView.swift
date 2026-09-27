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

	/// 一次排版的结果：正文字数、图片数、播放器 / 视频 / 音频数。全是 0 说明文章没有正文。
	struct RenderResult: Equatable {
		let textLength: Int
		let imageCount: Int
		/// 正文上方的播放器、正文里的视频框 / 视频 / 音频（ADR-041）
		var mediaCount: Int = 0

		var isEmpty: Bool { textLength == 0 && imageCount == 0 && mediaCount == 0 }
	}

	/// 点了正文里的一张图（ADR-040）：图片地址、外面包着的链接、图在本视图里的位置、替代文字。
	struct ImageTap: Equatable {
		let imageURL: URL?
		let linkURL: URL?
		let frame: CGRect
		let altText: String
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
	/// 用户点了正文里的图片（ADR-040）。图片外面即使包着链接，也只走这里、不再打开链接。
	var onImageTapped: ((ImageTap) -> Void)?
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
	private static let imageTapMessageName = "babel2ImageTapped"

	override init(frame: CGRect) {
		// 视频在文章里原地播放（ADR-041，用户 2026-09-27 同意为此给边界测试加精确例外）：
		// 这两项只能在创建网页控件时给定，之后改不了。自动播放一律关掉，要用户自己点。
		let configuration = WKWebViewConfiguration()
		configuration.allowsInlineMediaPlayback = true
		configuration.mediaTypesRequiringUserActionForPlayback = .all
		webView = WKWebView(frame: .zero, configuration: configuration)
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
		let messageProxy = Babel2ReaderMessageProxy(owner: self)
		for name in [Self.heightMessageName, Self.imageTapMessageName] {
			webView.configuration.userContentController.add(messageProxy, contentWorld: .defaultClient, name: name)
		}
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
	/// - youTubeVideoID: 非 nil 时在正文上方放 YouTube 播放器（ADR-041）。
	func render(body: String, baseURL: URL?, title: String = "", youTubeVideoID: String? = nil) async -> RenderResult? {
		renderState = .loadingShell
		articleHeight = nil
		guard await loadShellIfNeeded(baseURL: baseURL) else {
			renderState = .failed
			return nil
		}
		renderState = .rendering
		// 排版前后各清一次翻译引擎留在网页里的记忆（见 discardTranslationScriptState）
		await discardTranslationScriptState()
		do {
			let raw = try await webView.callAsyncJavaScript(
				Self.renderScript,
				arguments: ["body": body, "title": title, "youTube": youTubeVideoID ?? ""],
				in: nil,
				contentWorld: .defaultClient
			)
			guard let values = raw as? [String: Any],
				let textLength = (values["textLength"] as? NSNumber)?.intValue,
				let imageCount = (values["imageCount"] as? NSNumber)?.intValue else {
				renderState = .failed
				return nil
			}
			let mediaCount = (values["mediaCount"] as? NSNumber)?.intValue ?? 0
			await discardTranslationScriptState()
			renderState = .rendered
			if let height = (values["articleHeight"] as? NSNumber)?.doubleValue {
				updateArticleHeight(CGFloat(height))
			}
			return RenderResult(textLength: textLength, imageCount: imageCount, mediaCount: mediaCount)
		} catch {
			renderState = .failed
			return nil
		}
	}

	/// 正文是空的时候填一段纯文本（YouTube 视频简介，ADR-041）：按空行分段、段内保留换行，
	/// 网址变成可点的链接；全部由页内脚本用 textContent 写入，不拼接 HTML。正文不空时什么都不做。
	/// 返回填完后的排版结果（没填返回 nil）。
	func fillEmptyBody(withPlainText text: String) async -> RenderResult? {
		guard renderState == .rendered else { return nil }
		let raw = try? await webView.callAsyncJavaScript(
			Self.fillPlainTextScript,
			arguments: ["text": text],
			in: nil,
			contentWorld: .defaultClient
		)
		guard let values = raw as? [String: Any],
			let textLength = (values["textLength"] as? NSNumber)?.intValue,
			let imageCount = (values["imageCount"] as? NSNumber)?.intValue else { return nil }
		let mediaCount = (values["mediaCount"] as? NSNumber)?.intValue ?? 0
		return RenderResult(textLength: textLength, imageCount: imageCount, mediaCount: mediaCount)
	}

	/// 在正文上方放一个居中的音频条（播客单集，ADR-041）。已经有播放器时不重复放。
	@discardableResult
	func installAudioPlayer(url: URL) async -> Bool {
		guard renderState == .rendered, ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return false }
		let raw = try? await webView.callAsyncJavaScript(
			Self.installAudioScript,
			arguments: ["src": url.absoluteString],
			in: nil,
			contentWorld: .defaultClient
		)
		return (raw as? Bool) ?? false
	}

	/// 翻译引擎的页内脚本（translation.js，跑在网页自己的脚本环境里）会记住「原文备份 / 是否正在显示译文 /
	/// 分组」。它原本假设「换正文 = 整页重新加载」，而本页切阅读模式、重试都是在**同一个网页里重排**，
	/// 那些记忆就过期了——2026-09-27 实测：切到全文后点「原文」跳回摘要，点「翻译」直接变回英文（ADR-037）。
	/// 所以每次排版都把它清掉（排版前清一次；排版后再清一次，防止排版期间被取消的翻译流程又把旧状态写回来）。
	/// 下次翻译时引擎会重新注入一份全新的。
	private func discardTranslationScriptState() async {
		_ = try? await webView.evaluateJavaScript(
			"if (window.nnwTranslation && window.nnwTranslation.dispose) { window.nnwTranslation.dispose(); } else { delete window.nnwTranslation; } true;"
		)
	}

	// MARK: - 长图用的临时标题区（ADR-025）

	/// 长图导出只截网页；阅读页的日期/标题/署名是原生控件、不在网页里。
	/// 生成长图前临时在正文上方放一份同样样式的标题区（纯文本写入，不拼接 HTML），截完移除。
	func insertSnapshotHeader(date: String?, title: String, byline: String?) async {
		_ = try? await webView.callAsyncJavaScript(
			"""
			const old = document.getElementById('babel2-snapshot-header');
			if (old) { old.remove(); }
			const root = document.getElementById('babel2-article');
			if (!root) { return false; }
			const header = document.createElement('header');
			header.id = 'babel2-snapshot-header';
			const add = (className, text) => {
				if (!text) { return; }
				const p = document.createElement('p');
				p.className = className;
				p.textContent = text;
				header.appendChild(p);
			};
			add('babel2-snap-date', date);
			add('babel2-snap-title', title);
			add('babel2-snap-byline', byline);
			root.parentNode.insertBefore(header, root);
			// 同一瞬间往下滚同样高度：屏幕上看到的内容不动，用户看不到页面跳动
			window.scrollBy(0, header.getBoundingClientRect().height);
			return true;
			""",
			arguments: ["date": date ?? "", "title": title, "byline": byline ?? ""],
			in: nil,
			contentWorld: .defaultClient
		)
	}

	func removeSnapshotHeader() async {
		_ = try? await webView.callAsyncJavaScript(
			"const h = document.getElementById('babel2-snapshot-header'); if (h) { const height = h.getBoundingClientRect().height; h.remove(); window.scrollBy(0, -height); } return true;",
			arguments: [:],
			in: nil,
			contentWorld: .defaultClient
		)
	}

	/// 仅供自动化测试：读出正文容器里的纯文字。
	// MARK: - 读到哪（ADR-053）

	/// 某个正文坐标 y（可视区顶边）落在正文第几段、在那一段的什么比例处，以及在整篇正文里的进度。
	/// 段落 = 正文容器的直接子元素（译文与原文一一对应）；不占高度的元素跳过。排版没完成时为 nil。
	func readingAnchor(atContentY y: CGFloat) async -> (block: Int, blockCount: Int, fraction: Double, progress: Double)? {
		guard renderState == .rendered else { return nil }
		let raw = try? await webView.callAsyncJavaScript("""
			const root = document.getElementById('babel2-article');
			if (!root) { return null; }
			const box = root.getBoundingClientRect();
			const rootTop = box.top + window.scrollY;
			const rootBottom = box.bottom + window.scrollY;
			const progress = rootBottom > rootTop ? Math.min(Math.max((y - rootTop) / (rootBottom - rootTop), 0), 1) : 0;
			const blocks = root.children;
			for (let i = 0; i < blocks.length; i++) {
				const r = blocks[i].getBoundingClientRect();
				if (r.height <= 0) { continue; }
				const top = r.top + window.scrollY;
				if (top + r.height > y) {
					return { block: i, count: blocks.length, fraction: Math.min(Math.max((y - top) / r.height, 0), 1), progress: progress };
				}
			}
			return { block: Math.max(blocks.length - 1, 0), count: blocks.length, fraction: 1, progress: progress };
			""", arguments: ["y": Double(y)], in: nil, contentWorld: .defaultClient)
		guard let dictionary = raw as? [String: Any],
			let block = (dictionary["block"] as? NSNumber)?.intValue,
			let count = (dictionary["count"] as? NSNumber)?.intValue,
			let fraction = (dictionary["fraction"] as? NSNumber)?.doubleValue,
			let progress = (dictionary["progress"] as? NSNumber)?.doubleValue else { return nil }
		return (block, count, fraction, progress)
	}

	/// 记下的位置现在在正文里的 y：段数没变就按「第几段 + 段内比例」，段数对不上就按整体进度。
	func contentY(block: Int, blockCount: Int, fraction: Double, progress: Double) async -> CGFloat? {
		guard renderState == .rendered else { return nil }
		let raw = try? await webView.callAsyncJavaScript("""
			const root = document.getElementById('babel2-article');
			if (!root) { return null; }
			const blocks = root.children;
			if (blocks.length === count && block < blocks.length) {
				const r = blocks[block].getBoundingClientRect();
				if (r.height > 0) { return r.top + window.scrollY + fraction * r.height; }
			}
			const box = root.getBoundingClientRect();
			return box.top + window.scrollY + progress * box.height;
			""", arguments: ["block": block, "count": blockCount, "fraction": fraction, "progress": progress], in: nil, contentWorld: .defaultClient)
		return (raw as? NSNumber).map { CGFloat($0.doubleValue) }
	}

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

	/// 页内脚本报来的是图片在文档里的位置（CSS 像素 = 点）；换算成本视图里的位置：
	/// 文档坐标原点就是滚动区内容的原点（标题区挂在负坐标里），所以减去当前滚动偏移即可。
	fileprivate func handleImageTap(_ body: [String: Any]) {
		func number(_ key: String) -> CGFloat { CGFloat((body[key] as? NSNumber)?.doubleValue ?? 0) }
		let offset = webView.scrollView.contentOffset
		let frameInWebView = CGRect(x: number("docX") - offset.x, y: number("docY") - offset.y, width: number("width"), height: number("height"))
		let tap = ImageTap(
			imageURL: (body["src"] as? String).flatMap { URL(string: $0) },
			linkURL: (body["link"] as? String).flatMap { $0.isEmpty ? nil : URL(string: $0) },
			frame: webView.convert(frameInWebView, to: self),
			altText: body["alt"] as? String ?? ""
		)
		onImageTapped?(tap)
	}

	/// 截下本视图里一块区域的画面（查看器放大动画的起始画面，大图下载完之前先顶上）。
	func snapshotImage(in rect: CGRect) async -> UIImage? {
		let rectInWebView = convert(rect, to: webView).intersection(webView.bounds)
		guard !rectInWebView.isNull, rectInWebView.width >= 1, rectInWebView.height >= 1 else { return nil }
		let configuration = WKSnapshotConfiguration()
		configuration.rect = rectInWebView
		return try? await webView.takeSnapshot(configuration: configuration)
	}

	/// 仅供自动化测试：模拟点一下正文里的第 index 张图。
	func tapImageForTesting(at index: Int) async {
		_ = try? await webView.callAsyncJavaScript(
			"const img = document.querySelectorAll('#babel2-article img')[index]; if (img) { img.click(); } return true;",
			arguments: ["index": index], in: nil, contentWorld: .defaultClient)
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

	/// 正文字色（2026-09-27 用户反馈：深色模式晚上、亮度不高时正文看不清）。
	/// 原先正文用 BabelPalette.mutedInk：深色 #6C6C6C 在 #1C1C1C 底上对比度只有约 3.2:1，
	/// 还比日期、作者这类次要文字（#8E8E8E）更暗。改为专用的正文色，只影响阅读页正文，App 其它地方的灰不动：
	/// 深色 #B4B4B4（约 8:1，不用纯白——暗光下纯白字会刺眼发散）；浅色按用户要求顺带加深，#787878 → #626262（约 3.9:1 → 5.5:1）。
	static let bodyInk = UIColor { traits in
		traits.userInterfaceStyle == .dark
			? UIColor(red: 180.0 / 255.0, green: 180.0 / 255.0, blue: 180.0 / 255.0, alpha: 1)
			: UIColor(red: 98.0 / 255.0, green: 98.0 / 255.0, blue: 98.0 / 255.0, alpha: 1)
	}

	/// 图注字色：比正文淡一级。浅色沿用设计稿次要灰 #787878；深色用 #8E8E8E（原先的 #6C6C6C 同样看不清）。
	static let captionInk = UIColor { traits in
		traits.userInterfaceStyle == .dark
			? UIColor(red: 142.0 / 255.0, green: 142.0 / 255.0, blue: 142.0 / 255.0, alpha: 1)
			: UIColor(red: 120.0 / 255.0, green: 120.0 / 255.0, blue: 120.0 / 255.0, alpha: 1)
	}

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
			--body: \(hex(bodyInk, traits));
			--caption: \(hex(captionInk, traits));
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

	/// 排版数值按 Figma 04A「Article Content」(ADR-018)，ADR-033 整体收小一档：左右边距 20pt，
	/// 正文 17pt / 行高 28pt（原 19 / 30）、正文色见 bodyInk（原设计稿次要灰 #787878，2026-09-27 加深）；段距 18pt；小标题 20 / 18 / 17；引用块竖线 2pt（距正文左缘 8pt）、文字距竖线 18pt、引用内段距 8pt；
	/// 小标题与链接用主墨色；链接加粗 + 中性下划线（不用绿色）；
	/// 横图（脚本判定后加 babel2-bleed）贴满屏幕两边、直角；文字和图注保留边距。
	private static let css = """
	html { -webkit-text-size-adjust: 100%; background: var(--bg); }
	html, body { margin: 0; padding: 0; overflow-x: hidden; }
	body { background: var(--bg); color: var(--body); font: 17px/28px -apple-system, system-ui, sans-serif; overflow-wrap: break-word; }
	#babel2-title { display: none; }
	#babel2-snapshot-header { padding: 26px 20px 60px; }
	#babel2-snapshot-header .babel2-snap-date { font: 600 11px/15px -apple-system, system-ui, sans-serif; letter-spacing: 0.3px; color: var(--tertiary); margin: 0 0 13px; }
	#babel2-snapshot-header .babel2-snap-title { font: 600 27px/33px -apple-system, system-ui, sans-serif; letter-spacing: -0.4px; color: var(--ink); margin: 0 0 9px; }
	#babel2-snapshot-header .babel2-snap-byline { font: 600 11px/15px -apple-system, system-ui, sans-serif; letter-spacing: 0.25px; color: var(--tertiary); margin: 0; white-space: pre-line; }
	#babel2-article { padding: 0 20px 48px; }
	#babel2-article > :first-child { margin-top: 0; }
	p { margin: 0 0 18px; }
	h1, h2, h3, h4, h5, h6 { color: var(--ink); font-weight: 700; line-height: 1.3; margin: 28px 0 12px; }
	h1 { font-size: 20px; } h2 { font-size: 18px; } h3 { font-size: 17px; } h4, h5, h6 { font-size: 17px; }
	a { color: var(--ink); font-weight: 600; text-decoration: underline; text-decoration-color: var(--tertiary); text-decoration-thickness: 1px; text-underline-offset: 3px; }
	img, video { display: block; max-width: 100%; height: auto; margin: 22px auto; border-radius: 0; }
	img.babel2-bleed { width: 100vw; max-width: 100vw; margin-left: calc(50% - 50vw); margin-right: calc(50% - 50vw); }
	img.babel2-hidden { display: none; }
	figure { margin: 22px 0; }
	figure img, figure video { margin-top: 0; margin-bottom: 0; }
	figcaption { font-size: 13px; line-height: 19px; color: var(--caption); margin-top: 8px; }
	blockquote { margin: 18px 0 25px 8px; padding-left: 18px; border-left: 2px solid var(--hairline); color: var(--body); }
	blockquote p { margin: 0 0 8px; }
	blockquote > :last-child { margin-bottom: 0; }
	pre { overflow-x: auto; font: 13px/19px ui-monospace, Menlo, monospace; background: var(--raised); padding: 12px; margin: 0 0 18px; }
	code { font-family: ui-monospace, Menlo, monospace; font-size: 0.85em; }
	ul, ol { padding-left: 24px; margin: 0 0 18px; }
	li { margin-bottom: 6px; }
	hr { border: 0; border-top: 1px solid var(--hairline); margin: 28px 0; }
	table { display: block; overflow-x: auto; border-collapse: collapse; font-size: 14px; line-height: 21px; margin: 0 0 18px; }
	td, th { border: 1px solid var(--hairline); padding: 6px 8px; }
	iframe { display: block; width: 100%; aspect-ratio: 16 / 9; height: auto; border: 0; margin: 22px 0; }
	iframe.babel2-bleed, video.babel2-bleed { width: 100vw; max-width: 100vw; margin-left: calc(50% - 50vw); margin-right: calc(50% - 50vw); border-radius: 0; }
	video.babel2-bleed { aspect-ratio: 16 / 9; height: auto; background: #000; }
	#babel2-media { margin: 0 0 24px; }
	#babel2-media.babel2-video { width: 100%; aspect-ratio: 16 / 9; background: #000; }
	#babel2-media.babel2-video iframe { width: 100%; height: 100%; margin: 0; aspect-ratio: auto; }
	#babel2-media.babel2-audio { padding: 0 20px; }
	#babel2-media.babel2-audio audio { display: block; width: 100%; max-width: 520px; margin: 0 auto; }
	.babel2-plain { white-space: pre-line; }
	"""

	/// 页内排版脚本（在隔离环境里运行，参数 body 是文章原文）。
	/// 做的事：用浏览器解析原文 → 去掉脚本、样式、表单和所有 on* 事件属性 →
	/// 补上懒加载图片的真实地址 → 放进容器 → 图片加载后按宽高比决定是否贴边。
	private static let renderScript = """
	const root = document.getElementById('babel2-article');
	if (!root) { return null; }
	// YouTube 播放器（ADR-041）：放在正文容器外面、紧挨在它上方——翻译只动正文容器，碰不到它。
	// 同一个视频已经放好了就不重建（切阅读模式时正在播放的不被打断）；不是 YouTube 时不动已有的播放器（播客音频条）。
	if (youTube && /^[A-Za-z0-9_-]{11}$/.test(youTube)) {
		const existing = document.getElementById('babel2-media');
		if (!existing || existing.dataset.video !== youTube) {
			if (existing) { existing.remove(); }
			const box = document.createElement('div');
			box.id = 'babel2-media';
			box.className = 'babel2-video';
			box.dataset.video = youTube;
			const frame = document.createElement('iframe');
			frame.src = 'https://www.youtube.com/embed/' + youTube + '?playsinline=1&rel=0';
			frame.setAttribute('allow', 'encrypted-media; picture-in-picture; fullscreen');
			frame.setAttribute('allowfullscreen', '');
			frame.setAttribute('title', title);
			box.appendChild(frame);
			root.parentNode.insertBefore(box, root);
		}
	}
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
	// 正文里自带的视频（ADR-041）：视频网站的播放框和 <video> 贴满屏幕两边；<video> 补上控件、原地播放
	root.querySelectorAll('iframe').forEach(frame => {
		if (/youtube|youtu\\.be|vimeo|bilibili|dailymotion|player\\./i.test(frame.getAttribute('src') || '')) { frame.classList.add('babel2-bleed'); }
	});
	root.querySelectorAll('video').forEach(video => {
		video.setAttribute('controls', '');
		video.setAttribute('playsinline', '');
		if (!video.getAttribute('preload')) { video.setAttribute('preload', 'metadata'); }
		video.classList.add('babel2-bleed');
	});
	root.querySelectorAll('audio').forEach(audio => { audio.setAttribute('controls', ''); });
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
	// 点图片（ADR-040）：拦在捕获阶段，阻止外层链接跳转，把图片信息交给原生查看器。
	// 太小的图（表情、图标，≤ 24pt）不拦，外层链接照常可点。整个网页只装一次。
	if (!window.babel2ImageTapInstalled) {
		window.babel2ImageTapInstalled = true;
		document.addEventListener('click', event => {
			const img = event.target && event.target.closest ? event.target.closest('#babel2-article img') : null;
			if (!img || img.classList.contains('babel2-hidden')) { return; }
			const rect = img.getBoundingClientRect();
			if (rect.width <= 24 || rect.height <= 24) { return; }
			event.preventDefault();
			event.stopPropagation();
			const link = img.closest('a');
			window.webkit.messageHandlers.babel2ImageTapped.postMessage({
				src: img.currentSrc || img.src || '', link: link ? link.href : '', alt: img.alt || '',
				docX: rect.left + window.scrollX, docY: rect.top + window.scrollY, width: rect.width, height: rect.height
			});
		}, true);
	}
	// 正文高度：先量一次随结果返回；之后正文尺寸变化（图片加载、旋转）时再上报
	const measure = () => Math.ceil(root.getBoundingClientRect().bottom + window.scrollY);
	if (window.babel2HeightObserver) { window.babel2HeightObserver.disconnect(); }
	window.babel2HeightObserver = new ResizeObserver(() => {
		window.webkit.messageHandlers.babel2ArticleHeight.postMessage(measure());
	});
	window.babel2HeightObserver.observe(root);
	const mediaCount = root.querySelectorAll('iframe, video, audio').length + (document.getElementById('babel2-media') ? 1 : 0);
	return { textLength: root.innerText.trim().length, imageCount: images.length, mediaCount: mediaCount, articleHeight: measure() };
	"""

	/// 空正文填纯文本（参数 text）。按空行分段，段内保留换行；网址用 DOM 拆成可点的链接。
	private static let fillPlainTextScript = """
	const root = document.getElementById('babel2-article');
	if (!root || root.innerText.trim().length > 0) { return null; }
	const pattern = /(https?:\\/\\/[^\\s]+)/g;
	for (const chunk of text.split(/\\n\\s*\\n/)) {
		const trimmed = chunk.trim();
		if (!trimmed) { continue; }
		const p = document.createElement('p');
		p.className = 'babel2-plain';
		let last = 0;
		for (const match of trimmed.matchAll(pattern)) {
			p.appendChild(document.createTextNode(trimmed.slice(last, match.index)));
			const link = document.createElement('a');
			link.href = match[0];
			link.textContent = match[0];
			p.appendChild(link);
			last = match.index + match[0].length;
		}
		p.appendChild(document.createTextNode(trimmed.slice(last)));
		root.appendChild(p);
	}
	const mediaCount = root.querySelectorAll('iframe, video, audio').length + (document.getElementById('babel2-media') ? 1 : 0);
	return { textLength: root.innerText.trim().length, imageCount: root.querySelectorAll('img').length, mediaCount: mediaCount };
	"""

	/// 正文上方放居中的音频条（参数 src）。已经有播放器时不重复放。
	private static let installAudioScript = """
	const root = document.getElementById('babel2-article');
	if (!root || document.getElementById('babel2-media')) { return false; }
	const box = document.createElement('div');
	box.id = 'babel2-media';
	box.className = 'babel2-audio';
	const audio = document.createElement('audio');
	audio.setAttribute('controls', '');
	audio.setAttribute('preload', 'none');
	audio.src = src;
	box.appendChild(audio);
	root.parentNode.insertBefore(box, root);
	return true;
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

/// 转发页内上报的消息（正文高度、点了哪张图）。单独一个弱引用小对象，避免网页控件和显示面互相强引用导致内存泄漏。
@MainActor
private final class Babel2ReaderMessageProxy: NSObject, WKScriptMessageHandler {
	private weak var owner: Babel2ReaderContentView?

	init(owner: Babel2ReaderContentView) {
		self.owner = owner
	}

	func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
		switch message.name {
		case "babel2ArticleHeight":
			guard let height = (message.body as? NSNumber)?.doubleValue else { return }
			owner?.updateArticleHeight(CGFloat(height))
		case "babel2ImageTapped":
			guard let body = message.body as? [String: Any] else { return }
			owner?.handleImageTap(body)
		default:
			break
		}
	}
}
