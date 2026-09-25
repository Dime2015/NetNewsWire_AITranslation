import XCTest
import UIKit
import Babel2Core
import Babel2UI
@testable import NetNewsWire

@MainActor
final class Babel2FeedReaderTests: XCTestCase {
	/// 阅读页测试用固定文章编号；「按单篇文章记忆」存在 UserDefaults 里，每个测试前后清掉。
	override func setUp() async throws {
		try await super.setUp()
		ArticleReadingStateStore.setReaderMode(false, for: "account|reader-article")
		ArticleReadingStateStore.setTranslated(false, for: "account|reader-article")
	}

	override func tearDown() async throws {
		ArticleReadingStateStore.setReaderMode(false, for: "account|reader-article")
		ArticleReadingStateStore.setTranslated(false, for: "account|reader-article")
		try await super.tearDown()
	}

	// MARK: - 文章列表底栏（ADR-023）

	func testFeedToolbarSwitchesScopeInPlaceAndSyncsHome() async throws {
		let feedID = FeedSnapshot.ID(accountID: "account", feedID: "feed")
		let feed = makeFeed(id: feedID, title: "Feed")
		let article = makeArticle(accountID: "account", feedID: "feed", articleID: "a", title: "A", body: "<p>A</p>", url: nil)
		let provider = FakeDataProvider(feeds: [feedID: [article]])
		let navigationController = Babel2SceneComposition.makeRoot(environment: makeEnvironment(provider: provider))
		let root = try XCTUnwrap(navigationController.viewControllers.first as? Babel2RootViewController)
		root.onFeedRequested?(feed, .unread)
		let feedViewController = try XCTUnwrap(navigationController.topViewController as? Babel2FeedViewController)
		feedViewController.loadViewIfNeeded()
		let tableView = try XCTUnwrap(descendant(of: feedViewController.view, matching: UITableView.self))
		await waitForRows(in: tableView, count: 1)

		// 底栏三档：初始选中与首页带进来的档位一致
		let filter = feedViewController.scopeFilterForTesting
		XCTAssertEqual(filter.selectedScope, .unread)
		XCTAssertEqual(filter.buttons[.unread]?.accessibilityValue, "Selected")
		let translation = try XCTUnwrap(descendant(of: feedViewController.view, matching: Babel2TranslationToggle.self))
		XCTAssertTrue(translation.isEnabled, "title translation toggle is wired (ADR-024)")

		// 点「全部」：原地换档位重新加载，首页同步到同一档
		filter.buttons[.all]?.sendActions(for: .touchUpInside)
		XCTAssertEqual(feedViewController.scope, .all)
		await waitForRows(in: tableView, count: 1)
		let requests = await provider.feedScopeRequests
		XCTAssertEqual(requests, [.unread, .all])
		XCTAssertEqual(root.selectedScope, .all, "scope is global: home follows")
		XCTAssertEqual(filter.buttons[.all]?.accessibilityValue, "Selected")
	}

	// MARK: - 标题翻译开关（ADR-024）

	func testTitleTranslationToggleRequestsVisibleTitlesAndShowsFigmaStates() async throws {
		let feedID = FeedSnapshot.ID(accountID: "account", feedID: "feed")
		func article(_ id: String, title: String, translated: String? = nil) -> ArticleSnapshot {
			ArticleSnapshot(id: ArticleSnapshot.ID(accountID: "account", feedID: "feed", articleID: id), title: title, translatedTitle: translated, url: nil, feedID: feedID)
		}
		let list = [
			article("en", title: "An English headline"),
			article("done", title: "Already translated", translated: "已经翻好"),
			article("zh", title: "纯中文标题")
		]
		var enabled = false
		var requested = [[String]]()
		let setting = Babel2TitleTranslationSetting(
			isEnabled: { enabled },
			setEnabled: { enabled = $0 },
			request: { requested.append($0.map(\.articleID)) }
		)
		let provider = FakeDataProvider(feeds: [feedID: list])
		let feedViewController = Babel2FeedViewController(feed: makeFeed(id: feedID, title: "Feed"), scope: .all, environment: makeEnvironment(provider: provider), titleTranslation: setting)
		let window = hostInWindow(feedViewController)
		defer { window.isHidden = true }
		let tableView = try XCTUnwrap(descendant(of: feedViewController.view, matching: UITableView.self))
		await waitForRows(in: tableView, count: 3)
		let toggle = feedViewController.titleTranslationToggleForTesting
		XCTAssertEqual(toggle.displayedText.main, "原")
		XCTAssertTrue(requested.isEmpty, "nothing is requested while off")

		// 打开：只请求屏幕上、还没有译文、且可能需要翻的（英文那条），显示「译 生成中」
		toggle.sendActions(for: .touchUpInside)
		XCTAssertTrue(enabled)
		XCTAssertEqual(requested, [["en"]])
		XCTAssertEqual(toggle.displayedText.main, "译")
		XCTAssertEqual(toggle.displayedText.caption, "生成中")
		// 有译文入库：变成「译 原文」
		NotificationCenter.default.post(name: .babel2TitleTranslationDidChange, object: nil)
		XCTAssertEqual(toggle.displayedText.caption, "原文")
		// 关掉：回到「原 翻译」
		toggle.sendActions(for: .touchUpInside)
		XCTAssertFalse(enabled)
		XCTAssertEqual(toggle.displayedText.main, "原")
		XCTAssertEqual(toggle.displayedText.caption, "翻译")
	}

	func testTitleTranslationSkipsWhenNothingOnScreenNeedsIt() async throws {
		let feedID = FeedSnapshot.ID(accountID: "account", feedID: "feed")
		let list = [ArticleSnapshot(id: ArticleSnapshot.ID(accountID: "account", feedID: "feed", articleID: "zh"), title: "纯中文标题", url: nil, feedID: feedID)]
		var requested = [[ArticleSnapshot.ID]]()
		let setting = Babel2TitleTranslationSetting(isEnabled: { true }, setEnabled: { _ in }, request: { requested.append($0) })
		let feedViewController = Babel2FeedViewController(feed: makeFeed(id: feedID, title: "Feed"), scope: .all, environment: makeEnvironment(provider: FakeDataProvider(feeds: [feedID: list])), titleTranslation: setting)
		let window = hostInWindow(feedViewController)
		defer { window.isHidden = true }
		let tableView = try XCTUnwrap(descendant(of: feedViewController.view, matching: UITableView.self))
		await waitForRows(in: tableView, count: 1)
		feedViewController.requestVisibleTitleTranslationsForTesting()
		XCTAssertTrue(requested.isEmpty, "Chinese-only titles are not sent (no cost, no stuck 生成中)")
		XCTAssertEqual(feedViewController.titleTranslationToggleForTesting.displayedText.caption, "原文")
	}

	func testMarkAllReadConfirmsCountThenMarksWholeFeed() async throws {
		let feedID = FeedSnapshot.ID(accountID: "account", feedID: "feed")
		func article(_ id: String) -> ArticleSnapshot {
			ArticleSnapshot(id: ArticleSnapshot.ID(accountID: "account", feedID: "feed", articleID: id), title: id, url: nil, feedID: feedID)
		}
		let provider = FakeDataProvider(feeds: [feedID: [article("a"), article("b")]])
		let handler = RecordingActionHandler()
		let feedViewController = Babel2FeedViewController(feed: makeFeed(id: feedID, title: "Feed"), scope: .unread, environment: makeEnvironment(provider: provider, actionHandler: handler))
		let window = hostInWindow(feedViewController)
		defer { window.isHidden = true }
		let tableView = try XCTUnwrap(descendant(of: feedViewController.view, matching: UITableView.self))
		await waitForRows(in: tableView, count: 2)

		let readAll = try XCTUnwrap(descendant(of: feedViewController.view, matching: UIButton.self) { $0.accessibilityIdentifier == "babel2.feed.read-all" })
		readAll.sendActions(for: .touchUpInside)
		// 先确认：「将 2 篇文章标为已读？」
		await waitUntil { feedViewController.pendingMarkAllReadCountForTesting == 2 }
		let actionsBefore = await handler.actions
		XCTAssertTrue(actionsBefore.isEmpty, "nothing is marked before confirming")
		feedViewController.presentedViewController?.dismiss(animated: false)
		feedViewController.confirmMarkAllReadForTesting()
		for _ in 0..<100 {
			if await !handler.actions.isEmpty { break }
			try await Task.sleep(for: .milliseconds(20))
		}
		let actions = await handler.actions
		XCTAssertEqual(actions, [.markFeedRead(feedID)], "one batch action for the whole feed")
	}

	// MARK: - 下一篇（Slice 5 第 4 步）

	func testNextArticleFollowsListOrderAndSkipsReadInUnreadScope() async throws {
		let feedID = FeedSnapshot.ID(accountID: "account", feedID: "feed")
		func article(_ id: String, read: Bool) -> ArticleSnapshot {
			ArticleSnapshot(id: ArticleSnapshot.ID(accountID: "account", feedID: "feed", articleID: id), title: id, url: nil, feedID: feedID, isRead: read)
		}
		let list = [article("a", read: false), article("b", read: true), article("c", read: false)]
		func loadedFeed(_ scope: Babel2FeedScope) async throws -> Babel2FeedViewController {
			let provider = FakeDataProvider(feeds: [feedID: list])
			let controller = Babel2FeedViewController(feed: makeFeed(id: feedID, title: "Feed"), scope: scope, environment: makeEnvironment(provider: provider))
			controller.loadViewIfNeeded()
			let tableView = try XCTUnwrap(descendant(of: controller.view, matching: UITableView.self))
			await waitForRows(in: tableView, count: 3)
			return controller
		}
		let unread = try await loadedFeed(.unread)
		XCTAssertEqual(unread.nextArticle(after: list[0].id)?.id.articleID, "c", "unread scope skips already-read b")
		XCTAssertNil(unread.nextArticle(after: list[2].id), "last article has no next")
		let all = try await loadedFeed(.all)
		XCTAssertEqual(all.nextArticle(after: list[0].id)?.id.articleID, "b", "all scope keeps read articles")
	}

