import Babel2Core
import Babel2UI
import UIKit

@MainActor
enum Babel2SceneComposition {
	static func makeRoot(
		environment: AppEnvironment? = nil,
		restoration: Babel2NavigationRestoration? = nil,
		localizationBundle: Bundle = .main,
		openURL: @escaping (URL) -> Void = { UIApplication.shared.open($0) },
		settingsService: Babel2SettingsService? = nil,
		subscriptionService: Babel2SubscriptionService? = nil,
		libraryEditing: Babel2LibraryEditing? = nil,
		lastPlace: Babel2LastPlaceStore? = nil
	) -> Babel2NavigationController {
		// A production scene always gets the live adapter graph. Preview/test
		// callers can still inject deterministic collaborators explicitly.
		let resolvedEnvironment = environment ?? Babel2AppAssembly.makeLiveEnvironment()
		let root = Babel2RootViewController(environment: resolvedEnvironment, localizationBundle: localizationBundle)
		// 首页长按整理文件夹 / 订阅源、「+」里新建文件夹（ADR-045）：正式实现走账户公开接口；测试可注入假的实现
		root.libraryEditing = libraryEditing ?? liveLibraryEditing()
		let navigationController = Babel2NavigationController(rootViewController: root)
		// 设置页（Slice 6）：接到现有存储的正式实现；测试可注入假的实现
		let resolvedSettings = settingsService ?? Babel2LiveSettingsService()
		// 添加订阅页（2026-09-25）：接 1.x 发现引擎的正式实现；测试可注入假的实现
		let resolvedSubscriptions = subscriptionService ?? Babel2LiveSubscriptionService()
		navigationController.routeFactory = { route in
			makeRoute(route, environment: resolvedEnvironment, localizationBundle: localizationBundle, settings: resolvedSettings, subscriptions: resolvedSubscriptions)
		}
		// 配色模式应用到整个窗口；设置里改了立即重新应用
		navigationController.interfaceStyleProvider = { resolvedSettings.appearance.interfaceStyle }
		let appearanceObserver = NotificationCenter.default.addObserver(forName: .babel2AppearanceDidChange, object: nil, queue: .main) { [weak navigationController] _ in
			MainActor.assumeIsolated { navigationController?.applyInterfaceStyle() }
		}
		navigationController.onTearDown = { NotificationCenter.default.removeObserver(appearanceObserver) }
		// 重开 App 回到上次的页面（Babel2LastPlace）：恢复时不带动画地推入列表
		let pushMode = Babel2PushMode()

		root.onSettingsRequested = { [weak navigationController] in
			guard let navigationController else { return }
			navigationController.pushBabel2(Babel2SettingsHomeViewController(service: resolvedSettings), animated: true)
		}
		root.onAddRequested = { [weak navigationController] in
			guard let navigationController else { return }
			guard let addSubscription = Babel2SceneComposition.makeRoute(
				.addSubscription,
				environment: resolvedEnvironment,
				localizationBundle: localizationBundle,
				settings: resolvedSettings,
				subscriptions: resolvedSubscriptions
			) else { return }
			navigationController.pushBabel2(addSubscription, animated: true)
		}
		root.onFeedRequested = { [weak navigationController, weak root] feed, scope in
			guard let navigationController else { return }
			let feedViewController = Babel2FeedViewController(
				feed: feed,
				scope: scope,
				environment: resolvedEnvironment,
				titleTranslation: Babel2TitleTranslationSetting(
					isEnabled: { Babel2LiveTitleTranslation.isEnabled(feed.id) },
					setEnabled: { Babel2LiveTitleTranslation.setEnabled($0, for: feed.id) },
					request: { ids in Task { await Babel2LiveTitleTranslation.request(ids) } }
				),
				heroImage: Babel2FeedHeroImageSource(
					cached: { Babel2LiveFeedHeroImage.cached(feed.id) },
					fetch: { onImage in Babel2LiveFeedHeroImage.fetch(feed.id, onImage: onImage) }
				),
				confirmMarkAllRead: { resolvedSettings.confirmMarkAllRead },
				// 大图上的「刷新」「更多」（ADR-031）
				feedActions: Babel2FeedActions(
					refresh: { Babel2LiveFeedActions.refreshAll() },
					isSyncing: { Babel2LiveFeedActions.isSyncing },
					homePageURL: { Babel2LiveFeedActions.homePageURL(feed.id) },
					feedURL: { Babel2LiveFeedActions.feedURL(feed.id) },
					isAlwaysReadingMode: { Babel2LiveFeedReaderSetting.isAlwaysOn(feed.id) },
					setAlwaysReadingMode: { Babel2LiveFeedReaderSetting.setAlwaysOn($0, for: feed.id) },
					notificationsEnabled: { Babel2LiveFeedActions.notificationsEnabled(feed.id) },
					setNotificationsEnabled: { Babel2LiveFeedActions.setNotificationsEnabled($0, for: feed.id) },
					isForeign: { Babel2LiveForeignFeeds.isForeign(feed.id) },
					setForeign: { Babel2LiveForeignFeeds.setForeign($0, for: feed.id) },
					// 自定义图标（ADR-046）
					hasCustomIcon: { Babel2LiveCustomFeedIcons.hasCustomIcon(feed.id) },
					setCustomIcon: { Babel2LiveCustomFeedIcons.set($0, for: feed.id) },
					rename: { name in await Babel2LiveFeedActions.rename(feed.id, to: name) },
					unsubscribe: { await Babel2LiveFeedActions.unsubscribe(feed.id) },
					// 打开网站主页：按设置「打开链接」用内置浏览器或系统浏览器
					openURL: { [weak navigationController] url in
						if resolvedSettings.openLinksInApp, let navigationController {
							navigationController.pushBabel2(makeBrowser(url, navigationController: navigationController,
								environment: resolvedEnvironment, settings: resolvedSettings, openURL: openURL), animated: true)
						} else {
							openURL(url)
						}
					}
				),
				// 打开时图标还没到的，之后补上（ADR-039）
				currentIcon: { Babel2LiveIconCache.currentIconData(for: feed.id) },
				// 记住滑到哪（ADR-053）
				positionStore: .shared
			)
			wireArticleList(feedViewController, root: root, navigationController: navigationController,
				environment: resolvedEnvironment, settings: resolvedSettings, openURL: openURL)
			navigationController.pushBabel2(feedViewController, animated: !pushMode.isRestoring)
		}
		// 跨源入口（今日未读 / 全部未读 / 外文源 / 全部星标，ADR-044）：同一个列表页，文章来自多个订阅源
		root.onSmartFeedRequested = { [weak navigationController, weak root] kind, scope in
			guard let navigationController else { return }
			let listViewController = Babel2FeedViewController(
				smartFeed: kind,
				scope: scope,
				environment: resolvedEnvironment,
				confirmMarkAllRead: { resolvedSettings.confirmMarkAllRead },
				positionStore: .shared
			)
			wireArticleList(listViewController, root: root, navigationController: navigationController,
				environment: resolvedEnvironment, settings: resolvedSettings, openURL: openURL)
			navigationController.pushBabel2(listViewController, animated: !pushMode.isRestoring)
		}

		if let restoration {
			navigationController.applyRestoration(restoration) { route in
				makeRoute(route, environment: resolvedEnvironment, localizationBundle: localizationBundle, settings: resolvedSettings, subscriptions: resolvedSubscriptions)
			}
		}
		if let lastPlace {
			installLastPlace(lastPlace, navigationController: navigationController, root: root,
				environment: resolvedEnvironment, pushMode: pushMode)
		}
		return navigationController
	}

