import Foundation
import UIKit
import Babel2Core
import Babel2UI

/// Babel 2.0 阅读页（Slice 4：第 1 步静态图文页 + 第 2 步滑动收缩 + 第 3 步底栏与显隐）。
///
/// 页面结构（从上到下）：
/// - 顶栏（58pt，不透明）：返回 / 打开原文 / 分享
/// - 正文滚动区：最上面是原生的标题区（日期、标题、订阅源名），下面是网页排版的正文
///
/// 标题区是原生控件、不等网页加载 —— 合同要求「一进文章，标题和作者立刻可见」。
/// 它放在正文滚动区里、跟正文一起滚动。
///
/// 第 2 步「滑动收缩」（方案 A）：顶栏下方盖一条紧凑标题栏，由滚动位置直接驱动 ——
/// 大标题随正文滚走，紧凑栏的底色/图标/圆环/小标题同步渐显，小标题滑入到位；
/// 之后圆环跟随阅读进度。滚动时不改变正文区域的尺寸。
///
/// 第 3 步：底部工具栏（已读 / 星标可用，其余占位）；紧凑栏固定后，
/// 顶栏按钮与底栏随上下滑一起显隐（方案 A：顶栏底色保留，紧凑栏纹丝不动；底栏整条滑出）。
/// 按订阅源的「总是用阅读模式」开关（读写由装配层注入，页面不直接碰账户数据）。
struct Babel2FeedReaderModeSetting {
	let isAlwaysOn: @MainActor () -> Bool
	let setAlwaysOn: @MainActor (Bool) -> Void
}

@MainActor
final class Babel2ArticleViewController: UIViewController {
	private let article: ArticleSnapshot
	private let environment: AppEnvironment
	private let feedTitle: String?
	private let compactHeader: Babel2ReaderCompactHeaderView
	private let motionRecorder: any Babel2MotionRecording
	/// 大标题上沿开始钻进顶栏时的已滚动距离（布局后测得）。
	private var collapseStart: CGFloat = 0
	private var chromeState: MotionReaderChromeState = .expanded
	private let toolbar = Babel2ReaderToolbarView()
	private var topButtons = [UIButton]()
	private var topBar: UIView?
	private var moreButton: UIButton?
	private let feedAuthor: String?
	private var barVisibility = Babel2ReaderBarVisibility()
	private var barAnimator: UIViewPropertyAnimator?
	private var barAnimationStart: CGFloat = 0
	/// 一次「栏显隐」交互是否正在进行（用于性能打点成对：一次交互只记一对 begin/end）。
	private var isBarIntervalOpen = false
	private var barAnimationTarget: CGFloat = 0
	private var lastScrolled: CGFloat?
	private var settleTimer: Timer?
	private var isRead: Bool
	private var isStarred: Bool
	private var isStatusRequestInFlight = false
	/// 本次打开是否已经自动标过已读（只标一次；之后手动标回未读不会被再次改掉）。
	private var didAutoMarkRead = false
	/// 翻译引擎需要的原始文章对象（类型刻意不写明，只在网页控件专用目录里的宿主扩展中还原）。
	private(set) var translationHostArticle: AnyObject?
	private let hostArticleProvider: (@MainActor (ArticleSnapshot.ID) async -> AnyObject?)?
	private var isTranslationPrepared = false
	/// 阅读模式（全文）：开着时正文显示的是从原网页提取的全文。
	private(set) var isReaderModeOn = false
	private var fullTextHTML: String?
	private var fullTextTask: Task<Void, Never>?
	private let fullTextProvider: @MainActor (URL, UIView) async throws -> String
	private let feedReaderModeSetting: Babel2FeedReaderModeSetting?
	/// 内置浏览器工厂（装配层注入；为 nil 时退回用系统浏览器打开）。ADR-021。
	private let makeBrowser: ((URL) -> (any Babel2PreparableRoute))?
	private var browserMotion: Babel2ReaderBrowserMotion?
	private let statusLabel = UILabel()
	private var statusHideTask: Task<Void, Never>?
	/// 复用的翻译引擎：分块、流式、缓存、断点续翻、骨架色条都在里面，这里只接按钮和标题。
	private lazy var translation: TranslationController = {
		let controller = TranslationController(currentWebViewController: { [weak self] in self })
		controller.stateDidChange = { [weak self] state in
			self?.toolbar.setTranslationState(state)
		}
		controller.presentError = { [weak self] message in
			self?.presentTranslationError(message)
		}
		return controller
	}()
	private let contentView = Babel2ReaderContentView()
	private let headerView = UIView()
	private let dateLabel = UILabel()
	private let titleLabel = UILabel()
	private let bylineLabel = UILabel()
	private let messageStack = UIStackView()
	private let messageLabel = UILabel()
	private let retryButton = UIButton(type: .system)
	private var renderTask: Task<Void, Never>?
	private var renderGeneration = UUID()
	private var lastHeaderWidth: CGFloat = 0
	private var headerHeight: CGFloat = 0
	var onOpenOriginal: ((URL, String) -> Void)?
	/// 用户点了正文里的链接。
	var onOpenLink: ((URL) -> Void)?
	/// 下一篇（ADR-022）：由文章列表按显示顺序决定；装配层负责原地替换成新的阅读页。
	var nextArticleProvider: (() -> ArticleSnapshot?)? {
		didSet { refreshNextAvailability() }
	}
	var onShowNext: ((ArticleSnapshot) -> Void)?

	/// 仅供自动化测试观察。
	var readerContentView: Babel2ReaderContentView { contentView }
	private(set) var lastRenderResult: Babel2ReaderContentView.RenderResult?

