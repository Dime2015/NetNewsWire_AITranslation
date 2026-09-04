import XCTest
import Articles
import RSParser

@testable import Account

@MainActor
final class FeedArticleCountsTests: XCTestCase {
	func testCountsAreGroupedByFeedAndMissingFeedIsZero() async throws {
		let manager = TestAccountManager()
		let account = manager.createAccount(type: .onMyMac)
		defer { manager.deleteAccount(account) }

		let firstFeed = account.createFeed(with: "First", url: "https://example.com/first", feedID: "first", homePageURL: nil)
		let secondFeed = account.createFeed(with: "Second", url: "https://example.com/second", feedID: "second", homePageURL: nil)
		account.addFeedToTreeAtTopLevel(firstFeed)
		account.addFeedToTreeAtTopLevel(secondFeed)

		let firstItems = Set([
			makeItem(id: "first-1", feedURL: firstFeed.url),
			makeItem(id: "first-2", feedURL: firstFeed.url)
		])
		let secondItems = Set([
			makeItem(id: "second-1", feedURL: secondFeed.url)
		])
		_ = await account.updateAsync(feedID: firstFeed.feedID, parsedItems: firstItems, deleteOlder: false)
		_ = await account.updateAsync(feedID: secondFeed.feedID, parsedItems: secondItems, deleteOlder: false)
		_ = await account.updateStatusesAsync(articleIDs: ["first-1"], statusKey: .read, flag: false)
		_ = await account.updateStatusesAsync(articleIDs: ["first-2"], statusKey: .read, flag: true)
		_ = await account.updateStatusesAsync(articleIDs: ["first-2"], statusKey: .starred, flag: true)
		_ = await account.updateStatusesAsync(articleIDs: ["second-1"], statusKey: .read, flag: false)

		let counts = await account.fetchFeedArticleCountsAsync()
		XCTAssertEqual(counts[firstFeed.feedID]?.totalCount, 2)
		XCTAssertEqual(counts[firstFeed.feedID]?.unreadCount, 1)
		XCTAssertEqual(counts[firstFeed.feedID]?.starredCount, 1)
		XCTAssertEqual(counts[secondFeed.feedID]?.totalCount, 1)
		XCTAssertEqual(counts[secondFeed.feedID]?.unreadCount, 1)
		XCTAssertEqual(counts[secondFeed.feedID]?.starredCount, 0)
		XCTAssertEqual(counts["missing"]?.totalCount ?? 0, 0)
		XCTAssertEqual(counts["missing"]?.unreadCount ?? 0, 0)
		XCTAssertEqual(counts["missing"]?.starredCount ?? 0, 0)
	}

	func testEmptyFeedSetReturnsEmptyMap() async throws {
		let manager = TestAccountManager()
		let account = manager.createAccount(type: .onMyMac)
		defer { manager.deleteAccount(account) }

		let counts = await account.fetchFeedArticleCountsAsync()
		XCTAssertTrue(counts.isEmpty)
	}

	private func makeItem(id: String, feedURL: String) -> ParsedItem {
		ParsedItem(
			syncServiceID: id,
			uniqueID: id,
			feedURL: feedURL,
			url: "https://example.com/articles/\(id)",
			externalURL: nil,
			title: id,
			language: nil,
			contentHTML: "<p>Body</p>",
			contentText: "Body",
			markdown: nil,
			summary: nil,
			imageURL: nil,
			bannerImageURL: nil,
			datePublished: Date(),
			dateModified: nil,
			authors: nil,
			tags: nil,
			attachments: nil
		)
	}
}
