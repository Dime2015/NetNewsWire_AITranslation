//
//  BabelLibrary.swift
//  NetNewsWire
//

import Foundation
import Account
import Articles

enum BabelLibrarySection: String, CaseIterable, Hashable {
	case today
	case unread
	case saved

	var title: String {
		switch self {
		case .today: "今天"
		case .unread: "未读"
		case .saved: "已收藏"
		}
	}

	var subtitle: String {
		switch self {
		case .today: "最近一天抵达的文章"
		case .unread: "还没有读过的全部文章"
		case .saved: "留给以后慢慢读"
		}
	}

	var symbolName: String {
		switch self {
		case .today: "sun.max"
		case .unread: "circle.fill"
		case .saved: "bookmark"
		}
	}
}

struct BabelHomeSnapshot {
	let counts: [BabelLibrarySection: Int]
	let accountCount: Int
	let feedCount: Int
	let latestUnreadArticle: Article?
}

@MainActor enum BabelLibrary {

	static func loadHomeSnapshot() async -> BabelHomeSnapshot {
		let todayArticles = await SmartFeedsController.shared.todayFeed.fetchArticlesAsync()
		let unreadArticles = await SmartFeedsController.shared.unreadFeed.fetchArticlesAsync()
		let savedArticles = await SmartFeedsController.shared.starredFeed.fetchArticlesAsync()
		let accounts = AccountManager.shared.sortedActiveAccounts

		return BabelHomeSnapshot(
			counts: [
				.today: todayArticles.count,
				.unread: AccountManager.shared.unreadCount,
				.saved: savedArticles.count
			],
			accountCount: accounts.count,
			feedCount: accounts.reduce(0) { $0 + $1.flattenedFeeds().count },
			latestUnreadArticle: unreadArticles.max { $0.logicalDatePublished < $1.logicalDatePublished }
		)
	}

	static func loadArticles(for section: BabelLibrarySection) async -> [Article] {
		let articles: Set<Article>
		switch section {
		case .today:
			articles = await SmartFeedsController.shared.todayFeed.fetchArticlesAsync()
		case .unread:
			articles = await SmartFeedsController.shared.unreadFeed.fetchArticlesAsync()
		case .saved:
			articles = await SmartFeedsController.shared.starredFeed.fetchArticlesAsync()
		}

		return articles.sorted {
			if $0.logicalDatePublished == $1.logicalDatePublished {
				return $0.articleID < $1.articleID
			}
			return $0.logicalDatePublished > $1.logicalDatePublished
		}
	}

	static func loadArticles(for fetchType: FetchType) async -> [Article] {
		let articles = await AccountManager.shared.fetchArticlesAsync(fetchType)
		return articles.sorted {
			if $0.logicalDatePublished == $1.logicalDatePublished { return $0.articleID < $1.articleID }
			return $0.logicalDatePublished > $1.logicalDatePublished
		}
	}

	static func displayTitle(for article: Article) -> String {
		NNWTitleTranslationController.shared.cachedTranslatedTitle(for: article)
			?? article.title?.trimmingCharacters(in: .whitespacesAndNewlines)
			?? "无标题"
	}

	static func summary(for article: Article) -> String? {
		let candidate = article.summary ?? article.contentText
		guard let candidate else { return nil }
		let collapsed = candidate
			.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
			.trimmingCharacters(in: .whitespacesAndNewlines)
		return collapsed.isEmpty ? nil : collapsed
	}
}
