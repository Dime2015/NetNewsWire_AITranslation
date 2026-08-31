//
//  BabelFeedsViewController.swift
//  NetNewsWire
//
//  Reeder Classic 参考中的 Feeds / Folders 层。只读展示。
//

import UIKit
import Account
import Images
import ErrorLog

final class BabelFeedsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {

    private enum Row {
        case unread
        case foldersHeader
        case folder(Folder)
        case feed(Feed)
    }

    var onSelectUnread: ((BabelArticleFilter) -> Void)?
    var onSelectFeed: ((Feed, BabelArticleFilter) -> Void)?
    var onSelectFolder: ((Folder, BabelArticleFilter) -> Void)?
    var onOpenSubscribe: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    private var rows = [Row]()
    private var collapsedFolders = Set<String>()
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let emptyLabel = UILabel()
    private let bottomBar = UIView()
    private let customHeader = UIView()
    private let headerTitleLabel = UILabel()
    private let headerSubtitleLabel = UILabel()
    private let syncGlyph = BabelSyncGlyphView()
    private let starredFilterButton = BabelFilterControl(filter: .starred)
    private let unreadFilterButton = BabelFilterControl(filter: .unread)
    private let allFilterButton = BabelFilterControl(filter: .all)
    var debugInitialScrollOffset: CGFloat = 0
    var debugExpandedFolderNames: Set<String>?
    var debugSelectedFeedName: String?
    private var didApplyInitialOffset = false
    private var didApplyDebugFolderState = false
    private var hasAppeared = false
    private var selectedFilter: BabelArticleFilter = .unread
    private var isSyncing = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = BabelPalette.background
        title = "Feeds"
        navigationItem.largeTitleDisplayMode = .never
        tableView.backgroundColor = BabelPalette.background
        tableView.separatorStyle = .none
        tableView.contentInsetAdjustmentBehavior = .never
        tableView.rowHeight = 44
        tableView.estimatedRowHeight = 44
        tableView.register(BabelFeedCell.self, forCellReuseIdentifier: BabelFeedCell.reuseIdentifier)
        emptyLabel.text = "No Feeds"
        emptyLabel.textColor = BabelPalette.mutedInk
        emptyLabel.font = BabelTypography.title(size: 17, weight: .regular)
        emptyLabel.textAlignment = .center
        emptyLabel.isHidden = true
        tableView.backgroundView = emptyLabel
        let refresh = UIRefreshControl()
		// The header's BabelSyncGlyphView is the only visible sync indicator.
		// Keep the pull gesture, but do not duplicate it with UIKit's spinner.
        refresh.tintColor = .clear
        refresh.addTarget(self, action: #selector(refreshFeeds), for: .valueChanged)
        tableView.refreshControl = refresh
        tableView.dataSource = self
        tableView.delegate = self
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: view.topAnchor, constant: 184),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -72)
        ])
        configureCustomHeader()
        configureBottomBar()
        rebuildRows()
        NotificationCenter.default.addObserver(self, selector: #selector(rebuild), name: .UnreadCountDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(rebuild), name: .AccountDidDownloadArticles, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(syncDidBegin), name: .AccountRefreshDidBegin, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(syncDidFinish), name: .AccountRefreshDidFinish, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(starredIndexDidChange), name: NNWStarredIndex.didChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(feedIconDidBecomeAvailable(_:)), name: .feedIconDidBecomeAvailable, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(faviconDidBecomeAvailable(_:)), name: .FaviconDidBecomeAvailable, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(feedSettingDidChange(_:)), name: .feedSettingDidChange, object: nil)
        // Warm the per-feed starred index before the user changes filters. It is
        // one account-level query followed by an in-memory grouping, not one
        // database query per visible source.
        NNWStarredIndex.shared.refresh()
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        hasAppeared = true
        applyInitialOffsetIfNeeded()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateSyncState()
        // An icon may have finished downloading while the article list covered
        // this controller. Re-query the shared caches when returning instead of
        // leaving an already-visible initials placeholder on screen.
        refreshVisibleFeedIcons()
    }

    private func configureCustomHeader() {
        customHeader.translatesAutoresizingMaskIntoConstraints = false
        customHeader.backgroundColor = BabelPalette.background
        view.addSubview(customHeader)

        let titleLabel = headerTitleLabel
        titleLabel.text = "Feeds"
        titleLabel.font = .systemFont(ofSize: 36, weight: .semibold)
        titleLabel.textColor = BabelPalette.ink
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        customHeader.addSubview(titleLabel)

        let subtitle = headerSubtitleLabel
        subtitle.text = nil
        subtitle.font = .systemFont(ofSize: 16, weight: .medium)
        subtitle.textColor = BabelPalette.tertiaryInk
        subtitle.textAlignment = .center
        subtitle.translatesAutoresizingMaskIntoConstraints = false
        customHeader.addSubview(subtitle)

        syncGlyph.translatesAutoresizingMaskIntoConstraints = false
        syncGlyph.isAccessibilityElement = false
        syncGlyph.isHidden = true
        customHeader.addSubview(syncGlyph)

        let settings = makeTemplateIconControl(assetName: "BabelHomeAccountToggle", label: "Settings")
        settings.accessibilityHint = "Open app settings"
        settings.accessibilityIdentifier = "babel.feeds.settings"
        settings.addTarget(self, action: #selector(showSettings), for: .touchUpInside)
        customHeader.addSubview(settings)

        let subscribe = makeTemplateIconControl(assetName: "BabelHomeAdd", label: "Add Subscription")
        subscribe.addTarget(self, action: #selector(showSubscribe), for: .touchUpInside)
        customHeader.addSubview(subscribe)

        NSLayoutConstraint.activate([
            customHeader.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            customHeader.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            customHeader.topAnchor.constraint(equalTo: view.topAnchor, constant: 59),
            customHeader.heightAnchor.constraint(equalToConstant: 125),
            settings.centerXAnchor.constraint(equalTo: customHeader.leadingAnchor, constant: BabelChromeMetrics.topSlots[0]),
            settings.centerYAnchor.constraint(equalTo: customHeader.topAnchor, constant: BabelChromeMetrics.topControlCenterY),
            settings.widthAnchor.constraint(equalToConstant: BabelChromeMetrics.minimumHitTarget),
            settings.heightAnchor.constraint(equalToConstant: BabelChromeMetrics.minimumHitTarget),
            syncGlyph.centerXAnchor.constraint(equalTo: customHeader.leadingAnchor, constant: BabelChromeMetrics.topSlots[1]),
            syncGlyph.centerYAnchor.constraint(equalTo: customHeader.topAnchor, constant: BabelChromeMetrics.topControlCenterY),
            syncGlyph.widthAnchor.constraint(equalToConstant: 24),
            syncGlyph.heightAnchor.constraint(equalToConstant: 24),
            subscribe.centerXAnchor.constraint(equalTo: customHeader.leadingAnchor, constant: 370),
            subscribe.centerYAnchor.constraint(equalTo: customHeader.topAnchor, constant: BabelChromeMetrics.topControlCenterY),
            subscribe.widthAnchor.constraint(equalToConstant: 44),
            subscribe.heightAnchor.constraint(equalToConstant: 44),
            titleLabel.leadingAnchor.constraint(equalTo: customHeader.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: customHeader.trailingAnchor, constant: -20),
            titleLabel.topAnchor.constraint(equalTo: customHeader.topAnchor, constant: 35),
            titleLabel.heightAnchor.constraint(equalToConstant: 43),
            subtitle.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitle.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            subtitle.topAnchor.constraint(equalTo: customHeader.topAnchor, constant: 76),
            subtitle.heightAnchor.constraint(equalToConstant: 22)
        ])
    }

    private func configureBottomBar() {
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.backgroundColor = BabelPalette.background
        view.addSubview(bottomBar)

        let hairline = UIView()
        hairline.translatesAutoresizingMaskIntoConstraints = false
        hairline.backgroundColor = BabelPalette.hairline
        bottomBar.addSubview(hairline)

        starredFilterButton.addTarget(self, action: #selector(selectStarredFilter), for: .touchUpInside)
        unreadFilterButton.addTarget(self, action: #selector(selectUnreadFilter), for: .touchUpInside)
        allFilterButton.addTarget(self, action: #selector(selectAllFilter), for: .touchUpInside)
        [starredFilterButton, unreadFilterButton, allFilterButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            bottomBar.addSubview($0)
        }

        NSLayoutConstraint.activate([
            bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            bottomBar.heightAnchor.constraint(equalToConstant: 72),
            hairline.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor),
            hairline.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor),
            hairline.topAnchor.constraint(equalTo: bottomBar.topAnchor),
            hairline.heightAnchor.constraint(equalToConstant: 0.5),
            starredFilterButton.centerXAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: BabelChromeMetrics.bottomSlots[1]),
            unreadFilterButton.centerXAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: BabelChromeMetrics.bottomSlots[2]),
            allFilterButton.centerXAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: BabelChromeMetrics.bottomSlots[3]),
            starredFilterButton.centerYAnchor.constraint(equalTo: bottomBar.topAnchor, constant: BabelChromeMetrics.bottomControlCenterY),
            unreadFilterButton.centerYAnchor.constraint(equalTo: starredFilterButton.centerYAnchor),
            allFilterButton.centerYAnchor.constraint(equalTo: starredFilterButton.centerYAnchor),
            starredFilterButton.widthAnchor.constraint(equalToConstant: 90),
            unreadFilterButton.widthAnchor.constraint(equalToConstant: 78),
            allFilterButton.widthAnchor.constraint(equalToConstant: 68),
            starredFilterButton.heightAnchor.constraint(equalToConstant: BabelChromeMetrics.minimumHitTarget),
            unreadFilterButton.heightAnchor.constraint(equalToConstant: BabelChromeMetrics.minimumHitTarget),
            allFilterButton.heightAnchor.constraint(equalToConstant: BabelChromeMetrics.minimumHitTarget)
        ])
        updateFilterControls(animated: false)
    }

    private func makeUnreadToolbarButton() -> UIControl {
        let button = UIControl()
        button.translatesAutoresizingMaskIntoConstraints = false
        button.accessibilityLabel = "Unread"
        let pill = UIView()
        pill.translatesAutoresizingMaskIntoConstraints = false
        pill.isUserInteractionEnabled = false
        pill.backgroundColor = BabelPalette.raisedBackground.withAlphaComponent(0.62)
        pill.layer.cornerRadius = 13
        button.addSubview(pill)
        let dot = UIView()
        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.backgroundColor = BabelPalette.tertiaryInk
        dot.layer.cornerRadius = 4
        pill.addSubview(dot)
        let title = UILabel()
        title.translatesAutoresizingMaskIntoConstraints = false
        title.text = "UNREAD"
        title.textColor = BabelPalette.tertiaryInk
        title.font = UIFont.systemFont(ofSize: 10, weight: .semibold)
        pill.addSubview(title)
        NSLayoutConstraint.activate([
            pill.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            pill.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            pill.widthAnchor.constraint(equalToConstant: 78),
            pill.heightAnchor.constraint(equalToConstant: 26),
            dot.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 8),
            dot.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: 8),
            dot.heightAnchor.constraint(equalToConstant: 8),
            title.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 7),
            title.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
            title.widthAnchor.constraint(equalToConstant: 47)
        ])
        return button
    }

    private func makeTemplateIconControl(assetName: String, label: String) -> UIControl {
        let control = UIControl()
        control.translatesAutoresizingMaskIntoConstraints = false
        control.accessibilityLabel = label
        let imageView = UIImageView(image: UIImage(named: assetName)?.withRenderingMode(.alwaysTemplate))
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = BabelPalette.mutedInk
        imageView.isUserInteractionEnabled = false
        control.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: control.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: control.centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 24),
            imageView.heightAnchor.constraint(equalToConstant: 24)
        ])
        return control
    }

    @objc private func selectStarredFilter() { selectFilter(.starred) }
    @objc private func selectUnreadFilter() { selectFilter(.unread) }
    @objc private func selectAllFilter() { selectFilter(.all) }

    private func selectFilter(_ filter: BabelArticleFilter) {
        guard selectedFilter != filter else { return }
        selectedFilter = filter
        updateFilterControls(animated: true)
        rebuildRows()
        if filter == .starred {
            NNWStarredIndex.shared.refresh()
        }
    }

    private func updateFilterControls(animated: Bool) {
        starredFilterButton.setSelected(selectedFilter == .starred, animated: animated)
        unreadFilterButton.setSelected(selectedFilter == .unread, animated: animated)
        allFilterButton.setSelected(selectedFilter == .all, animated: animated)
    }

    @objc private func closeFeeds() { navigationController?.popViewController(animated: true) }

    private func folderKey(_ folder: Folder) -> String {
        "\(folder.accountID):\(folder.nameForDisplay)"
    }

    private func rebuildRows() {
        let accounts = AccountManager.shared.sortedActiveAccounts
        if !didApplyDebugFolderState, let expandedNames = debugExpandedFolderNames {
            let folders = accounts.flatMap { $0.folders ?? [] }
            for folder in folders where !expandedNames.contains(folder.nameForDisplay) {
                collapsedFolders.insert(folderKey(folder))
            }
            didApplyDebugFolderState = !folders.isEmpty
        }

        var sourceRows = [Row]()
        for account in accounts {
            for folder in (account.folders ?? []).sorted(by: { $0.nameForDisplay < $1.nameForDisplay }) {
                let visibleFeeds = filteredFeeds(folder.topLevelFeeds)
                if selectedFilter == .starred, NNWStarredIndex.shared.hasLoaded, visibleFeeds.isEmpty {
                    continue
                }
                sourceRows.append(.folder(folder))
                if !collapsedFolders.contains(folderKey(folder)) {
                    sourceRows.append(contentsOf: visibleFeeds.map(Row.feed))
                }
            }
            sourceRows.append(contentsOf: filteredFeeds(account.topLevelFeeds).map(Row.feed))
        }
        rows = [.unread]
        if !sourceRows.isEmpty {
            rows.append(.foldersHeader)
            rows.append(contentsOf: sourceRows)
        }
        emptyLabel.text = selectedFilter == .starred ? "No Starred Feeds" : "No Feeds"
        tableView.reloadData()
        restoreSelectedFeedIfNeeded()
        emptyLabel.isHidden = rows.contains { row in
            if case .feed = row { return true }
            return false
        }
        // A fresh install can receive the account snapshot after the view has
        // appeared. Apply the initial Reeder scroll position only after rows
        // exist, otherwise UIKit clamps the offset against the empty table.
        applyInitialOffsetIfNeeded()
    }

    private func applyInitialOffsetIfNeeded() {
        guard hasAppeared, !didApplyInitialOffset,
              rows.contains(where: { if case .feed = $0 { return true }; return false }) else { return }
        didApplyInitialOffset = true
        DispatchQueue.main.async { [weak self] in
            self?.tableView.setContentOffset(CGPoint(x: 0, y: self?.debugInitialScrollOffset ?? 300), animated: false)
        }
    }

    @objc private func rebuild() { rebuildRows() }

    @objc private func starredIndexDidChange() {
        guard selectedFilter == .starred else { return }
        rebuildRows()
    }

    @objc private func feedIconDidBecomeAvailable(_ notification: Notification) {
        guard let feed = notification.userInfo?[UserInfoKey.feed] as? Feed else { return }
        refreshVisibleFeedIcons(matching: feed)
    }

    @objc private func faviconDidBecomeAvailable(_ notification: Notification) {
        // Favicon notifications identify the downloaded URL, not the Feed. A
        // homepage can be shared by several feeds, so re-query only the visible
        // feed rows. This is cheap and avoids rebuilding or flickering the table.
        refreshVisibleFeedIcons()
    }

    @objc private func feedSettingDidChange(_ notification: Notification) {
        guard let feed = notification.object as? Feed,
              let key = notification.userInfo?[Feed.SettingUserInfoKey] as? Feed.SettingKey,
              key == .iconURL || key == .homePageURL || key == .faviconURL else { return }
        refreshVisibleFeedIcons(matching: feed)
    }

    private func refreshVisibleFeedIcons(matching targetFeed: Feed? = nil) {
        for indexPath in tableView.indexPathsForVisibleRows ?? [] {
            guard rows.indices.contains(indexPath.row),
                  case .feed(let feed) = rows[indexPath.row],
                  targetFeed.map({ feedsRepresentSameSource(feed, $0) }) ?? true,
                  let cell = tableView.cellForRow(at: indexPath) as? BabelFeedCell else { continue }
            cell.updateIcon(feedIcon(for: feed), initials: feedInitials(for: feed.nameForDisplay))
        }
    }

    private func feedsRepresentSameSource(_ lhs: Feed, _ rhs: Feed) -> Bool {
        lhs.accountID == rhs.accountID && lhs.feedID == rhs.feedID
    }

    private func feedIcon(for feed: Feed) -> UIImage? {
        // Match the article-list hero exactly. Podcast and YouTube feeds often
        // have no declared icon/favicon; their usable artwork is discovered as
        // homepage metadata and persisted by FeedHeroIconLoader. This cache is
        // why an article list can already show artwork while Feeds still showed
        // initials. Do not start hero downloads for every row here; returning
        // from the article list re-queries its existing memory/disk cache.
        FeedHeroIconLoader.shared.cachedHero(for: feed)
            ?? FeedIconDownloader.shared.icon(for: feed)?.image
            ?? FaviconDownloader.shared.faviconAsIcon(for: feed)?.image
    }

    @objc private func syncDidBegin() {
        updateSyncState()
    }

    @objc private func syncDidFinish() {
        updateSyncState()
        if !isSyncing { tableView.refreshControl?.endRefreshing() }
    }

    private func updateSyncState() {
        isSyncing = AccountManager.shared.sortedActiveAccounts.contains(where: \.refreshInProgress)
        updateSyncSubtitle()
    }

    private func updateSyncSubtitle() {
        headerSubtitleLabel.text = isSyncing ? "Syncing..." : nil
        headerSubtitleLabel.isHidden = !isSyncing
        syncGlyph.setSyncing(isSyncing)
    }

    @objc private func refreshFeeds() {
        // Account emits AccountRefreshDidBegin only when a real refresh begins.
        // The passive status must not be fabricated for an idle tap.
        AccountManager.shared.refreshAllWithoutWaiting(errorHandler: ErrorHandler.log)
    }

    @objc private func showFeedIssues() {
        let controller = BabelFeedIssuesViewController()
        if let sheet = controller.sheetPresentationController {
            // Keep the compact state tall enough to show both the title and
            // the empty/error message without clipping the status text.
            let compact = UISheetPresentationController.Detent.custom(identifier: .init("babelFeedIssuesCompact")) { _ in 180 }
            sheet.detents = [compact, .large()]
            sheet.selectedDetentIdentifier = compact.identifier
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 18
        }
        present(controller, animated: true)
    }

    /// Deterministic entry used by simulator screenshot checks.
    func presentFeedIssuesForDebug() { showFeedIssues() }

    func presentStarredFilterForDebug() { selectFilter(.starred) }

    @objc private func showFeedActions() {
        let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "Mark All as Read", style: .default) { [weak self] _ in
            self?.markAllArticles(read: true)
        })
        alert.addAction(UIAlertAction(title: "Mark All as Unread", style: .default) { [weak self] _ in
            self?.markAllArticles(read: false)
        })
        alert.addAction(UIAlertAction(title: "Refresh", style: .default) { [weak self] _ in
            self?.refreshFeeds()
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if traitCollection.userInterfaceIdiom == .pad, let popover = alert.popoverPresentationController {
            popover.sourceView = bottomBar
            popover.sourceRect = CGRect(x: bottomBar.bounds.midX, y: 0, width: 1, height: 1)
        }
        present(alert, animated: true)
    }

    private func markAllArticles(read: Bool) {
        let accounts = AccountManager.shared.sortedActiveAccounts
        Task { @MainActor in
            for account in accounts {
                var ids = Set<String>()
                for feed in account.flattenedFeeds() {
                    let articles = await account.fetchArticlesAsync(.feed(feed))
                    ids.formUnion(articles.map(\.articleID))
                }
                guard !ids.isEmpty else { continue }
                try? await account.markArticles(articleIDs: ids, statusKey: .read, flag: read)
            }
            rebuildRows()
        }
    }

    @objc private func showSubscribe() {
        onOpenSubscribe?()
    }

    @objc private func showSettings() {
        onOpenSettings?()
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { rows.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: BabelFeedCell.reuseIdentifier, for: indexPath) as! BabelFeedCell
        // Spacer rows are intentionally inert, but reused cells must regain
        // interaction before representing a real feed or folder.
        cell.isUserInteractionEnabled = true
        switch rows[indexPath.row] {
        case .unread:
            let summary: (title: String, count: Int?)
            switch selectedFilter {
            case .unread: summary = ("Unread", AccountManager.shared.unreadCount)
            case .starred: summary = ("Starred", NNWStarredIndex.shared.hasLoaded ? NNWStarredIndex.shared.totalStarredCount() : nil)
            case .all: summary = ("All", nil)
            }
            cell.configure(title: summary.title, count: summary.count, image: nil, indent: 0, isFolder: false, sectionHeader: true, showsTopRule: true)
            cell.accessibilityIdentifier = "babel.feeds.row.summary"
        case .foldersHeader:
            cell.configure(title: "Folders", count: nil, image: nil, indent: 0, isFolder: false, sectionHeader: true)
            cell.accessibilityIdentifier = "babel.feeds.row.folders"
        case .folder(let folder):
            let expanded = !collapsedFolders.contains(folderKey(folder))
            let key = folderKey(folder)
            cell.configure(title: folder.nameForDisplay, count: displayedCount(for: folder), image: nil, indent: 0, isFolder: true, expanded: expanded) { [weak self] in
                guard let self else { return }
                if self.collapsedFolders.contains(key) { self.collapsedFolders.remove(key) } else { self.collapsedFolders.insert(key) }
                self.rebuildRows()
            }
            cell.accessibilityIdentifier = "babel.feeds.row.folder.\(folder.nameForDisplay)"
        case .feed(let feed):
            let icon = feedIcon(for: feed)
            cell.configure(title: feed.nameForDisplay, count: displayedCount(for: feed), image: icon, indent: 1, isFolder: false, initials: feedInitials(for: feed.nameForDisplay))
            cell.accessibilityIdentifier = "babel.feeds.row.feed.\(feed.nameForDisplay)"
        }
        return cell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        switch rows[indexPath.row] {
        case .unread: return 68
        case .foldersHeader: return 82
        case .folder, .feed: return 44
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        switch rows[indexPath.row] {
        case .unread:
            tableView.deselectRow(at: indexPath, animated: true)
            onSelectUnread?(selectedFilter)
        case .foldersHeader:
            tableView.deselectRow(at: indexPath, animated: true)
        case .folder(let folder):
            tableView.deselectRow(at: indexPath, animated: true)
            onSelectFolder?(folder, selectedFilter)
        case .feed(let feed):
            onSelectFeed?(feed, selectedFilter)
        }
    }

    private func restoreSelectedFeedIfNeeded() {
        guard let selectedName = debugSelectedFeedName else { return }
        let namedRow = rows.firstIndex(where: {
            if case .feed(let feed) = $0 { return feed.nameForDisplay == selectedName }
            return false
        })
        // The connected simulator can contain a different account dataset
        // from the locked Figma sample. In screenshot mode, use the fifth
        // visible feed as a geometry-only fallback because it occupies the
        // same 510pt selected-row slot as node 19:18.
        let fallbackRow = rows.indices.filter { if case .feed = rows[$0] { return true }; return false }.dropFirst(4).first
        guard let row = namedRow ?? fallbackRow else { return }
        DispatchQueue.main.async { [weak self] in
            self?.tableView.selectRow(at: IndexPath(row: row, section: 0), animated: false, scrollPosition: .none)
        }
    }

    private func feedInitials(for title: String) -> String {
        if title.lowercased().hasPrefix("www.") {
            let domain = title.dropFirst(4).split(separator: ".").first.map(String.init) ?? title
            return String(domain.prefix(1)).uppercased()
        }
        let characters = Array(title)
        if characters.contains(where: { $0.unicodeScalars.contains(where: { $0.value >= 0x3000 }) }) {
            return String(characters.prefix(2))
        }
        let tokens = title.split { !$0.isLetter && !$0.isNumber }.filter { !$0.isEmpty }
        if tokens.count >= 2 {
            return tokens.suffix(2).compactMap(\.first).map(String.init).joined().uppercased()
        }
        return tokens.first.map { String($0.prefix(2)).uppercased() } ?? ""
    }

    private func filteredFeeds<S: Sequence>(_ feeds: S) -> [Feed] where S.Element == Feed {
        feeds
            .filter { feed in
                guard selectedFilter == .starred, NNWStarredIndex.shared.hasLoaded else { return true }
                return NNWStarredIndex.shared.starredCount(forFeedID: feed.feedID, accountID: feed.accountID) > 0
            }
            .sorted(by: { $0.nameForDisplay < $1.nameForDisplay })
    }

    private func displayedCount(for feed: Feed) -> Int? {
        switch selectedFilter {
        case .unread: return feed.unreadCount
        case .starred:
            guard NNWStarredIndex.shared.hasLoaded else { return nil }
            return NNWStarredIndex.shared.starredCount(forFeedID: feed.feedID, accountID: feed.accountID)
        case .all: return nil
        }
    }

    private func displayedCount(for folder: Folder) -> Int? {
        switch selectedFilter {
        case .unread: return folder.unreadCount
        case .starred:
            guard NNWStarredIndex.shared.hasLoaded else { return nil }
            return NNWStarredIndex.shared.starredCount(for: folder)
        case .all: return nil
        }
    }
}

private final class BabelFeedIssuesViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = BabelPalette.background

        let close = UIButton(type: .custom)
        close.setImage(UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)), for: .normal)
        close.tintColor = BabelPalette.ink
        close.accessibilityIdentifier = "babel.feed-issues.close"
        close.addTarget(self, action: #selector(closeSheet), for: .touchUpInside)
        close.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(close)

        let title = UILabel()
        title.text = "Feed Issues"
        title.font = BabelTypography.title(size: 36, weight: .bold)
        title.textColor = BabelPalette.ink
        title.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(title)

        let message = UILabel()
        message.text = "No feed issues"
        message.font = BabelTypography.title(size: 17, weight: .regular)
        message.textColor = BabelPalette.mutedInk
        message.textAlignment = .left
        message.numberOfLines = 0
        message.accessibilityIdentifier = "babel.feed-issues.message"
        message.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(message)

        NSLayoutConstraint.activate([
            close.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            close.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            close.widthAnchor.constraint(equalToConstant: 44), close.heightAnchor.constraint(equalToConstant: 44),
            title.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            title.topAnchor.constraint(equalTo: close.bottomAnchor, constant: 20),
            message.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 18),
            message.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            message.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28)
        ])
		Task { @MainActor in
			let entries = await AccountManager.shared.errorLogDatabase.allEntries()
			if entries.isEmpty {
				message.text = "No feed issues"
			} else {
				message.text = entries.prefix(5).map { entry in
					let operation = entry.operation.isEmpty ? "Feed" : entry.operation
					return "\(entry.sourceName) · \(operation)\n\(entry.errorMessage)"
				}.joined(separator: "\n\n")
			}
		}
    }

    @objc private func closeSheet() { dismiss(animated: true) }
}

