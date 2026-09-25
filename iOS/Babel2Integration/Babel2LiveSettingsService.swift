import Foundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import Account
import RSCore

/// 设置页的正式实现（Slice 6）：把 Babel 2.0 设置页接到现有的存储与页面上。
/// - 旧设置存储（排序 / 已读确认 / 打开链接 / 配色模式）只经 Babel2LiveAppDefaults（边界测试唯一放行点）
/// - 账户只经 Babel2LiveDataAdapters 同一个账户单例入口
/// - 翻译、发现服务、强调色、界面语言用各自现成的存储
/// - 新增账户、日志、统计、关于用现成页面（只调用，不改）
@MainActor
final class Babel2LiveSettingsService: Babel2SettingsService {

	// MARK: 文章列表 / 阅读器

	var sortNewestFirst: Bool {
		get { Babel2LiveAppDefaults.sortNewestFirst }
		set {
			Babel2LiveAppDefaults.sortNewestFirst = newValue
			// 列表与首页按新顺序刷新
			NotificationCenter.default.post(name: .babel2LibraryDidChange, object: nil)
		}
	}

	var confirmMarkAllRead: Bool {
		get { Babel2LiveAppDefaults.confirmMarkAllRead }
		set { Babel2LiveAppDefaults.confirmMarkAllRead = newValue }
	}

	var openLinksInApp: Bool {
		get { Babel2LiveAppDefaults.openLinksInApp }
		set { Babel2LiveAppDefaults.openLinksInApp = newValue }
	}

	// MARK: 外观与语言

	var appearance: Babel2AppearanceMode {
		get { Babel2AppearanceMode(rawValue: Babel2LiveAppDefaults.colorPaletteRawValue) ?? .automatic }
		set {
			Babel2LiveAppDefaults.colorPaletteRawValue = newValue.rawValue
			NotificationCenter.default.post(name: .babel2AppearanceDidChange, object: nil)
		}
	}

	var accentOptions: [Babel2AccentOption] {
		NNWAccentPalette.Choice.allCases.map { choice in
			Babel2AccentOption(id: choice.rawValue, name: Self.accentName(choice), color: NNWAccentPalette.color(for: choice))
		}
	}

	private static func accentName(_ choice: NNWAccentPalette.Choice) -> String {
		switch choice {
		case .orange: return Babel2SettingsText.t("Orange")
		case .terracotta: return Babel2SettingsText.t("Terracotta")
		case .indigo: return Babel2SettingsText.t("Indigo")
		case .forest: return Babel2SettingsText.t("Forest")
		case .plum: return Babel2SettingsText.t("Plum")
		case .graphite: return Babel2SettingsText.t("Graphite")
		}
	}

	var accentID: String {
		get { NNWAccentPalette.choice.rawValue }
		set {
			guard let choice = NNWAccentPalette.Choice(rawValue: newValue) else { return }
			NNWAccentPalette.setChoice(choice)
		}
	}

	var languageOptions: [Babel2LanguageOption] {
		AppLanguageController.availableOptions.map { option in
			guard let code = option.code else {
				let system = AppLanguageController.displayName(for: Locale.preferredLanguages.first ?? "en")
				return Babel2LanguageOption(code: nil, name: Babel2SettingsText.f("Follow System (%@)", system))
			}
			return Babel2LanguageOption(code: code, name: option.displayName)
		}
	}

	var languageCode: String? {
		get { AppLanguageController.selectedLanguage }
		set { AppLanguageController.selectedLanguage = newValue }
	}

	// MARK: 账户与同步

	var accounts: [Babel2AccountSummary] {
		Babel2LiveAccounts.summaries()
	}

	var syncUnreadArticleContent: Bool {
		get { Babel2LiveAccounts.syncUnreadArticleContent }
		set { Babel2LiveAccounts.syncUnreadArticleContent = newValue }
	}

	func deleteAccount(_ id: String) {
		Babel2LiveAccounts.delete(id)
	}

	var addableAccountKinds: [Babel2AddAccountKind] {
		Babel2LiveAccounts.addableKinds(isDeveloperBuild: Babel2LiveAppDefaults.isDeveloperBuild)
	}

