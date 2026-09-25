import Foundation

public enum Babel2FeedScope: String, CaseIterable, Hashable, Sendable {
	case all
	case unread
	case starred
}

public enum LibraryAction: Hashable, Sendable {
	case markRead(ArticleSnapshot.ID)
	case markUnread(ArticleSnapshot.ID)
	case toggleStar(ArticleSnapshot.ID)
	/// 把这个订阅源里所有未读文章标为已读（文章列表底栏「全部标为已读」，ADR-023）。
	case markFeedRead(FeedSnapshot.ID)
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
}

extension DataProviding {
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
