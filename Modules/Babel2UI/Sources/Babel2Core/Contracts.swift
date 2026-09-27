import Foundation

public enum Babel2FeedScope: String, CaseIterable, Hashable, Sendable {
	case all
	case unread
	case starred
}

/// 首页顶部的跨源入口（2026-09-27 用户反馈第 5 条，ADR-044）。跟随档位显示：
/// 未读档 = 今日未读 / 全部未读 / 外文源；全部档 = 今天 / 全部文章 / 外文源；星标档 = 全部星标。
public enum Babel2SmartFeed: String, CaseIterable, Hashable, Sendable {
	/// 最近 24 小时（与上游「今天」同一口径）
	case today
	/// 全部订阅源
	case all
	/// 外文订阅源（自动识别 + 手动开关）
	case foreign
	/// 全部星标
	case starred

	/// 这个档位下首页列出哪些入口。
	public static func entries(for scope: Babel2FeedScope) -> [Babel2SmartFeed] {
		scope == .starred ? [.starred] : [.today, .all, .foreign]
	}

	/// 在列表里切档时实际显示哪个入口：星标档一律是「全部星标」；从「全部星标」切到别的档显示「全部」。
	public static func effective(_ base: Babel2SmartFeed, scope: Babel2FeedScope) -> Babel2SmartFeed {
		if scope == .starred { return .starred }
		return base == .starred ? .all : base
	}
}

public enum LibraryAction: Hashable, Sendable {
	case markRead(ArticleSnapshot.ID)
	case markUnread(ArticleSnapshot.ID)
	case toggleStar(ArticleSnapshot.ID)
	/// 把这个订阅源里所有未读文章标为已读（文章列表底栏「全部标为已读」，ADR-023）。
	case markFeedRead(FeedSnapshot.ID)
	/// 把这些文章标为已读（跨源列表的「全部标为已读」，ADR-044）。
	case markArticlesRead([ArticleSnapshot.ID])
	case selectFeed(FeedSnapshot.ID)
	case selectFolder(FolderSnapshot.ID)
}

public struct SettingsSnapshot: Hashable, Sendable {
	public enum Appearance: String, Hashable, Sendable {
		case system
		case light
		case dark
	}

	public let appearance: Appearance
	public let prefersReaderMode: Bool
	public let translationEnabled: Bool

	public init(
		appearance: Appearance = .system,
		prefersReaderMode: Bool = true,
		translationEnabled: Bool = true
	) {
		self.appearance = appearance
		self.prefersReaderMode = prefersReaderMode
		self.translationEnabled = translationEnabled
	}
}

public struct ArticleRenderSnapshot: Hashable, Sendable {
	public let articleID: ArticleSnapshot.ID
	public let body: String
	public let contentType: String

	public init(articleID: ArticleSnapshot.ID, body: String, contentType: String = "text/html") {
		self.articleID = articleID
		self.body = body
		self.contentType = contentType
	}
}

public protocol DataProviding: Sendable {
	func librarySnapshot(for scope: Babel2FeedScope) async throws -> LibrarySnapshot
	func feedArticlesSnapshot(for id: FeedSnapshot.ID, scope: Babel2FeedScope) async throws -> [ArticleSnapshot]
	func articleSnapshot(for id: ArticleSnapshot.ID) async throws -> ArticleSnapshot?
	/// 在一个订阅源的全部文章里搜索（不分未读 / 星标档位）。结果按列表顺序排列。
	func searchFeedArticles(_ id: FeedSnapshot.ID, query: String) async throws -> [ArticleSnapshot]
	/// 跨源合并的文章列表（ADR-044），按时间从新到旧。
	func smartFeedArticles(_ kind: Babel2SmartFeed, scope: Babel2FeedScope) async throws -> SmartFeedArticlesSnapshot
	/// 一次取回一批文章的最新状态（跨源列表原地刷新已读 / 星标用）。找不到的不返回。
	func articleSnapshots(for ids: [ArticleSnapshot.ID]) async throws -> [ArticleSnapshot]
}

extension DataProviding {
	/// 默认实现：没有跨源数据（测试替身与占位数据用）。
	public func smartFeedArticles(_ kind: Babel2SmartFeed, scope: Babel2FeedScope) async throws -> SmartFeedArticlesSnapshot {
		SmartFeedArticlesSnapshot()
	}

	/// 默认实现：逐篇取。
	public func articleSnapshots(for ids: [ArticleSnapshot.ID]) async throws -> [ArticleSnapshot] {
		var result = [ArticleSnapshot]()
		for id in ids {
			if let article = try await articleSnapshot(for: id) { result.append(article) }
		}
		return result
	}

	/// 默认实现：在该源全部文章的标题、译文标题、摘要里做不区分大小写的包含匹配。
	/// 正式实现（接入层）改用数据库全文搜索，覆盖正文。
	public func searchFeedArticles(_ id: FeedSnapshot.ID, query: String) async throws -> [ArticleSnapshot] {
		let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else { return [] }
		return try await feedArticlesSnapshot(for: id, scope: .all).filter { article in
			[article.title, article.translatedTitle ?? "", article.summary].contains {
				$0.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) != nil
			}
		}
	}
}

public protocol ActionHandling: Sendable {
	func handle(_ action: LibraryAction) async throws
}

public protocol SettingsProviding: Sendable {
	func settingsSnapshot() async throws -> SettingsSnapshot
}

public protocol ArticleRendering: Sendable {
	func render(_ article: ArticleSnapshot) async throws -> ArticleRenderSnapshot
}

public protocol ImageProviding: Sendable {
	func imageData(for url: URL) async throws -> Data?
}
