//
//  FeedPreviewArticleViewController.swift
//  NetNewsWire
//
//  [发现] 本 fork 新增,上游没有这个文件。试读 Phase B(2026-07-29)。
//
//  试读的文章页(基础版):把一篇**内存文章**用上游渲染层原样画出来 + 点链接外开。
//
//  ## 刻意不做的两件事
//  1. **不复用主阅读页 WebViewController** —— 它和 SceneCoordinator 深度耦合
//     (上一篇/下一篇、已读/星标、webViewProvider 全走协调器),拿来当预览页
//     要伺候一堆对"库里根本不存在的文章"毫无意义的机制。
//  2. **暂不带翻译/阅读模式/长图** —— 这三个功能现在焊在主阅读页上
//     (JS 桥在 WebViewController.swift 尾部、长图导出的入参就是它),
//     Phase C 再抽成两页共用,方案记录在 NOTES-todo 的 T32。
//
//  ## 复用了上游/fork 的哪些现成件(它们本身一行没改)
//  - ArticleRenderer.articleHTML —— 独立静态函数,喂内存 Article 就能出整页 HTML
//  - WebViewConfiguration.configuration(with:) —— 主阅读页同款的 WKWebView 配置
//    (含注入脚本、内容拦截规则),所以字体/主题/样式和正式阅读页一致
//  - NNWLinkOpener —— 点正文里的链接,走 app 统一的外开逻辑
//

#if os(iOS)

import UIKit
import WebKit
import Articles
import Images
import RSCore

@MainActor final class FeedPreviewArticleViewController: UIViewController {

	private let article: Article

	/// 发现结果里的图标地址(播客封面等),喂给正文模板头部的"源头像"位
	private let iconURL: String?

	private var webView: WKWebView?

	/// scheme 处理器自己持有一份,保证生命周期覆盖整个页面
	private var iconSchemeHandler: FeedPreviewIconSchemeHandler?

	init(article: Article, iconURL: String?) {
		self.article = article
		self.iconURL = iconURL
		super.init(nibName: nil, bundle: nil)
	}

	required init?(coder: NSCoder) {
		fatalError("这一页不走 storyboard")
	}

	override func viewDidLoad() {
		super.viewDidLoad()

		// [外观] 网页透明,纸色由这层铺 —— 主阅读页同思路
		view.backgroundColor = AppAppearance.paperBackground
		navigationItem.largeTitleDisplayMode = .never

		if let link = article.preferredLink, URL(string: link) != nil {
			navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "safari"),
																style: .plain,
																target: self,
																action: #selector(openInBrowser))
			navigationItem.rightBarButtonItem?.accessibilityLabel = "在浏览器打开"
		}

		let handler = FeedPreviewIconSchemeHandler(iconURL: iconURL)
		iconSchemeHandler = handler
		let configuration = WebViewConfiguration.configuration(with: handler)

		// 注入的 main_ios.js 等脚本会往这三个消息口发消息(点图放大等)。
		// 没有接收方时 JS 会在事件回调里报错;挂上空处理器让脚本安静地工作。
		// (试读页不做图片放大/源信息页,收到消息后什么都不做。)
		for name in ["imageWasClicked", "imageWasShown", "showFeedInspector"] {
			configuration.userContentController.add(WrapperScriptMessageHandler(self), name: name)
		}

		// ⚠️ 反制"藏表头"标记(独立审查必修 2):
		// 注入的 nnw_appearance.js 会无条件给 <html> 打 nnw-reading-bar 类,
		// 把网页自己的大标题/日期/源头衔全部 display:none —— 主阅读页有原生「阅读栏」
		// 把这些信息画回来,试读页没有,不反制的话文章页第一眼就没有标题。
		// 它打类有两个时机,这里各盖一手,顺序有保证:
		//   ① document start:它先注入先跑,我们的脚本在它之后加进 userContentController,
		//     所以紧随其后执行,当场摘掉;
		//   ② DOMContentLoaded:它的 inject() 会再打一次 —— 同一事件的监听器按注册
		//     顺序执行,我们注册在后,刚好摘在它后面。
		// 不用"反制 CSS"是因为那要猜每个被藏元素原本的 display 值,猜错就破版式。
		let unhideHeaderScript = WKUserScript(source: """
			(function() {
				document.documentElement.classList.remove("nnw-reading-bar");
				document.addEventListener("DOMContentLoaded", function() {
					document.documentElement.classList.remove("nnw-reading-bar");
				});
			})();
			""", injectionTime: .atDocumentStart, forMainFrameOnly: true)
		configuration.userContentController.addUserScript(unhideHeaderScript)