	func presentAddAccount(_ kind: Babel2AddAccountKind, from host: UIViewController, completion: @escaping () -> Void) {
		Babel2AddAccountHost.present(kind, from: host, completion: completion)
	}

	// MARK: 订阅

	func importOPML(into accountID: String, from host: UIViewController) {
		Babel2OPMLImportHost.present(accountID: accountID, from: host)
	}

	func exportOPML(from accountID: String, host: UIViewController) {
		guard let (name, opml) = Babel2LiveAccounts.exportOPML(accountID) else { return }
		let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).opml")
		do {
			try opml.write(to: fileURL, atomically: true, encoding: .utf8)
			host.present(UIDocumentPickerViewController(forExporting: [fileURL]), animated: true)
		} catch {
			Self.presentError(error.localizedDescription, from: host)
		}
	}

	// MARK: 发现服务

	var redditClientID: String? { FeedDiscoveryKeychain.redditClientID }
	var redditClientSecret: String? { FeedDiscoveryKeychain.redditClientSecret }
	var youTubeAPIKey: String? { FeedDiscoveryKeychain.youTubeAPIKey }

	func saveDiscoveryKeys(redditClientID: String, redditClientSecret: String, youTubeAPIKey: String) {
		FeedDiscoveryKeychain.redditClientID = redditClientID.isEmpty ? nil : redditClientID
		FeedDiscoveryKeychain.redditClientSecret = redditClientSecret.isEmpty ? nil : redditClientSecret
		FeedDiscoveryKeychain.youTubeAPIKey = youTubeAPIKey.isEmpty ? nil : youTubeAPIKey
	}

	// MARK: 翻译

	var translationModelID: String {
		get { TranslationConfigStore.selectedModel }
		set { TranslationConfigStore.selectedModel = newValue }
	}

	/// 模型显示名：目录里有就用目录的名字（去掉「厂商: 」前缀），否则用编号简写。
	func translationModelDisplayName(_ id: String) -> String {
		if let model = OpenRouterCatalog.cached().first(where: { $0.id == id }) {
			return Self.shortName(model.name)
		}
		return TranslationConfigStore.displayName(for: id)
	}

	private static func shortName(_ name: String) -> String {
		guard let colon = name.range(of: ": ") else { return name }
		return String(name[colon.upperBound...])
	}

	var translationAPIKey: String? { TranslationConfigStore.apiKey }
	var translationBaseURL: String { TranslationConfigStore.baseURL }
	var translationDefaultBaseURL: String { TranslationConfigStore.defaultBaseURL }

	func saveTranslationAPI(apiKey: String, baseURL: String) {
		TranslationConfigStore.apiKey = apiKey.isEmpty ? nil : apiKey
		TranslationConfigStore.baseURL = baseURL
	}

	func testTranslationConnection(apiKey: String, baseURL: String) async -> Babel2ConnectionTestResult {
		let config = TranslationConfig(baseURL: baseURL.isEmpty ? TranslationConfigStore.defaultBaseURL : baseURL, apiKey: apiKey)
		guard config.chatCompletionsURL != nil else {
			return .failure(message: Babel2SettingsText.f("The service URL isn't a valid web address: %@", baseURL))
		}
		let model = TranslationConfigStore.selectedModel
		do {
			let reply = try await OpenAICompatibleTranslator.testConnection(config: config, model: model)
			return .success(reply: Babel2SettingsText.f("Model %@ replied:", translationModelDisplayName(model)) + "\n\n" + reply)
		} catch {
			let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
			return .failure(message: [message, Self.hint(for: error)].compactMap { $0 }.joined(separator: "\n\n"))
		}
	}

	/// 常见错误的下一步提示（与现有翻译 API 页同一套判断）。
	private static func hint(for error: Error) -> String? {
		guard let translationError = error as? TranslationError else { return nil }
		switch translationError {
		case .serverError(let status, _):
			switch status {
			case 401, 403: return Babel2SettingsText.t("The API key is probably wrong or expired. Check that it was copied completely.")
			case 402: return Babel2SettingsText.t("The account balance is probably too low.")
			case 404: return Babel2SettingsText.t("The service URL is probably wrong, or this model isn't available there.")
			case 429: return Babel2SettingsText.t("Rate limited. Try again in a moment.")
			default: return nil
			}
		case .networkFailure:
			return Babel2SettingsText.t("Check your network connection and the service URL.")
		case .invalidResponse:
			return Babel2SettingsText.t("The server responded in an unexpected format. The URL may not be an OpenAI-compatible API.")
		default:
			return nil
		}
	}

	func cachedTranslationModels() -> [Babel2TranslationModel] {
		Self.convert(OpenRouterCatalog.cached())
	}

	func refreshTranslationModels() async throws -> [Babel2TranslationModel] {
		let models = try await OpenRouterCatalog.fetchAll(baseURL: TranslationConfigStore.baseURL)
		return Self.convert(models)
	}

	/// 只列适合挑选的模型：去掉「始终最新」别名、免费变体和不适合翻译的（与现有模型页同一筛选）。
	private static func convert(_ models: [OpenRouterCatalogModel]) -> [Babel2TranslationModel] {
		models
			.filter { $0.isBrowseWorthy && !$0.isLatestAlias && !$0.isFreeVariant }
			.map { Babel2TranslationModel(id: $0.id, name: shortName($0.name), vendor: $0.vendor, popularity: $0.popularity, created: $0.created) }
	}

	func vendorLogo(_ vendor: String, traits: UITraitCollection) -> UIImage? {
		OpenRouterVendorStyle.icon(for: vendor, traits: traits)
	}

	func vendorDisplayName(_ vendor: String) -> String {
		OpenRouterVendorStyle.displayName(for: vendor)
	}

	// MARK: 通知 / 支持与诊断

	func openSystemNotificationSettings() {
		guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else { return }
		UIApplication.shared.open(url)
	}

	var hasICloudAccount: Bool { Babel2LiveAccounts.hasICloudAccount }

	func makeDiagnosticsPage(_ kind: Babel2DiagnosticsKind) -> UIViewController? {
		let root: UIViewController
		switch kind {
		case .errorLog: root = UIHostingController(rootView: ErrorLogView())
		case .activityLog: root = UIHostingController(rootView: ActivityLogView())
		case .accountStats: root = UIHostingController(rootView: AccountStatsView())
		case .dinosaurs: root = UIHostingController(rootView: DinosaursView(dismissAndPresent: { _ in }))
		case .iCloudStats: root = UIHostingController(rootView: CloudKitStatsView())
		}
		return Self.sheet(root)
	}

	func openHelp(_ kind: Babel2HelpKind) {
		let url: HelpURL
		switch kind {
		case .help: url = .helpHome
		case .forum: url = .discourse
		case .releaseNotes: url = .releaseNotes
		case .bugTracker: url = .bugTracker
		}
		guard let target = URL(string: url.rawValue) else { return }
		UIApplication.shared.open(target)
	}

	func makeAboutPage() -> UIViewController {
		Self.sheet(UIHostingController(rootView: AboutView()))
	}

	/// 包成底部卡片：系统导航栏（保留页面自带的右上角按钮）+ 左上角关闭。
	private static func sheet(_ root: UIViewController) -> UIViewController {
		let navigation = UINavigationController(rootViewController: root)
		root.navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak navigation] _ in
			navigation?.dismiss(animated: true)
		})
		navigation.modalPresentationStyle = .pageSheet
		return navigation
	}

	static func presentError(_ message: String, from host: UIViewController) {
		let alert = UIAlertController(title: Babel2SettingsText.t("Couldn't Complete the Action"), message: message, preferredStyle: .alert)
		alert.addAction(UIAlertAction(title: Babel2SettingsText.t("OK"), style: .default))
		host.present(alert, animated: true)
	}
}

