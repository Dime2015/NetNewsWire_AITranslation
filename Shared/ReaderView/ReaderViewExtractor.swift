//
//  ReaderViewExtractor.swift
//  NetNewsWire
//
//  [阅读视图] 本 fork 新增,上游没有这个文件。
//

#if os(iOS)

import UIKit
import WebKit
import os

/// 「阅读视图」的正文提取器 —— **完全在本机运行,不依赖任何服务器或密钥**。
///
/// ## 为什么要替换上游的实现
///
/// 上游的 `ArticleExtractor` 调用 Feedbin 的付费解析服务
/// (`https://extract.feedbin.com/parser`),需要 `mercuryClientID` /
/// `mercuryClientSecret` 两个密钥。那是 NetNewsWire 官方买的,
/// **开源仓库里是空数组**,所以这个功能在我们的构建里从来就是坏的。
/// 上游自己也知道,所以在 dev 版里直接把按钮禁用了。
///
/// ## 现在怎么做
///
/// 用一个隐藏的 WKWebView 打开文章原网页,注入 Mozilla 的 `Readability.js`
/// (Firefox 阅读模式用的就是它),让**浏览器自己**把正文摘出来。
/// 好处:零成本、无服务器、无密钥、不会过期,也不会把「你读了什么」告诉第三方。
///
/// 这也正合 CLAUDE.md 第 5 节的架构原则:**HTML 的活交给浏览器里的 JS 做,Swift 不解析。**
///
/// ## 为什么长得和上游的类一模一样
///
/// 故意的。`WebViewController` 里有 20 处引用 `articleExtractor`,
/// 但真正用到的接口只有 `state` / `articleLink` / `process()` / `cancel()` 四样。
/// 做成同样的形状,调用方就只需要改「变量类型」和「构造那一行」两处,
/// 上游的 `ArticleExtractor.swift` 可以原封不动留着(将来想切回去也容易)。
@MainActor final class ReaderViewExtractor: NSObject {

	private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "ReaderView")

	/// 超时。到点还没结果就算失败 —— **绝不能让按钮一直转圈。**
	private static let timeout: TimeInterval = 20

	let articleLink: String
	private(set) var state = ArticleExtractorState.ready

	private let delegate: ArticleExtractorDelegate
	private let url: URL
	private weak var hostView: UIView?

	private var webView: WKWebView?
	private var timeoutTask: Task<Void, Never>?

	/// - Parameter hostView: 隐藏的 WebView 会挂到这个视图上。
	///   ⚠️ 不挂进视图层级的 WKWebView 可能被系统限流甚至不加载,所以要挂。
	init?(_ articleLink: String, delegate: ArticleExtractorDelegate, hostView: UIView?) {
		guard let url = URL(string: articleLink), url.scheme == "http" || url.scheme == "https" else {
			return nil
		}
		self.articleLink = articleLink
		self.delegate = delegate
		self.url = url
		self.hostView = hostView
		super.init()
	}

	func process() {
		state = .processing

		let webView = makeHiddenWebView()
		self.webView = webView

		timeoutTask = Task { [weak self] in
			try? await Task.sleep(for: .seconds(Self.timeout))
			guard !Task.isCancelled else { return }
			self?.finishWithFailure(reason: "超时")
		}

		webView.load(URLRequest(url: url))
	}

	func cancel() {
		state = .cancelled
		teardown()
	}
}
// MARK: - 私有

private extension ReaderViewExtractor {

	func makeHiddenWebView() -> WKWebView {
		let configuration = WKWebViewConfiguration()
		// 需要让页面自己的 JS 跑起来,否则前端渲染的站点会是一片空白。
		configuration.defaultWebpagePreferences.allowsContentJavaScript = true
		// 提取正文而已,别自动播放视频。
		configuration.mediaTypesRequiringUserActionForPlayback = .all

		// 有尺寸才会正常布局/加载;alpha 0 + 不可交互,用户看不见也点不到。
		let frame = hostView?.bounds ?? CGRect(x: 0, y: 0, width: 390, height: 844)
		let webView = WKWebView(frame: frame, configuration: configuration)
		webView.navigationDelegate = self
		webView.alpha = 0
		webView.isUserInteractionEnabled = false

		// 复用上游编译好的广告/追踪拦截规则:少下垃圾、快一点、干净一点。
		WebViewConfiguration.addContentBlockingRules(to: webView)

		hostView?.insertSubview(webView, at: 0)
		return webView
	}

