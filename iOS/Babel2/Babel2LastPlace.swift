import UIKit
import Babel2Core

/// 重开 App 回到上次的页面（2026-09-27 用户要求「点开 App 直接跳到上次退出时的那个页面」；「隔太久就回首页」）。
///
/// 记什么：上次在看哪个文章列表（订阅源或跨源入口）、哪一档，以及列表上面打开着的那篇文章。
/// - 只记「列表 → 文章」这两层：停在内置浏览器里 → 回到那篇文章（网页状态不可靠，不恢复）；
///   停在设置、添加订阅、首页 → 不记，下次从首页开始。「翻译此页」的独立网页不算文章。
/// - 滑到哪、阅读模式、是否在看译文，各自早就按文章记着（ADR-053 / ADR-019），这里不重复记。
/// 什么时候记：App 退到后台时（从后台划掉 App 之前必然先退到后台）。
/// 什么时候用：冷启动时，记录不超过 24 小时才用（maxAge）；超过了从首页开始。
/// App 还留在后台时切回来本来就停在原处，不经过这里。
struct Babel2LastPlace: Codable, Equatable {
	/// 隔多久就不回去了（用户：「隔太久就回首页」；数字可调）。
	static let maxAge: TimeInterval = 24 * 60 * 60

	struct ArticleRef: Codable, Equatable {
		var accountID: String
		var feedID: String
		var articleID: String
	}

	/// 订阅源的文章列表（跨源列表时为 nil）
	var accountID: String?
	var feedID: String?
	/// 跨源列表（今日未读 / 全部未读 / 外文源 / 全部星标，Babel2SmartFeed 的原始值）
	var smartFeed: String?
	/// 列表当时在哪一档（Babel2FeedScope 的原始值）
	var scope: String
	/// 列表上面打开着的文章
	var article: ArticleRef?
	var savedAt: Date

	var feedSnapshotID: FeedSnapshot.ID? {
		guard let accountID, let feedID else { return nil }
		return FeedSnapshot.ID(accountID: accountID, feedID: feedID)
	}
	var smartFeedKind: Babel2SmartFeed? { smartFeed.flatMap(Babel2SmartFeed.init(rawValue:)) }
	var feedScope: Babel2FeedScope { Babel2FeedScope(rawValue: scope) ?? .unread }
	var articleSnapshotID: ArticleSnapshot.ID? {
		article.map { ArticleSnapshot.ID(accountID: $0.accountID, feedID: $0.feedID, articleID: $0.articleID) }
	}

	func isFresh(now: Date) -> Bool {
		now.timeIntervalSince(savedAt) <= Self.maxAge && now >= savedAt.addingTimeInterval(-60)
	}

	/// 从导航栈里读出「现在在哪」：找到第一个文章列表，再找它上面第一篇（非独立网页的）文章。没有列表 → nil（首页）。
	@MainActor
	static func capture(from viewControllers: [UIViewController], now: Date) -> Babel2LastPlace? {
		guard let listIndex = viewControllers.firstIndex(where: { $0 is Babel2FeedViewController }),
			  let list = viewControllers[listIndex] as? Babel2FeedViewController else { return nil }
		var place = Babel2LastPlace(scope: list.scope.rawValue, savedAt: now)
		if let smart = list.smartFeed {
			place.smartFeed = smart.rawValue
		} else {
			place.accountID = list.placeFeedID.accountID
			place.feedID = list.placeFeedID.feedID
		}
		let above = viewControllers[(listIndex + 1)...]
		if let reader = above.first(where: { $0 is Babel2ArticleViewController }) as? Babel2ArticleViewController,
		   let id = reader.placeArticleID {
			place.article = ArticleRef(accountID: id.accountID, feedID: id.feedID, articleID: id.articleID)
		}
		return place
	}
}

/// 「上次停在哪」存在手机上（Application Support/Babel2LastPlace.json，只有几个编号和一个时间）。
/// Babel2 目录不用 UserDefaults（边界测试禁止），和位置记忆一样用自己的小文件。
@MainActor
final class Babel2LastPlaceStore {
	static let shared = Babel2LastPlaceStore(fileURL: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
		.appendingPathComponent("Babel2LastPlace.json"))

	private let fileURL: URL

	init(fileURL: URL) {
		self.fileURL = fileURL
	}

	func load() -> Babel2LastPlace? {
		// 仅供自动测试：与清空阅读位置同一个开关（真实数据 UI 测试会带），每次都从首页开始
		if ProcessInfo.processInfo.environment["BABEL2_RESET_READING_POSITIONS"] == "1" {
			try? FileManager.default.removeItem(at: fileURL)
			return nil
		}
		guard let data = try? Data(contentsOf: fileURL) else { return nil }
		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .secondsSince1970
		return try? decoder.decode(Babel2LastPlace.self, from: data)
	}

	/// 立刻写盘（退到后台时调用）；nil = 在首页 / 设置等，下次从首页开始。
	func save(_ place: Babel2LastPlace?) {
		guard let place else {
			try? FileManager.default.removeItem(at: fileURL)
			return
		}
		let encoder = JSONEncoder()
		encoder.dateEncodingStrategy = .secondsSince1970
		guard let data = try? encoder.encode(place) else { return }
		try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
		try? data.write(to: fileURL, options: .atomic)
	}
}

/// 恢复期间盖在最上面的纸色底板：和启动画面同色，恢复好（或放弃）后淡出，
/// 这样打开时看不到「先闪一下首页再跳进去」。
@MainActor
final class Babel2ResumeCover: UIView {
	override init(frame: CGRect) {
		super.init(frame: frame)
		backgroundColor = BabelPalette.background
		autoresizingMask = [.flexibleWidth, .flexibleHeight]
		accessibilityIdentifier = "babel2.resume-cover"
	}

	required init?(coder: NSCoder) { nil }

	func dismiss() {
		guard superview != nil else { return }
		Babel2Motion.animate(Babel2Motion.standard, { self.alpha = 0 }, completion: { _ in self.removeFromSuperview() })
	}
}
