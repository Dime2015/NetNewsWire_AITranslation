import Foundation
import UIKit
import Account

/// 添加订阅页的正式实现（2026-09-25，ADR-030）：复用 1.x 发现引擎（`Shared/Discovery/`，只调用不改），
/// 账户操作经 `Babel2LiveSubscriptions`（本层唯一碰账户单例的文件）。
@MainActor
final class Babel2LiveSubscriptionService: Babel2SubscriptionService {
	/// 关键词并行搜时的分组顺序与默认展开（1.x 用户决定：网站最前且展开，其余三类先收起）。
	private static let order: [FeedSearchResult.Kind] = [.website, .podcast, .youtube, .reddit]

	/// 与试读页之间的桥：试读页只弱引用它，这里保存到页面关闭。
	private var previewBridges = [Babel2PreviewBridge]()
	/// 最近搜到的原始结果（按订阅地址）：试读页要用主页地址、播客编号等，转换时不能丢。
	private var originals = [String: FeedSearchResult]()

	// MARK: 搜索

	func search(_ query: String) async -> [Babel2DiscoveryGroup] {
		let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !keyword.isEmpty else { return [] }
		switch FeedQueryRouter.route(for: keyword) {
		case .podcastKeyword(let unified):
			return await unifiedSearch(unified)
		case .reddit(let name):
			return [single(.reddit, results: RedditFeedBuilder.results(subreddit: name), error: nil)]
		case .youtube(let text):
			do {
				return [single(.youtube, results: [try await YouTubeFeedResolver.resolve(text)], error: nil)]
			} catch {
				return [single(.youtube, results: [], error: error)]
			}
		case .website(let text):
			do {
				return [single(.website, results: try await WebsiteFeedResolver.search(text), error: nil)]
			} catch {
				return [single(.website, results: [], error: error)]
			}
		case .unsupportedKeyword(let hint):
			return [Babel2DiscoveryGroup(kind: .website, results: [], statusMessage: hint, isExpanded: true)]
		}
	}

	/// 关键词：四类并行搜，一类失败不连累其它三类（每组显示自己的原因）。
	private func unifiedSearch(_ keyword: String) async -> [Babel2DiscoveryGroup] {
		async let website = Self.attempt { try await WebsiteSearcher.search(keyword) }
		async let podcast = Self.attempt { try await PodcastSearcher.search(keyword) }
		async let youtube = Self.attempt { try await YouTubeSearcher.search(keyword) }
		async let reddit = Self.attempt { try await RedditSearcher.search(keyword) }
		let outcomes = await [FeedSearchResult.Kind.website: website, .podcast: podcast, .youtube: youtube, .reddit: reddit]
		return Self.order.map { kind in
			let outcome = outcomes[kind] ?? ([], nil)
			var group = single(kind, results: outcome.0, error: outcome.1)
			group.isExpanded = kind == .website
			return group
		}
	}

	private static func attempt(_ work: () async throws -> [FeedSearchResult]) async -> ([FeedSearchResult], Error?) {
		do { return (try await work(), nil) } catch { return ([], error) }
	}

	private func single(_ kind: FeedSearchResult.Kind, results: [FeedSearchResult], error: Error?) -> Babel2DiscoveryGroup {
		for result in results { originals[result.feedURL] = result }
		let mapped = results.map(Self.convert)
		let status: String? = mapped.isEmpty ? (error.map(Self.message(for:)) ?? Self.emptyMessage(for: Self.kind(kind))) : nil
		return Babel2DiscoveryGroup(kind: Self.kind(kind), results: mapped, statusMessage: status, isExpanded: true)
	}

	private static func kind(_ kind: FeedSearchResult.Kind) -> Babel2DiscoveryKind {
		switch kind {
		case .website: return .website
		case .podcast: return .podcast
		case .youtube: return .youtube
		case .reddit: return .reddit
		}
	}

	private static func convert(_ result: FeedSearchResult) -> Babel2DiscoveryResult {
		Babel2DiscoveryResult(kind: kind(result.kind), title: result.title, subtitle: result.subtitle,
			feedURL: result.feedURL, iconURL: result.iconURL.flatMap(URL.init(string:)))
	}

	/// 发现引擎里对应的原始结果（试读要用）；万一不在缓存里，按已有字段重建。
	private func original(_ result: Babel2DiscoveryResult) -> FeedSearchResult {
		if let cached = originals[result.feedURL] { return cached }
		let kind: FeedSearchResult.Kind
		switch result.kind {
		case .website: kind = .website
		case .podcast: kind = .podcast
		case .youtube: kind = .youtube
		case .reddit: kind = .reddit
		}
		return FeedSearchResult(kind: kind, title: result.title, subtitle: result.subtitle, feedURL: result.feedURL,
			homePageURL: nil, appleCollectionID: nil, iconURL: result.iconURL?.absoluteString)
	}

	private static func emptyMessage(for kind: Babel2DiscoveryKind) -> String {
		switch kind {
		case .website: return Babel2SettingsText.t("No matching websites.")
		case .podcast: return Babel2SettingsText.t("No matching podcasts.")
		case .youtube: return Babel2SettingsText.t("No matching YouTube channels.")
		case .reddit: return Babel2SettingsText.t("No matching subreddits.")
		}
	}

