import UIKit

/// 设置页读写的全部东西（Slice 6）。页面只认这个接口，不直接碰账户、钥匙串或旧的设置存储；
/// 正式实现在数据接入层（Babel2LiveSettingsService），测试用假的实现。
@MainActor
protocol Babel2SettingsService: AnyObject {
	// MARK: 文章列表
	/// 未读文章排序：true = 最新优先。
	var sortNewestFirst: Bool { get set }
	/// 全部标为已读前先确认。
	var confirmMarkAllRead: Bool { get set }

	// MARK: 阅读器
	/// 链接在 Babel 内置浏览器打开（false = 系统浏览器）。
	var openLinksInApp: Bool { get set }

	// MARK: 外观与语言
	var appearance: Babel2AppearanceMode { get set }
	var accentOptions: [Babel2AccentOption] { get }
	var accentID: String { get set }
	var languageOptions: [Babel2LanguageOption] { get }
	/// nil = 跟随系统。
	var languageCode: String? { get set }

	// MARK: 账户与同步
	var accounts: [Babel2AccountSummary] { get }
	var syncUnreadArticleContent: Bool { get set }
	func deleteAccount(_ id: String)
	var addableAccountKinds: [Babel2AddAccountKind] { get }
	/// 弹出该类账户的登录 / 创建页面（现成页面）；成功后回调。
	func presentAddAccount(_ kind: Babel2AddAccountKind, from host: UIViewController, completion: @escaping () -> Void)

	// MARK: 订阅
	/// 导入 / 导出 OPML（有多个账户时由调用方先选好账户）。
	func importOPML(into accountID: String, from host: UIViewController)
	func exportOPML(from accountID: String, host: UIViewController)

	// MARK: 发现服务
	var redditClientID: String? { get }
	var redditClientSecret: String? { get }
	var youTubeAPIKey: String? { get }
	func saveDiscoveryKeys(redditClientID: String, redditClientSecret: String, youTubeAPIKey: String)

	// MARK: 翻译
	var translationModelID: String { get set }
	func translationModelDisplayName(_ id: String) -> String
	var translationAPIKey: String? { get }
	var translationBaseURL: String { get }
	var translationDefaultBaseURL: String { get }
	func saveTranslationAPI(apiKey: String, baseURL: String)
	/// 用填写中的值测一次（不保存）。成功返回模型的回复。
	func testTranslationConnection(apiKey: String, baseURL: String) async -> Babel2ConnectionTestResult
	/// 已缓存的模型目录（立即可用）。
	func cachedTranslationModels() -> [Babel2TranslationModel]
	/// 联网刷新模型目录。
	func refreshTranslationModels() async throws -> [Babel2TranslationModel]
	func vendorLogo(_ vendor: String, traits: UITraitCollection) -> UIImage?
	func vendorDisplayName(_ vendor: String) -> String

	// MARK: 通知 / 支持与诊断
	func openSystemNotificationSettings()
	var hasICloudAccount: Bool { get }
	/// 以底部卡片弹出的现成页面（已包好导航栏与关闭按钮）。
	func makeDiagnosticsPage(_ kind: Babel2DiagnosticsKind) -> UIViewController?
	func openHelp(_ kind: Babel2HelpKind)
	func makeAboutPage() -> UIViewController
}

enum Babel2AppearanceMode: Int, CaseIterable {
	case automatic
	case light
	case dark

	var interfaceStyle: UIUserInterfaceStyle {
		switch self {
		case .automatic: return .unspecified
		case .light: return .light
		case .dark: return .dark
		}
	}
}

struct Babel2AccentOption: Equatable {
	let id: String
	let name: String
	let color: UIColor
}

struct Babel2LanguageOption: Equatable {
	/// nil = 跟随系统。
	let code: String?
	let name: String
}

struct Babel2AccountSummary: Equatable {
	enum Kind: Equatable {
		case local
		case iCloud
		case web
		case selfHosted
	}

	let id: String
	let name: String
	let kind: Kind
	/// 默认的本地账户不能删除（与现有账户详情页同一规则）。
	let isDefault: Bool
}

enum Babel2AddAccountKind: String, CaseIterable {
	case local
	case iCloud
	case bazQux
	case feedbin
	case feedly
	case inoreader
	case newsBlur
	case theOldReader
	case freshRSS
}

enum Babel2DiagnosticsKind: CaseIterable {
	case errorLog
	case activityLog
	case accountStats
	case dinosaurs
	case iCloudStats
}

enum Babel2HelpKind: CaseIterable {
	case help
	case forum
	case releaseNotes
	case bugTracker
}

enum Babel2ConnectionTestResult: Equatable {
	case success(reply: String)
	case failure(message: String)
}

struct Babel2TranslationModel: Equatable {
	let id: String
	let name: String
	let vendor: String
	/// 热度（OpenRouter 排行分数，0 = 没有排行数据）。
	let popularity: Double
	let created: Double
}

/// 翻译模型页的排行规则（SETTINGS-IA-SPEC / 产品合同：热门前 10 + 每个服务商恰好 3 个，刷新在最上方）。纯计算，可直接测试。
enum Babel2TranslationModelRanking {
	static let topCount = 10
	static let perVendorCount = 3
	static let vendorCount = 10

	struct VendorGroup: Equatable {
		let vendor: String
		let models: [Babel2TranslationModel]
	}

	/// 热门前 10：按热度从高到低；只看有热度数据的模型。
	static func top(_ models: [Babel2TranslationModel]) -> [Babel2TranslationModel] {
		Array(models.filter { $0.popularity > 0 }.sorted(by: morePopular).prefix(topCount))
	}

	/// 按服务商分组：每组恰好 3 个最热门的模型（不足 3 个的服务商不列出），
	/// 组按组内最高热度排序，最多 10 组。
	static func vendorGroups(_ models: [Babel2TranslationModel]) -> [VendorGroup] {
		let byVendor = Dictionary(grouping: models, by: \.vendor)
		let groups = byVendor.compactMap { vendor, list -> VendorGroup? in
			let picked = Array(list.sorted(by: morePopular).prefix(perVendorCount))
			guard picked.count == perVendorCount else { return nil }
			return VendorGroup(vendor: vendor, models: picked)
		}
		return Array(groups.sorted { lhs, rhs in
			let left = lhs.models.first?.popularity ?? 0
			let right = rhs.models.first?.popularity ?? 0
			return left != right ? left > right : lhs.vendor < rhs.vendor
		}.prefix(vendorCount))
	}

	/// 热度高的在前；一样时新的在前，再按编号保证顺序稳定。
	private static func morePopular(_ lhs: Babel2TranslationModel, _ rhs: Babel2TranslationModel) -> Bool {
		if lhs.popularity != rhs.popularity { return lhs.popularity > rhs.popularity }
		if lhs.created != rhs.created { return lhs.created > rhs.created }
		return lhs.id < rhs.id
	}
}
