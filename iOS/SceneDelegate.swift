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

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {

	var window: UIWindow?
	var coordinator: SceneCoordinator!
	private var genesisV2RootViewController: RootSplitViewController?
	private weak var babelShellViewController: BabelShellViewController?
	private var legacyToggleButton: UIButton?

	// UIWindowScene delegate

	func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {

		// [外观] 一行换一行:窗口的 tint 改走调色板,并且**换色时会重设**
		// (原来这里设一次静态色板就不管了 —— 用户第 9 件的病根之一)。见 NNWAccentTint。
		NNWAccentTint.install(in: window!)

		let rootViewController = window!.rootViewController as! RootSplitViewController
		genesisV2RootViewController = rootViewController
		rootViewController.presentsWithGesture = true
		rootViewController.showsSecondaryOnlyButton = true
		rootViewController.preferredDisplayMode = UISplitViewController.DisplayMode(rawValue: AppDefaults.shared.splitViewPreferredDisplayMode) ?? .oneBesideSecondary

		// On first run on iPad, show all three columns so the sidebar is visible
		if AppDefaults.shared.isFirstRun && UIDevice.current.userInterfaceIdiom == .pad {
			rootViewController.preferredDisplayMode = .twoBesideSecondary
		}

		coordinator = SceneCoordinator(rootSplitViewController: rootViewController)
		rootViewController.coordinator = coordinator
		rootViewController.delegate = coordinator

		coordinator.restoreWindowState(activity: session.stateRestorationActivity)

		updateUserInterfaceStyle()
		installBabelShellIfRequested()

		NotificationCenter.default.addObserver(self, selector: #selector(handleUserInterfaceColorPaletteDidUpdate(_:)), name: .userInterfaceColorPaletteDidUpdate, object: AppDefaults.self)

		if connectionOptions.urlContexts.first?.url != nil {
			self.scene(scene, openURLContexts: connectionOptions.urlContexts)
			return
		}

		if let shortcutItem = connectionOptions.shortcutItem {
			handleShortcutItem(shortcutItem)
			return
		}

		if let notificationResponse = connectionOptions.notificationResponse {
			showGenesisV2Interface()
			coordinator.handle(notificationResponse)
			return
		}

		// Handle activities from external sources (Handoff, Spotlight, Siri Shortcuts).
		// Skip handling session.stateRestorationActivity since UserDefaults now handles state restoration.
		if let userActivity = connectionOptions.userActivities.first {
			showGenesisV2Interface()
			coordinator.handle(userActivity)
		}
	}

	func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
		appDelegate.resumeIfNecessary()
		handleShortcutItem(shortcutItem)
		completionHandler(true)
	}

	func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
		appDelegate.resumeIfNecessary()
		showGenesisV2Interface()
		coordinator.handle(userActivity)
	}

	func sceneDidEnterBackground(_ scene: UIScene) {
		coordinator.didEnterBackground()
		appDelegate.prepareAccountsForBackground()
	}

	func sceneWillEnterForeground(_ scene: UIScene) {
		appDelegate.resumeIfNecessary()
		appDelegate.prepareAccountsForForeground()
		coordinator.resetFocus()
	}

	func stateRestorationActivity(for scene: UIScene) -> NSUserActivity? {
		return coordinator.stateRestorationActivity
	}

	// API

	func handle(_ response: UNNotificationResponse) {
		appDelegate.resumeIfNecessary()
		showGenesisV2Interface()
		coordinator.handle(response)
	}

	func suspend() {
		coordinator.suspend()
	}

	func cleanUp(conditional: Bool) {
		coordinator.cleanUp(conditional: conditional)
	}

	// Handle Opening of URLs

	func scene(_ scene: UIScene, openURLContexts urlContexts: Set<UIOpenURLContext>) {
		guard let context = urlContexts.first else { return }
		showGenesisV2Interface()

		DispatchQueue.main.async {

			DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
				self.coordinator.dismissIfLaunchingFromExternalAction()
			}

			let urlString = context.url.absoluteString

			// Handle the feed: and feeds: schemes
			if urlString.starts(with: "feed:") || urlString.starts(with: "feeds:") {
				let normalizedURLString = urlString.normalizedURL
				if normalizedURLString.mayBeURL {
					self.coordinator.showAddFeed(initialFeed: normalizedURLString, initialFeedName: nil)
				}
			}

			// Show Unread View or Article
			if urlString.contains(WidgetDeepLink.unread.url.absoluteString) {
				guard let comps = URLComponents(string: urlString ) else { return  }
				let id = comps.queryItems?.first(where: { $0.name == "id" })?.value
				if id != nil {
					if AccountManager.shared.isSuspended {
						AccountManager.shared.resumeAll()
					}
					self.coordinator.selectAllUnreadFeed {
						DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
							self.coordinator.selectArticleInCurrentFeed(id!)
						}
					}
				} else {
					self.coordinator.selectAllUnreadFeed()
				}
			}

			// Show Today View or Article
			if urlString.contains(WidgetDeepLink.today.url.absoluteString) {
				guard let comps = URLComponents(string: urlString ) else { return  }
				let id = comps.queryItems?.first(where: { $0.name == "id" })?.value
				if id != nil {
					if AccountManager.shared.isSuspended {
						AccountManager.shared.resumeAll()
					}
					self.coordinator.selectTodayFeed {
						DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
							self.coordinator.selectArticleInCurrentFeed(id!)
						}
					}
				} else {
					self.coordinator.selectTodayFeed()
				}
			}

			// Show Starred View or Article
			if urlString.contains(WidgetDeepLink.starred.url.absoluteString) {
				guard let comps = URLComponents(string: urlString ) else { return  }
				let id = comps.queryItems?.first(where: { $0.name == "id" })?.value
				if id != nil {
					if AccountManager.shared.isSuspended {
						AccountManager.shared.resumeAll()
					}
					self .coordinator.selectStarredFeed {
						DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
							self.coordinator.selectArticleInCurrentFeed(id!)
						}
					}
				} else {
					self.coordinator.selectStarredFeed()
				}
			}

			let filename = context.url.standardizedFileURL.path
			if filename.hasSuffix(ArticleTheme.nnwThemeSuffix) {
				self.coordinator.importTheme(filename: filename)
				return
			}

			// Handle theme URLs: netnewswire://theme/add?url={url}
			guard let comps = URLComponents(url: context.url, resolvingAgainstBaseURL: false),
				  "theme" == comps.host,
				 let queryItems = comps.queryItems else {
				return
			}

			if let providedThemeURL = queryItems.first(where: { $0.name == "url" })?.value {
				if let themeURL = URL(string: providedThemeURL) {
					let request = URLRequest(url: themeURL)

					DispatchQueue.main.async {
						NotificationCenter.default.post(name: .didBeginDownloadingTheme, object: nil)
					}
					let task = URLSession.shared.downloadTask(with: request) { location, _, error in
						guard
							  let location = location else { return }

						Task { @MainActor in
							do {
								try ArticleThemeDownloader.shared.handleFile(at: location)
							} catch {
								NotificationCenter.default.post(name: .didFailToImportThemeWithError, object: nil, userInfo: ["error": error])
							}
						}
					}
					task.resume()
				} else {
					print("No theme URL")
					return
				}
			} else {
				return
			}
		}
	}
}

