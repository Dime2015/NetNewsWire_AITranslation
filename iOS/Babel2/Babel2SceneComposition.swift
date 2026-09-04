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
		root.onFeedRequested = { [weak navigationController] feed, scope in
			guard let navigationController else { return }
			let feedViewController = Babel2FeedViewController(feed: feed, scope: scope, environment: resolvedEnvironment)
			feedViewController.onSelectArticle = { [weak navigationController] article in
				guard let navigationController else { return }
				let articleViewController = Babel2ArticleViewController(article: article, environment: resolvedEnvironment)
				articleViewController.onOpenOriginal = { url, _ in
					openURL(url)
				}
				navigationController.pushBabel2(articleViewController, animated: true)
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
