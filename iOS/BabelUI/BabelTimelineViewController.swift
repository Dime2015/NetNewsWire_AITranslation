//
//  BabelTimelineViewController.swift
//  NetNewsWire
//

import UIKit
import Account
import Articles

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
	private var articles = [Article]()
	private var daySections = [(date: Date, articles: [Article])]()
	private var loadTask: Task<Void, Never>?
	private var searchQuery = ""

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

	deinit {
		loadTask?.cancel()
		NotificationCenter.default.removeObserver(self)
	}

	private func configureView() {
		title = source.title
		view.backgroundColor = BabelPalette.background
        navigationItem.largeTitleDisplayMode = .never
		navTitleLabel.text = source.title
		navTitleLabel.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
		navTitleLabel.textColor = BabelPalette.ink
		navTitleLabel.textAlignment = .center
		navSubtitleLabel.text = ""
		navSubtitleLabel.font = UIFont.systemFont(ofSize: 12, weight: .regular)
		navSubtitleLabel.textColor = BabelPalette.mutedInk
		navSubtitleLabel.textAlignment = .center
		let navTitleStack = UIStackView(arrangedSubviews: [navTitleLabel, navSubtitleLabel])
		navTitleStack.axis = .vertical
		navTitleStack.alignment = .center
		navTitleStack.spacing = 0
		navigationItem.titleView = navTitleStack
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "ellipsis"),
            style: .plain, target: self, action: #selector(showActions)
        )

		tableView.backgroundColor = BabelPalette.background
		tableView.separatorStyle = .none
        tableView.contentInset = UIEdgeInsets(top: 2, left: 0, bottom: 62, right: 0)
		tableView.rowHeight = UITableView.automaticDimension
		tableView.estimatedRowHeight = 154
		tableView.register(BabelTimelineCell.self, forCellReuseIdentifier: BabelTimelineCell.reuseIdentifier)
		tableView.dataSource = self
		tableView.delegate = self
		view.addSubview(tableView)
		tableView.babelPinToEdges(of: view)

		emptyLabel.text = "这里暂时没有文章"
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
        for (symbol, label) in [("checkmark.circle", "已读"), ("star", "星标"),
                                ("circle.fill", "未读"), ("magnifyingglass", "搜索")] {
            var config = UIButton.Configuration.plain()
            config.image = UIImage(systemName: symbol)
            config.baseForegroundColor = BabelPalette.mutedInk
            if label == "未读" {
                config.imagePlacement = .leading
                config.imagePadding = 8
                config.attributedTitle = AttributedString("UNREAD", attributes: AttributeContainer([
                    .font: UIFont.systemFont(ofSize: 13, weight: .semibold)
                ]))
                config.background = .listPlainCell()
                config.background.backgroundColor = BabelPalette.raisedBackground
                config.background.cornerRadius = 24
            }
            let button = UIButton(configuration: config)
            button.accessibilityLabel = label
            button.configuration?.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 15, bottom: 10, trailing: 15)
            switch label {
            case "已读": button.addTarget(self, action: #selector(markAllRead), for: .touchUpInside)
            case "星标": button.addTarget(self, action: #selector(openSaved), for: .touchUpInside)
            case "未读": button.addTarget(self, action: #selector(openUnread), for: .touchUpInside)
            case "搜索": button.addTarget(self, action: #selector(showSearch), for: .touchUpInside)
            default: break
            }
            bottom.addArrangedSubview(button)
        }
        NSLayoutConstraint.activate([
            bottom.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottom.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottom.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            bottom.heightAnchor.constraint(equalToConstant: 54)
        ])
	}

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

    @objc private func showActions() {
		let alert = UIAlertController(title: source.title, message: nil, preferredStyle: .actionSheet)
		alert.addAction(UIAlertAction(title: "标记全部已读", style: .default) { [weak self] _ in
			self?.markAllRead()
		})
		alert.addAction(UIAlertAction(title: "取消", style: .cancel))
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
		}
	}

	private func reloadArticles() {
		loadTask?.cancel()
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
			loadingIndicator.stopAnimating()
			tableView.refreshControl?.endRefreshing()
			emptyLabel.isHidden = !loaded.isEmpty
		}
	}

	private func rebuildSections(from articles: [Article]) {
		let filtered: [Article]
		if searchQuery.isEmpty {
			filtered = articles
		} else {
			filtered = articles.filter { article in
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

	func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		let cell = tableView.dequeueReusableCell(withIdentifier: BabelTimelineCell.reuseIdentifier, for: indexPath) as! BabelTimelineCell
		cell.configure(article: daySections[indexPath.section].articles[indexPath.row])
		return cell
	}

	func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		tableView.deselectRow(at: indexPath, animated: true)
		navigationController?.pushViewController(BabelReaderViewController(article: daySections[indexPath.section].articles[indexPath.row]), animated: true)
	}

	func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
		guard let header = view as? UITableViewHeaderFooterView else { return }
		header.textLabel?.font = UIFont.systemFont(ofSize: 14, weight: .medium)
		header.textLabel?.textColor = BabelPalette.ink
		header.contentView.backgroundColor = BabelPalette.background
	}

	func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
		let article = daySections[indexPath.section].articles[indexPath.row]
		let star = UIContextualAction(style: .normal, title: article.status.starred ? "取消星标" : "星标") { [weak self] _, _, completion in
			guard let account = article.account else { completion(false); return }
			Task {
				try? await account.markArticles(articleIDs: [article.articleID], statusKey: .starred, flag: !article.status.starred)
				await MainActor.run { completion(true); self?.reloadArticles() }
			}
		}
		star.backgroundColor = BabelPalette.accent
		let read = UIContextualAction(style: .normal, title: article.status.read ? "未读" : "已读") { [weak self] _, _, completion in
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
	private let separator = UIView()

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

        titleLabel.font = BabelTypography.title(size: 17)
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

		let metaRow = UIStackView(arrangedSubviews: [unreadDot, feedLabel, UIView(), dateLabel])
		metaRow.alignment = .center
		metaRow.spacing = 8

		let stack = UIStackView(arrangedSubviews: [metaRow, titleLabel, summaryLabel])
		stack.axis = .vertical
		stack.spacing = 9
		stack.translatesAutoresizingMaskIntoConstraints = false
		contentView.addSubview(stack)

		separator.backgroundColor = BabelPalette.hairline
		separator.translatesAutoresizingMaskIntoConstraints = false
		contentView.addSubview(separator)

		NSLayoutConstraint.activate([
			unreadDot.widthAnchor.constraint(equalToConstant: 6),
			unreadDot.heightAnchor.constraint(equalToConstant: 6),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
			stack.trailingAnchor.constraint(equalTo: thumbnailView.leadingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: separator.topAnchor, constant: -12),
            separator.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            separator.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
			separator.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
			separator.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale)
			,thumbnailView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
			thumbnailView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
			thumbnailView.widthAnchor.constraint(equalToConstant: 132),
			thumbnailView.heightAnchor.constraint(equalToConstant: 82)
		])
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	func configure(article: Article) {
		feedLabel.text = (article.feed?.nameForDisplay ?? "订阅文章").uppercased()
		dateLabel.text = Self.timeFormatter.string(from: article.logicalDatePublished)
		titleLabel.text = BabelLibrary.displayTitle(for: article)
		summaryLabel.text = BabelLibrary.summary(for: article)
		summaryLabel.isHidden = summaryLabel.text == nil
		thumbnailView.image = nil
		if let imageLink = article.rawImageLink, let url = URL(string: imageLink) {
			Task { [weak self] in
				guard let (data, _) = try? await URLSession.shared.data(from: url), let image = UIImage(data: data) else { return }
				guard !Task.isCancelled else { return }
				await MainActor.run { self?.thumbnailView.image = image }
			}
		}
		unreadDot.isHidden = article.status.read
		accessibilityLabel = "\(feedLabel.text ?? "")，\(titleLabel.text ?? "")，\(dateLabel.text ?? "")"
	}

	private static let timeFormatter: DateFormatter = {
		let formatter = DateFormatter()
		formatter.dateFormat = "H:mm"
		return formatter
	}()
}
