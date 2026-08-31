import Foundation
import Testing
@testable import Babel2Core
@testable import Babel2UI

@Suite struct Babel2UITests {
	@Test func productIdentityIsExplicit() {
		#expect(Babel2Core.productName == "Babel 2.0")
		#if canImport(UIKit)
		#expect(Babel2UI.isUIKitAvailable)
		#else
		#expect(!Babel2UI.isUIKitAvailable)
		#endif
	}

	@Test func snapshotsAreValueBasedAndNavigationIsPure() throws {
		let feedURL = try #require(URL(string: "https://example.com/feed"))
		let articleURL = try #require(URL(string: "https://example.com/article"))
		let feed = FeedSnapshot(id: "feed", title: "Feed", url: feedURL, articleIDs: ["article"])
		let article = ArticleSnapshot(id: "article", title: "Title", url: articleURL, feedID: feed.id)
		let library = LibrarySnapshot(feeds: [feed], articles: [article])
		let state = NavigationState().pushing(.feed(feed.id)).pushing(.article(article.id))

		#expect(library.feeds == [feed])
		#expect(library.articles == [article])
		#expect(state.currentRoute == .article(article.id))
		#expect(state.popping().currentRoute == .feed(feed.id))
	}
}
