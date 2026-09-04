import XCTest
import UIKit
import Babel2Core
import Babel2UI
@testable import NetNewsWire

@MainActor
final class Babel2FeedReaderTests: XCTestCase {
	func testFeedLoadsOnlyRequestedFeedAndPassesSnapshotToReader() async throws {
		let accountAFeed = FeedSnapshot.ID(accountID: "account-a", feedID: "shared-feed")
		let accountBFeed = FeedSnapshot.ID(accountID: "account-b", feedID: "shared-feed")
		let articleA = makeArticle(
			accountID: accountAFeed.accountID,
			feedID: accountAFeed.feedID,
			articleID: "article-a",
			title: "Account A",
			body: "<p>Only account A</p>",
			url: URL(string: "https://example.com/article-a")
		)
		let articleB = makeArticle(
			accountID: accountBFeed.accountID,
			feedID: accountBFeed.feedID,
			articleID: "article-b",
			title: "Account B",
			body: "<p>Only account B</p>",
			url: URL(string: "https://example.com/article-b")
		)
		let feed = makeFeed(id: accountAFeed, title: "A feed")
		let provider = FakeDataProvider(feeds: [accountAFeed: [articleA], accountBFeed: [articleB]])
		let renderer = RecordingRenderer()
		let environment = makeEnvironment(provider: provider, renderer: renderer)
		let feedViewController = Babel2FeedViewController(feed: feed, environment: environment)

		feedViewController.loadViewIfNeeded()
		let tableView = try XCTUnwrap(descendant(of: feedViewController.view, matching: UITableView.self))
		await waitForRows(in: tableView, count: 1)

		let feedRequests = await provider.feedRequests
		let feedScopeRequests = await provider.feedScopeRequests
		let libraryRequestCount = await provider.libraryRequestCount
		XCTAssertEqual(feedRequests, [accountAFeed])
		XCTAssertEqual(feedScopeRequests, [.all])
		XCTAssertEqual(libraryRequestCount, 0)
		XCTAssertEqual(tableView.dataSource?.tableView(tableView, numberOfRowsInSection: 0), 1)

		var selectedArticle: ArticleSnapshot?
		feedViewController.onSelectArticle = { selectedArticle = $0 }
		feedViewController.tableView(tableView, didSelectRowAt: IndexPath(row: 0, section: 0))
		XCTAssertEqual(selectedArticle, articleA)

		let articleViewController = Babel2ArticleViewController(article: articleA, environment: environment)
		articleViewController.loadViewIfNeeded()
		await waitForRenderer(renderer)
		let receivedArticles = await renderer.received
		XCTAssertEqual(receivedArticles, [articleA])
		let textView = try XCTUnwrap(descendant(of: articleViewController.view, matching: UITextView.self))
		XCTAssertEqual(textView.text, "Only account A")
		XCTAssertNotEqual(articleA.id, articleB.id)
	}

	func testLateMismatchedRenderResultDoesNotPublishToReader() async throws {
		let feedID = FeedSnapshot.ID(accountID: "account", feedID: "feed")
		let articleID = ArticleSnapshot.ID(accountID: "account", feedID: "feed", articleID: "article")
		let article = ArticleSnapshot(
			id: articleID,
			title: "Article",
			content: "<p>Original body</p>",
			url: nil,
			feedID: feedID
		)
		let wrongID = ArticleSnapshot.ID(accountID: "account", feedID: "feed", articleID: "other")
		let renderer = RecordingRenderer(result: ArticleRenderSnapshot(articleID: wrongID, body: "<p>Stale body</p>"))
		let environment = makeEnvironment(provider: FakeDataProvider(), renderer: renderer)
		let viewController = Babel2ArticleViewController(article: article, environment: environment)

		viewController.loadViewIfNeeded()
		await waitForRenderer(renderer)

		let textView = try XCTUnwrap(descendant(of: viewController.view, matching: UITextView.self))
		XCTAssertEqual(textView.text, "Loading…")
	}

