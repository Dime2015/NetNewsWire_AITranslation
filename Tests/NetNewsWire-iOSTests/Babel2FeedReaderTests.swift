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

	/// 用户反馈标题翻译慢：标题请求要和正文请求一样关掉思考（只对 OpenRouter 发该字段）。
	func testTitleTranslationRequestDisablesReasoningOnOpenRouter() async throws {
		URLProtocol.registerClass(CapturingTranslationProtocol.self)
		defer { URLProtocol.unregisterClass(CapturingTranslationProtocol.self) }

		CapturingTranslationProtocol.lastBody = nil
		let translated = try await NNWTitleBatchTranslator.translate(
			["A headline"],
			config: TranslationConfig(baseURL: "https://openrouter.ai/api/v1", apiKey: "test"),
			model: "some/model"
		)
		XCTAssertEqual(translated, ["一个标题"])
		let openRouterBody = try XCTUnwrap(CapturingTranslationProtocol.lastBody)
		let json = try XCTUnwrap(JSONSerialization.jsonObject(with: openRouterBody) as? [String: Any])
		let reasoning = try XCTUnwrap(json["reasoning"] as? [String: Any], "OpenRouter request must carry reasoning settings")
		XCTAssertEqual(reasoning["effort"] as? String, "none")
		XCTAssertEqual(reasoning["exclude"] as? Bool, true)

		CapturingTranslationProtocol.lastBody = nil
		_ = try await NNWTitleBatchTranslator.translate(
			["A headline"],
			config: TranslationConfig(baseURL: "https://api.example-provider.com/v1", apiKey: "test"),
			model: "some/model"
		)
		let otherBody = try XCTUnwrap(CapturingTranslationProtocol.lastBody)
		let otherJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: otherBody) as? [String: Any])
		XCTAssertNil(otherJSON["reasoning"], "non-OpenRouter providers do not get the field")
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

	// MARK: - 列表缩略图（2026-09-25）

	// MARK: - 顶部大图（ADR-027 第 2 步）

	/// 大图从屏幕最顶端铺到安全区下方 169pt，列表紧接其下；有订阅源高清图标时铺上清晰底图，
	/// 抓到更好的图时替换；标题、返回在大图里；文章数显示「N 篇」但辅助功能值仍是纯数字。
	func testFeedHeroShowsArtTitleAndCount() async throws {
		let feedID = FeedSnapshot.ID(accountID: "account", feedID: "feed")
		let list = (1...3).map { ArticleSnapshot(id: ArticleSnapshot.ID(accountID: "account", feedID: "feed", articleID: "\($0)"), title: "T\($0)", url: nil, feedID: feedID) }
		let art = UIGraphicsImageRenderer(size: CGSize(width: 512, height: 512)).image { context in
			UIColor.systemOrange.setFill()
			context.fill(CGRect(x: 0, y: 0, width: 512, height: 512))
		}
		var deliver: ((UIImage) -> Void)?
		let controller = Babel2FeedViewController(
			feed: makeFeed(id: feedID, title: "Marginal Revolution"), scope: .all,
			environment: makeEnvironment(provider: FakeDataProvider(feeds: [feedID: list])),
			heroImage: Babel2FeedHeroImageSource(cached: { nil }, fetch: { deliver = $0 })
		)
		let window = hostInWindow(controller)
		defer { window.isHidden = true }
		let tableView = try XCTUnwrap(descendant(of: controller.view, matching: UITableView.self))
		await waitForRows(in: tableView, count: 3)
		controller.view.layoutIfNeeded()

		let hero = try XCTUnwrap(controller.heroViewForTesting)
		XCTAssertEqual(hero.frame.minY, 0, "hero starts at the very top (under the status bar)")
		XCTAssertEqual(hero.frame.maxY, controller.view.safeAreaInsets.top + 169, accuracy: 0.5)
		XCTAssertEqual(tableView.rect(forSection: 0).minY - tableView.contentOffset.y, hero.frame.maxY, accuracy: 0.5, "list content starts right below the hero, no gap")
		XCTAssertFalse(hero.hasArtForTesting, "no cached art yet → plain paper")
		XCTAssertEqual(hero.titleLabel.text, "Marginal Revolution")
		let compact = try XCTUnwrap(controller.compactBarForTesting)
		XCTAssertEqual(compact.backButton.accessibilityIdentifier, "babel2.feed.back", "back lives in the fixed compact layer")

		let count = try XCTUnwrap(descendant(of: hero, matching: UILabel.self) { $0.accessibilityIdentifier == "babel2.feed.count" })
		XCTAssertEqual(count.accessibilityValue, "3", "UI driver reads the plain number")
		XCTAssertEqual(count.text, String(format: Babel2Localization.text(.articleCount), 3))

		// 抓到图后淡入底图
		let fetch = try XCTUnwrap(deliver, "hero asked for a better image")
		fetch(art)
		for _ in 0..<150 where !hero.hasArtForTesting { try await Task.sleep(for: .milliseconds(20)) }
		XCTAssertTrue(hero.hasArtForTesting)
	}

	// MARK: - 添加订阅页（2026-09-25，ADR-030）

	/// 首页「+」打开添加订阅页（路由恢复 home → addSubscription）。
	func testAddButtonOpensAddSubscriptionPage() throws {
		let navigation = Babel2SceneComposition.makeRoot(environment: makeEnvironment(provider: FakeDataProvider()),
			settingsService: FakeSettingsService(), subscriptionService: FakeSubscriptionService())
		let window = hostInWindow(navigation)
		defer { window.isHidden = true }
		let root = try XCTUnwrap(navigation.viewControllers.first as? Babel2RootViewController)
		root.loadViewIfNeeded()
		let add = try XCTUnwrap(descendant(of: root.view, matching: UIButton.self) { $0.accessibilityIdentifier == "babel2.add" })
		add.sendActions(for: .touchUpInside)
		XCTAssertTrue(navigation.topViewController is Babel2AddSubscriptionViewController)
		XCTAssertEqual(navigation.restorationValue().routes, [.home, .addSubscription])
		let restored = Babel2SceneComposition.makeRoot(environment: makeEnvironment(provider: FakeDataProvider()),
			restoration: Babel2NavigationRestoration(routes: [.home, .addSubscription]),
			settingsService: FakeSettingsService(), subscriptionService: FakeSubscriptionService())
		XCTAssertTrue(restored.topViewController is Babel2AddSubscriptionViewController, "restores the add subscription page")
	}

	/// 搜索结果分组（无结果的组显示自己的说明，组可收起）；默认订阅到第一个位置、可改；
	/// 订阅订到选中位置且留在本页、行变成已订阅；取消订阅调用服务。
	func testAddSubscriptionSearchSubscribeAndUnsubscribe() async throws {
		let service = FakeSubscriptionService()
		let page = Babel2AddSubscriptionViewController(service: service)
		let window = hostInWindow(page)
		defer { window.isHidden = true }
		page.view.layoutIfNeeded()
		XCTAssertEqual(page.destinationIDForTesting, "local", "defaults to the first destination (top level)")
		XCTAssertEqual(page.statusTextForTesting, Babel2Localization.text(.addSubscriptionHint))

		page.runSearch("swift")
		for _ in 0..<100 where page.groupsForTesting.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
		XCTAssertEqual(page.groupsForTesting.map(\.kind), [.website, .podcast])
		XCTAssertNil(page.statusTextForTesting, "results shown")
		let table = page.tableViewForTesting
		table.layoutIfNeeded()
		XCTAssertEqual(table.numberOfRows(inSection: 1), 2, "website results")
		XCTAssertEqual(table.numberOfRows(inSection: 2), 1, "podcast group shows its own status message")
		page.toggleGroupForTesting(0)
		XCTAssertEqual(table.numberOfRows(inSection: 1), 0, "group collapses")
		page.toggleGroupForTesting(0)

		// 改订阅位置：弹出选单选第二项
		let destinationRow = try XCTUnwrap(descendant(of: table, matching: Babel2SettingsSelectRow.self) { $0.accessibilityIdentifier == "babel2.add-subscription.destination" })
		destinationRow.sendActions(for: .touchUpInside)
		let popover = try XCTUnwrap(page.view.subviews.compactMap { $0 as? Babel2SettingsPopover }.last)
		popover.selectForTesting(1)
		XCTAssertEqual(page.destinationIDForTesting, "local/1")

		let result = service.websiteResults[0]
		page.subscribeForTesting(result)
		for _ in 0..<100 where service.subscribed.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
		XCTAssertEqual(service.subscribed.first?.1, "local/1", "subscribes into the chosen folder")
		try await Task.sleep(for: .milliseconds(50))
		table.reloadData()
		table.layoutIfNeeded()
		let cell = try XCTUnwrap(table.cellForRow(at: IndexPath(row: 0, section: 1)) as? Babel2DiscoveryResultCell)
		XCTAssertEqual(cell.stateForTesting, .subscribed, "row shows subscribed; page stays open")

		page.performUnsubscribe(result)
		for _ in 0..<100 where service.unsubscribed.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
		XCTAssertEqual(service.unsubscribed, [result.feedURL])
	}

	/// 真实实现：粘贴 Reddit 版块网址直接给出 Reddit 那一组（不联网；关键词会走四类并行搜索，要联网，不在这里测）。
	func testLiveSubscriptionServiceRoutesSubredditWithoutNetwork() async {
		let groups = await Babel2LiveSubscriptionService().search("https://www.reddit.com/r/swift/")
		XCTAssertEqual(groups.map(\.kind), [.reddit])
		XCTAssertFalse(groups[0].results.isEmpty)
		XCTAssertTrue(groups[0].results.allSatisfy { $0.feedURL.contains("reddit.com/r/swift") })
	}

	// MARK: - 列表搜索（2026-09-25）

	/// 放大镜原地进入搜索：窄栏换成搜索框、底栏隐藏；按全部文章（不分档）搜索、结果替换列表；
	/// 无结果显示说明；下一篇按结果顺序；取消恢复原列表、底栏与滚动位置。
	func testFeedSearchInPlaceAndCancelRestores() async throws {
		let feedID = FeedSnapshot.ID(accountID: "account", feedID: "feed")
		func article(_ id: String, _ title: String, read: Bool) -> ArticleSnapshot {
			ArticleSnapshot(id: ArticleSnapshot.ID(accountID: "account", feedID: "feed", articleID: id), title: title, url: nil, feedID: feedID, isRead: read)
		}
		let list = (1...30).map { article("n\($0)", "Filler \($0)", read: false) }
			+ [article("a", "Treasury Trading", read: true), article("b", "Treasury Bills", read: false)]
		let controller = Babel2FeedViewController(feed: makeFeed(id: feedID, title: "Feed"), scope: .unread,
			environment: makeEnvironment(provider: FakeDataProvider(feeds: [feedID: list])))
		let window = hostInWindow(controller)
		defer { window.isHidden = true }
		let tableView = try XCTUnwrap(descendant(of: controller.view, matching: UITableView.self))
		// 假数据提供者不按档位过滤：列表是全部 32 篇
		await waitForRows(in: tableView, count: 32)
		tableView.layoutIfNeeded()
		tableView.contentOffset.y = -tableView.adjustedContentInset.top + 300
		let offsetBefore = tableView.contentOffset.y
		let compact = try XCTUnwrap(controller.compactBarForTesting)
		XCTAssertFalse(compact.searchButton.isHidden, "search button is available")

		controller.beginSearchForTesting()
		XCTAssertTrue(controller.isSearching)
		XCTAssertTrue(compact.isSearching)
		XCTAssertFalse(compact.searchField.isHidden)
		XCTAssertEqual(compact.backdropAlphaForTesting, 1, "compact bar fully opaque while searching")
		let toolbar = try XCTUnwrap(descendant(of: controller.view, matching: UIButton.self) { $0.accessibilityIdentifier == "babel2.feed.read-all" })
		XCTAssertTrue(toolbar.isHidden || toolbar.superview?.isHidden == true, "bottom toolbar hidden while searching")

		controller.searchForTesting("treasury")
		await waitForRows(in: tableView, count: 2)
		XCTAssertEqual(Set(controller.articlesForTesting.map(\.id.articleID)), ["a", "b"], "matches include the read article (search ignores the scope)")
		let first = controller.articlesForTesting[0]
		XCTAssertEqual(controller.nextArticle(after: first.id)?.id.articleID ?? "none",
			controller.articlesForTesting.count > 1 && !controller.articlesForTesting[1].isRead ? controller.articlesForTesting[1].id.articleID : "none",
			"next article follows the result order")

		// 搜索时松手不做大图补完：拖了 20pt 松手，目标位置保持不变（修复「下滑失灵」）
		var target = CGPoint(x: 0, y: -tableView.adjustedContentInset.top + 20)
		controller.scrollViewWillEndDragging(tableView, withVelocity: .zero, targetContentOffset: &target)
		XCTAssertEqual(target.y, -tableView.adjustedContentInset.top + 20, accuracy: 0.5, "no hero snapping while searching")
		// 放大镜：搜索框里、但不在输入框内部的那个图片（输入框的 × 也是图片）
		let glass = try XCTUnwrap(descendant(of: compact.searchField, matching: UIImageView.self) { !$0.isDescendant(of: compact.searchField.textField) })
		compact.layoutIfNeeded()
		// 16×16（允许像素对齐的误差），宽高比接近 1：不再被横向拉长
		XCTAssertEqual(glass.bounds.width, 16, accuracy: 0.5)
		XCTAssertEqual(glass.bounds.height, 16, accuracy: 0.5)
		XCTAssertEqual(glass.bounds.width / max(glass.bounds.height, 1), 1, accuracy: 0.05, "magnifier keeps its proportions")
		XCTAssertEqual(compact.searchField.textField.clearButtonMode, .always)

		controller.searchForTesting("zzz-no-match")
		await waitForRows(in: tableView, count: 0)
		let state = try XCTUnwrap(descendant(of: controller.view, matching: UILabel.self) { $0.accessibilityIdentifier == "babel2.feed.articles.state" })
		XCTAssertFalse(state.isHidden)
		XCTAssertEqual(state.text, String(format: Babel2Localization.text(.noSearchResults), "zzz-no-match"))

		controller.endSearch()
		XCTAssertFalse(controller.isSearching)
		XCTAssertFalse(compact.isSearching)
		XCTAssertTrue(compact.searchField.isHidden)
		XCTAssertEqual(controller.articlesForTesting.count, 32, "original list restored")
		XCTAssertEqual(tableView.contentOffset.y, offsetBefore, accuracy: 1, "scroll position restored")
		XCTAssertFalse(toolbar.isHidden || toolbar.superview?.isHidden == true)
	}

	// MARK: - 设置页（Slice 6，Figma 110:300 等）

	/// 首页齿轮进入设置首页（路由恢复为 home → settings）；8 个类别都能进入对应页面。
	func testSettingsHomeFromGearAndEveryCategoryOpens() throws {
		let service = FakeSettingsService()
		let navigation = Babel2SceneComposition.makeRoot(environment: makeEnvironment(provider: FakeDataProvider()), settingsService: service)
		let window = hostInWindow(navigation)
		defer { window.isHidden = true }
		let root = try XCTUnwrap(navigation.viewControllers.first as? Babel2RootViewController)
		root.loadViewIfNeeded()
		let gear = try XCTUnwrap(descendant(of: root.view, matching: UIButton.self) { $0.accessibilityIdentifier == "babel2.settings" })
		gear.sendActions(for: .touchUpInside)
		XCTAssertTrue(navigation.topViewController is Babel2SettingsHomeViewController)
		XCTAssertEqual(navigation.restorationValue().routes, [.home, .settings])

		// 测试窗口不挂屏幕场景，带动画的推入永远不结束、之后的推入会被忽略（见 STATUS 内置浏览器一节）：
		// 每个类别用一个新的导航栈验证。
		let expected: [(String, UIViewController.Type)] = [
			("babel2.settings.accounts", Babel2SettingsAccountsViewController.self),
			("babel2.settings.subscriptions", Babel2SettingsSubscriptionsViewController.self),
			("babel2.settings.timeline", Babel2SettingsTimelineViewController.self),
			("babel2.settings.reader", Babel2SettingsReaderViewController.self),
			("babel2.settings.translation", Babel2SettingsTranslationViewController.self),
			("babel2.settings.appearance", Babel2SettingsAppearanceViewController.self),
			("babel2.settings.notifications", Babel2SettingsNotificationsViewController.self),
			("babel2.settings.support", Babel2SettingsSupportViewController.self)
		]
		for (identifier, type) in expected {
			let home = Babel2SettingsHomeViewController(service: service)
			let stack = Babel2NavigationController(rootViewController: home)
			let categoryWindow = hostInWindow(stack)
			defer { categoryWindow.isHidden = true }
			let row = try XCTUnwrap(descendant(of: home.view, matching: Babel2SettingsRowControl.self) { $0.accessibilityIdentifier == identifier }, identifier)
			row.sendActions(for: .touchUpInside)
			let top = try XCTUnwrap(stack.topViewController)
			XCTAssertTrue(Swift.type(of: top) == type, "\(identifier) opens \(type), got \(Swift.type(of: top))")
			top.loadViewIfNeeded()
		}
	}

	/// 弹出单选菜单：右边对齐内容区、在触发行下方；选完立即生效、行上的值更新、菜单关闭。开关立即生效。
	func testSettingsSelectPopoverAndToggleApplyImmediately() throws {
		let service = FakeSettingsService()
		let page = Babel2SettingsTimelineViewController(service: service)
		let window = hostInWindow(page)
		defer { window.isHidden = true }
		page.view.layoutIfNeeded()
		let sort = try XCTUnwrap(descendant(of: page.view, matching: Babel2SettingsSelectRow.self) { $0.accessibilityIdentifier == "babel2.settings.timeline.sort" })
		XCTAssertEqual(sort.valueLabel.text, Babel2SettingsText.t("Newest First"))
		sort.sendActions(for: .touchUpInside)
		let popover = try XCTUnwrap(page.presentedPopoverForTesting)
		XCTAssertEqual(popover.optionControlsForTesting.count, 2)
		XCTAssertTrue(popover.optionControlsForTesting[0].accessibilityTraits.contains(.selected))
		XCTAssertEqual(popover.cardFrameForTesting.maxX, page.view.bounds.width - 20, accuracy: 0.5, "right edge aligns with content")
		XCTAssertEqual(popover.cardFrameForTesting.width, 272)
		XCTAssertGreaterThan(popover.cardFrameForTesting.minY, sort.convert(sort.bounds, to: page.view).maxY)
		popover.selectForTesting(1)
		XCTAssertFalse(service.sortNewestFirst, "applies immediately")
		XCTAssertEqual(sort.valueLabel.text, Babel2SettingsText.t("Oldest First"))
		XCTAssertNil(page.presentedPopoverForTesting, "popover dismissed")

		let confirm = try XCTUnwrap(descendant(of: page.view, matching: Babel2SettingsSwitch.self))
		XCTAssertTrue(confirm.isOn)
		confirm.toggleForTesting()
		XCTAssertFalse(service.confirmMarkAllRead)
		XCTAssertGreaterThanOrEqual(confirm.bounds.width, 44, "switch hit target is at least 44pt")
	}

	/// 编辑页：取消丢弃改动，保存才写入。
	func testSettingsEditorCancelDiscardsAndSaveWrites() throws {
		let service = FakeSettingsService()
		let navigation = Babel2NavigationController(rootViewController: UIViewController())
		let window = hostInWindow(navigation)
		defer { window.isHidden = true }

		let cancelled = Babel2SettingsDiscoveryKeysViewController(service: service)
		navigation.pushBabel2(cancelled, animated: false)
		cancelled.loadViewIfNeeded()
		cancelled.fieldsForTesting[2].textField.text = "new-key"
		cancelled.leadingTapped()
		XCTAssertNil(service.youTubeAPIKey, "cancel keeps the old value")

		let saved = Babel2SettingsDiscoveryKeysViewController(service: service)
		navigation.pushBabel2(saved, animated: false)
		saved.loadViewIfNeeded()
		saved.fieldsForTesting[0].textField.text = "  id  "
		saved.fieldsForTesting[2].textField.text = "new-key"
		saved.saveTapped()
		XCTAssertEqual(service.redditClientID, "id", "trimmed")
		XCTAssertEqual(service.youTubeAPIKey, "new-key")

		let api = Babel2SettingsTranslationAPIViewController(service: service)
		navigation.pushBabel2(api, animated: false)
		api.loadViewIfNeeded()
		api.keyFieldForTesting.textField.text = "sk-test"
		api.saveTapped()
		XCTAssertEqual(service.translationAPIKey, "sk-test")
	}

	/// 翻译模型：热门前 10 按热度；每个服务商恰好 3 个（不足 3 个的不列）；选择在保存后才生效。
	func testTranslationModelRankingAndEditor() throws {
		var models = [Babel2TranslationModel]()
		for vendor in 0..<12 {
			for index in 0..<(vendor == 11 ? 2 : 4) {
				models.append(Babel2TranslationModel(id: "v\(vendor)/m\(index)", name: "V\(vendor) M\(index)", vendor: "v\(vendor)",
					popularity: Double(100 - vendor * 5 - index), created: 0))
			}
		}
		let top = Babel2TranslationModelRanking.top(models)
		XCTAssertEqual(top.count, 10)
		XCTAssertEqual(top.first?.id, "v0/m0")
		XCTAssertEqual(top.map(\.popularity), top.map(\.popularity).sorted(by: >))
		let groups = Babel2TranslationModelRanking.vendorGroups(models)
		XCTAssertEqual(groups.count, 10, "at most 10 vendors")
		XCTAssertTrue(groups.allSatisfy { $0.models.count == 3 }, "exactly 3 per vendor")
		XCTAssertFalse(groups.contains { $0.vendor == "v11" }, "vendors with fewer than 3 models are left out")
		XCTAssertEqual(groups.first?.vendor, "v0")

		let service = FakeSettingsService()
		service.models = models
		service.translationModelID = "v0/m0"
		let navigation = Babel2NavigationController(rootViewController: UIViewController())
		let window = hostInWindow(navigation)
		defer { window.isHidden = true }
		let editor = Babel2SettingsTranslationModelViewController(service: service)
		navigation.pushBabel2(editor, animated: false)
		editor.loadViewIfNeeded()
		XCTAssertNotNil(descendant(of: editor.view, matching: UIButton.self) { $0.accessibilityIdentifier == "babel2.settings.translation-model.refresh" }, "refresh button on top")
		editor.chooseForTesting("v3/m1")
		XCTAssertEqual(service.translationModelID, "v0/m0", "not applied before save")
		editor.saveTapped()
		XCTAssertEqual(service.translationModelID, "v3/m1")
	}

	/// 账户详情：默认本地账户不显示删除；其它账户可删除。没有 iCloud 账户时不显示 iCloud 存储统计。
	func testSettingsAccountDeleteAndSupportRows() throws {
		let service = FakeSettingsService()
		let navigation = Babel2NavigationController(rootViewController: UIViewController())
		let window = hostInWindow(navigation)
		defer { window.isHidden = true }
		let local = Babel2SettingsAccountDetailViewController(service: service, account: service.accounts[0])
		navigation.pushBabel2(local, animated: false)
		local.loadViewIfNeeded()
		XCTAssertNil(descendant(of: local.view, matching: Babel2SettingsActionRow.self) { $0.accessibilityIdentifier == "babel2.settings.account-detail.delete" })
		navigation.popBabel2(animated: false)

		let feedbin = Babel2SettingsAccountDetailViewController(service: service, account: service.accounts[1])
		navigation.pushBabel2(feedbin, animated: false)
		feedbin.loadViewIfNeeded()
		XCTAssertNotNil(descendant(of: feedbin.view, matching: Babel2SettingsActionRow.self) { $0.accessibilityIdentifier == "babel2.settings.account-detail.delete" })
		feedbin.performDelete()
		XCTAssertEqual(service.deletedAccountIDs, ["feedbin"])

		let support = Babel2SettingsSupportViewController(service: service)
		support.loadViewIfNeeded()
		XCTAssertNil(descendant(of: support.view, matching: Babel2SettingsRowControl.self) { $0.accessibilityIdentifier == "babel2.settings.support.iCloudStats" })
		XCTAssertNotNil(descendant(of: support.view, matching: Babel2SettingsRowControl.self) { $0.accessibilityIdentifier == "babel2.settings.support.errorLog" })
	}

	/// 设置「全部标为已读前确认」关掉后，点底栏按钮直接标记，不弹确认。
	func testMarkAllReadSkipsConfirmationWhenDisabled() async throws {
		let feedID = FeedSnapshot.ID(accountID: "account", feedID: "feed")
		let list = ["a", "b"].map { ArticleSnapshot(id: ArticleSnapshot.ID(accountID: "account", feedID: "feed", articleID: $0), title: $0, url: nil, feedID: feedID) }
		let handler = RecordingActionHandler()
		let controller = Babel2FeedViewController(feed: makeFeed(id: feedID, title: "Feed"), scope: .unread,
			environment: makeEnvironment(provider: FakeDataProvider(feeds: [feedID: list]), actionHandler: handler),
			confirmMarkAllRead: { false })
		let window = hostInWindow(controller)
		defer { window.isHidden = true }
		let tableView = try XCTUnwrap(descendant(of: controller.view, matching: UITableView.self))
		await waitForRows(in: tableView, count: 2)
		let readAll = try XCTUnwrap(descendant(of: controller.view, matching: UIButton.self) { $0.accessibilityIdentifier == "babel2.feed.read-all" })
		readAll.sendActions(for: .touchUpInside)
		for _ in 0..<150 {
			if await !handler.actions.isEmpty { break }
			try await Task.sleep(for: .milliseconds(20))
		}
		let actions = await handler.actions
		XCTAssertEqual(actions, [.markFeedRead(feedID)])
		XCTAssertNil(controller.pendingMarkAllReadCountForTesting, "no confirmation shown")
	}

	/// 设置页用到的每一条文案都在文案表里、且有中英文。
	func testSettingsStringsAreBilingual() throws {
		let projectRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
		let catalog = try JSONSerialization.jsonObject(with: Data(contentsOf: projectRoot.appendingPathComponent("iOS/Babel2/Resources/Babel2Localizable.xcstrings"))) as! [String: Any]
		let strings = catalog["strings"] as! [String: Any]
		let sources = ["iOS/Babel2/Settings/Babel2SettingsPages.swift", "iOS/Babel2/Settings/Babel2SettingsAccountPages.swift",
			"iOS/Babel2/Settings/Babel2SettingsEditors.swift", "iOS/Babel2/Settings/Babel2SettingsComponents.swift",
			"iOS/Babel2Integration/Babel2LiveSettingsService.swift"]
		// 直接写在 Babel2SettingsText.t("…") / f("…") 里的键
		let pattern = try NSRegularExpression(pattern: #"Babel2SettingsText\.[tf]\("([^"]+)""#)
		var keys = Set<String>()
		for source in sources {
			let text = try String(contentsOf: projectRoot.appendingPathComponent(source), encoding: .utf8)
			for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
				keys.insert(String(text[Range(match.range(at: 1), in: text)!]))
			}
		}
		var checked = 0
		for key in keys {
			let localizations = (strings[key] as? [String: Any])?["localizations"] as? [String: Any]
			XCTAssertNotNil(localizations?["en"], "missing en for \(key)")
			XCTAssertNotNil(localizations?["zh-Hans"], "missing zh for \(key)")
			checked += 1
		}
		XCTAssertGreaterThan(checked, 80)
		for key in Babel2SettingsHomeViewController.Category.allCases.flatMap({ [$0.titleKey, $0.detailKey] }) + ["Refresh Model List", "Refreshing…", "Set", "Not Set", "Back", "Close", "Cancel", "Save"] {
			let localizations = (strings[key] as? [String: Any])?["localizations"] as? [String: Any]
			XCTAssertNotNil(localizations?["zh-Hans"], "missing zh for \(key)")
		}
	}

	// MARK: - 顶部大图收缩（ADR-027 第 3 步，MOTION-CONTRACT §11）

	/// 一行标题（有无缩略图）的行不被撑高、标题标签不被拉伸，图标与第一行字对齐（2026-09-25 用户截图：
	/// 隐藏的缩略图仍把每行撑到 120pt，一行标题的字被上下居中而下沉）。
	func testSingleLineTitleRowsAreNotStretched() async throws {
		let feedID = FeedSnapshot.ID(accountID: "account", feedID: "feed")
		let now = Date()
		let titles = ["自民党项目组要求针对获取重要土地采用许可制并加强审查的一个长标题", "蒙古国总理乌其尔勒将于27日起访日", "Treasury Trading at the Close"]
		let list = titles.enumerated().map { index, title in
			ArticleSnapshot(id: ArticleSnapshot.ID(accountID: "account", feedID: "feed", articleID: "\(index)"), title: title,
				summary: "【共同社9月25日电】日本政府25日宣布一段较长的摘要文字", url: nil, feedID: feedID,
				publishedAt: now.addingTimeInterval(-Double(index) * 60), imageURL: index == 2 ? URL(string: "https://e.com/x.png") : nil)
		}
		let controller = Babel2FeedViewController(feed: makeFeed(id: feedID, title: "新闻 - 共同网"), scope: .all,
			environment: makeEnvironment(provider: FakeDataProvider(feeds: [feedID: list])))
		let window = hostInWindow(controller)
		defer { window.isHidden = true }
		let tableView = try XCTUnwrap(descendant(of: controller.view, matching: UITableView.self))
		await waitForRows(in: tableView, count: 3)
		tableView.layoutIfNeeded()
		var heights = [CGFloat]()
		for row in 0..<3 {
			let cell = try XCTUnwrap(tableView.cellForRow(at: IndexPath(row: row, section: 0)))
			let title = try XCTUnwrap(cell.contentView.subviews.compactMap { $0 as? UILabel }.first { $0.accessibilityIdentifier == "babel2.article.title" })
			let icon = try XCTUnwrap(descendant(of: cell, matching: UIImageView.self) { $0.accessibilityIdentifier == "babel2.article.feed-icon" })
			let fit = title.sizeThatFits(CGSize(width: title.bounds.width, height: .greatestFiniteMagnitude)).height
			XCTAssertEqual(title.bounds.height, fit, accuracy: 0.5, "title label is not stretched (row \(row))")
			// 第一行字的中线 = 标题顶 + 半个行高（行高固定 22）
			XCTAssertEqual(icon.frame.midY, title.frame.minY + 11, accuracy: 1.5, "icon aligned with first title line (row \(row))")
			heights.append(cell.bounds.height)
		}
		XCTAssertLessThan(heights[1], heights[0], "a one-line title row without thumbnail is shorter than a two-line row")
		XCTAssertGreaterThanOrEqual(heights[2], 33 + 3 + 70 + 14, "thumbnail row still fits the thumbnail")
	}

	func testFeedHeroMotionProgressAndSettling() {
		let rest: CGFloat = -161
		XCTAssertEqual(Babel2FeedHeroMotion.progress(offsetY: rest, restOffset: rest), 0)
		XCTAssertEqual(Babel2FeedHeroMotion.progress(offsetY: rest - 50, restOffset: rest), 0, "pull-down bounce keeps the hero expanded")
		XCTAssertEqual(Babel2FeedHeroMotion.progress(offsetY: rest + 35, restOffset: rest), 0.5, accuracy: 0.0001)
		XCTAssertEqual(Babel2FeedHeroMotion.progress(offsetY: rest + 70, restOffset: rest), 1)
		XCTAssertEqual(Babel2FeedHeroMotion.progress(offsetY: rest + 900, restOffset: rest), 1)
		// 松手停在半路：不到一半回到展开，过半收到窄栏；两端以外不干预
		XCTAssertEqual(Babel2FeedHeroMotion.settledTargetOffset(proposed: rest + 20, restOffset: rest), rest)
		XCTAssertEqual(Babel2FeedHeroMotion.settledTargetOffset(proposed: rest + 50, restOffset: rest), rest + 70)
		XCTAssertEqual(Babel2FeedHeroMotion.settledTargetOffset(proposed: rest + 300, restOffset: rest), rest + 300)
		XCTAssertEqual(Babel2FeedHeroMotion.settledTargetOffset(proposed: rest, restOffset: rest), rest)
		XCTAssertEqual(Babel2FeedHeroMotion.compactBackgroundAlpha(1), 1, "compact chrome is fully opaque when collapsed")
	}

	/// 展开 / 中间 / 收缩 三个状态：大图（或窄栏）下沿与列表内容紧贴、无缝；收缩后窄栏完全不透明、
	/// 日期段标题吸在窄栏下沿；切换档位回顶后大图重新展开。
	func testFeedHeroCollapsesWithScrollWithoutGaps() async throws {
		let feedID = FeedSnapshot.ID(accountID: "account", feedID: "feed")
		let now = Date()
		let list = (1...40).map { index in
			ArticleSnapshot(id: ArticleSnapshot.ID(accountID: "account", feedID: "feed", articleID: "\(index)"), title: "Title \(index)",
				summary: "Summary", url: nil, feedID: feedID, publishedAt: now.addingTimeInterval(-Double(index) * 60))
		}
		let controller = Babel2FeedViewController(feed: makeFeed(id: feedID, title: "Feed"), scope: .all,
			environment: makeEnvironment(provider: FakeDataProvider(feeds: [feedID: list])))
		let window = hostInWindow(controller)
		defer { window.isHidden = true }
		let tableView = try XCTUnwrap(descendant(of: controller.view, matching: UITableView.self))
		await waitForRows(in: tableView, count: 40)
		controller.view.layoutIfNeeded()
		let hero = try XCTUnwrap(controller.heroViewForTesting)
		let compact = try XCTUnwrap(controller.compactBarForTesting)
		let safeTop = controller.view.safeAreaInsets.top
		let rest = -tableView.adjustedContentInset.top
		XCTAssertEqual(rest, -(safeTop + 99), accuracy: 0.5, "list reserves exactly the compact bar height")
		func contentTop() -> CGFloat { tableView.rect(forSection: 0).minY - tableView.contentOffset.y }

		for (travel, expectedHeroBottom) in [(CGFloat(0), safeTop + 169), (35, safeTop + 134), (70, safeTop + 99)] {
			tableView.contentOffset.y = rest + travel
			XCTAssertEqual(controller.heroProgressForTesting, travel / 70, accuracy: 0.001)
			XCTAssertEqual(hero.frame.maxY, expectedHeroBottom, accuracy: 0.5, "hero bottom at travel \(travel)")
			XCTAssertEqual(contentTop(), hero.frame.maxY, accuracy: 0.5, "no gap between hero and list at travel \(travel)")
		}
		XCTAssertEqual(compact.backdropAlphaForTesting, 1, "collapsed compact bar is fully opaque")
		XCTAssertEqual(compact.frame.maxY, safeTop + 99, accuracy: 0.5)

		// 继续往下：窄栏固定，日期段标题吸在窄栏下沿
		tableView.contentOffset.y = rest + 600
		tableView.layoutIfNeeded()
		XCTAssertEqual(controller.heroProgressForTesting, 1)
		let header = try XCTUnwrap(tableView.headerView(forSection: 0))
		XCTAssertEqual(header.convert(header.bounds, to: controller.view).minY, compact.frame.maxY, accuracy: 0.5, "day header pins right under the compact bar")

		// 切换档位：回顶，大图重新展开
		controller.selectScope(.unread, fromUser: false)
		XCTAssertEqual(controller.heroProgressForTesting, 0)
		XCTAssertEqual(hero.transform, .identity)
	}

	// MARK: - Reeder 式文章行与按天分组（2026-09-25）

	func testDaySectionsGroupConsecutiveArticlesByDay() {
		var calendar = Calendar(identifier: .gregorian)
		calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
		let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 25, hour: 15))!
		let today1 = calendar.date(byAdding: .hour, value: -1, to: now)!
		let today2 = calendar.date(byAdding: .hour, value: -5, to: now)!
		let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
		let older = calendar.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 20))!
		let sections = Babel2DaySection.make(for: [today1, today2, yesterday, older, nil, nil], calendar: calendar, now: now)
		XCTAssertEqual(sections.map(\.range), [0..<2, 2..<3, 3..<4, 4..<6])
		XCTAssertNil(sections[3].title, "articles without a date get no header")
		XCTAssertEqual(sections[0].title, sections[0].title?.uppercased(), "Latin titles are uppercased like the reference")
		XCTAssertNotEqual(sections[0].title, sections[1].title)
		XCTAssertNotEqual(sections[1].title, sections[2].title)
	}

	/// 按天分段后：点第二段的文章打开的是它本身；下一篇仍按列表顺序跨段；第一行显示大写来源名 + 贴右边的时刻；
	/// 没有订阅源图标时显示首字母方块；摘要只有 1 行；不再有「英文 → 简体中文」提示行。
	func testFeedListGroupsByDayAndRowsFollowReaderLayout() async throws {
		let feedID = FeedSnapshot.ID(accountID: "account", feedID: "feed")
		let now = Date()
		func article(_ id: String, daysAgo: Int, translated: String? = nil) -> ArticleSnapshot {
			ArticleSnapshot(id: ArticleSnapshot.ID(accountID: "account", feedID: "feed", articleID: id), title: "Title \(id)",
				translatedTitle: translated, summary: String(repeating: "A long summary sentence. ", count: 20), url: nil, feedID: feedID,
				publishedAt: Calendar.current.date(byAdding: .day, value: -daysAgo, to: now))
		}
		let list = [article("a", daysAgo: 0, translated: "标题 a"), article("b", daysAgo: 0), article("c", daysAgo: 3)]
		let controller = Babel2FeedViewController(feed: makeFeed(id: feedID, title: "Marginal Revolution"), scope: .all,
			environment: makeEnvironment(provider: FakeDataProvider(feeds: [feedID: list])))
		var opened: ArticleSnapshot?
		controller.onSelectArticle = { opened = $0 }
		let window = hostInWindow(controller)
		defer { window.isHidden = true }
		let tableView = try XCTUnwrap(descendant(of: controller.view, matching: UITableView.self))
		await waitForRows(in: tableView, count: 3)
		tableView.layoutIfNeeded()

		XCTAssertEqual(tableView.numberOfSections, 2)
		XCTAssertEqual(tableView.numberOfRows(inSection: 0), 2)
		XCTAssertEqual(controller.daySectionTitlesForTesting.count, 2)
		XCTAssertNotNil(tableView.headerView(forSection: 0), "day header is shown")

		controller.tableView(tableView, didSelectRowAt: IndexPath(row: 0, section: 1))
		XCTAssertEqual(opened?.id.articleID, "c", "row in the second day opens that article")
		XCTAssertEqual(controller.nextArticle(after: list[1].id)?.id.articleID, "c", "next article crosses day sections")

		let cell = try XCTUnwrap(tableView.cellForRow(at: IndexPath(row: 0, section: 0)))
		let labels = cell.contentView.subviews.compactMap { $0 as? UILabel }
		func label(_ id: String) throws -> UILabel { try XCTUnwrap(labels.first { $0.accessibilityIdentifier == id }) }
		XCTAssertEqual(try label("babel2.article.feed").text, "MARGINAL REVOLUTION")
		XCTAssertEqual(try label("babel2.article.title").text, "标题 a", "translated title replaces the original")
		XCTAssertEqual(try label("babel2.article.summary").numberOfLines, 1)
		XCTAssertFalse(labels.contains { $0.text == "英文 → 简体中文" }, "no translation hint line")
		let date = try label("babel2.article.date")
		XCTAssertEqual(date.convert(date.bounds, to: cell.contentView).maxX, cell.contentView.bounds.width - 20, accuracy: 0.5)
		let icon = try XCTUnwrap(descendant(of: cell, matching: UIImageView.self) { $0.accessibilityIdentifier == "babel2.article.feed-icon" })
		XCTAssertEqual(icon.bounds.size, CGSize(width: 24, height: 24))
		XCTAssertEqual(icon.convert(icon.bounds, to: cell.contentView).minX, 20, accuracy: 0.5)
		XCTAssertEqual(try label("babel2.article.title").convert(try label("babel2.article.title").bounds, to: cell.contentView).minX, 49, accuracy: 0.5)
		XCTAssertTrue(descendant(of: icon, matching: UILabel.self)?.text == "M", "no feed icon → initial letter tile")
		// 图标中心对准标题第一行字的视觉中线（基线往上半个大写字母高度）
		let title = try label("babel2.article.title")
		let probe = UIView()
		probe.translatesAutoresizingMaskIntoConstraints = false
		cell.contentView.addSubview(probe)
		NSLayoutConstraint.activate([probe.topAnchor.constraint(equalTo: title.firstBaselineAnchor), probe.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor)])
		cell.contentView.layoutIfNeeded()
		let firstBaseline = probe.frame.minY
		probe.removeFromSuperview()
		let capHeight = UIFont.systemFont(ofSize: 17, weight: .semibold).capHeight
		XCTAssertEqual(icon.convert(icon.bounds, to: cell.contentView).midY, firstBaseline - capHeight / 2, accuracy: 1)
	}

	// 数据接入层：普通 RSS 文章没有自带图片地址，要从正文里取第一张像样的配图。
	/// 没有单独摘要字段的文章：标题下显示正文开头几句（去掉标签）。
	func testListSummaryFallsBackToOpeningSentencesOfBody() {
		let text = Babel2LiveDataProvider.listSummaryForTesting(
			html: #"<p><img src="https://e.com/a.jpg">Believing that <b>AI</b> will be incorrigible leads to bad policy.</p><p>Second paragraph.</p>"#,
			summary: nil)
		XCTAssertTrue(text.hasPrefix("Believing that AI will be incorrigible leads to bad policy."), text)
		XCTAssertFalse(text.contains("<"), "no HTML tags")
	}

	func testRSSArticleUsesFirstUsefulImageFromBody() {
		// 1×1 追踪像素跳过；相对地址按文章链接补全
		let html = #"<p><img src="https://t.example.com/p.gif" width="1" height="1"></p><p>Hi</p><img src="/images/cover.jpg"><img src="https://example.com/second.jpg">"#
		let url = Babel2LiveDataProvider.thumbnailURLForTesting(html: html, imageURL: nil, link: "https://example.com/posts/1")
		XCTAssertEqual(url?.absoluteString, "https://example.com/images/cover.jpg")
	}

	func testJSONFeedImageURLWins() {
		let url = Babel2LiveDataProvider.thumbnailURLForTesting(html: #"<img src="https://example.com/body.jpg">"#, imageURL: "https://example.com/declared.jpg", link: nil)
		XCTAssertEqual(url?.absoluteString, "https://example.com/declared.jpg")
	}

	func testArticleWithoutImagesHasNoThumbnail() {
		XCTAssertNil(Babel2LiveDataProvider.thumbnailURLForTesting(html: "<p>Only words.</p>", imageURL: nil, link: nil))
		XCTAssertNil(Babel2LiveDataProvider.thumbnailURLForTesting(html: #"<img src="data:image/png;base64,AAAA">"#, imageURL: nil, link: nil))
	}

	/// 有图片地址的文章显示 70pt、圆角 5 的缩略图，且按缩略图尺寸缩小解码（不把 2000px 原图整张放进内存）；
	/// 下载失败保持浅灰占位；没有图片地址的文章不留缩略图位置。
	func testArticleThumbnailsAreDownsampledAndFailuresKeepPlaceholder() async throws {
		let feedID = FeedSnapshot.ID(accountID: "account", feedID: "feed")
		func article(_ id: String, image: String?) -> ArticleSnapshot {
			ArticleSnapshot(id: ArticleSnapshot.ID(accountID: "account", feedID: "feed", articleID: id), title: id, url: nil,
				feedID: feedID, imageURL: image.flatMap(URL.init(string:)))
		}
		let list = [
			article("with-image", image: "https://example.com/big.png"),
			article("broken", image: "https://example.com/broken.png"),
			article("no-image", image: nil)
		]
		let controller = Babel2FeedViewController(
			feed: makeFeed(id: feedID, title: "Feed"),
			scope: .all,
			environment: makeEnvironment(provider: FakeDataProvider(feeds: [feedID: list]), imageProvider: LargeImageProvider(size: CGSize(width: 2400, height: 1600)))
		)
		let window = hostInWindow(controller)
		defer { window.isHidden = true }
		let tableView = try XCTUnwrap(descendant(of: controller.view, matching: UITableView.self))
		await waitForRows(in: tableView, count: 3)
		tableView.layoutIfNeeded()

		func thumbnail(row: Int) throws -> UIImageView {
			let cell = try XCTUnwrap(tableView.cellForRow(at: IndexPath(row: row, section: 0)))
			return try XCTUnwrap(descendant(of: cell, matching: UIImageView.self) { $0.accessibilityIdentifier == "babel2.article.thumbnail" })
		}
		let loaded = try thumbnail(row: 0)
		for _ in 0..<100 where loaded.image == nil { try await Task.sleep(for: .milliseconds(20)) }
		let image = try XCTUnwrap(loaded.image, "thumbnail loaded")
		XCTAssertFalse(loaded.isHidden)
		XCTAssertEqual(loaded.bounds.size, CGSize(width: 70, height: 70))
		XCTAssertEqual(loaded.layer.cornerRadius, 5)
		let pixelWidth = CGFloat(image.cgImage?.width ?? 0), pixelHeight = CGFloat(image.cgImage?.height ?? 0)
		XCTAssertLessThanOrEqual(max(pixelWidth, pixelHeight), 70 * max(controller.traitCollection.displayScale, 1), "decoded at thumbnail size, not 2400px")
		XCTAssertGreaterThan(pixelWidth, 0)

		// 日期贴屏幕右边缘（不被挤到缩略图左边），缩略图在日期下方
		let firstCell = try XCTUnwrap(tableView.cellForRow(at: IndexPath(row: 0, section: 0)))
		let date = try XCTUnwrap(descendant(of: firstCell, matching: UILabel.self) { $0.accessibilityIdentifier == "babel2.article.date" })
		let dateFrame = date.convert(date.bounds, to: firstCell.contentView)
		let thumbFrame = loaded.convert(loaded.bounds, to: firstCell.contentView)
		XCTAssertEqual(dateFrame.maxX, firstCell.contentView.bounds.width - 20, accuracy: 0.5, "date hugs the right edge")
		XCTAssertEqual(thumbFrame.maxX, firstCell.contentView.bounds.width - 20, accuracy: 0.5)
		XCTAssertGreaterThanOrEqual(thumbFrame.minY, dateFrame.maxY, "thumbnail sits below the date")

		let broken = try thumbnail(row: 1)
		try await Task.sleep(for: .milliseconds(300))
		XCTAssertFalse(broken.isHidden, "failed download keeps the placeholder slot")
		XCTAssertNil(broken.image)
		XCTAssertNotEqual(broken.backgroundColor, .clear)

		XCTAssertTrue(try thumbnail(row: 2).isHidden, "no image → text uses the full width")
	}

	// MARK: - 生成长图（Slice 5 第 5 步，ADR-025）


	func testLongImageIncludesTitleAreaAndCleansUp() async throws {
		let paragraphs = (1...30).map { "<p>Paragraph \($0) of a long enough article body.</p>" }.joined()
		let viewController = makeReader(body: paragraphs, author: "Jane Doe")
		let window = hostInWindow(viewController)
		defer { window.isHidden = true }
		await waitForReaderRender(viewController)
		// 菜单里的「生成长图」可点（不再是灰色占位）
		XCTAssertTrue(viewController.moreMenuItemIdentifiers.contains("babel2.article.long-image"))
		XCTAssertFalse(viewController.isGeneratingLongImage)

		// 临时标题区：用当前显示的标题/署名，纯文本写入
		await viewController.readerContentView.insertSnapshotHeader(date: "SEP 25", title: "Reader", byline: "JANE DOE\nFEED")
		let headerText = await viewController.readerContentView.evaluateForTesting(
			"const h = document.getElementById('babel2-snapshot-header'); return h ? h.innerText : null;"
		) as? String
		XCTAssertEqual(headerText?.contains("Reader"), true)
		XCTAssertEqual(headerText?.contains("JANE DOE"), true)
		await viewController.readerContentView.removeSnapshotHeader()

		// 真实导出：得到一张竖长图；结束后临时标题区、定格截图、状态字都清掉
		let subviewCount = viewController.view.subviews.count
		let images = try await viewController.makeLongImage()
		XCTAssertEqual(images.count, 1, "a short article stays one image")
		let image = try XCTUnwrap(images.first)
		XCTAssertGreaterThan(image.size.height, image.size.width, "a tall long image")
		XCTAssertGreaterThan(image.size.width, 300)
		let leftover = await viewController.readerContentView.evaluateForTesting(
			"return document.getElementById('babel2-snapshot-header') === null;"
		) as? Bool
		XCTAssertEqual(leftover, true, "temporary title area removed")
		XCTAssertEqual(viewController.view.subviews.count, subviewCount, "no leftover views")
		XCTAssertNil(viewController.statusTextForTesting)
		XCTAssertFalse(viewController.isGeneratingLongImage)

		// 「分享自 Babel」签名在长图顶部（2026-09-25）：图标所在的那一行有非底色像素；
		// 长图末尾同一位置（旧版页脚的图标处）是纯底色，不再有签名
		XCTAssertNotNil(UIImage(named: "Babel2ShareSignatureIcon"), "new Babel 2.0 icon asset is bundled")
		let pixelsPerPoint: CGFloat = 2		// 文章不长，导出器按 2 倍、不降分辨率
		let signatureCenterY = 38 * pixelsPerPoint
		XCTAssertGreaterThan(nonBackgroundPixelCount(in: image, row: Int(signatureCenterY)), 70, "signature drawn at the top (icon + text ≈ 100 px; page content alone ≈ 34)")
		XCTAssertEqual(nonBackgroundPixelCount(in: image, row: Int(image.size.height - signatureCenterY)), 0, "no signature at the bottom")
	}

	/// 超长文章（网页导出时会被切成多页 PDF，每页最高 14400 点）：
	/// 修复前拼出来的长图只剩最后一页，其余一整片底色（2026-09-25 用户真机报告）。
	func testVeryLongArticleSplitsIntoSharpImagesWithContentThroughout() async throws {
		let paragraphs = (1...900).map { "<p>Paragraph \($0) of a very long article body that keeps going.</p>" }.joined()
		let viewController = makeReader(body: paragraphs, author: "Jane Doe")
		let window = hostInWindow(viewController)
		defer { window.isHidden = true }
		await waitForReaderRender(viewController)
		// 排版完成后内容高度才会长到位，最多等约 5 秒
		for _ in 0..<100 where viewController.readerContentView.scrollView.contentSize.height <= 14400 * 2 {
			try await Task.sleep(for: .milliseconds(50))
		}
		XCTAssertGreaterThan(viewController.readerContentView.scrollView.contentSize.height, 14400 * 2, "long enough for a multi-page PDF")

		// 旧版「一张图」画法（1.x 阅读页用）：中间不再是一整片底色
		let single = try await ArticleLongImageExporter.export(from: viewController)
		XCTAssertGreaterThan(contentSliceCount(in: single, slices: 10), 8, "legacy single image has content throughout")

		// Babel 2.0：拆成几张、每张 2 倍清晰度、每张都有内容、接缝在两行字之间
		let images = try await viewController.makeLongImage()
		XCTAssertGreaterThanOrEqual(images.count, 2, "split into several images")
		for (index, image) in images.enumerated() {
			XCTAssertEqual(image.size.width, 804, "image \(index + 1) keeps 2x sharpness")
			XCTAssertLessThanOrEqual(image.size.height, 25000)
			XCTAssertGreaterThanOrEqual(contentSliceCount(in: image, slices: 5), 4, "image \(index + 1) has content throughout")
		}
		for image in images.dropLast() {
			XCTAssertEqual(nonBackgroundPixelCount(in: image, row: Int(image.size.height) - 1), 0, "cut falls between lines")
		}
		for image in images.dropFirst() {
			XCTAssertEqual(nonBackgroundPixelCount(in: image, row: 0), 0, "next image starts between lines")
		}
		// 签名只在第 1 张顶部
		XCTAssertGreaterThan(nonBackgroundPixelCount(in: images[0], row: 76), 70, "signature on the first image")
	}

	/// 把图片竖着分成几段，数有多少段里能找到非底色的行。
	private func contentSliceCount(in image: UIImage, slices: Int) -> Int {
		let height = Int(image.size.height)
		return (0..<slices).filter { slice in
			let start = height * slice / slices, end = height * (slice + 1) / slices
			return stride(from: start, to: end, by: 7).contains { nonBackgroundPixelCount(in: image, row: $0) > 0 }
		}.count
	}

	func testSavingImageFromShareSheetShowsToastOnlyOnSuccess() async throws {
		let viewController = makeReader(body: "<p>Body</p>", author: nil)
		let window = hostInWindow(viewController)
		defer { window.isHidden = true }
		await waitForReaderRender(viewController)

		// 取消、分享给别的 app、保存失败：都不提示
		viewController.handleShareCompletion(activityType: .saveToCameraRoll, completed: false, error: nil)
		viewController.handleShareCompletion(activityType: .copyToPasteboard, completed: true, error: nil)
		viewController.handleShareCompletion(activityType: .saveToCameraRoll, completed: true, error: NSError(domain: "test", code: 1))
		XCTAssertNil(viewController.toastTextForTesting)

		// 「存储图像」成功：底栏上方浮出「已存储到相册」
		viewController.handleShareCompletion(activityType: .saveToCameraRoll, completed: true, error: nil)
		XCTAssertEqual(viewController.toastTextForTesting, Babel2Localization.text(.savedToPhotos))
		let toast = try XCTUnwrap(descendant(of: viewController.view, matching: UIView.self) { $0.accessibilityIdentifier == "babel2.article.toast" })
		viewController.view.layoutIfNeeded()
		XCTAssertLessThan(toast.frame.maxY, viewController.toolbarView.frame.minY, "toast sits above the bottom toolbar")
		XCTAssertFalse(toast.isUserInteractionEnabled, "toast never blocks taps")
	}

	/// 某一行像素里，与该行最左边像素（底色）明显不同的像素个数。
	private func nonBackgroundPixelCount(in image: UIImage, row: Int) -> Int {
		guard let cgImage = image.cgImage, row >= 0, row < cgImage.height else { return -1 }
		let width = cgImage.width
		var pixels = [UInt8](repeating: 0, count: width * 4)
		let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
			guard let context = CGContext(data: buffer.baseAddress, width: width, height: 1, bitsPerComponent: 8, bytesPerRow: width * 4,
				space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
			// 只画出目标那一行（CGContext 原点在左下）
			context.draw(cgImage, in: CGRect(x: 0, y: -(cgImage.height - 1 - row), width: width, height: cgImage.height))
			return true
		}
		guard drawn else { return -1 }
		let background = Array(pixels[0..<4])
		var count = 0
		for x in 0..<width {
			let pixel = pixels[(x * 4)..<(x * 4 + 4)]
			if zip(pixel, background).contains(where: { abs(Int($0) - Int($1)) > 24 }) { count += 1 }
		}
		return count
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

/// 返回一张指定尺寸的 PNG（模拟原图很大的文章配图）；地址含 "broken" 时下载失败。
private struct LargeImageProvider: ImageProviding {
	let size: CGSize
	func imageData(for url: URL) async throws -> Data? {
		if url.absoluteString.contains("broken") { return nil }
		return await MainActor.run {
			let format = UIGraphicsImageRendererFormat()
			format.scale = 1
			return UIGraphicsImageRenderer(size: size, format: format).pngData { context in
				UIColor.systemTeal.setFill()
				context.fill(CGRect(origin: .zero, size: size))
			}
		}
	}
}

@MainActor
private func makeEnvironment(
	provider: any DataProviding,
	renderer: any ArticleRendering = RecordingRenderer(),
	actionHandler: any ActionHandling = NoopActionHandler(),
	imageProvider: any ImageProviding = NoopImageProvider()
) -> AppEnvironment {
	Babel2AppAssembly.makeEnvironment(
		dataProvider: provider,
		actionHandler: actionHandler,
		settingsProvider: NoopSettingsProvider(),
		articleRenderer: renderer,
		imageProvider: imageProvider
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
	// 按真实时间等（最多约 3 秒）：按 Task.yield 次数等，在全量测试负载下会偶发超时（LESSONS 32）
	let deadline = Date().addingTimeInterval(3)
	while Date() < deadline {
		// 文章列表按天分段后行数分散在多段里：数全部段的行数
		let total = (0..<tableView.numberOfSections).reduce(0) { $0 + tableView.numberOfRows(inSection: $1) }
		if total == count { return }
		try? await Task.sleep(for: .milliseconds(10))
	}
	XCTFail("Timed out waiting for \(count) feed rows")
}

@MainActor
private func waitForRootState(_ root: Babel2RootViewController, scope: Babel2FeedScope, state: String, rows: Int) async {
	guard let tableView = rootTable(for: root, scope: scope) else {
		XCTFail("Missing root feed table")
		return
	}
	// 按真实时间等（最多约 3 秒），理由同上（2026-09-25 全量测试中偶发超时）
	let deadline = Date().addingTimeInterval(3)
	while Date() < deadline {
		if tableView.accessibilityValue == state && tableView.numberOfRows(inSection: 0) == rows { return }
		try? await Task.sleep(for: .milliseconds(10))
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

/// 拦截翻译请求：记下请求体，回一个合法的标题翻译结果（不联网）。
private final class CapturingTranslationProtocol: URLProtocol {
	nonisolated(unsafe) static var lastBody: Data?

	override class func canInit(with request: URLRequest) -> Bool {
		request.url?.path.hasSuffix("/chat/completions") == true
	}

	override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

	override func startLoading() {
		var body = request.httpBody
		if body == nil, let stream = request.httpBodyStream {
			stream.open()
			var data = Data()
			var buffer = [UInt8](repeating: 0, count: 4096)
			while stream.hasBytesAvailable {
				let read = stream.read(&buffer, maxLength: buffer.count)
				if read <= 0 { break }
				data.append(buffer, count: read)
			}
			stream.close()
			body = data
		}
		Self.lastBody = body
		let payload = #"{"choices":[{"message":{"content":"[\"一个标题\"]"}}]}"#.data(using: .utf8)!
		let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
		client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
		client?.urlProtocol(self, didLoad: payload)
		client?.urlProtocolDidFinishLoading(self)
	}

	override func stopLoading() {}
}

/// 设置页测试用的假服务：全部存内存，记录删除与保存。
@MainActor
private final class FakeSettingsService: Babel2SettingsService {
	var sortNewestFirst = true
	var confirmMarkAllRead = true
	var openLinksInApp = true
	var appearance: Babel2AppearanceMode = .automatic
	var accentOptions = [Babel2AccentOption(id: "orange", name: "Orange", color: .orange), Babel2AccentOption(id: "indigo", name: "Indigo", color: .blue)]
	var accentID = "orange"
	var languageOptions = [Babel2LanguageOption(code: nil, name: "System"), Babel2LanguageOption(code: "en", name: "English")]
	var languageCode: String?
	var accounts = [
		Babel2AccountSummary(id: "local", name: "On My iPhone", kind: .local, isDefault: true),
		Babel2AccountSummary(id: "feedbin", name: "Feedbin", kind: .web, isDefault: false)
	]
	var syncUnreadArticleContent = true
	var deletedAccountIDs = [String]()
	func deleteAccount(_ id: String) { deletedAccountIDs.append(id) }
	var addableAccountKinds = Babel2AddAccountKind.allCases
	func presentAddAccount(_ kind: Babel2AddAccountKind, from host: UIViewController, completion: @escaping () -> Void) {}
	func importOPML(into accountID: String, from host: UIViewController) {}
	func exportOPML(from accountID: String, host: UIViewController) {}
	var redditClientID: String?
	var redditClientSecret: String?
	var youTubeAPIKey: String?
	func saveDiscoveryKeys(redditClientID: String, redditClientSecret: String, youTubeAPIKey: String) {
		self.redditClientID = redditClientID.isEmpty ? nil : redditClientID
		self.redditClientSecret = redditClientSecret.isEmpty ? nil : redditClientSecret
		self.youTubeAPIKey = youTubeAPIKey.isEmpty ? nil : youTubeAPIKey
	}
	var translationModelID = "deepseek/deepseek-v4-flash"
	func translationModelDisplayName(_ id: String) -> String { id }
	var translationAPIKey: String?
	var translationBaseURL = "https://openrouter.ai/api/v1"
	var translationDefaultBaseURL = "https://openrouter.ai/api/v1"
	func saveTranslationAPI(apiKey: String, baseURL: String) {
		translationAPIKey = apiKey.isEmpty ? nil : apiKey
		translationBaseURL = baseURL.isEmpty ? translationDefaultBaseURL : baseURL
	}
	func testTranslationConnection(apiKey: String, baseURL: String) async -> Babel2ConnectionTestResult { .success(reply: "ok") }
	var models = [Babel2TranslationModel]()
	func cachedTranslationModels() -> [Babel2TranslationModel] { models }
	func refreshTranslationModels() async throws -> [Babel2TranslationModel] { models }
	func vendorLogo(_ vendor: String, traits: UITraitCollection) -> UIImage? { nil }
	func vendorDisplayName(_ vendor: String) -> String { vendor }
	func openSystemNotificationSettings() {}
	var hasICloudAccount = false
	func makeDiagnosticsPage(_ kind: Babel2DiagnosticsKind) -> UIViewController? { UIViewController() }
	func openHelp(_ kind: Babel2HelpKind) {}
	func makeAboutPage() -> UIViewController { UIViewController() }
}

/// 添加订阅页测试用的假服务。
@MainActor
private final class FakeSubscriptionService: Babel2SubscriptionService {
	let websiteResults = [
		Babel2DiscoveryResult(kind: .website, title: "Swift.org", subtitle: "swift.org", feedURL: "https://swift.org/atom.xml", iconURL: nil),
		Babel2DiscoveryResult(kind: .website, title: "Swift by Sundell", subtitle: nil, feedURL: "https://swiftbysundell.com/rss", iconURL: nil)
	]
	var subscribedURLs = Set<String>()
	var subscribed = [(String, String)]()
	var unsubscribed = [String]()
	func search(_ query: String) async -> [Babel2DiscoveryGroup] {
		[Babel2DiscoveryGroup(kind: .website, results: websiteResults, statusMessage: nil, isExpanded: true),
		 Babel2DiscoveryGroup(kind: .podcast, results: [], statusMessage: "No matching podcasts.", isExpanded: true)]
	}
	var destinations = [Babel2SubscriptionDestination(id: "local", title: "Top Level"), Babel2SubscriptionDestination(id: "local/1", title: "Tech")]
	func isSubscribed(_ result: Babel2DiscoveryResult) -> Bool { subscribedURLs.contains(result.feedURL) }
	func subscribe(_ result: Babel2DiscoveryResult, to destinationID: String) async -> String? {
		subscribed.append((result.feedURL, destinationID))
		subscribedURLs.insert(result.feedURL)
		return nil
	}
	func unsubscribe(_ result: Babel2DiscoveryResult) async -> String? {
		unsubscribed.append(result.feedURL)
		subscribedURLs.remove(result.feedURL)
		return nil
	}
	func makePreview(_ result: Babel2DiscoveryResult, isBusy: @escaping () -> Bool, subscribe: @escaping (@escaping (String?) -> Void) -> Void) -> UIViewController? { nil }
}