private extension SceneDelegate {

	func installBabelShellIfRequested() {
		guard BabelShellConfiguration.isEnabled else { return }

		let shellViewController = BabelShellViewController()
		shellViewController.onOpenGenesisV2 = { [weak self] in
			self?.showGenesisV2Interface()
		}
		babelShellViewController = shellViewController
		window?.rootViewController = shellViewController
		window?.makeKeyAndVisible()
	}

	func showGenesisV2Interface() {
		guard let genesisV2RootViewController,
			  window?.rootViewController !== genesisV2RootViewController else {
			return
		}
		legacyToggleButton?.removeFromSuperview()
		legacyToggleButton = nil

		window?.rootViewController = genesisV2RootViewController
		window?.makeKeyAndVisible()
		let button = UIButton(type: .system)
		button.setTitle("Babel", for: .normal)
		button.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
		button.backgroundColor = .secondarySystemBackground
		button.layer.cornerRadius = 16
		button.addTarget(self, action: #selector(showBabelInterface), for: .touchUpInside)
		button.translatesAutoresizingMaskIntoConstraints = false
		genesisV2RootViewController.view.addSubview(button)
		NSLayoutConstraint.activate([
			button.trailingAnchor.constraint(equalTo: genesisV2RootViewController.view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
			button.topAnchor.constraint(equalTo: genesisV2RootViewController.view.safeAreaLayoutGuide.topAnchor, constant: 8),
			button.widthAnchor.constraint(equalToConstant: 62), button.heightAnchor.constraint(equalToConstant: 32)
		])
		legacyToggleButton = button
	}

	@objc private func showBabelInterface() {
		legacyToggleButton?.removeFromSuperview()
		legacyToggleButton = nil
		guard let babelShellViewController else { return }
		window?.rootViewController = babelShellViewController
		window?.makeKeyAndVisible()
	}

	func handleShortcutItem(_ shortcutItem: UIApplicationShortcutItem) {
		showGenesisV2Interface()
		switch shortcutItem.type {
		case "com.ranchero.NetNewsWire.FirstUnread":
			coordinator.selectFirstUnreadInAllUnread()
		case "com.ranchero.NetNewsWire.ShowSearch":
			coordinator.showSearch()
		case "com.ranchero.NetNewsWire.ShowAdd":
			coordinator.showAddFeed()
		default:
			break
		}
	}

	@objc func handleUserInterfaceColorPaletteDidUpdate(_ notification: Notification) {
		assert(Thread.isMainThread)
		Task {
			updateUserInterfaceStyle()
		}
	}

	@MainActor func updateUserInterfaceStyle() {
		switch AppDefaults.userInterfaceColorPalette {
		case .automatic:
			self.window?.overrideUserInterfaceStyle = .unspecified
		case .light:
			self.window?.overrideUserInterfaceStyle = .light
		case .dark:
			self.window?.overrideUserInterfaceStyle = .dark
		}
	}
}
