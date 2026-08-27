//
//  FeedPreviewArticleViewController.swift
//  NetNewsWire
//
//  [发现] 本 fork 新增,上游没有这个文件。试读 Phase B(2026-07-29)。
//
//  试读的文章页:把一篇**内存文章**用上游渲染层原样画出来,
//  底部工具栏带**翻译 / 阅读模式**(Phase C,2026-07-30;长图按钮已于 2026-08-12 拿掉,
//  用户反馈试读场景用不上),点链接外开。
//
//  ## 为什么不复用主阅读页 WebViewController
//  它和 SceneCoordinator 深度耦合(上一篇/下一篇、已读/星标、webViewProvider
//  全走协调器),拿来当预览页要伺候一堆对"库里根本不存在的文章"毫无意义的机制。
//
//  ## 两件功能是怎么共用的(Phase C 的核心)
//  翻译对页面的全部依赖被抽成了 NNWArticlePageHost 协议
//  (Shared/Translation/NNWArticlePageHost.swift,桥接原样搬自主阅读页):
//  本页 conform 它,TranslationController 对两页一视同仁。
//  阅读模式用的 ReaderViewExtractor 本来就是独立组件,照主阅读页的状态机接一遍即可。
//
//  ## 复用了上游/fork 的哪些现成件(它们本身一行没改)
//  - ArticleRenderer.articleHTML —— 独立静态函数,喂内存 Article 就能出整页 HTML
//    (阅读模式 = 多喂一个 extractedArticle,渲染器自己会用提取出的正文)
//  - WebViewConfiguration.configuration(with:) —— 主阅读页同款的 WKWebView 配置
//  - TranslationController(含按钮与整套流程)、ArticleExtractorButton
//  - NNWLinkOpener —— 点正文里的链接,走 app 统一的外开逻辑
//
//  ## 和主阅读页的已知差异(有意为之,记在 T35)
//  - 不做「长按翻译键强制重翻」(试读场景用不上)
//  - 不做「按源自动进阅读视图」(试读的源多半还没订阅,没有 Feed 对象)
//  - 不做长图(2026-08-12 拿掉,用户反馈试读场景用不上)
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

	// MARK: Phase C 的三件功能的状态

	/// 翻译流程编排(和主阅读页同一个类;它通过 NNWArticlePageHost 协议使唤本页)
	private lazy var translationController = TranslationController { [weak self] in self }

	/// 阅读模式:提取器 + 提取结果 + 当前显示哪个。状态机照抄主阅读页。
	private var articleExtractor: ReaderViewExtractor?
	private var extractedArticle: ExtractedArticle?
	private var isShowingExtractedArticle = false

	/// 阅读模式按钮(主阅读页同款,自带 关/开/转圈/出错 四态图标)
	private let extractorButton = ArticleExtractorButton()

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

		configureToolbar()
		render()
	}

	/// 底部工具栏:翻译 ‖ 阅读模式。
	/// [发现] 2026-08-12:长图按钮拿掉了(用户反馈试读页用不上)。
	/// 两个键都是主阅读页的现成组件,原样搬来 —— 状态机(转圈/角标/出错)零重接。
	private func configureToolbar() {

		translationController.button.addTarget(self, action: #selector(translateTapped), for: .touchUpInside)
		translationController.presentError = { [weak self] message in
			self?.presentError(title: "翻译", message: message)
		}
		// 按当前文章的缓存状态摆好按钮初始图标(有完整缓存会带实心角标)
		translationController.resetForNewArticle()

		// 阅读模式按钮:和主阅读页一样要钉死尺寸(转圈态 setImage(nil) 会让固有尺寸
		// 变 0,iOS 26 工具栏会把它算成 0 宽塌掉 —— L19 的坑,别省这两条约束)
		extractorButton.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			extractorButton.widthAnchor.constraint(equalToConstant: 44),
			extractorButton.heightAnchor.constraint(equalToConstant: 44)
		])
		// ⚠️ 初始图标必须显式设(独立审查必修 1):buttonState 默认就是 .off,
		// didSet 有"值没变就不动"的守卫,不设的话是一个 44×44 的空白可点区。
		// 主阅读页是在创建按钮时设的(ArticleViewController.swift),这里补同一句。
		extractorButton.setImage(Assets.Images.articleExtractorOff, for: .normal)
		extractorButton.tintColor = .label	// 和主阅读页控件板同色
		extractorButton.addTarget(self, action: #selector(readerTapped), for: .touchUpInside)

		toolbarItems = [
			UIBarButtonItem(customView: translationController.button),
			UIBarButtonItem.flexibleSpace(),
			UIBarButtonItem(customView: extractorButton)
		]
	}

	/// 工具栏跟着本页走:进来亮出,离开收起(试读列表页和发现页都没有工具栏)
	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		navigationController?.setToolbarHidden(false, animated: animated)
	}

	override func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)
		navigationController?.setToolbarHidden(true, animated: animated)
	}

	/// 退出页面(pop)时把在飞的翻译掐掉(独立审查建议 3):
	/// 主阅读页的 WebViewController 由协调器长期持有,"翻完留给下次"说得通;
	/// 试读页一退就没了,继续跑只是烧钱给看不见的页面。
	/// resetForNewArticle 的取消路径会把已翻的组存成断点缓存,重进同一篇能接着用。
	override func willMove(toParent parent: UIViewController?) {
		super.willMove(toParent: parent)
		if parent == nil {
			translationController.resetForNewArticle()
		}
	}

	/// 渲染配方照抄主阅读页 renderPage(WebViewController.swift):
	/// Rendering → 套 page 模板 → 特例过滤 → loadHTMLString。一步不少、一步不多。
	private func render() {
		guard let webView else { return }

		let theme = ArticleThemesManager.shared.currentTheme
		// [翻译] 标题若有「标题翻译」的译文缓存就用中文标题。
		// 试读**已订阅**的源时会命中 —— 试读文章用的是真实账户身份
		// (身份映射见 FeedPreviewViewController.makeArticles);没订阅的源没有开关,原样显示。
		let displayArticle = NNWTitleTranslationController.shared.cachedDisplayArticle(for: article)
		// 阅读模式开着就多喂一个提取结果,渲染器会用提取出的正文(主阅读页同款分支)
		let rendering: ArticleRenderer.Rendering
		if isShowingExtractedArticle, let extractedArticle {
			rendering = ArticleRenderer.articleHTML(article: displayArticle, extractedArticle: extractedArticle, theme: theme)
		} else {
			rendering = ArticleRenderer.articleHTML(article: displayArticle, theme: theme)
		}

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

// MARK: - Phase C:三个按钮的动作

extension FeedPreviewArticleViewController {

	@objc private func translateTapped() {
		translationController.toggle()
	}

	/// 阅读模式:关 →(提取中,可点取消)→ 开 → 关。状态机语义照抄主阅读页。
	@objc private func readerTapped() {

		if let articleExtractor {
			// 正在提取:再点一下 = 取消
			articleExtractor.cancel()
			self.articleExtractor = nil
			extractorButton.buttonState = .off	// 状态真的变了,didSet 会把图标换回 off
			return
		}

		if isShowingExtractedArticle {
			isShowingExtractedArticle = false
			extractorButton.buttonState = .off
			rerender()
			return
		}

		if extractedArticle != nil {
			// 这一页已经提取过了:直接切过去,不重新抓
			isShowingExtractedArticle = true
			extractorButton.buttonState = .on
			rerender()
			return
		}

		guard let link = article.preferredLink,
			  let extractor = ReaderViewExtractor(link, delegate: self, hostView: view) else {
			presentError(title: "阅读模式", message: "这篇文章没有可用的原文链接,无法提取。")
			return
		}
		articleExtractor = extractor
		extractorButton.buttonState = .animated
		// ⚠️ .animated 的 didSet 会把按钮禁点(主阅读页靠上下文菜单取消,试读页没有那个入口)。
		// 重新打开交互,让"转圈中再点一下 = 取消"这条路真的走得到(独立审查建议 2)。
		extractorButton.isUserInteractionEnabled = true
		extractor.process()
	}

	/// 换显示内容(原文 ↔ 提取版)= 整页重载。先把在飞的翻译掐掉(独立审查项 7):
	/// 新 DOM 没有旧的分组标记,译文贴不上会白白重试;掐掉的同时把已翻的组存成断点缓存。
	/// 顺带把翻译按钮恢复成和缓存状态相符的样子。
	private func rerender() {
		translationController.resetForNewArticle()
		render()
	}

}

// MARK: - 阅读模式的提取回调

extension FeedPreviewArticleViewController: ArticleExtractorDelegate {

	func articleExtractionDidFail(with error: Error) {
		articleExtractor = nil
		extractorButton.buttonState = .error
		presentError(title: "阅读模式", message: error.localizedDescription)
	}

	func articleExtractionDidComplete(extractedArticle: ExtractedArticle) {
		let wasCancelled = (articleExtractor?.state == .cancelled)
		articleExtractor = nil
		guard !wasCancelled else { return }
		self.extractedArticle = extractedArticle
		isShowingExtractedArticle = true
		extractorButton.buttonState = .on
		render()
	}
}

// MARK: - 文章页宿主(翻译 / 长图通过这个协议使唤本页)

extension FeedPreviewArticleViewController: NNWArticlePageHost {

	var nnwHostArticle: Article? { article }

	var nnwHostWebView: WKWebView? { webView }

	/// 试读页的网页表头本来就可见(没有阅读栏),标题译文直接改在 DOM 里,这里无事可做
	func nnwTranslationTitleDidChange(_ text: String?) {
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

	func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
		// [翻译] 页面就绪后:这篇要是记着「上次显示译文」且本地有完整缓存,
		// 自动秒显译文(零请求)—— 主阅读页同款行为
		translationController.autoApplyTranslationFromCacheIfNeeded()
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
