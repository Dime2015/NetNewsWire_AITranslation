//
//  BabelTimelineViewController.swift
//  NetNewsWire
//

import UIKit
import Account
import Articles
import Images
import ErrorLog

final class BabelTimelineViewController: UIViewController {
	@MainActor enum Source {
		case section(BabelLibrarySection)
		case folder(Folder)
		case feed(Feed)

		var title: String {
			switch self {
			case .section(let section): section.title
			case .folder(let folder): folder.nameForDisplay
			case .feed(let feed): feed.nameForDisplay
			}
		}
	}

	private let source: Source
	// Grouped section headers move with their rows. A plain table pins the first
	// date header at the expanded content inset while the hero collapses, leaving
	// a false 70pt gap and covering the first article title.
	private let tableView = UITableView(frame: .zero, style: .grouped)
	private let statusBarBackdrop = UIView()
	private let emptyLabel = UILabel()
	private let navTitleLabel = UILabel()
	private let navSubtitleLabel = UILabel()
	private let timelineHeader = UIView()
	private let timelineHeaderSeparator = UIView()
	private var feedHeroHeader: BabelFeedHeroHeaderView?
	private var feedHeroHeightConstraint: NSLayoutConstraint?
	private var feedHeroTopInset: CGFloat = 0
	private var feedHeroExpandedHeight: CGFloat {
		BabelFeedHeroHeaderView.expandedContentHeight + view.safeAreaInsets.top
	}
	private let bottomToolbar = UIView()
	private let starredFilterButton = BabelFilterControl(filter: .starred)
	private let unreadFilterButton = BabelFilterControl(filter: .unread)
	private let allFilterButton = BabelFilterControl(filter: .all)
	private let filterSelectionPill = UIView()
	private var filterSelectionCenterConstraints = [BabelArticleFilter: NSLayoutConstraint]()
	private var filterSelectionWidthConstraint: NSLayoutConstraint?
	private let translationButton = BabelTranslationToggleControl()
	private let syncIndicator = BabelSyncGlyphView()
	private var articles = [Article]()
	private var daySections = [(date: Date, articles: [Article])]()
	private var loadTask: Task<Void, Never>?
	private var scheduledReloadTask: Task<Void, Never>?
	private var translationRefreshTask: Task<Void, Never>?
	private var preparedReaderWebView: PreloadedWebView?
	private var isPreparingReaderWebView = false
	private var hasCompletedInitialAppearance = false
	private var searchQuery = ""
	private var articleFilter: BabelArticleFilter
	private var showsTranslatedTitles = true
	private var isSyncing = false
	private weak var searchOverlay: BabelArticleSearchViewController?

	init(section: BabelLibrarySection, filter: BabelArticleFilter? = nil) {
		self.source = .section(section)
		self.articleFilter = filter ?? (section == .saved ? .starred : .unread)
		super.init(nibName: nil, bundle: nil)
	}

	init(feed: Feed, filter: BabelArticleFilter = .unread) {
		self.source = .feed(feed)
		self.articleFilter = filter
		super.init(nibName: nil, bundle: nil)
	}