	func testNextButtonReplacesReaderInPlaceWithoutGrowingTheStack() async throws {
		let feedID = FeedSnapshot.ID(accountID: "account", feedID: "feed")
		let feed = makeFeed(id: feedID, title: "Feed")
		let first = makeArticle(accountID: "account", feedID: "feed", articleID: "first", title: "First", body: "<p>One</p>", url: nil)
		let second = makeArticle(accountID: "account", feedID: "feed", articleID: "second", title: "Second", body: "<p>Two</p>", url: nil)
		let provider = FakeDataProvider(feeds: [feedID: [first, second]])
		let navigationController = Babel2SceneComposition.makeRoot(environment: makeEnvironment(provider: provider))
		let root = try XCTUnwrap(navigationController.viewControllers.first as? Babel2RootViewController)
		root.onFeedRequested?(feed, .all)
		let feedViewController = try XCTUnwrap(navigationController.topViewController as? Babel2FeedViewController)
		feedViewController.loadViewIfNeeded()
		let tableView = try XCTUnwrap(descendant(of: feedViewController.view, matching: UITableView.self))
		await waitForRows(in: tableView, count: 2)
		feedViewController.tableView(tableView, didSelectRowAt: IndexPath(row: 0, section: 0))
		let firstReader = try XCTUnwrap(navigationController.topViewController as? Babel2ArticleViewController)
		firstReader.loadViewIfNeeded()
		let depth = navigationController.viewControllers.count
		XCTAssertTrue(firstReader.toolbarView.nextButton.isEnabled)

		firstReader.showNextArticle()
		let secondReader = try XCTUnwrap(navigationController.topViewController as? Babel2ArticleViewController)
		XCTAssertFalse(secondReader === firstReader)
		XCTAssertEqual(navigationController.viewControllers.count, depth, "next replaces in place, no stack growth")
		secondReader.loadViewIfNeeded()
		let title = try XCTUnwrap(descendant(of: secondReader.view, matching: UILabel.self) { $0.accessibilityIdentifier == "babel2.article.title" })
		XCTAssertEqual(title.attributedText?.string, "Second")
		// 已是最后一篇：∨ 变灰
		XCTAssertFalse(secondReader.toolbarView.nextButton.isEnabled)
	}

	// MARK: - 内置浏览器（Slice 5 第 3 步）

	func testBrowserMotionProgressAndFinishRule() {
		XCTAssertEqual(Babel2ReaderBrowserMotion.progress(translationX: 0, width: 400), 0)
		XCTAssertEqual(Babel2ReaderBrowserMotion.progress(translationX: -100, width: 400), 0.25)
		XCTAssertEqual(Babel2ReaderBrowserMotion.progress(translationX: -900, width: 400), 1)
		XCTAssertEqual(Babel2ReaderBrowserMotion.progress(translationX: 50, width: 400), 0, "rightward drag never goes negative")
		XCTAssertFalse(Babel2ReaderBrowserMotion.shouldFinish(progress: 0.4, velocityX: 0, width: 400))
		XCTAssertTrue(Babel2ReaderBrowserMotion.shouldFinish(progress: 0.6, velocityX: 0, width: 400))
		// 快速左甩：0.3 + (1200/400)×0.15 = 0.75 → 补完
		XCTAssertTrue(Babel2ReaderBrowserMotion.shouldFinish(progress: 0.3, velocityX: -1200, width: 400))
		// 过半但往回甩：0.6 − (1200/400)×0.15 = 0.15 → 弹回
		XCTAssertFalse(Babel2ReaderBrowserMotion.shouldFinish(progress: 0.6, velocityX: 1200, width: 400))
	}

	func testRightEdgeSwipeCancelLeavesReaderUntouchedAndCommitPushesBrowser() async throws {
		var made = [StubBrowser]()
		let reader = makeReader(body: "<p>Body</p>", makeBrowser: { url in
			let browser = StubBrowser(url: url)
			made.append(browser)
			return browser
		})
		let navigation = Babel2NavigationController(rootViewController: UIViewController())
		let window = hostInWindow(navigation)
		defer { window.isHidden = true }
		navigation.pushBabel2(reader, animated: false)
		navigation.view.layoutIfNeeded()
		await waitForReaderRender(reader)
		let motion = try XCTUnwrap(reader.browserMotionForTesting)
		let width = navigation.view.bounds.width

		// 起手即准备好浏览器（网页在后台开始加载），两页跟手
		XCTAssertTrue(motion.begin())
		let first = try XCTUnwrap(made.last)
		XCTAssertTrue(first.didPrepare)
		motion.update(translationX: -width * 0.3)
		XCTAssertEqual(reader.view.transform.tx, -width * 0.3, accuracy: 0.5)
		XCTAssertEqual(first.view.transform.tx, width * 0.7, accuracy: 0.5)
		// 没过半松手：弹回，浏览器丢弃，阅读页原样
		motion.end(velocityX: 0, cancelled: false)
		motion.finishSettleImmediatelyForTesting()
		XCTAssertTrue(first.didDiscard)
		XCTAssertNil(first.view.superview)
		XCTAssertEqual(reader.view.transform, .identity)
		XCTAssertTrue(navigation.topViewController === reader)

		// 过半松手：补完，浏览器成为当前页
		XCTAssertTrue(motion.begin())
		let second = try XCTUnwrap(made.last)
		motion.update(translationX: -width * 0.7)
		motion.end(velocityX: 0, cancelled: false)
		motion.finishSettleImmediatelyForTesting()
		XCTAssertFalse(second.didDiscard)
		XCTAssertTrue(navigation.topViewController === second)
		XCTAssertEqual(reader.view.transform, .identity)
		XCTAssertEqual(second.url, URL(string: "https://example.com/post"))
	}

	func testLinksAndSourceArrowOpenTheInAppBrowser() async throws {
		var systemOpened = [URL]()
		let reader = makeReader(body: "<p>Body</p>", makeBrowser: { StubBrowser(url: $0) })
		reader.onOpenLink = { systemOpened.append($0) }
		let navigation = Babel2NavigationController(rootViewController: UIViewController())
		let window = hostInWindow(navigation)
		defer { window.isHidden = true }
		navigation.pushBabel2(reader, animated: false)
		navigation.view.layoutIfNeeded()
		await waitForReaderRender(reader)
		// 紧凑栏副标题末尾出现「↗」
		XCTAssertEqual(reader.compactHeaderView.subtitleText, "FEED ↗")
		// 非网页链接（邮件）→ 交给系统，不推新页面
		reader.openLinkForTesting(URL(string: "mailto:someone@example.com")!)
		XCTAssertEqual(systemOpened, [URL(string: "mailto:someone@example.com")!])
		XCTAssertTrue(navigation.topViewController === reader)
		// 网页链接 → 内置浏览器（测试窗口不挂屏幕场景，推入动画不会播完，只检查栈顶）
		reader.openLinkForTesting(URL(string: "https://other.example/story")!)
		let browser = try XCTUnwrap(navigation.topViewController as? StubBrowser)
		XCTAssertEqual(browser.url, URL(string: "https://other.example/story"))
		XCTAssertEqual(systemOpened.count, 1, "web links do not go to the system browser")
	}

	func testBrowserPageShowsChromeAndRetryOnFailure() async throws {
		let browser = Babel2BrowserViewController(url: URL(string: "https://nonexistent.invalid/")!, openExternally: { _ in })
		let window = hostInWindow(browser)
		defer { window.isHidden = true }
		let ids = browser.view.allSubviews.compactMap { ($0 as? UIButton)?.accessibilityIdentifier }
		for id in ["babel2.browser.close", "babel2.browser.back", "babel2.browser.forward", "babel2.browser.reload", "babel2.browser.share", "babel2.browser.safari"] {
			XCTAssertTrue(ids.contains(id), id)
		}
		let back = try XCTUnwrap(descendant(of: browser.view, matching: UIButton.self) { $0.accessibilityIdentifier == "babel2.browser.back" })
		XCTAssertFalse(back.isEnabled, "no history yet")
		// 打不开的地址：显示原因 + 重试
		for _ in 0..<200 {
			if browser.isShowingErrorForTesting { break }
			try await Task.sleep(for: .milliseconds(50))
		}
		XCTAssertTrue(browser.isShowingErrorForTesting)
	}

	// MARK: - 阅读模式（Slice 5 第 2 步）

	func testReaderModeSwapsToFullTextRemembersAndReturnsToOriginal() async throws {
		var requested = [URL]()
		let viewController = makeReader(body: "<p>Summary only.</p>", fullTextProvider: { url, _ in
			requested.append(url)
			return "<p>The complete article text.</p><p>Second paragraph.</p>"
		})
		let window = hostInWindow(viewController)
		defer { window.isHidden = true }
		await waitForReaderRender(viewController)
		let readingModeButton = viewController.toolbarView.readingModeButton
		XCTAssertEqual(readingModeButton.accessibilityValue, "off")
		XCTAssertTrue(readingModeButton.isEnabled)
		let scrollView = viewController.readerContentView.scrollView
		scrollView.contentOffset.y += 5

		// 底栏第 4 格「阅读模式」一点即开（ADR-020）
		readingModeButton.sendActions(for: .touchUpInside)
		await waitUntil { viewController.isReaderModeOn }
		await waitUntil { viewController.lastRenderResult?.textLength ?? 0 > 30 }
		let fullText = await viewController.readerContentView.articleTextForTesting()
		XCTAssertTrue(fullText?.contains("The complete article text.") == true)
		XCTAssertEqual(requested, [URL(string: "https://example.com/post")!])
		XCTAssertEqual(readingModeButton.accessibilityValue, "on")
		XCTAssertNil(viewController.statusTextForTesting)
		XCTAssertEqual(scrollView.contentOffset.y, -scrollView.adjustedContentInset.top, accuracy: 0.5, "switching scrolls to top")
		XCTAssertTrue(ArticleReadingStateStore.state(for: "account|reader-article").readerMode)

		// 关掉：回到订阅源自带的正文，并忘掉记忆
		viewController.toggleReaderMode()
		await waitUntil { viewController.lastRenderResult?.textLength ?? 99 < 30 }
		let original = await viewController.readerContentView.articleTextForTesting()
		XCTAssertEqual(original, "Summary only.")
		XCTAssertFalse(viewController.isReaderModeOn)
		XCTAssertFalse(ArticleReadingStateStore.state(for: "account|reader-article").readerMode)
	}

	func testFeedAlwaysReaderModeOpensFullTextWithoutPerArticleMemory() async throws {
		var feedSetting = true
		let setting = Babel2FeedReaderModeSetting(isAlwaysOn: { feedSetting }, setAlwaysOn: { feedSetting = $0 })
		let viewController = makeReader(body: "<p>Summary only.</p>", fullTextProvider: { _, _ in
			"<p>Full text because the feed always uses reading mode.</p>"
		}, feedReaderModeSetting: setting)
		let window = hostInWindow(viewController)
		defer { window.isHidden = true }
		// 订阅源开着「总是用阅读模式」：打开即取全文，零操作
		await waitUntil { viewController.isReaderModeOn }
		XCTAssertEqual(viewController.toolbarView.readingModeButton.accessibilityValue, "on")
		// 因订阅源设置自动打开的，不记到单篇文章上
		XCTAssertFalse(ArticleReadingStateStore.state(for: "account|reader-article").readerMode)
		XCTAssertEqual(viewController.moreMenuItemIdentifiers, ["babel2.article.feed-always-reading-mode", "babel2.article.open-original", "babel2.article.long-image"])
		XCTAssertEqual(viewController.moreMenuFeedAlwaysReaderModeState, .on)
		// 菜单里关掉订阅源开关：写回设置，当前文章保持全文
		viewController.toggleFeedAlwaysReaderMode()
		XCTAssertFalse(feedSetting)
		XCTAssertEqual(viewController.moreMenuFeedAlwaysReaderModeState, .off)
		XCTAssertTrue(viewController.isReaderModeOn)
	}

