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
		case .today: "Today"
		case .unread: "Unread"
		case .saved: "Starred"
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

		return uniqueArticles(articles).sorted {
			if $0.logicalDatePublished == $1.logicalDatePublished {
				return $0.articleID < $1.articleID
			}
			return $0.logicalDatePublished > $1.logicalDatePublished
		}
	}

	static func loadArticles(for fetchType: FetchType) async -> [Article] {
		let articles = await AccountManager.shared.fetchArticlesAsync(fetchType)
		return sortedArticles(articles)
	}

	/// `FetchType` has no account-wide "all" case. The compact filter bar does,
	/// so compose its local source from the actual feeds rather than pretending
	/// the unread smart feed contains read articles.
	static func loadAllArticles() async -> [Article] {
		var articles = Set<Article>()
		for account in AccountManager.shared.sortedActiveAccounts {
			for feed in account.flattenedFeeds() {
				articles.formUnion(await account.fetchArticlesAsync(.feed(feed)))
			}
		}
		return sortedArticles(articles)
	}

	/// Smart feeds can temporarily expose the same article through more than one
	/// backing record while sync is settling. The timeline is keyed by article ID,
	/// so collapse those records before grouping into day sections; otherwise one
	/// article is rendered twice on top of itself.
	private static func uniqueArticles(_ articles: some Sequence<Article>) -> [Article] {
		var seen = Set<String>()
		return articles.filter { seen.insert($0.articleID).inserted }
	}

	private static func sortedArticles(_ articles: some Sequence<Article>) -> [Article] {
		uniqueArticles(articles).sorted {
			if $0.logicalDatePublished == $1.logicalDatePublished { return $0.articleID < $1.articleID }
			return $0.logicalDatePublished > $1.logicalDatePublished
		}
	}

	static func sorted(_ articles: some Sequence<Article>) -> [Article] {
		sortedArticles(articles)
	}

	static func displayTitle(for article: Article, usesTitleTranslation: Bool = true) -> String {
		if usesTitleTranslation,
		   let translated = NNWTitleTranslationController.shared.cachedTranslatedTitle(for: article), !translated.isEmpty {
			return decodeHTMLText(translated)
		}
		if let title = article.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
			return decodeHTMLText(title)
		}
		// Some feeds omit the title; Reeder still shows a useful readable line.
		if let summary = summary(for: article),
		   let boundary = summary.firstIndex(where: { ".!?。！？".contains($0) }) {
			let fallback = summary[...boundary].drop(while: { $0.isWhitespace })
			let text = String(fallback).trimmingCharacters(in: .whitespacesAndNewlines)
			return text.count > 80 ? String(text.prefix(77)) + "…" : text
		}
		if let html = article.contentHTML, let heading = html.range(of: #"(?s)<h[1-6][^>]*>.*?</h[1-6]>"#, options: .regularExpression) {
			let raw = String(html[heading]).replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
			let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
			if !text.isEmpty {
				let decoded = decodeHTMLText(text)
				return decoded.count > 80 ? String(decoded.prefix(77)) + "…" : decoded
			}
		}
		if let html = article.contentHTML {
			let plain = html
				.replacingOccurrences(of: #"(?is)<script[^>]*>.*?</script>|<style[^>]*>.*?</style>"#, with: " ", options: .regularExpression)
				.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
				.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
				.trimmingCharacters(in: .whitespacesAndNewlines)
			if !plain.isEmpty {
				let text = plain.split(separator: ".", maxSplits: 1).first.map(String.init) ?? plain
				let decoded = decodeHTMLText(text)
				return decoded.count > 80 ? String(decoded.prefix(77)) + "…" : decoded
			}
		}
		return "Untitled"
	}

	static func summary(for article: Article) -> String? {
		let candidate = article.summary ?? article.contentText
		guard let candidate else { return nil }
		let collapsed = candidate
			.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
			.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !collapsed.isEmpty else { return nil }
		return decodeHTMLText(collapsed)
	}

	private static func decodeHTMLText(_ value: String) -> String {
		let entities: [String: String] = [
			"&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"",
			"&#39;": "'", "&apos;": "'", "&rsquo;": "’", "&lsquo;": "‘",
			"&rdquo;": "”", "&ldquo;": "“", "&nbsp;": " ",
			"&ndash;": "–", "&mdash;": "—", "&hellip;": "…",
			"&copy;": "©", "&reg;": "®", "&trade;": "™",
			"&laquo;": "«", "&raquo;": "»", "&middot;": "·", "&bull;": "•"
		]
		// Title/summary decoding sits on the cell-configuration hot path. Using
		// NSAttributedString's HTML importer here spins up the HTML/WebKit stack
		// once per visible label and can stall the main thread for seconds. Feed
		// titles only need tags removed and entities decoded, so keep this path
		// deliberately lightweight and deterministic.
		var normalized = value.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
		// Feeds occasionally double-encode entities (for example &amp;rsquo;).
		// Two passes handle both the direct and double-encoded forms.
		for _ in 0..<2 {
			for (entity, replacement) in entities { normalized = normalized.replacingOccurrences(of: entity, with: replacement) }
			normalized = decodeNumericEntities(in: normalized)
		}
		// Handle feeds that preserve an arbitrary number of ampersand layers.
		normalized = normalized.replacingOccurrences(of: #"(?i)&(?:amp;)*rsquo;"#, with: "’", options: .regularExpression)
		normalized = normalized.replacingOccurrences(of: #"(?i)&(?:amp;)*lsquo;"#, with: "‘", options: .regularExpression)
		normalized = normalized.replacingOccurrences(of: #"(?i)&(?:amp;)*rdquo;"#, with: "”", options: .regularExpression)
		normalized = normalized.replacingOccurrences(of: #"(?i)&(?:amp;)*ldquo;"#, with: "“", options: .regularExpression)
		return normalized.trimmingCharacters(in: .whitespacesAndNewlines)
	}

	private static func decodeNumericEntities(in value: String) -> String {
		guard let expression = try? NSRegularExpression(pattern: #"&#(?:x([0-9a-fA-F]+)|([0-9]+));"#) else { return value }
		let range = NSRange(value.startIndex..<value.endIndex, in: value)
		let matches = expression.matches(in: value, range: range)
		guard !matches.isEmpty else { return value }
		let result = NSMutableString(string: value)
		for match in matches.reversed() {
			let hexRange = match.range(at: 1)
			let decimalRange = match.range(at: 2)
			let digits: String
			let radix: Int
			if hexRange.location != NSNotFound {
				digits = (value as NSString).substring(with: hexRange)
				radix = 16
			} else {
				digits = (value as NSString).substring(with: decimalRange)
				radix = 10
			}
			guard let scalarValue = UInt32(digits, radix: radix),
				  let scalar = UnicodeScalar(scalarValue) else { continue }
			result.replaceCharacters(in: match.range, with: String(Character(scalar)))
		}
		return result as String
	}
}