	init(folder: Folder, filter: BabelArticleFilter = .unread) {
		self.source = .folder(folder)
		self.articleFilter = filter
		super.init(nibName: nil, bundle: nil)
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		configureView()
		prepareReaderWebViewIfNeeded()
		reloadArticles()
		startObserving()
	}

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		updateSyncState()
		// A reader marks an article read while it is visible. Refresh the
		// timeline on return so counts and row styling reflect that change,
		// while UITableView preserves the user's current content offset.
		if hasCompletedInitialAppearance {
			reloadArticles()
		}
	}

	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)
		hasCompletedInitialAppearance = true
	}

	override func viewDidLayoutSubviews() {
		super.viewDidLayoutSubviews()
		guard feedHeroHeader != nil else { return }
		let topInset = feedHeroExpandedHeight
		guard abs(feedHeroTopInset - topInset) > 0.5 else { return }
		let atRest = tableView.contentOffset.y <= -feedHeroTopInset + 0.5
		feedHeroTopInset = topInset
		tableView.contentInset.top = topInset
		if atRest { tableView.contentOffset = CGPoint(x: 0, y: -topInset) }
		synchronizeFeedHeroWithScrollPosition()
	}

	deinit {
		loadTask?.cancel()
		scheduledReloadTask?.cancel()
		translationRefreshTask?.cancel()
		NotificationCenter.default.removeObserver(self)
	}

	@objc private func imageDidBecomeAvailable() {
		tableView.reloadRows(at: tableView.indexPathsForVisibleRows ?? [], with: .none)
	}

	private func configureView() {
		title = source.title
		view.backgroundColor = BabelPalette.background
		view.isOpaque = true
		statusBarBackdrop.backgroundColor = BabelPalette.background
		statusBarBackdrop.isOpaque = true
		statusBarBackdrop.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(statusBarBackdrop)
		NSLayoutConstraint.activate([
			statusBarBackdrop.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			statusBarBackdrop.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			statusBarBackdrop.topAnchor.constraint(equalTo: view.topAnchor),
			statusBarBackdrop.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor)
		])
        navigationItem.largeTitleDisplayMode = .never
		navTitleLabel.text = source.title
		navTitleLabel.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
		navTitleLabel.textColor = BabelPalette.ink
		navTitleLabel.textAlignment = .center
		switch source {
		case .section(.unread):
			navSubtitleLabel.text = "\(AccountManager.shared.unreadCount.formatted()) Unread Items"
		case .section:
			navSubtitleLabel.text = ""
		case .feed(let feed):
			navSubtitleLabel.text = "\(feed.unreadCount.formatted()) Unread Items"
		case .folder(let folder):
			navSubtitleLabel.text = "\(folder.unreadCount.formatted()) Unread Items"
		}
		navSubtitleLabel.font = UIFont.systemFont(ofSize: 12, weight: .regular)
		navSubtitleLabel.textColor = BabelPalette.mutedInk
		navSubtitleLabel.textAlignment = .center
		let navTitleStack = UIStackView(arrangedSubviews: [navTitleLabel, navSubtitleLabel])
		navTitleStack.axis = .vertical
		navTitleStack.alignment = .center
		navTitleStack.spacing = 0
		// The title stack is rendered in the custom header below.
		configureTimelineHeader()

		tableView.backgroundColor = BabelPalette.background
		tableView.isOpaque = true
		tableView.separatorStyle = .none
		// Plain UITableView adds a 22pt lead-in before the first section header.
		// Here the feed hero already owns that separation, so the system padding
		// reads as a second blank strip between the source title and the date.
		tableView.sectionHeaderTopPadding = 0
		tableView.sectionFooterHeight = .leastNormalMagnitude
		tableView.estimatedSectionFooterHeight = 0
		// The custom header already occupies the top region; a small inset keeps
		// the first day label just below it, matching Reeder's timeline rhythm.
		// The table is pinned behind the custom navigation header. A small
		// negative top inset cancels UIKit's automatic safe-area contribution so
		// the first day header sits directly below the Reeder-style title bar.
		tableView.contentInsetAdjustmentBehavior = .never
		if feedHeroHeader != nil {
			// A selected feed starts below its hero. The hero includes the status
			// bar so its artwork is one continuous surface from screen top.
			// the hero contracts in the same coordinate system rather than adding
			// a second scrolling surface.
			feedHeroTopInset = feedHeroExpandedHeight
			tableView.contentInset = UIEdgeInsets(top: feedHeroTopInset, left: 0, bottom: 12, right: 0)
		} else {
			tableView.contentInset = UIEdgeInsets(top: 68, left: 0, bottom: 12, right: 0)
		}
		tableView.rowHeight = 99
		tableView.estimatedRowHeight = 99
		tableView.register(BabelTimelineCell.self, forCellReuseIdentifier: BabelTimelineCell.reuseIdentifier)
		tableView.dataSource = self
		tableView.delegate = self
		NotificationCenter.default.addObserver(self, selector: #selector(imageDidBecomeAvailable), name: .imageDidBecomeAvailable, object: nil)
		view.addSubview(tableView)
		tableView.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			tableView.topAnchor.constraint(equalTo: feedHeroHeader == nil ? view.safeAreaLayoutGuide.topAnchor : view.topAnchor)
		])
		tableView.setContentOffset(CGPoint(x: 0, y: -tableView.contentInset.top), animated: false)

		emptyLabel.text = "No Articles"
		emptyLabel.font = BabelTypography.reading(size: 19)
		emptyLabel.textColor = BabelPalette.mutedInk
		emptyLabel.textAlignment = .center
		emptyLabel.isHidden = true
		emptyLabel.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(emptyLabel)
		NSLayoutConstraint.activate([
			emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
			emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor)
		])

		let refreshControl = UIRefreshControl()
		// Sync state is represented by the custom circular-arrow glyph in the
		// header. Preserve pull-to-refresh behavior without adding UIKit's second
		// spinner below it.
		refreshControl.tintColor = .clear
		refreshControl.addTarget(self, action: #selector(refreshFromControl), for: .valueChanged)
        tableView.refreshControl = refreshControl

		bottomToolbar.backgroundColor = BabelPalette.background
		bottomToolbar.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(bottomToolbar)
		let bottomSeparator = UIView()
        bottomSeparator.backgroundColor = BabelPalette.hairline
        bottomSeparator.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bottomSeparator)
		let readAllButton = makeTimelineToolbarButton(symbol: "checkmark.circle", label: "全部标为已读")
		readAllButton.addTarget(self, action: #selector(markAllRead), for: .touchUpInside)
		starredFilterButton.addTarget(self, action: #selector(selectStarredFilter), for: .touchUpInside)
		unreadFilterButton.addTarget(self, action: #selector(selectUnreadFilter), for: .touchUpInside)
		allFilterButton.addTarget(self, action: #selector(selectAllFilter), for: .touchUpInside)
		translationButton.addTarget(self, action: #selector(toggleTitleTranslation), for: .touchUpInside)
		filterSelectionPill.backgroundColor = BabelPalette.raisedBackground.withAlphaComponent(0.62)
		filterSelectionPill.layer.cornerRadius = 13
		filterSelectionPill.isUserInteractionEnabled = false
		filterSelectionPill.translatesAutoresizingMaskIntoConstraints = false
		bottomToolbar.addSubview(filterSelectionPill)
		starredFilterButton.usesExternalSelectionPill = true
		unreadFilterButton.usesExternalSelectionPill = true
		allFilterButton.usesExternalSelectionPill = true
		for control in [readAllButton, starredFilterButton, unreadFilterButton, allFilterButton, translationButton] {
			control.translatesAutoresizingMaskIntoConstraints = false
			bottomToolbar.addSubview(control)
		}
		NSLayoutConstraint.activate([
			bottomToolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			bottomToolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			bottomToolbar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
			bottomToolbar.heightAnchor.constraint(equalToConstant: 72),
			readAllButton.centerXAnchor.constraint(equalTo: bottomToolbar.leadingAnchor, constant: 32),
			starredFilterButton.centerXAnchor.constraint(equalTo: bottomToolbar.leadingAnchor, constant: 104),
			unreadFilterButton.centerXAnchor.constraint(equalTo: bottomToolbar.centerXAnchor),
			allFilterButton.centerXAnchor.constraint(equalTo: bottomToolbar.leadingAnchor, constant: BabelChromeMetrics.bottomSlots[3]),
			translationButton.centerXAnchor.constraint(equalTo: bottomToolbar.leadingAnchor, constant: BabelChromeMetrics.bottomSlots[4]),
			readAllButton.centerYAnchor.constraint(equalTo: bottomToolbar.topAnchor, constant: 24),
			starredFilterButton.centerYAnchor.constraint(equalTo: readAllButton.centerYAnchor),
			unreadFilterButton.centerYAnchor.constraint(equalTo: readAllButton.centerYAnchor),
			allFilterButton.centerYAnchor.constraint(equalTo: readAllButton.centerYAnchor),
			translationButton.centerYAnchor.constraint(equalTo: readAllButton.centerYAnchor),
			readAllButton.widthAnchor.constraint(equalToConstant: 44),
			readAllButton.heightAnchor.constraint(equalToConstant: 44),
			starredFilterButton.widthAnchor.constraint(equalToConstant: 90),
			starredFilterButton.heightAnchor.constraint(equalToConstant: 44),
			unreadFilterButton.widthAnchor.constraint(equalToConstant: 78),
			unreadFilterButton.heightAnchor.constraint(equalToConstant: 44),
			allFilterButton.widthAnchor.constraint(equalToConstant: 68),
			allFilterButton.heightAnchor.constraint(equalToConstant: 44),
			translationButton.widthAnchor.constraint(equalToConstant: 58),
			translationButton.heightAnchor.constraint(equalToConstant: 44)
		])
		filterSelectionWidthConstraint = filterSelectionPill.widthAnchor.constraint(equalToConstant: articleFilter.selectedWidth)
		filterSelectionCenterConstraints = [
			.starred: filterSelectionPill.centerXAnchor.constraint(equalTo: starredFilterButton.centerXAnchor),
			.unread: filterSelectionPill.centerXAnchor.constraint(equalTo: unreadFilterButton.centerXAnchor),
			.all: filterSelectionPill.centerXAnchor.constraint(equalTo: allFilterButton.centerXAnchor)
		]
		filterSelectionWidthConstraint?.isActive = true
		filterSelectionCenterConstraints[articleFilter]?.isActive = true
		filterSelectionPill.centerYAnchor.constraint(equalTo: starredFilterButton.centerYAnchor).isActive = true
		filterSelectionPill.heightAnchor.constraint(equalToConstant: 26).isActive = true
        NSLayoutConstraint.activate([
            bottomSeparator.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomSeparator.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			bottomSeparator.bottomAnchor.constraint(equalTo: bottomToolbar.topAnchor),
            bottomSeparator.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale)
        ])
		// Keep article content above the persistent toolbar instead of drawing
		// underneath it. This matters when a larger Reeder-style preview wraps
		// onto two lines near the end of the viewport.
		tableView.bottomAnchor.constraint(equalTo: bottomToolbar.topAnchor).isActive = true
		updateFilterControls()
		translationButton.display = showsTranslatedTitles ? .translation : .original
		view.bringSubviewToFront(bottomToolbar)
		view.bringSubviewToFront(timelineHeader)
		if let feedHeroHeader {
			view.bringSubviewToFront(feedHeroHeader)
		} else {
			view.bringSubviewToFront(statusBarBackdrop)
		}
	}

	private func makeTimelineToolbarButton(symbol: String, label: String) -> UIButton {
		var config = UIButton.Configuration.plain()
		config.baseForegroundColor = BabelPalette.mutedInk
		config.image = BabelChromeMetrics.bottomSymbol(symbol)
		config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
			pointSize: BabelChromeMetrics.bottomIconPointSize,
			weight: .regular
		)
		config.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4)
		let button = UIButton(configuration: config)
		button.accessibilityLabel = label
		button.accessibilityIdentifier = "babel.timeline.toolbar.read-all"
		return button
	}

	private func configureTimelineHeader() {
		if case .feed(let feed) = source {
			configureFeedHeroHeader(feed)
			return
		}
		timelineHeader.translatesAutoresizingMaskIntoConstraints = false
		timelineHeader.backgroundColor = BabelPalette.background
		view.addSubview(timelineHeader)
		timelineHeaderSeparator.backgroundColor = BabelPalette.hairline
		timelineHeaderSeparator.translatesAutoresizingMaskIntoConstraints = false
		timelineHeader.addSubview(timelineHeaderSeparator)
		let back = UIButton(type: .custom)
		back.setImage(UIImage(systemName: "chevron.left", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)), for: .normal)
		back.tintColor = BabelPalette.ink
		back.addTarget(self, action: #selector(closeTimeline), for: .touchUpInside)
		back.translatesAutoresizingMaskIntoConstraints = false
		timelineHeader.addSubview(back)
		navTitleLabel.translatesAutoresizingMaskIntoConstraints = false
		navSubtitleLabel.translatesAutoresizingMaskIntoConstraints = false
		timelineHeader.addSubview(navTitleLabel)
		timelineHeader.addSubview(navSubtitleLabel)
		syncIndicator.isHidden = true
		syncIndicator.translatesAutoresizingMaskIntoConstraints = false
		timelineHeader.addSubview(syncIndicator)
		let actions = UIButton(type: .custom)
		actions.setImage(UIImage(systemName: "ellipsis"), for: .normal)
		actions.tintColor = BabelPalette.ink
		actions.addTarget(self, action: #selector(showActions), for: .touchUpInside)
		actions.translatesAutoresizingMaskIntoConstraints = false
		timelineHeader.addSubview(actions)
		let search = UIButton(type: .custom)
		search.setImage(UIImage(systemName: "magnifyingglass", withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .regular)), for: .normal)
		search.tintColor = BabelPalette.ink
		search.accessibilityLabel = "搜索文章"
		search.accessibilityIdentifier = "babel.timeline.header.search"
		search.addTarget(self, action: #selector(showSearch), for: .touchUpInside)
		search.translatesAutoresizingMaskIntoConstraints = false
		timelineHeader.addSubview(search)
		NSLayoutConstraint.activate([
			timelineHeader.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			timelineHeader.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			timelineHeader.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
			timelineHeader.heightAnchor.constraint(equalToConstant: 68),
			timelineHeaderSeparator.leadingAnchor.constraint(equalTo: timelineHeader.leadingAnchor),
			timelineHeaderSeparator.trailingAnchor.constraint(equalTo: timelineHeader.trailingAnchor),
			timelineHeaderSeparator.bottomAnchor.constraint(equalTo: timelineHeader.bottomAnchor),
			timelineHeaderSeparator.heightAnchor.constraint(equalToConstant: 0.5),
			back.leadingAnchor.constraint(equalTo: timelineHeader.leadingAnchor),
			back.centerYAnchor.constraint(equalTo: timelineHeader.topAnchor, constant: 24),
			back.widthAnchor.constraint(equalToConstant: 44), back.heightAnchor.constraint(equalToConstant: 44),
			syncIndicator.centerXAnchor.constraint(equalTo: timelineHeader.leadingAnchor, constant: BabelChromeMetrics.topSlots[1]),
			syncIndicator.centerYAnchor.constraint(equalTo: timelineHeader.topAnchor, constant: BabelChromeMetrics.topControlCenterY),
			syncIndicator.widthAnchor.constraint(equalToConstant: 24), syncIndicator.heightAnchor.constraint(equalToConstant: 24),
			navTitleLabel.centerXAnchor.constraint(equalTo: timelineHeader.centerXAnchor),
			navTitleLabel.topAnchor.constraint(equalTo: timelineHeader.topAnchor, constant: 8),
			navSubtitleLabel.centerXAnchor.constraint(equalTo: timelineHeader.centerXAnchor),
			navSubtitleLabel.topAnchor.constraint(equalTo: navTitleLabel.bottomAnchor),
			actions.centerXAnchor.constraint(equalTo: timelineHeader.trailingAnchor, constant: -32),
			actions.centerYAnchor.constraint(equalTo: timelineHeader.topAnchor, constant: 24),
			actions.widthAnchor.constraint(equalToConstant: 44), actions.heightAnchor.constraint(equalToConstant: 44),
			search.centerXAnchor.constraint(equalTo: timelineHeader.trailingAnchor, constant: -72),
			search.centerYAnchor.constraint(equalTo: actions.centerYAnchor),
			search.widthAnchor.constraint(equalToConstant: 44), search.heightAnchor.constraint(equalToConstant: 44)
		])
	}

	private func configureFeedHeroHeader(_ feed: Feed) {
		let hero = BabelFeedHeroHeaderView(feed: feed)
		hero.setSyncing(isSyncing)
		hero.onBack = { [weak self] in self?.closeTimeline() }
		hero.onSearch = { [weak self] in self?.showSearch() }
		hero.onActions = { [weak self] in self?.showActions() }
		hero.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(hero)
		let height = hero.heightAnchor.constraint(equalToConstant: feedHeroExpandedHeight)
		feedHeroHeightConstraint = height
		NSLayoutConstraint.activate([
			hero.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			hero.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			hero.topAnchor.constraint(equalTo: view.topAnchor),
			height
		])
		feedHeroHeader = hero
	}

	@objc private func closeTimeline() { navigationController?.popViewController(animated: true) }

	private func startObserving() {
		let names: [Notification.Name] = [
			.UnreadCountDidChange,
			.AccountDidDownloadArticles
		]
		for name in names {
			NotificationCenter.default.addObserver(self, selector: #selector(dataDidChange), name: name, object: nil)
		}
		NotificationCenter.default.addObserver(self, selector: #selector(syncDidBegin), name: .AccountRefreshDidBegin, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(syncDidFinish), name: .AccountRefreshDidFinish, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(titleTranslationDidUpdate), name: .nnwTitleTranslationDidUpdate, object: nil)
	}

	@objc private func dataDidChange() {
		// One refresh can emit article-download and several unread-count
		// notifications back-to-back. Coalesce them so the timeline performs one
		// database read and one visual update instead of repeatedly cancelling and
		// rebuilding the same screen.
		scheduledReloadTask?.cancel()
		scheduledReloadTask = Task { [weak self] in
			try? await Task.sleep(for: .milliseconds(140))
			guard !Task.isCancelled else { return }
			self?.reloadArticles()
		}
	}

	@objc private func titleTranslationDidUpdate() {
		// A batch can publish several updates while the user is decelerating.
		// Coalesce them and update only title labels; rebuilding complete cells in
		// the scroll path caused duplicate layers/constraint churn on translated feeds.
		translationRefreshTask?.cancel()
		translationRefreshTask = Task { [weak self] in
			try? await Task.sleep(for: .milliseconds(60))
			guard !Task.isCancelled else { return }
			self?.refreshVisibleArticleTitles()
		}
	}

    @objc private func refreshFromControl() {
		AccountManager.shared.refreshAllWithoutWaiting(errorHandler: ErrorHandler.log)
    }

	@objc private func selectStarredFilter() { selectFilter(.starred) }
	@objc private func selectUnreadFilter() { selectFilter(.unread) }
	@objc private func selectAllFilter() { selectFilter(.all) }

	private func selectFilter(_ filter: BabelArticleFilter, animated: Bool = true) {
		guard articleFilter != filter else { return }
		let previous = articleFilter
		let forward = (BabelArticleFilter.allCases.firstIndex(of: filter) ?? 0) > (BabelArticleFilter.allCases.firstIndex(of: previous) ?? 0)
		articleFilter = filter
		updateFilterControls(animated: animated, from: previous)
		reloadArticles(slideForward: animated ? forward : nil, resetToTop: true)
	}

	private func updateFilterControls(animated: Bool = false, from previous: BabelArticleFilter? = nil) {
		starredFilterButton.setSelected(articleFilter == .starred, animated: false)
		unreadFilterButton.setSelected(articleFilter == .unread, animated: false)
		allFilterButton.setSelected(articleFilter == .all, animated: false)
		guard previous != nil, previous != articleFilter else { return }
		filterSelectionCenterConstraints.values.forEach { $0.isActive = false }
		filterSelectionCenterConstraints[articleFilter]?.isActive = true
		filterSelectionWidthConstraint?.constant = articleFilter.selectedWidth
		if animated {
			UIView.animate(withDuration: 0.32, delay: 0, usingSpringWithDamping: 0.84, initialSpringVelocity: 0.45, options: [.allowUserInteraction, .beginFromCurrentState]) {
				self.bottomToolbar.layoutIfNeeded()
			}
		} else {
			bottomToolbar.layoutIfNeeded()
		}
	}

	@objc private func syncDidBegin() {
		updateSyncState()
	}

	@objc private func syncDidFinish() {
		updateSyncState()
		if !isSyncing { tableView.refreshControl?.endRefreshing() }
	}

	private func updateSyncState() {
		let currentlySyncing = AccountManager.shared.sortedActiveAccounts.contains(where: \.refreshInProgress)
		guard isSyncing != currentlySyncing else {
			syncIndicator.setSyncing(currentlySyncing)
			feedHeroHeader?.setSyncing(currentlySyncing)
			return
		}
		isSyncing = currentlySyncing
		syncIndicator.setSyncing(currentlySyncing)
		feedHeroHeader?.setSyncing(currentlySyncing)
		if currentlySyncing {
			navSubtitleLabel.text = "Syncing..."
			feedHeroHeader?.subtitle = "正在同步…"
		} else {
			updateDisplayedCount()
		}
	}

	@objc private func showSearch() {
		guard searchOverlay == nil else { return }
		let overlay = BabelArticleSearchViewController(sourceTitle: source.title, articles: articles)
		overlay.onDismiss = { [weak self, weak overlay] in
			guard let self, let overlay else { return }
			self.dismissSearchOverlay(overlay)
		}
		overlay.onSelectArticle = { [weak self, weak overlay] article in
			guard let self, let overlay else { return }
			self.dismissSearchOverlay(overlay)
			self.openReader(for: article)
		}
		addChild(overlay)
		overlay.view.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(overlay.view)
		NSLayoutConstraint.activate([
			overlay.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			overlay.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			overlay.view.topAnchor.constraint(equalTo: view.topAnchor),
			overlay.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
		])
		overlay.didMove(toParent: self)
		searchOverlay = overlay
		overlay.view.alpha = 0
		overlay.view.transform = CGAffineTransform(translationX: 0, y: -12)
		UIView.animate(withDuration: 0.26, delay: 0, options: [.curveEaseOut, .allowUserInteraction, .beginFromCurrentState]) {
			overlay.view.alpha = 1
			overlay.view.transform = .identity
		}
	}

	private func dismissSearchOverlay(_ overlay: BabelArticleSearchViewController) {
		guard overlay.parent === self else { return }
		overlay.willMove(toParent: nil)
		searchOverlay = nil
		UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseIn, .allowUserInteraction, .beginFromCurrentState]) {
			overlay.view.alpha = 0
			overlay.view.transform = CGAffineTransform(translationX: 0, y: -10)
		} completion: { _ in
			overlay.view.removeFromSuperview()
			overlay.removeFromParent()
		}
	}

	private func openReader(for selected: Article) {
		var currentArticle = selected
		let reader = BabelReaderViewController(
			article: selected,
			preparedWebView: takePreparedReaderWebView()
		)
		reader.takePreparedWebView = { [weak self] in
			self?.takePreparedReaderWebView()
		}
		reader.nextArticle = { [weak self] in
			guard let self,
				  let sectionIndex = self.daySections.firstIndex(where: { $0.articles.contains(where: { $0.articleID == currentArticle.articleID }) }),
				  let rowIndex = self.daySections[sectionIndex].articles.firstIndex(where: { $0.articleID == currentArticle.articleID }) else { return nil }
			let next: Article?
			if rowIndex + 1 < self.daySections[sectionIndex].articles.count {
				next = self.daySections[sectionIndex].articles[rowIndex + 1]
			} else if sectionIndex + 1 < self.daySections.count {
				next = self.daySections[sectionIndex + 1].articles.first
			} else {
				next = nil
			}
			guard let next else { return nil }
			currentArticle = next
			return next
		}
		navigationController?.pushViewController(reader, animated: true)
	}

	/// Genesis v2 keeps a ready WebView alive behind its persistent article
	/// controller. Babel uses push navigation, so reserve one ready instance while
	/// the user is reading the timeline and inject it into the next reader.
	private func prepareReaderWebViewIfNeeded() {
		guard preparedReaderWebView == nil,
			  !isPreparingReaderWebView,
			  let provider = BabelReaderWebViewPool.provider else { return }
		isPreparingReaderWebView = true
		provider.dequeueWebView { [weak self] webView in
			webView.ready { [weak self] in
				guard let self else { return }
				self.isPreparingReaderWebView = false
				self.preparedReaderWebView = webView
			}
		}
	}

	private func takePreparedReaderWebView() -> PreloadedWebView? {
		let webView = preparedReaderWebView
		preparedReaderWebView = nil
		prepareReaderWebViewIfNeeded()
		return webView
	}

	@objc private func toggleTitleTranslation() {
		showsTranslatedTitles.toggle()
		translationButton.display = showsTranslatedTitles ? .translation : .original
		refreshVisibleArticleTitles()
	}

    @objc private func showActions() {
		let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
		alert.addAction(UIAlertAction(title: "Mark All as Read", style: .default) { [weak self] _ in
			self?.markAllRead()
		})
		alert.addAction(UIAlertAction(title: "Mark All as Unread", style: .default) { [weak self] _ in
			self?.markAllUnread()
		})
		alert.addAction(UIAlertAction(title: "Refresh", style: .default) { [weak self] _ in
			self?.refreshFromControl()
		})
		alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
		present(alert, animated: true)
    }

	@objc private func markAllRead() {
		let unread = articles.filter { !$0.status.read }
		let grouped = Dictionary(grouping: unread, by: { $0.accountID })
		Task { @MainActor in
			for (accountID, accountArticles) in grouped {
				guard let account = AccountManager.shared.existingAccount(accountID: accountID) else { continue }
				try? await account.markArticles(articleIDs: Set(accountArticles.map(\.articleID)), statusKey: .read, flag: true)
			}
			reloadArticles()
		}
	}

	@objc private func markAllUnread() {
		let grouped = Dictionary(grouping: articles, by: { $0.accountID })
		Task { @MainActor in
			for (accountID, accountArticles) in grouped {
				guard let account = AccountManager.shared.existingAccount(accountID: accountID) else { continue }
				try? await account.markArticles(articleIDs: Set(accountArticles.map(\.articleID)), statusKey: .read, flag: false)
			}
			reloadArticles()
		}
	}

	private var topContentOffset: CGPoint {
		CGPoint(x: 0, y: -tableView.contentInset.top)
	}

	private func reloadArticles(slideForward: Bool? = nil, resetToTop: Bool = false) {
		loadTask?.cancel()
		let shouldPreserveOffset = tableView.window != nil && !resetToTop
		let shouldStartAtTop = resetToTop || !shouldPreserveOffset
		let preservedOffset = tableView.contentOffset
		emptyLabel.isHidden = true
		loadTask = Task { [weak self] in
			guard let self else { return }
			let loaded: [Article]
			switch source {
			case .section:
				switch articleFilter {
				case .starred: loaded = await BabelLibrary.loadArticles(for: .saved)
				case .unread: loaded = await BabelLibrary.loadArticles(for: .unread)
				case .all: loaded = await BabelLibrary.loadAllArticles()
				}
			case .folder(let folder):
				switch articleFilter {
				case .unread: loaded = BabelLibrary.sorted(await folder.fetchUnreadArticlesAsync())
				case .starred: loaded = BabelLibrary.sorted(await folder.fetchArticlesAsync().filter(\.status.starred))
				case .all: loaded = BabelLibrary.sorted(await folder.fetchArticlesAsync())
				}
			case .feed(let feed):
				switch articleFilter {
				case .unread: loaded = BabelLibrary.sorted(await feed.fetchUnreadArticlesAsync())
				case .starred: loaded = BabelLibrary.sorted(await feed.fetchArticlesAsync().filter(\.status.starred))
				case .all: loaded = BabelLibrary.sorted(await feed.fetchArticlesAsync())
				}
			}
			guard !Task.isCancelled else { return }
			articles = loaded
			let updates = {
				self.rebuildSections(from: loaded)
				self.tableView.reloadData()
				// Setting the offset while the table is still empty is not durable:
				// UITableView clamps it back to zero when the first async rows arrive.
				// Zero means "hero fully collapsed" in our coordinate system while the
				// content still owns the expanded 169pt inset, producing the exact 70pt
				// blank strip reported on device. Re-apply the paired inset/offset only
				// after reloadData has materialized and laid out the first rows.
				self.tableView.layoutIfNeeded()
				if shouldStartAtTop {
					self.tableView.setContentOffset(self.topContentOffset, animated: false)
					self.synchronizeFeedHeroWithScrollPosition()
				}
			}
			applyTableUpdate(slideForward: slideForward, updates: updates)
			if shouldPreserveOffset {
				tableView.layoutIfNeeded()
				tableView.setContentOffset(preservedOffset, animated: false)
				synchronizeFeedHeroWithScrollPosition()
			}
			tableView.refreshControl?.endRefreshing()
			emptyLabel.isHidden = !daySections.isEmpty
		}
	}

	private func applyTableUpdate(slideForward: Bool?, updates: () -> Void) {
		guard let slideForward, let container = tableView.superview,
			  let outgoing = tableView.snapshotView(afterScreenUpdates: false) else {
			updates()
			return
		}
		outgoing.frame = tableView.frame
		container.insertSubview(outgoing, aboveSubview: tableView)
		updates()
		tableView.layoutIfNeeded()
		let travel: CGFloat = 36
		tableView.transform = CGAffineTransform(translationX: slideForward ? travel : -travel, y: 0)
		tableView.alpha = 0.12
		UIView.animate(withDuration: 0.34, delay: 0, usingSpringWithDamping: 0.84, initialSpringVelocity: 0.35, options: [.allowUserInteraction, .beginFromCurrentState]) {
			self.tableView.transform = .identity
			self.tableView.alpha = 1
			outgoing.transform = CGAffineTransform(translationX: slideForward ? -travel : travel, y: 0)
			outgoing.alpha = 0
		} completion: { _ in
			outgoing.removeFromSuperview()
		}
	}

	private func refreshVisibleArticleTitles() {
		UIView.performWithoutAnimation {
			for indexPath in tableView.indexPathsForVisibleRows ?? [] {
				guard daySections.indices.contains(indexPath.section),
					  daySections[indexPath.section].articles.indices.contains(indexPath.row),
					  let cell = tableView.cellForRow(at: indexPath) as? BabelTimelineCell else { continue }
				cell.updateTitle(article: daySections[indexPath.section].articles[indexPath.row], showsTranslatedTitle: showsTranslatedTitles)
			}
		}
	}

	private func updateDisplayedCount() {
		guard !isSyncing else { return }
		let count = daySections.reduce(0) { $0 + $1.articles.count }
		let text: String
		switch articleFilter {
		case .unread: text = "\(count.formatted()) 未读文章"
		case .starred: text = "\(count.formatted()) 星标文章"
		case .all: text = "\(count.formatted()) 篇文章"
		}
		navSubtitleLabel.text = text
		feedHeroHeader?.subtitle = text
	}

	func openFirstArticleForDebug() {
		Task { @MainActor [weak self] in
			guard let self else { return }
			for _ in 0..<60 where self.daySections.isEmpty {
				try? await Task.sleep(for: .milliseconds(150))
			}
			let candidates = self.daySections.flatMap(\.articles)
			guard let first = candidates.max(by: { lhs, rhs in
				let lhsLength = (lhs.contentText?.count ?? 0) + (lhs.contentHTML?.count ?? 0)
				let rhsLength = (rhs.contentText?.count ?? 0) + (rhs.contentHTML?.count ?? 0)
				return lhsLength < rhsLength
			}) else { return }
			var currentArticle = first
			let reader = BabelReaderViewController(
				article: first,
				preparedWebView: self.takePreparedReaderWebView()
			)
			reader.takePreparedWebView = { [weak self] in
				self?.takePreparedReaderWebView()
			}
			reader.nextArticle = { [weak self] in
				guard let self,
					  let sectionIndex = self.daySections.firstIndex(where: { $0.articles.contains(where: { $0.articleID == currentArticle.articleID }) }),
					  let rowIndex = self.daySections[sectionIndex].articles.firstIndex(where: { $0.articleID == currentArticle.articleID }) else { return nil }
				let next: Article?
				if rowIndex + 1 < self.daySections[sectionIndex].articles.count {
					next = self.daySections[sectionIndex].articles[rowIndex + 1]
				} else if sectionIndex + 1 < self.daySections.count {
					next = self.daySections[sectionIndex + 1].articles.first
				} else {
					next = nil
				}
				guard let next else { return nil }
				currentArticle = next
				return next
			}
			navigationController?.pushViewController(reader, animated: false)
		}
	}

	/// Selects a deterministic in-place toolbar state for simulator screenshots.
	func presentFilterForDebug() {
		selectFilter(.all, animated: false)
	}

	func presentSearchForDebug() {
		showSearch()
	}

	func collapseFeedHeroForDebug() {
		guard feedHeroHeader != nil else { return }
		view.layoutIfNeeded()
		let target = CGPoint(x: 0, y: -tableView.contentInset.top + BabelFeedHeroHeaderView.collapseDistance)
		tableView.setContentOffset(target, animated: false)
		// Do not force the hero independently from UITableView. A short table may
		// clamp its offset; forcing only the hero in that case creates a fake gap
		// that cannot occur through normal scrolling.
		synchronizeFeedHeroWithScrollPosition()
		view.layoutIfNeeded()
	}

	/// Simulator-only stress path: scrolls through the collapsing hero while
	/// translation batches repeatedly announce title updates. This reproduces the
	/// two callbacks that previously fought over the table's render state.
	func runTranslationScrollStressForDebug() {
		Task { @MainActor [weak self] in
			guard let self else { return }
			for _ in 0..<40 where self.daySections.isEmpty {
				try? await Task.sleep(for: .milliseconds(100))
			}
			guard !self.daySections.isEmpty else { return }
			let start = -self.tableView.contentInset.top
			let end = min(max(start + 360, start + BabelFeedHeroHeaderView.collapseDistance),
						  max(start, self.tableView.contentSize.height - self.tableView.bounds.height))
			for step in 0...180 {
				let phase = CGFloat(step) / 180
				let wave = phase <= 0.5 ? phase * 2 : (1 - phase) * 2
				self.tableView.setContentOffset(CGPoint(x: 0, y: start + (end - start) * wave), animated: false)
				if step.isMultiple(of: 4) { self.titleTranslationDidUpdate() }
				try? await Task.sleep(for: .milliseconds(16))
			}
		}
	}

	private func rebuildSections(from articles: [Article]) {
		let filtered: [Article]
		if searchQuery.isEmpty {
			filtered = articles.filter {
				switch articleFilter {
				case .all: true
				case .unread: !$0.status.read
				case .starred: $0.status.starred
				}
			}
		} else {
			filtered = articles.filter { article in
				let matchesFilter: Bool
				switch articleFilter {
				case .all: matchesFilter = true
				case .unread: matchesFilter = !article.status.read
				case .starred: matchesFilter = article.status.starred
				}
				guard matchesFilter else { return false }
				let haystack = [article.title, article.summary, article.contentText]
					.compactMap { $0?.lowercased() }
					.joined(separator: " ")
				return haystack.contains(searchQuery.lowercased())
			}
		}
		let calendar = Calendar.current
		let grouped = Dictionary(grouping: filtered) { calendar.startOfDay(for: $0.logicalDatePublished) }
		daySections = grouped.keys.sorted(by: >).map { date in
			(date: date, articles: grouped[date] ?? [])
		}
		updateDisplayedCount()
	}

	private static let dayFormatter: DateFormatter = {
		let formatter = DateFormatter()
		formatter.locale = Locale(identifier: "en_US_POSIX")
		formatter.dateFormat = "EEEE, MMMM d, yyyy"
		return formatter
	}()
}

extension BabelTimelineViewController: UISearchResultsUpdating {
	func updateSearchResults(for searchController: UISearchController) {
		searchQuery = searchController.searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
		rebuildSections(from: articles)
		tableView.reloadData()
	}
}

extension BabelTimelineViewController: UITableViewDataSource, UITableViewDelegate {

	func scrollViewDidScroll(_ scrollView: UIScrollView) {
		guard scrollView === tableView, let hero = feedHeroHeader else { return }
		synchronizeFeedHeroWithScrollPosition(hero: hero)
	}

	private func synchronizeFeedHeroWithScrollPosition(hero suppliedHero: BabelFeedHeroHeaderView? = nil) {
		guard let hero = suppliedHero ?? feedHeroHeader else { return }
		let travel = max(0, tableView.contentOffset.y + feedHeroTopInset)
		let progress = min(travel / BabelFeedHeroHeaderView.collapseDistance, 1)
		let height = feedHeroExpandedHeight - BabelFeedHeroHeaderView.collapseDistance * progress
		if abs((feedHeroHeightConstraint?.constant ?? height) - height) > 0.1 {
			feedHeroHeightConstraint?.constant = height
			// Keep UITableView's inset stable during a pan. Mutating contentInset on
			// every scroll callback forces the whole table to be composited again and
			// becomes visibly corrupt when asynchronous translated titles arrive.
			view.layoutIfNeeded()
		}
		hero.apply(scrollProgress: progress)
	}

	func numberOfSections(in tableView: UITableView) -> Int { daySections.count }

	func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		daySections[section].articles.count
	}

	func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
		Self.dayFormatter.string(from: daySections[section].date).uppercased()
	}

	func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
		let header = UIView()
		header.backgroundColor = BabelPalette.background
		let label = UILabel()
		label.text = Self.dayFormatter.string(from: daySections[section].date).uppercased()
		label.font = UIFont.systemFont(ofSize: 14, weight: .medium)
		label.textColor = BabelPalette.ink
		label.textAlignment = .left
		label.translatesAutoresizingMaskIntoConstraints = false
		header.addSubview(label)
		NSLayoutConstraint.activate([
			// 50pt renders at the 120px reference origin on the 3x simulator canvas.
			label.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 50),
			label.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -16),
			label.centerYAnchor.constraint(equalTo: header.centerYAnchor)
		])
		return header
	}

	func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat { 44 }

	func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		let cell = tableView.dequeueReusableCell(withIdentifier: BabelTimelineCell.reuseIdentifier, for: indexPath) as! BabelTimelineCell
		let article = daySections[indexPath.section].articles[indexPath.row]
		cell.configure(article: article, showsTranslatedTitle: showsTranslatedTitles)
		cell.accessibilityIdentifier = "babel.timeline.row.\(article.articleID)"
		return cell
	}

	func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		tableView.deselectRow(at: indexPath, animated: true)
		openReader(for: daySections[indexPath.section].articles[indexPath.row])
	}

	func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
		let article = daySections[indexPath.section].articles[indexPath.row]
		let star = UIContextualAction(style: .normal, title: article.status.starred ? "Unstar" : "Star") { [weak self] _, _, completion in
			guard let account = article.account else { completion(false); return }
			Task {
				try? await account.markArticles(articleIDs: [article.articleID], statusKey: .starred, flag: !article.status.starred)
				await MainActor.run { completion(true); self?.reloadArticles() }
			}
		}
		star.backgroundColor = BabelPalette.mutedInk
		let read = UIContextualAction(style: .normal, title: article.status.read ? "Mark Unread" : "Mark Read") { [weak self] _, _, completion in
			guard let account = article.account else { completion(false); return }
			Task {
				try? await account.markArticles(articleIDs: [article.articleID], statusKey: .read, flag: !article.status.read)
				await MainActor.run { completion(true); self?.reloadArticles() }
			}
		}
		read.backgroundColor = BabelPalette.mutedInk
		return UISwipeActionsConfiguration(actions: [star, read])
	}
}

