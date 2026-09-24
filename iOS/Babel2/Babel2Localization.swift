import Foundation
import Babel2Core

enum Babel2LocalizationKey: String, CaseIterable {
	case feeds = "Feeds"
	case folders = "Folders"
	case settings = "Settings"
	case add = "Add"
	case syncing = "Syncing…"
	case notAvailable = "Not available yet"
	case ok = "OK"
	case all = "All"
	case unread = "Unread"
	case starred = "Starred"
	case loading = "Loading…"
	case noFeeds = "No feeds"
	case unableToLoadFeeds = "Unable to load feeds"
	case noArticles = "No articles"
	case unableToLoadArticles = "Unable to load articles"
	case retry = "Retry"
	case back = "Back"
	case share = "Share"
	case openOriginal = "Open Original"
	case unableToLoadArticle = "Unable to load article"
	case noArticleContent = "This article has no content"

	var accessibilityIdentifier: String {
		switch self {
		case .feeds: return "babel2.feeds"
		case .folders: return "babel2.feeds.folders"
		case .settings: return "babel2.settings"
		case .add: return "babel2.add"
		case .syncing: return "babel2.feeds.syncing"
		case .notAvailable: return "babel2.not-available"
		case .ok: return "babel2.ok"
		case .all: return "babel2.scope.all"
		case .unread: return "babel2.scope.unread"
		case .starred: return "babel2.scope.starred"
		case .loading: return "babel2.feeds.loading"
		case .noFeeds: return "babel2.feeds.empty"
		case .unableToLoadFeeds: return "babel2.feeds.error"
		case .noArticles: return "babel2.feed.articles.empty"
		case .unableToLoadArticles: return "babel2.feed.articles.error"
		case .retry: return "babel2.retry"
		case .back: return "babel2.article.back"
		case .share: return "babel2.article.share"
		case .openOriginal: return "babel2.article.open-original"
		case .unableToLoadArticle: return "babel2.article.error"
		case .noArticleContent: return "babel2.article.empty"
		}
	}
}

extension Babel2FeedScope {
	var localizationKey: Babel2LocalizationKey {
		switch self {
		case .all: return .all
		case .unread: return .unread
		case .starred: return .starred
		}
	}
}

enum Babel2Localization {
	static func text(_ key: Babel2LocalizationKey, bundle: Bundle = .main) -> String {
		bundle.localizedString(forKey: key.rawValue, value: key.rawValue, table: "Babel2Localizable")
	}
}
