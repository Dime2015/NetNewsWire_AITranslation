import Foundation
import Babel2Core

enum Babel2LocalizationKey: String, CaseIterable {
	case feeds = "Feeds"
	case settings = "Settings"
	case add = "Add"
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

	var accessibilityIdentifier: String {
		switch self {
		case .feeds: return "babel2.feeds"
		case .settings: return "babel2.settings"
		case .add: return "babel2.add"
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