// MARK: - Selected feed hero

/// The feed hero deliberately reuses the existing `FeedHeroIconLoader` chain. It
/// never manufactures a colour-swapped placeholder: until a real source image is
/// available it remains paper, and refreshes once the shared loader obtains one.
@MainActor private final class BabelFeedHeroHeaderView: UIView {

	static let expandedContentHeight: CGFloat = 169
	static let compactContentHeight: CGFloat = 99
	static let collapseDistance: CGFloat = expandedContentHeight - compactContentHeight

	var onBack: (() -> Void)?
	var onSearch: (() -> Void)?
	var onActions: (() -> Void)?
	var subtitle: String? {
		didSet { subtitleLabel.text = subtitle }
	}

	private let feed: Feed
	private let backgroundImageView = UIImageView()
	private let lowLightWash = UIView()
	private let titleFeatherOuter = UIView()
	private let titleFeatherCore = UIView()
	private let titleFeatherOuterGradient = CAGradientLayer()
	private let titleFeatherCoreGradient = CAGradientLayer()
	private let identityImageView = UIImageView()
	private let titleLabel = UILabel()
	private let subtitleLabel = UILabel()
	private let backButton = UIButton(type: .custom)
	private let refreshGlyph = BabelSyncGlyphView()
	private let searchButton = UIButton(type: .custom)
	private let actionsButton = UIButton(type: .custom)
	private let separator = UIView()
	private let paperFade = CAGradientLayer()
	private var scrollProgress: CGFloat = 0

