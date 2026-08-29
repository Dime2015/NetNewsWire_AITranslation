//
//  BabelTimelineViewController.swift
//  NetNewsWire
//

import UIKit
import Account
import Articles
import Images

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
	private let tableView = UITableView(frame: .zero, style: .plain)
	private let emptyLabel = UILabel()
	private let loadingIndicator = UIActivityIndicatorView(style: .medium)
	private let navTitleLabel = UILabel()
	private let navSubtitleLabel = UILabel()
	private let timelineHeader = UIView()
	private var articles = [Article]()
	private var daySections = [(date: Date, articles: [Article])]()
	private var loadTask: Task<Void, Never>?
	private var searchQuery = ""
	private enum ArticleFilter { case all, unread, starred }
	private var articleFilter: ArticleFilter = .all

	init(section: BabelLibrarySection) {
		self.source = .section(section)
		super.init(nibName: nil, bundle: nil)
	}

	init(feed: Feed) {
		self.source = .feed(feed)
		super.init(nibName: nil, bundle: nil)
	}

	init(folder: Folder) {
		self.source = .folder(folder)
		super.init(nibName: nil, bundle: nil)
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		configureView()
		reloadArticles()
		startObserving()
	}

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		navigationController?.setNavigationBarHidden(true, animated: animated)
		// A reader marks an article read while it is visible. Refresh the
		// timeline on return so counts and row styling reflect that change,
		// while UITableView preserves the user's current content offset.
		if isViewLoaded {
			reloadArticles()
		}
	}

	override func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)
		navigationController?.setNavigationBarHidden(false, animated: animated)
	}

	deinit {
		loadTask?.cancel()
		NotificationCenter.default.removeObserver(self)
	}

	@objc private func imageDidBecomeAvailable() {
		tableView.reloadRows(at: tableView.indexPathsForVisibleRows ?? [], with: .none)
	}

	private func configureView() {
		title = source.title
		view.backgroundColor = BabelPalette.background
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
		tableView.separatorStyle = .none
		// The custom header already occupies the top region; a small inset keeps
		// the first day label just below it, matching Reeder's timeline rhythm.
		tableView.contentInset = UIEdgeInsets(top: 30, left: 0, bottom: 62, right: 0)
		tableView.rowHeight = UITableView.automaticDimension
		tableView.estimatedRowHeight = 154
		tableView.register(BabelTimelineCell.self, forCellReuseIdentifier: BabelTimelineCell.reuseIdentifier)
		tableView.dataSource = self
		tableView.delegate = self
		NotificationCenter.default.addObserver(self, selector: #selector(imageDidBecomeAvailable), name: .imageDidBecomeAvailable, object: nil)
		view.addSubview(tableView)
		tableView.babelPinToEdges(of: view)

		emptyLabel.text = "No Articles"
		emptyLabel.font = BabelTypography.reading(size: 19)
		emptyLabel.textColor = BabelPalette.mutedInk
		emptyLabel.textAlignment = .center
		emptyLabel.isHidden = true
		emptyLabel.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(emptyLabel)
		loadingIndicator.color = BabelPalette.mutedInk
		loadingIndicator.hidesWhenStopped = true
		loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(loadingIndicator)
		NSLayoutConstraint.activate([
			emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
			emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
			loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
			loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
		])

		let refreshControl = UIRefreshControl()
		refreshControl.addTarget(self, action: #selector(refreshFromControl), for: .valueChanged)
        tableView.refreshControl = refreshControl

        let bottom = UIStackView()
        bottom.axis = .horizontal
        bottom.distribution = .equalCentering
        bottom.alignment = .center
        bottom.backgroundColor = BabelPalette.background
        bottom.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bottom)
        for (symbol, label) in [("checkmark.circle.fill", "已读"), ("star.fill", "星标"),
                                ("circle.fill", "未读"), ("list.bullet", "列表"),
                                ("magnifyingglass", "搜索")] {
            let button = makeTimelineToolbarButton(symbol: symbol, label: label)
            button.accessibilityLabel = label
            button.accessibilityIdentifier = "babel.timeline.toolbar.\(label)"
            switch label {
            case "已读": button.addTarget(self, action: #selector(markAllRead), for: .touchUpInside)
            case "星标": button.addTarget(self, action: #selector(openSaved), for: .touchUpInside)
            case "未读": button.addTarget(self, action: #selector(openUnread), for: .touchUpInside)
			case "列表": button.addTarget(self, action: #selector(showFilterMenu), for: .touchUpInside)
            case "搜索": button.addTarget(self, action: #selector(showSearch), for: .touchUpInside)
            default: break
            }
            bottom.addArrangedSubview(button)
        }
        NSLayoutConstraint.activate([
            bottom.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottom.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottom.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            bottom.heightAnchor.constraint(equalToConstant: 90)
        ])
		view.bringSubviewToFront(bottom)
        view.bringSubviewToFront(timelineHeader)
	}

    private func makeTimelineToolbarButton(symbol: String, label: String) -> UIButton {
        if label == "未读" {
            var config = UIButton.Configuration.plain()
            config.baseForegroundColor = BabelPalette.mutedInk
            config.background.backgroundColor = BabelPalette.raisedBackground
            config.background.cornerRadius = 14
            let button = UIButton(configuration: config)
            button.translatesAutoresizingMaskIntoConstraints = false
            let dot = UIView()
            dot.translatesAutoresizingMaskIntoConstraints = false
            dot.backgroundColor = BabelPalette.mutedInk
            dot.layer.cornerRadius = 5
            button.addSubview(dot)
            let title = UILabel()
            title.translatesAutoresizingMaskIntoConstraints = false
            title.text = "UNREAD"
            title.textColor = BabelPalette.mutedInk
            title.font = UIFont.systemFont(ofSize: 10, weight: .semibold)
            title.adjustsFontSizeToFitWidth = true
            title.minimumScaleFactor = 0.8
            title.lineBreakMode = .byClipping
            button.addSubview(title)
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant: 76),
                button.heightAnchor.constraint(equalToConstant: 28),
                dot.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 10),
                dot.centerYAnchor.constraint(equalTo: button.centerYAnchor),
                dot.widthAnchor.constraint(equalToConstant: 10), dot.heightAnchor.constraint(equalToConstant: 10),
                title.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 6),
                title.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -4),
                title.centerYAnchor.constraint(equalTo: button.centerYAnchor)
            ])
            return button
        }
        var config = UIButton.Configuration.plain()
        config.baseForegroundColor = BabelPalette.mutedInk
        config.image = UIImage(systemName: symbol)
        // Match Reeder's compact bottom control glyphs on the 3x iPhone
        // canvas; the button hit targets remain 44pt for accessibility.
        let pointSize: CGFloat = label == "已读" ? 14 : (label == "搜索" ? 16 : (label == "列表" ? 8 : 12))
        config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        config.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4)
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 44).isActive = true
        button.heightAnchor.constraint(equalToConstant: 36).isActive = true
        return button
    }

	private func configureTimelineHeader() {
		timelineHeader.translatesAutoresizingMaskIntoConstraints = false
		timelineHeader.backgroundColor = BabelPalette.background
		view.addSubview(timelineHeader)
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
		let actions = UIButton(type: .custom)
		actions.setImage(UIImage(systemName: "ellipsis"), for: .normal)
		actions.tintColor = BabelPalette.ink
		actions.addTarget(self, action: #selector(showActions), for: .touchUpInside)
		actions.translatesAutoresizingMaskIntoConstraints = false
		timelineHeader.addSubview(actions)
		NSLayoutConstraint.activate([
			timelineHeader.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			timelineHeader.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			timelineHeader.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
			timelineHeader.heightAnchor.constraint(equalToConstant: 68),
			back.leadingAnchor.constraint(equalTo: timelineHeader.leadingAnchor),
			back.centerYAnchor.constraint(equalTo: timelineHeader.topAnchor, constant: 24),
			back.widthAnchor.constraint(equalToConstant: 44), back.heightAnchor.constraint(equalToConstant: 44),
			navTitleLabel.centerXAnchor.constraint(equalTo: timelineHeader.centerXAnchor),
			navTitleLabel.topAnchor.constraint(equalTo: timelineHeader.topAnchor, constant: 8),
			navSubtitleLabel.centerXAnchor.constraint(equalTo: timelineHeader.centerXAnchor),
			navSubtitleLabel.topAnchor.constraint(equalTo: navTitleLabel.bottomAnchor),
			actions.trailingAnchor.constraint(equalTo: timelineHeader.trailingAnchor, constant: -16),
			actions.centerYAnchor.constraint(equalTo: timelineHeader.topAnchor, constant: 24),
			actions.widthAnchor.constraint(equalToConstant: 44), actions.heightAnchor.constraint(equalToConstant: 44)
		])
	}

	@objc private func closeTimeline() { navigationController?.popViewController(animated: true) }

	private func startObserving() {
		let names: [Notification.Name] = [
			.UnreadCountDidChange,
			.AccountDidDownloadArticles,
			.nnwTitleTranslationDidUpdate
		]
		for name in names {
			NotificationCenter.default.addObserver(self, selector: #selector(dataDidChange), name: name, object: nil)
		}
	}

	@objc private func dataDidChange() {
		reloadArticles()
	}

    @objc private func refreshFromControl() {
        reloadArticles()
    }

	@objc private func openSaved() {
		guard case .section(.saved) = source else {
			navigationController?.pushViewController(BabelTimelineViewController(section: .saved), animated: true)
			return
		}
	}

	@objc private func openUnread() {
		guard case .section(.unread) = source else {
			navigationController?.pushViewController(BabelTimelineViewController(section: .unread), animated: true)
			return
		}
	}

	@objc private func showSearch() {
		let controller = UISearchController(searchResultsController: nil)
		controller.searchResultsUpdater = self
		controller.obscuresBackgroundDuringPresentation = false
		controller.searchBar.placeholder = "Search Articles"
		present(controller, animated: true)
		controller.searchBar.becomeFirstResponder()
	}

	@objc private func showFilterMenu() {
		let selectedIndex: Int = {
			switch articleFilter { case .all: 0; case .unread: 1; case .starred: 2 }
		}()
		let controller = BabelArticleFilterViewController(selectedIndex: selectedIndex) { [weak self] index in
			guard let self else { return }
			self.articleFilter = [.all, .unread, .starred][index]
			self.rebuildSections(from: self.articles)
			self.tableView.reloadData()
			self.tableView.layoutIfNeeded()
			self.tableView.setContentOffset(CGPoint(x: 0, y: -self.tableView.adjustedContentInset.top), animated: false)
			self.emptyLabel.isHidden = !self.daySections.isEmpty
		}
		if let sheet = controller.sheetPresentationController {
			sheet.detents = [.medium()]
			sheet.prefersGrabberVisible = true
			sheet.preferredCornerRadius = 18
		}
		present(controller, animated: true)
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

	private func reloadArticles() {
		loadTask?.cancel()
		let shouldPreserveOffset = tableView.window != nil
		let preservedOffset = tableView.contentOffset
		loadingIndicator.startAnimating()
		emptyLabel.isHidden = true
		loadTask = Task { [weak self] in
			guard let self else { return }
			let loaded: [Article]
			switch source {
			case .section(let section): loaded = await BabelLibrary.loadArticles(for: section)
			case .folder(let folder): loaded = await BabelLibrary.loadArticles(for: .folder(folder, true))
			case .feed(let feed): loaded = await BabelLibrary.loadArticles(for: .feed(feed))
			}
			guard !Task.isCancelled else { return }
			articles = loaded
			navSubtitleLabel.text = "\(loaded.filter { !$0.status.read }.count) Unread Items"
			self.rebuildSections(from: loaded)
			tableView.reloadData()
			if shouldPreserveOffset {
				tableView.layoutIfNeeded()
				tableView.setContentOffset(preservedOffset, animated: false)
			}
			loadingIndicator.stopAnimating()
			tableView.refreshControl?.endRefreshing()
			emptyLabel.isHidden = !loaded.isEmpty
		}
	}

	func openFirstArticleForDebug() {
		Task { @MainActor [weak self] in
			guard let self else { return }
			for _ in 0..<60 where self.daySections.isEmpty {
				try? await Task.sleep(for: .milliseconds(150))
			}
			guard let first = self.daySections.first?.articles.first else { return }
			var currentArticle = first
			let reader = BabelReaderViewController(article: first)
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
	}

	private static let dayFormatter: DateFormatter = {
		let formatter = DateFormatter()
		formatter.locale = Locale(identifier: "en_US_POSIX")
		formatter.dateFormat = "EEEE, MMMM d, yyyy"
		return formatter
	}()
}

private final class BabelArticleFilterViewController: UIViewController {
	private let onSelect: (Int) -> Void
	private let selectedIndex: Int
	init(selectedIndex: Int, onSelect: @escaping (Int) -> Void) {
		self.selectedIndex = selectedIndex
		self.onSelect = onSelect
		super.init(nibName: nil, bundle: nil)
	}
	required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

	override func viewDidLoad() {
		super.viewDidLoad()
		view.backgroundColor = BabelPalette.background
		let close = UIButton(type: .custom)
		close.setImage(UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18)), for: .normal)
		close.tintColor = BabelPalette.ink
		close.addTarget(self, action: #selector(closeSheet), for: .touchUpInside)
		close.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(close)
		let title = UILabel()
		title.text = "Filter Articles"
		title.font = BabelTypography.title(size: 28, weight: .bold)
		title.textColor = BabelPalette.ink
		title.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(title)
		let stack = UIStackView()
		stack.axis = .vertical; stack.spacing = 1
		stack.backgroundColor = BabelPalette.raisedBackground
		stack.layer.cornerRadius = 14; stack.clipsToBounds = true
		stack.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(stack)
		for (index, label) in ["All", "Unread", "Starred"].enumerated() {
			var buttonConfiguration = UIButton.Configuration.plain()
			buttonConfiguration.title = label
			buttonConfiguration.baseForegroundColor = BabelPalette.ink
			buttonConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 18, bottom: 0, trailing: 18)
			let button = UIButton(configuration: buttonConfiguration)
			button.contentHorizontalAlignment = .left
			button.titleLabel?.font = BabelTypography.title(size: 17, weight: .regular)
			if index == selectedIndex {
				button.setImage(UIImage(systemName: "checkmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)), for: .normal)
				button.tintColor = BabelPalette.accent
				button.accessibilityTraits.insert(.selected)
			}
			button.tag = index
			button.addTarget(self, action: #selector(selected(_:)), for: .touchUpInside)
			button.heightAnchor.constraint(equalToConstant: 52).isActive = true
			stack.addArrangedSubview(button)
		}
		NSLayoutConstraint.activate([
			close.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20), close.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12), close.widthAnchor.constraint(equalToConstant: 44), close.heightAnchor.constraint(equalToConstant: 44),
			title.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24), title.topAnchor.constraint(equalTo: close.bottomAnchor, constant: 18),
			stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20), stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20), stack.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 22)
		])
	}
	@objc private func selected(_ sender: UIButton) { dismiss(animated: true) { self.onSelect(sender.tag) } }
	@objc private func closeSheet() { dismiss(animated: true) }
}