	init(
		article: ArticleSnapshot,
		environment: AppEnvironment,
		feedTitle: String? = nil,
		feedIconData: Data? = nil,
		motionRecorder: any Babel2MotionRecording = Babel2OSLogMotionRecorder(),
		hostArticleProvider: (@MainActor (ArticleSnapshot.ID) async -> AnyObject?)? = nil,
		fullTextProvider: @escaping @MainActor (URL, UIView) async throws -> String = { url, host in
			try await Babel2FullTextFetcher.fetch(url: url, hostView: host)
		},
		feedReaderModeSetting: Babel2FeedReaderModeSetting? = nil,
		makeBrowser: ((URL) -> (any Babel2PreparableRoute))? = nil
	) {
		self.feedReaderModeSetting = feedReaderModeSetting
		self.makeBrowser = makeBrowser
		self.hostArticleProvider = hostArticleProvider
		self.fullTextProvider = fullTextProvider
		self.article = article
		self.environment = environment
		self.feedTitle = feedTitle
		self.feedAuthor = article.author
		self.motionRecorder = motionRecorder
		isRead = article.isRead
		isStarred = article.isStarred
		compactHeader = Babel2ReaderCompactHeaderView(
			feedTitle: feedTitle,
			author: article.author,
			articleTitle: article.title,
			iconData: feedIconData,
			showsSourceLink: article.url != nil && makeBrowser != nil
		)
		super.init(nibName: nil, bundle: nil)
		restorationIdentifier = "babel2.article.\(article.id.accountID).\(article.id.feedID).\(article.id.articleID)"
	}

	required init?(coder: NSCoder) { nil }