	func testDeinitCancelsSuspendedRendererAndRejectsLateResult() async throws {
		let feedID = FeedSnapshot.ID(accountID: "account", feedID: "feed")
		let article = makeArticle(
			accountID: feedID.accountID,
			feedID: feedID.feedID,
			articleID: "article",
			title: "Article",
			body: "<p>Cached body</p>",
			url: nil
		)
		let renderer = SuspendedRenderer()
		let environment = makeEnvironment(provider: FakeDataProvider(), renderer: renderer)
		var controllerReference: WeakReference<Babel2ArticleViewController>?
		var retainedTextView: UITextView?

		do {
			let viewController = Babel2ArticleViewController(article: article, environment: environment)
			controllerReference = WeakReference(viewController)
			viewController.loadViewIfNeeded()
			await waitForRendererStart(renderer)
			retainedTextView = try XCTUnwrap(descendant(of: viewController.view, matching: UITextView.self))
		}

		let reference = try XCTUnwrap(controllerReference)
		await waitForRelease(reference)
		let rendererDidStart = await renderer.didStart
		XCTAssertTrue(rendererDidStart)
		await renderer.resume()
		await waitForRendererReturn(renderer)
		let rendererTaskWasCancelled = await renderer.taskWasCancelled
		XCTAssertTrue(rendererTaskWasCancelled)
		XCTAssertEqual(retainedTextView?.text, "Loading…")
	}

	func testOpenOriginalUsesInjectedClosureAndMissingURLHasNoButton() async throws {
		let feedID = FeedSnapshot.ID(accountID: "account", feedID: "feed")
		let feed = makeFeed(id: feedID, title: "Feed")
		let article = makeArticle(
			accountID: feedID.accountID,
			feedID: feedID.feedID,
			articleID: "article",
			title: "Original",
			body: "<p>Body</p>",
			url: URL(string: "https://example.com/article")
		)
		let provider = FakeDataProvider(feeds: [feedID: [article]])
		let environment = makeEnvironment(provider: provider)
		var openedURL: URL?
		let navigationController = Babel2SceneComposition.makeRoot(
			environment: environment,
			openURL: { openedURL = $0 }
		)
		let root = try XCTUnwrap(navigationController.viewControllers.first as? Babel2RootViewController)

		root.onFeedRequested?(feed, .all)
		let feedViewController = try XCTUnwrap(navigationController.topViewController as? Babel2FeedViewController)
		feedViewController.loadViewIfNeeded()
		let feedTableView = try XCTUnwrap(descendant(of: feedViewController.view, matching: UITableView.self))
		await waitForRows(in: feedTableView, count: 1)
		feedViewController.tableView(feedTableView, didSelectRowAt: IndexPath(row: 0, section: 0))
		let articleViewController = try XCTUnwrap(navigationController.topViewController as? Babel2ArticleViewController)
		articleViewController.loadViewIfNeeded()
		let openButton = try XCTUnwrap(descendant(of: articleViewController.view, matching: UIButton.self) { button in
			button.accessibilityIdentifier == "babel2.article.open-original"
		})
		openButton.sendActions(for: .touchUpInside)
		XCTAssertEqual(openedURL, article.url)

		let bodyOnlyArticle = ArticleSnapshot(
			id: ArticleSnapshot.ID(accountID: feedID.accountID, feedID: feedID.feedID, articleID: "body-only"),
			title: "Body only",
			content: "<p>Cached body</p>",
			url: nil,
			feedID: feedID
		)
		let bodyOnlyViewController = Babel2ArticleViewController(article: bodyOnlyArticle, environment: environment)
		bodyOnlyViewController.loadViewIfNeeded()
		let buttons = bodyOnlyViewController.view.allSubviews.compactMap { $0 as? UIButton }
		let bodyOnlyOpenButton = try XCTUnwrap(buttons.first { $0.accessibilityIdentifier == "babel2.article.open-original" })
		XCTAssertTrue(bodyOnlyOpenButton.isHidden)
	}