extension Notification.Name {
	/// 设置里改了配色模式：界面按新模式重画。
	static let babel2AppearanceDidChange = Notification.Name("Babel2AppearanceDidChange")
}

// MARK: - 新增账户

/// 现成的账户登录 / 创建页要求「弹出它的页面」遵守 AddAccountDismissDelegate 并在成功后被通知。
/// 用一个不可见的子页面作宿主：它负责弹出、接收完成通知，完成后移除自己并回调。
private final class Babel2AddAccountHost: UIViewController, AddAccountDismissDelegate, OAuthAccountAuthorizationOperationDelegate {
	private var completion: (() -> Void)?

	static func present(_ kind: Babel2AddAccountKind, from parent: UIViewController, completion: @escaping () -> Void) {
		let host = Babel2AddAccountHost()
		host.completion = completion
		parent.addChild(host)
		host.view.isHidden = true
		host.view.frame = .zero
		parent.view.addSubview(host.view)
		host.didMove(toParent: parent)
		host.start(kind)
	}

	private func start(_ kind: Babel2AddAccountKind) {
		switch kind {
		case .local:
			presentStoryboard("LocalAccountNavigationViewController") { ($0 as? LocalAccountViewController)?.delegate = self }
		case .iCloud:
			presentStoryboard("CloudKitAccountNavigationViewController") { ($0 as? CloudKitAccountViewController)?.delegate = self }
		case .feedbin:
			presentStoryboard("FeedbinAccountNavigationViewController") { ($0 as? FeedbinAccountViewController)?.delegate = self }
		case .newsBlur:
			presentStoryboard("NewsBlurAccountNavigationViewController") { ($0 as? NewsBlurAccountViewController)?.delegate = self }
		case .bazQux, .inoreader, .freshRSS, .theOldReader:
			let type: AccountType
			switch kind {
			case .bazQux: type = .bazQux
			case .inoreader: type = .inoreader
			case .freshRSS: type = .freshRSS
			default: type = .theOldReader
			}
			presentStoryboard("ReaderAPIAccountNavigationViewController") { controller in
				guard let readerAPI = controller as? ReaderAPIAccountViewController else { return }
				readerAPI.accountType = type
				readerAPI.delegate = self
			}
		case .feedly:
			guard let window = parent?.view.window else { return }
			let operation = OAuthAccountAuthorizationOperation(accountType: .feedly)
			operation.delegate = self
			operation.presentationAnchor = window
			MainThreadOperationQueue.shared.add(operation)
		}
	}

