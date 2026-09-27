import Foundation
import UIKit
import UserNotifications
import Account
import Articles
import Images
import RSWeb
import RSCore
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
		// 订阅源增删（添加订阅、取消订阅、导入 OPML、删除账户）：首页重新加载（2026-09-25 添加订阅页时补上）
		center.addObserver(self, selector: #selector(libraryDidChange(_:)), name: .ChildrenDidChange, object: nil)
		// 订阅源 / 文件夹改了名（首页长按或文章列表「更多」里重命名，ADR-045）
		center.addObserver(self, selector: #selector(libraryDidChange(_:)), name: .DisplayNameDidChange, object: nil)
		// 外文源判定变了（自动识别出一批 / 用户拨了开关）：首页「外文源」入口的篇数要跟着变（ADR-044）
		center.addObserver(self, selector: #selector(libraryDidChange(_:)), name: NNWForeignFeedStore.didChangeNotification, object: nil)
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

		let smartCounts = try await makeSmartFeedCounts(scope: scope, accounts: accounts, countsByFeedID: countsByFeedID)
		return LibrarySnapshot(
			feeds: feedSnapshots,
			folders: folderSnapshots,
			generatedAt: Date(),
			isSyncing: AccountManager.shared.refreshInProgress,
			smartFeedCounts: smartCounts,
			accountTitles: Dictionary(accounts.map { ($0.accountID, $0.nameForDisplay) }, uniquingKeysWith: { first, _ in first })
		)
	}

	/// 首页顶部跨源入口的篇数（ADR-044）：按档位——
	/// 未读档：今日未读（上游「今天」口径的未读数）/ 全部未读 / 外文源未读；
	/// 全部档：今天的文章数 / 全部文章数 / 外文源文章数；星标档：全部星标。
	private func makeSmartFeedCounts(scope: Babel2FeedScope, accounts: [Account], countsByFeedID: [FeedSnapshot.ID: Int]) async throws -> [Babel2SmartFeed: Int] {
		let foreignIDs = Self.foreignFeedIDs(in: accounts)
		let total = countsByFeedID.values.reduce(0, +)
		let foreign = countsByFeedID.reduce(0) { $0 + (foreignIDs.contains($1.key) ? $1.value : 0) }
		switch scope {
		case .starred:
			return [.starred: total]
		case .unread:
			var today = 0
			for account in accounts {
				try Task.checkCancellation()
				today += await account.fetchUnreadCountForTodayAsync()
			}
			return [.today: today, .all: total, .foreign: foreign]
		case .all:
			var today = 0
			for account in accounts {
				try Task.checkCancellation()
				today += await account.fetchArticlesAsync(.today(nil)).count
			}
			return [.today: today, .all: total, .foreign: foreign]
		}
	}

	private static func foreignFeedIDs(in accounts: [Account]) -> Set<FeedSnapshot.ID> {
		var ids = Set<FeedSnapshot.ID>()
		for account in accounts {
			for feed in account.flattenedFeeds() where NNWForeignFeedStore.shared.isForeign(feed) {
				ids.insert(FeedSnapshot.ID(accountID: account.accountID, feedID: feed.feedID))
			}
		}
		return ids
	}

	/// 跨源列表最多列多少篇（从新到旧取）。首页入口的篇数仍是真实总数。
	static let smartFeedLimit = 1000
	/// 全部档的「全部文章 / 外文源」只看最近这么多天（全库文章可能有几万篇，逐源取全部太重）。
	static let smartFeedRecentWindow: TimeInterval = 30 * 24 * 60 * 60

	nonisolated func smartFeedArticles(_ kind: Babel2SmartFeed, scope: Babel2FeedScope) async throws -> SmartFeedArticlesSnapshot {
		try await makeSmartFeedArticles(kind, scope: scope)
	}

	/// 跨源合并的文章（ADR-044）。按「这个档位下实际显示哪个入口」取（星标档一律全部星标），
	/// 从新到旧最多 1000 篇；只留仍在订阅的源里的文章（每行要显示来源名与图标）。
	private func makeSmartFeedArticles(_ kind: Babel2SmartFeed, scope: Babel2FeedScope) async throws -> SmartFeedArticlesSnapshot {
		let effective = Babel2SmartFeed.effective(kind, scope: scope)
		let accounts = AccountManager.shared.sortedActiveAccounts
		var collected = [Article]()
		for account in accounts {
			try Task.checkCancellation()
			let foreign = Set(account.flattenedFeeds().filter { NNWForeignFeedStore.shared.isForeign($0) }.map(\.feedID))
			switch (effective, scope) {
			case (.starred, _):
				collected += await account.fetchArticlesAsync(.starred(nil))
			case (.today, .unread):
				collected += await account.fetchArticlesAsync(.today(nil)).filter { !$0.status.read }
			case (.today, _):
				collected += await account.fetchArticlesAsync(.today(nil))
			case (.all, .unread):
				collected += await account.fetchArticlesAsync(.unread(nil))
			case (.foreign, .unread):
				guard !foreign.isEmpty else { continue }
				collected += await account.fetchArticlesAsync(.unread(nil)).filter { foreign.contains($0.feedID) }
			case (.all, _), (.foreign, _):
				let cutoff = Date().addingTimeInterval(-Self.smartFeedRecentWindow)
				for feed in account.flattenedFeeds() where effective == .all || foreign.contains(feed.feedID) {
					try Task.checkCancellation()
					collected += await account.fetchArticlesAsync(.feed(feed)).filter { $0.logicalDatePublished >= cutoff }
				}
			}
		}
		try Task.checkCancellation()
		var feedsByID = [FeedSnapshot.ID: FeedSnapshot]()
		var articles = [ArticleSnapshot]()
		for article in collected.sorted(by: { $0.logicalDatePublished > $1.logicalDatePublished }) {
			guard articles.count < Self.smartFeedLimit else { break }
			let feedID = FeedSnapshot.ID(accountID: article.accountID, feedID: article.feedID)
			if feedsByID[feedID] == nil {
				guard let account = AccountManager.shared.existingAccount(accountID: article.accountID),
					let feed = account.existingFeed(withFeedID: article.feedID),
					let snapshot = makeFeedSnapshot(accountID: account.accountID, feed: feed, articleCount: 0) else { continue }
				feedsByID[feedID] = snapshot
			}
			let snapshot = makeArticleSnapshot(article)
			articleCache[snapshot.id] = snapshot
			articles.append(snapshot)
		}
		return SmartFeedArticlesSnapshot(articles: articles.sorted(by: articleComesFirst), feeds: Array(feedsByID.values))
	}

	nonisolated func articleSnapshots(for ids: [ArticleSnapshot.ID]) async throws -> [ArticleSnapshot] {
		try await makeFreshArticleSnapshots(for: ids)
	}

	/// 一批文章的最新状态（绕过快照缓存直接读数据库，按账户一次取完），并更新缓存。
	private func makeFreshArticleSnapshots(for ids: [ArticleSnapshot.ID]) async throws -> [ArticleSnapshot] {
		var result = [ArticleSnapshot]()
		for (accountID, group) in Dictionary(grouping: ids, by: \.accountID) {
			try Task.checkCancellation()
			guard let account = AccountManager.shared.existingAccount(accountID: accountID) else { continue }
			let wanted = Set(group)
			let articles = await account.fetchArticlesAsync(.articleIDs(Set(group.map(\.articleID))))
			for article in articles {
				let snapshot = makeArticleSnapshot(article)
				guard wanted.contains(snapshot.id) else { continue }
				articleCache[snapshot.id] = snapshot
				result.append(snapshot)
			}
		}
		return result
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
			// 空文件夹（刚新建、还没放源）在未读 / 全部档也列出来，不然新建了在首页看不到（ADR-045）
			guard !visibleFeedIDs.isEmpty || (feedIDs.isEmpty && scope != .starred) else { continue }
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

	/// 文章顺序：设置里的「未读文章排序」（默认最新优先，Slice 6 接通）。
	private func articleComesFirst(_ lhs: ArticleSnapshot, _ rhs: ArticleSnapshot) -> Bool {
		switch (lhs.publishedAt, rhs.publishedAt) {
		case let (.some(left), .some(right)) where left != right:
			return Babel2LiveAppDefaults.sortNewestFirst ? left > right : left < right
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

	nonisolated func searchFeedArticles(_ id: FeedSnapshot.ID, query: String) async throws -> [ArticleSnapshot] {
		try await makeFeedSearchResults(for: id, query: query)
	}

	/// 列表搜索（2026-09-25）：在该源全部文章里搜，不分档位。两路合并：
	/// ① 数据库全文搜索（标题 + 正文）；② 标题 / 译文标题 / 摘要的包含匹配——
	/// 全文搜索按空格分词，中文整句往往搜不到，②补上中文与译文标题。
	private func makeFeedSearchResults(for id: FeedSnapshot.ID, query: String) async throws -> [ArticleSnapshot] {
		let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty,
			let account = AccountManager.shared.existingAccount(accountID: id.accountID),
			let feed = account.existingFeed(withFeedID: id.feedID),
			feed.accountID == id.accountID else { return [] }
		let all = try await fetchArticles(for: account, feed: feed, scope: .all)
		try Task.checkCancellation()
		let fullText = await account.fetchArticlesAsync(.searchWithArticleIDs(trimmed, Set(all.map(\.articleID))))
		try Task.checkCancellation()
		let fullTextIDs = Set(fullText.map(\.articleID))
		return all
			.filter { $0.accountID == id.accountID && $0.feedID == id.feedID }
			.map { article in
				let snapshot = makeArticleSnapshot(article)
				articleCache[snapshot.id] = snapshot
				return snapshot
			}
			.filter { snapshot in
				fullTextIDs.contains(snapshot.id.articleID)
					|| [snapshot.title, snapshot.translatedTitle ?? "", snapshot.summary].contains {
						$0.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) != nil
					}
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
		let iconData = Babel2LiveIconCache.iconData(for: feed, accountID: accountID)
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
		case .markArticlesRead(let articleIDs):
			// 跨源列表的「全部标为已读」：按账户分组，每个账户一次批量标记（ADR-044）
			for (accountID, group) in Dictionary(grouping: articleIDs, by: \.accountID) {
				guard let account = AccountManager.shared.existingAccount(accountID: accountID) else { continue }
				try await account.markArticles(articleIDs: Set(group.map(\.articleID)), statusKey: .read, flag: true)
			}
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

/// 阅读页正文上方的播放器信息（ADR-041）：原样复用 1.x 的两个「重新读一次订阅源」的加载器
/// （YouTubeDescriptionLoader 取视频简介、PodcastEpisodeLocator 找播客音频；都按订阅源缓存，
/// 包括「这个源没有音频」的结论，所以普通源每次启动最多多读一次订阅源；1.x 文件零改动）。
/// 只认本地 / iCloud 账户（订阅源编号就是订阅源地址）；同步服务账户拿不到就当没有。
@MainActor
enum Babel2LiveArticleMedia {
	static func extras(for id: ArticleSnapshot.ID) async -> Babel2ArticleMediaExtras? {
		guard let article = await Babel2LiveArticleLookup.article(for: id) as? Article else { return nil }
		if let description = await YouTubeDescriptionLoader.shared.description(for: article) {
			return Babel2ArticleMediaExtras(youTubeDescription: description)
		}
		// YouTube 文章没有音频可找（播放器由阅读页按链接自己放）
		guard Babel2ArticleMedia.youTubeVideoID(from: article.preferredURL) == nil else { return nil }
		if let episode = await PodcastEpisodeLocator.shared.episode(for: article), let url = URL(string: episode.audioURL) {
			return Babel2ArticleMediaExtras(audioURL: url)
		}
		return nil
	}
}

/// 外文源（ADR-044）：原样复用 1.x 的判定（NNWForeignFeedStore：看最近 15 个标题的语言，手动开关优先于自动；
/// 1.x 文件零改动）。启动时和每次同步结束后补做还没判定过的源（新订阅的源）。
@MainActor
enum Babel2LiveForeignFeeds {
	private static var observer: NSObjectProtocol?

	static func start() {
		NNWForeignFeedStore.shared.refreshDetectionIfNeeded()
		guard observer == nil else { return }
		observer = NotificationCenter.default.addObserver(forName: .AccountRefreshDidFinish, object: nil, queue: .main) { _ in
			MainActor.assumeIsolated { NNWForeignFeedStore.shared.refreshDetectionIfNeeded() }
		}
	}

	static func isForeign(_ id: FeedSnapshot.ID) -> Bool {
		Babel2LiveFeedReaderSetting.feed(id).map { NNWForeignFeedStore.shared.isForeign($0) } ?? false
	}

	/// 手动拨开关（识别错了时纠正），之后不再听自动判定。
	static func setForeign(_ foreign: Bool, for id: FeedSnapshot.ID) {
		guard let feed = Babel2LiveFeedReaderSetting.feed(id) else { return }
		NNWForeignFeedStore.shared.setManualOverride(foreign, for: feed)
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
		// 用户换过图标的源，大图也用它（ADR-046）
		if let custom = Babel2LiveCustomFeedIcons.image(for: id) {
			return custom
		}
		guard let feed = Babel2LiveFeedReaderSetting.feed(id),
			let image = FeedHeroIconLoader.shared.cachedHero(for: feed),
			FeedHeroIconLoader.isUsableAsHero(image) else { return nil }
		return image
	}

	static func fetch(_ id: FeedSnapshot.ID, onImage: @escaping @MainActor (UIImage) -> Void) {
		guard !Babel2LiveCustomFeedIcons.hasCustomIcon(id),
			let feed = Babel2LiveFeedReaderSetting.feed(id) else { return }
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

/// 旧设置存储（AppDefaults）的唯一接入点（Slice 6，2026-09-25 用户同意：边界测试对本文件单独放行 AppDefaults.shared，
/// 与 AccountManager.shared 同一写法）。Babel 2.0 其它文件一律经这里读写，不直接碰旧存储。
@MainActor
enum Babel2LiveAppDefaults {
	/// 未读文章排序：true = 最新优先（旧值 orderedDescending）。
	static var sortNewestFirst: Bool {
		get { AppDefaults.shared.timelineSortDirection != .orderedAscending }
		set { AppDefaults.shared.timelineSortDirection = newValue ? .orderedDescending : .orderedAscending }
	}

	static var confirmMarkAllRead: Bool {
		get { AppDefaults.shared.confirmMarkAllAsRead }
		set { AppDefaults.shared.confirmMarkAllAsRead = newValue }
	}

	/// 链接在 Babel 内置浏览器打开（旧设置存的是反义的「用系统浏览器」）。
	static var openLinksInApp: Bool {
		get { !AppDefaults.shared.useSystemBrowser }
		set { AppDefaults.shared.useSystemBrowser = !newValue }
	}

	/// 配色模式：0 自动 / 1 浅色 / 2 深色（与旧设置同值）。
	static var colorPaletteRawValue: Int {
		get { AppDefaults.userInterfaceColorPalette.rawValue }
		set { AppDefaults.userInterfaceColorPalette = UserInterfaceColorPalette(rawValue: newValue) ?? .automatic }
	}

	/// 开发版不允许添加 iCloud / Feedly / Inoreader 账户（与现有「新增账户」页同一规则）。
	static var isDeveloperBuild: Bool { AppDefaults.shared.isDeveloperBuild }
}

/// 设置页的账户操作（Slice 6）：账户单例只能在本文件里使用（边界测试放行点），设置页经这里读写。
@MainActor
enum Babel2LiveAccounts {
	static func summaries() -> [Babel2AccountSummary] {
		let manager = AccountManager.shared
		return manager.sortedAccounts.map { account in
			Babel2AccountSummary(id: account.accountID, name: account.nameForDisplay, kind: kind(of: account.type), isDefault: account === manager.defaultAccount)
		}
	}

	private static func kind(of type: AccountType) -> Babel2AccountSummary.Kind {
		switch type {
		case .onMyMac: return .local
		case .cloudKit: return .iCloud
		case .freshRSS: return .selfHosted
		default: return .web
		}
	}

	static var syncUnreadArticleContent: Bool {
		get { AccountManager.shared.syncArticleContentForUnreadArticles }
		set { AccountManager.shared.syncArticleContentForUnreadArticles = newValue }
	}

	static func delete(_ id: String) {
		let manager = AccountManager.shared
		guard let account = manager.existingAccount(accountID: id), account !== manager.defaultAccount else { return }
		manager.deleteAccount(account)
	}

	static var hasICloudAccount: Bool {
		AccountManager.shared.accounts.contains { $0.type == .cloudKit }
	}

	/// 可新增的账户类型：已有 iCloud 账户时不能再加；开发版不能加 iCloud / Feedly / Inoreader（与现有新增账户页同一规则）。
	static func addableKinds(isDeveloperBuild: Bool) -> [Babel2AddAccountKind] {
		Babel2AddAccountKind.allCases.filter { kind in
			switch kind {
			case .iCloud: return !isDeveloperBuild && !hasICloudAccount
			case .feedly, .inoreader: return !isDeveloperBuild
			default: return true
			}
		}
	}

	/// 导出：返回（账户名, OPML 文本）。
	static func exportOPML(_ id: String) -> (String, String)? {
		guard let account = AccountManager.shared.existingAccount(accountID: id) else { return nil }
		return (account.nameForDisplay, OPMLExporter.OPMLString(with: account, title: account.nameForDisplay))
	}

	/// 导入：失败时回调错误说明（成功回调 nil）。
	static func importOPML(_ url: URL, into id: String, completion: @escaping @MainActor (String?) -> Void) {
		guard let account = AccountManager.shared.existingAccount(accountID: id) else {
			completion(nil)
			return
		}
		account.importOPML(url) { result in
			Task { @MainActor in
				if case .failure(let error) = result {
					completion(error.localizedDescription)
				} else {
					completion(nil)
				}
			}
		}
	}
}

/// 添加订阅页的账户操作（2026-09-25）：订阅落点、是否已订阅、订阅、取消订阅。
/// 账户单例只能在本文件使用（边界测试放行点）；只调用账户的公开接口（createFeed / removeFeed），禁区一行不改。
@MainActor
enum Babel2LiveSubscriptions {
	struct Destination {
		/// 「账户编号」或「账户编号/文件夹编号」。
		let id: String
		let accountName: String
		/// nil = 顶层（不放进文件夹）。
		let folderName: String?
	}

	/// 可订阅到的位置：每个账户的顶层（个别同步服务不允许放顶层则不给）+ 各文件夹。
	static func destinations() -> [Destination] {
		AccountManager.shared.sortedActiveAccounts.flatMap { account -> [Destination] in
			var list = [Destination]()
			if !account.behaviors.contains(.disallowFeedInRootFolder) {
				list.append(Destination(id: account.accountID, accountName: account.nameForDisplay, folderName: nil))
			}
			for folder in account.sortedFolders ?? [] {
				list.append(Destination(id: "\(account.accountID)/\(folder.folderID)", accountName: account.nameForDisplay, folderName: folder.nameForDisplay))
			}
			return list
		}
	}

	private static func container(for destinationID: String) -> Container? {
		let parts = destinationID.split(separator: "/", maxSplits: 1).map(String.init)
		guard let account = AccountManager.shared.existingAccount(accountID: parts[0]) else { return nil }
		guard parts.count == 2 else { return account }
		return account.sortedFolders?.first { String($0.folderID) == parts[1] }
	}

	/// 当场问账户（不维护第二份缓存）：任一活跃账户订了这个地址就算已订阅。
	static func isSubscribed(_ feedURL: String) -> Bool {
		AccountManager.shared.activeAccounts.contains { $0.hasFeed(withURL: feedURL) }
	}

	enum SubscribeOutcome {
		case subscribed
		case alreadySubscribed
		case failed(Error)
	}

	static func subscribe(feedURL: String, name: String?, destinationID: String) async -> SubscribeOutcome {
		guard let container = container(for: destinationID) else { return .failed(AccountError.createErrorNotFound) }
		let account: Account? = (container as? Account) ?? (container as? Folder)?.account
		guard let account else { return .failed(AccountError.createErrorNotFound) }
		if account.hasFeed(withURL: feedURL) { return .alreadySubscribed }
		BatchUpdate.shared.start()
		defer { BatchUpdate.shared.end() }
		return await withCheckedContinuation { continuation in
			account.createFeed(url: feedURL, name: name, container: container, validateFeed: true) { result in
				switch result {
				case .success: continuation.resume(returning: .subscribed)
				case .failure(let error): continuation.resume(returning: .failed(error))
				}
			}
		}
	}

	/// 取消订阅：跨账户找到这个地址的所有落点逐个移除（与 1.x 发现页同一做法）。失败返回第一个错误。
	static func unsubscribe(feedURL: String) async -> Error? {
		var targets = [(Account, Feed, Container)]()
		for account in AccountManager.shared.activeAccounts {
			guard let feed = account.existingFeed(withURL: feedURL) else { continue }
			for container in account.existingContainers(withFeed: feed) {
				targets.append((account, feed, container))
			}
		}
		guard !targets.isEmpty else { return nil }
		BatchUpdate.shared.start()
		defer { BatchUpdate.shared.end() }
		var firstError: Error?
		for (account, feed, container) in targets {
			let error: Error? = await withCheckedContinuation { continuation in
				account.removeFeed(feed, from: container) { result in
					if case .failure(let error) = result {
						continuation.resume(returning: error)
					} else {
						continuation.resume(returning: nil)
					}
				}
			}
			if firstError == nil { firstError = error }
		}
		return firstError
	}
}

/// 文章列表大图上的「刷新」与「更多」（2026-09-25，ADR-031）：单个订阅源的操作，全部走账户公开接口。
@MainActor
enum Babel2LiveFeedActions {
	/// 同步按账户进行，无法只刷新一个源：刷新所有账户（与 1.x 相同）。
	static func refreshAll() {
		AccountManager.shared.refreshAllWithoutWaiting(errorHandler: ErrorHandler.log)
	}

	static var isSyncing: Bool { AccountManager.shared.refreshInProgress }

	private static func feed(_ id: FeedSnapshot.ID) -> Feed? {
		Babel2LiveFeedReaderSetting.feed(id)
	}

	static func homePageURL(_ id: FeedSnapshot.ID) -> URL? {
		guard let string = feed(id)?.homePageURL, let url = URL(string: string),
			url.scheme == "http" || url.scheme == "https" else { return nil }
		return url
	}

	static func feedURL(_ id: FeedSnapshot.ID) -> String? { feed(id)?.url }

	static func notificationsEnabled(_ id: FeedSnapshot.ID) -> Bool {
		feed(id)?.newArticleNotificationsEnabled ?? false
	}

	/// 打开新文章通知时先请求系统通知权限（与现有订阅源详情页同一做法）。
	static func setNotificationsEnabled(_ on: Bool, for id: FeedSnapshot.ID) {
		guard let feed = feed(id) else { return }
		if on {
			UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }
		}
		feed.newArticleNotificationsEnabled = on
	}

	/// 重命名：失败返回说明。
	static func rename(_ id: FeedSnapshot.ID, to name: String) async -> String? {
		guard let feed = feed(id), let account = feed.account else { return nil }
		do {
			try await account.renameFeed(feed, name: name)
			return nil
		} catch {
			return error.localizedDescription
		}
	}

	/// 取消订阅：只移除**这个账户里的这个源**（它所在的每个文件夹 / 顶层），不碰其它账户里同地址的源。
	/// 失败返回说明。
	static func unsubscribe(_ id: FeedSnapshot.ID) async -> String? {
		guard let feed = feed(id), let account = feed.account else { return nil }
		BatchUpdate.shared.start()
		defer { BatchUpdate.shared.end() }
		for container in account.existingContainers(withFeed: feed) {
			let error: Error? = await withCheckedContinuation { continuation in
				account.removeFeed(feed, from: container) { result in
					if case .failure(let error) = result {
						continuation.resume(returning: error)
					} else {
						continuation.resume(returning: nil)
					}
				}
			}
			if let error { return error.localizedDescription }
		}
		return nil
	}
}

/// 订阅源小图标的备份（2026-09-25，用户反馈切回前台时所有图标都重新加载一次）。
/// 上游的图标下载器在 app 进后台时清空**内存**缓存（刻意省内存，硬盘缓存仍在），回到前台首页刷新的那一刻
/// 拿不到图标、先显示空白，等从硬盘读回再逐个补上。这里记住每个源最后一次拿到的图标：
/// 进后台不清，只在系统报内存紧张时清。上游缓存逻辑一行不改。
///
/// 2026-09-27（用户报「第一次打开 app 时图标要延迟几秒」，ADR-039）：备份原来只在内存里，冷启动是空的，
/// 只能等上游下载器从硬盘把图一张张读回来。现在备份也存一份到手机上（Caches/Babel2FeedIcons.plist），
/// 冷启动第一眼就用它。存之前把图缩到最长边 96 像素（列表 20pt、紧凑栏 26pt，3 倍屏也够清晰），
/// 全部源加起来几百 KB；同一张图只压缩、只写盘一次。
@MainActor
enum Babel2LiveIconCache {
	/// 最长边超过这个像素就缩小再存。
	static let maxPixelSide: CGFloat = 96
	private static var icons = [String: Data]()
	/// 每个源上次压缩的原图（弱引用：原图被上游释放后自然失效）。同一张原图不重复压缩。
	private static var sources = [String: WeakImageBox]()
	private static var didLoadDisk = false
	private static var isSaveScheduled = false
	private static var observer: NSObjectProtocol?

	private final class WeakImageBox {
		weak var image: UIImage?
		init(_ image: UIImage) { self.image = image }
	}

	static func iconData(for feed: Feed, accountID: String) -> Data? {
		// 用户自己换的图标优先（ADR-046）
		if let custom = Babel2LiveCustomFeedIcons.iconData(for: FeedSnapshot.ID(accountID: accountID, feedID: feed.feedID)) {
			return custom
		}
		installMemoryWarningObserverIfNeeded()
		loadFromDiskIfNeeded()
		let key = "\(accountID)|\(feed.feedID)"
		if let image = FeedIconDownloader.shared.icon(for: feed)?.image ?? FaviconDownloader.shared.faviconAsIcon(for: feed)?.image,
			sources[key]?.image !== image || icons[key] == nil {
			sources[key] = WeakImageBox(image)
			if let data = compactData(for: image), data != icons[key] {
				icons[key] = data
				scheduleSave()
			}
		}
		return icons[key]
	}

	/// 某个订阅源此刻的小图标（ADR-039）：文章列表页 / 阅读页打开时图标还没到的，
	/// 之后据此补上（以前这两页一直显示首字母，直到重新进入）。找不到订阅源时退回备份。
	static func currentIconData(for id: FeedSnapshot.ID) -> Data? {
		if let custom = Babel2LiveCustomFeedIcons.iconData(for: id) {
			return custom
		}
		guard let feed = Babel2LiveFeedReaderSetting.feed(id) else {
			loadFromDiskIfNeeded()
			return icons["\(id.accountID)|\(id.feedID)"]
		}
		return iconData(for: feed, accountID: id.accountID)
	}

	/// 缩到最长边 96 像素（本来就小的不放大）再转成 PNG。
	static func compactData(for image: UIImage) -> Data? {
		let pixelWidth = image.size.width * image.scale
		let pixelHeight = image.size.height * image.scale
		let longest = max(pixelWidth, pixelHeight)
		guard longest > maxPixelSide else { return image.pngData() }
		let ratio = maxPixelSide / longest
		let size = CGSize(width: max(1, (pixelWidth * ratio).rounded()), height: max(1, (pixelHeight * ratio).rounded()))
		let format = UIGraphicsImageRendererFormat()
		format.scale = 1
		return UIGraphicsImageRenderer(size: size, format: format).pngData { _ in
			image.draw(in: CGRect(origin: .zero, size: size))
		}
	}

	// MARK: 存在手机上的那一份

	private static var fileURL: URL {
		FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
			.appendingPathComponent("Babel2FeedIcons.plist")
	}

	/// 第一次用到时同步读一次（文件只有几百 KB，冷启动首页第一眼就要用）。内存里已有的（更新鲜）不被覆盖。
	private static func loadFromDiskIfNeeded() {
		guard !didLoadDisk else { return }
		didLoadDisk = true
		guard let data = try? Data(contentsOf: fileURL),
			let stored = try? PropertyListDecoder().decode([String: Data].self, from: data) else { return }
		icons.merge(stored) { current, _ in current }
	}

	/// 攒 1 秒再写（冷启动时图标一张张到，合并成一次写盘），写盘在后台做。
	private static func scheduleSave() {
		guard !isSaveScheduled else { return }
		isSaveScheduled = true
		Task { @MainActor in
			try? await Task.sleep(for: .seconds(1))
			saveNow()
		}
	}

	private static func saveNow() {
		isSaveScheduled = false
		guard let data = try? PropertyListEncoder().encode(icons) else { return }
		let url = fileURL
		Task.detached(priority: .utility) {
			try? data.write(to: url, options: .atomic)
		}
	}

	private static func installMemoryWarningObserverIfNeeded() {
		guard observer == nil else { return }
		observer = NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { _ in
			MainActor.assumeIsolated {
				icons.removeAll()
				sources.removeAll()
				// 下次用到时从手机上那一份读回来（小图，读回来不占多少内存）
				didLoadDisk = false
			}
		}
	}

	/// 仅供自动化测试。
	static func storeForTesting(_ data: Data, key: String) { icons[key] = data }
	static func cachedForTesting(_ key: String) -> Data? { icons[key] }
	/// 仅供自动化测试：立刻写盘 / 清空内存后从手机上那一份读回 / 删掉某个键。
	static func saveNowForTesting() async {
		guard let data = try? PropertyListEncoder().encode(icons) else { return }
		try? data.write(to: fileURL, options: .atomic)
	}
	static func reloadFromDiskForTesting() {
		icons.removeAll()
		sources.removeAll()
		didLoadDisk = false
		loadFromDiskIfNeeded()
	}
	static func removeForTesting(_ key: String) {
		icons[key] = nil
		sources[key] = nil
	}
}

/// 首页整理文件夹与订阅源（2026-09-27 用户反馈第 4 条，ADR-045）。
///
/// 全部调用账户的公开接口（addFolder / renameFolder / removeFolder / moveFeed / removeFeed），
/// 账户模块（A 级禁区）一行不改。改完账户会发「子项变了」的通知，首页随之重新加载。
///
/// 首页上「重复」的订阅源从哪来：同一个账户里，一个源可以同时放在几个文件夹里（导入 OPML、
/// 同步服务的「标签」都会造成），首页就在每个文件夹下各列一次；多个账户各订了同一个地址时也会出现两行。
/// 长按菜单顶部写明它在哪个账户、哪几个文件夹，并提供「从这个文件夹移出」。
@MainActor
enum Babel2LiveLibraryEditing {
	static func accounts() -> [Babel2AccountChoice] {
		AccountManager.shared.sortedActiveAccounts.map { Babel2AccountChoice(id: $0.accountID, title: $0.nameForDisplay) }
	}

	/// 只有一个账户时不显示账户名。
	private static func accountTitle(_ account: Account) -> String? {
		AccountManager.shared.activeAccounts.count > 1 ? account.nameForDisplay : nil
	}

	/// 与首页快照同一种写法：「账户编号:文件夹编号」。
	static func folderSnapshotID(_ folder: Folder) -> FolderSnapshot.ID {
		"\(folder.accountID):\(folder.folderID)"
	}

	/// 「账户编号:文件夹编号」→ 文件夹。账户编号里也可能有冒号，所以从最后一个冒号拆。
	private static func folder(_ id: FolderSnapshot.ID) -> (Account, Folder)? {
		guard let separator = id.lastIndex(of: ":"),
			let number = Int(id[id.index(after: separator)...]),
			let account = AccountManager.shared.existingAccount(accountID: String(id[..<separator])),
			let folder = account.existingFolder(withID: number) else { return nil }
		return (account, folder)
	}

	private static func feed(_ id: FeedSnapshot.ID) -> (Account, Feed)? {
		guard let account = AccountManager.shared.existingAccount(accountID: id.accountID),
			let feed = account.existingFeed(withFeedID: id.feedID),
			feed.accountID == id.accountID else { return nil }
		return (account, feed)
	}

	/// 位置 → 容器：nil 是账户顶层；文件夹必须属于同一个账户（不能跨账户移动）。
	private static func container(_ folderID: FolderSnapshot.ID?, in account: Account) -> Container? {
		guard let folderID else { return account }
		guard let (owner, folder) = folder(folderID), owner.accountID == account.accountID else { return nil }
		return folder
	}

	private static func sortedFolders(_ account: Account) -> [Folder] {
		(account.folders ?? []).sorted {
			$0.nameForDisplay.localizedCaseInsensitiveCompare($1.nameForDisplay) == .orderedAscending
		}
	}

	static func folderInfo(_ id: FolderSnapshot.ID) -> Babel2FolderInfo? {
		guard let (account, folder) = folder(id) else { return nil }
		return Babel2FolderInfo(title: folder.nameForDisplay, feedCount: folder.topLevelFeeds.count, accountTitle: accountTitle(account))
	}

	/// 这个源在哪个账户、现在在哪些位置、可以移去哪些位置（顶层 + 该账户全部文件夹，含空文件夹）。
	static func placement(_ id: FeedSnapshot.ID) -> Babel2FeedPlacement? {
		guard let (account, feed) = feed(id) else { return nil }
		let topLevel = Babel2FeedLocation(folderID: nil, title: "")
		var current = account.topLevelFeeds.contains(feed) ? [topLevel] : []
		var destinations = [topLevel]
		for folder in sortedFolders(account) {
			let location = Babel2FeedLocation(folderID: folderSnapshotID(folder), title: folder.nameForDisplay)
			destinations.append(location)
			if folder.topLevelFeeds.contains(feed) {
				current.append(location)
			}
		}
		return Babel2FeedPlacement(accountTitle: accountTitle(account), current: current, destinations: destinations)
	}

	static func createFolder(named name: String, accountID: String) async -> Result<FolderSnapshot.ID, Babel2EditFailure> {
		guard let account = AccountManager.shared.existingAccount(accountID: accountID) else {
			return .failure(Babel2EditFailure(message: Babel2Localization.text(.notAvailable)))
		}
		do {
			let folder = try await account.addFolder(name)
			return .success(folderSnapshotID(folder))
		} catch {
			return .failure(Babel2EditFailure(message: error.localizedDescription))
		}
	}

	static func renameFolder(_ id: FolderSnapshot.ID, to name: String) async -> String? {
		guard let (account, folder) = folder(id) else { return nil }
		do {
			try await account.renameFolder(folder, to: name)
			return nil
		} catch {
			return error.localizedDescription
		}
	}

	/// 删除文件夹。
	/// - keepFeeds = true：只在这个文件夹里的源先移到顶层，再删文件夹（同时也在别处的源本来就不会丢）。
	/// - keepFeeds = false：与上游「删除文件夹」相同——只在这个文件夹里的源随文件夹一起删除，
	///   同时也在别的文件夹里的源留在那里。
	static func deleteFolder(_ id: FolderSnapshot.ID, keepFeeds: Bool) async -> String? {
		guard let (account, folder) = folder(id) else { return nil }
		BatchUpdate.shared.start()
		defer { BatchUpdate.shared.end() }
		if keepFeeds {
			let onlyHere = folder.topLevelFeeds
				.filter { account.existingContainers(withFeed: $0).count == 1 }
				.sorted { $0.feedID < $1.feedID }
			for feed in onlyHere {
				if let message = await completion({ account.moveFeed(feed, from: folder, to: account, completion: $0) }) {
					return message
				}
			}
		}
		return await completion { account.removeFolder(folder, completion: $0) }
	}

	/// 把源从一个位置移到另一个位置（nil = 顶层）。目标位置本来就有它（「重复」的情况）：只从原位置移出。
	static func moveFeed(_ id: FeedSnapshot.ID, from source: FolderSnapshot.ID?, to destination: FolderSnapshot.ID?) async -> String? {
		guard source != destination,
			let (account, feed) = feed(id),
			let from = container(source, in: account),
			let to = container(destination, in: account),
			from.topLevelFeeds.contains(feed) else { return nil }
		BatchUpdate.shared.start()
		defer { BatchUpdate.shared.end() }
		if to.topLevelFeeds.contains(feed) {
			return await completion { account.removeFeed(feed, from: from, completion: $0) }
		}
		return await completion { account.moveFeed(feed, from: from, to: to, completion: $0) }
	}

	/// 从某个文件夹移出。只在它同时还在别处时才做——只剩这一处时移出就等于取消订阅，那要走「取消订阅」。
	static func removeFeed(_ id: FeedSnapshot.ID, fromFolder folderID: FolderSnapshot.ID) async -> String? {
		guard let (account, feed) = feed(id),
			let folder = container(folderID, in: account),
			folder.topLevelFeeds.contains(feed),
			account.existingContainers(withFeed: feed).count > 1 else { return nil }
		return await completion { account.removeFeed(feed, from: folder, completion: $0) }
	}

	/// 账户接口是回调式的：等它回调，失败时返回说明。
	private static func completion(_ start: (@escaping (Result<Void, Error>) -> Void) -> Void) async -> String? {
		await withCheckedContinuation { continuation in
			start { result in
				if case .failure(let error) = result {
					continuation.resume(returning: error.localizedDescription)
				} else {
					continuation.resume(returning: nil)
				}
			}
		}
	}
}