	/// 常见错误换成中英文说明（「未配置 Key」指向 Babel 2.0 的设置位置）；其余沿用发现引擎自己的说明。
	private static func message(for error: Error) -> String {
		guard let searchError = error as? FeedSearchError else {
			return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
		}
		switch searchError {
		case .missingCredentials(let service):
			return Babel2SettingsText.f("No %@ API key yet. Add it in Settings → Subscriptions & Discovery → Discovery API Keys to search %@ here.", service, service)
		case .network:
			return Babel2SettingsText.t("Couldn't connect. Check your network and try again.")
		case .badResponse(let code):
			return Babel2SettingsText.f("The server returned an error (%d). Try again later.", code)
		case .reddit(let code) where code == 429:
			return Babel2SettingsText.t("Reddit is rate limiting requests. Wait a minute or two and try again.")
		case .youtube(let code) where code == 403:
			return Babel2SettingsText.t("YouTube refused the search. The free daily quota (about 100 searches) may be used up, or the API key is wrong.")
		case .websiteFeedNotFound:
			return Babel2SettingsText.t("No RSS feed was found on this website. If you know its feed address, paste that instead.")
		default:
			return searchError.errorDescription ?? error.localizedDescription
		}
	}

	// MARK: 订阅位置 / 订阅 / 取消订阅

	var destinations: [Babel2SubscriptionDestination] {
		let all = Babel2LiveSubscriptions.destinations()
		let multipleAccounts = Set(all.map(\.accountName)).count > 1
		return all.map { destination in
			let title: String
			if let folder = destination.folderName {
				title = multipleAccounts ? "\(destination.accountName) / \(folder)" : folder
			} else {
				title = multipleAccounts
					? Babel2SettingsText.f("%@ (Top Level)", destination.accountName)
					: Babel2SettingsText.t("Top Level (No Folder)")
			}
			return Babel2SubscriptionDestination(id: destination.id, title: title)
		}
	}

	func isSubscribed(_ result: Babel2DiscoveryResult) -> Bool {
		Babel2LiveSubscriptions.isSubscribed(result.feedURL)
	}

	func subscribe(_ result: Babel2DiscoveryResult, to destinationID: String) async -> String? {
		switch await Babel2LiveSubscriptions.subscribe(feedURL: result.feedURL, name: result.title, destinationID: destinationID) {
		case .subscribed:
			// 首页立即按新订阅重新加载；留在本页（1.x 用户决定：订完通常还要继续挑）
			NotificationCenter.default.post(name: .babel2LibraryDidChange, object: nil)
			return nil
		case .alreadySubscribed:
			return Babel2SettingsText.t("You're already subscribed to this feed.")
		case .failed(let error):
			// Reddit 的失败换成说实话的提示（上游把限流也报成「找不到 feed」）
			if result.kind == .reddit {
				let name = RedditFeedBuilder.subredditName(from: result.feedURL) ?? result.title
				return Self.message(for: RedditFeedBuilder.friendlyError(for: error, subreddit: name))
			}
			return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
		}
	}

	func unsubscribe(_ result: Babel2DiscoveryResult) async -> String? {
		let error = await Babel2LiveSubscriptions.unsubscribe(feedURL: result.feedURL)
		NotificationCenter.default.post(name: .babel2LibraryDidChange, object: nil)
		return error.map { ($0 as? LocalizedError)?.errorDescription ?? $0.localizedDescription }
	}

	// MARK: 试读

	func makePreview(_ result: Babel2DiscoveryResult, isBusy: @escaping () -> Bool, subscribe: @escaping (@escaping (String?) -> Void) -> Void) -> UIViewController? {
		let bridge = Babel2PreviewBridge(isBusy: isBusy, subscribe: subscribe)
		previewBridges.append(bridge)
		let preview = FeedPreviewViewController(result: original(result), subscriptionHandler: bridge)
		let navigation = UINavigationController(rootViewController: preview)
		preview.navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak navigation] _ in
			navigation?.dismiss(animated: true)
		})
		navigation.modalPresentationStyle = .pageSheet
		return navigation
	}
}

/// 试读页要求的订阅接口 → 转给添加订阅页（订到页面当前选的位置；成败都回调，错误由试读页自己弹）。
private final class Babel2PreviewBridge: FeedPreviewSubscriptionHandling {
	private let isBusy: () -> Bool
	private let subscribe: (@escaping (String?) -> Void) -> Void

	init(isBusy: @escaping () -> Bool, subscribe: @escaping (@escaping (String?) -> Void) -> Void) {
		self.isBusy = isBusy
		self.subscribe = subscribe
	}

	func previewIsSubscribed(_ result: FeedSearchResult) -> Bool {
		Babel2LiveSubscriptions.isSubscribed(result.feedURL)
	}

	func previewIsBusy(_ result: FeedSearchResult) -> Bool { isBusy() }

	func previewSubscribe(_ result: FeedSearchResult, completion: @escaping (Error?) -> Void) {
		subscribe { message in
			completion(message.map { NSError(domain: "Babel2Subscription", code: 0, userInfo: [NSLocalizedDescriptionKey: $0]) })
		}
	}
}
