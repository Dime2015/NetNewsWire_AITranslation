import Foundation
import UIKit
import Babel2Core

@MainActor
final class Babel2FeedViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
	private enum LoadState: String {
		case loading
		case loaded
		case empty
		case error
	}

	private let feed: FeedSnapshot
	private let scope: Babel2FeedScope
	private let environment: AppEnvironment
	private let tableView = UITableView(frame: .zero, style: .plain)
	private let emptyLabel = UILabel()
	private let countLabel = UILabel()
	private let retryButton = UIButton(type: .system)
	private var articles = [ArticleSnapshot]()
	private var loadTask: Task<Void, Never>?
	private var loadGeneration = UUID()
	private var loadState: LoadState = .loading
	private var statusRefreshTimer: Timer?
	private var statusRefreshTask: Task<Void, Never>?
	var onSelectArticle: ((ArticleSnapshot) -> Void)?

	init(feed: FeedSnapshot, scope: Babel2FeedScope = .all, environment: AppEnvironment) {
		self.feed = feed
		self.scope = scope
		self.environment = environment
		super.init(nibName: nil, bundle: nil)
		restorationIdentifier = "babel2.feed.\(feed.id.accountID).\(feed.id.feedID)"
		// 已读/星标等状态变化（阅读页操作、后台同步）时，原地刷新每一行的状态
		NotificationCenter.default.addObserver(self, selector: #selector(libraryDidChange(_:)), name: .babel2LibraryDidChange, object: nil)
	}

	required init?(coder: NSCoder) { nil }

	override func viewDidLoad() {
		super.viewDidLoad()
		view.backgroundColor = BabelPalette.background
		configureHeader()
		configureTable()
		startLoading()
	}

	override func viewDidDisappear(_ animated: Bool) {
		super.viewDidDisappear(animated)
		if isMovingFromParent {
			cancelLoading()
			statusRefreshTimer?.invalidate()
			statusRefreshTask?.cancel()
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
				changedRows.append(IndexPath(row: index, section: 0))
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

	// MARK: - 下一篇（ADR-022）

	/// 按列表显示顺序，找这一篇之后的下一篇；「未读」档里跳过已经读过的（它们留在列表里只是变细）。
	/// 没有下一篇、或这一篇不在列表里时返回 nil。
	func nextArticle(after id: ArticleSnapshot.ID) -> ArticleSnapshot? {
		guard let index = articles.firstIndex(where: { $0.id == id }) else { return nil }
		return articles[(index + 1)...].first { scope != .unread || !$0.isRead }
	}

	/// 翻到某一篇后，让列表滚到它、保证返回时它在屏幕上（只做最小滚动）。
	func revealArticle(_ id: ArticleSnapshot.ID) {
		guard let index = articles.firstIndex(where: { $0.id == id }) else { return }
		tableView.scrollToRow(at: IndexPath(row: index, section: 0), at: .none, animated: false)
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
		tableView.reloadData()
		countLabel.text = nil
		countLabel.accessibilityValue = nil
		countLabel.isHidden = true
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
				self.countLabel.text = self.articles.count.formatted()
				self.countLabel.accessibilityValue = String(self.articles.count)
				self.countLabel.isHidden = false
				self.tableView.reloadData()
				self.setState(self.articles.isEmpty ? .empty : .loaded)
			} catch is CancellationError {
				return
			} catch {
				guard !Task.isCancelled, let self,
					self.loadGeneration == generation,
					self.feed.id == feedID,
					self.scope == scope else { return }
				self.articles.removeAll(keepingCapacity: true)
				self.tableView.reloadData()
				self.countLabel.text = nil
				self.countLabel.accessibilityValue = nil
				self.countLabel.isHidden = true
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

	private func configureHeader() {
		let header = UIView()
		header.backgroundColor = BabelPalette.background
		header.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(header)

		let back = UIButton(type: .system)
		back.setImage(UIImage(systemName: "chevron.left"), for: .normal)
		back.tintColor = BabelPalette.ink
		back.accessibilityLabel = "Back"
		back.accessibilityIdentifier = "babel2.feed.back"
		back.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
		back.translatesAutoresizingMaskIntoConstraints = false
		header.addSubview(back)

		let titleLabel = UILabel()
		titleLabel.text = feed.title
		titleLabel.accessibilityValue = scope.rawValue
		titleLabel.accessibilityIdentifier = "babel2.feed.title"
		titleLabel.font = .systemFont(ofSize: 18, weight: .semibold)
		titleLabel.textColor = BabelPalette.ink
		titleLabel.lineBreakMode = .byTruncatingTail
		titleLabel.translatesAutoresizingMaskIntoConstraints = false
		header.addSubview(titleLabel)

		countLabel.text = feed.articleCount.map { $0.formatted() }
		countLabel.accessibilityValue = feed.articleCount.map(String.init)
		countLabel.isHidden = feed.articleCount == nil
		countLabel.accessibilityIdentifier = "babel2.feed.count"
		countLabel.font = .systemFont(ofSize: 13, weight: .regular)
		countLabel.textColor = BabelPalette.tertiaryInk
		countLabel.translatesAutoresizingMaskIntoConstraints = false
		header.addSubview(countLabel)

		let line = UIView()
		line.backgroundColor = BabelPalette.hairline
		line.translatesAutoresizingMaskIntoConstraints = false
		header.addSubview(line)

		NSLayoutConstraint.activate([
			header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
			header.heightAnchor.constraint(equalToConstant: 64),
			back.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 10),
			back.centerYAnchor.constraint(equalTo: header.centerYAnchor),
			back.widthAnchor.constraint(equalToConstant: 44),
			back.heightAnchor.constraint(equalToConstant: 44),
			titleLabel.leadingAnchor.constraint(equalTo: back.trailingAnchor, constant: 6),
			titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: countLabel.leadingAnchor, constant: -8),
			titleLabel.centerYAnchor.constraint(equalTo: back.centerYAnchor),
			countLabel.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -20),
			countLabel.centerYAnchor.constraint(equalTo: back.centerYAnchor),
			line.leadingAnchor.constraint(equalTo: header.leadingAnchor),
			line.trailingAnchor.constraint(equalTo: header.trailingAnchor),
			line.bottomAnchor.constraint(equalTo: header.bottomAnchor),
			line.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale)
		])
	}

	private func configureTable() {
		tableView.backgroundColor = BabelPalette.background
		tableView.separatorStyle = .none
		tableView.rowHeight = UITableView.automaticDimension
		tableView.estimatedRowHeight = 118
		tableView.dataSource = self
		tableView.delegate = self
		tableView.register(Babel2ArticleCell.self, forCellReuseIdentifier: Babel2ArticleCell.reuseIdentifier)
		tableView.accessibilityIdentifier = "babel2.feed.articles.table"
		tableView.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(tableView)

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
			tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 64),
			tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
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

	func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { articles.count }

	func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		let cell = tableView.dequeueReusableCell(withIdentifier: Babel2ArticleCell.reuseIdentifier, for: indexPath) as! Babel2ArticleCell
		let article = articles[indexPath.row]
		cell.configure(article: article, imageProvider: environment.imageProvider)
		cell.accessibilityIdentifier = "babel2.article.\(article.id.accountID).\(article.id.feedID).\(article.id.articleID)"
		return cell
	}

	func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		tableView.deselectRow(at: indexPath, animated: true)
		onSelectArticle?(articles[indexPath.row])
	}
}

