import UIKit
import Babel2Core

/// 阅读位置记忆（2026-09-27 用户反馈，ADR-053）：文章列表滑到哪、文章里读到哪，下次打开回到原处；关掉 App 重开也记得。
///
/// - 文章列表：记「可视区最上面那一篇」和它的顶边离可视区顶边多远，不记像素位置——
///   列表会变（新文章插在上面、未读档里读过的被收起），按文章找回才对得上；
///   另记离开时列表里最新一篇的时间（每一档各记各的），回来时据此数出「这之后来的新文章」。
///   订阅源的未读 / 全部 / 星标三档共用一个位置（用户选定）；「今日未读」「全部未读」
///   （全部档的「今天」「全部文章」）也共用一个（用户要求：在一个里看过的位置，到另一个里接着看）。
///   离开时停在最上面（没往下滑过）就不算「看到哪」，下次也从最上面开始；
///   「新文章」只跟同一档上次记下的比（星标档里最新的一篇往往很旧，拿去跟全部档比，会把没加星标的旧文章都算成新的），
///   这一档还没记过就不提示。
/// - 文章里：记读到正文第几段、在那一段里往下多少（按段落比例），再记整体进度做后备——
///   原文和译文段落一一对应，切换后仍对得上。
///
/// 存在 app 自己的资料夹（Application Support/Babel2ReadingPositions.json），只有编号和几个数字，
/// 列表最多记 300 个、文章最多 1000 篇，超过了丢最久没动的。写盘攒 1 秒一次，进后台时立刻写。
@MainActor
final class Babel2PositionStore {
	static let shared = Babel2PositionStore(fileURL: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
		.appendingPathComponent("Babel2ReadingPositions.json"))

	struct ListPosition: Codable, Equatable {
		var accountID: String
		var feedID: String
		var articleID: String
		var publishedAt: Date?
		/// 那一篇的顶边在可视区顶边下方多少点（负数 = 顶边已经滚到可视区上面去了）
		var offset: Double
		var savedAt: Date
		/// 离开时停在最上面（没往下滑过）：下次也从最上面开始，不去对「同一篇的同一位置」
		var atTop: Bool? = nil
		/// 每一档（未读 / 全部 / 星标）上次离开时，那一档列表里最新一篇的时间：回来时比它新的就是「新文章」。
		/// 分档记，换一档离开时不把别的档记下的冲掉
		var seenByScope: [String: Date]? = nil

		var articleSnapshotID: ArticleSnapshot.ID {
			ArticleSnapshot.ID(accountID: accountID, feedID: feedID, articleID: articleID)
		}
	}

	struct ArticlePosition: Codable, Equatable {
		/// 正文第几段（正文容器的第几个子元素）
		var block: Int
		/// 当时正文一共几段：回来时段数对不上（例如译文多出一段），就改用整体进度
		var blockCount: Int
		/// 在那一段里往下多少（0 = 段首，1 = 段尾）
		var fraction: Double
		/// 整体进度（0…1）：段落数对不上时的后备
		var progress: Double
		var savedAt: Date
	}

	static let maxLists = 300
	static let maxArticles = 1000

	private struct Payload: Codable {
		var lists = [String: ListPosition]()
		var articles = [String: ArticlePosition]()
	}

	private let fileURL: URL
	private var payload = Payload()
	private var isLoaded = false
	private var isSaveScheduled = false
	private var backgroundObserver: NSObjectProtocol?

	init(fileURL: URL) {
		self.fileURL = fileURL
	}

	// MARK: 键

	/// 订阅源的文章列表：三档共用。
	static func listKey(feed id: FeedSnapshot.ID) -> String {
		"feed:\(id.accountID)|\(id.feedID)"
	}

	/// 跨源列表：今天 / 全部（未读档叫今日未读 / 全部未读）共用一个位置；外文源、全部星标各一个。
	static func listKey(smart kind: Babel2SmartFeed) -> String {
		switch kind {
		case .today, .all: return "smart:timeline"
		case .foreign: return "smart:foreign"
		case .starred: return "smart:starred"
		}
	}

	private static func articleKey(_ id: ArticleSnapshot.ID) -> String {
		"\(id.accountID)|\(id.feedID)|\(id.articleID)"
	}

	// MARK: 读写

	func listPosition(for key: String) -> ListPosition? {
		loadIfNeeded()
		return payload.lists[key]
	}

	func setListPosition(_ position: ListPosition?, for key: String) {
		loadIfNeeded()
		guard payload.lists[key] != position else { return }
		payload.lists[key] = position
		trim(&payload.lists, limit: Self.maxLists) { $0.savedAt }
		scheduleSave()
	}

	func articlePosition(for id: ArticleSnapshot.ID) -> ArticlePosition? {
		loadIfNeeded()
		return payload.articles[Self.articleKey(id)]
	}

