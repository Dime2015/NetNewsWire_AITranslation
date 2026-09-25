import Babel2Core
import Babel2UI
import UIKit

@MainActor
enum Babel2SceneComposition {
	static func makeRoot(
		environment: AppEnvironment? = nil,
		restoration: Babel2NavigationRestoration? = nil,
		localizationBundle: Bundle = .main,
		openURL: @escaping (URL) -> Void = { UIApplication.shared.open($0) }
	) -> Babel2NavigationController {
		// A production scene always gets the live adapter graph. Preview/test
		// callers can still inject deterministic collaborators explicitly.
		let resolvedEnvironment = environment ?? Babel2AppAssembly.makeLiveEnvironment()
		let root = Babel2RootViewController(environment: resolvedEnvironment, localizationBundle: localizationBundle)
		let navigationController = Babel2NavigationController(rootViewController: root)
		navigationController.routeFactory = { route in
			makePlaceholder(route: route, environment: resolvedEnvironment, localizationBundle: localizationBundle)
		}

		// Keep the root action seam explicit until Settings and subscription
		// discovery routes are implemented; no legacy controller is involved.
		root.onSettingsRequested = { [weak navigationController] in
			guard let navigationController else { return }
			guard let settings = Babel2SceneComposition.makePlaceholder(
				route: .settings,
				environment: resolvedEnvironment,
				localizationBundle: localizationBundle
			) else { return }
			navigationController.pushBabel2(settings, animated: true)
		}
		root.onAddRequested = { [weak navigationController] in
			guard let navigationController else { return }
			guard let addSubscription = Babel2SceneComposition.makePlaceholder(
				route: .addSubscription,
				environment: resolvedEnvironment,
				localizationBundle: localizationBundle
			) else { return }
			navigationController.pushBabel2(addSubscription, animated: true)
		}
		root.onFeedRequested = { [weak navigationController, weak root] feed, scope in
			guard let navigationController else { return }
			let feedViewController = Babel2FeedViewController(feed: feed, scope: scope, environment: resolvedEnvironment)
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
					makeBrowser: { url in Babel2BrowserViewController(url: url, openExternally: openURL) }
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
				makePlaceholder(route: route, environment: resolvedEnvironment, localizationBundle: localizationBundle)
			}
		}
		return navigationController
	}

	private static func makePlaceholder(
		route: Babel2RouteState,
		environment: AppEnvironment,
		localizationBundle: Bundle
	) -> UIViewController? {
		guard route == .settings || route == .addSubscription else { return nil }
		return Babel2PlaceholderViewController(route: route, environment: environment, localizationBundle: localizationBundle)
	}
}
