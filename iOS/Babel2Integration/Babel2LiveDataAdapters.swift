import Foundation
import Account
import Articles
import Images
import RSWeb
import Babel2Core

/// The Babel 2.0 boundary to the existing feed/account services.
///
/// This adapter deliberately owns the MainActor hop. Babel2 screens only see
/// value snapshots and never retain Account, Feed, Folder, or Article objects;
/// that keeps the new navigation tree independent from the legacy controller
/// tree while allowing the already-stable database and sync services to be
/// reused.
@MainActor
final class Babel2LiveDataProvider: DataProviding {
	private var articleCache = [ArticleSnapshot.ID: ArticleSnapshot]()

	init() {
		let center = NotificationCenter.default
		center.addObserver(self, selector: #selector(libraryDidChange(_:)), name: .AccountRefreshDidBegin, object: nil)
		center.addObserver(self, selector: #selector(libraryDidChange(_:)), name: .AccountRefreshDidFinish, object: nil)
		center.addObserver(self, selector: #selector(libraryDidChange(_:)), name: .StatusesDidChange, object: nil)
		center.addObserver(self, selector: #selector(libraryDidChange(_:)), name: .AccountDidDownloadArticles, object: nil)
		center.addObserver(self, selector: #selector(libraryDidChange(_:)), name: .feedIconDidBecomeAvailable, object: nil)
		center.addObserver(self, selector: #selector(libraryDidChange(_:)), name: .FaviconDidBecomeAvailable, object: nil)
	}

	deinit {
	}

	@objc private func libraryDidChange(_ notification: Notification) {
		NotificationCenter.default.post(name: .babel2LibraryDidChange, object: nil)
	}

	nonisolated func librarySnapshot(for scope: Babel2FeedScope) async throws -> LibrarySnapshot {
		try await makeLibrarySnapshot(for: scope)
	}

	private func makeLibrarySnapshot(for scope: Babel2FeedScope) async throws -> LibrarySnapshot {
		let accounts = AccountManager.shared.sortedActiveAccounts
		var feedSnapshots = [FeedSnapshot]()
		var countsByFeedID = [FeedSnapshot.ID: Int]()
		for account in accounts {
			try Task.checkCancellation()
			let countMap = await account.fetchFeedArticleCountsAsync()

			for feed in account.flattenedFeeds() {
				try Task.checkCancellation()
				let count = countMap[feed.feedID].map { counts in
					switch scope {
					case .all: return counts.totalCount
					case .unread: return counts.unreadCount
					case .starred: return counts.starredCount
					}
				} ?? 0
				// Starred only surfaces sources that currently have starred articles.
				// Unread/All keep every subscribed source so folder hierarchy stays stable;
				// the root hides zero counts visually while still listing the feed.
				let include: Bool
				switch scope {
				case .starred:
					include = count > 0
				case .unread, .all:
					include = true
				}
				guard include,
					let snapshot = makeFeedSnapshot(accountID: account.accountID, feed: feed, articleCount: count) else {
					continue
				}
				countsByFeedID[snapshot.id] = count
				feedSnapshots.append(snapshot)
			}
		}
		feedSnapshots.sort(by: feedComesFirst)
		let folderSnapshots = makeFolderSnapshots(from: accounts, countsByFeedID: countsByFeedID, scope: scope)

		return LibrarySnapshot(
			feeds: feedSnapshots,
			folders: folderSnapshots,
			generatedAt: Date(),
			isSyncing: AccountManager.shared.refreshInProgress
		)
	}

	private func makeFolderSnapshots(
		from accounts: [Account],
		countsByFeedID: [FeedSnapshot.ID: Int],
		scope: Babel2FeedScope
	) -> [FolderSnapshot] {
		let folders = accounts.flatMap { $0.folders ?? [] }.sorted(by: folderComesFirst)
		var snapshots = [FolderSnapshot]()
		snapshots.reserveCapacity(folders.count)
		for folder in folders {
			var feedIDs = [FeedSnapshot.ID]()
			feedIDs.reserveCapacity(folder.topLevelFeeds.count)
			for feed in folder.topLevelFeeds {
				feedIDs.append(FeedSnapshot.ID(accountID: folder.accountID, feedID: feed.feedID))
			}
			feedIDs.sort { lhs, rhs in
				if lhs.accountID == rhs.accountID {
					return lhs.feedID < rhs.feedID
				}
				return lhs.accountID < rhs.accountID
			}
			var visibleFeedIDs = [FeedSnapshot.ID]()
			var total = 0
			for feedID in feedIDs {
				guard let count = countsByFeedID[feedID] else { continue }
				visibleFeedIDs.append(feedID)
				total += count
			}
			guard !visibleFeedIDs.isEmpty else { continue }
			if scope == .starred, total <= 0 { continue }
			snapshots.append(
				FolderSnapshot(
					id: folderID(for: folder),
					title: folder.nameForDisplay,
					feedIDs: visibleFeedIDs,
					articleCount: total
				)
			)
		}
		return snapshots
	}

	private func feedComesFirst(_ lhs: FeedSnapshot, _ rhs: FeedSnapshot) -> Bool {
		let titleOrder = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
		guard titleOrder == .orderedSame else { return titleOrder == .orderedAscending }
		guard lhs.id.accountID == rhs.id.accountID else { return lhs.id.accountID < rhs.id.accountID }
		return lhs.id.feedID < rhs.id.feedID
	}

	private func folderComesFirst(_ lhs: Folder, _ rhs: Folder) -> Bool {
		lhs.nameForDisplay.localizedCaseInsensitiveCompare(rhs.nameForDisplay) == .orderedAscending
	}

	private func articleComesFirst(_ lhs: ArticleSnapshot, _ rhs: ArticleSnapshot) -> Bool {
		switch (lhs.publishedAt, rhs.publishedAt) {
		case let (.some(left), .some(right)) where left != right: return left > right
		case (.some, .none): return true
		case (.none, .some): return false
		default: break
		}
		guard lhs.id.accountID == rhs.id.accountID else { return lhs.id.accountID < rhs.id.accountID }
		guard lhs.id.feedID == rhs.id.feedID else { return lhs.id.feedID < rhs.id.feedID }
		return lhs.id.articleID < rhs.id.articleID
	}

	nonisolated func feedArticlesSnapshot(for id: FeedSnapshot.ID, scope: Babel2FeedScope) async throws -> [ArticleSnapshot] {
		try await makeFeedArticlesSnapshot(for: id, scope: scope)
	}

	private func makeFeedArticlesSnapshot(for id: FeedSnapshot.ID, scope: Babel2FeedScope) async throws -> [ArticleSnapshot] {
		guard let account = AccountManager.shared.existingAccount(accountID: id.accountID),
			let feed = account.existingFeed(withFeedID: id.feedID),
			feed.accountID == id.accountID else { return [] }

		let articles = try await fetchArticles(for: account, feed: feed, scope: scope)
		try Task.checkCancellation()
		return articles
			.filter { $0.accountID == id.accountID && $0.feedID == id.feedID }
			.map { article in
				let snapshot = makeArticleSnapshot(article)
				articleCache[snapshot.id] = snapshot
				return snapshot
			}
			.sorted(by: articleComesFirst)
	}

	nonisolated func articleSnapshot(for id: ArticleSnapshot.ID) async throws -> ArticleSnapshot? {
		try await makeArticleSnapshot(for: id)
	}

	private func makeArticleSnapshot(for id: ArticleSnapshot.ID) async throws -> ArticleSnapshot? {
		if let cached = articleCache[id] {
			return cached
		}

		guard let account = AccountManager.shared.existingAccount(accountID: id.accountID),
			let feed = account.existingFeed(withFeedID: id.feedID),
			feed.accountID == id.accountID else { return nil }
		let articles = await account.fetchArticlesAsync(.articleIDs([id.articleID]))
		guard !Task.isCancelled,
			let article = articles.first(where: {
				$0.accountID == id.accountID && $0.feedID == id.feedID && $0.articleID == id.articleID
			}) else {
			return nil
		}
		let snapshot = makeArticleSnapshot(article)
		articleCache[id] = snapshot
		return snapshot
	}

	private func fetchArticles(for account: Account, feed: Feed, scope: Babel2FeedScope) async throws -> Set<Article> {
		try Task.checkCancellation()
		switch scope {
		case .all:
			let articles = await account.fetchArticlesAsync(.feed(feed))
			return articles.filter {
				$0.accountID == account.accountID && $0.feedID == feed.feedID
			}
		case .unread:
			let articles = await account.fetchUnreadArticlesAsync(feed: feed)
			return articles.filter {
				$0.accountID == account.accountID && $0.feedID == feed.feedID
			}
		case .starred:
			let articles = await account.fetchArticlesAsync(.starred(nil))
			return articles.filter {
				$0.accountID == account.accountID && $0.feedID == feed.feedID && $0.status.starred
			}
		}
	}

	private func makeFeedSnapshot(accountID: String, feed: Feed, articleCount: Int) -> FeedSnapshot? {
		guard let url = URL(string: feed.url), url.isHTTPOrHTTPSURL() else { return nil }
		let iconData = FeedIconDownloader.shared.icon(for: feed)?.image.dataRepresentation()
			?? FaviconDownloader.shared.faviconAsIcon(for: feed)?.image.dataRepresentation()
		return FeedSnapshot(
			id: FeedSnapshot.ID(accountID: accountID, feedID: feed.feedID),
			title: feed.nameForDisplay,
			url: url,
			articleCount: articleCount,
			iconData: iconData
		)
	}

	private func makeArticleSnapshot(_ article: Article) -> ArticleSnapshot {
		let body = article.contentHTML ?? article.contentText ?? article.summary ?? ""
		let title = article.title?.trimmingCharacters(in: .whitespacesAndNewlines)
		let summary = article.summary ?? article.contentText ?? ""
		let originalTitle = title?.isEmpty == false ? title! : "Untitled"
		// Cache-only title translation for Timeline. Never enqueue AI work here.
		var translatedTitle: String? = nil
		if NNWTitleTranslationStore.shared.isEnabled(accountID: article.accountID, feedID: article.feedID),
			let raw = article.title, !raw.isEmpty {
			let model = TranslationConfigStore.selectedModel
			if let hit = NNWTitleTranslationCache.shared.translation(
				articleID: article.articleID,
				title: raw,
				model: model
			), hit != raw {
				translatedTitle = hit
			}
		}
		return ArticleSnapshot(
			id: ArticleSnapshot.ID(accountID: article.accountID, feedID: article.feedID, articleID: article.articleID),
			title: originalTitle,
			translatedTitle: translatedTitle,
			summary: summary,
			content: body,
			url: article.preferredURL,
			feedID: FeedSnapshot.ID(accountID: article.accountID, feedID: article.feedID),
			publishedAt: article.datePublished ?? article.dateModified ?? article.status.dateArrived,
			imageURL: article.imageURL,
			isRead: article.status.read,
			isStarred: article.status.starred
		)
	}

	private func folderID(for folder: Folder) -> FolderSnapshot.ID {
		"\(folder.accountID):\(folder.folderID)"
	}
}

/// Mutations cross the same boundary in the opposite direction. Selection is
/// represented as a notification for now; read/starred mutations are persisted
/// through the existing account API and followed by a library-change event.
@MainActor
final class Babel2LiveActionHandler: ActionHandling {
	nonisolated func handle(_ action: LibraryAction) async throws {
		try await handleOnMainActor(action)
	}

	private func handleOnMainActor(_ action: LibraryAction) async throws {
		switch action {
		case .selectFeed(let feedID):
			NotificationCenter.default.post(name: .babel2SelectionDidChange, object: feedID)
		case .selectFolder(let folderID):
			NotificationCenter.default.post(name: .babel2SelectionDidChange, object: folderID)
		case .markRead(let articleID):
			try await updateStatus(articleID: articleID, key: .read, value: true)
		case .markUnread(let articleID):
			try await updateStatus(articleID: articleID, key: .read, value: false)
		case .toggleStar(let articleID):
			guard let article = await article(for: articleID) else { return }
			try await updateStatus(articleID: articleID, key: .starred, value: !article.status.starred)
		}
	}

	private func article(for id: ArticleSnapshot.ID) async -> Article? {
		guard let account = AccountManager.shared.existingAccount(accountID: id.accountID),
			let feed = account.existingFeed(withFeedID: id.feedID),
			feed.accountID == id.accountID else { return nil }
		let articles = await account.fetchArticlesAsync(.articleIDs([id.articleID]))
		guard !Task.isCancelled else { return nil }
		return articles.first {
			$0.accountID == id.accountID && $0.feedID == id.feedID && $0.articleID == id.articleID
		}
	}

	private func updateStatus(articleID: ArticleSnapshot.ID, key: ArticleStatus.Key, value: Bool) async throws {
		guard let account = AccountManager.shared.existingAccount(accountID: articleID.accountID),
			let article = await article(for: articleID),
			article.accountID == account.accountID else { return }
		try await account.markArticles(articleIDs: [article.articleID], statusKey: key, flag: value)
	}
}

/// A concrete settings boundary. The initial value is intentionally in-memory;
/// the settings screen can later replace this provider with its persisted
/// store without making the library or reader depend on UIKit defaults.
@MainActor
final class Babel2LiveSettingsProvider: SettingsProviding {
	private var value = SettingsSnapshot()

	nonisolated func settingsSnapshot() async throws -> SettingsSnapshot {
		await currentSnapshot()
	}

	private func currentSnapshot() -> SettingsSnapshot { value }

	func update(_ settings: SettingsSnapshot) {
		value = settings
		NotificationCenter.default.post(name: .babel2SettingsDidChange, object: settings)
	}
}

struct Babel2LiveArticleRenderer: ArticleRendering {
	func render(_ article: ArticleSnapshot) async throws -> ArticleRenderSnapshot {
		ArticleRenderSnapshot(articleID: article.id, body: article.content, contentType: "text/html")
	}
}

struct Babel2LiveImageProvider: ImageProviding {
	func imageData(for url: URL) async throws -> Data? {
		try await Self.loadImageData(for: url)
	}

	@MainActor
	private static func loadImageData(for url: URL) async throws -> Data? {
		if let cached = ImageDownloader.shared.image(for: url.absoluteString) {
			return cached
		}
		let response = try await Downloader.shared.download(url)
		return response.data
	}
}

extension Notification.Name {
	static let babel2SelectionDidChange = Notification.Name("Babel2SelectionDidChange")
	static let babel2LibraryDidChange = Notification.Name("Babel2LibraryDidChange")
	static let babel2SettingsDidChange = Notification.Name("Babel2SettingsDidChange")
}
