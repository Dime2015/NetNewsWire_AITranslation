//
//  AppDelegate.swift
//  NetNewsWire
//
//  Created by Maurice Parker on 6/28/19.
//  Copyright © 2019 Ranchero Software. All rights reserved.
//

import UIKit
import UserNotifications
import Account
import Babel2Core
import Babel2UI

@MainActor
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {

	var window: UIWindow?
	private var babel2NavigationController: Babel2NavigationController?
	private var sceneGenerationToken = UUID()
	/// Narrow test seam for proving that the URL callback passes the parser's
	/// typed value directly to the executor. Production leaves this nil.
	var externalActionExecutionObserverForTesting: ((Babel2LegacyURLAction) -> Void)?

	// UIWindowScene delegate

	func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
		guard let windowScene = scene as? UIWindowScene else { return }
		// Observe the configuration UIKit actually attached to this session. The
		// AppDelegate's selected configuration is recorded separately; missing or
		// unnamed session evidence remains incomplete rather than being invented.
		appDelegate.recordObservedSceneConfiguration(session.configuration)
		installBabel2Root(in: windowScene, restoration: restorationValue(from: session.stateRestorationActivity))

		if let context = connectionOptions.urlContexts.first {
			_ = handleExternalActionURL(context.url)
		} else if let shortcutItem = connectionOptions.shortcutItem {
			handleShortcutItem(shortcutItem)
		} else if let notificationResponse = connectionOptions.notificationResponse {
			handle(notificationResponse)
		} else if let userActivity = connectionOptions.userActivities.first {
			continueUserActivity(userActivity)
		}
	}

	func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
		handleShortcutItem(shortcutItem)
		completionHandler(true)
	}

	func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
		continueUserActivity(userActivity)
	}

	func sceneDidEnterBackground(_ scene: UIScene) {
		appDelegate.prepareAccountsForBackground()
	}

	func sceneWillEnterForeground(_ scene: UIScene) {
		appDelegate.resumeIfNecessary()
		appDelegate.prepareAccountsForForeground()
	}

	func sceneDidBecomeActive(_ scene: UIScene) {}

	func sceneDidDisconnect(_ scene: UIScene) {
		sceneGenerationToken = UUID()
		appDelegate.recordTeardown("sceneDidDisconnect.babel2")
		babel2NavigationController?.tearDown()
		babel2NavigationController = nil
		window?.rootViewController = nil
		window?.isHidden = true
		window = nil
	}

	func stateRestorationActivity(for scene: UIScene) -> NSUserActivity? {
		babel2NavigationController?.makeRestorationActivity()
	}

	// API

	func handle(_ response: UNNotificationResponse) {
		appDelegate.logExternalAction("ignored notification while Babel2 root remains active")
	}

	func suspend() {}
	func cleanUp(conditional: Bool) {}

	// Handle Opening of URLs

	func scene(_ scene: UIScene, openURLContexts urlContexts: Set<UIOpenURLContext>) {
		for context in urlContexts {
			_ = handleExternalActionURL(context.url)
		}
	}

	@discardableResult
	func handleExternalActionURL(_ url: URL) -> Babel2LegacyURLAction? {
		guard let action = Babel2ExternalActionParser.parse(url) else {
			appDelegate.logExternalAction("ignored unknown external action")
			return nil
		}
		externalActionExecutionObserverForTesting?(action)
		appDelegate.logExternalAction("ignored \(action.traceName) while Babel2 root remains active")
		return action
	}
}

private extension SceneDelegate {

	func installBabel2Root(in windowScene: UIWindowScene, restoration: Babel2NavigationRestoration?) {
		guard babel2NavigationController == nil else { return }

		let navigationController = Babel2SceneComposition.makeRoot(restoration: restoration)
		let generationToken = sceneGenerationToken
		navigationController.onContainerAppeared = { [weak self, weak navigationController] in
			guard let self,
				  let navigationController,
				  self.sceneGenerationToken == generationToken,
				  self.babel2NavigationController === navigationController else { return }
			appDelegate.recordContainerAppeared(window: navigationController.view.window, root: navigationController)
			appDelegate.logLaunchTrace()
		}
		if let root = navigationController.viewControllers.first as? Babel2RootViewController {
			root.onContentFirstFramePresented = { [weak self, weak root, weak navigationController] in
				guard let self,
					  let root,
					  let navigationController,
					  self.sceneGenerationToken == generationToken,
					  self.babel2NavigationController === navigationController,
					  root === navigationController.viewControllers.first else { return }
				appDelegate.recordContentFirstFramePresented(window: navigationController.view.window, root: navigationController, content: root.viewIfLoaded)
				appDelegate.logLaunchTrace()
			}
		}

		babel2NavigationController = navigationController
		let babel2Window = UIWindow(windowScene: windowScene)
		babel2Window.rootViewController = navigationController
		window = babel2Window
		appDelegate.recordRootInstalled(window: babel2Window, root: navigationController)
		babel2Window.makeKeyAndVisible()
		appDelegate.recordRootVisible(window: babel2Window, root: navigationController)
		appDelegate.logLaunchTrace()
	}

	func restorationValue(from activity: NSUserActivity?) -> Babel2NavigationRestoration? {
		guard let data = activity?.userInfo?["babel2.restoration"] as? Data else { return nil }
		return Babel2NavigationRestoration.validated(data)
	}

	func handleShortcutItem(_ shortcutItem: UIApplicationShortcutItem) {
		appDelegate.logExternalAction("ignored shortcut while Babel2 root remains active")
	}

	func continueUserActivity(_ activity: NSUserActivity) {
		appDelegate.logExternalAction("ignored user activity while Babel2 root remains active")
	}
}