		let webView = WKWebView(frame: view.bounds, configuration: configuration)
		webView.isOpaque = false
		webView.backgroundColor = .clear
		webView.scrollView.backgroundColor = .clear
		webView.navigationDelegate = self
		webView.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(webView)
		NSLayoutConstraint.activate([
			webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			webView.topAnchor.constraint(equalTo: view.topAnchor),
			webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
		])
		self.webView = webView

		render()
	}

	/// 渲染配方照抄主阅读页 renderPage(WebViewController.swift):
	/// Rendering → 套 page 模板 → 特例过滤 → loadHTMLString。一步不少、一步不多。
	private func render() {
		guard let webView else { return }

		let theme = ArticleThemesManager.shared.currentTheme
		let rendering = ArticleRenderer.articleHTML(article: article, theme: theme)

		let substitutions = [
			"title": rendering.title,
			"baseURL": rendering.baseURL,
			"style": rendering.style,
			"body": rendering.html,
			"windowScrollY": "0"
		]

		var html = try! MacroProcessor.renderedText(withTemplate: ArticleRenderer.page.html, substitutions: substitutions)
		html = ArticleRenderingSpecialCases.filterHTMLIfNeeded(baseURL: rendering.baseURL, html: html)

		WebViewConfiguration.addContentBlockingRules(to: webView)
		// baseURL 走主阅读页同一个调整入口([YouTube] 特例,见 WebViewController 末尾)
		webView.loadHTMLString(html, baseURL: WebViewController.nnwAdjustedBaseURL(rendering.baseURL))
	}

	@objc private func openInBrowser() {
		guard let link = article.preferredLink, let url = URL(string: link) else { return }
		NNWLinkOpener.open(url, from: self)
	}
}

// MARK: - 链接点击一律外开

extension FeedPreviewArticleViewController: WKNavigationDelegate {

	func webView(_ webView: WKWebView,
				 decidePolicyFor navigationAction: WKNavigationAction,
				 decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {

		if navigationAction.navigationType == .linkActivated {
			if let url = navigationAction.request.url {
				NNWLinkOpener.open(url, from: self)
			}
			decisionHandler(.cancel)
			return
		}
		decisionHandler(.allow)
	}
}

// MARK: - 注入脚本的消息口(空实现,理由见 viewDidLoad)

extension FeedPreviewArticleViewController: WKScriptMessageHandler {

	func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
		// 试读页不做图片放大等交互;挂这个空实现只为了让注入脚本不报错
	}
}

// MARK: - 源头像 scheme

/// 正文模板头部有一个"源头像"位,主阅读页用自定义 scheme 从账户里取图
/// (ArticleIconSchemeHandler,依赖协调器)。试读页没有账户,
/// 就把发现结果里已有的图标喂给同一个 scheme;没有图标时按"取不到"处理 ——
/// 模板里那个 <img> 加载失败即不显示,页面其余部分不受影响。
final class FeedPreviewIconSchemeHandler: NSObject, WKURLSchemeHandler {

	private let iconURL: String?

	init(iconURL: String?) {
		self.iconURL = iconURL
	}

	func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {

		guard let url = urlSchemeTask.request.url,
			  let iconURL,
			  let data = ImageDownloader.shared.image(for: iconURL),
			  let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
											 headerFields: ["Cache-Control": "no-cache"]) else {
			urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
			return
		}

		urlSchemeTask.didReceive(response)
		urlSchemeTask.didReceive(data)
		urlSchemeTask.didFinish()
	}

	func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
	}
}

#endif
