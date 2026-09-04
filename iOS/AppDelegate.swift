//
//  AppDelegate.swift
//  NetNewsWire
//
//  Created by Maurice Parker on 4/8/19.
//  Copyright © 2019 Ranchero Software. All rights reserved.
//

import UIKit
@preconcurrency import BackgroundTasks
import os
import WidgetKit
import Babel2UI
import RSCore
import RSWeb
import Account
import Articles
import Secrets
import ErrorLog
import Images

@MainActor var appDelegate: AppDelegate!

@main
@MainActor final class AppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate, UnreadCountProvider {
	private let backgroundTaskDispatchQueue = DispatchQueue.init(label: "BGTaskScheduler")

	private var waitBackgroundUpdateTask = UIBackgroundTaskIdentifier.invalid
	private var syncBackgroundUpdateTask = UIBackgroundTaskIdentifier.invalid
	private(set) var launchDecision: Babel2FeatureGateDecision
	private let launchTraceRecorder: Babel2LaunchTraceRecorder
	private var babel2BootstrapStarted = false
	private var lastLoggedLaunchSequence = -1

	/// A read-only value snapshot for diagnostics and tests. All writes go
	/// through the recorder so the event stream remains append-only.
	var launchTrace: Babel2LaunchTrace {
		launchTraceRecorder.snapshot
	}

	var shuttingDown = false {
		didSet {
			if shuttingDown {
				ArticleStatusSyncTimer.shared.stop()
			}
		}
	}