private final class Babel2ArticleCell: UITableViewCell {
	static let reuseIdentifier = "Babel2ArticleCell"
	private static let thumbSide: CGFloat = 70

	private let dateLabel = UILabel()
	private let titleLabel = UILabel()
	private let translationLabel = UILabel()
	private let summaryLabel = UILabel()
	private let thumbnailView = UIImageView()
	private var imageLoadTask: Task<Void, Never>?
	private var configuredArticleID: ArticleSnapshot.ID?

	private var titleToThumb: NSLayoutConstraint!
	private var dateToThumb: NSLayoutConstraint!
	private var titleToTrailing: NSLayoutConstraint!
	private var dateToTrailing: NSLayoutConstraint!
	private var translationTopFromTitle: NSLayoutConstraint!
	private var translationTopFromTitleCollapsed: NSLayoutConstraint!
	private var summaryTopFromTranslation: NSLayoutConstraint!
	private var summaryTopFromTitle: NSLayoutConstraint!
	private var translationHeight: NSLayoutConstraint!

	override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
		super.init(style: style, reuseIdentifier: reuseIdentifier)
		backgroundColor = .clear
		contentView.backgroundColor = .clear
		selectionStyle = .default

		thumbnailView.translatesAutoresizingMaskIntoConstraints = false
		thumbnailView.contentMode = .scaleAspectFill
		thumbnailView.clipsToBounds = true
		thumbnailView.layer.cornerRadius = 10
		thumbnailView.layer.cornerCurve = .continuous
		thumbnailView.backgroundColor = BabelPalette.raisedBackground
		thumbnailView.isHidden = true
		contentView.addSubview(thumbnailView)

		for label in [dateLabel, titleLabel, translationLabel, summaryLabel] {
			label.translatesAutoresizingMaskIntoConstraints = false
			contentView.addSubview(label)
		}

		dateLabel.font = .systemFont(ofSize: 12, weight: .regular)
		dateLabel.textColor = BabelPalette.tertiaryInk
		dateLabel.textAlignment = .right
		dateLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
		dateLabel.setContentHuggingPriority(.required, for: .vertical)

		titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
		titleLabel.textColor = BabelPalette.ink
		titleLabel.numberOfLines = 2

		translationLabel.font = .systemFont(ofSize: 12, weight: .regular)
		translationLabel.textColor = BabelPalette.mutedInk
		translationLabel.numberOfLines = 1
		translationLabel.isHidden = true

