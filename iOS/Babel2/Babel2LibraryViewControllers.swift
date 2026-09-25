import Foundation
import ImageIO
import UIKit
import Babel2Core

/// 文章列表的标题翻译开关（按订阅源；读写与请求由装配层注入，页面不直接碰翻译引擎或账户数据）。ADR-024。
struct Babel2TitleTranslationSetting {
	let isEnabled: @MainActor () -> Bool
	let setEnabled: @MainActor (Bool) -> Void
	/// 把这些文章的标题交给翻译引擎（已有译文 / 本来是中文的由引擎跳过）。
	let request: @MainActor ([ArticleSnapshot.ID]) -> Void
}

/// 文章列表页顶部大图的图片来源（订阅源高清图标；读取与下载由装配层注入，页面不碰账户数据）。ADR-027。
struct Babel2FeedHeroImageSource {
	/// 已有缓存（内存 / 磁盘），不触发网络；没有返回 nil。
	let cached: @MainActor () -> UIImage?
	/// 需要时去抓；抓到更好的一张时回调（可能不回调）。
	let fetch: @MainActor (@escaping @MainActor (UIImage) -> Void) -> Void
}

@MainActor
final class Babel2FeedViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
	private enum LoadState: String {
		case loading
		case loaded
		case empty
		case error
	}

	private let feed: FeedSnapshot
	private(set) var scope: Babel2FeedScope
	private let environment: AppEnvironment
	private let tableView = UITableView(frame: .zero, style: .plain)
	private let emptyLabel = UILabel()
	private let countLabel = UILabel()
	private let retryButton = UIButton(type: .system)
	private var articles = [ArticleSnapshot]()
	/// 按天分段（Reeder 式日期分组，2026-09-25）：每段是 articles 里连续的一截，不改文章顺序。
	private var daySections = [Babel2DaySection]()
	/// 订阅源图标只解码一次，所有行共用。
	private lazy var feedIconImage: UIImage? = feed.iconData.flatMap(UIImage.init(data:))
	private var loadTask: Task<Void, Never>?
	private var loadGeneration = UUID()
	private var loadState: LoadState = .loading
	private var statusRefreshTimer: Timer?
	private var statusRefreshTask: Task<Void, Never>?
	var onSelectArticle: ((ArticleSnapshot) -> Void)?
	/// 用户在本页底栏切了档位：档位是全局的，由装配层同步给首页（ADR-023）。
	var onScopeChanged: ((Babel2FeedScope) -> Void)?
	private let bottomToolbar = UIView()
	private lazy var scopeFilter = Babel2ScopeFilterControl(selectedScope: scope)
	private let readAllButton = UIButton(type: .system)
	private let titleTranslationToggle = Babel2TranslationToggle()
	private weak var headerTitleLabel: UILabel?
	private weak var heroView: Babel2FeedHeroView?
	private weak var compactBar: Babel2FeedCompactBar?
	/// 仅供自动化测试观察。
	var compactBarForTesting: Babel2FeedCompactBar? { compactBar }
	var heroProgressForTesting: CGFloat { heroProgress }
	private var heroProgress: CGFloat = 0
	private let heroImage: Babel2FeedHeroImageSource?
	/// 仅供自动化测试观察。
	var heroViewForTesting: Babel2FeedHeroView? { heroView }

	private let titleTranslation: Babel2TitleTranslationSetting?
	private var titleTranslationTimeout: Task<Void, Never>?

	/// 设置「全部标为已读前确认」（Slice 6）；关掉时点底栏按钮直接标记。
	private let shouldConfirmMarkAllRead: @MainActor () -> Bool

	init(feed: FeedSnapshot, scope: Babel2FeedScope = .all, environment: AppEnvironment, titleTranslation: Babel2TitleTranslationSetting? = nil, heroImage: Babel2FeedHeroImageSource? = nil, confirmMarkAllRead: @escaping @MainActor () -> Bool = { true }) {
		self.shouldConfirmMarkAllRead = confirmMarkAllRead
		self.feed = feed
		self.scope = scope
		self.environment = environment
		self.titleTranslation = titleTranslation
		self.heroImage = heroImage
		super.init(nibName: nil, bundle: nil)
		restorationIdentifier = "babel2.feed.\(feed.id.accountID).\(feed.id.feedID)"
		// 已读/星标等状态变化（阅读页操作、后台同步）时，原地刷新每一行的状态
		NotificationCenter.default.addObserver(self, selector: #selector(libraryDidChange(_:)), name: .babel2LibraryDidChange, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(titleTranslationDidChange(_:)), name: .babel2TitleTranslationDidChange, object: nil)
	}

	required init?(coder: NSCoder) { nil }

	override func viewDidLoad() {
		super.viewDidLoad()
		view.backgroundColor = BabelPalette.background
		configureHeader()
		configureToolbar()
		configureTable()
		startLoading()
	}

	override func viewDidDisappear(_ animated: Bool) {
		super.viewDidDisappear(animated)
		if isMovingFromParent {
			cancelLoading()
			statusRefreshTimer?.invalidate()
			statusRefreshTask?.cancel()
			titleTranslationTimeout?.cancel()
		}
	}

	deinit {
		loadTask?.cancel()
		statusRefreshTask?.cancel()
	}

	// MARK: - 状态原地刷新

	/// 同步时通知会一串串地来：攒 0.3 秒再统一刷新一次。
	@objc private func libraryDidChange(_ notification: Notification) {
		statusRefreshTimer?.invalidate()
		statusRefreshTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
			MainActor.assumeIsolated { self?.refreshStatusesInPlace() }
		}
	}

	/// 重新读取这个订阅源所有文章的最新状态，只替换已显示的行（用户 2026-09-24 选定方案 A）：
	/// 不增删行、不改顺序、不动滚动位置、不显示加载中。例如「未读」档里刚读完的文章
	/// 仍留在列表里、只是标题变细，离开再进来才按新状态筛选。
	private func refreshStatusesInPlace() {
		guard loadState == .loaded, !articles.isEmpty else { return }
		statusRefreshTask?.cancel()
		let provider = environment.dataProvider
		let feedID = feed.id
		let generation = loadGeneration
		statusRefreshTask = Task { @MainActor [weak self, provider, feedID, generation] in
			guard let fresh = try? await provider.feedArticlesSnapshot(for: feedID, scope: .all),
				!Task.isCancelled,
				let self,
				self.loadGeneration == generation,
				self.loadState == .loaded else { return }
			let freshByID = Dictionary(fresh.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
			var changedRows = [IndexPath]()
			for (index, article) in self.articles.enumerated() {
				guard let updated = freshByID[article.id], updated != article else { continue }
				self.articles[index] = updated
				if let indexPath = self.indexPath(forArticleAt: index) { changedRows.append(indexPath) }
			}
			let visible = Set(self.tableView.indexPathsForVisibleRows ?? [])
			let visibleChanged = changedRows.filter { visible.contains($0) }
			if !visibleChanged.isEmpty {
				UIView.performWithoutAnimation {
					self.tableView.reloadRows(at: visibleChanged, with: .none)
				}
			}
		}
	}

	/// 仅供自动化测试观察。
	var articlesForTesting: [ArticleSnapshot] { articles }
	var daySectionTitlesForTesting: [String?] { daySections.map(\.title) }

	// MARK: - 按天分段

	/// 文章换了一批（加载完成 / 出错清空）后重新分段。
	private func rebuildDaySections() {
		daySections = Babel2DaySection.make(for: articles.map(\.publishedAt))
	}

	private func articleIndex(for indexPath: IndexPath) -> Int? {
		guard indexPath.section < daySections.count else { return nil }
		let range = daySections[indexPath.section].range
		let index = range.lowerBound + indexPath.row
		return range.contains(index) ? index : nil
	}

	private func indexPath(forArticleAt index: Int) -> IndexPath? {
		guard let section = daySections.firstIndex(where: { $0.range.contains(index) }) else { return nil }
		return IndexPath(row: index - daySections[section].range.lowerBound, section: section)
	}

	// MARK: - 底栏（Figma Feed Toolbar，ADR-023）

	/// 72pt 底栏：全部标为已读（x=32）/ 星标·未读·全部（x=104/201/290.5）/ 标题翻译开关（x=362，下一步接通前为灰色）。
	private func configureToolbar() {
		bottomToolbar.backgroundColor = BabelPalette.background
		bottomToolbar.accessibilityIdentifier = "babel2.feed.toolbar"
		bottomToolbar.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(bottomToolbar)
		let separator = UIView()
		separator.backgroundColor = BabelPalette.hairline
		separator.translatesAutoresizingMaskIntoConstraints = false
		bottomToolbar.addSubview(separator)

		// 档位条铺满整条底栏；左右两个按钮后加，叠在它上面才能点到
		scopeFilter.onSelect = { [weak self] scope in self?.selectScope(scope, fromUser: true) }
		scopeFilter.translatesAutoresizingMaskIntoConstraints = false
		bottomToolbar.addSubview(scopeFilter)

		readAllButton.setImage(UIImage(named: "Babel2FeedReadAll")?.withRenderingMode(.alwaysTemplate), for: .normal)
		readAllButton.tintColor = BabelPalette.mutedInk
		readAllButton.accessibilityLabel = Babel2Localization.text(.markAllRead)
		readAllButton.accessibilityIdentifier = "babel2.feed.read-all"
		readAllButton.addTarget(self, action: #selector(readAllTapped), for: .touchUpInside)
		readAllButton.translatesAutoresizingMaskIntoConstraints = false
		bottomToolbar.addSubview(readAllButton)

		titleTranslationToggle.isEnabled = titleTranslation != nil
		titleTranslationToggle.setState(titleTranslation?.isEnabled() == true ? .translated : .original)
		titleTranslationToggle.addTarget(self, action: #selector(titleTranslationTapped), for: .touchUpInside)
		titleTranslationToggle.accessibilityIdentifier = "babel2.feed.title-translation"
		titleTranslationToggle.translatesAutoresizingMaskIntoConstraints = false
		bottomToolbar.addSubview(titleTranslationToggle)

		NSLayoutConstraint.activate([
			bottomToolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			bottomToolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			bottomToolbar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
			bottomToolbar.heightAnchor.constraint(equalToConstant: 72),
			separator.leadingAnchor.constraint(equalTo: bottomToolbar.leadingAnchor),
			separator.trailingAnchor.constraint(equalTo: bottomToolbar.trailingAnchor),
			separator.topAnchor.constraint(equalTo: bottomToolbar.topAnchor),
			separator.heightAnchor.constraint(equalToConstant: 0.5),
			scopeFilter.leadingAnchor.constraint(equalTo: bottomToolbar.leadingAnchor),
			scopeFilter.trailingAnchor.constraint(equalTo: bottomToolbar.trailingAnchor),
			scopeFilter.topAnchor.constraint(equalTo: bottomToolbar.topAnchor),
			scopeFilter.bottomAnchor.constraint(equalTo: bottomToolbar.bottomAnchor),
			NSLayoutConstraint(item: readAllButton, attribute: .centerX, relatedBy: .equal, toItem: bottomToolbar, attribute: .trailing, multiplier: 32.0 / 402.0, constant: 0),
			readAllButton.centerYAnchor.constraint(equalTo: bottomToolbar.topAnchor, constant: 24),
			readAllButton.widthAnchor.constraint(equalToConstant: 44),
			readAllButton.heightAnchor.constraint(equalToConstant: 44),
			NSLayoutConstraint(item: titleTranslationToggle, attribute: .centerX, relatedBy: .equal, toItem: bottomToolbar, attribute: .trailing, multiplier: 362.0 / 402.0, constant: 0),
			titleTranslationToggle.centerYAnchor.constraint(equalTo: bottomToolbar.topAnchor, constant: 24),
			titleTranslationToggle.widthAnchor.constraint(equalToConstant: Babel2TranslationToggle.size.width),
			titleTranslationToggle.heightAnchor.constraint(equalToConstant: Babel2TranslationToggle.size.height)
		])
	}

	/// 切档位：原地换成新档位的文章并回到顶部（设计稿：不跳页、替换当前集合、回顶）。
	/// fromUser = 本页底栏点的，需要同步给首页；外部同步过来的不再回传。
	func selectScope(_ newScope: Babel2FeedScope, fromUser: Bool) {
		guard newScope != scope else { return }
		scope = newScope
		scopeFilter.setSelectedScope(newScope, animated: fromUser)
		headerTitleLabel?.accessibilityValue = newScope.rawValue
		tableView.setContentOffset(CGPoint(x: 0, y: -tableView.adjustedContentInset.top), animated: false)
		startLoading()
		if fromUser { onScopeChanged?(newScope) }
	}

	/// 全部标为已读：先数一下本订阅源有多少未读，确认后一次性批量标记，再重新加载列表。
	@objc private func readAllTapped() {
		let provider = environment.dataProvider
		let feedID = feed.id
		Task { @MainActor [weak self] in
			let count = (try? await provider.feedArticlesSnapshot(for: feedID, scope: .unread).count) ?? 0
			guard let self, count > 0 else { return }
			if self.shouldConfirmMarkAllRead() {
				self.confirmMarkAllRead(count: count)
			} else {
				self.performMarkAllRead()
			}
		}
	}

	private func confirmMarkAllRead(count: Int) {
		let sheet = UIAlertController(
			title: nil,
			message: String(format: Babel2Localization.text(.markAllReadConfirm), count),
			preferredStyle: .actionSheet
		)
		sheet.addAction(UIAlertAction(title: Babel2Localization.text(.markAllRead), style: .default) { [weak self] _ in
			self?.performMarkAllRead()
		})
		sheet.addAction(UIAlertAction(title: Babel2Localization.text(.cancel), style: .cancel))
		sheet.popoverPresentationController?.sourceView = readAllButton
		sheet.popoverPresentationController?.sourceRect = readAllButton.bounds
		present(sheet, animated: true)
		pendingMarkAllReadCountForTesting = count
	}

	private func performMarkAllRead() {
		let handler = environment.actionHandler
		let feedID = feed.id
		Task { @MainActor [weak self] in
			try? await handler.handle(.markFeedRead(feedID))
			self?.startLoading()
		}
	}

	// MARK: - 标题翻译（ADR-024）

	/// 「原 翻译」开关：开 → 屏幕上的标题交给翻译引擎（显示「译 生成中」）；关 → 列表原地恢复原文。
	@objc private func titleTranslationTapped() {
		guard let titleTranslation else { return }
		let newValue = !titleTranslation.isEnabled()
		titleTranslation.setEnabled(newValue)
		if newValue {
			requestVisibleTitleTranslations()
		} else {
			titleTranslationTimeout?.cancel()
			titleTranslationToggle.setState(.original)
		}
	}

	/// 只翻屏幕上看得到、还没有译文的标题（用户选的省钱方式）；滚动停下、列表加载完成时也会调用。
	private func requestVisibleTitleTranslations() {
		guard let titleTranslation, titleTranslation.isEnabled() else { return }
		let visible = (tableView.indexPathsForVisibleRows ?? []).compactMap { articleIndex(for: $0).map { articles[$0] } }
		let missing = visible.filter { $0.translatedTitle == nil && Self.mayNeedTranslation($0.title) }
		guard !missing.isEmpty else {
			titleTranslationToggle.setState(.translated)
			return
		}
		titleTranslationToggle.setState(.working)
		titleTranslation.request(missing.map(\.id))
		// 引擎失败时是静默的（不弹窗、不通知）：最多等 20 秒就把开关从「生成中」放回「译 原文」
		titleTranslationTimeout?.cancel()
		titleTranslationTimeout = Task { @MainActor [weak self] in
			try? await Task.sleep(for: .seconds(20))
			guard !Task.isCancelled, let self, self.titleTranslation?.isEnabled() == true else { return }
			self.titleTranslationToggle.setState(.translated)
		}
	}

	/// 含拉丁字母才可能需要翻（纯中文等标题引擎会跳过，不应让开关一直停在「生成中」）。
	private static func mayNeedTranslation(_ title: String) -> Bool {
		title.range(of: "[A-Za-z]", options: .regularExpression) != nil
	}

	/// 有译文入库或开关变了：原地刷新各行（沿用状态刷新那套：只重画变了的行，不跳位置）。
	@objc private func titleTranslationDidChange(_ notification: Notification) {
		libraryDidChange(notification)
		guard titleTranslation?.isEnabled() == true else { return }
		titleTranslationTimeout?.cancel()
		titleTranslationToggle.setState(.translated)
	}

	func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
		requestVisibleTitleTranslations()
	}

	func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
		if !decelerate { requestVisibleTitleTranslations() }
	}

	var titleTranslationToggleForTesting: Babel2TranslationToggle { titleTranslationToggle }
	func requestVisibleTitleTranslationsForTesting() { requestVisibleTitleTranslations() }

	/// 仅供自动化测试。
	private(set) var pendingMarkAllReadCountForTesting: Int?
	func confirmMarkAllReadForTesting() { performMarkAllRead() }
	var scopeFilterForTesting: Babel2ScopeFilterControl { scopeFilter }

	// MARK: - 下一篇（ADR-022）

	/// 按列表显示顺序，找这一篇之后的下一篇；「未读」档里跳过已经读过的（它们留在列表里只是变细）。
	/// 没有下一篇、或这一篇不在列表里时返回 nil。
	func nextArticle(after id: ArticleSnapshot.ID) -> ArticleSnapshot? {
		guard let index = articles.firstIndex(where: { $0.id == id }) else { return nil }
		return articles[(index + 1)...].first { scope != .unread || !$0.isRead }
	}

	/// 翻到某一篇后，让列表滚到它、保证返回时它在屏幕上（只做最小滚动）。
	func revealArticle(_ id: ArticleSnapshot.ID) {
		guard let index = articles.firstIndex(where: { $0.id == id }), let indexPath = indexPath(forArticleAt: index) else { return }
		tableView.scrollToRow(at: indexPath, at: .none, animated: false)
	}

	private func cancelLoading() {
		loadGeneration = UUID()
		loadTask?.cancel()
		loadTask = nil
	}

	private func startLoading() {
		loadGeneration = UUID()
		let generation = loadGeneration
		loadTask?.cancel()
		articles.removeAll(keepingCapacity: true)
		rebuildDaySections()
		tableView.reloadData()
		setCount(nil)
		setState(.loading)
		let provider = environment.dataProvider
		let feedID = feed.id
		let scope = self.scope
		loadTask = Task { @MainActor [weak self, provider, feedID, scope, generation] in
			defer {
				if let self, self.loadGeneration == generation {
					self.loadTask = nil
				}
			}
			do {
				let snapshot = try await provider.feedArticlesSnapshot(for: feedID, scope: scope)
				guard !Task.isCancelled, let self,
					self.loadGeneration == generation,
					self.feed.id == feedID,
					self.scope == scope else { return }
				self.articles = snapshot
				self.rebuildDaySections()
				self.setCount(self.articles.count)
				self.tableView.reloadData()
				self.setState(self.articles.isEmpty ? .empty : .loaded)
				// 列表排好后再看哪些行在屏幕上
				DispatchQueue.main.async { [weak self] in self?.requestVisibleTitleTranslations() }
			} catch is CancellationError {
				return
			} catch {
				guard !Task.isCancelled, let self,
					self.loadGeneration == generation,
					self.feed.id == feedID,
					self.scope == scope else { return }
				self.articles.removeAll(keepingCapacity: true)
				self.rebuildDaySections()
				self.tableView.reloadData()
				self.setCount(nil)
				self.setState(.error)
			}
		}
	}

	private func setState(_ state: LoadState) {
		loadState = state
		tableView.accessibilityValue = state.rawValue
		emptyLabel.accessibilityValue = state.rawValue
		switch state {
		case .loading:
			emptyLabel.text = Babel2Localization.text(.loading)
			emptyLabel.isHidden = false
			retryButton.isHidden = true
		case .loaded:
			emptyLabel.isHidden = true
			retryButton.isHidden = true
		case .empty:
			emptyLabel.text = Babel2Localization.text(.noArticles)
			emptyLabel.isHidden = false
			retryButton.isHidden = true
		case .error:
			emptyLabel.text = Babel2Localization.text(.unableToLoadArticles)
			emptyLabel.isHidden = false
			retryButton.isHidden = false
		}
	}

	/// 顶部大图（ADR-027）：从屏幕最顶端铺到安全区下方 169pt，标题 / 「N 篇」在里面；
	/// 上层是收缩后的窄栏（安全区 + 99pt，返回按钮在这层、全程不动）。随列表滚动跟手收缩（第 3 步）。
	private func configureHeader() {
		setCount(feed.articleCount)
		let hero = Babel2FeedHeroView(title: feed.title, countLabel: countLabel)
		hero.titleLabel.accessibilityValue = scope.rawValue
		headerTitleLabel = hero.titleLabel
		hero.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(hero)
		heroView = hero
		let compact = Babel2FeedCompactBar(title: feed.title, icon: feedIconImage)
		compact.backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
		compact.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(compact)
		compactBar = compact
		NSLayoutConstraint.activate([
			hero.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			hero.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			hero.topAnchor.constraint(equalTo: view.topAnchor),
			hero.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: Babel2FeedHeroView.expandedHeight),
			compact.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			compact.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			compact.topAnchor.constraint(equalTo: view.topAnchor),
			compact.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: Babel2FeedHeroMotion.compactHeight)
		])
		// 头图：有缓存立即铺上（不动画）；再请求一次，抓到更好的图时淡入替换
		if let heroImage {
			hero.setArt(heroImage.cached(), animated: false)
			heroImage.fetch { [weak hero] image in hero?.setArt(image, animated: true) }
		}
	}

	/// 文章数：屏幕上显示「N 篇」；辅助功能值保持纯数字（UI 自动测试按它核对行数）。
	private func setCount(_ count: Int?) {
		countLabel.text = count.map { String(format: Babel2Localization.text(.articleCount), $0) }
		countLabel.accessibilityValue = count.map(String.init)
		countLabel.isHidden = count == nil
	}

	private func configureTable() {
		tableView.backgroundColor = BabelPalette.background
		tableView.separatorStyle = .none
		tableView.rowHeight = UITableView.automaticDimension
		tableView.estimatedRowHeight = 100
		tableView.sectionHeaderTopPadding = 0
		tableView.sectionHeaderHeight = UITableView.automaticDimension
		tableView.estimatedSectionHeaderHeight = Babel2DayHeaderView.height
		tableView.register(Babel2DayHeaderView.self, forHeaderFooterViewReuseIdentifier: Babel2DayHeaderView.reuseIdentifier)
		tableView.dataSource = self
		tableView.delegate = self
		tableView.register(Babel2ArticleCell.self, forCellReuseIdentifier: Babel2ArticleCell.reuseIdentifier)
		tableView.accessibilityIdentifier = "babel2.feed.articles.table"
		tableView.translatesAutoresizingMaskIntoConstraints = false
		// 列表铺满全屏、压在大图与窄栏下面：顶部固定留出窄栏高度（系统再自动加上安全区），
		// 最上面垫 70pt 空白——静止时「窄栏 + 垫片」正好等于大图的 169pt。边距只设这一次，滚动中不改（MOTION-CONTRACT §11）。
		tableView.contentInset.top = Babel2FeedHeroMotion.compactHeight
		let spacer = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: Babel2FeedHeroMotion.collapseDistance))
		spacer.backgroundColor = .clear
		tableView.tableHeaderView = spacer
		view.insertSubview(tableView, at: 0)

		emptyLabel.text = Babel2Localization.text(.noArticles)
		emptyLabel.accessibilityIdentifier = "babel2.feed.articles.state"
		emptyLabel.accessibilityValue = LoadState.loading.rawValue
		emptyLabel.font = .systemFont(ofSize: 17, weight: .regular)
		emptyLabel.textColor = BabelPalette.mutedInk
		emptyLabel.textAlignment = .center
		emptyLabel.isHidden = true
		emptyLabel.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(emptyLabel)

		retryButton.configuration = .plain()
		retryButton.setTitle(Babel2Localization.text(.retry), for: .normal)
		retryButton.accessibilityIdentifier = "babel2.feed.articles.retry"
		retryButton.isHidden = true
		retryButton.translatesAutoresizingMaskIntoConstraints = false
		retryButton.addTarget(self, action: #selector(retryTapped), for: .touchUpInside)
		view.addSubview(retryButton)

		NSLayoutConstraint.activate([
			tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			tableView.topAnchor.constraint(equalTo: view.topAnchor),
			tableView.bottomAnchor.constraint(equalTo: bottomToolbar.topAnchor),
			emptyLabel.centerXAnchor.constraint(equalTo: tableView.centerXAnchor),
			emptyLabel.centerYAnchor.constraint(equalTo: tableView.centerYAnchor, constant: -20),
			retryButton.topAnchor.constraint(equalTo: emptyLabel.bottomAnchor, constant: 8),
			retryButton.centerXAnchor.constraint(equalTo: tableView.centerXAnchor),
			retryButton.heightAnchor.constraint(equalToConstant: 44),
			retryButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 44)
		])
	}

	@objc private func retryTapped() { startLoading() }

	@objc private func backTapped() { _ = (navigationController as? Babel2NavigationController)?.popBabel2(animated: true) }

	func numberOfSections(in tableView: UITableView) -> Int { daySections.count }

	func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		section < daySections.count ? daySections[section].range.count : 0
	}

	/// 日期段标题：今天 / 昨天 / 具体日期（跟随手机语言），滚动时吸在顶部。没有日期的那一段不显示标题。
	func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
		guard section < daySections.count, let title = daySections[section].title else { return nil }
		let header = tableView.dequeueReusableHeaderFooterView(withIdentifier: Babel2DayHeaderView.reuseIdentifier) as? Babel2DayHeaderView
		header?.configure(title: title)
		header?.setPinned(false)
		return header
	}

	func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
		guard section < daySections.count, daySections[section].title != nil else { return 0 }
		return Babel2DayHeaderView.height
	}

	/// 段标题吸在顶部时，下方显示一根细线（与参考截图一致）；在原位时不显示。
	func scrollViewDidScroll(_ scrollView: UIScrollView) {
		guard scrollView === tableView else { return }
		updateHeroProgress()
		let pinnedTop = tableView.contentOffset.y + tableView.adjustedContentInset.top
		for section in 0..<daySections.count {
			guard let header = tableView.headerView(forSection: section) as? Babel2DayHeaderView else { continue }
			let naturalTop = tableView.rect(forSection: section).minY
			header.setPinned(naturalTop < pinnedTop - 0.5 && header.frame.minY > naturalTop + 0.5)
		}
	}

	// MARK: - 顶部大图收缩（ADR-027 第 3 步）

	/// 按滚动位置更新大图与窄栏（只改平移与透明度）。
	private func updateHeroProgress() {
		let progress = Babel2FeedHeroMotion.progress(offsetY: tableView.contentOffset.y, restOffset: -tableView.adjustedContentInset.top)
		guard progress != heroProgress else { return }
		heroProgress = progress
		heroView?.apply(progress: progress)
		compactBar?.apply(progress: progress)
	}

	/// 松手后预计停在半路：改停到最近的一端（不到一半弹回展开，过半收到窄栏）。
	func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint, targetContentOffset: UnsafeMutablePointer<CGPoint>) {
		guard scrollView === tableView else { return }
		targetContentOffset.pointee.y = Babel2FeedHeroMotion.settledTargetOffset(
			proposed: targetContentOffset.pointee.y,
			restOffset: -tableView.adjustedContentInset.top
		)
	}

	func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		let cell = tableView.dequeueReusableCell(withIdentifier: Babel2ArticleCell.reuseIdentifier, for: indexPath) as! Babel2ArticleCell
		guard let index = articleIndex(for: indexPath) else { return cell }
		let article = articles[index]
		cell.configure(article: article, feedTitle: feed.title, feedIcon: feedIconImage, imageProvider: environment.imageProvider)
		cell.accessibilityIdentifier = "babel2.article.\(article.id.accountID).\(article.id.feedID).\(article.id.articleID)"
		return cell
	}

	func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		tableView.deselectRow(at: indexPath, animated: true)
		guard let index = articleIndex(for: indexPath) else { return }
		onSelectArticle?(articles[index])
	}
}

