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
	case markRead = "Mark as Read"
	case markUnread = "Mark as Unread"
	case star = "Star"
	case unstar = "Remove Star"
	case nextArticle = "Next Article"
	case readingMode = "Reading Mode"
	case translate = "Translate"
	case showOriginal = "Show Original"
	case cancelTranslation = "Cancel Translation"
	case translationFailed = "Translation Failed"
	case more = "More"
	case fetchingFullText = "Fetching full text…"
	case unableToFetchFullText = "Unable to fetch full text"
	case longImage = "Long Image"
	case feedAlwaysReadingMode = "Always Use Reading Mode for This Feed"
	case browserBack = "Go Back"
	case browserForward = "Go Forward"
	case browserReload = "Reload"
	case openInSafari = "Open in Safari"
	case unableToLoadPage = "Unable to load page"
	case markAllRead = "Mark All as Read"
	case markAllReadConfirm = "Mark %d articles as read?"
	case cancel = "Cancel"
	case generatingLongImage = "Generating long image…"
	case unableToGenerateLongImage = "Unable to generate long image"
	case savedToPhotos = "Saved to Photos"
	case articleCount = "%d articles"
	case search = "Search"
	case searchFeedPlaceholder = "Search %@"
	case noSearchResults = "No articles match “%@”"
	case searchFailed = "Search failed"
	case addSubscription = "Add Subscription"
	case addSubscriptionPlaceholder = "Paste a URL or search by keyword"
	case addSubscriptionHint = "Paste a website, feed, YouTube or Reddit address, or enter a keyword to search websites, podcasts, YouTube and Reddit."
	case searching = "Searching…"
	case subscribeTo = "Subscribe To"
	case noSubscriptionDestination = "No account is available to subscribe with. Add an account in Settings first."
	case subscribe = "Subscribe"
	case unsubscribe = "Unsubscribe"
	case unsubscribeConfirm = "Unsubscribe from “%@”? Its articles will be removed."
	case discoveryWebsites = "Websites"
	case discoveryPodcasts = "Podcasts"

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
		case .markRead, .markUnread: return "babel2.article.toolbar.read"
		case .star, .unstar: return "babel2.article.toolbar.star"
		case .nextArticle: return "babel2.article.toolbar.next"
		case .readingMode: return "babel2.article.toolbar.reading-mode"
		case .translate, .showOriginal, .cancelTranslation: return "babel2.article.toolbar.translate"
		case .translationFailed: return "babel2.article.translation-error"
		case .more: return "babel2.article.more"
		case .fetchingFullText, .unableToFetchFullText: return "babel2.article.status"
		case .longImage: return "babel2.article.toolbar.long-image"
		case .feedAlwaysReadingMode: return "babel2.article.feed-always-reading-mode"
		case .browserBack: return "babel2.browser.back"
		case .browserForward: return "babel2.browser.forward"
		case .browserReload: return "babel2.browser.reload"
		case .openInSafari: return "babel2.browser.safari"
		case .unableToLoadPage: return "babel2.browser.error"
		case .markAllRead, .markAllReadConfirm: return "babel2.feed.read-all"
		case .cancel: return "babel2.cancel"
		case .generatingLongImage, .unableToGenerateLongImage: return "babel2.article.status"
		case .savedToPhotos: return "babel2.article.toast"
		case .articleCount: return "babel2.feed.count"
		case .search, .searchFeedPlaceholder: return "babel2.feed.search"
		case .noSearchResults, .searchFailed: return "babel2.feed.articles.state"
		case .addSubscription, .addSubscriptionPlaceholder, .addSubscriptionHint, .searching, .subscribeTo, .noSubscriptionDestination,
			.subscribe, .unsubscribe, .unsubscribeConfirm, .discoveryWebsites, .discoveryPodcasts:
			return "babel2.add-subscription"
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