	nonisolated private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "Application")

	var unreadCount = 0 {
		didSet {
			if unreadCount != oldValue {
				postUnreadCountDidChangeNotification()
				updateBadge()
			}
		}
	}

	var isSyncArticleStatusRunning = false
	var isWaitingForSyncTasks = false

	override init() {
		// Capture the process boundary before evaluating any generation policy.
		// The session id is created at the same boundary so every later event can
		// be joined to this exact process launch.
		let processEntryUptime = ProcessInfo.processInfo.systemUptime
		let launchSessionID = UUID().uuidString
		let gateUptime = ProcessInfo.processInfo.systemUptime
		#if DEBUG
		let buildChannel: Babel2BuildChannel = .debug
		#else
		let buildChannel: Babel2BuildChannel = .release
		#endif
		launchDecision = Babel2FeatureGate.decision(buildChannel: buildChannel)
		let recorder = Babel2LaunchTraceRecorder(
			decision: launchDecision,
			buildChannel: buildChannel,
			gateUptime: gateUptime,
			processEntryUptime: processEntryUptime,
			sessionID: launchSessionID
		)
		launchTraceRecorder = recorder
		super.init()
		appDelegate = self
		startBabel2LifecycleIfNeeded()
	}

	func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
		bootstrapBabel2RuntimeIfNeeded()
		return true
	}

	/// Starts only services shared by the Babel 2 runtime. UI composition belongs
	/// to `SceneDelegate` and is never selected by process arguments.
	private func startBabel2LifecycleIfNeeded() {
		guard !babel2BootstrapStarted else { return }
		babel2BootstrapStarted = true
		AppDefaults.registerDefaults()
		AccountManager.shared.start()
		NotificationCenter.default.addObserver(self, selector: #selector(unreadCountDidChange(_:)), name: .UnreadCountDidChange, object: nil)
		FaviconGenerator.templateImage = Assets.Images.faviconTemplate
		ArticleThemesManager.shared.start()
		NetworkMonitor.shared.start()
	}

	private func bootstrapBabel2RuntimeIfNeeded() {
		startBabel2LifecycleIfNeeded()
		registerBackgroundTasks()
		if AppDefaults.shared.isFirstRun && !AccountManager.shared.anyAccountHasAtLeastOneFeed() {
			DefaultFeedsImporter.importDefaultFeeds(account: AccountManager.shared.defaultAccount)
		}
		unreadCount = AccountManager.shared.unreadCount
		updateBadge()
		UNUserNotificationCenter.current().delegate = self
	}

	func application(
		_ application: UIApplication,
		configurationForConnecting connectingSceneSession: UISceneSession,
		options: UIScene.ConnectionOptions
	) -> UISceneConfiguration {
		let configuration = Babel2SceneConfiguration.makeBabel2(for: connectingSceneSession.role)
		recordSelectedSceneConfiguration(Babel2SceneConfiguration.name)
		return configuration
	}

	func recordSelectedSceneConfiguration(_ lookupName: String) {
		launchTraceRecorder.recordSceneConfigurationSelected(lookupName)
	}

	func recordObservedSceneConfiguration(_ configuration: UISceneConfiguration) {
		launchTraceRecorder.recordSceneConfigurationObserved(
			name: configuration.name,
			delegateClassName: configuration.delegateClass.map { String(describing: $0) },
			delegateMatchesExpected: configuration.delegateClass === SceneDelegate.self,
			storyboardPresent: configuration.storyboard != nil
		)
	}

	func recordRootInstalled(window: UIWindow, root: UIViewController) {
		launchTraceRecorder.recordRootInstalled(surface: launchTraceSurface(window: window, root: root))
	}

	func recordRootVisible(window: UIWindow, root: UIViewController) {
		launchTraceRecorder.recordRootVisible(surface: launchTraceSurface(window: window, root: root))
	}

	func recordContainerAppeared(window: UIWindow?, root: UIViewController) {
		launchTraceRecorder.recordContainerAppeared(surface: launchTraceSurface(window: window, root: root))
	}

	func recordContentFirstFramePresented(window: UIWindow?, root: UIViewController, content: UIView?) {
		launchTraceRecorder.recordContentFirstFramePresented(
			surface: launchTraceSurface(window: window, root: root, content: content)
		)
	}

	func recordTeardown(_ detail: String) {
		launchTraceRecorder.recordTeardown(detail)
		logLaunchTrace()
	}

	func recordLegacyUILifecycle(source: String, detail: String? = nil) {
		launchTraceRecorder.recordLegacyUILifecycle(source: source, detail: detail)
		logLaunchTrace()
	}

	func recordLegacyBootstrap(source: String, detail: String? = nil) {
		launchTraceRecorder.recordLegacyBootstrap(source: source, detail: detail)
		logLaunchTrace()
	}

	@discardableResult
	func recordLegacyBlankWebViewBootstrap(source: String, detail: String? = nil) -> Bool {
		let accepted = launchTraceRecorder.recordLegacyBlankWebViewBootstrap(source: source, detail: detail)
		if accepted { logLaunchTrace() }
		return accepted
	}

	func recordLegacyStoryboardDecode(source: String, detail: String? = nil) {
		launchTraceRecorder.recordLegacyStoryboardDecode(source: source, detail: detail)
		logLaunchTrace()
	}

	func recordLegacyCoordinatorCreation(source: String, detail: String? = nil) {
		launchTraceRecorder.recordLegacyCoordinatorCreation(source: source, detail: detail)
		logLaunchTrace()
	}

	@discardableResult
	func recordLegacyWebViewBootstrap(source: String, detail: String? = nil) -> Bool {
		let accepted = launchTraceRecorder.recordLegacyWebViewBootstrap(source: source, detail: detail)
		if accepted { logLaunchTrace() }
		return accepted
	}

	func logLaunchTrace() {
		let trace = launchTrace
		guard let latestSequence = trace.events.last?.sequence, latestSequence > lastLoggedLaunchSequence else { return }
		for event in trace.events where event.sequence > lastLoggedLaunchSequence {
			Self.logger.info("Babel2 launch trace event \(event.structuredJSONLine, privacy: .public)")
		}
		lastLoggedLaunchSequence = latestSequence
		Self.logger.info("Babel2 launch trace result \(trace.resultJSONLine, privacy: .public)")
	}

	func logExternalAction(_ detail: String) {
		Self.logger.info("Babel2 external action \(detail)")
	}

	private func launchTraceSurface(window: UIWindow?, root: UIViewController, content: UIView? = nil) -> Babel2TraceSurface {
		let rootView = root.viewIfLoaded
		let contentView = content ?? rootView
		return Babel2TraceSurface(
			controllerType: String(describing: type(of: root)),
			contentType: contentView.map { String(describing: type(of: $0)) },
			windowBounds: window.map { traceRect($0.bounds) },
			rootBounds: rootView.map { traceRect($0.bounds) },
			rootFrame: rootView.map { traceRect($0.frame) },
			contentBounds: contentView.map { traceRect($0.bounds) },
			contentFrame: contentView.map { traceRect($0.frame) },
			safeAreaInsets: rootView.map {
				Babel2TraceInsets(
					top: Double($0.safeAreaInsets.top),
					left: Double($0.safeAreaInsets.left),
					bottom: Double($0.safeAreaInsets.bottom),
					right: Double($0.safeAreaInsets.right)
				)
			},
			windowIsHidden: window.map(\.isHidden),
			windowIsKey: window.map(\.isKeyWindow),
			rootMatchesExpected: root is Babel2NavigationController
		)
	}

	private func traceRect(_ rect: CGRect) -> Babel2TraceRect {
		Babel2TraceRect(x: Double(rect.origin.x), y: Double(rect.origin.y), width: Double(rect.size.width), height: Double(rect.size.height))
	}

    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
		Task { @MainActor in
			self.resumeIfNecessary()
			await AccountManager.shared.receiveRemoteNotification(userInfo: userInfo)
			self.suspendApplication()
			completionHandler(.newData)
		}
    }

	func applicationWillTerminate(_ application: UIApplication) {
		shuttingDown = true
	}

	func applicationDidEnterBackground(_ application: UIApplication) {
		updateBadge()
	}

	func applicationDidReceiveMemoryWarning(_ application: UIApplication) {
		AppNotification.postLowMemory()
	}

	private func updateBadge() {
		assert(unreadCount == AccountManager.shared.unreadCount)
		UNUserNotificationCenter.current().setBadgeCount(unreadCount)
	}

	// MARK: Notifications

	@objc func unreadCountDidChange(_ note: Notification) {
		if note.object is AccountManager {
			unreadCount = AccountManager.shared.unreadCount
		}
	}

	// MARK: - API

	func manualRefresh(errorHandler: @escaping @Sendable (Error) -> Void) {
		AccountManager.shared.refreshAllWithoutWaiting(errorHandler: errorHandler)
	}

	/// Un-suspend network activity if it was suspended on background entry.
	func resumeIfNecessary() {
		if AccountManager.shared.isSuspended {
			AccountManager.shared.resumeAll()
			Self.logger.info("Application processing resumed.")
		}
	}

	func prepareAccountsForBackground() {
		updateBadge()

#if !SKIP_APP_GROUP_ACCESS
		ExtensionFeedAddRequestFile.shared.suspend()
#endif

		ArticleStatusSyncTimer.shared.invalidate()
		scheduleBackgroundFeedRefresh()
		syncArticleStatus()
		WidgetDataEncoder.shared?.encode()
		waitForSyncTasksToFinish()
	}

	func prepareAccountsForForeground() {
		updateBadge()
#if !SKIP_APP_GROUP_ACCESS
		ExtensionFeedAddRequestFile.shared.resume()
#endif
		ArticleStatusSyncTimer.shared.update()

		if let lastRefresh = AppDefaults.shared.lastRefresh {
			if Date() > lastRefresh.addingTimeInterval(15 * 60) {
				AccountManager.shared.refreshAllWithoutWaiting(errorHandler: ErrorHandler.log)
			} else {
				AccountManager.shared.syncArticleStatusAllWithoutWaiting()
			}
		} else {
			AccountManager.shared.refreshAllWithoutWaiting(errorHandler: ErrorHandler.log)
		}
	}

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
		completionHandler([.list, .banner, .badge, .sound])
    }

	nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {

		// Wrapper to safely transfer non-Sendable values to MainActor
		struct UnsafeSendable<T>: @unchecked Sendable {
			let value: T
		}

		let wrappedResponse = UnsafeSendable(value: response)
		let wrappedCompletionHandler = UnsafeSendable(value: completionHandler)

		Task { @MainActor in
			let response = wrappedResponse.value
			if let sceneDelegate = response.targetScene?.delegate as? SceneDelegate {
				sceneDelegate.handle(response)
			} else {
				self.logExternalAction("ignored notification without a Babel2 scene")
			}
			wrappedCompletionHandler.value()
		}
    }
}

