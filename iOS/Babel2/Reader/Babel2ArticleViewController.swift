import Foundation
import UIKit
import Babel2Core
import Babel2UI

/// Babel 2.0 阅读页（Slice 4：第 1 步静态图文页 + 第 2 步滑动收缩）。
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

	/// 仅供自动化测试观察。
	var readerContentView: Babel2ReaderContentView { contentView }
	private(set) var lastRenderResult: Babel2ReaderContentView.RenderResult?

	init(
		article: ArticleSnapshot,
		environment: AppEnvironment,
		feedTitle: String? = nil,
		feedIconData: Data? = nil,
		motionRecorder: any Babel2MotionRecording = Babel2OSLogMotionRecorder()
	) {
		self.article = article
		self.environment = environment
		self.feedTitle = feedTitle
		self.motionRecorder = motionRecorder
		compactHeader = Babel2ReaderCompactHeaderView(feedTitle: feedTitle, articleTitle: article.title, iconData: feedIconData)
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
		configureHeader()
		configureMessage()
		contentView.onScrollGeometryChange = { [weak self] in
			self?.updateChrome()
		}
		contentView.onLinkActivated = { [weak self] url in
			self?.onOpenLink?(url)
		}
		contentView.onContentProcessTerminated = { [weak self] in
			self?.cancelRendering()
			self?.showMessage(Babel2Localization.text(.unableToLoadArticle), allowsRetry: true)
		}
		startRendering()
	}

	override func viewDidLayoutSubviews() {
		super.viewDidLayoutSubviews()
		layoutHeaderIfNeeded()
	}

	override func viewDidDisappear(_ animated: Bool) {
		super.viewDidDisappear(animated)
		if isMovingFromParent { cancelRendering() }
	}

	deinit { renderTask?.cancel() }

	// MARK: - 正文加载

	private func startRendering() {
		cancelRendering()
		hideMessage()
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
				let rendered = try await renderer.render(article)
				// 过期保护：页面已关闭、已重试、或渲染结果不属于这篇文章 → 丢弃
				guard !Task.isCancelled,
					let self,
					self.renderGeneration == generation,
					self.article.id == articleID,
					rendered.articleID == articleID else { return }
				let result = await self.contentView.render(body: rendered.body, baseURL: article.url)
				guard !Task.isCancelled, self.renderGeneration == generation else { return }
				self.lastRenderResult = result
				if let result {
					if result.isEmpty {
						self.showMessage(Babel2Localization.text(.noArticleContent), allowsRetry: false)
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

	@objc private func retryTapped() { startRendering() }

	// MARK: - 顶栏

	private func configureTopBar() -> UIView {
		let bar = UIView()
		bar.backgroundColor = BabelPalette.background
		bar.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(bar)

		let back = makeBarButton(symbol: "chevron.left", key: .back, identifier: "babel2.article.back", action: #selector(backTapped))
		let original = makeBarButton(symbol: "safari", key: .openOriginal, identifier: "babel2.article.open-original", action: #selector(originalTapped))
		original.isHidden = article.url == nil
		let share = makeBarButton(symbol: "square.and.arrow.up", key: .share, identifier: "babel2.article.share", action: #selector(shareTapped))
		[back, original, share].forEach(bar.addSubview)

		// 按钮中心位置对应 402pt 设计稿的 x = 32（返回）/ 330（原文）/ 370（分享）
		NSLayoutConstraint.activate([
			bar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			bar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			bar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
			bar.heightAnchor.constraint(equalToConstant: 58),
			back.centerXAnchor.constraint(equalTo: bar.leadingAnchor, constant: 32),
			share.centerXAnchor.constraint(equalTo: bar.trailingAnchor, constant: -32),
			original.centerXAnchor.constraint(equalTo: bar.trailingAnchor, constant: -76)
		] + [back, original, share].flatMap { button in [
			button.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
			button.widthAnchor.constraint(equalToConstant: 44),
			button.heightAnchor.constraint(equalToConstant: 44)
		] })

		// 状态栏区域也保持不透明（合同：正文不得透到状态栏下面）
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
		return bar
	}

	private func makeBarButton(symbol: String, key: Babel2LocalizationKey, identifier: String, action: Selector) -> UIButton {
		let button = UIButton(type: .system)
		let configuration = UIImage.SymbolConfiguration(pointSize: 20, weight: .regular)
		button.setImage(UIImage(systemName: symbol, withConfiguration: configuration), for: .normal)
		button.tintColor = BabelPalette.ink
		button.accessibilityLabel = Babel2Localization.text(key)
		button.accessibilityIdentifier = identifier
		button.addTarget(self, action: action, for: .touchUpInside)
		button.translatesAutoresizingMaskIntoConstraints = false
		return button
	}

	@objc private func backTapped() { _ = (navigationController as? Babel2NavigationController)?.popBabel2(animated: true) }

	@objc private func originalTapped() {
		guard let url = article.url else { return }
		onOpenOriginal?(url, article.title)
	}

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
	private func configureHeader() {
		headerView.backgroundColor = BabelPalette.background
		headerView.accessibilityIdentifier = "babel2.article.header"

		dateLabel.text = article.publishedAt.map(Self.formatDate)
		dateLabel.isHidden = article.publishedAt == nil
		dateLabel.font = .systemFont(ofSize: 12, weight: .semibold)
		dateLabel.textColor = BabelPalette.tertiaryInk
		dateLabel.numberOfLines = 1
		dateLabel.accessibilityIdentifier = "babel2.article.date"

		let paragraph = NSMutableParagraphStyle()
		paragraph.minimumLineHeight = 40
		paragraph.maximumLineHeight = 40
		titleLabel.attributedText = NSAttributedString(string: article.title, attributes: [
			.font: UIFont.systemFont(ofSize: 34, weight: .bold),
			.foregroundColor: BabelPalette.ink,
			.paragraphStyle: paragraph
		])
		titleLabel.numberOfLines = 0
		titleLabel.accessibilityIdentifier = "babel2.article.title"
		titleLabel.accessibilityTraits = .header

		let trimmedFeedTitle = feedTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
		bylineLabel.text = trimmedFeedTitle.uppercased()
		bylineLabel.isHidden = trimmedFeedTitle.isEmpty
		bylineLabel.font = .systemFont(ofSize: 12, weight: .semibold)
		bylineLabel.textColor = BabelPalette.tertiaryInk
		bylineLabel.numberOfLines = 2
		bylineLabel.accessibilityIdentifier = "babel2.article.byline"

		let stack = UIStackView(arrangedSubviews: [dateLabel, titleLabel, bylineLabel])
		stack.axis = .vertical
		stack.alignment = .fill
		stack.spacing = 10
		stack.translatesAutoresizingMaskIntoConstraints = false
		headerView.addSubview(stack)
		NSLayoutConstraint.activate([
			stack.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 20),
			stack.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -20),
			stack.topAnchor.constraint(equalTo: headerView.topAnchor, constant: 8),
			stack.bottomAnchor.constraint(equalTo: headerView.bottomAnchor, constant: -24)
		])
		// 标题区挂在正文滚动区里、位于正文上方（负坐标），跟正文一起滚动
		contentView.scrollView.addSubview(headerView)
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

	/// 每次滚动 / 正文变长时调用：只重算两个进度值并交给紧凑栏重画。
	private func updateChrome() {
		guard lastHeaderWidth > 0 else { return }
		let progress = chromeProgress
		let scrolled = scrolledDistance
		let pCollapse = progress.pCollapse(scrolled: scrolled)
		let pReading = progress.pReading(scrolled: scrolled)
		compactHeader.apply(pCollapse: pCollapse, pReading: pReading)

		// 性能打点只在状态切换时记，不在每一帧记：
		// 进入「收缩中」= 区间开始；离开「收缩中」= 区间结束；
		// 一帧内直接从展开跳到固定（或反过来，例如快速甩动）= 单点事件，不留下不成对的区间
		let state = Babel2ReaderChromeProgress.state(pCollapse: pCollapse)
		guard state != chromeState else { return }
		let previous = chromeState
		chromeState = state
		let phase: MotionSignpostPhase = state == .collapsing ? .begin : (previous == .collapsing ? .end : .event)
		motionRecorder.record(MotionSignpostEvent(
			payload: .readerChrome(MotionReaderChromePayload(
				state: state,
				pCollapse: MotionProgress(Double(pCollapse)),
				barP: MotionProgress(0)
			)),
			phase: phase
		))
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