	init(feed: Feed) {
		self.feed = feed
		super.init(frame: .zero)
		backgroundColor = BabelPalette.background
		clipsToBounds = true
		configureViews()
		titleLabel.text = feed.nameForDisplay
		subtitle = "\(feed.unreadCount.formatted()) 未读文章"
		loadArtwork()
	}

	required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

	private func configureViews() {
		backgroundImageView.contentMode = .scaleAspectFill
		backgroundImageView.clipsToBounds = true
		addSubview(backgroundImageView)
		lowLightWash.backgroundColor = UIColor(red: 27 / 255, green: 26 / 255, blue: 24 / 255, alpha: 0.52)
		addSubview(lowLightWash)
		paperFade.colors = [
			BabelPalette.background.withAlphaComponent(0.02).cgColor,
			BabelPalette.background.withAlphaComponent(0.04).cgColor,
			BabelPalette.background.withAlphaComponent(0.36).cgColor,
			BabelPalette.background.cgColor
		]
		paperFade.locations = [0, 0.30, 0.78, 1]
		paperFade.startPoint = CGPoint(x: 0.5, y: 0)
		paperFade.endPoint = CGPoint(x: 0.5, y: 1)
		layer.addSublayer(paperFade)

		configureFeather(titleFeatherOuter, gradient: titleFeatherOuterGradient, opacity: 0.12)
		configureFeather(titleFeatherCore, gradient: titleFeatherCoreGradient, opacity: 0.20)

		identityImageView.contentMode = .scaleAspectFill
		identityImageView.clipsToBounds = true
		identityImageView.layer.borderWidth = 0.75
		identityImageView.layer.borderColor = UIColor(red: 209 / 255, green: 209 / 255, blue: 204 / 255, alpha: 0.42).cgColor
		addSubview(identityImageView)
		titleLabel.textColor = UIColor(red: 65 / 255, green: 68 / 255, blue: 73 / 255, alpha: 0.96)
		titleLabel.numberOfLines = 1
		titleLabel.lineBreakMode = .byTruncatingTail
		addSubview(titleLabel)
		subtitleLabel.font = .systemFont(ofSize: 13, weight: .medium)
		subtitleLabel.textColor = UIColor(red: 65 / 255, green: 68 / 255, blue: 73 / 255, alpha: 0.48)
		subtitleLabel.numberOfLines = 1
		addSubview(subtitleLabel)

		configure(button: backButton, symbol: "chevron.left", label: "返回", action: #selector(didTapBack))
		configure(button: searchButton, symbol: "magnifyingglass", label: "搜索文章", action: #selector(didTapSearch))
		configure(button: actionsButton, symbol: "ellipsis", label: "更多操作", action: #selector(didTapActions))
		refreshGlyph.isUserInteractionEnabled = false
		refreshGlyph.setSyncing(false)
		addSubview(refreshGlyph)
		separator.backgroundColor = BabelPalette.hairline
		addSubview(separator)
		apply(scrollProgress: 0)
	}

	private func configure(button: UIButton, symbol: String, label: String, action: Selector) {
		button.setImage(UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .regular)), for: .normal)
		button.tintColor = BabelPalette.ink
		button.accessibilityLabel = label
		button.addTarget(self, action: action, for: .touchUpInside)
		addSubview(button)
	}

	private func configureFeather(_ feather: UIView, gradient: CAGradientLayer, opacity: CGFloat) {
		// A radial alpha falloff gives the title just enough relief on an image.
		// It intentionally has no filled, rounded plate: the Figma reference uses
		// a soft paper feather, not a pill or a card.
		feather.backgroundColor = .clear
		gradient.type = .radial
		gradient.colors = [
			BabelPalette.background.withAlphaComponent(opacity).cgColor,
			BabelPalette.background.withAlphaComponent(opacity * 0.45).cgColor,
			BabelPalette.background.withAlphaComponent(0).cgColor
		]
		gradient.locations = [0, 0.55, 1]
		gradient.startPoint = CGPoint(x: 0.5, y: 0.5)
		gradient.endPoint = CGPoint(x: 1, y: 1)
		feather.layer.addSublayer(gradient)
		addSubview(feather)
	}

	private func loadArtwork() {
		let current = FeedHeroIconLoader.shared.cachedHero(for: feed)
			?? FeedIconDownloader.shared.icon(for: feed)?.image
			?? FaviconDownloader.shared.favicon(for: feed)?.image
		applyArtwork(current)
		FeedHeroIconLoader.shared.fetchHeroIfNeeded(for: feed) { [weak self] image in
			self?.applyArtwork(image)
		}
	}

	private func applyArtwork(_ image: UIImage?) {
		guard let image else { return }
		backgroundImageView.image = image
		identityImageView.image = image
	}

	func apply(scrollProgress progress: CGFloat) {
		scrollProgress = max(0, min(1, progress))
		setNeedsLayout()
		layoutIfNeeded()
	}

	func setSyncing(_ syncing: Bool) {
		refreshGlyph.setSyncing(syncing)
	}

	override func layoutSubviews() {
		super.layoutSubviews()
		let p = scrollProgress
		backgroundImageView.frame = bounds
		lowLightWash.frame = bounds
		paperFade.frame = bounds
		// The full artwork is the only feed identity in the expanded hero. As
		// scrolling collapses the header, a duplicate of that same artwork moves
		// and scales on the direct linear scroll fraction into the compact icon.
		// There is no separately visible circular badge at progress zero.
		backgroundImageView.alpha = 1 - p
		lowLightWash.alpha = 1 - p

		// The image reaches the physical top edge, but controls stay below the
		// system status items exactly as they did before this extension.
		let topInset = safeAreaInsets.top
		let controlY = topInset
		backButton.frame = CGRect(x: 10, y: controlY, width: 44, height: 44)
		refreshGlyph.frame = CGRect(x: bounds.midX - 12, y: controlY + 10, width: 24, height: 24)
		searchButton.frame = CGRect(x: bounds.width - 94, y: controlY, width: 44, height: 44)
		actionsButton.frame = CGRect(x: bounds.width - 54, y: controlY, width: 44, height: 44)

		let compactIconFrame = CGRect(x: 20, y: topInset + 54, width: 26, height: 26)
		identityImageView.frame = CGRect(
			x: bounds.minX + (compactIconFrame.minX - bounds.minX) * p,
			y: bounds.minY + (compactIconFrame.minY - bounds.minY) * p,
			width: bounds.width + (compactIconFrame.width - bounds.width) * p,
			height: bounds.height + (compactIconFrame.height - bounds.height) * p
		)
		identityImageView.alpha = p
		identityImageView.layer.cornerRadius = 13 * p
		identityImageView.layer.borderWidth = 0.75 * p

		let titleX: CGFloat
		if p <= 0.5 { titleX = 20 + 84 * p } else { titleX = 62 - 12 * (p - 0.5) }
		let titleY = topInset + 103 - 47 * p
		let titleSize = 24 - 7 * p
		titleLabel.font = .systemFont(ofSize: titleSize, weight: .semibold)
		titleLabel.frame = CGRect(x: titleX, y: titleY, width: max(0, bounds.width - titleX - 20), height: 30)
		subtitleLabel.frame = CGRect(x: titleX, y: titleY + 30, width: max(0, bounds.width - titleX - 20), height: 18)
		subtitleLabel.alpha = 1 - min(p * 1.5, 1)
		titleFeatherOuter.frame = CGRect(x: max(2, titleX - 18), y: titleY - 7, width: min(210, bounds.width - max(2, titleX - 18) - 8), height: 46)
		titleFeatherCore.frame = CGRect(x: max(13, titleX - 7), y: titleY + 1, width: min(182, bounds.width - max(13, titleX - 7) - 8), height: 31)
		titleFeatherOuterGradient.frame = titleFeatherOuter.bounds
		titleFeatherCoreGradient.frame = titleFeatherCore.bounds
		titleFeatherOuter.alpha = 1 - p
		titleFeatherCore.alpha = 1 - p
		separator.frame = CGRect(x: 0, y: bounds.height - 1 / UIScreen.main.scale, width: bounds.width, height: 1 / UIScreen.main.scale)
		separator.alpha = p
	}

	@objc private func didTapBack() { onBack?() }
	@objc private func didTapSearch() { onSearch?() }
	@objc private func didTapActions() { onActions?() }
}

private final class BabelTimelineCell: UITableViewCell {