	private func presentStoryboard(_ identifier: String, configure: (UIViewController?) -> Void) {
		guard let navigation = UIStoryboard.account.instantiateViewController(withIdentifier: identifier) as? UINavigationController else { return }
		configure(navigation.topViewController)
		navigation.modalPresentationStyle = .formSheet
		parent?.present(navigation, animated: true)
	}

	/// 登录 / 创建成功（现成页面已自己关闭）。
	func dismiss() {
		finish(success: true)
	}

	func oauthAccountAuthorizationOperation(_ operation: OAuthAccountAuthorizationOperation, didCreate account: Account) {
		account.triggerRefreshAll()
		finish(success: true)
	}

	func oauthAccountAuthorizationOperation(_ operation: OAuthAccountAuthorizationOperation, didFailWith error: Error) {
		if let parent { Babel2LiveSettingsService.presentError(error.localizedDescription, from: parent) }
		finish(success: false)
	}

	private func finish(success: Bool) {
		let callback = success ? completion : nil
		completion = nil
		willMove(toParent: nil)
		view.removeFromSuperview()
		removeFromParent()
		callback?()
	}
}

// MARK: - 导入 OPML

/// 文件选择器的结果要有人接：同样用不可见的子页面作宿主。
private final class Babel2OPMLImportHost: UIViewController, UIDocumentPickerDelegate {
	private var accountID = ""

	static func present(accountID: String, from parent: UIViewController) {
		let host = Babel2OPMLImportHost()
		host.accountID = accountID
		parent.addChild(host)
		host.view.isHidden = true
		host.view.frame = .zero
		parent.view.addSubview(host.view)
		host.didMove(toParent: parent)
		let types = [UTType.xml, UTType(filenameExtension: "opml")].compactMap { $0 }
		let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
		picker.delegate = host
		parent.present(picker, animated: true)
	}

	func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
		if let url = urls.first {
			let parentController = parent
			Babel2LiveAccounts.importOPML(url, into: accountID) { message in
				if let message, let parentController {
					Babel2LiveSettingsService.presentError(message, from: parentController)
				}
			}
		}
		finish()
	}

	func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
		finish()
	}

	private func finish() {
		willMove(toParent: nil)
		view.removeFromSuperview()
		removeFromParent()
	}
}