	func setArticlePosition(_ position: ArticlePosition?, for id: ArticleSnapshot.ID) {
		loadIfNeeded()
		let key = Self.articleKey(id)
		guard payload.articles[key] != position else { return }
		payload.articles[key] = position
		trim(&payload.articles, limit: Self.maxArticles) { $0.savedAt }
		scheduleSave()
	}

	/// 超过上限：丢掉最久没动的。
	private func trim<Value>(_ dictionary: inout [String: Value], limit: Int, date: (Value) -> Date) {
		guard dictionary.count > limit else { return }
		let oldest = dictionary.sorted { date($0.value) < date($1.value) }.prefix(dictionary.count - limit)
		for (key, _) in oldest { dictionary[key] = nil }
	}

	// MARK: 存在手机上

	private func loadIfNeeded() {
		guard !isLoaded else { return }
		isLoaded = true
		installBackgroundObserverIfNeeded()
		// 仅供自动测试与取证：启动时带环境变量 BABEL2_RESET_READING_POSITIONS=1（真实数据 UI 自动测试会带；
		// 用 simctl 启动时写成 SIMCTL_CHILD_BABEL2_RESET_READING_POSITIONS=1）就先清空记住的位置——
		// 位置会跨启动保存，手动滑过之后再跑测试，列表会停在上次的地方，「打开就在最上面」的前提就不成立了。
		if ProcessInfo.processInfo.environment["BABEL2_RESET_READING_POSITIONS"] == "1" {
			try? FileManager.default.removeItem(at: fileURL)
			return
		}
		guard let data = try? Data(contentsOf: fileURL) else { return }
		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .secondsSince1970
		if let stored = try? decoder.decode(Payload.self, from: data) {
			payload = stored
		}
	}

	private func scheduleSave() {
		guard !isSaveScheduled else { return }
		isSaveScheduled = true
		Task { @MainActor [weak self] in
			try? await Task.sleep(for: .seconds(1))
			self?.saveNow()
		}
	}

	/// 立刻写盘（进后台时、测试里用）。
	func saveNow() {
		isSaveScheduled = false
		let encoder = JSONEncoder()
		encoder.dateEncodingStrategy = .secondsSince1970
		guard let data = try? encoder.encode(payload) else { return }
		let url = fileURL
		try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
		try? data.write(to: url, options: .atomic)
	}

	private func installBackgroundObserverIfNeeded() {
		guard backgroundObserver == nil else { return }
		backgroundObserver = NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
			MainActor.assumeIsolated {
				guard let self, self.isSaveScheduled else { return }
				self.saveNow()
			}
		}
	}
}

/// 「↑ N 篇新文章」（ADR-053）：文章列表停在中间、而列表里有新来的文章时，浮在底栏上方一点点；点一下滚到新文章那里。
/// 外观与阅读页的小提示同款（墨色胶囊、纸色字）；出现时上浮 8pt 淡入，收起时淡出（ADR-034）。
@MainActor
final class Babel2NewArticlesPill: UIControl {
	private let arrow = UIImageView(image: Babel2Icon.arrowUp.image(size: 15))
	private let label = UILabel()
	private(set) var count = 0

	override init(frame: CGRect) {
		super.init(frame: frame)
		backgroundColor = BabelPalette.ink
		layer.cornerRadius = 17
		layer.cornerCurve = .continuous
		isAccessibilityElement = true
		accessibilityTraits = .button
		accessibilityIdentifier = "babel2.feed.new-articles"
		accessibilityHint = Babel2Localization.text(.backToTop)
		arrow.tintColor = BabelPalette.background
		label.font = .systemFont(ofSize: 13, weight: .semibold)
		label.textColor = BabelPalette.background
		let stack = UIStackView(arrangedSubviews: [arrow, label])
		stack.spacing = 6
		stack.alignment = .center
		stack.isUserInteractionEnabled = false
		stack.translatesAutoresizingMaskIntoConstraints = false
		addSubview(stack)
		NSLayoutConstraint.activate([
			heightAnchor.constraint(equalToConstant: 34),
			stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
			stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
			stack.centerYAnchor.constraint(equalTo: centerYAnchor)
		])
		isHidden = true
		Babel2Motion.addPressFeedback(to: self)
	}

	required init?(coder: NSCoder) { nil }

	var isShowing: Bool { !isHidden }

	func show(count newCount: Int) {
		count = newCount
		label.text = String(format: Babel2Localization.text(newCount == 1 ? .newArticlesOne : .newArticles), newCount)
		accessibilityLabel = label.text
		guard isHidden else { return }
		isHidden = false
		alpha = 0
		transform = CGAffineTransform(translationX: 0, y: Babel2Motion.offset(8))
		Babel2Motion.animate(Babel2Motion.standard) {
			self.alpha = 1
			self.transform = .identity
		}
	}

	func hide(animated: Bool = true) {
		guard !isHidden else { return }
		guard animated, window != nil else {
			isHidden = true
			return
		}
		Babel2Motion.animate(Babel2Motion.standard, { self.alpha = 0 }, completion: { _ in
			if self.alpha == 0 { self.isHidden = true }
		})
	}
}