extension BabelTimelineViewController: UISearchResultsUpdating {
	func updateSearchResults(for searchController: UISearchController) {
		searchQuery = searchController.searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
		rebuildSections(from: articles)
		tableView.reloadData()
	}
}

extension BabelTimelineViewController: UITableViewDataSource, UITableViewDelegate {

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
		cell.configure(article: daySections[indexPath.section].articles[indexPath.row])
		return cell
	}

	func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		 tableView.deselectRow(at: indexPath, animated: true)
		let selected = daySections[indexPath.section].articles[indexPath.row]
		var currentArticle = selected
		let reader = BabelReaderViewController(article: selected)
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

	func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
		let article = daySections[indexPath.section].articles[indexPath.row]
		let star = UIContextualAction(style: .normal, title: article.status.starred ? "Unstar" : "Star") { [weak self] _, _, completion in
			guard let account = article.account else { completion(false); return }
			Task {
				try? await account.markArticles(articleIDs: [article.articleID], statusKey: .starred, flag: !article.status.starred)
				await MainActor.run { completion(true); self?.reloadArticles() }
			}
		}
		star.backgroundColor = BabelPalette.accent
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

private final class BabelTimelineCell: UITableViewCell {

	static let reuseIdentifier = "BabelTimelineCell"

	private let unreadDot = UIView()
	private let feedLabel = UILabel()
	private let dateLabel = UILabel()
	private let titleLabel = UILabel()
	private let summaryLabel = UILabel()
	private let thumbnailView = UIImageView()
	private let feedIconView = UIImageView()
	private let separator = UIView()
	private var representedImageURL: URL?