/// 按天分的一段：articles 里连续的一截（不改顺序）。title 为 nil 表示这些文章没有日期、不显示段标题。
struct Babel2DaySection: Equatable {
	let title: String?
	let range: Range<Int>

	/// 相邻、同一天的文章归为一段；日期文字跟随手机语言（英文按参考截图全大写）。
	static func make(for dates: [Date?], calendar: Calendar = .current, now: Date = Date()) -> [Babel2DaySection] {
		var sections = [Babel2DaySection]()
		var start = 0
		while start < dates.count {
			let day = dates[start].map { calendar.startOfDay(for: $0) }
			var end = start + 1
			while end < dates.count, dates[end].map({ calendar.startOfDay(for: $0) }) == day { end += 1 }
			sections.append(Babel2DaySection(title: day.map { title(for: $0, calendar: calendar, now: now) }, range: start..<end))
			start = end
		}
		return sections
	}

	/// 今天 / 昨天 用系统的相对说法，其余为完整日期（如 Wednesday, September 23, 2026 / 2026年9月23日 星期三）。
	static func title(for day: Date, calendar: Calendar = .current, now: Date = Date()) -> String {
		let formatter = DateFormatter()
		formatter.calendar = calendar
		formatter.timeZone = calendar.timeZone
		formatter.dateStyle = .full
		formatter.timeStyle = .none
		formatter.doesRelativeDateFormatting = true
		let text = formatter.string(from: day)
		return text.uppercased(with: formatter.locale)
	}
}