	func testTurningOnFeedAlwaysReaderModeFetchesCurrentArticle() async throws {
		var feedSetting = false
		let setting = Babel2FeedReaderModeSetting(isAlwaysOn: { feedSetting }, setAlwaysOn: { feedSetting = $0 })
		let viewController = makeReader(body: "<p>Summary only.</p>", fullTextProvider: { _, _ in
			"<p>Full text after turning on the feed setting.</p>"
		}, feedReaderModeSetting: setting)
		let window = hostInWindow(viewController)
		defer { window.isHidden = true }
		await waitForReaderRender(viewController)
		XCTAssertFalse(viewController.isReaderModeOn)
		viewController.toggleFeedAlwaysReaderMode()
		XCTAssertTrue(feedSetting)
		await waitUntil { viewController.isReaderModeOn }
	}

	func testReaderModeFailureKeepsOriginalAndShowsStatus() async throws {
		struct Blocked: Error {}
		let viewController = makeReader(body: "<p>Summary only.</p>", fullTextProvider: { _, _ in
			try await Task.sleep(for: .milliseconds(200))
			throw Blocked()
		})
		let window = hostInWindow(viewController)
		defer { window.isHidden = true }
		await waitForReaderRender(viewController)
		viewController.toggleReaderMode()
		// 获取中：署名下方一行状态字，正文照常
		XCTAssertEqual(viewController.statusTextForTesting, Babel2Localization.text(.fetchingFullText))
		await waitUntil { !viewController.isFetchingFullTextForTesting }
		XCTAssertEqual(viewController.statusTextForTesting, Babel2Localization.text(.unableToFetchFullText))
		XCTAssertFalse(viewController.isReaderModeOn)
		let text = await viewController.readerContentView.articleTextForTesting()
		XCTAssertEqual(text, "Summary only.")
		XCTAssertFalse(ArticleReadingStateStore.state(for: "account|reader-article").readerMode)
	}

	func testReaderModeIsRestoredWhenReopeningTheArticle() async throws {
		ArticleReadingStateStore.setReaderMode(true, for: "account|reader-article")
		let viewController = makeReader(body: "<p>Summary only.</p>", fullTextProvider: { _, _ in
			"<p>Remembered full text for this article.</p>"
		})
		let window = hostInWindow(viewController)
		defer { window.isHidden = true }
		await waitUntil { viewController.isReaderModeOn }
		await waitUntil { viewController.lastRenderResult?.textLength ?? 0 > 30 }
		let text = await viewController.readerContentView.articleTextForTesting()
		XCTAssertEqual(text, "Remembered full text for this article.")
	}

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
		let window = hostInWindow(articleViewController)
		defer { window.isHidden = true }
		await waitForRenderer(renderer)
		let receivedArticles = await renderer.received
		XCTAssertEqual(receivedArticles, [articleA])
		await waitForReaderRender(articleViewController)
		let bodyText = await articleViewController.readerContentView.articleTextForTesting()
		XCTAssertEqual(bodyText, "Only account A")
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
		for _ in 0..<20 { await Task.yield() }

		// 渲染结果属于别的文章 → 被丢弃，正文从未开始排版
		XCTAssertEqual(viewController.readerContentView.renderState, .idle)
		XCTAssertNil(viewController.lastRenderResult)
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
		var retainedContentView: Babel2ReaderContentView?

		do {
			let viewController = Babel2ArticleViewController(article: article, environment: environment)
			controllerReference = WeakReference(viewController)
			viewController.loadViewIfNeeded()
			await waitForRendererStart(renderer)
			retainedContentView = viewController.readerContentView
		}

		let reference = try XCTUnwrap(controllerReference)
		await waitForRelease(reference)
		let rendererDidStart = await renderer.didStart
		XCTAssertTrue(rendererDidStart)
		await renderer.resume()
		await waitForRendererReturn(renderer)
		let rendererTaskWasCancelled = await renderer.taskWasCancelled
		XCTAssertTrue(rendererTaskWasCancelled)
		XCTAssertEqual(retainedContentView?.renderState, .idle)
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
		// 「打开原文」在「•••」菜单里（ADR-018），在内置浏览器打开（ADR-021）
		XCTAssertTrue(articleViewController.moreMenuHasOpenOriginal)
		articleViewController.openOriginalFromMenuForTesting()
		let browser = try XCTUnwrap(navigationController.topViewController as? Babel2BrowserViewController)
		XCTAssertEqual(browser.initialURLForTesting, article.url)
		// 浏览器底栏「在 Safari 中打开」交给系统
		browser.loadViewIfNeeded()
		let safari = try XCTUnwrap(descendant(of: browser.view, matching: UIButton.self) { $0.accessibilityIdentifier == "babel2.browser.safari" })
		safari.sendActions(for: .touchUpInside)
		XCTAssertEqual(openedURL, article.url)
		navigationController.popBabel2(animated: false)

