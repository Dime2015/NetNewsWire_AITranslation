import Foundation
import RSCore
import RSWeb

/// Typed external actions retained as a parsing seam for integrations and
/// tests. The Babel 2 runtime deliberately does not transition to a legacy
/// controller when one of these URLs arrives.
enum Babel2LegacyURLAction: Equatable {
	case addFeed(String)
	case showUnread(articleID: String?)
	case showToday(articleID: String?)
	case showStarred(articleID: String?)
	case importThemeFile(URL)
	case downloadTheme(URL)

	var traceName: String {
		switch self {
		case .addFeed: return "addFeed"
		case .showUnread: return "showUnread"
		case .showToday: return "showToday"
		case .showStarred: return "showStarred"
		case .importThemeFile: return "importThemeFile"
		case .downloadTheme: return "downloadTheme"
		}
	}
}

enum Babel2ExternalActionParser {
	static func parse(_ url: URL) -> Babel2LegacyURLAction? {
		let rawValue = url.absoluteString

		if url.isFileURL {
			let path = url.standardizedFileURL.path
			guard path.hasSuffix(ArticleTheme.nnwThemeSuffix) else { return nil }
			return .importThemeFile(url.standardizedFileURL)
		}

		guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
			  components.fragment == nil,
			  components.user == nil,
			  components.password == nil,
			  components.port == nil else { return nil }

		if rawValue.hasPrefix("feed:") || rawValue.hasPrefix("feeds:") {
			return parseFeedURL(rawValue)
		}

		if rawValue.hasPrefix("nnw://"), components.scheme == "nnw",
			let host = components.host,
			["showunread", "showtoday", "showstarred"].contains(host),
			components.path.isEmpty {

			let query = components.queryItems ?? []
			guard components.percentEncodedQuery == nil || (query.count == 1 && query[0].name == "id") else {
				return nil
			}
			let articleID: String?
			if components.percentEncodedQuery == nil {
				articleID = nil
			} else {
				guard let value = query[0].value, !value.isEmpty else { return nil }
				articleID = value
			}
			switch host {
			case "showunread": return .showUnread(articleID: articleID)
			case "showtoday": return .showToday(articleID: articleID)
			default: return .showStarred(articleID: articleID)
			}
		}

		guard rawValue.hasPrefix("netnewswire://"),
			  components.scheme == "netnewswire",
			  components.host == "theme",
			  components.path == "/add",
			  let queryItems = components.queryItems,
			  queryItems.count == 1,
			  queryItems[0].name == "url",
			  let value = queryItems[0].value,
			  !value.isEmpty,
			  let themeURL = URL(string: value),
			  let themeComponents = URLComponents(url: themeURL, resolvingAgainstBaseURL: false),
			  themeComponents.host != nil,
			  themeComponents.user == nil,
			  themeComponents.password == nil,
			  themeComponents.fragment == nil,
			  themeURL.absoluteString.hasPrefix("http://") || themeURL.absoluteString.hasPrefix("https://") else {
			return nil
		}
		return .downloadTheme(themeURL)
	}

	private static func parseFeedURL(_ rawValue: String) -> Babel2LegacyURLAction? {
		let isFeeds = rawValue.hasPrefix("feeds:")
		let prefix = isFeeds ? "feeds:" : "feed:"
		let remainder = String(rawValue.dropFirst(prefix.count))
		if !remainder.isEmpty,
			!remainder.hasPrefix("//"),
			!remainder.hasPrefix("http://"),
			!remainder.hasPrefix("https://") {
			guard !remainder.contains("://") else { return nil }
		}
		let normalized = rawValue.normalizedURL
		guard normalized.mayBeURL,
			  let normalizedURL = URL(string: normalized),
			  let normalizedComponents = URLComponents(url: normalizedURL, resolvingAgainstBaseURL: false),
			  ["http", "https"].contains(normalizedComponents.scheme ?? ""),
			  normalizedComponents.host != nil,
			  normalizedComponents.user == nil,
			  normalizedComponents.password == nil else { return nil }
		return .addFeed(normalized)
	}
}