	func testRootScopeChangesQueryAndKeepsOnlyScopedPositiveCounts() async throws {
		let allFeedID = FeedSnapshot.ID(accountID: "account", feedID: "all")
		let unreadFeedID = FeedSnapshot.ID(accountID: "account", feedID: "unread")
		let allFeed = makeFeed(id: allFeedID, title: "All", count: 2)
		let unreadFeed = makeFeed(id: unreadFeedID, title: "Unread", count: 1)
		let provider = FakeDataProvider(
			feeds: [:],
			librarySnapshots: [
				.all: LibrarySnapshot(feeds: [allFeed]),
				.unread: LibrarySnapshot(feeds: [unreadFeed]),
				.starred: LibrarySnapshot(feeds: [])
			]
		)
		let root = try XCTUnwrap(Babel2SceneComposition.makeRoot(environment: makeEnvironment(provider: provider)).viewControllers.first as? Babel2RootViewController)
		root.loadViewIfNeeded()
		root.viewDidAppear(false)
		let tableView = try XCTUnwrap(rootTable(for: root, scope: .all))
		await waitForRootState(root, scope: .all, state: "loaded", rows: 1)
		XCTAssertEqual(root.selectedScope, .all)
		let allCell = root.tableView(tableView, cellForRowAt: IndexPath(row: 0, section: 0))
		XCTAssertEqual(allCell.accessibilityValue, "2")

		let unreadButton = try XCTUnwrap(descendant(of: root.view, matching: UIButton.self) { $0.accessibilityIdentifier == "babel2.scope.unread" })
		unreadButton.sendActions(for: .touchUpInside)
		await waitForRootState(root, scope: .unread, state: "loaded", rows: 1)
		XCTAssertEqual(root.selectedScope, .unread)
		let unreadTableView = try XCTUnwrap(rootTable(for: root, scope: .unread))
		let unreadCell = root.tableView(unreadTableView, cellForRowAt: IndexPath(row: 0, section: 0))
		XCTAssertEqual(unreadCell.accessibilityValue, "1")

		let allButton = try XCTUnwrap(descendant(of: root.view, matching: UIButton.self) { $0.accessibilityIdentifier == "babel2.scope.all" })
		let starredButton = try XCTUnwrap(descendant(of: root.view, matching: UIButton.self) { $0.accessibilityIdentifier == "babel2.scope.starred" })
		allButton.sendActions(for: .touchUpInside)
		unreadButton.sendActions(for: .touchUpInside)
		starredButton.sendActions(for: .touchUpInside)
		await waitForLibraryScope(provider, .starred)
		await waitForRootState(root, scope: .starred, state: "empty", rows: 0)
		XCTAssertEqual(root.selectedScope, .starred)
		let requestedScopes = await provider.libraryScopes
		XCTAssertTrue(requestedScopes.contains(.all))
		XCTAssertTrue(requestedScopes.contains(.unread))
		XCTAssertTrue(requestedScopes.contains(.starred))
	}

	func testPendingReloadKeepsSettledRowsUntilReplacementArrives() async throws {
		let feedID = FeedSnapshot.ID(accountID: "account", feedID: "feed")
		let feed = makeFeed(id: feedID, title: "Feed", count: 2)
		let provider = FakeDataProvider(librarySnapshots: [.all: LibrarySnapshot(feeds: [feed])])
		let root = try XCTUnwrap(Babel2SceneComposition.makeRoot(environment: makeEnvironment(provider: provider)).viewControllers.first as? Babel2RootViewController)
		root.loadViewIfNeeded()
		root.viewDidAppear(false)
		await waitForRootState(root, scope: .all, state: "loaded", rows: 1)

		await provider.delayNextLibraryRequest(.all)
		NotificationCenter.default.post(name: .babel2LibraryDidChange, object: nil)
		await waitForLibraryStart(provider, .all, after: 1)
		let tableView = try XCTUnwrap(rootTable(for: root, scope: .all))
		XCTAssertEqual(tableView.numberOfRows(inSection: 0), 1)
		XCTAssertEqual(tableView.accessibilityValue, "loaded")
		await provider.releaseLibraryRequest(.all, snapshot: LibrarySnapshot(feeds: [feed]))
		await waitForRootState(root, scope: .all, state: "loaded", rows: 1)
	}