private final class BabelFeedCell: UITableViewCell {
    static let reuseIdentifier = "BabelFeedCell"
    private let iconContainer = UIView()
    private let iconView = UIImageView()
    private let initialsLabel = UILabel()
    private let titleLabel = UILabel()
    private let countLabel = UILabel()
    private let disclosureButton = BabelFolderDisclosureControl()
    private let ruleView = UIView()
    private var layoutConstraints = [NSLayoutConstraint]()
    private var toggleFolder: (() -> Void)?
    private var usesInitials = false

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        let selection = UIView()
        selection.backgroundColor = BabelPalette.raisedBackground
        selection.layer.cornerRadius = 10
        selectedBackgroundView = selection

        iconContainer.layer.cornerRadius = 3
        iconContainer.clipsToBounds = true
        iconView.contentMode = .scaleAspectFit
        initialsLabel.font = .systemFont(ofSize: 10, weight: .medium)
        initialsLabel.textAlignment = .center
        titleLabel.textColor = BabelPalette.ink
        titleLabel.lineBreakMode = .byTruncatingTail
        countLabel.textColor = BabelPalette.tertiaryInk
        countLabel.textAlignment = .right
        ruleView.backgroundColor = BabelPalette.hairline

        for subview in [iconContainer, titleLabel, countLabel, disclosureButton, ruleView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(subview)
        }
        for subview in [iconView, initialsLabel] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            iconContainer.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: iconContainer.leadingAnchor),
            iconView.trailingAnchor.constraint(equalTo: iconContainer.trailingAnchor),
            iconView.topAnchor.constraint(equalTo: iconContainer.topAnchor),
            iconView.bottomAnchor.constraint(equalTo: iconContainer.bottomAnchor),
            initialsLabel.leadingAnchor.constraint(equalTo: iconContainer.leadingAnchor),
            initialsLabel.trailingAnchor.constraint(equalTo: iconContainer.trailingAnchor),
            initialsLabel.topAnchor.constraint(equalTo: iconContainer.topAnchor),
            initialsLabel.bottomAnchor.constraint(equalTo: iconContainer.bottomAnchor)
        ])
        disclosureButton.addTarget(self, action: #selector(disclosureTapped), for: .touchUpInside)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        selectedBackgroundView?.frame = bounds.insetBy(dx: 10, dy: 0)
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
        updateInitialsAppearance(selected: selected)
    }

    func configure(
        title: String,
        count: Int?,
        image: UIImage?,
        indent: Int,
        isFolder: Bool,
        expanded: Bool = false,
        sectionHeader: Bool = false,
        showsTopRule: Bool = false,
        initials: String? = nil,
        toggleFolder: (() -> Void)? = nil
    ) {
        NSLayoutConstraint.deactivate(layoutConstraints)
        layoutConstraints.removeAll()

        self.toggleFolder = toggleFolder
        titleLabel.text = title
        countLabel.text = count?.formatted()
        countLabel.isHidden = count == nil
        ruleView.isHidden = !showsTopRule

        disclosureButton.isHidden = !isFolder
        disclosureButton.isExpanded = expanded
        disclosureButton.accessibilityLabel = isFolder ? title : nil
        disclosureButton.accessibilityValue = isFolder ? (expanded ? "Expanded" : "Collapsed") : nil

        iconView.image = image
        usesInitials = !sectionHeader && !isFolder && image == nil
        initialsLabel.text = usesInitials ? initials : nil
        iconContainer.isHidden = sectionHeader || isFolder
        iconView.isHidden = image == nil
        initialsLabel.isHidden = !usesInitials
        updateInitialsAppearance(selected: isSelected)

        if sectionHeader {
            titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
            countLabel.font = .systemFont(ofSize: 20, weight: .regular)
            layoutConstraints = [
                ruleView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 111),
                ruleView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 2),
                ruleView.widthAnchor.constraint(equalToConstant: 180),
                ruleView.heightAnchor.constraint(equalToConstant: 0.5),
                titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
                titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 31),
                titleLabel.heightAnchor.constraint(equalToConstant: 28),
                titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: countLabel.leadingAnchor, constant: -12),
                countLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
                countLabel.topAnchor.constraint(equalTo: titleLabel.topAnchor),
                countLabel.heightAnchor.constraint(equalToConstant: 28),
                countLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 92)
            ]
        } else if isFolder {
            titleLabel.font = .systemFont(ofSize: 18, weight: .semibold)
            countLabel.font = .systemFont(ofSize: 18, weight: .regular)
            layoutConstraints = [
                disclosureButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 17),
                disclosureButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
                disclosureButton.widthAnchor.constraint(equalToConstant: 44),
                disclosureButton.heightAnchor.constraint(equalToConstant: 44),
                titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 56),
                titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
                titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: countLabel.leadingAnchor, constant: -12),
                countLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
                countLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
                countLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 72)
            ]
        } else {
            titleLabel.font = .systemFont(ofSize: 17, weight: .medium)
            countLabel.font = .systemFont(ofSize: 17, weight: .regular)
            layoutConstraints = [
                iconContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 49),
                iconContainer.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
                iconContainer.widthAnchor.constraint(equalToConstant: 24),
                iconContainer.heightAnchor.constraint(equalToConstant: 24),
                titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 79),
                titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
                titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: countLabel.leadingAnchor, constant: -12),
                countLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18),
                countLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
                countLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 65)
            ]
        }
        NSLayoutConstraint.activate(layoutConstraints)
    }

    func updateIcon(_ image: UIImage?, initials: String?) {
        iconView.image = image
        usesInitials = image == nil
        initialsLabel.text = usesInitials ? initials : nil
        iconView.isHidden = image == nil
        initialsLabel.isHidden = !usesInitials
        updateInitialsAppearance(selected: isSelected)
    }

    private func updateInitialsAppearance(selected: Bool) {
        guard usesInitials else {
            iconContainer.backgroundColor = .clear
            return
        }
        iconContainer.backgroundColor = selected ? BabelPalette.raisedBackground : .clear
        initialsLabel.textColor = selected ? BabelPalette.ink : BabelPalette.mutedInk
    }

    @objc private func disclosureTapped() { toggleFolder?() }
}