	override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
		super.init(style: style, reuseIdentifier: reuseIdentifier)
		backgroundColor = .clear
		selectedBackgroundView = {
			let view = UIView()
			view.backgroundColor = BabelPalette.raisedBackground
			return view
		}()

		unreadDot.backgroundColor = BabelPalette.accent
		unreadDot.layer.cornerRadius = 3
		unreadDot.translatesAutoresizingMaskIntoConstraints = false

        feedLabel.font = .systemFont(ofSize: 11, weight: .semibold)
		feedLabel.textColor = BabelPalette.mutedInk
		feedLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

		dateLabel.font = .preferredFont(forTextStyle: .caption1)
		dateLabel.textColor = BabelPalette.mutedInk
		dateLabel.textAlignment = .right
		dateLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        titleLabel.font = BabelTypography.title(size: 17, weight: .regular)
		titleLabel.textColor = BabelPalette.ink
		titleLabel.numberOfLines = 3

        summaryLabel.font = .systemFont(ofSize: 12)
		summaryLabel.textColor = BabelPalette.mutedInk
		summaryLabel.numberOfLines = 2

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

		let metaRow = UIStackView(arrangedSubviews: [unreadDot, feedLabel, UIView(), dateLabel])
		metaRow.alignment = .center
		metaRow.spacing = 8