@MainActor
enum Babel2SceneConfiguration {
	static let name = "Babel2 Configuration"

	static func makeBabel2(for role: UISceneSession.Role) -> UISceneConfiguration {
		let configuration = UISceneConfiguration(name: name, sessionRole: role)
		return configuration
	}

}

// MARK: App Initialization

// MARK: Go To Background

private extension AppDelegate {

	func waitForSyncTasksToFinish() {
		guard !isWaitingForSyncTasks && UIApplication.shared.applicationState == .background else { return }

		isWaitingForSyncTasks = true

		self.waitBackgroundUpdateTask = UIApplication.shared.beginBackgroundTask { [weak self] in
			guard let self = self else { return }
			Task { @MainActor in
				self.completeProcessing(true)
				Self.logger.info("Accounts wait for progress terminated for running too long.")
			}
		}

		DispatchQueue.main.async { [weak self] in
			self?.waitToComplete { [weak self] suspend in
				self?.completeProcessing(suspend)
			}
		}
	}

	func waitToComplete(completion: @escaping (Bool) -> Void) {
		guard UIApplication.shared.applicationState == .background else {
			Self.logger.info("App came back to foreground, no longer waiting.")
			completion(false)
			return
		}

		if AccountManager.shared.refreshInProgress || isSyncArticleStatusRunning || WidgetDataEncoder.shared?.isRunning ?? false {
			Self.logger.info("Waiting for sync to finish…")
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
				self?.waitToComplete(completion: completion)
			}
		} else {
			Self.logger.info("Refresh progress complete.")
			completion(true)
		}
	}

	func completeProcessing(_ suspend: Bool) {
		if suspend {
			suspendApplication()
		}
		UIApplication.shared.endBackgroundTask(self.waitBackgroundUpdateTask)
		self.waitBackgroundUpdateTask = UIBackgroundTaskIdentifier.invalid
		isWaitingForSyncTasks = false
	}

	func syncArticleStatus() {
		guard !isSyncArticleStatusRunning else { return }

		isSyncArticleStatusRunning = true

		let completeProcessing = { [weak self] in
			guard let self else {
				return
			}
			self.isSyncArticleStatusRunning = false
			UIApplication.shared.endBackgroundTask(self.syncBackgroundUpdateTask)
			self.syncBackgroundUpdateTask = UIBackgroundTaskIdentifier.invalid
		}

		self.syncBackgroundUpdateTask = UIApplication.shared.beginBackgroundTask { [weak self] in
			Task { @MainActor in
				guard let self = self else { return }
				self.isSyncArticleStatusRunning = false
				UIApplication.shared.endBackgroundTask(self.syncBackgroundUpdateTask)
				self.syncBackgroundUpdateTask = UIBackgroundTaskIdentifier.invalid
				Self.logger.info("Accounts sync processing terminated for running too long.")
			}
		}

		Task { @MainActor in
			await AccountManager.shared.syncArticleStatusAll()
			completeProcessing()
		}
	}

	func suspendApplication() {
		guard UIApplication.shared.applicationState == .background else {
			return
		}
		guard !AccountManager.shared.isSuspended else {
			return
		}

		AccountManager.shared.suspendNetworkAll()
		AccountManager.shared.saveAll()
		ArticleThemeDownloader.shared.cleanUp()

		AppNotification.postAppDidGoToBackground()

		CoalescingQueue.standard.performCallsImmediately()
		for scene in UIApplication.shared.connectedScenes {
			if let sceneDelegate = scene.delegate as? SceneDelegate {
				sceneDelegate.suspend()
			}
		}

		Self.logger.info("Application processing suspended.")
	}

}