/// 日期段标题：14pt 中等粗细、墨色，与文字列左对齐（49pt）；吸顶时下方出现细线。
private final class Babel2DayHeaderView: UITableViewHeaderFooterView {
	static let reuseIdentifier = "Babel2DayHeaderView"
	static let height: CGFloat = 46

	private let label = UILabel()
	private let hairline = UIView()

	override init(reuseIdentifier: String?) {
		super.init(reuseIdentifier: reuseIdentifier)
		var background = UIBackgroundConfiguration.clear()
		background.backgroundColor = BabelPalette.background
		backgroundConfiguration = background
		label.font = .systemFont(ofSize: 14, weight: .medium)
		label.textColor = BabelPalette.ink
		label.accessibilityIdentifier = "babel2.feed.day-header"
		label.accessibilityTraits = .header
		label.translatesAutoresizingMaskIntoConstraints = false
		hairline.backgroundColor = BabelPalette.hairline
		hairline.isHidden = true
		hairline.translatesAutoresizingMaskIntoConstraints = false
		contentView.addSubview(label)
		contentView.addSubview(hairline)
		NSLayoutConstraint.activate([
			label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 49),
			label.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -20),
			label.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
			hairline.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 10),
			hairline.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -10),
			hairline.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
			hairline.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale)
		])
	}

	required init?(coder: NSCoder) { nil }

	func configure(title: String) {
		label.attributedText = NSAttributedString(string: title, attributes: [
			.font: UIFont.systemFont(ofSize: 14, weight: .medium),
			.foregroundColor: BabelPalette.ink,
			.kern: 0.3
		])
	}

	func setPinned(_ pinned: Bool) {
		hairline.isHidden = !pinned
	}

	var isPinnedForTesting: Bool { !hairline.isHidden }
}