		let bodyOnlyArticle = ArticleSnapshot(
			id: ArticleSnapshot.ID(accountID: feedID.accountID, feedID: feedID.feedID, articleID: "body-only"),
			title: "Body only",
			content: "<p>Cached body</p>",
			url: nil,
			feedID: feedID
		)
		let bodyOnlyViewController = Babel2ArticleViewController(article: bodyOnlyArticle, environment: environment)
		bodyOnlyViewController.loadViewIfNeeded()
		XCTAssertFalse(bodyOnlyViewController.moreMenuHasOpenOriginal)
		XCTAssertFalse(bodyOnlyViewController.toolbarView.readingModeButton.isEnabled, "no reading mode without an original URL")
		XCTAssertEqual(bodyOnlyViewController.moreMenuItemIdentifiers, ["babel2.article.long-image"])
		let moreButton = try XCTUnwrap(descendant(of: bodyOnlyViewController.view, matching: UIButton.self) { $0.accessibilityIdentifier == "babel2.article.more" })
		// 菜单里始终有「生成长图」（第 5 步前为灰色占位），所以 ••• 本身可以打开
		XCTAssertTrue(moreButton.isEnabled)
	}

	// MARK: - 文章列表随状态变化原地刷新（2026-09-24）

	func testFeedListUpdatesReadStateInPlaceWithoutRemovingRows() async throws {
		let feedID = FeedSnapshot.ID(accountID: "account", feedID: "feed")
		func article(_ id: String, read: Bool, starred: Bool = false) -> ArticleSnapshot {
			ArticleSnapshot(
				id: ArticleSnapshot.ID(accountID: "account", feedID: "feed", articleID: id),
				title: "Article \(id)",
				url: nil,
				feedID: feedID,
				isRead: read,
				isStarred: starred
			)
		}
		let provider = FakeDataProvider(feeds: [feedID: [article("a", read: false), article("b", read: false), article("c", read: false)]])
		let feedViewController = Babel2FeedViewController(feed: makeFeed(id: feedID, title: "Feed"), scope: .unread, environment: makeEnvironment(provider: provider))
		let window = hostInWindow(feedViewController)
		defer { window.isHidden = true }
		let tableView = try XCTUnwrap(descendant(of: feedViewController.view, matching: UITableView.self))
		await waitForRows(in: tableView, count: 3)

		// 数据库里：b 被标为已读并加星，c 已不在（例如未读档下被读掉后的新查询结果不含它）
		await provider.setFeedArticles([article("a", read: false), article("b", read: true, starred: true)], for: feedID)
		NotificationCenter.default.post(name: .babel2LibraryDidChange, object: nil)
		NotificationCenter.default.post(name: .babel2LibraryDidChange, object: nil)
		await waitUntil { feedViewController.articlesForTesting.map(\.isRead) == [false, true, false] }

		// 行数、顺序不变；b 原地变成已读；缺失的 c 保持原样不被删掉
		XCTAssertEqual(feedViewController.articlesForTesting.map(\.id.articleID), ["a", "b", "c"])
		XCTAssertEqual(tableView.numberOfRows(inSection: 0), 3)
		XCTAssertTrue(feedViewController.articlesForTesting[1].isStarred)
		let bCell = try XCTUnwrap(tableView.cellForRow(at: IndexPath(row: 1, section: 0)))
		let bTitle = try XCTUnwrap(descendant(of: bCell.contentView, matching: UILabel.self) { $0.text == "Article b" })
		XCTAssertEqual(bTitle.font.fontDescriptor.object(forKey: .traits).flatMap { ($0 as? [UIFontDescriptor.TraitKey: Any])?[.weight] as? CGFloat } ?? 0, UIFont.Weight.regular.rawValue, accuracy: 0.01)
		// 两次通知被合并成一次刷新：初次加载 1 次 + 刷新 1 次
		let requests = await provider.feedScopeRequests
		XCTAssertEqual(requests, [.unread, .all])
	}

	/// 真实使用场景：状态变化发生时列表被阅读页盖住，返回后才露出来。
	func testFeedListRepaintsRowsChangedWhileCoveredByReader() async throws {
		let feedID = FeedSnapshot.ID(accountID: "account", feedID: "feed")
		func article(_ id: String, read: Bool) -> ArticleSnapshot {
			ArticleSnapshot(
				id: ArticleSnapshot.ID(accountID: "account", feedID: "feed", articleID: id),
				title: "Article \(id)",
				url: nil,
				feedID: feedID,
				isRead: read
			)
		}
		let provider = FakeDataProvider(feeds: [feedID: [article("a", read: false), article("b", read: false)]])
		let feedViewController = Babel2FeedViewController(feed: makeFeed(id: feedID, title: "Feed"), scope: .unread, environment: makeEnvironment(provider: provider))
		let navigation = UINavigationController(rootViewController: feedViewController)
		let window = hostInWindow(navigation)
		defer { window.isHidden = true }
		let tableView = try XCTUnwrap(descendant(of: feedViewController.view, matching: UITableView.self))
		await waitForRows(in: tableView, count: 2)

		// 进入「阅读页」盖住列表
		navigation.pushViewController(UIViewController(), animated: false)
		navigation.view.layoutIfNeeded()
		XCTAssertNil(feedViewController.view.window, "list is covered")
		await provider.setFeedArticles([article("a", read: true), article("b", read: false)], for: feedID)
		NotificationCenter.default.post(name: .babel2LibraryDidChange, object: nil)
		await waitUntil { feedViewController.articlesForTesting.first?.isRead == true }

		// 返回列表：a 的标题必须已经是常规字重
		navigation.popViewController(animated: false)
		navigation.view.layoutIfNeeded()
		let aCell = try XCTUnwrap(tableView.cellForRow(at: IndexPath(row: 0, section: 0)))
		let aTitle = try XCTUnwrap(descendant(of: aCell.contentView, matching: UILabel.self) { $0.text == "Article a" })
		let weight = (aTitle.font.fontDescriptor.object(forKey: .traits) as? [UIFontDescriptor.TraitKey: Any])?[.weight] as? CGFloat
		XCTAssertEqual(weight ?? -1, UIFont.Weight.regular.rawValue, accuracy: 0.01, "row changed while covered must repaint on return")
	}

	// MARK: - 阅读页翻译（Slice 5 第 1 步）

	func testTranslationBridgeReadsBodyAndHiddenTitleAndAppliesTranslation() async throws {
		let viewController = makeReader(body: "<h1>Inner heading</h1><p>Hello world.</p><p>Second paragraph.</p>")
		let window = hostInWindow(viewController)
		defer { window.isHidden = true }
		await waitForReaderRender(viewController)

		// 翻译引擎读到的正文是我们的正文容器；标题来自隐藏标题元素，而不是正文里的 h1
		let body = try await viewController.nnwTranslationReadBody()
		XCTAssertEqual(body, "<h1>Inner heading</h1><p>Hello world.</p><p>Second paragraph.</p>")
		let title = try await viewController.nnwTranslationReadTitle()
		XCTAssertEqual(title, "Reader")

		// 标题译文：同步到原生大标题与紧凑栏
		let titleApplied = try await viewController.nnwTranslationApplyTitle("读者")
		XCTAssertTrue(titleApplied)
		let nativeTitle = try XCTUnwrap(descendant(of: viewController.view, matching: UILabel.self) { $0.accessibilityIdentifier == "babel2.article.title" })
		XCTAssertEqual(nativeTitle.attributedText?.string, "读者")
		let compactTitle = try XCTUnwrap(descendant(of: viewController.view, matching: UILabel.self) { $0.accessibilityIdentifier == "babel2.article.compact-title" })
		XCTAssertEqual(compactTitle.text, "读者")
		// 正文里的 h1 没被当成标题改掉
		let bodyAfterTitle = try await viewController.nnwTranslationReadBody()
		XCTAssertTrue(bodyAfterTitle?.contains("Inner heading") == true)

		// 正文译文替换，再切回原文
		let applied = try await viewController.nnwTranslationApply("<p>你好世界。</p>")
		XCTAssertTrue(applied)
		let translatedText = await viewController.readerContentView.articleTextForTesting()
		XCTAssertEqual(translatedText, "你好世界。")
		let showing = try await viewController.nnwTranslationIsShowingTranslation()
		XCTAssertTrue(showing)
		let restored = try await viewController.nnwTranslationRestore()
		XCTAssertTrue(restored)
		let originalText = await viewController.readerContentView.articleTextForTesting()
		XCTAssertTrue(originalText?.contains("Hello world.") == true)
		XCTAssertEqual(nativeTitle.attributedText?.string, "Reader", "restore returns the native title to the original")
	}

	func testTranslateButtonEnablesOnlyWhenPageAndArticleAreReady() async throws {
		// 取不到文章对象：正文排好了按钮也保持不可点
		let withoutArticle = makeReader(body: "<p>Body</p>")
		let window1 = hostInWindow(withoutArticle)
		await waitForReaderRender(withoutArticle)
		try await Task.sleep(for: .milliseconds(200))
		XCTAssertFalse(withoutArticle.toolbarView.translationToggle.isEnabled)
		XCTAssertFalse(withoutArticle.isTranslationReadyForTesting)
		window1.isHidden = true

		// 取得到：正文排好后可点，初始为「原文」状态
		let withArticle = makeReader(body: "<p>Body</p>", hostArticle: NSObject())
		let window2 = hostInWindow(withArticle)
		defer { window2.isHidden = true }
		await waitForReaderRender(withArticle)
		await waitUntil { withArticle.isTranslationReadyForTesting }
		XCTAssertTrue(withArticle.toolbarView.translationToggle.isEnabled)
		XCTAssertEqual(withArticle.toolbarView.translationToggle.accessibilityValue, "original")
	}

	func testTranslationToggleMatchesFigmaTextStates() {
		let toolbar = Babel2ReaderToolbarView()
		toolbar.setTranslationAvailable(true)
		// Figma Translation Toggle：原文「原 翻译」、翻译中「译 生成中」、已译「译 原文」；失败「原 重试」
		let expected: [(TranslationButtonState, String, String, String, String)] = [
			(.original, "原", "翻译", "original", Babel2Localization.text(.translate)),
			(.cachedAvailable, "原", "翻译", "cached", Babel2Localization.text(.translate)),
			(.partialCacheAvailable, "原", "翻译", "partial", Babel2Localization.text(.translate)),
			(.working, "译", "生成中", "working", Babel2Localization.text(.cancelTranslation)),
			(.translated, "译", "原文", "translated", Babel2Localization.text(.showOriginal)),
			(.failed, "原", "重试", "failed", Babel2Localization.text(.translate))
		]
		let toggle = toolbar.translationToggle
		for (state, main, caption, value, label) in expected {
			toolbar.setTranslationState(state)
			XCTAssertEqual(toggle.displayedText.main, main)
			XCTAssertEqual(toggle.displayedText.caption, caption)
			XCTAssertEqual(toggle.accessibilityValue, value)
			XCTAssertEqual(toggle.accessibilityLabel, label)
			XCTAssertTrue(toggle.isEnabled, "\(value) stays tappable (working = cancel)")
		}
	}

	func testReaderChromeUsesFigmaGeometryAndIcons() async throws {
		let viewController = makeReader(body: "<p>Body</p>", author: "John Gruber")
		let window = hostInWindow(viewController)
		defer { window.isHidden = true }
		// 顶栏：✕ / ••• / 分享，中心 x = 32 / 201 / 370，中心 y 距顶栏顶 22
		let buttons = viewController.topBarButtons
		XCTAssertEqual(buttons.map(\.accessibilityIdentifier), ["babel2.article.back", "babel2.article.more", "babel2.article.share"])
		let centers = buttons.map { $0.superview!.convert($0.center, to: nil) }
		let barTop = try XCTUnwrap(buttons.first?.superview).convert(CGPoint.zero, to: nil).y
		for (center, expectedX) in zip(centers, [32, 201, 370] as [CGFloat]) {
			XCTAssertEqual(center.x, expectedX, accuracy: 0.5)
			XCTAssertEqual(center.y - barTop, 22, accuracy: 0.5)
		}
		// 底栏：设计稿图标资源、翻译开关 58×44
		let toolbar = viewController.toolbarView
		XCTAssertEqual(toolbar.starIconName, "Babel2ReaderStar")
		XCTAssertNotNil(toolbar.readButton.image(for: .normal))
		XCTAssertEqual(toolbar.translationToggle.bounds.size, CGSize(width: 58, height: 44))
		// 署名两行：作者 / 订阅源（大写）
		let byline = try XCTUnwrap(descendant(of: viewController.view, matching: UILabel.self) { $0.accessibilityIdentifier == "babel2.article.byline" })
		XCTAssertEqual(byline.text, "JOHN GRUBER\nFEED")
		let subtitle = try XCTUnwrap(descendant(of: viewController.view, matching: UILabel.self) { $0.accessibilityIdentifier == "babel2.article.compact-subtitle" })
		XCTAssertEqual(subtitle.text, "FEED · JOHN GRUBER")
		// 正文为次要灰（设计稿 #787878），不是主墨色
		await waitForReaderRender(viewController)
		let color = await viewController.readerContentView.evaluateForTesting(
			"return getComputedStyle(document.querySelector('#babel2-article p')).color;"
		) as? String
		// 与当前外观（浅色 #787878 / 深色 #6C6C6C）下的次要灰一致
		var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
		BabelPalette.mutedInk.resolvedColor(with: viewController.view.traitCollection).getRed(&r, green: &g, blue: &b, alpha: &a)
		XCTAssertEqual(color, "rgb(\(Int((r * 255).rounded())), \(Int((g * 255).rounded())), \(Int((b * 255).rounded())))")
	}

	// MARK: - 阅读页（Slice 4 第 1 步）

	func testReaderHeaderIsVisibleBeforeBodyRenders() async throws {
		let feedID = FeedSnapshot.ID(accountID: "account", feedID: "feed")
		let article = ArticleSnapshot(
			id: ArticleSnapshot.ID(accountID: "account", feedID: "feed", articleID: "article"),
			title: "Header first",
			content: "<p>Body</p>",
			url: nil,
			feedID: feedID,
			publishedAt: Date(timeIntervalSince1970: 1_790_000_000)
		)
		let renderer = SuspendedRenderer()
		let viewController = Babel2ArticleViewController(
			article: article,
			environment: makeEnvironment(provider: FakeDataProvider(), renderer: renderer),
			feedTitle: "Example Feed"
		)
		let window = hostInWindow(viewController)
		defer { window.isHidden = true }
		await waitForRendererStart(renderer)

		// 正文还卡在加载中，标题区已经在正文上方显示
		let title = try XCTUnwrap(descendant(of: viewController.view, matching: UILabel.self) { $0.accessibilityIdentifier == "babel2.article.title" })
		let byline = try XCTUnwrap(descendant(of: viewController.view, matching: UILabel.self) { $0.accessibilityIdentifier == "babel2.article.byline" })
		let date = try XCTUnwrap(descendant(of: viewController.view, matching: UILabel.self) { $0.accessibilityIdentifier == "babel2.article.date" })
		XCTAssertEqual(title.attributedText?.string, "Header first")
		XCTAssertEqual(byline.text, "EXAMPLE FEED")
		XCTAssertFalse(date.isHidden)
		XCTAssertNil(viewController.lastRenderResult)
		let header = try XCTUnwrap(title.superview?.superview)
		XCTAssertGreaterThan(header.bounds.height, 40)
		XCTAssertLessThan(header.frame.maxY, 0.5, "header sits above the body content")
		let scrollView = viewController.readerContentView.scrollView
		XCTAssertEqual(scrollView.contentInset.top, header.bounds.height, accuracy: 0.5)
		await renderer.resume()
	}

	func testReaderStripsScriptsEventHandlersAndScriptLinks() async throws {
		let viewController = makeReader(body: """
		<p>Safe text</p>
		<script>document.title = 'script-ran';</script>
		<img id="broken" src="https://invalid.invalid/x.png" onerror="document.title = 'handler-ran'">
		<a id="bad" href="javascript:document.title='link'">bad link</a>
		<p style="width: 2000px" class="evil">Styled</p>
		""")
		let window = hostInWindow(viewController)
		defer { window.isHidden = true }
		await waitForReaderRender(viewController)

		let result = await viewController.readerContentView.evaluateForTesting("""
		const root = document.getElementById('babel2-article');
		return [
			root.querySelectorAll('script').length,
			root.querySelectorAll('[onerror]').length,
			root.querySelector('#bad').hasAttribute('href') ? 1 : 0,
			root.querySelectorAll('[style], [class]').length,
			document.title
		].join('|');
		""") as? String
		XCTAssertEqual(result, "0|0|0|0|")
		let text = await viewController.readerContentView.articleTextForTesting()
		XCTAssertTrue(text?.contains("Safe text") == true)
	}

	func testLandscapeImageBleedsAndPortraitImageKeepsInset() async throws {
		let wide = pngDataURI(size: CGSize(width: 800, height: 400))
		let tall = pngDataURI(size: CGSize(width: 300, height: 600))
		let viewController = makeReader(body: "<p>Text</p><img id=\"wide\" src=\"\(wide)\"><img id=\"tall\" src=\"\(tall)\">")
		let window = hostInWindow(viewController)
		defer { window.isHidden = true }
		await waitForReaderRender(viewController)
		XCTAssertEqual(viewController.lastRenderResult?.imageCount, 2)

		var classes: String?
		for _ in 0..<100 {
			classes = await viewController.readerContentView.evaluateForTesting("""
			const wide = document.getElementById('wide');
			const tall = document.getElementById('tall');
			if (!wide.complete || !tall.complete) { return null; }
			return wide.className + '|' + tall.className + '|' + Math.round(wide.getBoundingClientRect().width) + '|' + Math.round(window.innerWidth);
			""") as? String
			if classes?.hasPrefix("babel2-bleed") == true { break }
			try await Task.sleep(for: .milliseconds(50))
		}
		let parts = try XCTUnwrap(classes).split(separator: "|", omittingEmptySubsequences: false).map(String.init)
		XCTAssertEqual(parts[0], "babel2-bleed")
		XCTAssertEqual(parts[1], "")
		XCTAssertEqual(parts[2], parts[3], "landscape image spans the full viewport width")
	}

	func testEmptyBodyShowsNoContentMessage() async throws {
		let viewController = makeReader(body: "")
		let window = hostInWindow(viewController)
		defer { window.isHidden = true }
		await waitForReaderRender(viewController)
		XCTAssertEqual(viewController.lastRenderResult?.isEmpty, true)
		let message = try XCTUnwrap(descendant(of: viewController.view, matching: UILabel.self) { $0.accessibilityIdentifier == "babel2.article.message" })
		XCTAssertEqual(message.text, Babel2Localization.text(.noArticleContent))
		XCTAssertFalse(message.superview?.isHidden ?? true)
	}

	func testPlainTextBodyBecomesParagraphs() async throws {
		let viewController = makeReader(body: "First paragraph.\n\nSecond paragraph.")
		let window = hostInWindow(viewController)
		defer { window.isHidden = true }
		await waitForReaderRender(viewController)
		let count = await viewController.readerContentView.evaluateForTesting(
			"return document.querySelectorAll('#babel2-article > p').length;"
		) as? NSNumber
		XCTAssertEqual(count?.intValue, 2)
	}

	func testReaderLinkDecisions() {
		let base = URL(string: "https://example.com/post")
		func decide(_ link: Bool, _ mainFrame: Bool, _ url: String?, loaded: Bool = true) -> Babel2ReaderContentView.LinkDecision {
			Babel2ReaderContentView.linkDecision(
				isLinkActivation: link,
				isMainFrame: mainFrame,
				url: url.flatMap(URL.init(string:)),
				shellIsLoaded: loaded,
				shellBaseURL: base
			)
		}
		let external = URL(string: "https://other.example/page")!
		XCTAssertEqual(decide(true, true, "https://other.example/page"), .cancelAndOpenExternally(external))
		XCTAssertEqual(decide(true, false, "https://other.example/page"), .cancelAndOpenExternally(external))
		XCTAssertEqual(decide(true, true, "https://example.com/post#section"), .allow)
		XCTAssertEqual(decide(true, true, "javascript:alert(1)"), .cancel)
		XCTAssertEqual(decide(false, true, "https://example.com/post", loaded: false), .allow)
		XCTAssertEqual(decide(false, true, "https://redirect.example/"), .cancel)
		XCTAssertEqual(decide(false, false, "https://www.youtube.com/embed/x"), .allow)
	}

	// MARK: - 阅读页滑动收缩（Slice 4 第 2 步）

	func testChromeProgressFormulas() {
		let progress = Babel2ReaderChromeProgress(collapseStart: 40, collapseDistance: 70, maxScroll: 1040)
		XCTAssertTrue(progress.isEligible)
		XCTAssertEqual(progress.pCollapse(scrolled: 0), 0)
		XCTAssertEqual(progress.pCollapse(scrolled: 40), 0)
		XCTAssertEqual(progress.pCollapse(scrolled: 75), 0.5, accuracy: 0.0001)
		XCTAssertEqual(progress.pCollapse(scrolled: 110), 1)
		XCTAssertEqual(progress.pCollapse(scrolled: 5000), 1)
		XCTAssertEqual(progress.pReading(scrolled: 40), 0)
		XCTAssertEqual(progress.pReading(scrolled: 540), 0.5, accuracy: 0.0001)
		XCTAssertEqual(progress.pReading(scrolled: 1040), 1)
		XCTAssertEqual(progress.pReading(scrolled: 1200), 1, "rubber-band overscroll stays clamped")
		XCTAssertEqual(Babel2ReaderChromeProgress.state(pCollapse: 0), .expanded)
		XCTAssertEqual(Babel2ReaderChromeProgress.state(pCollapse: 0.3), .collapsing)
		XCTAssertEqual(Babel2ReaderChromeProgress.state(pCollapse: 1), .compactPinned)

		// 短文：最多只能滚到收缩起点之前 → 永远不收缩、圆环永远为 0
		let short = Babel2ReaderChromeProgress(collapseStart: 40, maxScroll: 30)
		XCTAssertFalse(short.isEligible)
		XCTAssertEqual(short.pCollapse(scrolled: 30), 0)
		XCTAssertEqual(short.pReading(scrolled: 30), 0)
		let empty = Babel2ReaderChromeProgress(collapseStart: 40, maxScroll: -200)
		XCTAssertFalse(empty.isEligible)
	}

	func testLongArticleCollapsesContinuouslyAndRingTracksReading() async throws {
		let paragraphs = (1...80).map { "<p>Paragraph \($0) with enough words to wrap across the reading column.</p>" }.joined()
		let recorder = RecordingMotionRecorder()
		let viewController = makeReader(body: paragraphs, motionRecorder: recorder)
		let window = hostInWindow(viewController)
		defer { window.isHidden = true }
		await waitForReaderRender(viewController)
		await waitForScrollableLength(viewController, atLeast: 1500)

		let compact = viewController.compactHeaderView
		let scrollView = viewController.readerContentView.scrollView
		// 刚进文章：停在顶部，且还没有任何收缩打点
		XCTAssertEqual(scrollView.contentOffset.y, -scrollView.adjustedContentInset.top, accuracy: 0.5)
		XCTAssertTrue(recorder.events.isEmpty)
		let progress = viewController.chromeProgress
		XCTAssertTrue(progress.isEligible)
		XCTAssertGreaterThan(progress.collapseStart, 0)
		func scroll(to scrolled: CGFloat) {
			scrollView.contentOffset = CGPoint(x: 0, y: scrolled - scrollView.adjustedContentInset.top)
		}

		// 刚进来：展开态，紧凑栏不出现
		scroll(to: 0)
		XCTAssertEqual(compact.pCollapse, 0)
		XCTAssertTrue(compact.isHidden)

		// 收缩到一半：紧凑栏半透明出现，圆环还没开始走多少
		scroll(to: progress.collapseStart + progress.collapseDistance / 2)
		XCTAssertEqual(compact.pCollapse, 0.5, accuracy: 0.01)
		XCTAssertFalse(compact.isHidden)
		XCTAssertEqual(compact.textLayer.alpha, 0.5, accuracy: 0.01)

		// 滑过收缩距离：固定
		scroll(to: progress.collapseStart + progress.collapseDistance + 10)
		XCTAssertEqual(compact.pCollapse, 1)
		XCTAssertEqual(compact.textLayer.transform, .identity)

		// 读到一半、读到底：圆环连续跟随
		let midReading = progress.collapseStart + (progress.maxScroll - progress.collapseStart) / 2
		scroll(to: midReading)
		XCTAssertEqual(compact.pReading, 0.5, accuracy: 0.01)
		scroll(to: progress.maxScroll)
		XCTAssertEqual(compact.pReading, 1, accuracy: 0.001)

		// 往回滑：经过收缩中，倒着走回展开态
		scroll(to: progress.collapseStart + progress.collapseDistance / 4)
		XCTAssertEqual(compact.pCollapse, 0.25, accuracy: 0.01)
		scroll(to: 0)
		XCTAssertEqual(compact.pCollapse, 0)
		XCTAssertTrue(compact.isHidden)
		// 一帧直接从展开甩到固定（快速甩动），再直接回顶
		scroll(to: progress.collapseStart + progress.collapseDistance * 3)
		scroll(to: 0)

		// 打点只记状态切换，且区间成对：收缩中=开始，离开收缩中=结束，直接跳跃=单点事件
		let transitions = recorder.events.compactMap { event -> String? in
			// 只看收缩状态；顶/底栏显隐（controlsChanging）另有测试
			if case .readerChrome(let payload)? = event.typedPayload, payload.state != .controlsChanging {
				return "\(payload.state.rawValue):\(event.phase.rawValue)"
			}
			return nil
		}
		XCTAssertEqual(transitions, [
			"collapsing:begin", "compactPinned:end",
			"collapsing:begin", "expanded:end",
			"compactPinned:event", "expanded:event"
		])
	}

	func testShortArticleNeverShowsCompactHeader() async throws {
		let viewController = makeReader(body: "<p>Short.</p>")
		let window = hostInWindow(viewController)
		defer { window.isHidden = true }
		await waitForReaderRender(viewController)
		try await Task.sleep(for: .milliseconds(300))
		XCTAssertFalse(viewController.chromeProgress.isEligible)
		let scrollView = viewController.readerContentView.scrollView
		// 即使被拉动（橡皮筋回弹）也不出现
		scrollView.contentOffset = CGPoint(x: 0, y: 200)
		XCTAssertEqual(viewController.compactHeaderView.pCollapse, 0)
		XCTAssertTrue(viewController.compactHeaderView.isHidden)
	}

	// MARK: - 阅读页底栏与显隐（Slice 4 第 3 步）

	func testBarVisibilityRules() {
		var bars = Babel2ReaderBarVisibility()
		// 没固定：怎么滑都显示
		bars.update(delta: 200, isPinned: false, isBottomOverscroll: false)
		XCTAssertEqual(bars.barP, 0)
		// 固定后，小于 12pt 不动
		bars.update(delta: 5, isPinned: true, isBottomOverscroll: false)
		bars.update(delta: 6, isPinned: true, isBottomOverscroll: false)
		XCTAssertEqual(bars.barP, 0)
		XCTAssertFalse(bars.isTracking)
		// 越过 12pt 后只计越过的部分：累计 41 → 越过 29 → 29/60
		bars.update(delta: 30, isPinned: true, isBottomOverscroll: false)
		XCTAssertTrue(bars.isTracking)
		XCTAssertEqual(bars.barP, 29 / 60, accuracy: 0.0001)
		bars.update(delta: 100, isPinned: true, isBottomOverscroll: false)
		XCTAssertEqual(bars.barP, 1)
		// 小幅反向（<12pt）不动，防闪烁
		bars.update(delta: -8, isPinned: true, isBottomOverscroll: false)
		XCTAssertEqual(bars.barP, 1)
		// 反向累计 8+42=50pt，越过门槛 38pt → 显示了 38/60
		bars.update(delta: -42, isPinned: true, isBottomOverscroll: false)
		XCTAssertEqual(bars.barP, 1 - 38.0 / 60, accuracy: 0.0001)
		XCTAssertEqual(bars.settleTarget, 0, "less than half hidden settles to shown")
		var halfway = Babel2ReaderBarVisibility()
		halfway.update(delta: 12 + 30, isPinned: true, isBottomOverscroll: false)
		XCTAssertEqual(halfway.barP, 0.5, accuracy: 0.0001)
		XCTAssertEqual(halfway.settleTarget, 1, "exactly half-way settles to hidden")
		// 到底回弹不算
		let before = bars.barP
		bars.update(delta: 40, isPinned: true, isBottomOverscroll: true)
		XCTAssertEqual(bars.barP, before)
		// 回到未固定（顶部附近）强制显示
		bars.update(delta: -1, isPinned: false, isBottomOverscroll: false)
		XCTAssertEqual(bars.barP, 0)
		XCTAssertFalse(bars.isTracking)
	}

	func testToolbarReadAndStarUseActionHandlerAndPlaceholdersAreDisabled() async throws {
		let handler = RecordingActionHandler()
		let viewController = makeReader(body: "<p>Body</p>", actionHandler: handler, isRead: false, isStarred: true)
		let window = hostInWindow(viewController)
		defer { window.isHidden = true }
		let toolbar = viewController.toolbarView
		XCTAssertEqual(toolbar.frame.maxY, window.bounds.maxY, accuracy: 0.5)
		XCTAssertEqual(toolbar.frame.height, 72)
		XCTAssertEqual(toolbar.starButton.accessibilityValue, "starred")
		XCTAssertTrue(toolbar.placeholderButtons.isEmpty, "all toolbar controls are wired")
		XCTAssertFalse(toolbar.nextButton.isEnabled, "no next article provider → disabled")
		// 5 个按钮的中心依次对应参考画布 x = 32 / 104 / 201 / 290.5 / 362（窗口宽 402）
		let centers = ([toolbar.readButton, toolbar.starButton, toolbar.nextButton, toolbar.readingModeButton, toolbar.translationToggle] as [UIView]).map { $0.center.x }
		for (actual, expected) in zip(centers, [32, 104, 201, 290.5, 362] as [CGFloat]) {
			XCTAssertEqual(actual, expected, accuracy: 0.5)
		}

		let articleID = ArticleSnapshot.ID(accountID: "account", feedID: "feed", articleID: "reader-article")
		// 打开即自动标为已读，图标变为实心圆
		await waitUntil { toolbar.readButton.accessibilityValue == "read" }
		// 手动标回未读：空心圈，且不会被再次自动改回已读
		toolbar.readButton.sendActions(for: .touchUpInside)
		await waitUntil { toolbar.readButton.accessibilityValue == "unread" }
		viewController.viewDidAppear(false)
		toolbar.starButton.sendActions(for: .touchUpInside)
		await waitUntil { toolbar.starButton.accessibilityValue == "unstarred" }
		XCTAssertEqual(toolbar.readButton.accessibilityValue, "unread")
		toolbar.readButton.sendActions(for: .touchUpInside)
		await waitUntil { toolbar.readButton.accessibilityValue == "read" }
		let actions = await handler.actions
		XCTAssertEqual(actions, [.markRead(articleID), .markUnread(articleID), .toggleStar(articleID), .markRead(articleID)])

		// 失败时按钮状态不变
		await handler.setShouldFail(true)
		toolbar.starButton.sendActions(for: .touchUpInside)
		try await Task.sleep(for: .milliseconds(200))
		XCTAssertEqual(toolbar.starButton.accessibilityValue, "unstarred")
	}

	func testBarsHideAfterPinnedDownwardTravelAndReturnOnUpwardTravel() async throws {
		let paragraphs = (1...120).map { "<p>Paragraph \($0) with enough words to wrap across the reading column.</p>" }.joined()
		let recorder = RecordingMotionRecorder()
		let viewController = makeReader(body: paragraphs, motionRecorder: recorder)
		let window = hostInWindow(viewController)
		defer { window.isHidden = true }
		await waitForReaderRender(viewController)
		await waitForScrollableLength(viewController, atLeast: 2500)
		let scrollView = viewController.readerContentView.scrollView
		// 正文底部让出底栏：窗口无安全区时应让出整整 72pt
		XCTAssertEqual(scrollView.contentInset.bottom, 72, accuracy: 0.5)
		let progress = viewController.chromeProgress
		func scroll(by distance: CGFloat, step: CGFloat = 4) {
			var moved: CGFloat = 0
			while abs(moved) < abs(distance) {
				let delta = distance > 0 ? min(step, distance - moved) : max(-step, distance - moved)
				scrollView.contentOffset.y += delta
				moved += delta
			}
		}
		// 固定之前往下滑：栏不动
		scrollView.contentOffset.y = -scrollView.adjustedContentInset.top
		scroll(by: progress.collapseStart + progress.collapseDistance - 2)
		XCTAssertEqual(viewController.barVisibilityProgress, 0)
		// 固定后继续往下：跟手隐藏
		scroll(by: 12 + 30 + 2)
		XCTAssertEqual(viewController.barVisibilityProgress, 30.0 / 60, accuracy: 0.05)
		XCTAssertEqual(viewController.toolbarView.alpha, 0.5, accuracy: 0.05)
		scroll(by: 100)
		XCTAssertEqual(viewController.barVisibilityProgress, 1)
		XCTAssertTrue(viewController.topBarButtons.allSatisfy { $0.alpha == 0 })
		XCTAssertEqual(viewController.toolbarView.transform.ty, 72, accuracy: 0.5)
		// Figma 04D3：顶部按钮行收起，紧凑栏上移 44pt 贴到状态栏下（ADR-018）
		XCTAssertEqual(viewController.compactHeaderView.transform.ty, -44, accuracy: 0.5)
		XCTAssertEqual(viewController.compactHeaderView.pCollapse, 1)
		// 往上滑：先 8pt 不动，越过 12pt 后显示回来
		scroll(by: -8)
		XCTAssertEqual(viewController.barVisibilityProgress, 1)
		scroll(by: -12 - 50)
		XCTAssertLessThan(viewController.barVisibilityProgress, 0.25)
		// 停下后补完到显示
		await waitUntil { viewController.barVisibilityProgress == 0 }
		try await Task.sleep(for: .milliseconds(300))
		XCTAssertTrue(viewController.topBarButtons.allSatisfy { $0.alpha == 1 && $0.isUserInteractionEnabled })
		XCTAssertEqual(viewController.toolbarView.transform, .identity)
		// 半路停下：补完到最近的一端（这里 >0.5 → 隐藏）
		scroll(by: 12 + 40)
		await waitUntil { viewController.barVisibilityProgress == 1 }
		// 拉回顶部：强制显示
		scrollView.contentOffset.y = -scrollView.adjustedContentInset.top
		XCTAssertEqual(viewController.barVisibilityProgress, 0)
		// 栏显隐打点成对出现：每个 begin 之后都有一个 end
		let barPhases = recorder.events.compactMap { event -> MotionSignpostPhase? in
			guard case .readerChrome(let payload)? = event.typedPayload, payload.state == .controlsChanging else { return nil }
			return event.phase
		}
		XCTAssertFalse(barPhases.isEmpty)
		XCTAssertEqual(barPhases.count % 2, 0, "bar intervals are paired: \(barPhases)")
		for (index, phase) in barPhases.enumerated() {
			XCTAssertEqual(phase, index % 2 == 0 ? .begin : .end)
		}
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
		let unreadTableView = try XCTUnwrap(rootTable(for: root, scope: .unread))
		await waitForRootState(root, scope: .unread, state: "loaded", rows: 1)
		XCTAssertEqual(root.selectedScope, .unread)
		let unreadCell = root.tableView(unreadTableView, cellForRowAt: IndexPath(row: 0, section: 0))
		XCTAssertEqual(unreadCell.accessibilityValue, "1")

		let allButton = try XCTUnwrap(descendant(of: root.view, matching: UIButton.self) { $0.accessibilityIdentifier == "babel2.scope.all" })
		allButton.sendActions(for: .touchUpInside)
		await waitForRootState(root, scope: .all, state: "loaded", rows: 1)
		XCTAssertEqual(root.selectedScope, .all)
		let tableView = try XCTUnwrap(rootTable(for: root, scope: .all))
		let allCell = root.tableView(tableView, cellForRowAt: IndexPath(row: 0, section: 0))
		XCTAssertEqual(allCell.accessibilityValue, "2")

		let unreadButton = try XCTUnwrap(descendant(of: root.view, matching: UIButton.self) { $0.accessibilityIdentifier == "babel2.scope.unread" })
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
		let provider = FakeDataProvider(librarySnapshots: [.unread: LibrarySnapshot(feeds: [feed])])
		let root = try XCTUnwrap(Babel2SceneComposition.makeRoot(environment: makeEnvironment(provider: provider)).viewControllers.first as? Babel2RootViewController)
		root.loadViewIfNeeded()
		root.viewDidAppear(false)
		await waitForRootState(root, scope: .unread, state: "loaded", rows: 1)

		await provider.delayNextLibraryRequest(.unread)
		NotificationCenter.default.post(name: .babel2LibraryDidChange, object: nil)
		await waitForLibraryStart(provider, .unread, after: 1)
		let tableView = try XCTUnwrap(rootTable(for: root, scope: .unread))
		XCTAssertEqual(tableView.numberOfRows(inSection: 0), 1)
		XCTAssertEqual(tableView.accessibilityValue, "loaded")
		await provider.releaseLibraryRequest(.unread, snapshot: LibrarySnapshot(feeds: [feed]))
		await waitForRootState(root, scope: .unread, state: "loaded", rows: 1)
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
			.unread: LibrarySnapshot(feeds: [unreadFeed]),
			.starred: LibrarySnapshot(feeds: [starredFeed])
		])
		let root = try XCTUnwrap(Babel2SceneComposition.makeRoot(environment: makeEnvironment(provider: provider)).viewControllers.first as? Babel2RootViewController)
		root.loadViewIfNeeded()
		root.viewDidAppear(false)
		// `.unread` is the eager default surface: `viewDidAppear` already loads it,
		// so it cannot be used as the "not yet loaded" scope below (re-selecting an
		// already-loaded scope reuses its cached rows instead of issuing a new
		// request). Use `.all` for the delayed/never-loaded leg instead, mirroring
		// the original race exactly with the roles swapped.
		await waitForRootState(root, scope: .unread, state: "loaded", rows: 1)

		await provider.delayNextLibraryRequest(.all)
		let allButton = try XCTUnwrap(descendant(of: root.view, matching: UIButton.self) { $0.accessibilityIdentifier == "babel2.scope.all" })
		let starredButton = try XCTUnwrap(descendant(of: root.view, matching: UIButton.self) { $0.accessibilityIdentifier == "babel2.scope.starred" })
		allButton.sendActions(for: .touchUpInside)
		await waitForLibraryStart(provider, .all, after: 1)
		starredButton.sendActions(for: .touchUpInside)
		await waitForRootState(root, scope: .starred, state: "loaded", rows: 1)
		await provider.releaseLibraryRequest(.all, snapshot: LibrarySnapshot(feeds: [allFeed]))
		for _ in 0..<100 { await Task.yield() }

		let allTable = try XCTUnwrap(rootTable(for: root, scope: .all))
		XCTAssertEqual(allTable.numberOfRows(inSection: 0), 0)
		XCTAssertEqual(allTable.accessibilityValue, "loading")
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
		await waitForRootState(root, scope: .unread, state: "loaded", rows: 1)
		let all = try XCTUnwrap(descendant(of: root.view, matching: UIButton.self) { $0.accessibilityIdentifier == "babel2.scope.all" })
		let starred = try XCTUnwrap(descendant(of: root.view, matching: UIButton.self) { $0.accessibilityIdentifier == "babel2.scope.starred" })
		all.sendActions(for: .touchUpInside)
		starred.sendActions(for: .touchUpInside)
		await waitForRootState(root, scope: .starred, state: "loaded", rows: 1)
		await waitForSelectedScopeButton(starred)
		XCTAssertEqual(root.selectedScope, .starred)
		XCTAssertEqual(all.accessibilityValue, "Not selected")
		XCTAssertEqual(starred.accessibilityValue, "Selected")
	}

	/// The existing rapid-tap test above never actually reaches
	/// `interruptScopeTransition()`: tapping two never-loaded scopes
	/// back-to-back only cancels a still-pending network request (see
	/// `invalidateLibraryRequest`), because `startScopeTransition` cannot run
	/// -- and so no `UIViewPropertyAnimator` exists to interrupt -- until a
	/// scope's data has actually arrived. This test pre-warms every scope
	/// first so the follow-up rapid taps land while a real cross-fade
	/// animator is still running, exercising the genuine "interrupt mid
	/// flight and redirect through a third target" path required by
	/// MOTION-CONTRACT.md §4A.
	func testRapidScopeTapsThroughThirdTargetDuringActiveAnimationSettleOnLastSelection() async throws {
		let feeds = Babel2FeedScope.allCases.reduce(into: [Babel2FeedScope: LibrarySnapshot]()) { result, scope in
			let id = FeedSnapshot.ID(accountID: "account", feedID: scope.rawValue)
			result[scope] = LibrarySnapshot(feeds: [makeFeed(id: id, title: scope.rawValue, count: 1)])
		}
		let provider = FakeDataProvider(librarySnapshots: feeds)
		let root = try XCTUnwrap(Babel2SceneComposition.makeRoot(environment: makeEnvironment(provider: provider)).viewControllers.first as? Babel2RootViewController)
		root.loadViewIfNeeded()
		root.viewDidAppear(false)
		await waitForRootState(root, scope: .unread, state: "loaded", rows: 1)

		let all = try XCTUnwrap(descendant(of: root.view, matching: UIButton.self) { $0.accessibilityIdentifier == "babel2.scope.all" })
		let starred = try XCTUnwrap(descendant(of: root.view, matching: UIButton.self) { $0.accessibilityIdentifier == "babel2.scope.starred" })
		let unread = try XCTUnwrap(descendant(of: root.view, matching: UIButton.self) { $0.accessibilityIdentifier == "babel2.scope.unread" })

		// Pre-warm both destination scopes (each settles fully before the
		// next tap) so their surfaces are already loaded going into the
		// real rapid-tap sequence below.
		all.sendActions(for: .touchUpInside)
		await waitForRootState(root, scope: .all, state: "loaded", rows: 1)
		await waitForSelectedScopeButton(all)
		starred.sendActions(for: .touchUpInside)
		await waitForRootState(root, scope: .starred, state: "loaded", rows: 1)
		await waitForSelectedScopeButton(starred)
		unread.sendActions(for: .touchUpInside)
		await waitForRootState(root, scope: .unread, state: "loaded", rows: 1)
		await waitForSelectedScopeButton(unread)

		// All three scopes are now loaded. Fire three taps back-to-back
		// with no `await` in between, so each lands while the previous
		// transition's animator is still actively running.
		starred.sendActions(for: .touchUpInside)
		all.sendActions(for: .touchUpInside)
		starred.sendActions(for: .touchUpInside)

		await waitForRootState(root, scope: .starred, state: "loaded", rows: 1)
		await waitForSelectedScopeButton(starred)
		XCTAssertEqual(root.selectedScope, .starred)
		XCTAssertEqual(starred.accessibilityValue, "Selected")
		XCTAssertEqual(all.accessibilityValue, "Not selected")
		XCTAssertEqual(unread.accessibilityValue, "Not selected")
		let starredTable = try XCTUnwrap(rootTable(for: root, scope: .starred))
		XCTAssertEqual(starredTable.numberOfRows(inSection: 0), 1)
		let cell = root.tableView(starredTable, cellForRowAt: IndexPath(row: 0, section: 0))
		XCTAssertEqual(cell.accessibilityValue, "1")
	}

	func testScopeTransitionEmitsLibraryFilterBeginAndEndMotionSignposts() async throws {
		let feed = makeFeed(id: FeedSnapshot.ID(accountID: "account", feedID: "starred"), title: "Starred", count: 1)
		let provider = FakeDataProvider(librarySnapshots: [.starred: LibrarySnapshot(feeds: [feed])])
		let recorder = RecordingMotionRecorder()
		let root = Babel2RootViewController(environment: makeEnvironment(provider: provider), motionRecorder: recorder)
		root.loadViewIfNeeded()
		root.viewDidAppear(false)
		await waitForRootState(root, scope: .unread, state: "empty", rows: 0)

		let starred = try XCTUnwrap(descendant(of: root.view, matching: UIButton.self) { $0.accessibilityIdentifier == "babel2.scope.starred" })
		starred.sendActions(for: .touchUpInside)
		await waitForRootState(root, scope: .starred, state: "loaded", rows: 1)
		await waitForSelectedScopeButton(starred)
		await waitUntil { root.isScopeTransitionSettledForTesting }

		let libraryEvents = recorder.events.filter { $0.name == .libraryFilter }
		XCTAssertEqual(libraryEvents.count, 2, "expected exactly one begin and one end for a single uninterrupted transition")
		guard libraryEvents.count == 2,
			case let .libraryFilter(beginPayload)? = libraryEvents[0].typedPayload,
			case let .libraryFilter(endPayload)? = libraryEvents[1].typedPayload else {
			XCTFail("expected typed libraryFilter payloads")
			return
		}
		XCTAssertEqual(libraryEvents[0].phase, .begin)
		XCTAssertEqual(libraryEvents[1].phase, .end)
		XCTAssertEqual(beginPayload.fromFilter, .unread)
		XCTAssertEqual(beginPayload.toFilter, .starred)
		XCTAssertEqual(beginPayload.pFilter, .zero)
		XCTAssertEqual(endPayload.fromFilter, .unread)
		XCTAssertEqual(endPayload.toFilter, .starred)
		XCTAssertEqual(endPayload.pFilter, .one)
		XCTAssertEqual(beginPayload.token, endPayload.token)
	}

	func testInterruptedScopeTransitionEmitsEventPhaseSignpostThenFreshBeginWithNewToken() async throws {
		let feeds = Babel2FeedScope.allCases.reduce(into: [Babel2FeedScope: LibrarySnapshot]()) { result, scope in
			let id = FeedSnapshot.ID(accountID: "account", feedID: scope.rawValue)
			result[scope] = LibrarySnapshot(feeds: [makeFeed(id: id, title: scope.rawValue, count: 1)])
		}
		let provider = FakeDataProvider(librarySnapshots: feeds)
		let recorder = RecordingMotionRecorder()
		let root = Babel2RootViewController(environment: makeEnvironment(provider: provider), motionRecorder: recorder)
		root.loadViewIfNeeded()
		root.viewDidAppear(false)
		await waitForRootState(root, scope: .unread, state: "loaded", rows: 1)

		let starred = try XCTUnwrap(descendant(of: root.view, matching: UIButton.self) { $0.accessibilityIdentifier == "babel2.scope.starred" })
		let all = try XCTUnwrap(descendant(of: root.view, matching: UIButton.self) { $0.accessibilityIdentifier == "babel2.scope.all" })
		let unread = try XCTUnwrap(descendant(of: root.view, matching: UIButton.self) { $0.accessibilityIdentifier == "babel2.scope.unread" })

		// Pre-warm both destinations, returning to `.unread` before the real
		// interrupt sequence so the begin/interrupt/begin/end trace below is
		// unambiguous.
		starred.sendActions(for: .touchUpInside)
		await waitForRootState(root, scope: .starred, state: "loaded", rows: 1)
		await waitForSelectedScopeButton(starred)
		await waitUntil { root.isScopeTransitionSettledForTesting }
		all.sendActions(for: .touchUpInside)
		await waitForRootState(root, scope: .all, state: "loaded", rows: 1)
		await waitForSelectedScopeButton(all)
		await waitUntil { root.isScopeTransitionSettledForTesting }
		unread.sendActions(for: .touchUpInside)
		await waitForRootState(root, scope: .unread, state: "loaded", rows: 1)
		await waitForSelectedScopeButton(unread)
		await waitUntil { root.isScopeTransitionSettledForTesting }
		recorder.clear()

		// unread -> starred (begins, animator running) -> all (interrupts
		// the in-flight starred transition mid-way and redirects to all),
		// with no `await` between the two taps.
		starred.sendActions(for: .touchUpInside)
		all.sendActions(for: .touchUpInside)

		await waitForRootState(root, scope: .all, state: "loaded", rows: 1)
		await waitForSelectedScopeButton(all)
		await waitUntil { root.isScopeTransitionSettledForTesting }

		let libraryEvents = recorder.events.filter { $0.name == .libraryFilter }
		XCTAssertEqual(libraryEvents.count, 4)
		guard libraryEvents.count == 4,
			case let .libraryFilter(firstBegin)? = libraryEvents[0].typedPayload,
			case let .libraryFilter(interruptSample)? = libraryEvents[1].typedPayload,
			case let .libraryFilter(secondBegin)? = libraryEvents[2].typedPayload,
			case let .libraryFilter(finalEnd)? = libraryEvents[3].typedPayload else {
			XCTFail("expected typed libraryFilter payloads")
			return
		}
		XCTAssertEqual(libraryEvents[0].phase, .begin)
		XCTAssertEqual(libraryEvents[1].phase, .event)
		XCTAssertEqual(libraryEvents[2].phase, .begin)
		XCTAssertEqual(libraryEvents[3].phase, .end)

		XCTAssertEqual(firstBegin.fromFilter, .unread)
		XCTAssertEqual(firstBegin.toFilter, .starred)
		XCTAssertEqual(firstBegin.pFilter, .zero)

		XCTAssertEqual(interruptSample.token, firstBegin.token, "the interrupt sample must report the interrupted transition's own token")
		XCTAssertEqual(interruptSample.toFilter, .starred)
		XCTAssertGreaterThanOrEqual(interruptSample.pFilter.value, 0)
		XCTAssertLessThanOrEqual(interruptSample.pFilter.value, 1)

		XCTAssertEqual(secondBegin.fromFilter, .unread, "displayed scope never actually reached starred before the interrupt")
		XCTAssertEqual(secondBegin.toFilter, .all)
		XCTAssertEqual(secondBegin.pFilter, .zero)
		XCTAssertNotEqual(secondBegin.token, firstBegin.token, "a redirected transition is a fresh interaction, not a continuation")

		XCTAssertEqual(finalEnd.token, secondBegin.token)
		XCTAssertEqual(finalEnd.toFilter, .all)
		XCTAssertEqual(finalEnd.pFilter, .one)
	}

	// A regression test for the real-device "scope buttons stuck at the left
	// edge on cold launch" bug (found 2026-09-08) was attempted here and
	// removed: it passed in isolation but failed when run as part of the full
	// suite, with the exact same code and assertions -- proving the failure
	// depends on ambient Auto Layout/window timing left over from whichever
	// tests happened to run first in the same process, not on anything this
	// test itself controls. A flaky, order-dependent test is worse than no
	// automated coverage here. See LESSONS.md for the full writeup and
	// VALIDATION.md for what was actually verified (production fix applied,
	// real-device confirmation still required from the user).

	func testErrorIsDistinctFromEmptyAndRetryReloads() async throws {
		let provider = FakeDataProvider()
		await provider.failNextLibraryRequest(.unread)
		let root = try XCTUnwrap(Babel2SceneComposition.makeRoot(environment: makeEnvironment(provider: provider)).viewControllers.first as? Babel2RootViewController)
		root.loadViewIfNeeded()
		root.viewDidAppear(false)
		await waitForRootState(root, scope: .unread, state: "error", rows: 0)
		let retry = try XCTUnwrap(descendant(of: root.view, matching: UIButton.self) { $0.accessibilityIdentifier == "babel2.feeds.retry.unread" })
		XCTAssertFalse(retry.isHidden)
		await provider.setLibrarySnapshot(.unread, snapshot: LibrarySnapshot())
		retry.sendActions(for: .touchUpInside)
		await waitForRootState(root, scope: .unread, state: "empty", rows: 0)
	}

	func testSyncArrowTracksActiveScopeSnapshot() async throws {
		let feedID = FeedSnapshot.ID(accountID: "account", feedID: "feed")
		let feed = makeFeed(id: feedID, title: "Feed", count: 1)
		let provider = FakeDataProvider(librarySnapshots: [.unread: LibrarySnapshot(feeds: [feed], isSyncing: true)])
		let root = try XCTUnwrap(Babel2SceneComposition.makeRoot(environment: makeEnvironment(provider: provider)).viewControllers.first as? Babel2RootViewController)
		root.loadViewIfNeeded()
		root.viewDidAppear(false)
		await waitForRootState(root, scope: .unread, state: "loaded", rows: 1)
		let arrow = try XCTUnwrap(descendant(of: root.view, matching: UIButton.self) { $0.accessibilityIdentifier == "babel2.sync.arrow" })
		XCTAssertFalse(arrow.isHidden)

		await provider.setLibrarySnapshot(.unread, snapshot: LibrarySnapshot(feeds: [feed], isSyncing: false))
		NotificationCenter.default.post(name: .babel2LibraryDidChange, object: nil)
		await waitForLibraryStart(provider, .unread, after: 2)
		for _ in 0..<200 {
			if arrow.isHidden { break }
			await Task.yield()
		}
		XCTAssertTrue(arrow.isHidden)
	}
}