	/// 注入 Readability.js,然后让它在页面自己的上下文里把正文摘出来。
	func runReadability() {
		guard let webView, let librarySource = Self.readabilitySource else {
			finishWithFailure(reason: "读不到 Readability.js")
			return
		}

		webView.evaluateJavaScript(librarySource) { [weak self] _, error in
			guard let self, self.state == .processing else { return }
			if let error {
				Self.logger.debug("[阅读视图] 注入 Readability 失败: \(error.localizedDescription)")
				self.finishWithFailure(reason: "注入失败")
				return
			}
			self.evaluateParse()
		}
	}

	func evaluateParse() {
		guard let webView else { return }

		webView.evaluateJavaScript(Self.parseScript) { [weak self] result, error in
			guard let self, self.state == .processing else { return }

			if let error {
				Self.logger.debug("[阅读视图] 解析失败: \(error.localizedDescription)")
				self.finishWithFailure(reason: "解析出错")
				return
			}
			// Readability 认为这个页面提不出正文时会返回 null(付费墙、登录页、纯列表页等)
			guard let json = result as? String, let data = json.data(using: .utf8) else {
				self.finishWithFailure(reason: "这个页面提不出正文")
				return
			}

			do {
				let decoder = JSONDecoder()
				decoder.dateDecodingStrategy = .iso8601
				let extracted = try decoder.decode(ExtractedArticle.self, from: data)
				guard extracted.content != nil else {
					self.finishWithFailure(reason: "提取结果是空的")
					return
				}
				self.state = .complete
				self.teardown()
				self.delegate.articleExtractionDidComplete(extractedArticle: extracted)
			} catch {
				Self.logger.debug("[阅读视图] JSON 解码失败: \(error.localizedDescription)")
				self.finishWithFailure(reason: "结果格式不对")
			}
		}
	}

	func finishWithFailure(reason: String) {
		// 已经取消 / 已经完成的,不要再回调一次
		guard state == .processing else { return }
		// 用 error 级别:debug 级别不会落盘,以后想排查"这个源为什么抽不出来"就没日志可看了。
		// 查看:xcrun simctl spawn booted log show --last 30m --predicate 'process == "NetNewsWire"' | grep 阅读视图
		Self.logger.error("[阅读视图] 失败(\(reason)):\(self.articleLink)")
		state = .failedToParse
		teardown()
		delegate.articleExtractionDidFail(with: ReaderViewExtractorError(reason: reason))
	}

	func teardown() {
		timeoutTask?.cancel()
		timeoutTask = nil
		webView?.stopLoading()
		webView?.navigationDelegate = nil
		webView?.removeFromSuperview()
		webView = nil
	}

	/// 打进 app 包里的 Readability.js。只读一次。
	static let readabilitySource: String? = {
		guard let url = Bundle.main.url(forResource: "Readability", withExtension: "js"),
			  let source = try? String(contentsOf: url, encoding: .utf8) else {
			logger.error("[阅读视图] app 包里找不到 Readability.js")
			return nil
		}
		return source
	}()