/// 文章行（Reeder 式，2026-09-25 用户给参考截图）：
/// 左列 24pt 来源图标（与标题第一行居中）；文字列从 49pt 起：
/// 第一行 来源名（12pt 大写浅灰）…… 时间（13pt，贴右边缘）；
/// 标题 17pt 最多 2 行（未读加粗、已读常规）；摘要 17pt 浅灰 1 行；
/// 缩略图 70pt 在时间下方、顶部与标题齐平，文字在它左边折行。行间无分隔线，只靠留白。
private final class Babel2ArticleCell: UITableViewCell {
	static let reuseIdentifier = "Babel2ArticleCell"
	private static let thumbSide: CGFloat = 70
	private static let iconSide: CGFloat = 24
	private static let textLeading: CGFloat = 49
	private static let titleLineHeight: CGFloat = 22
	/// 标题字体（17pt 半粗）的大写字母高度，用来找第一行字的视觉中线。
	static let titleCapHeight = UIFont.systemFont(ofSize: 17, weight: .semibold).capHeight

	private let feedIconView = UIImageView()
	private let feedInitialLabel = UILabel()
	private let feedLabel = UILabel()
	private let dateLabel = UILabel()
	private let titleLabel = UILabel()
	private let summaryLabel = UILabel()
	private let thumbnailView = UIImageView()
	private var imageLoadTask: Task<Void, Never>?
	private var configuredArticleID: ArticleSnapshot.ID?