// MARK: - Background Tasks

private extension AppDelegate {
	/// Register all background tasks.
	nonisolated func registerBackgroundTasks() {
		// Register background feed refresh.
		BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.ranchero.NetNewsWire.FeedRefresh", using: nil) { task in
			self.performBackgroundFeedRefresh(with: task as! BGAppRefreshTask)
		}
	}

	/// Schedule a background app refresh based on `AppDefaults.refreshInterval`.
	nonisolated func scheduleBackgroundFeedRefresh() {
		// We send this to a dedicated serial queue because as of 11/05/19 on iOS 13.2 the call to the
		// task scheduler can hang indefinitely.
		backgroundTaskDispatchQueue.async {
			do {
				let request = BGAppRefreshTaskRequest(identifier: "com.ranchero.NetNewsWire.FeedRefresh")
				request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60)
				try BGTaskScheduler.shared.submit(request)
			} catch {
				Self.logger.error("Could not schedule app refresh: \(error.localizedDescription)")
			}
		}
	}

	nonisolated func performBackgroundFeedRefresh(with task: BGAppRefreshTask) {

		scheduleBackgroundFeedRefresh() // schedule next refresh

		Self.logger.info("Performing background refresh.")

		Task { @MainActor in
			if AccountManager.shared.isSuspended {
				AccountManager.shared.resumeAll()
			}
			await AccountManager.shared.refreshAll(errorHandler: ErrorHandler.log)
			if !AccountManager.shared.isSuspended {
				await WidgetDataEncoder.shared?.encodeAndWait()
				self.suspendApplication()
				Self.logger.info("Background refresh completed.")
				task.setTaskCompleted(success: true)
			}
		}

		// set expiration handler
		task.expirationHandler = { [weak task] in
			Self.logger.info("Background refresh terminated for running too long.")
			task?.setTaskCompleted(success: false)
			Task { @MainActor in
				self.suspendApplication()
			}
		}
	}
}
