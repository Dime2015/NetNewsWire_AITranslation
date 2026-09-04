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
		let feedID = FeedSnapshot.ID(accountID: "account", feedID: "feed")
		let articleID = ArticleSnapshot.ID(accountID: "account", feedID: "feed", articleID: "article")
		let feed = FeedSnapshot(id: feedID, title: "Feed", url: feedURL, articleIDs: [articleID])
		let article = ArticleSnapshot(id: articleID, title: "Title", url: articleURL, feedID: feedID)
		let library = LibrarySnapshot(feeds: [feed], articles: [article])
		let state = NavigationState().pushing(.feed(feed.id)).pushing(.article(article.id))

		#expect(library.feeds == [feed])
		#expect(library.articles == [article])
		#expect(state.currentRoute == .article(article.id))
		#expect(state.popping().currentRoute == .feed(feed.id))
	}

	@Test func identitiesDoNotCollideAcrossAccounts() {
		let feedA = FeedSnapshot.ID(accountID: "account-a", feedID: "same-feed")
		let feedB = FeedSnapshot.ID(accountID: "account-b", feedID: "same-feed")
		let articleA = ArticleSnapshot.ID(accountID: "account-a", feedID: "same-feed", articleID: "same-article")
		let articleB = ArticleSnapshot.ID(accountID: "account-b", feedID: "same-feed", articleID: "same-article")

		#expect(feedA != feedB)
		#expect(articleA != articleB)
		#expect(Set([feedA, feedB]).count == 2)
		#expect(Set([articleA, articleB]).count == 2)
	}

	@Test func feedScopesAreExplicitAndDoNotChangeIdentity() throws {
		let feedURL = try #require(URL(string: "https://example.com/feed"))
		let feedID = FeedSnapshot.ID(accountID: "account", feedID: "shared")
		let snapshots = Babel2FeedScope.allCases.map {
			FeedSnapshot(id: feedID, title: $0.rawValue, url: feedURL, articleCount: 2)
		}

		#expect(Babel2FeedScope.allCases == [.all, .unread, .starred])
		#expect(Set(snapshots.map(\.id)).count == 1)
		#expect(LibrarySnapshot().isSyncing == false)
		#expect(FeedSnapshot(id: feedID, title: "Feed", url: feedURL).iconData == nil)
	}
}