	static let reuseIdentifier = "BabelTimelineCell"

	private let feedLabel = UILabel()
	private let dateLabel = UILabel()
	private let titleLabel = UILabel()
	private let summaryLabel = UILabel()
	private let thumbnailView = UIImageView()
	private let feedIconView = UIImageView()
	private let separator = UIView()
	private var representedImageURL: URL?
	private var thumbnailTextConstraints = [NSLayoutConstraint]()
	private var textOnlyConstraints = [NSLayoutConstraint]()

	override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
		super.init(style: style, reuseIdentifier: reuseIdentifier)
		backgroundColor = .clear
		selectedBackgroundView = {
			let view = UIView()
			view.backgroundColor = BabelPalette.raisedBackground
			return view
		}()

		feedLabel.font = .systemFont(ofSize: 10, weight: .regular)
		feedLabel.textColor = BabelPalette.mutedInk
		feedLabel.numberOfLines = 1
		feedLabel.translatesAutoresizingMaskIntoConstraints = false
		feedLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
		contentView.addSubview(feedLabel)

		dateLabel.font = .systemFont(ofSize: 11, weight: .regular)
		dateLabel.textColor = BabelPalette.ink
		dateLabel.textAlignment = .right
		dateLabel.numberOfLines = 1
		dateLabel.translatesAutoresizingMaskIntoConstraints = false
		dateLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
		contentView.addSubview(dateLabel)