	func testStaleScopeResultCannotPublishAfterLatestIntentChanges() async throws {
		let allID = FeedSnapshot.ID(accountID: "account", feedID: "all")
		let unreadID = FeedSnapshot.ID(accountID: "account", feedID: "unread")
		let starredID = FeedSnapshot.ID(accountID: "account", feedID: "starred")
		let allFeed = makeFeed(id: allID, title: "All", count: 1)
		let unreadFeed = makeFeed(id: unreadID, title: "Unread", count: 1)
		let starredFeed = makeFeed(id: starredID, title: "Starred", count: 1)
		let provider = FakeDataProvider(librarySnapshots: [
			.all: LibrarySnapshot(feeds: [allFeed]),
			.starred: LibrarySnapshot(feeds: [starredFeed])
		])
		let root = try XCTUnwrap(Babel2SceneComposition.makeRoot(environment: makeEnvironment(provider: provider)).viewControllers.first as? Babel2RootViewController)
		root.loadViewIfNeeded()
		root.viewDidAppear(false)
		await waitForRootState(root, scope: .all, state: "loaded", rows: 1)

		await provider.delayNextLibraryRequest(.unread)
		let unreadButton = try XCTUnwrap(descendant(of: root.view, matching: UIButton.self) { $0.accessibilityIdentifier == "babel2.scope.unread" })
		let starredButton = try XCTUnwrap(descendant(of: root.view, matching: UIButton.self) { $0.accessibilityIdentifier == "babel2.scope.starred" })
		unreadButton.sendActions(for: .touchUpInside)
		await waitForLibraryStart(provider, .unread, after: 1)
		starredButton.sendActions(for: .touchUpInside)
		await waitForRootState(root, scope: .starred, state: "loaded", rows: 1)
		await provider.releaseLibraryRequest(.unread, snapshot: LibrarySnapshot(feeds: [unreadFeed]))
		for _ in 0..<100 { await Task.yield() }

		let unreadTable = try XCTUnwrap(rootTable(for: root, scope: .unread))
		XCTAssertEqual(unreadTable.numberOfRows(inSection: 0), 0)
		XCTAssertEqual(unreadTable.accessibilityValue, "loading")
		XCTAssertEqual(root.selectedScope, .starred)
	}

	func testRapidScopeTapsSetOnlyLastScopeActive() async throws {
		let feeds = Babel2FeedScope.allCases.reduce(into: [Babel2FeedScope: LibrarySnapshot]()) { result, scope in
			let id = FeedSnapshot.ID(accountID: "account", feedID: scope.rawValue)
			result[scope] = LibrarySnapshot(feeds: [makeFeed(id: id, title: scope.rawValue, count: 1)])
		}
		let provider = FakeDataProvider(librarySnapshots: feeds)
		let root = try XCTUnwrap(Babel2SceneComposition.makeRoot(environment: makeEnvironment(provider: provider)).viewControllers.first as? Babel2RootViewController)
		root.loadViewIfNeeded()
		root.viewDidAppear(false)
		await waitForRootState(root, scope: .all, state: "loaded", rows: 1)
		let unread = try XCTUnwrap(descendant(of: root.view, matching: UIButton.self) { $0.accessibilityIdentifier == "babel2.scope.unread" })
		let starred = try XCTUnwrap(descendant(of: root.view, matching: UIButton.self) { $0.accessibilityIdentifier == "babel2.scope.starred" })
		unread.sendActions(for: .touchUpInside)
		starred.sendActions(for: .touchUpInside)
		await waitForRootState(root, scope: .starred, state: "loaded", rows: 1)
		await waitForSelectedScopeButton(starred)
		XCTAssertEqual(root.selectedScope, .starred)
		XCTAssertEqual(unread.accessibilityValue, "Not selected")
		XCTAssertEqual(starred.accessibilityValue, "Selected")
	}

