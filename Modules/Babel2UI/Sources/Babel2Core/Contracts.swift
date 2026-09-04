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