		titleLabel.font = .systemFont(ofSize: 15.5, weight: .regular)
		titleLabel.textColor = BabelPalette.ink
		titleLabel.numberOfLines = 2
		titleLabel.lineBreakMode = .byTruncatingTail
		titleLabel.translatesAutoresizingMaskIntoConstraints = false
		contentView.addSubview(titleLabel)

		summaryLabel.font = .systemFont(ofSize: 14.5, weight: .regular)
		summaryLabel.textColor = BabelPalette.mutedInk
		summaryLabel.numberOfLines = 1
		summaryLabel.lineBreakMode = .byTruncatingTail
		summaryLabel.translatesAutoresizingMaskIntoConstraints = false
		contentView.addSubview(summaryLabel)

		thumbnailView.contentMode = .scaleAspectFill
		thumbnailView.clipsToBounds = true
		thumbnailView.layer.cornerRadius = 5
		thumbnailView.backgroundColor = BabelPalette.raisedBackground
		thumbnailView.translatesAutoresizingMaskIntoConstraints = false
		contentView.addSubview(thumbnailView)
		feedIconView.contentMode = .scaleAspectFit
		feedIconView.layer.cornerRadius = 5
		feedIconView.clipsToBounds = true
		feedIconView.translatesAutoresizingMaskIntoConstraints = false
		contentView.addSubview(feedIconView)