	func testErrorIsDistinctFromEmptyAndRetryReloads() async throws {
		let provider = FakeDataProvider()
		await provider.failNextLibraryRequest(.all)
		let root = try XCTUnwrap(Babel2SceneComposition.makeRoot(environment: makeEnvironment(provider: provider)).viewControllers.first as? Babel2RootViewController)
		root.loadViewIfNeeded()
		root.viewDidAppear(false)
		await waitForRootState(root, scope: .all, state: "error", rows: 0)
		let retry = try XCTUnwrap(descendant(of: root.view, matching: UIButton.self) { $0.accessibilityIdentifier == "babel2.feeds.retry.all" })
		XCTAssertFalse(retry.isHidden)
		await provider.setLibrarySnapshot(.all, snapshot: LibrarySnapshot())
		retry.sendActions(for: .touchUpInside)
		await waitForRootState(root, scope: .all, state: "empty", rows: 0)
	}

	func testSyncArrowTracksActiveScopeSnapshot() async throws {
		let feedID = FeedSnapshot.ID(accountID: "account", feedID: "feed")
		let feed = makeFeed(id: feedID, title: "Feed", count: 1)
		let provider = FakeDataProvider(librarySnapshots: [.all: LibrarySnapshot(feeds: [feed], isSyncing: true)])
		let root = try XCTUnwrap(Babel2SceneComposition.makeRoot(environment: makeEnvironment(provider: provider)).viewControllers.first as? Babel2RootViewController)
		root.loadViewIfNeeded()
		root.viewDidAppear(false)
		await waitForRootState(root, scope: .all, state: "loaded", rows: 1)
		let arrow = try XCTUnwrap(descendant(of: root.view, matching: UIButton.self) { $0.accessibilityIdentifier == "babel2.sync.arrow" })
		XCTAssertFalse(arrow.isHidden)

		await provider.setLibrarySnapshot(.all, snapshot: LibrarySnapshot(feeds: [feed], isSyncing: false))
		NotificationCenter.default.post(name: .babel2LibraryDidChange, object: nil)
		await waitForLibraryStart(provider, .all, after: 2)
		for _ in 0..<200 {
			if arrow.isHidden { break }
			await Task.yield()
		}
		XCTAssertTrue(arrow.isHidden)
	}
}

private actor FakeDataProvider: DataProviding {
	private enum ProviderError: Error { case failed }
	private let feedArticles: [FeedSnapshot.ID: [ArticleSnapshot]]
	private var librarySnapshots: [Babel2FeedScope: LibrarySnapshot]
	private var delayedScopes = Set<Babel2FeedScope>()
	private var failedScopes = Set<Babel2FeedScope>()
	private var libraryContinuations = [Babel2FeedScope: CheckedContinuation<LibrarySnapshot, Error>]()
	private(set) var libraryRequestCount = 0
	private(set) var libraryScopes = [Babel2FeedScope]()
	private(set) var libraryStarts = [Babel2FeedScope]()
	private(set) var feedRequests = [FeedSnapshot.ID]()
	private(set) var feedScopeRequests = [Babel2FeedScope]()

	init(
		feeds: [FeedSnapshot.ID: [ArticleSnapshot]] = [:],
		librarySnapshots: [Babel2FeedScope: LibrarySnapshot] = [:]
	) {
		feedArticles = feeds
		self.librarySnapshots = librarySnapshots
	}

	func librarySnapshot(for scope: Babel2FeedScope) async throws -> LibrarySnapshot {
		libraryRequestCount += 1
		libraryScopes.append(scope)
		libraryStarts.append(scope)
		if failedScopes.remove(scope) != nil {
			throw ProviderError.failed
		}
		if delayedScopes.remove(scope) != nil {
			return try await withCheckedThrowingContinuation { continuation in
				libraryContinuations[scope] = continuation
			}
		}
		return librarySnapshots[scope] ?? LibrarySnapshot()
	}

	func delayNextLibraryRequest(_ scope: Babel2FeedScope) {
		delayedScopes.insert(scope)
	}

	func failNextLibraryRequest(_ scope: Babel2FeedScope) {
		failedScopes.insert(scope)
	}

	func releaseLibraryRequest(_ scope: Babel2FeedScope, snapshot: LibrarySnapshot) {
		libraryContinuations.removeValue(forKey: scope)?.resume(returning: snapshot)
	}

	func setLibrarySnapshot(_ scope: Babel2FeedScope, snapshot: LibrarySnapshot) {
		librarySnapshots[scope] = snapshot
	}

	func hasStarted(_ scope: Babel2FeedScope, atLeast count: Int) -> Bool {
		libraryStarts.filter { $0 == scope }.count >= count
	}

	func feedArticlesSnapshot(for id: FeedSnapshot.ID, scope: Babel2FeedScope) async throws -> [ArticleSnapshot] {
		feedRequests.append(id)
		feedScopeRequests.append(scope)
		return feedArticles[id] ?? []
	}

	func articleSnapshot(for id: ArticleSnapshot.ID) async throws -> ArticleSnapshot? {
		feedArticles.values.flatMap { $0 }.first { $0.id == id }
	}
}