	/// 重开 App 回到上次的页面（2026-09-27）：退到后台时记下「列表 → 文章」；冷启动时记录不超过 24 小时就搭回去。
	/// 搭的过程中盖一块纸色底板（与启动画面同色），搭好后淡出——看起来就是直接打开在那一页。
	/// 找不到订阅源 / 文章（退订了、删了）就停在能到的那一层；2 秒内没搭好就放弃、停在首页。
	private static func installLastPlace(
		_ store: Babel2LastPlaceStore,
		navigationController: Babel2NavigationController,
		root: Babel2RootViewController,
		environment: AppEnvironment,
		pushMode: Babel2PushMode
	) {
		let backgroundObserver = NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak navigationController] _ in
			MainActor.assumeIsolated {
				guard let navigationController else { return }
				store.save(Babel2LastPlace.capture(from: navigationController.viewControllers, now: .now))
			}
		}
		let previousTearDown = navigationController.onTearDown
		navigationController.onTearDown = {
			previousTearDown?()
			NotificationCenter.default.removeObserver(backgroundObserver)
		}

		// 系统恢复了设置 / 添加订阅页（被系统在后台回收过）时，以系统恢复的为准
		guard navigationController.viewControllers.count == 1,
			  let place = store.load(), place.isFresh(now: .now) else { return }
		let cover = Babel2ResumeCover(frame: navigationController.view.bounds)
		navigationController.view.addSubview(cover)
		let progress = Babel2ResumeProgress()
		Task { @MainActor [weak cover] in
			try? await Task.sleep(for: .seconds(2))
			progress.isExpired = true
			cover?.dismiss()
		}
		Task { @MainActor [weak navigationController, weak root, weak cover] in
			defer { cover?.dismiss() }
			let scope = place.feedScope
			// 用户已经动过（或已过期）就不再往里推
			@MainActor func stillWaiting() -> Bool {
				!progress.isExpired && navigationController?.viewControllers.count == 1
			}
			// 等窗口出来、首页先就位，再往上推（启动那一刻直接推会打乱页面出现的顺序）
			while !progress.isExpired, navigationController?.view.window == nil {
				try? await Task.sleep(for: .milliseconds(16))
			}
			if let kind = place.smartFeedKind {
				guard stillWaiting(), let root else { return }
				root.applyScope(scope)
				pushMode.isRestoring = true
				root.onSmartFeedRequested?(kind, scope)
				pushMode.isRestoring = false
			} else if let feedID = place.feedSnapshotID {
				let feed = await findFeed(feedID, scope: scope, provider: environment.dataProvider)
				guard let feed, stillWaiting(), let root else { return }
				root.applyScope(scope)
				pushMode.isRestoring = true
				root.onFeedRequested?(feed, scope)
				pushMode.isRestoring = false
			} else {
				return
			}
			guard let articleID = place.articleSnapshotID,
				  let article = try? await environment.dataProvider.articleSnapshot(for: articleID),
				  !progress.isExpired,
				  let list = navigationController?.topViewController as? Babel2FeedViewController else { return }
			list.onRestoreArticle?(article)
		}
	}

	/// 按编号找订阅源：先在那一档的首页数据里找（篇数与那一档一致），找不到再到「全部」里找。
	private static func findFeed(_ id: FeedSnapshot.ID, scope: Babel2FeedScope, provider: any DataProviding) async -> FeedSnapshot? {
		for candidate in [scope, .all] {
			if let feed = try? await provider.librarySnapshot(for: candidate).feeds.first(where: { $0.id == id }) {
				return feed
			}
		}
		return nil
	}

	/// 文章列表页（单个订阅源或跨源列表）的共同接线：档位同步给首页、点文章进阅读页、「下一篇」原地换页。
	/// 阅读页的来源名、图标、「总是用阅读模式」都按这篇文章自己的订阅源（跨源列表里每篇不同，ADR-044）。
	private static func wireArticleList(
		_ listViewController: Babel2FeedViewController,
		root: Babel2RootViewController?,
		navigationController: Babel2NavigationController,
		environment: AppEnvironment,
		settings: Babel2SettingsService,
		openURL: @escaping (URL) -> Void
	) {
		listViewController.onScopeChanged = { [weak root] scope in
			root?.applyScope(scope)
		}
		// 同一个装配函数既用于「从列表点进文章」，也用于「下一篇」原地换页（ADR-022）
		@MainActor func makeReader(_ article: ArticleSnapshot) -> Babel2ArticleViewController {
			let source = listViewController.sourceFeed(for: article)
			let articleViewController = Babel2ArticleViewController(
				article: article,
				environment: environment,
				feedTitle: source?.title,
				// 用此刻的图标（列表打开后图标才到的也能用上，ADR-039）
				feedIconData: Babel2LiveIconCache.currentIconData(for: article.feedID) ?? source?.iconData,
				hostArticleProvider: { id in await Babel2LiveArticleLookup.article(for: id) },
				feedReaderModeSetting: Babel2FeedReaderModeSetting(
					isAlwaysOn: { Babel2LiveFeedReaderSetting.isAlwaysOn(article.feedID) },
					setAlwaysOn: { Babel2LiveFeedReaderSetting.setAlwaysOn($0, for: article.feedID) }
				),
				// 设置「打开链接」选系统浏览器时不建内置浏览器：链接与原文交给系统打开（Slice 6）
				makeBrowser: settings.openLinksInApp ? { [weak navigationController] url in
					makeBrowser(url, navigationController: navigationController, environment: environment, settings: settings, openURL: openURL)
				} : nil,
				// 播客音频条、YouTube 简介（ADR-041）
				mediaProvider: { id in await Babel2LiveArticleMedia.extras(for: id) },
				// 记住读到哪（ADR-053）
				positionStore: .shared,
				// 阅读模式抽到的全文存在手机上，下次直接用（2026-09-27）
				fullTextCache: .shared
			)
			articleViewController.onOpenOriginal = { url, _ in
				openURL(url)
			}
			articleViewController.onOpenLink = { url in
				openURL(url)
			}
			articleViewController.nextArticleProvider = { [weak listViewController] in
				listViewController?.nextArticle(after: article.id)
			}
			articleViewController.onShowNext = { [weak navigationController, weak listViewController] next in
				guard let navigationController else { return }
				// 列表先滚到这一篇，返回时它就在屏幕上
				listViewController?.revealArticle(next.id)
				navigationController.replaceTopBabel2(with: makeReader(next), animated: true)
			}
			return articleViewController
		}
		listViewController.onSelectArticle = { [weak navigationController] article in
			guard let navigationController else { return }
			navigationController.pushBabel2(makeReader(article), animated: true)
		}
		// 重开 App 回到上次的页面：不带动画直接打开（Babel2LastPlace）
		listViewController.onRestoreArticle = { [weak navigationController] article in
			guard let navigationController else { return }
			navigationController.pushBabel2(makeReader(article), animated: false)
		}
	}

	/// 内置浏览器（ADR-021）。右上角「翻译此页」（ADR-047）：抽出的正文开一个阅读页（独立网页，不进订阅），自动翻译。
	static func makeBrowser(
		_ url: URL,
		navigationController: Babel2NavigationController?,
		environment: AppEnvironment,
		settings: Babel2SettingsService,
		openURL: @escaping (URL) -> Void
	) -> Babel2BrowserViewController {
		Babel2BrowserViewController(url: url, openExternally: openURL) { [weak navigationController] page in
			guard let navigationController else { return }
			let reader = makeWebPageReader(page, navigationController: navigationController, environment: environment,
				settings: settings, openURL: openURL)
			navigationController.pushBabel2(reader, animated: true)
		}
	}

	/// 「翻译此页」的阅读页：正文是抽出来的全文；没有已读 / 星标 / 下一篇 / 阅读模式；打开后自动翻译（ADR-047）。
	/// 文章编号按网址固定（同一页再翻直接用译文缓存）；翻译引擎需要的文章对象由接入层临时造一个（不存进数据库）。
	static func makeWebPageReader(
		_ page: Babel2BrowserViewController.PageContent,
		navigationController: Babel2NavigationController?,
		environment: AppEnvironment,
		settings: Babel2SettingsService,
		openURL: @escaping (URL) -> Void
	) -> Babel2ArticleViewController {
		let site = page.url.host ?? page.url.absoluteString
		let feedID = FeedSnapshot.ID(accountID: Babel2LiveWebPageArticle.accountID, feedID: site)
		let article = ArticleSnapshot(
			id: ArticleSnapshot.ID(accountID: feedID.accountID, feedID: site, articleID: page.articleID),
			title: page.title,
			content: page.html,
			url: page.url,
			feedID: feedID,
			isRead: true,
			author: page.byline
		)
		let reader = Babel2ArticleViewController(
			article: article,
			environment: environment,
			feedTitle: site,
			hostArticleProvider: { _ in Babel2LiveWebPageArticle.hostArticle(for: article) },
			makeBrowser: settings.openLinksInApp ? { [weak navigationController] url in
				makeBrowser(url, navigationController: navigationController, environment: environment, settings: settings, openURL: openURL)
			} : nil,
			standalonePage: true,
			positionStore: .shared
		)
		reader.onOpenOriginal = { url, _ in openURL(url) }
		reader.onOpenLink = { url in openURL(url) }
		reader.requestTranslationWhenReady()
		return reader
	}

	/// 首页整理的正式实现（ADR-045）：文件夹与订阅源的增删改走账户公开接口，自定义图标存在这台手机上（ADR-046）。
	static func liveLibraryEditing() -> Babel2LibraryEditing {
		Babel2LibraryEditing(
			accounts: { Babel2LiveLibraryEditing.accounts() },
			folderInfo: { Babel2LiveLibraryEditing.folderInfo($0) },
			placement: { Babel2LiveLibraryEditing.placement($0) },
			createFolder: { name, accountID in await Babel2LiveLibraryEditing.createFolder(named: name, accountID: accountID) },
			renameFolder: { id, name in await Babel2LiveLibraryEditing.renameFolder(id, to: name) },
			deleteFolder: { id, keepFeeds in await Babel2LiveLibraryEditing.deleteFolder(id, keepFeeds: keepFeeds) },
			moveFeed: { id, from, to in await Babel2LiveLibraryEditing.moveFeed(id, from: from, to: to) },
			removeFeedFromFolder: { id, folderID in await Babel2LiveLibraryEditing.removeFeed(id, fromFolder: folderID) },
			renameFeed: { id, name in await Babel2LiveFeedActions.rename(id, to: name) },
			unsubscribe: { id in await Babel2LiveFeedActions.unsubscribe(id) },
			customIcons: Babel2CustomFeedIconStore(
				hasCustomIcon: { Babel2LiveCustomFeedIcons.hasCustomIcon($0) },
				setCustomIcon: { id, data in Babel2LiveCustomFeedIcons.set(data, for: id) }
			)
		)
	}

	/// 路由恢复与路由工厂：设置 → 设置首页；添加订阅 → 添加订阅页。
	private static func makeRoute(
		_ route: Babel2RouteState,
		environment: AppEnvironment,
		localizationBundle: Bundle,
		settings: Babel2SettingsService,
		subscriptions: Babel2SubscriptionService
	) -> UIViewController? {
		switch route {
		case .settings:
			return Babel2SettingsHomeViewController(service: settings)
		case .addSubscription:
			return Babel2AddSubscriptionViewController(service: subscriptions, imageProvider: environment.imageProvider)
		default:
			return nil
		}
	}
}

/// 恢复上次页面时，首页的「打开订阅源」照常走同一段装配，只是不带动画（Babel2LastPlace）。
@MainActor
final class Babel2PushMode {
	var isRestoring = false
}

/// 恢复上次页面的进度：超过 2 秒还没搭好就放弃，之后到的数据不再往里推。
@MainActor
final class Babel2ResumeProgress {
	var isExpired = false
}
