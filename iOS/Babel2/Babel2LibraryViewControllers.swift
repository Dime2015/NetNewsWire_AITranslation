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

/// 大图上「刷新」「更多」的操作（ADR-031；读写与账户操作由装配层注入，页面不碰账户数据）。
struct Babel2FeedActions {
	/// 刷新所有账户（同步按账户进行，无法只刷新一个源）。
	let refresh: @MainActor () -> Void
	let isSyncing: @MainActor () -> Bool
	let homePageURL: @MainActor () -> URL?
	let feedURL: @MainActor () -> String?
	let isAlwaysReadingMode: @MainActor () -> Bool
	let setAlwaysReadingMode: @MainActor (Bool) -> Void
	let notificationsEnabled: @MainActor () -> Bool
	let setNotificationsEnabled: @MainActor (Bool) -> Void
	/// 失败返回说明。
	let rename: @MainActor (String) async -> String?
	/// 失败返回说明。
	let unsubscribe: @MainActor () async -> String?
	/// 打开网页（按设置：内置浏览器或系统浏览器）。
	let openURL: @MainActor (URL) -> Void
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
	/// 切档交叉淡入（ADR-034）：旧列表的截图、新列表进场方向、数据迟到时的兜底
	private var scopeFadeSnapshot: UIView?
	private var scopeFadeDirection: CGFloat = 1
	private var scopeFadeFallback: DispatchWorkItem?
	/// 首屏依次浮现只在第一次有文章时播一次
	private var hasPlayedEntrance = false
	/// 加载中的呼吸占位条（替代「加载中…」文字）
	private let skeleton = Babel2SkeletonView(style: .articleList, accessibilityText: Babel2Localization.text(.loading))
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
	private let feedActions: Babel2FeedActions?
	/// 大图标题（重命名后更新）。
	private var displayTitle: String
	/// 用户亲手点了刷新：同步结束时重新加载一次列表（后台自动同步不重载，避免列表突然跳动）。
	private var userRefreshTask: Task<Void, Never>?
	private var isShowingSync = false

