//
//  NNWForeignFeedStore.swift
//  NetNewsWire — AI 翻译 fork
//
//  [外文] 本 fork 新增,上游没有这个文件。用户 2026-08-08 第 5 件的地基:
//  **哪些订阅源是"外文源"**。
//
//  ## 判定分两层,手动的永远压过自动的
//
//  1. **自动**:抓这个源最近若干篇标题,认一次语言,结果缓存起来(30 天后重认一次)。
//  2. **手动**:源设置页里有一个开关。用户一拨,就为这个源记一条**明确的**决定,
//     从此不再听自动判定的(自动判定仍会继续更新缓存,只是不作数)。
//
//  之所以必须有手动这一层:语言识别对**短标题**天生不可靠,而 RSS 标题正好都很短。
//  与其把算法调到玄学,不如给一个一秒钟就能纠正的开关(这也是用户当初的要求)。
//
//  ## 判定规则(是启发式,不是真理 —— 所以才有上面那个开关)
//
//  | 认出来是 | 算不算外文 |
//  |---|---|
//  | 简体 / 繁体中文 | ❌ 不算 |
//  | 日文 / 韩文 | ✅ 算(对中文读者就是外文) |
//  | 其它语言 | ✅ 算,**但**汉字占比超过 30% 时不算 —— 那多半是中文源里混了几条英文标题把识别带偏了 |
//  | 认不出来(文字太少) | 不下结论,也**不写缓存**,下次再试 |
//
//  ⚠️ 没有碰 `Shared/SmartFeeds/`(A 级禁区),也没有碰 Account —— 判定结果全部
//  存在我们自己的 UserDefaults 里,键 = "账户ID|源ID"(带账户前缀,理由见 NNWTitleTranslationStore)。
//

#if os(iOS)

import Foundation
import NaturalLanguage
import Account
import Articles

@MainActor final class NNWForeignFeedStore {

	static let shared = NNWForeignFeedStore()

	/// 判定结果变了(自动认出来一批 / 用户拨了开关)。列表和智能源靠它刷新。
	static let didChangeNotification = Notification.Name("NNWForeignFeedStoreDidChange")

	private static let overridesKey = "nnwForeignFeedOverrides"		// 手动开关:键 → true/false
	private static let detectionKey = "nnwForeignFeedDetection"		// 自动判定:键 → [是否外文(0/1), 时间戳]
	/// 自动判定的保质期。源换语言是极小概率事件,但订阅换主人这种事真的会发生。
	private static let detectionLifetime: TimeInterval = 30 * 24 * 60 * 60
	/// 认语言时最多看多少篇标题 —— 再多也不会更准,只是更慢。
	private static let sampleTitleCount = 15

	private var overrides: [String: Bool]
	private var detection: [String: [Double]]

	private init() {
		overrides = UserDefaults.standard.dictionary(forKey: Self.overridesKey) as? [String: Bool] ?? [:]
		detection = UserDefaults.standard.dictionary(forKey: Self.detectionKey) as? [String: [Double]] ?? [:]
	}

	// MARK: - 键

	static func key(accountID: String, feedID: String) -> String {
		"\(accountID)|\(feedID)"
	}

	static func key(for feed: Feed) -> String? {
		guard let accountID = feed.account?.accountID else { return nil }
		return key(accountID: accountID, feedID: feed.feedID)
	}

	// MARK: - 查

	/// 这个源现在算不算外文源。手动开关优先,其次是自动判定,都没有就当**不是**。
	func isForeign(_ feed: Feed) -> Bool {
		guard let key = Self.key(for: feed) else { return false }
		if let manual = overrides[key] { return manual }
		return detection[key]?.first == 1
	}

	/// 这个源的判定是**用户手动定的**吗(界面上要区分"自动认出来的"和"你自己定的")。
	func hasManualOverride(_ feed: Feed) -> Bool {
		guard let key = Self.key(for: feed) else { return false }
		return overrides[key] != nil
	}

	/// 当前所有被认定为外文的源(跨账户)。
	func foreignFeeds() -> [Feed] {
		AccountManager.shared.activeAccounts
			.flatMap { $0.flattenedFeeds() }
			.filter { isForeign($0) }
	}

