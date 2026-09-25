import Foundation
import UIKit
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
		// 标题译文入库（或开关变了）：转给 Babel2 文章列表原地刷新（ADR-024）
		center.addObserver(self, selector: #selector(titleTranslationDidChange(_:)), name: .nnwTitleTranslationDidUpdate, object: nil)
	}

	@objc private func titleTranslationDidChange(_ notification: Notification) {
		NotificationCenter.default.post(name: .babel2TitleTranslationDidChange, object: nil)
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
		// 列表摘要：正文开头几句（上游时间线同一个函数：去标签、约 300 字、按文章缓存）。
		// 以前只读 summary 字段，很多源不提供它，标题下就是空的（2026-09-25 用户）。
		let summary = Self.listSummary(for: article)
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
			imageURL: Self.thumbnailURL(for: article),
			isRead: article.status.read,
			isStarred: article.status.starred,
			author: Self.authorName(article)
		)
	}

	/// 列表缩略图地址：文章自带的图片地址（只有 JSON Feed 有）；没有就取正文里第一张像样的配图。
	/// 普通 RSS/Atom 文章自带地址永远是空的，不补这一步列表几乎看不到缩略图（2026-09-25）。
	/// 取图复用 1.x 的 ArticleThumbnail：只读扫描正文开头、用上游 HTMLScanner、结果按文章缓存。
	static func thumbnailURL(for article: Article) -> URL? {
		if let url = article.imageURL {
			return url
		}
		return ArticleThumbnail.shared.firstImageURL(for: article).flatMap(URL.init(string:))
	}

	static func listSummary(for article: Article) -> String {
		ArticleStringFormatter.shared.truncatedSummary(article)
	}

	/// 仅供自动化测试：在 app 内构造一篇文章再取列表摘要。
	static func listSummaryForTesting(html: String?, summary: String?) -> String {
		let id = UUID().uuidString
		let article = Article(accountID: "test", articleID: id, feedID: "test", uniqueID: id, title: nil, contentHTML: html,
			contentText: nil, markdown: nil, url: nil, externalURL: nil, summary: summary, imageURL: nil,
			datePublished: nil, dateModified: nil, authors: nil,
			status: ArticleStatus(articleID: id, read: false, starred: false, dateArrived: Date()))
		return listSummary(for: article)
	}

	/// 仅供自动化测试：在 app 内构造一篇文章再取缩略图地址（测试目标不链接 Articles 模块）。
	static func thumbnailURLForTesting(html: String?, imageURL: String?, link: String?) -> URL? {
		let id = UUID().uuidString
		let article = Article(accountID: "test", articleID: id, feedID: "test", uniqueID: id, title: nil, contentHTML: html,
			contentText: nil, markdown: nil, url: link, externalURL: nil, summary: nil, imageURL: imageURL,
			datePublished: nil, dateModified: nil, authors: nil,
			status: ArticleStatus(articleID: id, read: false, starred: false, dateArrived: Date()))
		return thumbnailURL(for: article)
	}

	/// 取第一个有名字的作者（按名字排序，保证每次结果一致）。
	private static func authorName(_ article: Article) -> String? {
		article.authors?
			.compactMap { $0.name?.trimmingCharacters(in: .whitespacesAndNewlines) }
			.filter { !$0.isEmpty }
			.sorted()
			.first
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
		case .markFeedRead(let feedID):
			// 一次性批量标记（现成公开接口 markArticles 接受一组编号），不逐篇发请求
			guard let account = AccountManager.shared.existingAccount(accountID: feedID.accountID),
				let feed = account.existingFeed(withFeedID: feedID.feedID),
				feed.accountID == feedID.accountID else { return }
			let unread = await account.fetchUnreadArticlesAsync(feed: feed)
			let ids = Set(unread.filter { $0.feedID == feedID.feedID }.map(\.articleID))
			guard !ids.isEmpty else { return }
			try await account.markArticles(articleIDs: ids, statusKey: .read, flag: true)
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

/// 翻译引擎（Shared/Translation）需要原始 Article 对象：缓存键用 articleID/accountID，
/// 标题与原文链接也从它取。Babel2 页面只拿快照，唯一的例外就是阅读页做翻译时，
/// 经这里按快照编号取回对象（见 DECISIONS ADR-017）。返回类型刻意不暴露 Article，
/// 只有阅读页网页控件专用目录里的页面宿主扩展会把它还原成 Article。
@MainActor
enum Babel2LiveArticleLookup {
	static func article(for id: ArticleSnapshot.ID) async -> AnyObject? {
		guard let account = AccountManager.shared.existingAccount(accountID: id.accountID),
			let feed = account.existingFeed(withFeedID: id.feedID),
			feed.accountID == id.accountID else { return nil }
		let articles = await account.fetchArticlesAsync(.articleIDs([id.articleID]))
		return articles.first {
			$0.accountID == id.accountID && $0.feedID == id.feedID && $0.articleID == id.articleID
		}
	}
}

/// 按订阅源的「总是用阅读模式」开关：直接读写现成的 `Feed.readerViewAlwaysEnabled`
/// （公开接口，Babel 1.x 的订阅源设置页用的就是它，1.x 里设过的在新版继续生效）。ADR-020。
@MainActor
enum Babel2LiveFeedReaderSetting {
	static func isAlwaysOn(_ id: FeedSnapshot.ID) -> Bool {
		feed(id)?.readerViewAlwaysEnabled ?? false
	}

	static func setAlwaysOn(_ on: Bool, for id: FeedSnapshot.ID) {
		feed(id)?.readerViewAlwaysEnabled = on
	}

	fileprivate static func feed(_ id: FeedSnapshot.ID) -> Feed? {
		guard let account = AccountManager.shared.existingAccount(accountID: id.accountID),
			let feed = account.existingFeed(withFeedID: id.feedID),
			feed.accountID == id.accountID else { return nil }
		return feed
	}
}

/// 文章列表的标题翻译（ADR-024）：原样复用旧版标题批量翻译引擎
/// （NNWTitleTranslationController：攒批 ≤12 条一次请求、缓存、失败静默；开关按订阅源存在
/// NNWTitleTranslationStore，与 1.x 同一份，1.x 开过的源继续生效）。这里只做三件事：读写开关、
/// 把屏幕上的文章交给引擎排队、启动时唤醒引擎（它会在后台更新拉回新文章时提前翻，每次最多 50 条）。
/// 文章列表页顶部大图：订阅源高清图标（复用 1.x FeedHeroIconLoader：多来源候选、只收 ≥180px、磁盘缓存、
/// 元数据晚到时再升级；1.x 文件零改动）。ADR-027。
@MainActor
enum Babel2LiveFeedHeroImage {
	static func cached(_ id: FeedSnapshot.ID) -> UIImage? {
		guard let feed = Babel2LiveFeedReaderSetting.feed(id),
			let image = FeedHeroIconLoader.shared.cachedHero(for: feed),
			FeedHeroIconLoader.isUsableAsHero(image) else { return nil }
		return image
	}

	static func fetch(_ id: FeedSnapshot.ID, onImage: @escaping @MainActor (UIImage) -> Void) {
		guard let feed = Babel2LiveFeedReaderSetting.feed(id) else { return }
		FeedHeroIconLoader.shared.fetchHeroIfNeeded(for: feed) { image in
			guard FeedHeroIconLoader.isUsableAsHero(image) else { return }
			onImage(image)
		}
	}
}

@MainActor
enum Babel2LiveTitleTranslation {
	/// 唤醒引擎单例：它在初始化时开始监听「新文章下载完成」做提前翻译。
	static func start() {
		_ = NNWTitleTranslationController.shared
	}

	static func isEnabled(_ id: FeedSnapshot.ID) -> Bool {
		NNWTitleTranslationStore.shared.isEnabled(accountID: id.accountID, feedID: id.feedID)
	}

	static func setEnabled(_ on: Bool, for id: FeedSnapshot.ID) {
		NNWTitleTranslationStore.shared.setEnabled(on, accountID: id.accountID, feedID: id.feedID)
		if on { NNWTitleTranslationController.shared.resetFailures() }
		NotificationCenter.default.post(name: .babel2TitleTranslationDidChange, object: nil)
	}

	/// 把这些文章交给引擎：已有译文或本来是中文的由引擎自己跳过，其余攒批翻译。
	static func request(_ ids: [ArticleSnapshot.ID]) async {
		let byAccount = Dictionary(grouping: ids, by: \.accountID)
		for (accountID, accountIDs) in byAccount {
			guard let account = AccountManager.shared.existingAccount(accountID: accountID) else { continue }
			let articles = await account.fetchArticlesAsync(.articleIDs(Set(accountIDs.map(\.articleID))))
			for article in articles {
				_ = NNWTitleTranslationController.shared.displayArticle(for: article)
			}
		}
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
	static let babel2TitleTranslationDidChange = Notification.Name("Babel2TitleTranslationDidChange")
	static let babel2SettingsDidChange = Notification.Name("Babel2SettingsDidChange")
}