	private var titleToThumb: NSLayoutConstraint!
	private var titleToTrailing: NSLayoutConstraint!
	private var summaryToThumb: NSLayoutConstraint!
	private var summaryToTrailing: NSLayoutConstraint!
	/// 「行高至少容纳缩略图」：只在有缩略图时生效。隐藏的缩略图也会参与布局，若一直生效，
	/// 每行都被撑到 120pt，多出的高度分给标题、字被上下居中，与图标错位（2026-09-25 用户截图）。
	private var bottomBelowThumb: NSLayoutConstraint!

	override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
		super.init(style: style, reuseIdentifier: reuseIdentifier)
		backgroundColor = .clear
		contentView.backgroundColor = .clear
		selectionStyle = .default

		// 来源图标：24pt 圆角 5；没有图标时显示首字母方块（Figma 占位样式）
		feedIconView.contentMode = .scaleAspectFill
		feedIconView.clipsToBounds = true
		feedIconView.layer.cornerRadius = 5
		feedIconView.layer.cornerCurve = .continuous
		feedIconView.accessibilityIdentifier = "babel2.article.feed-icon"
		feedInitialLabel.font = .systemFont(ofSize: 13, weight: .semibold)
		feedInitialLabel.textColor = BabelPalette.mutedInk
		feedInitialLabel.textAlignment = .center