	/// 一个账户里被认定为外文的源。
	func foreignFeeds(in account: Account) -> [Feed] {
		account.flattenedFeeds().filter { isForeign($0) }
	}

	// MARK: - 写

	/// 用户拨了源设置里的开关。
	func setManualOverride(_ isForeign: Bool, for feed: Feed) {
		guard let key = Self.key(for: feed) else { return }
		overrides[key] = isForeign
		UserDefaults.standard.set(overrides, forKey: Self.overridesKey)
		NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
	}

	/// 自动判定的结果入库。
	private func setDetection(_ isForeign: Bool, for key: String) {
		detection[key] = [isForeign ? 1 : 0, Date().timeIntervalSince1970]
		UserDefaults.standard.set(detection, forKey: Self.detectionKey)
	}

	private func needsDetection(_ key: String) -> Bool {
		guard let entry = detection[key], entry.count == 2 else { return true }
		return Date().timeIntervalSince1970 - entry[1] > Self.detectionLifetime
	}

	// MARK: - 自动判定

	private var isDetecting = false

	/// 把还没认过(或缓存过期)的源认一遍。**一次只认一个,串行 await** ——
	/// 每个源都要查一次库,并发起来会在冷启动时和界面抢数据库。
	///
	/// 幂等:正在跑的时候再调是空操作(L113:给函数加触发点之前先确认它幂等)。
	func refreshDetectionIfNeeded() {

		guard !isDetecting else { return }
		let pending = AccountManager.shared.activeAccounts
			.flatMap { $0.flattenedFeeds() }
			.filter { feed in
				guard let key = Self.key(for: feed) else { return false }
				return needsDetection(key)
			}
		guard !pending.isEmpty else { return }

		isDetecting = true
		Task { @MainActor in
			defer { isDetecting = false }
			var changed = false
			for feed in pending {
				guard let key = Self.key(for: feed) else { continue }
				let articles = await feed.fetchArticlesAsync()
				let titles = Self.sampleTitles(from: articles)
				guard let verdict = Self.detectIsForeign(titles: titles) else { continue }
				setDetection(verdict, for: key)
				changed = changed || verdict
			}
			if changed {
				NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
			}
		}
	}

	/// 取最近的若干篇标题当样本。取"最近"而不是随便取,是因为源的语言若真的变了,
	/// 新文章才代表现在。
	private static func sampleTitles(from articles: Set<Article>) -> [String] {
		articles
			.sorted { (a: Article, b: Article) -> Bool in
				let left = a.datePublished ?? a.status.dateArrived
				let right = b.datePublished ?? b.status.dateArrived
				return left > right
			}
			.prefix(sampleTitleCount)
			.compactMap { $0.title }
			.filter { !$0.isEmpty }
	}

	// MARK: - 认语言(纯函数,好单独验)

	/// 返回 nil = 认不出来(样本太少),调用方**不要**把它当成"不是外文"存起来。
	static func detectIsForeign(titles: [String]) -> Bool? {

		let text = titles.joined(separator: "\n")
		// 太少的字认不准。20 个字符是实测下来 NLLanguageRecognizer 开始稳定的下限。
		guard text.count >= 20 else { return nil }

		let recognizer = NLLanguageRecognizer()
		recognizer.processString(text)
		guard let dominant = recognizer.dominantLanguage else { return nil }

		switch dominant {
		case .simplifiedChinese, .traditionalChinese:
			return false
		case .japanese, .korean:
			return true
		default:
			// 汉字占比很高却没被认成中文 —— 多半是几条英文标题把识别带偏了,按中文算。
			return hanRatio(of: text) < 0.3
		}
	}

	/// 汉字(CJK 统一表意文字)占**全部字母类字符**的比例。
	/// 只数字母,标点、数字、空白一律不算 —— 否则一条带长网址的标题就能把比例冲掉。
	private static func hanRatio(of text: String) -> Double {
		var letters = 0
		var han = 0
		for scalar in text.unicodeScalars {
			guard CharacterSet.letters.contains(scalar) else { continue }
			letters += 1
			if (0x4E00...0x9FFF).contains(scalar.value) || (0x3400...0x4DBF).contains(scalar.value) {
				han += 1
			}
		}
		guard letters > 0 else { return 0 }
		return Double(han) / Double(letters)
	}
}

#endif
