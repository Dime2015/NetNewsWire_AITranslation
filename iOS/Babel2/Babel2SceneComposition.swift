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
		subscriptionService: Babel2SubscriptionService? = nil
	) -> Babel2NavigationController {
		// A production scene always gets the live adapter graph. Preview/test
		// callers can still inject deterministic collaborators explicitly.
		let resolvedEnvironment = environment ?? Babel2AppAssembly.makeLiveEnvironment()
		let root = Babel2RootViewController(environment: resolvedEnvironment, localizationBundle: localizationBundle)
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
					rename: { name in await Babel2LiveFeedActions.rename(feed.id, to: name) },
					unsubscribe: { await Babel2LiveFeedActions.unsubscribe(feed.id) },
					// 打开网站主页：按设置「打开链接」用内置浏览器或系统浏览器
					openURL: { [weak navigationController] url in
						if resolvedSettings.openLinksInApp, let navigationController {
							navigationController.pushBabel2(Babel2BrowserViewController(url: url, openExternally: openURL), animated: true)
						} else {
							openURL(url)
						}
					}
				)
			)
			feedViewController.onScopeChanged = { [weak root] scope in
				root?.applyScope(scope)
			}
			// 同一个装配函数既用于「从列表点进文章」，也用于「下一篇」原地换页（ADR-022）
			@MainActor func makeReader(_ article: ArticleSnapshot) -> Babel2ArticleViewController {
				let articleViewController = Babel2ArticleViewController(
					article: article,
					environment: resolvedEnvironment,
					feedTitle: feed.title,
					feedIconData: feed.iconData,
					hostArticleProvider: { id in await Babel2LiveArticleLookup.article(for: id) },
					feedReaderModeSetting: Babel2FeedReaderModeSetting(
						isAlwaysOn: { Babel2LiveFeedReaderSetting.isAlwaysOn(article.feedID) },
						setAlwaysOn: { Babel2LiveFeedReaderSetting.setAlwaysOn($0, for: article.feedID) }
					),
					// 设置「打开链接」选系统浏览器时不建内置浏览器：链接与原文交给系统打开（Slice 6）
					makeBrowser: resolvedSettings.openLinksInApp ? { url in Babel2BrowserViewController(url: url, openExternally: openURL) } : nil
				)
				articleViewController.onOpenOriginal = { url, _ in
					openURL(url)
				}
				articleViewController.onOpenLink = { url in
					openURL(url)
				}
				articleViewController.nextArticleProvider = { [weak feedViewController] in
					feedViewController?.nextArticle(after: article.id)
				}
				articleViewController.onShowNext = { [weak navigationController, weak feedViewController] next in
					guard let navigationController else { return }
					// 列表先滚到这一篇，返回时它就在屏幕上
					feedViewController?.revealArticle(next.id)
					navigationController.replaceTopBabel2(with: makeReader(next), animated: true)
				}
				return articleViewController
			}
			feedViewController.onSelectArticle = { [weak navigationController] article in
				guard let navigationController else { return }
				navigationController.pushBabel2(makeReader(article), animated: true)
			}
			navigationController.pushBabel2(feedViewController, animated: true)
		}

		if let restoration {
			navigationController.applyRestoration(restoration) { route in
				makeRoute(route, environment: resolvedEnvironment, localizationBundle: localizationBundle, settings: resolvedSettings, subscriptions: resolvedSubscriptions)
			}
		}
		return navigationController
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