private actor RecordingRenderer: ArticleRendering {
	private(set) var received = [ArticleSnapshot]()
	private let result: ArticleRenderSnapshot?

	init(result: ArticleRenderSnapshot? = nil) {
		self.result = result
	}

	func render(_ article: ArticleSnapshot) async throws -> ArticleRenderSnapshot {
		received.append(article)
		return result ?? ArticleRenderSnapshot(articleID: article.id, body: article.content)
	}
}

private actor SuspendedRenderer: ArticleRendering {
	private var continuation: CheckedContinuation<ArticleRenderSnapshot, Never>?
	private var articleID: ArticleSnapshot.ID?
	private(set) var didStart = false
	private(set) var didReturn = false
	private(set) var taskWasCancelled = false

	func render(_ article: ArticleSnapshot) async throws -> ArticleRenderSnapshot {
		didStart = true
		articleID = article.id
		let result = await withCheckedContinuation { continuation in
			self.continuation = continuation
		}
		taskWasCancelled = Task.isCancelled
		didReturn = true
		return result
	}

	func resume() {
		guard let articleID else { return }
		continuation?.resume(returning: ArticleRenderSnapshot(articleID: articleID, body: "<p>Late body</p>"))
		continuation = nil
	}
}

private final class WeakReference<Object: AnyObject> {
	weak var value: Object?

	init(_ value: Object) {
		self.value = value
	}
}

private struct NoopActionHandler: ActionHandling {
	func handle(_ action: LibraryAction) async throws {}
}

private struct NoopSettingsProvider: SettingsProviding {
	func settingsSnapshot() async throws -> SettingsSnapshot { SettingsSnapshot() }
}

private struct NoopImageProvider: ImageProviding {
	func imageData(for url: URL) async throws -> Data? { nil }
}

@MainActor
private func makeEnvironment(
	provider: any DataProviding,
	renderer: any ArticleRendering = RecordingRenderer()
) -> AppEnvironment {
	Babel2AppAssembly.makeEnvironment(
		dataProvider: provider,
		actionHandler: NoopActionHandler(),
		settingsProvider: NoopSettingsProvider(),
		articleRenderer: renderer,
		imageProvider: NoopImageProvider()
	)
}

@MainActor
private func makeFeed(id: FeedSnapshot.ID, title: String, count: Int? = nil) -> FeedSnapshot {
	FeedSnapshot(id: id, title: title, url: URL(string: "https://example.com/\(id.feedID)")!, articleCount: count)
}

