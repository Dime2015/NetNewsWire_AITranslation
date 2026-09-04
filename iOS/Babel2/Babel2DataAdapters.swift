import Babel2Core
import Foundation

struct Babel2EmptyDataProvider: DataProviding {
	func librarySnapshot(for scope: Babel2FeedScope) async throws -> LibrarySnapshot { LibrarySnapshot() }
	func feedArticlesSnapshot(for id: FeedSnapshot.ID, scope: Babel2FeedScope) async throws -> [ArticleSnapshot] { [] }
	func articleSnapshot(for id: ArticleSnapshot.ID) async throws -> ArticleSnapshot? { nil }
}

struct Babel2NoopActionHandler: ActionHandling {
	func handle(_ action: LibraryAction) async throws {}
}

struct Babel2DefaultSettingsProvider: SettingsProviding {
	func settingsSnapshot() async throws -> SettingsSnapshot { SettingsSnapshot() }
}

struct Babel2PassthroughArticleRenderer: ArticleRendering {
	func render(_ article: ArticleSnapshot) async throws -> ArticleRenderSnapshot {
		ArticleRenderSnapshot(articleID: article.id, body: article.content)
	}
}

struct Babel2EmptyImageProvider: ImageProviding {
	func imageData(for url: URL) async throws -> Data? { nil }
}