private final class BabelFolderDisclosureControl: UIControl {
    var isExpanded = false { didSet { setNeedsDisplay() } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: BabelFolderDisclosureControl, _) in
            self.setNeedsDisplay()
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ rect: CGRect) {
        let origin = CGPoint(x: rect.midX - 9, y: rect.midY - 9)
        let path = UIBezierPath()
        if isExpanded {
            path.move(to: CGPoint(x: origin.x + 3, y: origin.y + 7))
            path.addLine(to: CGPoint(x: origin.x + 9, y: origin.y + 13))
            path.addLine(to: CGPoint(x: origin.x + 15, y: origin.y + 7))
        } else {
            path.move(to: CGPoint(x: origin.x + 6, y: origin.y + 3))
            path.addLine(to: CGPoint(x: origin.x + 12, y: origin.y + 9))
            path.addLine(to: CGPoint(x: origin.x + 6, y: origin.y + 15))
        }
        BabelPalette.mutedInk.setStroke()
        path.lineWidth = 2.5
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()
    }
}

final class BabelSyncGlyphView: UIView {
    private static let rotationAnimationKey = "babel.sync.rotation"
    private var syncing = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        isUserInteractionEnabled = false
        isHidden = true
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: BabelSyncGlyphView, _) in
            self.setNeedsDisplay()
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setSyncing(_ syncing: Bool) {
        self.syncing = syncing
        isHidden = !syncing
        updateRotationAnimation()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateRotationAnimation()
    }

    private func updateRotationAnimation() {
        guard syncing, window != nil else {
            layer.removeAnimation(forKey: Self.rotationAnimationKey)
            return
        }
        guard layer.animation(forKey: Self.rotationAnimationKey) == nil else { return }
        let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
        rotation.fromValue = 0
        rotation.toValue = CGFloat.pi * 2
        rotation.duration = 0.9
        rotation.repeatCount = .infinity
        rotation.timingFunction = CAMediaTimingFunction(name: .linear)
        rotation.isRemovedOnCompletion = false
        layer.add(rotation, forKey: Self.rotationAnimationKey)
    }

    override func draw(_ rect: CGRect) {
        BabelPalette.raisedBackground.withAlphaComponent(0.47).setFill()
        UIBezierPath(ovalIn: rect).fill()

        let path = UIBezierPath()
        path.move(to: CGPoint(x: 11.13, y: 7.08))
        path.addCurve(to: CGPoint(x: 14.4405, y: 7.64817), controlPoint1: CGPoint(x: 12.26599, y: 6.88199), controlPoint2: CGPoint(x: 13.4355, y: 7.08271))
        path.addCurve(to: CGPoint(x: 16.6444, y: 10.18281), controlPoint1: CGPoint(x: 15.4454, y: 8.21363), controlPoint2: CGPoint(x: 16.224, y: 9.10907))
        path.addCurve(to: CGPoint(x: 16.7473, y: 13.5401), controlPoint1: CGPoint(x: 17.0648, y: 11.25656), controlPoint2: CGPoint(x: 17.1012, y: 12.44262))
        path.addCurve(to: CGPoint(x: 14.7027, y: 16.205), controlPoint1: CGPoint(x: 16.3935, y: 14.6376), controlPoint2: CGPoint(x: 15.6712, y: 15.579))
        path.addCurve(to: CGPoint(x: 11.43327, y: 16.9748), controlPoint1: CGPoint(x: 13.73428, y: 16.8309), controlPoint2: CGPoint(x: 12.57925, y: 17.1029))
        path.addCurve(to: CGPoint(x: 8.41442, y: 15.5022), controlPoint1: CGPoint(x: 10.28729, y: 16.8467), controlPoint2: CGPoint(x: 9.22079, y: 16.3265))
        path.addCurve(to: CGPoint(x: 7.00852, y: 12.45174), controlPoint1: CGPoint(x: 7.60805, y: 14.6779), controlPoint2: CGPoint(x: 7.11138, y: 13.60026))
        path.addCurve(to: CGPoint(x: 7.85, y: 9.2), controlPoint1: CGPoint(x: 6.90565, y: 11.30322), controlPoint2: CGPoint(x: 7.20293, y: 10.15445))
        BabelPalette.ink.withAlphaComponent(0.91).setStroke()
        path.lineWidth = 2.2
        path.lineCapStyle = .round
        path.stroke()

        let arrow = UIBezierPath()
        arrow.move(to: CGPoint(x: 4.45, y: 11.1))
        arrow.addLine(to: CGPoint(x: 7.25, y: 6.2))
        arrow.addLine(to: CGPoint(x: 10.05, y: 10.85))
        arrow.close()
        BabelPalette.ink.withAlphaComponent(0.91).setFill()
        arrow.fill()
    }
}