	init(feed: FeedSnapshot, scope: Babel2FeedScope = .all, environment: AppEnvironment, titleTranslation: Babel2TitleTranslationSetting? = nil, heroImage: Babel2FeedHeroImageSource? = nil, confirmMarkAllRead: @escaping @MainActor () -> Bool = { true }, feedActions: Babel2FeedActions? = nil) {
		self.shouldConfirmMarkAllRead = confirmMarkAllRead
		self.feedActions = feedActions
		self.displayTitle = feed.title
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
		updateSyncState()
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
				// 读过后标题变细等：交叉淡入过渡，不瞬间跳（ADR-034）
				Babel2Motion.crossfade(self.tableView) {
					UIView.performWithoutAnimation {
						self.tableView.reloadRows(at: visibleChanged, with: .none)
					}
				}
			}
		}
	}

	/// 仅供自动化测试观察。
	var articlesForTesting: [ArticleSnapshot] { articles }
	var isScopeCrossfadingForTesting: Bool { scopeFadeSnapshot != nil }
	var isSkeletonShowingForTesting: Bool { skeleton.isShowing }
	var tableViewForTesting: UITableView { tableView }
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

	/// 72pt 底栏：全部标为已读（x=32）/ 星标·未读·全部（x=116.5/201/285.5）/ 标题翻译开关（x=370）。位置见 Babel2BarLayout。
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

		readAllButton.setImage(Babel2Type.icon(UIImage(named: "Babel2FeedReadAll"), side: Babel2Type.toolbarIcon), for: .normal)
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
		[readAllButton, titleTranslationToggle].forEach(Babel2Motion.addPressFeedback)

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
			Babel2BarLayout.centerX(readAllButton, in: bottomToolbar, slot: Babel2BarLayout.slots[0]),
			readAllButton.centerYAnchor.constraint(equalTo: bottomToolbar.topAnchor, constant: Babel2BarLayout.centerY),
			readAllButton.widthAnchor.constraint(equalToConstant: 44),
			readAllButton.heightAnchor.constraint(equalToConstant: 44),
			Babel2BarLayout.centerX(titleTranslationToggle, in: bottomToolbar, slot: Babel2BarLayout.slots[4]),
			titleTranslationToggle.centerYAnchor.constraint(equalTo: bottomToolbar.topAnchor, constant: Babel2BarLayout.centerY),
			titleTranslationToggle.widthAnchor.constraint(equalToConstant: Babel2TranslationToggle.size.width),
			titleTranslationToggle.heightAnchor.constraint(equalToConstant: Babel2TranslationToggle.size.height)
		])
	}

	/// 切档位：原地换成新档位的文章并回到顶部（设计稿：不跳页、替换当前集合、回顶）。
	/// fromUser = 本页底栏点的，需要同步给首页；外部同步过来的不再回传。
	func selectScope(_ newScope: Babel2FeedScope, fromUser: Bool) {
		guard newScope != scope else { return }
		let order = Babel2ScopeFilterControl.displayOrder
		let forward = (order.firstIndex(of: newScope) ?? 0) >= (order.firstIndex(of: scope) ?? 0)
		beginScopeCrossfade(direction: forward ? 1 : -1)
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

	/// 先确认「将 N 篇文章标为已读？」：全 app 统一的毛玻璃菜单，锚在底栏按钮上方；点空白处即取消。
	private func confirmMarkAllRead(count: Int) {
		Babel2GlassMenu.present(sections: [[
			Babel2MenuItem(title: Babel2Localization.text(.markAllRead), image: UIImage(named: "Babel2FeedReadAll"),
				identifier: "babel2.feed.read-all.confirm") { [weak self] in self?.performMarkAllRead() }
		]], title: String(format: Babel2Localization.text(.markAllReadConfirm), count), from: readAllButton, in: view)
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
				self.presentLoadedContent()
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
				self.finishScopeCrossfade()
			}
		}
	}

	// MARK: - 切档与首屏动效（ADR-034）

	/// 切档：先把旧列表拍一张截图盖在原位，新数据到了再交叉淡入并横向错开 12pt（减弱动态效果时只淡入），
	/// 不再出现「清空 → 加载中… → 出现」的闪白。不在屏幕上时（例如首页同步过来的切档）不做。
	private func beginScopeCrossfade(direction: CGFloat) {
		guard tableView.window != nil else { return }
		if scopeFadeSnapshot == nil {
			// 拍不到截图（极少见）就不做这个过渡，照旧直接换，绝不能把列表藏起来却没有东西盖着
			guard let snapshot = tableView.snapshotView(afterScreenUpdates: false) else { return }
			snapshot.frame = tableView.frame
			snapshot.isUserInteractionEnabled = false
			view.insertSubview(snapshot, aboveSubview: tableView)
			scopeFadeSnapshot = snapshot
		}
		scopeFadeDirection = direction
		tableView.layer.removeAllAnimations()
		tableView.alpha = 0
		tableView.transform = .identity
		emptyLabel.alpha = 0
		retryButton.alpha = 0
		// 数据迟迟不来：0.6 秒后照样淡过去，露出「加载中…」
		scopeFadeFallback?.cancel()
		let fallback = DispatchWorkItem { [weak self] in self?.finishScopeCrossfade() }
		scopeFadeFallback = fallback
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: fallback)
	}

	private func finishScopeCrossfade() {
		scopeFadeFallback?.cancel()
		scopeFadeFallback = nil
		guard let snapshot = scopeFadeSnapshot else { return }
		scopeFadeSnapshot = nil
		skeleton.setShowing(loadState == .loading)
		tableView.layoutIfNeeded()
		let shift = Babel2Motion.offset(Babel2Motion.shift) * scopeFadeDirection
		tableView.transform = CGAffineTransform(translationX: shift, y: 0)
		Babel2Motion.animate(Babel2Motion.standard, {
			snapshot.alpha = 0
			snapshot.transform = CGAffineTransform(translationX: -shift, y: 0)
			self.tableView.alpha = 1
			self.tableView.transform = .identity
			self.emptyLabel.alpha = 1
			self.retryButton.alpha = 1
		}, completion: { _ in snapshot.removeFromSuperview() })
	}

	/// 数据到了：切档中就交叉淡入；第一次有文章就让首屏各行依次浮现（每行间隔 0.02 秒，只播一次）。
	private func presentLoadedContent() {
		if scopeFadeSnapshot != nil {
			hasPlayedEntrance = true
			finishScopeCrossfade()
			return
		}
		guard !hasPlayedEntrance, !articles.isEmpty, tableView.window != nil else { return }
		hasPlayedEntrance = true
		tableView.layoutIfNeeded()
		let visible = tableView.bounds
		let headers: [UIView] = (0..<tableView.numberOfSections).compactMap { tableView.headerView(forSection: $0) }
		let views = (tableView.visibleCells as [UIView] + headers)
			.filter { $0.frame.intersects(visible) }
			.sorted { $0.frame.minY < $1.frame.minY }
		Babel2Motion.staggerIn(views)
	}

	private func setState(_ state: LoadState) {
		loadState = state
		// 切档交叉淡入期间旧列表还盖着，先不出占位条；淡入结束时若仍在加载再出
		skeleton.setShowing(state == .loading && scopeFadeSnapshot == nil)
		tableView.accessibilityValue = state.rawValue
		emptyLabel.accessibilityValue = state.rawValue
		switch state {
		case .loading:
			// 画面上用呼吸的占位条表示加载中（ADR-034）；文字留着给状态核对，但不显示
			emptyLabel.text = Babel2Localization.text(.loading)
			emptyLabel.isHidden = true
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
		compact.searchButton.addTarget(self, action: #selector(searchTapped), for: .touchUpInside)
		// 刷新与更多（ADR-031）：没有注入操作时不显示，不放点了没反应的按钮
		compact.refreshButton.isHidden = feedActions == nil
		compact.moreButton.isHidden = feedActions == nil
		compact.updateDiscVisibility()
		compact.refreshButton.addTarget(self, action: #selector(refreshTapped), for: .touchUpInside)
		compact.moreButton.addTarget(self, action: #selector(moreTapped), for: .touchUpInside)
		compact.searchField.onChange = { [weak self] query in self?.searchQueryChanged(query) }
		compact.searchField.onCancel = { [weak self] in self?.endSearch() }
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

	/// 文章数：屏幕上显示「N 篇」（同步中显示「正在同步…」）；辅助功能值保持纯数字（UI 自动测试按它核对行数）。
	private var shownCount: Int?

	private func setCount(_ count: Int?) {
		shownCount = count
		updateSubtitle()
	}

	private func updateSubtitle() {
		if isShowingSync {
			countLabel.text = Babel2Localization.text(.syncing)
			countLabel.isHidden = false
		} else {
			// 英文单复数：1 篇用单数（中文两者都是「N 篇」）
			countLabel.text = shownCount.map { String(format: Babel2Localization.text($0 == 1 ? .articleCountOne : .articleCount), $0) }
			countLabel.isHidden = shownCount == nil
		}
		countLabel.accessibilityValue = shownCount.map(String.init)
	}

	// MARK: - 刷新与更多（ADR-031）

	/// 同步开始 / 结束（账户刷新通知经首页数据层转来）：箭头旋转、副标题「正在同步…」。
	private func updateSyncState() {
		guard let feedActions else { return }
		let syncing = feedActions.isSyncing() || userRefreshTask != nil
		guard syncing != isShowingSync else { return }
		isShowingSync = syncing
		compactBar?.setSyncing(syncing)
		updateSubtitle()
	}

	@objc private func refreshTapped() {
		guard let feedActions, userRefreshTask == nil else { return }
		feedActions.refresh()
		// 同步结束（最多等 2 分钟）后重新加载一次，新文章出现在顶部
		userRefreshTask = Task { @MainActor [weak self] in
			try? await Task.sleep(for: .milliseconds(400))
			for _ in 0..<240 {
				guard self != nil, !Task.isCancelled else { return }
				if !feedActions.isSyncing() { break }
				try? await Task.sleep(for: .milliseconds(500))
			}
			guard let self, !Task.isCancelled else { return }
			self.userRefreshTask = nil
			self.updateSyncState()
			self.reloadKeepingPosition()
		}
		updateSyncState()
	}

	/// 重新读取当前档位的文章，保持滚动位置（在顶部时新文章直接可见）。搜索中不打扰。
	private func reloadKeepingPosition() {
		guard !isSearching else { return }
		let provider = environment.dataProvider
		let feedID = feed.id
		let scope = self.scope
		let generation = loadGeneration
		Task { @MainActor [weak self] in
			guard let snapshot = try? await provider.feedArticlesSnapshot(for: feedID, scope: scope),
				let self, self.loadGeneration == generation, self.scope == scope, !self.isSearching else { return }
			let offset = self.tableView.contentOffset
			let before = self.visibleRowPositions()
			let oldIDs = Set(self.articles.map(\.id))
			self.articles = snapshot
			self.rebuildDaySections()
			self.tableView.reloadData()
			self.tableView.layoutIfNeeded()
			self.tableView.setContentOffset(offset, animated: false)
			self.tableView.layoutIfNeeded()
			self.setCount(snapshot.count)
			self.setState(snapshot.isEmpty ? .empty : .loaded)
			self.animateRowsAfterRefresh(previousPositions: before, previousIDs: oldIDs)
		}
	}

	/// 屏幕上每篇文章所在行的顶边位置（刷新前记下，刷新后用来让原有的行平滑让位）。
	private func visibleRowPositions() -> [ArticleSnapshot.ID: CGFloat] {
		var positions = [ArticleSnapshot.ID: CGFloat]()
		for indexPath in tableView.indexPathsForVisibleRows ?? [] {
			guard let index = articleIndex(for: indexPath), index < articles.count,
				let cell = tableView.cellForRow(at: indexPath) else { continue }
			positions[articles[index].id] = cell.frame.minY
		}
		return positions
	}

	/// 刷新后（ADR-034）：原有的行从旧位置平滑移到新位置（往下让出空间），新文章从上方 8pt 淡入滑下。
	/// 只动 transform 与透明度，列表本身已经一次排好。
	private func animateRowsAfterRefresh(previousPositions: [ArticleSnapshot.ID: CGFloat], previousIDs: Set<ArticleSnapshot.ID>) {
		guard tableView.window != nil, !previousPositions.isEmpty else { return }
		for indexPath in tableView.indexPathsForVisibleRows ?? [] {
			guard let index = articleIndex(for: indexPath), index < articles.count,
				let cell = tableView.cellForRow(at: indexPath) else { continue }
			let id = articles[index].id
			if let oldY = previousPositions[id] {
				let delta = oldY - cell.frame.minY
				guard abs(delta) > 0.5 else { continue }
				cell.transform = CGAffineTransform(translationX: 0, y: Babel2Motion.offset(delta))
				Babel2Motion.animate(Babel2Motion.page) { cell.transform = .identity }
			} else if !previousIDs.contains(id) {
				cell.alpha = 0
				cell.transform = CGAffineTransform(translationX: 0, y: -Babel2Motion.offset(8))
				Babel2Motion.animate(Babel2Motion.page) {
					cell.alpha = 1
					cell.transform = .identity
				}
			}
		}
	}

	/// 「更多」：全 app 统一的毛玻璃菜单（2026-09-25 用户要求），每次打开时按当前状态生成（开关的勾永远准确）。
	@objc private func moreTapped() {
		guard let compactBar else { return }
		Babel2GlassMenu.present(sections: makeMoreMenuSections(), from: compactBar.moreButton, in: view)
	}

	private func makeMoreMenuSections() -> [[Babel2MenuItem]] {
		guard let feedActions else { return [] }
		var top = [Babel2MenuItem]()
		if let home = feedActions.homePageURL() {
			top.append(Babel2MenuItem(title: Babel2Localization.text(.openWebsite), image: UIImage(systemName: "safari"),
				identifier: "babel2.feed.more.website") { feedActions.openURL(home) })
		}
		if let address = feedActions.feedURL() {
			top.append(Babel2MenuItem(title: Babel2Localization.text(.copyFeedAddress), image: UIImage(systemName: "doc.on.doc"),
				identifier: "babel2.feed.more.copy") { UIPasteboard.general.string = address })
		}
		let toggles = [
			Babel2MenuItem(title: Babel2Localization.text(.feedAlwaysReadingMode), image: UIImage(systemName: "doc.plaintext"),
				identifier: "babel2.feed.more.reading-mode", isOn: feedActions.isAlwaysReadingMode()) {
				feedActions.setAlwaysReadingMode(!feedActions.isAlwaysReadingMode())
			},
			Babel2MenuItem(title: Babel2Localization.text(.newArticleNotifications), image: UIImage(systemName: "bell"),
				identifier: "babel2.feed.more.notifications", isOn: feedActions.notificationsEnabled()) {
				feedActions.setNotificationsEnabled(!feedActions.notificationsEnabled())
			}
		]
		let manage = [
			Babel2MenuItem(title: Babel2Localization.text(.rename), image: UIImage(systemName: "pencil"),
				identifier: "babel2.feed.more.rename") { [weak self] in self?.presentRename() },
			Babel2MenuItem(title: Babel2Localization.text(.unsubscribe), image: UIImage(systemName: "trash"),
				identifier: "babel2.feed.more.unsubscribe", isDestructive: true) { [weak self] in self?.confirmUnsubscribe() }
		]
		return [top, toggles, manage]
	}

	private func presentRename() {
		guard let feedActions else { return }
		let alert = UIAlertController(title: Babel2Localization.text(.renameFeed), message: nil, preferredStyle: .alert)
		alert.addTextField { [displayTitle] field in
			field.text = displayTitle
			field.clearButtonMode = .whileEditing
		}
		alert.addAction(UIAlertAction(title: Babel2Localization.text(.cancel), style: .cancel))
		alert.addAction(UIAlertAction(title: Babel2Localization.text(.ok), style: .default) { [weak self, weak alert] _ in
			let name = (alert?.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
			guard let self, !name.isEmpty, name != self.displayTitle else { return }
			Task { @MainActor [weak self] in
				if let message = await feedActions.rename(name) {
					self?.presentMessage(message)
				} else {
					self?.applyRenamedTitle(name)
				}
			}
		})
		present(alert, animated: true)
	}

	/// 重命名成功：大图标题、窄栏标题、文章行来源名同步更新。
	func applyRenamedTitle(_ name: String) {
		displayTitle = name
		heroView?.titleLabel.text = name
		compactBar?.titleLabel.text = name
		tableView.reloadData()
	}

	private func confirmUnsubscribe() {
		guard let feedActions else { return }
		let alert = UIAlertController(title: Babel2Localization.text(.unsubscribe),
			message: String(format: Babel2Localization.text(.unsubscribeConfirm), displayTitle), preferredStyle: .alert)
		alert.addAction(UIAlertAction(title: Babel2Localization.text(.cancel), style: .cancel))
		alert.addAction(UIAlertAction(title: Babel2Localization.text(.unsubscribe), style: .destructive) { [weak self] _ in
			Task { @MainActor [weak self] in
				if let message = await feedActions.unsubscribe() {
					self?.presentMessage(message)
				} else {
					self?.backTapped()
				}
			}
		})
		present(alert, animated: true)
	}

	private func presentMessage(_ message: String) {
		let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
		alert.addAction(UIAlertAction(title: Babel2Localization.text(.ok), style: .default))
		present(alert, animated: true)
	}

	/// 仅供自动化测试。
	var moreMenuSectionsForTesting: [[Babel2MenuItem]] { makeMoreMenuSections() }
	func refreshForTesting() { refreshTapped() }

	private func configureTable() {
		tableView.backgroundColor = BabelPalette.background
		tableView.separatorStyle = .none
		tableView.rowHeight = UITableView.automaticDimension
		tableView.estimatedRowHeight = 100
		// 搜索时拖动结果列表即收起键盘；键盘弹出时列表底部让出键盘高度，被挡住的结果也能滑上来
		tableView.keyboardDismissMode = .onDrag
		NotificationCenter.default.addObserver(self, selector: #selector(keyboardFrameChanged(_:)), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
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
		emptyLabel.font = .systemFont(ofSize: 15, weight: .regular)
		emptyLabel.textColor = BabelPalette.mutedInk
		emptyLabel.textAlignment = .center
		emptyLabel.isHidden = true
		emptyLabel.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(emptyLabel)
		// 占位条：在列表之上、大图之下，从第一行文章的位置开始
		skeleton.translatesAutoresizingMaskIntoConstraints = false
		view.insertSubview(skeleton, aboveSubview: tableView)
		NSLayoutConstraint.activate([
			skeleton.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			skeleton.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			skeleton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: Babel2FeedHeroView.expandedHeight + Babel2DayHeaderView.height),
			skeleton.heightAnchor.constraint(equalToConstant: 400)
		])

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

	// MARK: - 列表搜索（2026-09-25）

	/// 搜索中：原地把列表换成搜索结果（交互合同：在当前源原地搜索，取消恢复原列表与滚动位置）。
	private(set) var isSearching = false
	private var articlesBeforeSearch = [ArticleSnapshot]()
	private var offsetBeforeSearch: CGFloat = 0
	private var searchTask: Task<Void, Never>?
	/// 仅供自动化测试观察。
	var searchFieldForTesting: Babel2FeedSearchField? { compactBar?.searchField }

	@objc private func searchTapped() {
		guard !isSearching, let compactBar else { return }
		isSearching = true
		articlesBeforeSearch = articles
		offsetBeforeSearch = tableView.contentOffset.y
		// 大图收成窄栏、第二行换成搜索框；列表顶上 70pt 垫片暂时去掉，结果紧贴窄栏。
		// 整体交叉淡入过去（ADR-034），底栏往下滑出
		slideToolbar(out: true)
		Babel2Motion.crossfade(view) {
			self.heroView?.apply(progress: 1)
			compactBar.setSearching(true)
			self.setSpacerHeight(0)
			self.tableView.setContentOffset(CGPoint(x: 0, y: -self.tableView.adjustedContentInset.top), animated: false)
		}
		compactBar.searchField.textField.becomeFirstResponder()
	}

	/// 底栏滑出 / 滑回（减弱动态效果时只淡出淡入）。隐藏状态立即生效，动画只是视觉过渡。
	private func slideToolbar(out: Bool) {
		let distance = Babel2Motion.offset(bottomToolbar.bounds.height)
		guard bottomToolbar.window != nil else {
			bottomToolbar.isHidden = out
			return
		}
		if out {
			// 用一张底栏截图往下滑走，真正的底栏立即隐藏
			if let ghost = bottomToolbar.snapshotView(afterScreenUpdates: false) {
				ghost.frame = bottomToolbar.frame
				view.addSubview(ghost)
				Babel2Motion.animate(Babel2Motion.standard, {
					ghost.transform = CGAffineTransform(translationX: 0, y: distance)
					if distance == 0 { ghost.alpha = 0 }
				}, completion: { _ in ghost.removeFromSuperview() })
			}
			bottomToolbar.isHidden = true
		} else {
			bottomToolbar.isHidden = false
			bottomToolbar.transform = CGAffineTransform(translationX: 0, y: distance)
			bottomToolbar.alpha = distance == 0 ? 0 : 1
			Babel2Motion.animate(Babel2Motion.standard) {
				self.bottomToolbar.transform = .identity
				self.bottomToolbar.alpha = 1
			}
		}
	}

	/// 边打边搜：停止输入约 0.25 秒后搜索；空搜索框显示原列表。旧的搜索会被取消，只显示最新一次的结果。
	private func searchQueryChanged(_ query: String) {
		searchTask?.cancel()
		let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else {
			showSearchResults(articlesBeforeSearch, query: nil)
			return
		}
		let provider = environment.dataProvider
		let feedID = feed.id
		searchTask = Task { @MainActor [weak self] in
			try? await Task.sleep(for: .milliseconds(250))
			guard !Task.isCancelled else { return }
			do {
				let results = try await provider.searchFeedArticles(feedID, query: trimmed)
				guard !Task.isCancelled, let self, self.isSearching else { return }
				self.showSearchResults(results, query: trimmed)
			} catch {
				guard !Task.isCancelled, let self, self.isSearching, !(error is CancellationError) else { return }
				self.articles = []
				self.rebuildDaySections()
				self.tableView.reloadData()
				self.setState(.empty)
				self.emptyLabel.text = Babel2Localization.text(.searchFailed)
			}
		}
	}

	private func showSearchResults(_ results: [ArticleSnapshot], query: String?) {
		articles = results
		rebuildDaySections()
		tableView.reloadData()
		tableView.setContentOffset(CGPoint(x: 0, y: -tableView.adjustedContentInset.top), animated: false)
		if results.isEmpty, let query {
			setState(.empty)
			emptyLabel.text = String(format: Babel2Localization.text(.noSearchResults), query)
		} else {
			setState(results.isEmpty ? .empty : .loaded)
		}
		DispatchQueue.main.async { [weak self] in self?.requestVisibleTitleTranslations() }
	}

	/// 取消搜索：恢复原来的列表、档位、滚动位置与大图；并补一次状态刷新（搜索期间读过的文章变细）。
	func endSearch() {
		guard isSearching else { return }
		searchTask?.cancel()
		searchTask = nil
		isSearching = false
		// 交叉淡入回原来的列表与大图，底栏从下方滑回（ADR-034）
		Babel2Motion.crossfade(view) {
			self.compactBar?.setSearching(false)
			self.articles = self.articlesBeforeSearch
			self.rebuildDaySections()
			self.tableView.reloadData()
			self.setState(self.articles.isEmpty ? .empty : .loaded)
			self.setSpacerHeight(Babel2FeedHeroMotion.collapseDistance)
			self.tableView.layoutIfNeeded()
			self.tableView.setContentOffset(CGPoint(x: 0, y: self.offsetBeforeSearch), animated: false)
			self.heroProgress = -1
			self.updateHeroProgress()
		}
		slideToolbar(out: false)
		refreshStatusesInPlace()
	}

	/// 键盘与列表重叠的高度让出来（只在键盘变化时改一次底部边距，滚动中不改）。
	@objc private func keyboardFrameChanged(_ notification: Notification) {
		guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect, tableView.window != nil else { return }
		let keyboardTop = tableView.convert(frame, from: nil).minY
		let overlap = max(0, tableView.bounds.maxY - keyboardTop)
		tableView.contentInset.bottom = overlap
		tableView.verticalScrollIndicatorInsets.bottom = overlap
	}

	/// 仅供自动化测试：直接输入搜索词（不等键盘）。
	func searchForTesting(_ query: String) {
		compactBar?.searchField.textField.text = query
		searchQueryChanged(query)
	}

	func beginSearchForTesting() { searchTapped() }

	/// 列表最上面的垫片（静止时「窄栏 + 垫片」= 大图 169pt）。只在进入 / 退出搜索时改，滚动中不改。
	private func setSpacerHeight(_ height: CGFloat) {
		let spacer = UIView(frame: CGRect(x: 0, y: 0, width: tableView.bounds.width, height: height))
		spacer.backgroundColor = .clear
		tableView.tableHeaderView = spacer
	}

	// MARK: - 顶部大图收缩（ADR-027 第 3 步）

	/// 按滚动位置更新大图与窄栏（只改平移与透明度）。
	private func updateHeroProgress() {
		// 搜索时窄栏固定为完全收缩的样子，不随滚动变化
		guard !isSearching else { return }
		let progress = Babel2FeedHeroMotion.progress(offsetY: tableView.contentOffset.y, restOffset: -tableView.adjustedContentInset.top)
		guard progress != heroProgress else { return }
		heroProgress = progress
		heroView?.apply(progress: progress)
		compactBar?.apply(progress: progress)
	}

	/// 松手后预计停在半路：改停到最近的一端（不到一半弹回展开，过半收到窄栏）。
	func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint, targetContentOffset: UnsafeMutablePointer<CGPoint>) {
		// 搜索时没有大图，不做补完——否则在结果里拖一小段一松手就被拉回顶部（2026-09-25 用户报告「下滑失灵」）
		guard scrollView === tableView, !isSearching else { return }
		targetContentOffset.pointee.y = Babel2FeedHeroMotion.settledTargetOffset(
			proposed: targetContentOffset.pointee.y,
			restOffset: -tableView.adjustedContentInset.top
		)
	}

	func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		let cell = tableView.dequeueReusableCell(withIdentifier: Babel2ArticleCell.reuseIdentifier, for: indexPath) as! Babel2ArticleCell
		guard let index = articleIndex(for: indexPath) else { return cell }
		let article = articles[index]
		cell.configure(article: article, feedTitle: displayTitle, feedIcon: feedIconImage, imageProvider: environment.imageProvider)
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

/// 日期段标题：12pt 半粗、墨色（ADR-033，原 14 中等），与文字列左对齐（49pt）；吸顶时下方出现细线。
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
		label.font = Babel2Type.dayHeader
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
			.font: Babel2Type.dayHeader,
			.foregroundColor: BabelPalette.ink,
			.kern: 0.6
		])
	}

	func setPinned(_ pinned: Bool) {
		hairline.isHidden = !pinned
	}

	var isPinnedForTesting: Bool { !hairline.isHidden }
}

/// 文章行（Reeder 式，2026-09-25 用户给参考截图）：
/// 左列来源图标（与标题第一行居中）；文字列从 49pt 起：
/// 第一行 来源名（大写浅灰）…… 时间（贴右边缘）；
/// 标题最多 2 行（未读加粗、已读常规）；摘要浅灰 1 行；
/// 缩略图在时间下方（各尺寸见 Babel2Type「文章列表」，ADR-033 整体收小一档）、顶部与标题齐平，文字在它左边折行。行间无分隔线，只靠留白。
private final class Babel2ArticleCell: UITableViewCell {
	static let reuseIdentifier = "Babel2ArticleCell"
	private static let thumbSide = Babel2Type.rowThumbnail
	private static let iconSide = Babel2Type.rowIcon
	private static let textLeading: CGFloat = 49
	private static let titleLineHeight = Babel2Type.rowTitleLineHeight
	private static let rowPadding = Babel2Type.rowPadding
	/// 标题字体（半粗）的大写字母高度，用来找第一行字的视觉中线。
	static let titleCapHeight = Babel2Type.rowTitle(read: false).capHeight

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

		// 来源图标：圆角 5；没有图标时显示首字母方块（Figma 占位样式）
		feedIconView.contentMode = .scaleAspectFill
		feedIconView.clipsToBounds = true
		feedIconView.layer.cornerRadius = 5
		feedIconView.layer.cornerCurve = .continuous
		feedIconView.accessibilityIdentifier = "babel2.article.feed-icon"
		feedInitialLabel.font = .systemFont(ofSize: 11, weight: .semibold)
		feedInitialLabel.textColor = BabelPalette.mutedInk
		feedInitialLabel.textAlignment = .center

		// Figma「Article Row / Thumbnail」：见方、圆角 5、未加载时浅灰占位
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
		bottomBelowThumb = contentView.bottomAnchor.constraint(greaterThanOrEqualTo: thumbnailView.bottomAnchor, constant: Self.rowPadding)

		// 行高由内容决定：文字底 / 缩略图底，取较低者再留 rowPadding
		let textBottom = contentView.bottomAnchor.constraint(equalTo: summaryLabel.bottomAnchor, constant: Self.rowPadding)
		textBottom.priority = .defaultHigh

		NSLayoutConstraint.activate([
			feedLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Self.textLeading),
			feedLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Self.rowPadding),
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
			contentView.bottomAnchor.constraint(greaterThanOrEqualTo: summaryLabel.bottomAnchor, constant: Self.rowPadding),
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
		titleLabel.attributedText = Self.text(displayTitle, font: Babel2Type.rowTitle(read: article.isRead),
			color: BabelPalette.ink, lineHeight: Self.titleLineHeight, truncates: true)
		contentView.alpha = 1

		feedLabel.attributedText = Self.text(feedTitle.uppercased(), font: Babel2Type.rowSource,
			color: BabelPalette.tertiaryInk, lineHeight: 14, kern: 0.3)
		feedIconView.image = feedIcon
		feedIconView.backgroundColor = feedIcon == nil ? Self.placeholderColor : .clear
		feedInitialLabel.text = feedIcon == nil ? feedTitle.first.map { String($0).uppercased() } : nil

		let plainSummary = Self.plainSummary(article.summary)
		summaryLabel.attributedText = plainSummary.isEmpty ? nil : Self.text(plainSummary, font: Babel2Type.rowSummary,
			color: BabelPalette.tertiaryInk, lineHeight: Self.titleLineHeight, truncates: true)

		// 已按天分组，每行只显示时刻
		let time = article.publishedAt.map { Self.timeFormatter.string(from: $0) } ?? ""
		dateLabel.attributedText = Self.text(time, font: Babel2Type.rowTime,
			color: BabelPalette.ink, lineHeight: 14)
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
			showThumbnail(cached, animated: false)
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
				self.showThumbnail(image, animated: true)
			} else {
				// 下载或解码失败：保持浅灰占位，版面不变
				self.thumbnailView.image = nil
				self.thumbnailView.backgroundColor = Self.placeholderColor
			}
		}
	}

	/// 刚下载好的缩略图从灰色占位交叉淡入（ADR-034，0.22 秒）；内存里已有的直接显示，来回滚动不闪。
	private func showThumbnail(_ image: UIImage, animated: Bool) {
		let change = {
			self.thumbnailView.image = image
			self.thumbnailView.backgroundColor = .clear
		}
		if animated {
			Babel2Motion.crossfade(thumbnailView, change)
		} else {
			change()
		}
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