		// Figma「Article Row / Thumbnail」：70pt 见方、圆角 5、未加载时浅灰占位
		thumbnailView.contentMode = .scaleAspectFill
		thumbnailView.clipsToBounds = true
		thumbnailView.layer.cornerRadius = 5
		thumbnailView.layer.cornerCurve = .continuous
		thumbnailView.backgroundColor = Self.placeholderColor
		thumbnailView.accessibilityIdentifier = "babel2.article.thumbnail"
		thumbnailView.isHidden = true

		for view in [feedIconView, feedLabel, dateLabel, titleLabel, summaryLabel, thumbnailView] as [UIView] {
			view.translatesAutoresizingMaskIntoConstraints = false
			contentView.addSubview(view)
		}
		feedInitialLabel.translatesAutoresizingMaskIntoConstraints = false
		feedIconView.addSubview(feedInitialLabel)

		feedLabel.numberOfLines = 1
		feedLabel.lineBreakMode = .byTruncatingTail
		feedLabel.accessibilityIdentifier = "babel2.article.feed"
		feedLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

		dateLabel.textAlignment = .right
		dateLabel.accessibilityIdentifier = "babel2.article.date"
		dateLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
		dateLabel.setContentHuggingPriority(.required, for: .horizontal)

		titleLabel.numberOfLines = 2
		titleLabel.accessibilityIdentifier = "babel2.article.title"
		summaryLabel.numberOfLines = 1
		summaryLabel.accessibilityIdentifier = "babel2.article.summary"
		// 标题、摘要竖直方向不许被拉高：行高有富余时空白留在摘要下面，字不会被上下居中而与图标错位
		for label in [feedLabel, titleLabel, summaryLabel] {
			label.setContentHuggingPriority(.required, for: .vertical)
		}