		let stack = UIStackView(arrangedSubviews: [metaRow, titleLabel, summaryLabel])
		stack.axis = .vertical
		stack.spacing = 9
		stack.translatesAutoresizingMaskIntoConstraints = false
		contentView.addSubview(stack)

		// Reeder separates timeline entries with whitespace; no full-width table rule.
		separator.backgroundColor = .clear
		separator.translatesAutoresizingMaskIntoConstraints = false
		contentView.addSubview(separator)

		NSLayoutConstraint.activate([
			unreadDot.widthAnchor.constraint(equalToConstant: 6),
			unreadDot.heightAnchor.constraint(equalToConstant: 6),
            stack.leadingAnchor.constraint(equalTo: feedIconView.trailingAnchor, constant: 8),
			stack.trailingAnchor.constraint(equalTo: thumbnailView.leadingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: separator.topAnchor, constant: -12),
            separator.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            separator.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
			separator.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
			separator.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),
			feedIconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
			feedIconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
			feedIconView.widthAnchor.constraint(equalToConstant: 26),
			feedIconView.heightAnchor.constraint(equalToConstant: 26),
			thumbnailView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
			thumbnailView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            thumbnailView.widthAnchor.constraint(equalToConstant: 70),
            thumbnailView.heightAnchor.constraint(equalToConstant: 70)
		])
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	func configure(article: Article) {
		feedLabel.text = (article.feed?.nameForDisplay ?? "订阅文章").uppercased()
		feedIconView.image = article.feed.flatMap { FaviconDownloader.shared.faviconAsIcon(for: $0)?.image }
		feedIconView.backgroundColor = feedIconView.image == nil ? .clear : BabelPalette.raisedBackground
		dateLabel.text = Self.timeFormatter.string(from: article.logicalDatePublished)
		titleLabel.text = BabelLibrary.displayTitle(for: article)
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
		summaryLabel.text = explicitSummary ?? fallback
		summaryLabel.isHidden = summaryLabel.text == nil
		thumbnailView.image = ArticleThumbnail.shared.thumbnail(for: article)
		let imageLink = article.rawImageLink ?? ArticleThumbnail.shared.firstImageURL(for: article)
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
		unreadDot.isHidden = true
		accessibilityLabel = "\(feedLabel.text ?? "")，\(titleLabel.text ?? "")，\(dateLabel.text ?? "")"
	}

	private static let timeFormatter: DateFormatter = {
		let formatter = DateFormatter()
		formatter.dateFormat = "H:mm"
		return formatter
	}()
}