	/// 在页面里跑 Readability,把结果拼成**上游 Mercury 那套字段名**的 JSON。
	/// 这样就能用和上游完全一样的 `JSONDecoder` 解成 `ExtractedArticle`,
	/// `ExtractedArticle.swift` 一个字都不用改。
	static let parseScript = """
	(function () {
		try {
			if (typeof Readability !== "function") { return null; }
			// ⚠️ 必须传副本:Readability 的 parse() 会改动传进去的 DOM(官方文档明确警告)
			// 🔧 2026-08-12:**先把"在真实页面上根本看不见的东西"标记掉,再克隆**。
			//
			// 起因是 restofworld.org(用户报"阅读模式排版很乱、翻译后段落不全"):
			// 它的正文里嵌着**行内术语浮层** —— `<mark>Alibaba</mark>` 后面跟着一整段
			// "Alibaba, founded in 1999 by … READ MORE",平时被站点 CSS 藏着,
			// 鼠标悬停才出来。阅读模式剥掉站点 CSS 之后,这些文字**全部冒出来**,
			// 句子被撑成一团(那就是"排版乱"),而且它们混在 `<p>` 里一起喂给模型 ——
			// 又长又不成句,模型翻得乱、还容易漏掉整段(那就是"段落不全")。
			//
			// ⚠️ 这件事**只有在这里能做**:我们是在真实 WebView 里、站点 CSS 已经生效的时候提取的,
			// 所以 `getComputedStyle` 说得出"这个元素用户到底看不看得见"。
			// 换成拿 HTML 字符串离线解析(比如在服务器上跑 Readability)就**判不出来**。
			//
			// 判据取得很保守,只认三种"作者明确藏起来"的写法,不猜:
			//   display:none / visibility:hidden / aria-hidden="true"
			// (不查 opacity:0 和零尺寸 —— 懒加载和动画中的元素常常是那样,误删风险太大。)
			var hiddenMarked = [];
			var probeAll = document.body ? document.body.querySelectorAll("*") : [];
			for (var h = 0; h < probeAll.length; h++) {
				var node = probeAll[h];
				var hidden = node.getAttribute("aria-hidden") === "true";
				if (!hidden) {
					var cs = window.getComputedStyle(node);
					hidden = cs && (cs.display === "none" || cs.visibility === "hidden");
				}
				if (hidden) {
					node.setAttribute("data-nnw-hidden", "1");
					hiddenMarked.push(node);
				}
			}

			var work = document.cloneNode(true);
			var hiddenInClone = work.querySelectorAll ? work.querySelectorAll("[data-nnw-hidden]") : [];
			for (var r = hiddenInClone.length - 1; r >= 0; r--) {
				var doomed = hiddenInClone[r];
				if (doomed.parentNode) { doomed.parentNode.removeChild(doomed); }
			}
			// 把标记从**真实文档**上撤掉 —— 这个 WebView 虽然用户看不见,但别留痕
			for (var c = 0; c < hiddenMarked.length; c++) {
				hiddenMarked[c].removeAttribute("data-nnw-hidden");
			}

			// 🔧 2026-08-12:**先把懒加载图归位,再交给 Readability**。
			//
			// 起因是デイリーポータルＺ:它的图是
			//   <img src="…/loading-min.png" data-src="真正的图" class="lazy-image">
			// 真实地址只在 data-src 里,src 是个占位图。而我们是在**只有一屏高**的隐藏 WebView 里提取的,
			// 站点自己的懒加载脚本只会把靠近视口的那几张换成真图,屏幕外的全停在占位图上。
			//
			// Readability 自带 _fixLazyImages,但它的判据依赖站点怎么写 class/src,不一定接得住。
			// 我们**不改 Readability(vendored,不许动)**,而是在交给它之前先把常见的懒加载属性
			// 落到 src 上 —— 纯粹是"把页面恢复成它本该有的样子",不改结构、不动顺序。
			var lazyAttrs = ["data-src", "data-original", "data-lazy-src", "data-actualsrc"];
			var imgs = work.querySelectorAll("img");
			for (var i = 0; i < imgs.length; i++) {
				var img = imgs[i];
				for (var a = 0; a < lazyAttrs.length; a++) {
					var real = img.getAttribute(lazyAttrs[a]);
					if (real && real.length > 0 && real !== img.getAttribute("src")) {
						img.setAttribute("src", real);
						break;
					}
				}
				var realSet = img.getAttribute("data-srcset");
				if (realSet && realSet.length > 0) { img.setAttribute("srcset", realSet); }
			}

			var article = new Readability(work).parse();
			if (!article || !article.content) { return null; }

			return JSON.stringify({
				content: article.content,
				title: article.title || null,
				excerpt: article.excerpt || null,
				author: article.byline || null,
				direction: article.dir || null,
				domain: article.siteName || null,
				date_published: article.publishedTime || null,
				url: document.location.href
			});
		} catch (e) {
			return null;
		}
	})();
	"""
}

// MARK: - WKNavigationDelegate

extension ReaderViewExtractor: WKNavigationDelegate {

	func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
		guard state == .processing else { return }
		runReadability()
	}

	func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
		finishWithFailure(reason: error.localizedDescription)
	}

	func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
		finishWithFailure(reason: error.localizedDescription)
	}
}

// MARK: - 错误

struct ReaderViewExtractorError: LocalizedError {
	let reason: String
	// [阅读视图] 这里**故意不用 NSLocalizedString** —— 本 fork 禁用它,
	// 因为编译器会把文案自动塞进上游共用的 Localizable.xcstrings,造成 merge 冲突(见 L4)。
	var errorDescription: String? { "无法提取正文:\(reason)" }
}

#endif