	override func viewDidLoad() {
		super.viewDidLoad()
		view.backgroundColor = BabelPalette.background
		let topBar = configureTopBar()
		configureContent(below: topBar)
		configureCompactHeader(below: topBar)
		configureToolbar()
		configureHeader()
		configureMessage()
		contentView.onScrollGeometryChange = { [weak self] in
			self?.updateChrome()
		}
		contentView.onLinkActivated = { [weak self] url in
			self?.openLink(url)
		}
		compactHeader.onSourceLinkTapped = { [weak self] in self?.originalTapped() }
		installBrowserMotion()
		contentView.onContentProcessTerminated = { [weak self] in
			self?.cancelRendering()
			self?.showMessage(Babel2Localization.text(.unableToLoadArticle), allowsRetry: true)
		}
		startRendering()
		resolveTranslationHostArticle()
		// 自动取全文：订阅源设了「总是用阅读模式」（ADR-020），或这篇上次开着阅读模式离开（ADR-019）
		if article.url != nil {
			if isFeedAlwaysReaderMode {
				startFullTextFetch(rememberForArticle: false)
			} else if ArticleReadingStateStore.state(for: readingStateKey).readerMode {
				startFullTextFetch(rememberForArticle: true)
			}
		}
	}

	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)
		autoMarkReadIfNeeded()
		refreshNextAvailability()
	}

	private func refreshNextAvailability() {
		guard isViewLoaded else { return }
		toolbar.setNextAvailable(nextArticleProvider?() != nil)
	}

	/// 底栏 ∨：有下一篇就交给装配层原地换页；没有就把按钮置灰。
	func showNextArticle() {
		guard let next = nextArticleProvider?() else {
			toolbar.setNextAvailable(false)
			return
		}
		onShowNext?(next)
	}

	/// 打开文章即标为已读（用户 2026-09-25 决定；旧版与 Reeder 同样如此）。
	private func autoMarkReadIfNeeded() {
		guard !didAutoMarkRead else { return }
		didAutoMarkRead = true
		guard !isRead else { return }
		performStatusAction(.markRead(article.id)) { controller in
			controller.isRead = true
			controller.toolbar.setRead(true)
		}
	}

	override func viewDidLayoutSubviews() {
		super.viewDidLayoutSubviews()
		layoutHeaderIfNeeded()
		updateBottomInset()
	}

	override func viewDidDisappear(_ animated: Bool) {
		super.viewDidDisappear(animated)
		if isMovingFromParent {
			fullTextTask?.cancel()
			statusHideTask?.cancel()
			// 离开页面：取消还在飞的翻译请求（不再花钱，也不会写到别的页面上）
			if isTranslationPrepared { translation.resetForNewArticle() }
			cancelRendering()
			settleTimer?.invalidate()
			barAnimator?.stopAnimation(true)
		}
	}

	deinit { renderTask?.cancel() }

	// MARK: - 正文加载

	/// - fullText: 非 nil 时直接排版这段全文（阅读模式），不再向数据层要原文。
	/// - scrollToTop: 排版完成后回到顶部（切换阅读模式时；两版正文无法按位置对应，1.x 经验）。
	private func startRendering(fullText: String? = nil, scrollToTop: Bool = false) {
		cancelRendering()
		hideMessage()
		// 重新排版 = 网页里没有译文了，翻译按钮回到初始并等待重新就绪
		if isTranslationPrepared { translation.resetForNewArticle() }
		isTranslationPrepared = false
		toolbar.setTranslationAvailable(false)
		applyDisplayedTitle(nil)
		let generation = UUID()
		renderGeneration = generation
		let renderer = environment.articleRenderer
		let article = self.article
		let articleID = article.id
		renderTask = Task { @MainActor [weak self, renderer, article, articleID, generation] in
			defer {
				if let self, self.renderGeneration == generation {
					self.renderTask = nil
				}
			}
			do {
				let body: String
				if let fullText {
					body = fullText
				} else {
					let rendered = try await renderer.render(article)
					// 过期保护：渲染结果不属于这篇文章 → 丢弃
					guard rendered.articleID == articleID else { return }
					body = rendered.body
				}
				// 过期保护：页面已关闭、已重试 → 丢弃
				guard !Task.isCancelled,
					let self,
					self.renderGeneration == generation,
					self.article.id == articleID else { return }
				let result = await self.contentView.render(body: body, baseURL: article.url, title: article.title)
				guard !Task.isCancelled, self.renderGeneration == generation else { return }
				self.lastRenderResult = result
				if scrollToTop { self.scrollToTop() }
				if let result {
					if result.isEmpty {
						self.showMessage(Babel2Localization.text(.noArticleContent), allowsRetry: false)
					} else {
						self.prepareTranslationIfReady()
					}
				} else {
					self.showMessage(Babel2Localization.text(.unableToLoadArticle), allowsRetry: true)
				}
			} catch {
				guard !Task.isCancelled,
					let self,
					self.renderGeneration == generation,
					self.article.id == articleID else { return }
				self.showMessage(Babel2Localization.text(.unableToLoadArticle), allowsRetry: true)
			}
		}
	}

	private func cancelRendering() {
		renderGeneration = UUID()
		renderTask?.cancel()
		renderTask = nil
	}

	@objc private func retryTapped() { startRendering(fullText: isReaderModeOn ? fullTextHTML : nil) }

	// MARK: - 阅读模式（全文）

	/// 与翻译引擎相同的单篇文章键（ArticleReadingStateStore 里同时存着「阅读模式」「译文」两个记忆）。
	private var readingStateKey: String { article.id.accountID + "|" + article.id.articleID }

	private var isFeedAlwaysReaderMode: Bool { feedReaderModeSetting?.isAlwaysOn() ?? false }

	/// ••• 菜单「此订阅源总是用阅读模式」：写进订阅源设置；打开时若本篇还不是全文，立刻取。
	func toggleFeedAlwaysReaderMode() {
		guard let feedReaderModeSetting else { return }
		let newValue = !feedReaderModeSetting.isAlwaysOn()
		feedReaderModeSetting.setAlwaysOn(newValue)
		if newValue, !isReaderModeOn, fullTextTask == nil {
			startFullTextFetch(rememberForArticle: false)
		}
		readerModeStateDidChange()
	}

	/// 底栏第 4 格「阅读模式」：开 → 取全文；关 → 回到订阅源自带的正文（ADR-020）。
	func toggleReaderMode() {
		if isReaderModeOn || fullTextTask != nil {
			fullTextTask?.cancel()
			fullTextTask = nil
			hideStatus()
			let wasOn = isReaderModeOn
			isReaderModeOn = false
			ArticleReadingStateStore.setReaderMode(false, for: readingStateKey)
			readerModeStateDidChange()
			if wasOn { startRendering(fullText: nil, scrollToTop: true) }
		} else {
			startFullTextFetch(rememberForArticle: true)
		}
	}

	/// - rememberForArticle: 手动打开才记到「这篇文章」上；因订阅源设置自动打开的不记，
	///   以免关掉订阅源开关后，那些文章仍各自记着全文。
	private func startFullTextFetch(rememberForArticle: Bool) {
		guard let url = article.url, fullTextTask == nil else { return }
		showStatus(Babel2Localization.text(.fetchingFullText), autoHide: false)
		let provider = fullTextProvider
		let host: UIView = view
		fullTextTask = Task { @MainActor [weak self] in
			do {
				let html = try await provider(url, host)
				guard !Task.isCancelled, let self else { return }
				self.fullTextTask = nil
				self.fullTextHTML = html
				self.isReaderModeOn = true
				if rememberForArticle {
					ArticleReadingStateStore.setReaderMode(true, for: self.readingStateKey)
				}
				self.readerModeStateDidChange()
				self.hideStatus()
				self.startRendering(fullText: html, scrollToTop: true)
			} catch {
				guard !Task.isCancelled, let self else { return }
				self.fullTextTask = nil
				self.isReaderModeOn = false
				if rememberForArticle {
					ArticleReadingStateStore.setReaderMode(false, for: self.readingStateKey)
				}
				self.readerModeStateDidChange()
				self.showStatus(Babel2Localization.text(.unableToFetchFullText), autoHide: true)
			}
		}
		readerModeStateDidChange()
	}

	/// 阅读模式开关状态变化后，同步底栏按钮与 ••• 菜单。
	private func readerModeStateDidChange() {
		toolbar.setReaderMode(isReaderModeOn, available: article.url != nil)
		refreshMoreMenu()
	}

	private func scrollToTop() {
		let scrollView = contentView.scrollView
		scrollView.setContentOffset(CGPoint(x: 0, y: -scrollView.adjustedContentInset.top), animated: false)
	}

	/// 署名下方的一行浅灰状态字（不挡正文、不用系统转圈，ADR-019）。
	private func showStatus(_ text: String, autoHide: Bool) {
		statusHideTask?.cancel()
		statusLabel.attributedText = Self.metadata(text, kern: 0.25)
		statusLabel.isHidden = false
		relayoutHeader()
		guard autoHide else { return }
		statusHideTask = Task { @MainActor [weak self] in
			try? await Task.sleep(for: .seconds(3))
			guard !Task.isCancelled else { return }
			self?.hideStatus()
		}
	}

	private func hideStatus() {
		statusHideTask?.cancel()
		statusHideTask = nil
		guard !statusLabel.isHidden else { return }
		statusLabel.isHidden = true
		relayoutHeader()
	}

	private func relayoutHeader() {
		lastHeaderWidth = 0
		view.setNeedsLayout()
	}

	private func refreshMoreMenu() {
		moreButton?.menu = makeMoreMenu()
		moreButton?.isEnabled = moreButton?.menu?.children.isEmpty == false
	}

	/// 仅供自动化测试观察。
	var statusTextForTesting: String? { statusLabel.isHidden ? nil : statusLabel.text }
	var isFetchingFullTextForTesting: Bool { fullTextTask != nil }
	var moreMenuItemIdentifiers: [String] {
		moreButton?.menu?.children.compactMap { ($0 as? UIAction)?.identifier.rawValue } ?? []
	}
	var moreMenuFeedAlwaysReaderModeState: UIMenuElement.State? {
		(moreButton?.menu?.children.first { ($0 as? UIAction)?.identifier.rawValue == "babel2.article.feed-always-reading-mode" } as? UIAction)?.state
	}

	// MARK: - 翻译

	private func resolveTranslationHostArticle() {
		guard let hostArticleProvider else { return }
		let articleID = article.id
		Task { @MainActor [weak self] in
			let resolved = await hostArticleProvider(articleID)
			guard let self, self.article.id == articleID else { return }
			self.translationHostArticle = resolved
			self.prepareTranslationIfReady()
		}
	}

	/// 正文已排版、文章对象已取回，两者都齐了才启用翻译；
	/// 若这篇上次是以译文状态离开的、且有缓存，引擎会自动把译文放回来。
	private func prepareTranslationIfReady() {
		guard !isTranslationPrepared,
			translationHostArticle != nil,
			let result = lastRenderResult, !result.isEmpty else { return }
		isTranslationPrepared = true
		toolbar.setTranslationAvailable(true)
		translation.resetForNewArticle()
		translation.autoApplyTranslationFromCacheIfNeeded()
	}

	private func presentTranslationError(_ message: String) {
		let alert = UIAlertController(title: Babel2Localization.text(.translationFailed), message: message, preferredStyle: .alert)
		alert.addAction(UIAlertAction(title: Babel2Localization.text(.ok), style: .default))
		present(alert, animated: true)
	}

	/// 标题显示：nil = 原文标题；否则显示译文标题。大标题高度变了要重新让出正文空间。
	func applyDisplayedTitle(_ translated: String?) {
		let text = translated ?? article.title
		titleLabel.attributedText = Self.titleText(text)
		compactHeader.setArticleTitle(text)
		relayoutHeader()
	}

	/// 仅供自动化测试观察。
	var translationController: TranslationController { translation }
	var isTranslationReadyForTesting: Bool { isTranslationPrepared }

	// MARK: - 顶栏

	/// 顶栏按 Figma「Navigation Bar / Reader」(18:15)：58pt，图标 24pt、次要灰，中心 y = 22。
	/// 左 ✕ 关闭（x=32）/ 正中 ••• 更多菜单（x=201）/ 右 系统分享（x=370）。
	/// 设计稿的「标签」按钮不放（无此功能，ADR-018）；「打开原文」在更多菜单里。
	private func configureTopBar() -> UIView {
		let bar = UIView()
		bar.backgroundColor = BabelPalette.background
		bar.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(bar)

		let close = makeBarButton(image: UIImage(named: "Babel2ReaderClose"), key: .back, identifier: "babel2.article.back")
		close.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
		let more = makeBarButton(image: UIImage(named: "Babel2ReaderMore"), key: .more, identifier: "babel2.article.more")
		more.menu = makeMoreMenu()
		more.showsMenuAsPrimaryAction = true
		more.isEnabled = more.menu?.children.isEmpty == false
		// 顶栏右上是普通系统分享（合同最新决定），设计稿无对应图标，用系统分享符号按同一灰度与视觉尺寸
		let shareImage = UIImage(systemName: "square.and.arrow.up", withConfiguration: UIImage.SymbolConfiguration(pointSize: 19, weight: .medium))
		let share = makeBarButton(image: shareImage, key: .share, identifier: "babel2.article.share")
		share.addTarget(self, action: #selector(shareTapped), for: .touchUpInside)
		[close, more, share].forEach(bar.addSubview)
		topButtons = [close, more, share]
		moreButton = more

		NSLayoutConstraint.activate([
			bar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			bar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			bar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
			bar.heightAnchor.constraint(equalToConstant: 58),
			close.centerXAnchor.constraint(equalTo: bar.leadingAnchor, constant: 32),
			more.centerXAnchor.constraint(equalTo: bar.centerXAnchor),
			share.centerXAnchor.constraint(equalTo: bar.trailingAnchor, constant: -32)
		] + [close, more, share].flatMap { button in [
			button.centerYAnchor.constraint(equalTo: bar.topAnchor, constant: 22),
			button.widthAnchor.constraint(equalToConstant: 44),
			button.heightAnchor.constraint(equalToConstant: 44)
		] })

		// 状态栏区域也保持不透明（合同：正文不得透到状态栏下面）。它压在顶栏之上，
		// 栏隐藏时顶栏向上收进它后面。
		let statusBackdrop = UIView()
		statusBackdrop.backgroundColor = BabelPalette.background
		statusBackdrop.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(statusBackdrop)
		NSLayoutConstraint.activate([
			statusBackdrop.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			statusBackdrop.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			statusBackdrop.topAnchor.constraint(equalTo: view.topAnchor),
			statusBackdrop.bottomAnchor.constraint(equalTo: bar.topAnchor)
		])
		topBar = bar
		return bar
	}

	/// 「•••」更多菜单（ADR-020）：此订阅源总是用阅读模式（带勾）/ 打开原文 / 生成长图（Slice 5 第 5 步前为灰色）。
	/// 阅读模式本身的开关在底栏第 4 格。没有原文地址时前两项不出现。
	private func makeMoreMenu() -> UIMenu {
		var actions = [UIMenuElement]()
		if article.url != nil, feedReaderModeSetting != nil {
			actions.append(UIAction(
				title: Babel2Localization.text(.feedAlwaysReadingMode),
				image: UIImage(named: "BabelReaderReadingMode"),
				identifier: UIAction.Identifier("babel2.article.feed-always-reading-mode"),
				state: isFeedAlwaysReaderMode ? .on : .off
			) { [weak self] _ in self?.toggleFeedAlwaysReaderMode() })
		}
		if article.url != nil {
			actions.append(UIAction(
				title: Babel2Localization.text(.openOriginal),
				image: UIImage(systemName: "safari"),
				identifier: UIAction.Identifier("babel2.article.open-original")
			) { [weak self] _ in self?.originalTapped() })
		}
		actions.append(UIAction(
			title: Babel2Localization.text(.longImage),
			image: UIImage(named: "BabelReaderShareLongImage"),
			identifier: UIAction.Identifier("babel2.article.long-image"),
			attributes: .disabled
		) { _ in })
		return UIMenu(children: actions)
	}

	private func makeBarButton(image: UIImage?, key: Babel2LocalizationKey, identifier: String) -> UIButton {
		let button = UIButton(type: .system)
		button.setImage(image?.withRenderingMode(.alwaysTemplate), for: .normal)
		button.tintColor = BabelPalette.mutedInk
		button.accessibilityLabel = Babel2Localization.text(key)
		button.accessibilityIdentifier = identifier
		button.translatesAutoresizingMaskIntoConstraints = false
		return button
	}

	/// 仅供自动化测试：更多菜单里有没有「打开原文」，以及直接触发它。
	var moreMenuHasOpenOriginal: Bool {
		moreButton?.menu?.children.contains { ($0 as? UIAction)?.identifier.rawValue == "babel2.article.open-original" } ?? false
	}
	func openOriginalFromMenuForTesting() { originalTapped() }

	@objc private func backTapped() { _ = (navigationController as? Babel2NavigationController)?.popBabel2(animated: true) }

	/// 打开原文：有内置浏览器就在里面打开（ADR-021），否则交给系统。
	@objc private func originalTapped() {
		guard let url = article.url else { return }
		if let browser = makeBrowser?(url) {
			pushBrowser(browser, animated: true)
		} else {
			onOpenOriginal?(url, article.title)
		}
	}

	/// 正文里的链接：同样优先在内置浏览器打开；mailto 等非网页链接交给系统。
	private func openLink(_ url: URL) {
		let isWeb = ["http", "https"].contains(url.scheme?.lowercased() ?? "")
		if isWeb, let browser = makeBrowser?(url) {
			pushBrowser(browser, animated: true)
		} else {
			onOpenLink?(url)
		}
	}

	private func pushBrowser(_ browser: UIViewController, animated: Bool) {
		(navigationController as? Babel2NavigationController)?.pushBabel2(browser, animated: animated)
	}

	/// 正文右边缘往左滑进入浏览器（只在有原文地址时安装）。
	private func installBrowserMotion() {
		guard let url = article.url, let makeBrowser else { return }
		let motion = Babel2ReaderBrowserMotion(reader: self, makeBrowser: { makeBrowser(url) })
		motion.onCommit = { [weak self] browser in self?.pushBrowser(browser, animated: false) }
		// 右边缘起手时，正文滚动让位给边缘手势（只影响从右边缘起手的触摸）
		contentView.scrollView.panGestureRecognizer.require(toFail: motion.edgeGesture)
		browserMotion = motion
	}

	/// 仅供自动化测试。
	var browserMotionForTesting: Babel2ReaderBrowserMotion? { browserMotion }
	func openLinkForTesting(_ url: URL) { openLink(url) }

	/// 顶部的普通系统分享（合同：顶部原长图位置改为普通分享；长图以后放底栏）。
	@objc private func shareTapped(_ sender: UIButton) {
		var items: [Any] = []
		if let url = article.url {
			items.append(url)
		} else {
			items.append(article.title)
		}
		let activity = UIActivityViewController(activityItems: items, applicationActivities: nil)
		activity.popoverPresentationController?.sourceView = sender
		activity.popoverPresentationController?.sourceRect = sender.bounds
		present(activity, animated: true)
	}

	// MARK: - 正文区与标题区

	private func configureContent(below topBar: UIView) {
		contentView.translatesAutoresizingMaskIntoConstraints = false
		view.insertSubview(contentView, belowSubview: topBar)
		NSLayoutConstraint.activate([
			contentView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			contentView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			contentView.topAnchor.constraint(equalTo: topBar.bottomAnchor),
			contentView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
		])
	}

	/// 标题区：日期（小号大写、浅灰）→ 标题（34pt 粗体）→ 订阅源名（小号大写、浅灰）。
	/// 数值来自 Figma Drafts/BATCH-01-SPEC.md「04 · Reader」。
	/// 标题区按 Figma 04A「Article Content」：日期 11pt 半粗（字距 0.3）→ 13pt → 标题 34pt 粗体
	/// （行高 38、字距 -1）→ 9pt → 署名两行「作者 / 订阅源」11pt 半粗（字距 0.25、行高 15）；
	/// 顶部留 26pt，署名下方 60pt 开始正文。
	private func configureHeader() {
		headerView.backgroundColor = BabelPalette.background
		headerView.accessibilityIdentifier = "babel2.article.header"

		dateLabel.attributedText = article.publishedAt.map { Self.metadata(Self.formatDate($0), kern: 0.3) }
		dateLabel.isHidden = article.publishedAt == nil
		dateLabel.numberOfLines = 1
		dateLabel.accessibilityIdentifier = "babel2.article.date"

		titleLabel.numberOfLines = 0
		titleLabel.accessibilityIdentifier = "babel2.article.title"
		titleLabel.accessibilityTraits = .header
		titleLabel.attributedText = Self.titleText(article.title)

		let bylineLines = [feedAuthor, feedTitle]
			.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
			.filter { !$0.isEmpty }
			.map { $0.uppercased() }
		bylineLabel.attributedText = Self.metadata(bylineLines.joined(separator: "\n"), kern: 0.25)
		bylineLabel.isHidden = bylineLines.isEmpty
		bylineLabel.numberOfLines = 0
		bylineLabel.accessibilityIdentifier = "babel2.article.byline"

		statusLabel.isHidden = true
		statusLabel.numberOfLines = 1
		statusLabel.accessibilityIdentifier = "babel2.article.status"

		let stack = UIStackView(arrangedSubviews: [dateLabel, titleLabel, bylineLabel, statusLabel])
		stack.axis = .vertical
		stack.alignment = .fill
		stack.setCustomSpacing(13, after: dateLabel)
		stack.setCustomSpacing(9, after: titleLabel)
		stack.setCustomSpacing(8, after: bylineLabel)
		stack.translatesAutoresizingMaskIntoConstraints = false
		headerView.addSubview(stack)
		NSLayoutConstraint.activate([
			stack.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 20),
			stack.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -20),
			stack.topAnchor.constraint(equalTo: headerView.topAnchor, constant: 26),
			stack.bottomAnchor.constraint(equalTo: headerView.bottomAnchor, constant: -60)
		])
		// 标题区挂在正文滚动区里、位于正文上方（负坐标），跟正文一起滚动
		contentView.scrollView.addSubview(headerView)
	}

	/// 日期 / 署名：11pt 半粗、浅灰、行高 15。
	private static func metadata(_ text: String, kern: CGFloat) -> NSAttributedString {
		let paragraph = NSMutableParagraphStyle()
		paragraph.minimumLineHeight = 15
		paragraph.maximumLineHeight = 15
		return NSAttributedString(string: text, attributes: [
			.font: UIFont.systemFont(ofSize: 11, weight: .semibold),
			.foregroundColor: BabelPalette.tertiaryInk,
			.kern: kern,
			.paragraphStyle: paragraph
		])
	}

	/// 大标题：34pt 粗体、主墨色、行高 38、字距 -1。
	private static func titleText(_ text: String) -> NSAttributedString {
		let paragraph = NSMutableParagraphStyle()
		paragraph.minimumLineHeight = 38
		paragraph.maximumLineHeight = 38
		return NSAttributedString(string: text, attributes: [
			.font: UIFont.systemFont(ofSize: 34, weight: .bold),
			.foregroundColor: BabelPalette.ink,
			.kern: -1,
			.paragraphStyle: paragraph
		])
	}

	/// 宽度变化时（首次布局、旋转）重新计算标题区高度，并把正文往下让出同样的高度。
	/// 只在宽度变化时做，不在滚动的每一帧做（合同：不得每帧改滚动区几何）。
	private func layoutHeaderIfNeeded() {
		let width = contentView.bounds.width
		guard width > 0, width != lastHeaderWidth else { return }
		lastHeaderWidth = width
		let fitting = headerView.systemLayoutSizeFitting(
			CGSize(width: width, height: 0),
			withHorizontalFittingPriority: .required,
			verticalFittingPriority: .fittingSizeLevel
		)
		let newHeight = ceil(fitting.height)
		let scrollView = contentView.scrollView
		let wasAtTop = scrollView.contentOffset.y <= -scrollView.adjustedContentInset.top + 1
		headerHeight = newHeight
		headerView.frame = CGRect(x: 0, y: -newHeight, width: width, height: newHeight)
		var inset = scrollView.contentInset
		if inset.top != newHeight {
			inset.top = newHeight
			scrollView.contentInset = inset
		}
		if wasAtTop {
			scrollView.contentOffset = CGPoint(x: 0, y: -scrollView.adjustedContentInset.top)
		}
		headerView.layoutIfNeeded()
		collapseStart = titleLabel.convert(titleLabel.bounds, to: headerView).minY
		layoutMessage()
		updateChrome()
	}

	// MARK: - 紧凑标题栏（滑动收缩）

	private func configureCompactHeader(below topBar: UIView) {
		compactHeader.translatesAutoresizingMaskIntoConstraints = false
		view.insertSubview(compactHeader, belowSubview: topBar)
		// 合同：紧凑栏与顶栏的空白内边距重叠 14pt（402×874 画布上紧凑栏从 y=103 开始）
		NSLayoutConstraint.activate([
			compactHeader.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			compactHeader.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			compactHeader.topAnchor.constraint(equalTo: topBar.bottomAnchor, constant: -14),
			compactHeader.heightAnchor.constraint(equalToConstant: 86)
		])
	}

	/// 当前的收缩规则（随正文长度变化而变化）。
	var chromeProgress: Babel2ReaderChromeProgress {
		let scrollView = contentView.scrollView
		let insets = scrollView.adjustedContentInset
		// 用正文的实际高度（而不是至少一屏高的网页文档高度）计算最多能读到哪；
		// 还没测到高度时视为不可收缩，紧凑栏不出现
		guard let articleHeight = contentView.articleHeight else {
			return Babel2ReaderChromeProgress(collapseStart: collapseStart, maxScroll: 0)
		}
		let maxScroll = articleHeight + insets.top + insets.bottom - scrollView.bounds.height
		return Babel2ReaderChromeProgress(collapseStart: collapseStart, maxScroll: maxScroll)
	}

	/// 已滚动距离：0 = 刚进文章的位置。
	private var scrolledDistance: CGFloat {
		let scrollView = contentView.scrollView
		return scrollView.contentOffset.y + scrollView.adjustedContentInset.top
	}

	/// 仅供自动化测试观察。
	var compactHeaderView: Babel2ReaderCompactHeaderView { compactHeader }

	/// 每次滚动 / 正文变长时调用：重算两个进度值交给紧凑栏重画，并更新顶/底栏显隐。
	private func updateChrome() {
		guard lastHeaderWidth > 0 else { return }
		let progress = chromeProgress
		let scrolled = scrolledDistance
		let pCollapse = progress.pCollapse(scrolled: scrolled)
		let pReading = progress.pReading(scrolled: scrolled)
		compactHeader.apply(pCollapse: pCollapse, pReading: pReading)
		// 先记收缩状态的打点，再处理顶/底栏（同一帧里「固定」发生在「栏开始跟手」之前）
		defer { updateBarVisibility(scrolled: scrolled, isPinned: pCollapse >= 1) }

		// 性能打点只在状态切换时记，不在每一帧记：
		// 进入「收缩中」= 区间开始；离开「收缩中」= 区间结束；
		// 一帧内直接从展开跳到固定（或反过来，例如快速甩动）= 单点事件，不留下不成对的区间
		let state = Babel2ReaderChromeProgress.state(pCollapse: pCollapse)
		guard state != chromeState else { return }
		let previous = chromeState
		chromeState = state
		let phase: MotionSignpostPhase = state == .collapsing ? .begin : (previous == .collapsing ? .end : .event)
		recordChrome(state: state, pCollapse: pCollapse, phase: phase)
	}

	private func recordChrome(state: MotionReaderChromeState, pCollapse: CGFloat, phase: MotionSignpostPhase) {
		motionRecorder.record(MotionSignpostEvent(
			payload: .readerChrome(MotionReaderChromePayload(
				state: state,
				pCollapse: MotionProgress(Double(pCollapse)),
				barP: MotionProgress(Double(barVisibility.barP))
			)),
			phase: phase
		))
	}

	// MARK: - 底部工具栏

	/// 仅供自动化测试观察。
	var toolbarView: Babel2ReaderToolbarView { toolbar }
	var barVisibilityProgress: CGFloat { barVisibility.barP }
	var topBarButtons: [UIButton] { topButtons }

	private func configureToolbar() {
		toolbar.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(toolbar)
		NSLayoutConstraint.activate([
			toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			toolbar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
			toolbar.heightAnchor.constraint(equalToConstant: Babel2ReaderToolbarView.height)
		])
		toolbar.setRead(isRead)
		toolbar.setStarred(isStarred)
		toolbar.onToggleRead = { [weak self] in self?.toggleRead() }
		toolbar.onTranslate = { [weak self] in self?.translation.toggle() }
		toolbar.onToggleReaderMode = { [weak self] in self?.toggleReaderMode() }
		toolbar.onNext = { [weak self] in self?.showNextArticle() }
		// 页面一建好就确定 ∨ 能不能点，滑入动画期间状态就是对的（出现后还会再刷新一次）
		refreshNextAvailability()
		toolbar.setReaderMode(false, available: article.url != nil)
		toolbar.onToggleStar = { [weak self] in self?.toggleStar() }
		// 手指离开屏幕时决定是否需要补完显隐（滚动区的代理归网页控件所有，这里只加监听）
		contentView.scrollView.panGestureRecognizer.addTarget(self, action: #selector(scrollPanChanged(_:)))
	}

	/// 正文底部让出底栏高度（系统已自动让出 Home 指示条那部分），最后几行不被挡住。
	/// 只在安全区变化时改一次，不在滚动中改。
	private func updateBottomInset() {
		let scrollView = contentView.scrollView
		let desired = max(Babel2ReaderToolbarView.height - view.safeAreaInsets.bottom, 0)
		guard scrollView.contentInset.bottom != desired else { return }
		var inset = scrollView.contentInset
		inset.bottom = desired
		scrollView.contentInset = inset
	}

	/// 已读 / 星标：调用现成的数据接口，成功后才切换按钮状态；请求进行中不重复发送。
	private func toggleRead() {
		let action: LibraryAction = isRead ? .markUnread(article.id) : .markRead(article.id)
		performStatusAction(action) { controller in
			controller.isRead.toggle()
			controller.toolbar.setRead(controller.isRead)
		}
	}

	private func toggleStar() {
		performStatusAction(.toggleStar(article.id)) { controller in
			controller.isStarred.toggle()
			controller.toolbar.setStarred(controller.isStarred)
		}
	}

	private func performStatusAction(_ action: LibraryAction, onSuccess: @escaping @MainActor (Babel2ArticleViewController) -> Void) {
		guard !isStatusRequestInFlight else { return }
		isStatusRequestInFlight = true
		let handler = environment.actionHandler
		Task { @MainActor [weak self] in
			do {
				try await handler.handle(action)
				guard let self else { return }
				self.isStatusRequestInFlight = false
				onSuccess(self)
			} catch {
				self?.isStatusRequestInFlight = false
			}
		}
	}

	// MARK: - 顶/底栏随上下滑显隐

	private func updateBarVisibility(scrolled: CGFloat, isPinned: Bool) {
		defer { lastScrolled = scrolled }
		guard let previous = lastScrolled else { return }
		let delta = scrolled - previous
		guard delta != 0 else { return }

		if !isPinned {
			// 没固定（包括回到顶部）：强制显示；若当前是隐藏着的，用 180ms 显示回来
			closeBarInterval(pCollapse: 0)
			if barVisibility.barP > 0 {
				let start = barVisibility.barP
				barVisibility.forceShown()
				animateBars(from: start, to: 0)
			}
			return
		}

		let scrollView = contentView.scrollView
		let physicalMax = scrollView.contentSize.height + scrollView.adjustedContentInset.bottom - scrollView.bounds.height
		let isBottomOverscroll = scrollView.contentOffset.y > physicalMax

		if let animator = barAnimator, animator.state == .active {
			// 补完动画进行中又开始滑：停在当前画面位置，从这里接着跟手（可中断、可反向）
			let current = barAnimationStart + (barAnimationTarget - barAnimationStart) * animator.fractionComplete
			animator.stopAnimation(true)
			barAnimator = nil
			barVisibility.settle(at: current)
			applyBars(current)
		}
		let before = barVisibility.barP
		barVisibility.update(delta: delta, isPinned: true, isBottomOverscroll: isBottomOverscroll)
		if barVisibility.isTracking && !isBarIntervalOpen {
			isBarIntervalOpen = true
			recordChrome(state: .controlsChanging, pCollapse: 1, phase: .begin)
		}
		if barVisibility.barP != before {
			applyBars(barVisibility.barP)
		}
		scheduleSettleIfIdle()
	}

	@objc private func scrollPanChanged(_ gesture: UIPanGestureRecognizer) {
		switch gesture.state {
		case .ended, .cancelled, .failed:
			// 此刻滚动区可能还标记为「手指按着」，所以这里不做那项检查
			scheduleSettleIfIdle(afterFingerLifted: true)
		default:
			settleTimer?.invalidate()
		}
	}

	/// 手指已离开且滚动停下约 0.12 秒后，把停在半路的栏补完到最近的一端。
	private func scheduleSettleIfIdle(afterFingerLifted: Bool = false) {
		settleTimer?.invalidate()
		guard afterFingerLifted || !contentView.scrollView.isTracking else { return }
		settleTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: false) { [weak self] _ in
			MainActor.assumeIsolated { self?.settleBars() }
		}
	}

	private func settleBars() {
		let target = barVisibility.settleTarget
		let start = barVisibility.barP
		barVisibility.settle(at: target)
		if start != target {
			animateBars(from: start, to: target)
		}
		closeBarInterval(pCollapse: 1)
	}

	/// 栏显隐区间：controlsChanging begin（开始跟手）↔ controlsChanging end（补完 / 被强制显示）。
	private func closeBarInterval(pCollapse: CGFloat) {
		guard isBarIntervalOpen else { return }
		isBarIntervalOpen = false
		recordChrome(state: .controlsChanging, pCollapse: pCollapse, phase: .end)
	}

	private func animateBars(from start: CGFloat, to target: CGFloat) {
		barAnimator?.stopAnimation(true)
		barAnimationStart = start
		barAnimationTarget = target
		let animator = UIViewPropertyAnimator(duration: Babel2ReaderBarVisibility.settleDuration, curve: .linear) { [weak self] in
			self?.applyBars(target)
		}
		animator.addCompletion { [weak self] position in
			guard position == .end else { return }
			self?.barAnimator = nil
		}
		barAnimator = animator
		animator.startAnimation()
	}

	/// 按 barP 画出顶栏与底栏：0 = 显示，1 = 隐藏（Figma 04D3，ADR-018 推翻原方案 A）。
	/// 顶部按钮行整行向上收进状态栏底色后面（按钮同时淡出），紧凑栏随之上移 44pt
	/// （= 顶栏 58 − 重叠 14）贴到状态栏正下方；底栏整条向下滑出并淡出。
	private func applyBars(_ barP: CGFloat) {
		let hidden = barP >= 0.5
		topBar?.transform = CGAffineTransform(translationX: 0, y: -58 * barP)
		compactHeader.transform = CGAffineTransform(translationX: 0, y: -44 * barP)
		for button in topButtons {
			button.alpha = 1 - barP
			button.isUserInteractionEnabled = !hidden
		}
		toolbar.alpha = 1 - barP
		toolbar.transform = CGAffineTransform(translationX: 0, y: Babel2ReaderToolbarView.height * barP)
		toolbar.isUserInteractionEnabled = !hidden
	}

	// MARK: - 错误 / 无正文提示

	private func configureMessage() {
		messageLabel.font = .preferredFont(forTextStyle: .body)
		messageLabel.textColor = BabelPalette.mutedInk
		messageLabel.numberOfLines = 0
		messageLabel.accessibilityIdentifier = "babel2.article.message"
		var retryConfiguration = UIButton.Configuration.plain()
		retryConfiguration.title = Babel2Localization.text(.retry)
		retryConfiguration.baseForegroundColor = BabelPalette.ink
		retryConfiguration.contentInsets = .zero
		retryButton.configuration = retryConfiguration
		retryButton.contentHorizontalAlignment = .leading
		retryButton.accessibilityIdentifier = "babel2.article.retry"
		retryButton.addTarget(self, action: #selector(retryTapped), for: .touchUpInside)
		messageStack.axis = .vertical
		messageStack.alignment = .leading
		messageStack.spacing = 8
		messageStack.addArrangedSubview(messageLabel)
		messageStack.addArrangedSubview(retryButton)
		messageStack.isHidden = true
		// 提示放在标题区正下方（正文开始的位置），标题照常显示
		contentView.scrollView.addSubview(messageStack)
	}

	private func layoutMessage() {
		let width = max(lastHeaderWidth - 40, 0)
		let size = messageStack.systemLayoutSizeFitting(
			CGSize(width: width, height: 0),
			withHorizontalFittingPriority: .required,
			verticalFittingPriority: .fittingSizeLevel
		)
		messageStack.frame = CGRect(x: 20, y: 0, width: width, height: ceil(size.height))
	}

	private func showMessage(_ text: String, allowsRetry: Bool) {
		messageLabel.text = text
		retryButton.isHidden = !allowsRetry
		messageStack.isHidden = false
		layoutMessage()
	}

	private func hideMessage() {
		messageStack.isHidden = true
	}

	private static func formatDate(_ date: Date) -> String {
		let formatter = DateFormatter()
		formatter.dateStyle = .medium
		formatter.timeStyle = .short
		return formatter.string(from: date).uppercased()
	}
}