		titleToThumb = titleLabel.trailingAnchor.constraint(equalTo: thumbnailView.leadingAnchor, constant: -12)
		titleToTrailing = titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20)
		summaryToThumb = summaryLabel.trailingAnchor.constraint(equalTo: thumbnailView.leadingAnchor, constant: -12)
		summaryToTrailing = summaryLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20)
		bottomBelowThumb = contentView.bottomAnchor.constraint(greaterThanOrEqualTo: thumbnailView.bottomAnchor, constant: 14)

		// 行高由内容决定：文字底 / 缩略图底，取较低者再留 14pt
		let textBottom = contentView.bottomAnchor.constraint(equalTo: summaryLabel.bottomAnchor, constant: 14)
		textBottom.priority = .defaultHigh

		NSLayoutConstraint.activate([
			feedLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Self.textLeading),
			feedLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),
			feedLabel.trailingAnchor.constraint(lessThanOrEqualTo: dateLabel.leadingAnchor, constant: -8),

			// 时间：第一行最右，贴屏幕边缘（有没有缩略图都一样）
			dateLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
			dateLabel.firstBaselineAnchor.constraint(equalTo: feedLabel.firstBaselineAnchor),

			titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Self.textLeading),
			titleLabel.topAnchor.constraint(equalTo: feedLabel.bottomAnchor, constant: 4),
			titleToTrailing,

			summaryLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
			summaryLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
			summaryToTrailing,

			// 来源图标与标题第一行的字对齐：图标中心 = 第一行基线往上半个大写字母高度（字的视觉中线），
			// 不用行框中心——字在行框里偏下，按行框居中会显得图标偏高（用户 2026-09-25）
			feedIconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
			feedIconView.centerYAnchor.constraint(equalTo: titleLabel.firstBaselineAnchor, constant: -Self.titleCapHeight / 2),
			feedIconView.widthAnchor.constraint(equalToConstant: Self.iconSide),
			feedIconView.heightAnchor.constraint(equalToConstant: Self.iconSide),
			feedInitialLabel.centerXAnchor.constraint(equalTo: feedIconView.centerXAnchor),
			feedInitialLabel.centerYAnchor.constraint(equalTo: feedIconView.centerYAnchor),

			// 缩略图：时间下方，顶部与标题齐平
			thumbnailView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
			thumbnailView.topAnchor.constraint(equalTo: titleLabel.topAnchor, constant: 3),
			thumbnailView.widthAnchor.constraint(equalToConstant: Self.thumbSide),
			thumbnailView.heightAnchor.constraint(equalToConstant: Self.thumbSide),
			contentView.bottomAnchor.constraint(greaterThanOrEqualTo: summaryLabel.bottomAnchor, constant: 14),
			textBottom
		])
	}

	required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

	override func prepareForReuse() {
		super.prepareForReuse()
		imageLoadTask?.cancel()
		imageLoadTask = nil
		configuredArticleID = nil
		thumbnailView.image = nil
		setThumbVisible(false)
		summaryLabel.attributedText = nil
		titleLabel.attributedText = nil
		dateLabel.attributedText = nil
	}

	func configure(article: ArticleSnapshot, feedTitle: String, feedIcon: UIImage?, imageProvider: any ImageProviding) {
		configuredArticleID = article.id
		// 开了标题翻译时直接显示译文（不再在标题下加「英文 → 简体中文」提示行，2026-09-25）
		let displayTitle = article.translatedTitle ?? article.title
		titleLabel.attributedText = Self.text(displayTitle, font: .systemFont(ofSize: 17, weight: article.isRead ? .regular : .semibold),
			color: BabelPalette.ink, lineHeight: Self.titleLineHeight, truncates: true)
		contentView.alpha = 1

		feedLabel.attributedText = Self.text(feedTitle.uppercased(), font: .systemFont(ofSize: 12, weight: .regular),
			color: BabelPalette.tertiaryInk, lineHeight: 15, kern: 0.3)
		feedIconView.image = feedIcon
		feedIconView.backgroundColor = feedIcon == nil ? Self.placeholderColor : .clear
		feedInitialLabel.text = feedIcon == nil ? feedTitle.first.map { String($0).uppercased() } : nil

		let plainSummary = Self.plainSummary(article.summary)
		summaryLabel.attributedText = plainSummary.isEmpty ? nil : Self.text(plainSummary, font: .systemFont(ofSize: 17, weight: .regular),
			color: BabelPalette.tertiaryInk, lineHeight: Self.titleLineHeight, truncates: true)

		// 已按天分组，每行只显示时刻
		let time = article.publishedAt.map { Self.timeFormatter.string(from: $0) } ?? ""
		dateLabel.attributedText = Self.text(time, font: .monospacedDigitSystemFont(ofSize: 13, weight: .regular),
			color: BabelPalette.ink, lineHeight: 15)
		accessibilityLabel = [feedTitle, displayTitle, plainSummary, time].filter { !$0.isEmpty }.joined(separator: ". ")

		imageLoadTask?.cancel()
		imageLoadTask = nil
		thumbnailView.image = nil

		guard let imageURL = article.imageURL else {
			setThumbVisible(false)
			return
		}
		setThumbVisible(true)
		// 缩好的小图在内存里有就直接用（来回滚动不重新下载、不闪）
		if let cached = Self.thumbnailCache.object(forKey: imageURL as NSURL) {
			showThumbnail(cached)
			return
		}
		thumbnailView.backgroundColor = Self.placeholderColor
		let articleID = article.id
		let maxPixels = Self.thumbSide * max(traitCollection.displayScale, 1)
		imageLoadTask = Task { @MainActor [weak self] in
			let data = try? await imageProvider.imageData(for: imageURL)
			// 原图常见 2000px 以上：按缩略图尺寸缩小后再解码，放到后台做，不卡滚动、不占大块内存
			let image: UIImage? = await Task.detached(priority: .utility) {
				data.flatMap { Self.downsampledImage(from: $0, maxPixels: maxPixels) }
			}.value
			guard let self, !Task.isCancelled, self.configuredArticleID == articleID else { return }
			if let image {
				Self.thumbnailCache.setObject(image, forKey: imageURL as NSURL)
				self.showThumbnail(image)
			} else {
				// 下载或解码失败：保持浅灰占位，版面不变
				self.thumbnailView.image = nil
				self.thumbnailView.backgroundColor = Self.placeholderColor
			}
		}
	}

	private func showThumbnail(_ image: UIImage) {
		thumbnailView.image = image
		thumbnailView.backgroundColor = .clear
	}

	private func setThumbVisible(_ visible: Bool) {
		thumbnailView.isHidden = !visible
		bottomBelowThumb.isActive = visible
		titleToThumb.isActive = visible
		summaryToThumb.isActive = visible
		titleToTrailing.isActive = !visible
		summaryToTrailing.isActive = !visible
	}

	/// 固定行高的文字（行距稳定，图标与缩略图才能按「第一行」对齐）。
	private static func text(_ string: String, font: UIFont, color: UIColor, lineHeight: CGFloat, kern: CGFloat = 0, truncates: Bool = false) -> NSAttributedString {
		let paragraph = NSMutableParagraphStyle()
		paragraph.minimumLineHeight = lineHeight
		paragraph.maximumLineHeight = lineHeight
		if truncates { paragraph.lineBreakMode = .byTruncatingTail }
		return NSAttributedString(string: string, attributes: [
			.font: font,
			.foregroundColor: color,
			.kern: kern,
			.paragraphStyle: paragraph,
			.baselineOffset: (lineHeight - font.lineHeight) / 4
		])
	}

	/// 未加载 / 加载失败时的占位色（Figma color/background/placeholder）。
	private static let placeholderColor = BabelPalette.hairline

	/// 缩好的缩略图（按图片地址）。系统内存紧张时会自动清掉一部分。
	private static let thumbnailCache: NSCache<NSURL, UIImage> = {
		let cache = NSCache<NSURL, UIImage>()
		cache.countLimit = 300
		return cache
	}()

	/// 只把图片解码到「最长边 maxPixels」的大小（不先解码整张原图）。
	nonisolated static func downsampledImage(from data: Data, maxPixels: CGFloat) -> UIImage? {
		let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
		guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
		let options = [
			kCGImageSourceCreateThumbnailFromImageAlways: true,
			kCGImageSourceCreateThumbnailWithTransform: true,
			kCGImageSourceShouldCacheImmediately: true,
			kCGImageSourceThumbnailMaxPixelSize: max(1, Int(maxPixels))
		] as CFDictionary
		guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
		return UIImage(cgImage: cgImage)
	}

	private static func plainSummary(_ raw: String) -> String {
		guard !raw.isEmpty else { return "" }
		var s = raw.replacingOccurrences(of: #"(?is)<(script|style)[^>]*>.*?</\1>"#, with: " ", options: .regularExpression)
		s = s.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
		s = s
			.replacingOccurrences(of: "&nbsp;", with: " ")
			.replacingOccurrences(of: "&amp;", with: "&")
			.replacingOccurrences(of: "&lt;", with: "<")
			.replacingOccurrences(of: "&gt;", with: ">")
			.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
			.trimmingCharacters(in: .whitespacesAndNewlines)
		if s == "Comments" { return "" }
		return s
	}

	private static let timeFormatter: DateFormatter = {
		let formatter = DateFormatter()
		formatter.dateStyle = .none
		formatter.timeStyle = .short
		return formatter
	}()
}