		summaryLabel.font = .systemFont(ofSize: 14, weight: .regular)
		summaryLabel.textColor = BabelPalette.mutedInk
		summaryLabel.numberOfLines = 2

		titleToThumb = titleLabel.trailingAnchor.constraint(equalTo: thumbnailView.leadingAnchor, constant: -12)
		dateToThumb = dateLabel.trailingAnchor.constraint(equalTo: thumbnailView.leadingAnchor, constant: -12)
		titleToTrailing = titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20)
		dateToTrailing = dateLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20)

		translationTopFromTitle = translationLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4)
		translationTopFromTitleCollapsed = translationLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 0)
		summaryTopFromTranslation = summaryLabel.topAnchor.constraint(equalTo: translationLabel.bottomAnchor, constant: 4)
		summaryTopFromTitle = summaryLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4)
		translationHeight = translationLabel.heightAnchor.constraint(equalToConstant: 0)

		NSLayoutConstraint.activate([
			thumbnailView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
			thumbnailView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
			thumbnailView.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -12),
			thumbnailView.widthAnchor.constraint(equalToConstant: Self.thumbSide),
			thumbnailView.heightAnchor.constraint(equalToConstant: Self.thumbSide),

			dateLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
			dateLabel.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 20),
			dateToTrailing,

			titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
			titleToTrailing,
			titleLabel.topAnchor.constraint(equalTo: dateLabel.bottomAnchor, constant: 6),

			translationLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
			translationLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
			translationHeight,
			translationTopFromTitleCollapsed,

			summaryLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
			summaryLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
			summaryTopFromTitle,
			summaryLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -14)
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
		setTranslationVisible(false)
		summaryLabel.text = nil
		titleLabel.text = nil
		dateLabel.text = nil
	}

	func configure(article: ArticleSnapshot, imageProvider: any ImageProviding) {
		configuredArticleID = article.id
		let displayTitle = article.translatedTitle ?? article.title
		titleLabel.text = displayTitle
		titleLabel.font = .systemFont(ofSize: 17, weight: article.isRead ? .regular : .semibold)
		titleLabel.textColor = BabelPalette.ink
		contentView.alpha = 1

		let hasTranslation = !(article.translatedTitle ?? "").isEmpty
		setTranslationVisible(hasTranslation)

		let plainSummary = Self.plainSummary(article.summary)
		summaryLabel.text = plainSummary
		summaryLabel.isHidden = plainSummary.isEmpty

		dateLabel.text = article.publishedAt.map(Self.formatDate) ?? ""
		accessibilityLabel = [displayTitle, plainSummary].filter { !$0.isEmpty }.joined(separator: ". ")

		imageLoadTask?.cancel()
		imageLoadTask = nil
		thumbnailView.image = nil

		guard let imageURL = article.imageURL else {
			setThumbVisible(false)
			return
		}
		setThumbVisible(true)
		let articleID = article.id
		imageLoadTask = Task { @MainActor [weak self] in
			guard let self else { return }
			do {
				let data = try await imageProvider.imageData(for: imageURL)
				guard !Task.isCancelled, self.configuredArticleID == articleID else { return }
				if let data, let image = UIImage(data: data) {
					self.thumbnailView.image = image
					self.thumbnailView.backgroundColor = .clear
				} else {
					self.thumbnailView.image = nil
					self.thumbnailView.backgroundColor = BabelPalette.raisedBackground
				}
			} catch {
				guard !Task.isCancelled, self.configuredArticleID == articleID else { return }
				self.thumbnailView.image = nil
				self.thumbnailView.backgroundColor = BabelPalette.raisedBackground
			}
		}
	}

	private func setThumbVisible(_ visible: Bool) {
		thumbnailView.isHidden = !visible
		titleToThumb.isActive = visible
		dateToThumb.isActive = visible
		titleToTrailing.isActive = !visible
		dateToTrailing.isActive = !visible
	}

	private func setTranslationVisible(_ visible: Bool) {
		translationLabel.text = visible ? "英文 → 简体中文" : nil
		translationLabel.isHidden = !visible
		translationTopFromTitle.isActive = visible
		translationTopFromTitleCollapsed.isActive = !visible
		summaryTopFromTranslation.isActive = visible
		summaryTopFromTitle.isActive = !visible
		translationHeight.constant = visible ? 16 : 0
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

	private static func formatDate(_ date: Date) -> String {
		if Calendar.current.isDateInToday(date) {
			return timeFormatter.string(from: date)
		}
		return dateFormatter.string(from: date)
	}

	private static let dateFormatter: DateFormatter = {
		let formatter = DateFormatter()
		formatter.dateStyle = .medium
		formatter.timeStyle = .none
		return formatter
	}()

	private static let timeFormatter: DateFormatter = {
		let formatter = DateFormatter()
		formatter.dateStyle = .none
		formatter.timeStyle = .short
		return formatter
	}()
}