		// Reeder separates timeline entries with whitespace; no full-width table rule.
		separator.backgroundColor = .clear
		separator.translatesAutoresizingMaskIntoConstraints = false
		contentView.addSubview(separator)

		thumbnailTextConstraints = [
			dateLabel.trailingAnchor.constraint(equalTo: thumbnailView.leadingAnchor, constant: -6),
			titleLabel.trailingAnchor.constraint(equalTo: thumbnailView.leadingAnchor, constant: -6),
			summaryLabel.trailingAnchor.constraint(equalTo: thumbnailView.leadingAnchor, constant: -6)
		]
		textOnlyConstraints = [
			dateLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
			titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
			summaryLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20)
		]

		NSLayoutConstraint.activate([
			feedLabel.leadingAnchor.constraint(equalTo: feedIconView.trailingAnchor, constant: 7),
			feedLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
			feedLabel.heightAnchor.constraint(equalToConstant: 13),
			feedLabel.trailingAnchor.constraint(lessThanOrEqualTo: dateLabel.leadingAnchor, constant: -8),
			dateLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
			dateLabel.heightAnchor.constraint(equalToConstant: 13),
			titleLabel.leadingAnchor.constraint(equalTo: feedLabel.leadingAnchor),
			titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 22),
			titleLabel.heightAnchor.constraint(equalToConstant: 39),
			summaryLabel.leadingAnchor.constraint(equalTo: feedLabel.leadingAnchor),
			summaryLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 63),
			summaryLabel.heightAnchor.constraint(equalToConstant: 19),
            separator.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            separator.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
			separator.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
			separator.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),
			feedIconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
			feedIconView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 36),
			feedIconView.widthAnchor.constraint(equalToConstant: 26),
			feedIconView.heightAnchor.constraint(equalToConstant: 26),
			thumbnailView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
			thumbnailView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 15),
            thumbnailView.widthAnchor.constraint(equalToConstant: 70),
            thumbnailView.heightAnchor.constraint(equalToConstant: 70)
		] + thumbnailTextConstraints)
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	func configure(article: Article, showsTranslatedTitle: Bool) {
		let feedText = (article.feed?.nameForDisplay ?? "订阅文章").uppercased()
		feedLabel.attributedText = Self.attributedText(feedText, font: .systemFont(ofSize: 10), color: BabelPalette.mutedInk, lineHeight: 13)
		feedIconView.image = article.feed.flatMap { FaviconDownloader.shared.faviconAsIcon(for: $0)?.image }
		feedIconView.backgroundColor = feedIconView.image == nil ? .clear : BabelPalette.raisedBackground
		let timeText = Self.timeFormatter.string(from: article.logicalDatePublished)
		dateLabel.attributedText = Self.attributedText(timeText, font: .systemFont(ofSize: 11), color: BabelPalette.ink, lineHeight: 13)
		updateTitle(article: article, showsTranslatedTitle: showsTranslatedTitle)
		// Reeder keeps a preview line when the feed did not provide an
		// explicit summary. Use the stored plain text as a visual fallback.
		let explicitSummary = BabelLibrary.summary(for: article)
		let bodyFallback = (article.contentText ?? article.contentHTML)?
			.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
			.replacingOccurrences(of: "&nbsp;", with: " ")
			.replacingOccurrences(of: "&amp;", with: "&")
			.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
			.trimmingCharacters(in: .whitespacesAndNewlines)
		let fallback = bodyFallback.flatMap { $0.isEmpty ? nil : String($0.prefix(150)) }
		let summaryText = explicitSummary ?? fallback
		summaryLabel.attributedText = summaryText.map { Self.attributedText($0, font: .systemFont(ofSize: 14.5), color: BabelPalette.mutedInk, lineHeight: 19) }
		summaryLabel.isHidden = summaryText == nil
		thumbnailView.image = ArticleThumbnail.shared.thumbnail(for: article)
		let imageLink = article.rawImageLink ?? ArticleThumbnail.shared.firstImageURL(for: article)
		let hasThumbnail = imageLink != nil
		thumbnailView.isHidden = !hasThumbnail
		NSLayoutConstraint.deactivate(hasThumbnail ? textOnlyConstraints : thumbnailTextConstraints)
		NSLayoutConstraint.activate(hasThumbnail ? thumbnailTextConstraints : textOnlyConstraints)
		thumbnailView.backgroundColor = imageLink == nil ? .clear : BabelPalette.raisedBackground
		representedImageURL = imageLink.flatMap(URL.init(string:))
		if let imageLink {
			// ImageDownloader handles disk caching and emits a notification when
			// the async fetch completes; the owning timeline reloads visible cells.
			if let data = ImageDownloader.shared.image(for: imageLink), let image = UIImage(data: data) {
				thumbnailView.contentMode = .scaleAspectFill
				thumbnailView.image = image
			}
		}
		accessibilityLabel = "\(feedLabel.text ?? "")，\(titleLabel.text ?? "")，\(dateLabel.text ?? "")"
	}

	func updateTitle(article: Article, showsTranslatedTitle: Bool) {
		let displayArticle = showsTranslatedTitle ? NNWTitleTranslationController.shared.displayArticle(for: article) : article
		let titleText = BabelLibrary.displayTitle(for: displayArticle, usesTitleTranslation: false)
		let titleFont = UIFont.systemFont(ofSize: 15.5, weight: article.status.read ? .regular : .semibold)
		let titleColor = article.status.read ? BabelPalette.mutedInk : BabelPalette.ink
		titleLabel.attributedText = Self.attributedText(titleText, font: titleFont, color: titleColor, lineHeight: 19.5)
	}

	private static func attributedText(_ text: String, font: UIFont, color: UIColor, lineHeight: CGFloat) -> NSAttributedString {
		let paragraph = NSMutableParagraphStyle()
		paragraph.minimumLineHeight = lineHeight
		paragraph.maximumLineHeight = lineHeight
		return NSAttributedString(string: text, attributes: [
			.font: font,
			.foregroundColor: color,
			.paragraphStyle: paragraph,
			.baselineOffset: (lineHeight - font.lineHeight) / 2
		])
	}

	private static let timeFormatter: DateFormatter = {
		let formatter = DateFormatter()
		formatter.dateFormat = "H:mm"
		return formatter
	}()
}
