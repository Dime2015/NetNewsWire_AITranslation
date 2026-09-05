import Foundation

public struct ArticleSnapshot: Identifiable, Hashable, Sendable {
	public struct ID: Hashable, Sendable {
		public let accountID: String
		public let feedID: String
		public let articleID: String

		public init(accountID: String, feedID: String, articleID: String) {
			self.accountID = accountID
			self.feedID = feedID
			self.articleID = articleID
		}
	}

	public let id: ID
	public let title: String
	public let translatedTitle: String?
	public let summary: String
	public let content: String
	public let url: URL?
	public let feedID: FeedSnapshot.ID
	public let publishedAt: Date?
	public let imageURL: URL?
	public let isRead: Bool
	public let isStarred: Bool

	public init(
		id: ID,
		title: String,
		translatedTitle: String? = nil,
		summary: String = "",
		content: String = "",
		url: URL?,
		feedID: FeedSnapshot.ID,
		publishedAt: Date? = nil,
		imageURL: URL? = nil,
		isRead: Bool = false,
		isStarred: Bool = false
	) {
		self.id = id
		self.title = title
		self.translatedTitle = translatedTitle
		self.summary = summary
		self.content = content
		self.url = url
		self.feedID = feedID
		self.publishedAt = publishedAt
		self.imageURL = imageURL
		self.isRead = isRead
		self.isStarred = isStarred
	}
}

public struct FeedSnapshot: Identifiable, Hashable, Sendable {
	public struct ID: Hashable, Sendable {
		public let accountID: String
		public let feedID: String

		public init(accountID: String, feedID: String) {
			self.accountID = accountID
			self.feedID = feedID
		}
	}

	public let id: ID
	public let title: String
	public let url: URL
	public let articleIDs: [ArticleSnapshot.ID]
	public let articleCount: Int?
	public let iconData: Data?
	public let isMuted: Bool

	public init(
		id: ID,
		title: String,
		url: URL,
		articleIDs: [ArticleSnapshot.ID] = [],
		articleCount: Int? = nil,
		iconData: Data? = nil,
		isMuted: Bool = false
	) {
		self.id = id
		self.title = title
		self.url = url
		self.articleIDs = articleIDs
		self.articleCount = articleCount
		self.iconData = iconData
		self.isMuted = isMuted
	}
}

public struct FolderSnapshot: Identifiable, Hashable, Sendable {
	public typealias ID = String

	public let id: ID
	public let title: String
	public let feedIDs: [FeedSnapshot.ID]
	public let articleCount: Int?

	public init(id: ID, title: String, feedIDs: [FeedSnapshot.ID] = [], articleCount: Int? = nil) {
		self.id = id
		self.title = title
		self.feedIDs = feedIDs
		self.articleCount = articleCount
	}
}

public struct LibrarySnapshot: Hashable, Sendable {
	public let feeds: [FeedSnapshot]
	public let folders: [FolderSnapshot]
	public let articles: [ArticleSnapshot]
	public let generatedAt: Date
	public let isSyncing: Bool

	public init(
		feeds: [FeedSnapshot] = [],
		folders: [FolderSnapshot] = [],
		articles: [ArticleSnapshot] = [],
		generatedAt: Date = .now,
		isSyncing: Bool = false
	) {
		self.feeds = feeds
		self.folders = folders
		self.articles = articles
		self.generatedAt = generatedAt
		self.isSyncing = isSyncing
	}
}