@MainActor
private func makeArticle(
	accountID: String,
	feedID: String,
	articleID: String,
	title: String,
	body: String,
	url: URL?
) -> ArticleSnapshot {
	let feedSnapshotID = FeedSnapshot.ID(accountID: accountID, feedID: feedID)
	return ArticleSnapshot(
		id: ArticleSnapshot.ID(accountID: accountID, feedID: feedID, articleID: articleID),
		title: title,
		content: body,
		url: url,
		feedID: feedSnapshotID
	)
}

@MainActor
private func waitForRows(in tableView: UITableView, count: Int) async {
	for _ in 0..<100 {
		if tableView.numberOfRows(inSection: 0) == count { return }
		await Task.yield()
	}
	XCTFail("Timed out waiting for \(count) feed rows")
}

@MainActor
private func waitForRootState(_ root: Babel2RootViewController, scope: Babel2FeedScope, state: String, rows: Int) async {
	guard let tableView = rootTable(for: root, scope: scope) else {
		XCTFail("Missing root feed table")
		return
	}
	for _ in 0..<200 {
		if tableView.accessibilityValue == state && tableView.numberOfRows(inSection: 0) == rows { return }
		await Task.yield()
	}
	XCTFail("Timed out waiting for root \(scope.rawValue) state \(state) with \(rows) rows")
}

@MainActor
private func rootTable(for root: Babel2RootViewController, scope: Babel2FeedScope) -> UITableView? {
	descendant(of: root.view, matching: UITableView.self) { tableView in
		tableView.accessibilityIdentifier == "babel2.feeds.table.\(scope.rawValue)"
	}
}

@MainActor
private func waitForLibraryScope(_ provider: FakeDataProvider, _ scope: Babel2FeedScope) async {
	for _ in 0..<100 {
		if await provider.libraryScopes.contains(scope) { return }
		await Task.yield()
	}
	XCTFail("Timed out waiting for library scope \(scope.rawValue)")
}

@MainActor
private func waitForLibraryStart(_ provider: FakeDataProvider, _ scope: Babel2FeedScope, after count: Int) async {
	for _ in 0..<200 {
		if await provider.hasStarted(scope, atLeast: count) { return }
		await Task.yield()
	}
	XCTFail("Timed out waiting for library start \(scope.rawValue) #\(count)")
}

@MainActor
private func waitForSelectedScopeButton(_ button: UIButton) async {
	for _ in 0..<1000 {
		if button.accessibilityValue == "Selected" { return }
		await Task.yield()
	}
	XCTFail("Timed out waiting for scope button selection")
}

@MainActor
private func waitForRenderer(_ renderer: RecordingRenderer) async {
		for _ in 0..<100 {
			if !(await renderer.received.isEmpty) { return }
			await Task.yield()
	}
	XCTFail("Timed out waiting for article renderer")
}

@MainActor
private func waitForRendererStart(_ renderer: SuspendedRenderer) async {
		for _ in 0..<100 {
			if await renderer.didStart { return }
			await Task.yield()
	}
	XCTFail("Timed out waiting for suspended renderer")
}

@MainActor
private func waitForRendererReturn(_ renderer: SuspendedRenderer) async {
		for _ in 0..<100 {
			if await renderer.didReturn { return }
			await Task.yield()
	}
	XCTFail("Timed out waiting for suspended renderer return")
}

@MainActor
private func waitForRelease<Object: AnyObject>(_ reference: WeakReference<Object>) async {
	for _ in 0..<100 {
		if reference.value == nil { return }
		await Task.yield()
	}
	XCTFail("Timed out waiting for controller release")
}

@MainActor
private func descendant<T: UIView>(
	of view: UIView,
	matching type: T.Type,
	where predicate: ((T) -> Bool)? = nil
) -> T? {
	if let match = view as? T, predicate?(match) ?? true { return match }
	for child in view.subviews {
		if let match = descendant(of: child, matching: type, where: predicate) { return match }
	}
	return nil
}

@MainActor
private extension UIView {
	var allSubviews: [UIView] {
		subviews + subviews.flatMap(\.allSubviews)
	}
}