private actor FakeDataProvider: DataProviding {
	private enum ProviderError: Error { case failed }
	private var feedArticles: [FeedSnapshot.ID: [ArticleSnapshot]]
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

	/// 模拟「数据库里的状态被改了」（阅读页操作或后台同步）。
	func setFeedArticles(_ articles: [ArticleSnapshot], for id: FeedSnapshot.ID) {
		feedArticles[id] = articles
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

@MainActor
private final class RecordingMotionRecorder: Babel2MotionRecording {
	private(set) var events = [MotionSignpostEvent]()

	func record(_ event: MotionSignpostEvent) {
		events.append(event)
	}

	func clear() {
		events.removeAll()
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

private actor RecordingActionHandler: ActionHandling {
	private(set) var actions = [LibraryAction]()
	var shouldFail = false

	func setShouldFail(_ value: Bool) { shouldFail = value }

	func handle(_ action: LibraryAction) async throws {
		actions.append(action)
		if shouldFail { throw CancellationError() }
	}
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
	renderer: any ArticleRendering = RecordingRenderer(),
	actionHandler: any ActionHandling = NoopActionHandler()
) -> AppEnvironment {
	Babel2AppAssembly.makeEnvironment(
		dataProvider: provider,
		actionHandler: actionHandler,
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
	// 按真实时间等（最多约 3 秒），而不是按空转次数：选中态要等 180ms 的切换动画结束，
	// 空转次数对应的时间随机器忙闲变化，曾导致测试时过时不过（2026-09-24 修正）
	for _ in 0..<300 {
		if button.accessibilityValue == "Selected" { return }
		try? await Task.sleep(for: .milliseconds(10))
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

@MainActor
private func makeReader(
	body: String,
	motionRecorder: any Babel2MotionRecording = Babel2NullMotionRecorder(),
	actionHandler: any ActionHandling = NoopActionHandler(),
	isRead: Bool = false,
	isStarred: Bool = false,
	hostArticle: AnyObject? = nil,
	author: String? = nil,
	fullTextProvider: @escaping @MainActor (URL, UIView) async throws -> String = { _, _ in throw CancellationError() },
	feedReaderModeSetting: Babel2FeedReaderModeSetting? = nil,
	makeBrowser: ((URL) -> (any Babel2PreparableRoute))? = nil
) -> Babel2ArticleViewController {
	let feedID = FeedSnapshot.ID(accountID: "account", feedID: "feed")
	let article = ArticleSnapshot(
		id: ArticleSnapshot.ID(accountID: "account", feedID: "feed", articleID: "reader-article"),
		title: "Reader",
		content: body,
		url: URL(string: "https://example.com/post"),
		feedID: feedID,
		isRead: isRead,
		isStarred: isStarred,
		author: author
	)
	return Babel2ArticleViewController(
		article: article,
		environment: makeEnvironment(provider: FakeDataProvider(), actionHandler: actionHandler),
		feedTitle: "Feed",
		motionRecorder: motionRecorder,
		hostArticleProvider: { _ in hostArticle },
		fullTextProvider: fullTextProvider,
		feedReaderModeSetting: feedReaderModeSetting,
		makeBrowser: makeBrowser
	)
}

/// 网页正文只有真正放进窗口后才会稳定加载，所以阅读页测试都先挂到一个 402×874 的窗口里。
@MainActor
private func hostInWindow(_ viewController: UIViewController) -> UIWindow {
	let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
	window.rootViewController = viewController
	window.makeKeyAndVisible()
	viewController.view.layoutIfNeeded()
	return window
}

/// 等正文排版完成（成功或失败），最多约 10 秒。
@MainActor
private func waitForReaderRender(_ viewController: Babel2ArticleViewController) async {
	for _ in 0..<200 {
		let state = viewController.readerContentView.renderState
		if state == .rendered || state == .failed { return }
		try? await Task.sleep(for: .milliseconds(50))
	}
	XCTFail("Timed out waiting for reader render; state=\(viewController.readerContentView.renderState)")
}

@MainActor
private func pngDataURI(size: CGSize) -> String {
	let format = UIGraphicsImageRendererFormat()
	format.scale = 1
	let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
		UIColor.gray.setFill()
		context.fill(CGRect(origin: .zero, size: size))
	}
	return "data:image/png;base64," + (image.pngData() ?? Data()).base64EncodedString()
}

/// 等正文排版后的可滚动长度足够（网页布局是异步的）。
@MainActor
private func waitForScrollableLength(_ viewController: Babel2ArticleViewController, atLeast length: CGFloat) async {
	for _ in 0..<200 {
		if viewController.chromeProgress.maxScroll >= length { return }
		try? await Task.sleep(for: .milliseconds(50))
	}
	XCTFail("Timed out waiting for scrollable length; maxScroll=\(viewController.chromeProgress.maxScroll)")
}

/// 按真实时间等待某个条件成立（最多约 3 秒）。
@MainActor
private func waitUntil(_ condition: () -> Bool) async {
	for _ in 0..<300 {
		if condition() { return }
		try? await Task.sleep(for: .milliseconds(10))
	}
	XCTFail("Timed out waiting for condition")
}

/// 测试用浏览器替身：记录是否被准备 / 丢弃。
@MainActor
private final class StubBrowser: UIViewController, Babel2PreparableRoute {
	let url: URL
	private(set) var didPrepare = false
	private(set) var didDiscard = false
	init(url: URL) {
		self.url = url
		super.init(nibName: nil, bundle: nil)
	}
	required init?(coder: NSCoder) { nil }
	func prepare() { didPrepare = true; loadViewIfNeeded() }
	func discard() { didDiscard = true }
}
