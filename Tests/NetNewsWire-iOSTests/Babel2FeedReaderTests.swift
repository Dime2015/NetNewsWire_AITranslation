import XCTest
import UIKit
import WebKit
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
		let translation = try XCTUnwrap(descendant(of: feedViewController.view, matching: Babel2TranslateIconButton.self))
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

	/// 「● UNREAD」圆点和文字叠在一起（2026-09-27 用户反馈，第一次打开某个源时偶发）：
	/// 图标和文字的位置由按钮自己算，文字永远从图标右边开始、完整显示；
	/// 第一次排版发生在动画里（像页面滑入那样）、来回切档、按下缩放后，量真正画出来的视图都不重叠。
	func testScopeButtonsNeverDrawTitleOverIcon() async throws {
		// 纯规则：选中时文字起点 = 图标右边 + 间距；没选中只居中画图标
		let rule = Babel2ScopeButton.contentFrames(in: CGSize(width: 78, height: 44), iconSize: CGSize(width: 9, height: 9),
			textSize: CGSize(width: 40, height: 12), showsTitle: true, leadingInset: 8, iconSpacing: 7, scale: 3)
		XCTAssertEqual(rule.icon.minX, 8, accuracy: 0.01)
		XCTAssertEqual(try XCTUnwrap(rule.text).minX, rule.icon.maxX + 7, accuracy: 0.34)
		let plain = Babel2ScopeButton.contentFrames(in: CGSize(width: 78, height: 44), iconSize: CGSize(width: 9, height: 9),
			textSize: CGSize(width: 40, height: 12), showsTitle: false, leadingInset: 8, iconSpacing: 7, scale: 3)
		XCTAssertNil(plain.text)
		XCTAssertEqual(plain.icon.midX, 39, accuracy: 0.34)

		let feedID = FeedSnapshot.ID(accountID: "account", feedID: "feed")
		let provider = FakeDataProvider(feeds: [feedID: []])
		let controller = Babel2FeedViewController(feed: makeFeed(id: feedID, title: "Feed"), scope: .unread,
			environment: makeEnvironment(provider: provider))
		let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
		window.rootViewController = controller
		window.makeKeyAndVisible()
		defer { window.isHidden = true }
		// 第一次排版放在动画里（页面滑入时就是这样）
		UIView.animate(withDuration: 0.35) { controller.view.layoutIfNeeded() }
		let filter = controller.scopeFilterForTesting

		func assertSelectedLooksRight(_ scope: Babel2FeedScope, _ note: String, line: UInt = #line) {
			filter.layoutIfNeeded()
			guard let button = filter.buttons[scope] else { return XCTFail("no button", line: line) }
			button.layoutIfNeeded()
			let icon = button.iconViewForTesting.frame, text = button.textLabelForTesting.frame
			XCTAssertFalse(button.textLabelForTesting.isHidden, "\(scope) title shown (\(note))", line: line)
			XCTAssertGreaterThan(icon.width, 0, line: line)
			XCTAssertGreaterThanOrEqual(text.minX, icon.maxX + 5.5, "\(scope) title starts right of the icon (\(note))", line: line)
			XCTAssertLessThanOrEqual(text.maxX, button.bounds.width + 0.01, line: line)
			let fits = button.textLabelForTesting.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: 44)).width
			XCTAssertGreaterThanOrEqual(text.width, fits - 0.01, "\(scope) title is not cut off (\(note))", line: line)
			for (other, otherButton) in filter.buttons where other != scope {
				XCTAssertTrue(otherButton.textLabelForTesting.isHidden, "\(other) shows only its icon (\(note))", line: line)
			}
		}
		assertSelectedLooksRight(.unread, "first layout inside an animation")
		for scope in [Babel2FeedScope.all, .starred, .unread, .starred, .all, .unread] {
			filter.buttons[scope]?.sendActions(for: .touchUpInside)
			assertSelectedLooksRight(scope, "after switching")
		}
		// 按下缩放（94%）时：相对位置不变
		let unread = try XCTUnwrap(filter.buttons[.unread])
		unread.transform = CGAffineTransform(scaleX: 0.94, y: 0.94)
		unread.setNeedsLayout()
		assertSelectedLooksRight(.unread, "while pressed")
		unread.transform = .identity
		// 外部同步档位（首页那条底栏走这条路）
		filter.setSelectedScope(.all, animated: true)
		filter.setSelectedScope(.unread, animated: false)
		assertSelectedLooksRight(.unread, "after external sync")
	}

	/// ADR-033：文章列表底栏五个控件 x = 32 / 116.5 / 201 / 285.5 / 370，同一条中线 y = 24。
	func testFeedToolbarControlsAreEvenlySpacedOnOneCenterline() async throws {
		let feedID = FeedSnapshot.ID(accountID: "account", feedID: "feed")
		let feed = makeFeed(id: feedID, title: "Feed")
		let provider = FakeDataProvider(feeds: [feedID: []])
		let navigationController = Babel2SceneComposition.makeRoot(environment: makeEnvironment(provider: provider))
		let root = try XCTUnwrap(navigationController.viewControllers.first as? Babel2RootViewController)
		root.onFeedRequested?(feed, .unread)
		let feedViewController = try XCTUnwrap(navigationController.topViewController as? Babel2FeedViewController)
		let window = hostInWindow(feedViewController)
		defer { window.isHidden = true }
		let toolbar = try XCTUnwrap(descendant(of: feedViewController.view, matching: UIView.self) { $0.accessibilityIdentifier == "babel2.feed.toolbar" })
		let filter = feedViewController.scopeFilterForTesting
		let readAll = try XCTUnwrap(descendant(of: toolbar, matching: UIButton.self) { $0.accessibilityIdentifier == "babel2.feed.read-all" })
		let translation = try XCTUnwrap(descendant(of: toolbar, matching: Babel2TranslateIconButton.self))
		let controls: [UIView] = [readAll, try XCTUnwrap(filter.buttons[.starred]), try XCTUnwrap(filter.buttons[.unread]), try XCTUnwrap(filter.buttons[.all]), translation]
		let centers = controls.map { $0.convert(CGPoint(x: $0.bounds.midX, y: $0.bounds.midY), to: toolbar) }
		for (center, expectedX) in zip(centers, [32, 116.5, 201, 285.5, 370] as [CGFloat]) {
			XCTAssertEqual(center.x, expectedX, accuracy: 0.5)
			XCTAssertEqual(center.y, 24, accuracy: 0.5)
		}
	}

	// MARK: - 动效（ADR-034）

	func testMotionUsesThreeDurationsAndReduceMotionRemovesMovement() {
		XCTAssertEqual(Babel2Motion.quick, 0.15)
		XCTAssertEqual(Babel2Motion.standard, 0.22)
		XCTAssertEqual(Babel2Motion.page, 0.32)
		defer { Babel2Motion.reduceMotionOverride = nil }
		Babel2Motion.reduceMotionOverride = false
		XCTAssertEqual(Babel2Motion.offset(12), 12)
		Babel2Motion.reduceMotionOverride = true
		XCTAssertEqual(Babel2Motion.offset(12), 0, "Reduce Motion: fades only, no movement")
	}

	/// 切档：旧列表截图盖着、没有「加载中…」闪白；数据到了交叉淡入，列表恢复完全不透明、无位移。
	func testFeedScopeSwitchCrossfadesWithoutBlankState() async throws {
		let feedID = FeedSnapshot.ID(accountID: "account", feedID: "feed")
		let feed = makeFeed(id: feedID, title: "Feed")
		let article = makeArticle(accountID: "account", feedID: "feed", articleID: "a", title: "A", body: "<p>A</p>", url: nil)
		let provider = FakeDataProvider(feeds: [feedID: [article]])
		let navigationController = Babel2SceneComposition.makeRoot(environment: makeEnvironment(provider: provider))
		let root = try XCTUnwrap(navigationController.viewControllers.first as? Babel2RootViewController)
		root.onFeedRequested?(feed, .unread)
		let controller = try XCTUnwrap(navigationController.topViewController as? Babel2FeedViewController)
		let window = hostInWindow(controller)
		defer { window.isHidden = true }
		let tableView = controller.tableViewForTesting
		await waitForRows(in: tableView, count: 1)
		XCTAssertFalse(controller.isSkeletonShowingForTesting, "loaded list shows no placeholder bars")

		controller.scopeFilterForTesting.buttons[.all]?.sendActions(for: .touchUpInside)
		// 无界面的测试环境里系统有时拍不到截图，此时按设计不做过渡；拍到了就检查过渡中的状态
		if controller.isScopeCrossfadingForTesting {
			XCTAssertFalse(controller.isSkeletonShowingForTesting, "no placeholder over the old list")
			XCTAssertEqual(tableView.alpha, 0)
		} else {
			XCTAssertEqual(tableView.alpha, 1, "without a snapshot the list must never be hidden")
		}
		await waitForRows(in: tableView, count: 1)
		for _ in 0..<100 where controller.isScopeCrossfadingForTesting { try await Task.sleep(for: .milliseconds(10)) }
		XCTAssertFalse(controller.isScopeCrossfadingForTesting)
		XCTAssertEqual(tableView.alpha, 1)
		XCTAssertEqual(tableView.transform, .identity)
	}

	/// 首页文件夹：收起删掉子行、展开插回子行，箭头转到朝下（π/2）/ 朝右（0）。
	func testHomeFolderToggleAnimatesRowsAndRotatesChevron() async throws {
		let first = makeFeed(id: FeedSnapshot.ID(accountID: "account", feedID: "one"), title: "One", count: 2)
		let second = makeFeed(id: FeedSnapshot.ID(accountID: "account", feedID: "two"), title: "Two", count: 3)
		let folder = FolderSnapshot(id: "folder", title: "Folder", feedIDs: [first.id, second.id], articleCount: 5)
		let provider = FakeDataProvider(librarySnapshots: [.unread: LibrarySnapshot(feeds: [first, second], folders: [folder])])
		let navigationController = Babel2SceneComposition.makeRoot(environment: makeEnvironment(provider: provider))
		let root = try XCTUnwrap(navigationController.viewControllers.first as? Babel2RootViewController)
		let window = hostInWindow(navigationController)
		defer { window.isHidden = true }
		root.viewDidAppear(false)
		let tableView = try XCTUnwrap(rootTable(for: root, scope: .unread))
		await waitForRootState(root, scope: .unread, state: "loaded", rows: 3)
		XCTAssertEqual(try XCTUnwrap(root.folderChevronRotationForTesting(scope: .unread, row: 0)), .pi / 2, accuracy: 0.01)

		root.tableView(tableView, didSelectRowAt: IndexPath(row: 0, section: 0))
		XCTAssertEqual(tableView.numberOfRows(inSection: 0), 1, "collapsed: child rows removed")
		XCTAssertEqual(try XCTUnwrap(root.folderChevronRotationForTesting(scope: .unread, row: 0)), 0, accuracy: 0.01)

		root.tableView(tableView, didSelectRowAt: IndexPath(row: 0, section: 0))
		XCTAssertEqual(tableView.numberOfRows(inSection: 0), 3, "expanded: child rows inserted")
		XCTAssertEqual(try XCTUnwrap(root.folderChevronRotationForTesting(scope: .unread, row: 0)), .pi / 2, accuracy: 0.01)
	}

	/// 毛玻璃菜单从触发按钮那一侧展开：缩放中心在卡片靠按钮的边上，缩放时这个点不动。
	func testGlassMenuGrowsFromAnchorSide() throws {
		defer { Babel2Motion.reduceMotionOverride = nil }
		Babel2Motion.reduceMotionOverride = false
		let host = UIViewController()
		let window = hostInWindow(host)
		defer { window.isHidden = true }
		let anchor = UIView(frame: CGRect(x: 340, y: 60, width: 44, height: 44))
		host.view.addSubview(anchor)
		let menu = Babel2GlassMenu.present(sections: [[Babel2MenuItem(title: "One", image: nil, identifier: "one", isOn: nil, handler: {})]], from: anchor, in: host.view)
		let card = menu.cardFrameForTesting
		let origin = menu.growOriginForTesting
		XCTAssertEqual(origin.y, card.minY, accuracy: 0.5, "menu below the button grows from its top edge")
		XCTAssertEqual(origin.x, min(anchor.frame.midX, card.maxX - 22), accuracy: 0.5)
		let transform = menu.growTransformForTesting(scale: 0.92)
		let center = CGPoint(x: card.midX, y: card.midY)
		let moved = CGPoint(x: origin.x - center.x, y: origin.y - center.y).applying(transform)
		XCTAssertEqual(center.x + moved.x, origin.x, accuracy: 0.5)
		XCTAssertEqual(center.y + moved.y, origin.y, accuracy: 0.5)
		menu.removeFromSuperview()
	}

	/// 按下档位按钮时它缩到 94%，但选中胶囊仍按按钮原大小定位（不会小一圈）。
	func testScopePillKeepsFullSizeWhilePressed() {
		defer { Babel2Motion.reduceMotionOverride = nil }
		Babel2Motion.reduceMotionOverride = false
		let host = UIViewController()
		let window = hostInWindow(host)
		defer { window.isHidden = true }
		let filter = Babel2ScopeFilterControl(selectedScope: .unread)
		filter.frame = CGRect(x: 0, y: 0, width: 402, height: 72)
		host.view.addSubview(filter)
		filter.layoutIfNeeded()
		let all = filter.buttons[.all]!
		all.sendActions(for: .touchDown)
		XCTAssertNotEqual(all.transform, .identity, "pressed button shrinks")
		all.sendActions(for: .touchUpInside)
		XCTAssertEqual(filter.selectionPillFrameForTesting.width, all.bounds.width, accuracy: 0.5)
		XCTAssertEqual(filter.selectionPillFrameForTesting.midX, all.center.x, accuracy: 0.5)
		XCTAssertEqual(all.transform, .identity, "released button returns to full size")
	}

	// MARK: - 上拉翻篇（ADR-035）

	func testNextPullShapeFlattensAndDarkensUntilThreshold() {
		XCTAssertEqual(Babel2ReaderNextPull.progress(overscroll: -10), 0)
		XCTAssertEqual(Babel2ReaderNextPull.progress(overscroll: 40), 0.5, accuracy: 0.001)
		XCTAssertEqual(Babel2ReaderNextPull.progress(overscroll: 200), 1, "clamped at threshold")
		XCTAssertEqual(Babel2ReaderNextPull.depth(progress: 0), Babel2ReaderNextPull.restingDepth)
		XCTAssertLessThan(Babel2ReaderNextPull.depth(progress: 0.5), Babel2ReaderNextPull.restingDepth, "flatter as you pull")
		XCTAssertEqual(Babel2ReaderNextPull.depth(progress: 1), 0, "a straight line at the threshold")
		XCTAssertEqual(Babel2ReaderNextPull.opacity(overscroll: 0), 0)
		XCTAssertEqual(Babel2ReaderNextPull.opacity(overscroll: 100), 1)
		XCTAssertFalse(Babel2ReaderNextPull.isArmed(overscroll: 79))
		XCTAssertTrue(Babel2ReaderNextPull.isArmed(overscroll: 80))
		XCTAssertTrue(Babel2ReaderNextPull.shouldCommit(overscrollAtRelease: 90, hasNext: true))
		XCTAssertFalse(Babel2ReaderNextPull.shouldCommit(overscrollAtRelease: 60, hasNext: true), "pulled back below threshold → no flip")
		XCTAssertFalse(Babel2ReaderNextPull.shouldCommit(overscrollAtRelease: 200, hasNext: false), "last article never flips")
		// 长文章：最底 = 内容高 + 底部留白 − 可见高；短文章（不满一屏）以顶部为底
		XCTAssertEqual(Babel2ReaderNextPull.overscroll(offsetY: 1294, contentHeight: 2000, boundsHeight: 800, insetTop: 100, insetBottom: 72), 22)
		XCTAssertEqual(Babel2ReaderNextPull.overscroll(offsetY: -70, contentHeight: 300, boundsHeight: 800, insetTop: 100, insetBottom: 72), 30)
	}

	/// 阅读页：拉过临界点松手 → 走「下一篇」同一条路径；没过线或没有下一篇 → 不翻，最后一篇不显示 ∨。
	func testReaderNextPullCommitsOnlyPastThresholdWithNextArticle() {
		let reader = makeReader(body: "<p>Body</p>")
		reader.loadViewIfNeeded()
		let next = ArticleSnapshot(id: ArticleSnapshot.ID(accountID: "account", feedID: "feed", articleID: "next"), title: "Next", url: nil, feedID: FeedSnapshot.ID(accountID: "account", feedID: "feed"))
		var shown = [ArticleSnapshot.ID]()
		reader.onShowNext = { shown.append($0.id) }

		reader.nextArticleProvider = { nil }
		XCTAssertFalse(reader.simulateNextPullForTesting(overscroll: 120).visible, "last article: no arrow")
		reader.releaseNextPullForTesting(overscroll: 120)
		XCTAssertTrue(shown.isEmpty)

		reader.nextArticleProvider = { next }
		let halfway = reader.simulateNextPullForTesting(overscroll: 40)
		XCTAssertTrue(halfway.visible)
		XCTAssertEqual(halfway.progress, 0.5, accuracy: 0.001)
		reader.releaseNextPullForTesting(overscroll: 40)
		XCTAssertTrue(shown.isEmpty, "released before the threshold")

		_ = reader.simulateNextPullForTesting(overscroll: 95)
		reader.releaseNextPullForTesting(overscroll: 95)
		XCTAssertEqual(shown, [next.id])
	}

	/// 文章列表顶部的刷新按钮（2026-09-27 用户：圈外套圈）：外面已有毛玻璃圆底，箭头自带的灰色圆底不画；
	/// 首页标题旁的同步箭头没有别的底，照旧画。画出来核对：圆内、箭头外的一点，关掉后是透明的。
	func testFeedRefreshGlyphHasNoSecondCircle() throws {
		let bar = Babel2FeedCompactBar(title: "Feed", icon: nil)
		XCTAssertFalse(bar.refreshGlyphForTesting.showsBackgroundForTesting)
		XCTAssertTrue(Babel2SyncSpinner().showsBackgroundForTesting, "the home glyph keeps its own background")

		func alpha(at point: CGPoint, showsBackground: Bool) -> CGFloat {
			let spinner = Babel2SyncSpinner(frame: CGRect(x: 0, y: 0, width: 24, height: 24), showsBackground: showsBackground)
			spinner.layoutIfNeeded()
			let format = UIGraphicsImageRendererFormat()
			format.scale = 1
			format.opaque = false
			let image = UIGraphicsImageRenderer(size: spinner.bounds.size, format: format).image { context in
				spinner.layer.render(in: context.cgContext)
			}
			guard let data = image.cgImage?.dataProvider?.data, let bytes = CFDataGetBytePtr(data),
				let cgImage = image.cgImage else { return -1 }
			let offset = Int(point.y) * cgImage.bytesPerRow + Int(point.x) * 4
			return CGFloat(bytes[offset + 3]) / 255
		}
		// (12, 12)：同步圆弧的圆心（统一图标集的圆弧半径 7，圆心空着，ADR-065）——有圆底是灰的，没有是透明的
		XCTAssertGreaterThan(alpha(at: CGPoint(x: 12, y: 12), showsBackground: true), 0.1)
		XCTAssertEqual(alpha(at: CGPoint(x: 12, y: 12), showsBackground: false), 0, accuracy: 0.01)
		// 圆弧本身画出来了（左侧 x = 5 落在弧上）
		XCTAssertGreaterThan(alpha(at: CGPoint(x: 5, y: 12), showsBackground: false), 0.5)
	}

	/// 同步箭头：开始时加上转动；停止后不再算作转动，图形最终回到正位（模型值无旋转）。
	func testSyncSpinnerStartsAndSettles() {
		let host = UIViewController()
		let window = hostInWindow(host)
		defer { window.isHidden = true }
		let spinner = Babel2SyncSpinner(frame: CGRect(x: 0, y: 0, width: 24, height: 24))
		host.view.addSubview(spinner)
		spinner.setSpinning(true)
		XCTAssertTrue(spinner.isSpinning)
		XCTAssertNotNil(spinner.layer.animationKeys())
		spinner.setSpinning(false)
		XCTAssertFalse(spinner.isSpinning)
		XCTAssertEqual(spinner.layer.transform.m11, 1, accuracy: 0.001, "model value stays upright")
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
		XCTAssertEqual(toggle.accessibilityValue, "original")
		XCTAssertEqual(toggle.phase, .idle)
		XCTAssertTrue(requested.isEmpty, "nothing is requested while off")

		// 打开：只请求屏幕上、还没有译文、且可能需要翻的（英文那条），图标进入「进行中」（ADR-043）
		toggle.sendActions(for: .touchUpInside)
		XCTAssertTrue(enabled)
		XCTAssertEqual(requested, [["en"]])
		XCTAssertEqual(toggle.accessibilityValue, "working")
		XCTAssertEqual(toggle.phase, .working)
		// 有译文入库：变成「已译」（墨色方块底）
		NotificationCenter.default.post(name: .babel2TitleTranslationDidChange, object: nil)
		XCTAssertEqual(toggle.accessibilityValue, "translated")
		XCTAssertEqual(toggle.phase, .on)
		// 关掉：回到平时
		toggle.sendActions(for: .touchUpInside)
		XCTAssertFalse(enabled)
		XCTAssertEqual(toggle.accessibilityValue, "original")
		XCTAssertEqual(toggle.phase, .idle)
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
		XCTAssertEqual(feedViewController.titleTranslationToggleForTesting.accessibilityValue, "translated")
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
		// 确认用全 app 统一的毛玻璃菜单，顶部写「将 2 篇文章标为已读？」
		let menu = try XCTUnwrap(feedViewController.view.subviews.compactMap { $0 as? Babel2GlassMenu }.last)
		let title = try XCTUnwrap(descendant(of: menu, matching: UILabel.self) { $0.accessibilityIdentifier == "babel2.menu.title" })
		XCTAssertEqual(title.text, String(format: Babel2Localization.text(.markAllReadConfirm), 2))
		menu.removeFromSuperview()
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

	// MARK: - 大图上的刷新与更多（ADR-031）

	/// 刷新居中、放大镜 x=330、更多 x=370；没有注入操作时不显示刷新与更多。
	/// 更多菜单 6 项、开关勾选反映当前状态、无主页时不显示「打开网站主页」；重命名后标题与行来源名同步。
	func testFeedHeroRefreshAndMoreMenu() async throws {
		let feedID = FeedSnapshot.ID(accountID: "account", feedID: "feed")
		let list = [ArticleSnapshot(id: ArticleSnapshot.ID(accountID: "account", feedID: "feed", articleID: "a"), title: "A", url: nil, feedID: feedID)]
		var readingMode = true
		var notifications = false
		var home: URL? = URL(string: "https://example.com")
		let actions = Babel2FeedActions(
			refresh: {}, isSyncing: { false }, homePageURL: { home }, feedURL: { "https://example.com/feed" },
			isAlwaysReadingMode: { readingMode }, setAlwaysReadingMode: { readingMode = $0 },
			notificationsEnabled: { notifications }, setNotificationsEnabled: { notifications = $0 },
			rename: { _ in nil }, unsubscribe: { nil }, openURL: { _ in })
		let controller = Babel2FeedViewController(feed: makeFeed(id: feedID, title: "Feed"), scope: .all,
			environment: makeEnvironment(provider: FakeDataProvider(feeds: [feedID: list])), feedActions: actions)
		let window = hostInWindow(controller)
		defer { window.isHidden = true }
		let tableView = try XCTUnwrap(descendant(of: controller.view, matching: UITableView.self))
		await waitForRows(in: tableView, count: 1)
		controller.view.layoutIfNeeded()
		let compact = try XCTUnwrap(controller.compactBarForTesting)
		let width = controller.view.bounds.width
		XCTAssertFalse(compact.refreshButton.isHidden)
		XCTAssertFalse(compact.moreButton.isHidden)
		XCTAssertEqual(compact.refreshButton.frame.midX, width / 2, accuracy: 0.5)
		XCTAssertEqual(compact.searchButton.frame.midX, width - 72, accuracy: 0.5)
		XCTAssertEqual(compact.moreButton.frame.midX, width - 32, accuracy: 0.5)
		// 大图上的按钮有毛玻璃圆底（展开时可见），收起后淡出
		XCTAssertEqual(compact.glassDiscAlphaForTesting, 1, accuracy: 0.01)
		compact.apply(progress: 1)
		XCTAssertEqual(compact.glassDiscAlphaForTesting, 0, accuracy: 0.01)
		compact.apply(progress: 0)

		var items = controller.moreMenuSectionsForTesting.flatMap { $0 }
		XCTAssertEqual(items.map(\.identifier), ["babel2.feed.more.website", "babel2.feed.more.copy", "babel2.feed.more.reading-mode",
			"babel2.feed.more.notifications", "babel2.feed.more.rename", "babel2.feed.more.unsubscribe"])
		XCTAssertEqual(items.first { $0.identifier == "babel2.feed.more.reading-mode" }?.isOn, true)
		XCTAssertEqual(items.first { $0.identifier == "babel2.feed.more.notifications" }?.isOn, false)
		XCTAssertTrue(items.last?.isDestructive == true)
		// 点「•••」弹出统一的毛玻璃菜单；点开关项写回设置并关闭
		compact.moreButton.sendActions(for: .touchUpInside)
		let menu = try XCTUnwrap(controller.view.subviews.compactMap { $0 as? Babel2GlassMenu }.last, "glass menu shown")
		XCTAssertEqual(menu.itemControlsForTesting.count, 6)
		XCTAssertLessThanOrEqual(menu.cardFrameForTesting.maxX, width - 20 + 0.5, "menu stays on screen")
		menu.selectForTesting("babel2.feed.more.notifications")
		XCTAssertTrue(notifications)
		XCTAssertNil(menu.superview, "menu closes after choosing")
		home = nil
		items = controller.moreMenuSectionsForTesting.flatMap { $0 }
		XCTAssertFalse(items.contains { $0.identifier == "babel2.feed.more.website" }, "no home page → no Open Website")

		controller.applyRenamedTitle("Renamed")
		XCTAssertEqual(controller.heroViewForTesting?.titleLabel.text, "Renamed")
		XCTAssertEqual(compact.titleLabel.text, "Renamed")
		tableView.layoutIfNeeded()
		let cell = try XCTUnwrap(tableView.cellForRow(at: IndexPath(row: 0, section: 0)))
		XCTAssertTrue(cell.contentView.subviews.compactMap { $0 as? UILabel }.contains { $0.text == "RENAMED" }, "row source name follows the rename")

		// 没注入操作：不显示刷新与更多
		let plain = Babel2FeedViewController(feed: makeFeed(id: feedID, title: "Feed"), scope: .all, environment: makeEnvironment(provider: FakeDataProvider(feeds: [feedID: list])))
		plain.loadViewIfNeeded()
		XCTAssertTrue(plain.compactBarForTesting?.refreshButton.isHidden == true)
		XCTAssertTrue(plain.compactBarForTesting?.moreButton.isHidden == true)
	}

	/// 切到后台时上游清空图标内存缓存；Babel 2.0 的备份仍保留，回到前台首页直接用原图标（2026-09-25）。
	func testIconBackupSurvivesBackgroundButNotMemoryWarning() {
		let key = "test-account|\(UUID().uuidString)"
		Babel2LiveIconCache.storeForTesting(Data([1, 2, 3]), key: key)
		NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
		XCTAssertEqual(Babel2LiveIconCache.cachedForTesting(key), Data([1, 2, 3]), "kept across background")
	}

	/// 界面语言「跟随系统」只写这四个字，不带括号里的系统语言名。
	func testFollowSystemLanguageOptionHasNoSuffix() {
		let options = Babel2LiveSettingsService().languageOptions
		XCTAssertEqual(options.first?.code, nil)
		XCTAssertEqual(options.first?.name, Babel2SettingsText.t("Follow System"))
	}

	/// 点刷新：调用刷新、箭头转、副标题「正在同步…」（辅助功能值仍是纯数字）；同步结束后停止并重新加载（新文章出现）。
	func testFeedHeroRefreshShowsSyncingThenReloads() async throws {
		let feedID = FeedSnapshot.ID(accountID: "account", feedID: "feed")
		func article(_ id: String, minutesAgo: Double) -> ArticleSnapshot {
			ArticleSnapshot(id: ArticleSnapshot.ID(accountID: "account", feedID: "feed", articleID: id), title: id, url: nil, feedID: feedID,
				publishedAt: Date().addingTimeInterval(-minutesAgo * 60))
		}
		let provider = FakeDataProvider(feeds: [feedID: [article("old", minutesAgo: 60)]])
		var syncing = false
		var refreshCount = 0
		let actions = Babel2FeedActions(
			refresh: { refreshCount += 1; syncing = true }, isSyncing: { syncing }, homePageURL: { nil }, feedURL: { nil },
			isAlwaysReadingMode: { false }, setAlwaysReadingMode: { _ in }, notificationsEnabled: { false }, setNotificationsEnabled: { _ in },
			rename: { _ in nil }, unsubscribe: { nil }, openURL: { _ in })
		let controller = Babel2FeedViewController(feed: makeFeed(id: feedID, title: "Feed"), scope: .all,
			environment: makeEnvironment(provider: provider), feedActions: actions)
		let window = hostInWindow(controller)
		defer { window.isHidden = true }
		let tableView = try XCTUnwrap(descendant(of: controller.view, matching: UITableView.self))
		await waitForRows(in: tableView, count: 1)
		let compact = try XCTUnwrap(controller.compactBarForTesting)
		let count = try XCTUnwrap(descendant(of: controller.view, matching: UILabel.self) { $0.accessibilityIdentifier == "babel2.feed.count" })

		controller.refreshForTesting()
		XCTAssertEqual(refreshCount, 1)
		XCTAssertTrue(compact.isShowingSyncingForTesting)
		XCTAssertEqual(count.text, Babel2Localization.text(.syncing))
		XCTAssertEqual(count.accessibilityValue, "1", "UI driver still reads the plain number")

		// 同步拉回了新文章，然后同步结束
		await provider.setFeedArticles([article("new", minutesAgo: 1), article("old", minutesAgo: 60)], for: feedID)
		syncing = false
		await waitForRows(in: tableView, count: 2)
		XCTAssertEqual(controller.articlesForTesting.first?.id.articleID, "new", "new article appears on top after refresh")
		for _ in 0..<50 where compact.isShowingSyncingForTesting { try await Task.sleep(for: .milliseconds(20)) }
		XCTAssertFalse(compact.isShowingSyncingForTesting)
		XCTAssertEqual(count.text, String(format: Babel2Localization.text(.articleCount), 2))
	}

	// MARK: - 首页跨源入口（ADR-044）

	/// 首页顶部入口跟着档位变：未读档 今日未读 / 全部未读 / 外文源；全部档 今天 / 全部文章 / 外文源；星标档只有全部星标。
	/// 篇数来自数据层，0 不显示；点一下打开跨源文章列表（按当前档位请求）。
	func testHomeSmartEntriesFollowScopeShowCountsAndOpenList() async throws {
		let feed = makeFeed(id: FeedSnapshot.ID(accountID: "account", feedID: "feed"), title: "Feed", count: 3)
		let provider = FakeDataProvider(librarySnapshots: [
			.unread: LibrarySnapshot(feeds: [feed], smartFeedCounts: [.today: 2, .all: 12, .foreign: 0]),
			.all: LibrarySnapshot(feeds: [feed], smartFeedCounts: [.today: 4, .all: 40, .foreign: 9]),
			.starred: LibrarySnapshot(feeds: [feed], smartFeedCounts: [.starred: 3])
		])
		let editing = FakeLibraryEditing()
		let navigation = Babel2SceneComposition.makeRoot(environment: makeEnvironment(provider: provider),
			settingsService: FakeSettingsService(), subscriptionService: FakeSubscriptionService(), libraryEditing: editing.editing)
		let window = hostInWindow(navigation)
		defer { window.isHidden = true }
		let root = try XCTUnwrap(navigation.viewControllers.first as? Babel2RootViewController)
		await waitForRootState(root, scope: .unread, state: "loaded", rows: 1)

		func titles(_ scope: Babel2FeedScope) -> [String] { root.smartRowsForTesting(scope: scope).map { $0.titleLabel.text ?? "" } }
		XCTAssertEqual(titles(.unread), [Babel2LocalizationKey.smartTodayUnread, .smartAllUnread, .smartForeign].map { localized($0) })
		XCTAssertEqual(titles(.all), [Babel2LocalizationKey.smartToday, .smartAllArticles, .smartForeign].map { localized($0) })
		XCTAssertEqual(titles(.starred), [localized(.smartStarred)])
		let unreadRows = root.smartRowsForTesting(scope: .unread)
		XCTAssertEqual(unreadRows.map(\.accessibilityValue), ["2", "12", nil], "zero is not shown")

		unreadRows[1].sendActions(for: .touchUpInside)
		let list = try XCTUnwrap(navigation.topViewController as? Babel2FeedViewController)
		XCTAssertEqual(list.smartFeed, .all)
		list.loadViewIfNeeded()
		for _ in 0..<100 {
			if await !provider.smartRequests.isEmpty { break }
			try await Task.sleep(for: .milliseconds(10))
		}
		let requests = await provider.smartRequests
		XCTAssertEqual(requests, ["all/unread"])
	}

	/// 菜单按下时的高亮（2026-09-27 用户：直角矩形套在圆角卡片里很丑）：通用菜单、设置页弹出选单的每一行，
	/// 高亮底都是圆角 16（= 卡片 22 − 内边距 6，与卡片同心）、连续曲线；按下时真的有底色。
	func testMenuRowHighlightsAreRoundedLikeTheCard() {
		let host = UIViewController()
		let window = hostInWindow(host)
		defer { window.isHidden = true }
		XCTAssertEqual(Babel2GlassCard.rowCornerRadius, 16)
		let menu = Babel2GlassMenu.present(sections: [[
			Babel2MenuItem(title: "A", image: nil, identifier: "a") {},
			Babel2MenuItem(title: "B", image: nil, identifier: "b") {}
		]], from: host.view, in: host.view)
		for row in menu.itemControlsForTesting {
			XCTAssertEqual(row.layer.cornerRadius, 16)
			XCTAssertEqual(row.layer.cornerCurve, .continuous)
		}
		let first = menu.itemControlsForTesting[0]
		first.isHighlighted = true
		first.layer.removeAllAnimations()
		XCTAssertNotEqual(first.backgroundColor, .clear)
		XCTAssertNotNil(first.backgroundColor)
		menu.removeFromSuperview()

		let popover = Babel2SettingsPopover.present(options: [.init(title: "One", isSelected: true), .init(title: "Two", isSelected: false)],
			from: host.view, in: host.view) { _ in }
		for row in popover.optionControlsForTesting {
			XCTAssertEqual(row.layer.cornerRadius, 16)
			XCTAssertEqual(row.layer.cornerCurve, .continuous)
		}
		popover.removeFromSuperview()
	}

	/// 跨源列表长按文章（ADR-063）：菜单顶部是来源名，项目为「打开这个源 / 加星标」「编辑订阅源」「取消订阅该源」，弹性展开；
	/// 加星标只改这一篇并原地刷新；编辑改名后每行来源名跟着换；取消订阅先确认（写明星标文章也删），
	/// 成功后这个源的文章原地拿掉、篇数跟着变，失败说明原因；单个订阅源的列表不装长按。
	func testSmartListLongPressOffersSourceActions() async throws {
		let alpha = FeedSnapshot.ID(accountID: "account", feedID: "alpha")
		let beta = FeedSnapshot.ID(accountID: "account", feedID: "beta")
		func article(_ id: String, _ feed: FeedSnapshot.ID, minutes: Double, starred: Bool = false) -> ArticleSnapshot {
			ArticleSnapshot(id: ArticleSnapshot.ID(accountID: "account", feedID: feed.feedID, articleID: id), title: "Story \(id)",
				url: nil, feedID: feed, publishedAt: Date().addingTimeInterval(-minutes * 60), isStarred: starred)
		}
		let first = article("1", alpha, minutes: 1)
		let second = article("2", beta, minutes: 2, starred: true)
		let third = article("3", alpha, minutes: 3)
		let provider = FakeDataProvider()
		await provider.setSmartArticles(SmartFeedArticlesSnapshot(articles: [first, second, third],
			feeds: [makeFeed(id: alpha, title: "Alpha"), makeFeed(id: beta, title: "Beta")]), for: .all)
		let handler = RecordingActionHandler()
		let list = Babel2FeedViewController(smartFeed: .all, scope: .all,
			environment: makeEnvironment(provider: provider, actionHandler: handler), confirmMarkAllRead: { false })
		final class Record {
			var opened = [FeedSnapshot.ID]()
			var unsubscribed = [FeedSnapshot.ID]()
			var failure: String?
		}
		let record = Record()
		list.sourceActions = Babel2ArticleSourceActions(
			openFeed: { record.opened.append($0.id) },
			edit: { _, onSaved in onSaved("Alpha Two") },
			unsubscribe: { id in
				record.unsubscribed.append(id)
				return record.failure
			}
		)
		let window = hostInWindow(list)
		defer { window.isHidden = true }
		await waitForRows(in: list.tableViewForTesting, count: 3)
		XCTAssertNotNil(list.articleLongPressForTesting, "cross-source lists get the long press")

		let menu = try XCTUnwrap(list.presentSourceMenuForTesting(row: 0))
		XCTAssertEqual(menuTitle(menu), "Alpha")
		XCTAssertTrue(menu.didPopForTesting, "same long-press pop as the home screen")
		XCTAssertEqual(menu.itemControlsForTesting.map(\.accessibilityIdentifier), [
			"babel2.feed.article-menu.open-feed", "babel2.feed.article-menu.star",
			"babel2.feed.article-menu.edit-feed", "babel2.feed.article-menu.unsubscribe"
		])
		XCTAssertEqual(menu.itemControlsForTesting[1].accessibilityLabel, localized(.star))
		menu.selectForTesting("babel2.feed.article-menu.star")
		for _ in 0..<150 {
			if await !handler.actions.isEmpty { break }
			try await Task.sleep(for: .milliseconds(10))
		}
		let recorded = await handler.actions
		XCTAssertEqual(recorded, [.toggleStar(first.id)])
		// 已加星标的那篇：菜单里是「取消星标」
		let starredMenu = try XCTUnwrap(list.presentSourceMenuForTesting(row: 1))
		XCTAssertEqual(starredMenu.itemControlsForTesting[1].accessibilityLabel, localized(.unstar))
		XCTAssertEqual(menuTitle(starredMenu), "Beta")
		starredMenu.removeFromSuperview()

		try XCTUnwrap(list.presentSourceMenuForTesting(row: 0)).selectForTesting("babel2.feed.article-menu.open-feed")
		XCTAssertEqual(record.opened, [alpha])
		try XCTUnwrap(list.presentSourceMenuForTesting(row: 0)).selectForTesting("babel2.feed.article-menu.edit-feed")
		XCTAssertEqual(list.sourceFeed(for: first)?.title, "Alpha Two")
		XCTAssertEqual(list.sourceFeed(for: third)?.title, "Alpha Two", "every row of that source follows the new name")

		// 取消订阅：先确认，确认文字写明星标文章也删
		try XCTUnwrap(list.presentSourceMenuForTesting(row: 0)).selectForTesting("babel2.feed.article-menu.unsubscribe")
		await waitUntil { list.presentedViewController is UIAlertController }
		let confirm = try XCTUnwrap(list.presentedViewController as? UIAlertController)
		XCTAssertEqual(confirm.message, String(format: localized(.unsubscribeConfirm), "Alpha Two"))
		await dismissPresented(list)
		let alphaFeed = try XCTUnwrap(list.sourceFeed(for: first))
		// 失败：说明原因，列表不动
		record.failure = "Server said no"
		await list.performUnsubscribeSource(alphaFeed)
		XCTAssertEqual(list.articlesForTesting.count, 3)
		await waitUntil { (list.presentedViewController as? UIAlertController)?.message == "Server said no" }
		await dismissPresented(list)
		// 成功：Alpha 的两篇原地拿掉，只剩 Beta 那篇
		record.failure = nil
		await list.performUnsubscribeSource(alphaFeed)
		XCTAssertEqual(record.unsubscribed, [alpha, alpha])
		XCTAssertEqual(list.articlesForTesting.map(\.id), [second.id])
		XCTAssertEqual(list.tableViewForTesting.numberOfRows(inSection: 0), 1)
		XCTAssertNil(list.sourceFeed(for: first))

		// 单个订阅源的列表：不装长按（「更多」里本来就有编辑 / 取消订阅）
		let single = Babel2FeedViewController(feed: makeFeed(id: alpha, title: "Alpha"), scope: .all,
			environment: makeEnvironment(provider: FakeDataProvider()))
		single.loadViewIfNeeded()
		XCTAssertNil(single.articleLongPressForTesting)
	}

	/// 装配（ADR-063）：跨源列表的来源菜单接到真的页面——编辑推出编辑页、取消订阅走首页同一个整理接口、打开这个源推出它的列表。
	func testSmartListSourceActionsAreWired() async throws {
		let home = try await makeOrganizableHome()
		let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
		home.window.rootViewController = nil
		home.window.isHidden = true
		let window = UIWindow(windowScene: scene)
		window.rootViewController = home.navigation
		window.makeKeyAndVisible()
		defer { window.isHidden = true }
		let alphaID = FeedSnapshot.ID(accountID: "account", feedID: "a")
		let alpha = makeFeed(id: alphaID, title: "Alpha", count: 3)
		let story = ArticleSnapshot(id: ArticleSnapshot.ID(accountID: "account", feedID: "a", articleID: "s"), title: "Story",
			url: nil, feedID: alphaID, publishedAt: Date())
		await home.provider.setSmartArticles(SmartFeedArticlesSnapshot(articles: [story], feeds: [alpha]), for: .today)

		home.root.onSmartFeedRequested?(.today, .unread)
		let list = try XCTUnwrap(home.navigation.viewControllers.last as? Babel2FeedViewController)
		await waitUntil { home.navigation.transitionCoordinator == nil }
		let actions = try XCTUnwrap(list.sourceActions)

		let message = await actions.unsubscribe(alphaID)
		XCTAssertNil(message)
		XCTAssertEqual(home.editing.calls.last, "unsubscribe:a", "same unsubscribe as the home long press (all folders)")

		actions.edit(alpha) { _ in }
		let page = try XCTUnwrap(home.navigation.viewControllers.last as? Babel2FeedEditViewController)
		await waitUntil { home.navigation.transitionCoordinator == nil }
		page.loadViewIfNeeded()
		XCTAssertEqual(page.nameFieldForTesting.text, "Alpha")
		XCTAssertEqual(page.selectionForTesting, ["account:1", "account:3"])
		_ = home.navigation.popBabel2(animated: false)
		await waitUntil { home.navigation.topViewController === list && home.navigation.transitionCoordinator == nil }

		actions.openFeed(alpha)
		await waitUntil { home.navigation.viewControllers.count == 3 }
		let opened = try XCTUnwrap(home.navigation.viewControllers.last as? Babel2FeedViewController)
		XCTAssertEqual(opened.placeFeedID, alphaID)
		XCTAssertNil(opened.smartFeed)
		XCTAssertEqual(opened.scope, .unread, "opens in the same scope as the list")
	}

	/// 跨源列表：标题按档位（未读档「全部未读」）；每篇显示自己的来源名；不显示标题翻译开关与「更多」；
	/// 「全部标为已读」只标列出来的未读文章（一次批量）；后台状态变化时按列出的编号取回最新状态。
	func testSmartListShowsEachSourceAndMarksListedUnreadArticlesRead() async throws {
		let alpha = FeedSnapshot.ID(accountID: "account", feedID: "alpha")
		let beta = FeedSnapshot.ID(accountID: "account", feedID: "beta")
		let first = ArticleSnapshot(id: ArticleSnapshot.ID(accountID: "account", feedID: "alpha", articleID: "1"),
			title: "First", url: nil, feedID: alpha, publishedAt: Date())
		let second = ArticleSnapshot(id: ArticleSnapshot.ID(accountID: "account", feedID: "beta", articleID: "2"),
			title: "Second", url: nil, feedID: beta, publishedAt: Date().addingTimeInterval(-60), isRead: true)
		let provider = FakeDataProvider()
		await provider.setSmartArticles(SmartFeedArticlesSnapshot(articles: [first, second],
			feeds: [makeFeed(id: alpha, title: "Alpha"), makeFeed(id: beta, title: "Beta")]), for: .all)
		let handler = RecordingActionHandler()
		let list = Babel2FeedViewController(smartFeed: .all, scope: .unread,
			environment: makeEnvironment(provider: provider, actionHandler: handler), confirmMarkAllRead: { false })
		let window = hostInWindow(list)
		defer { window.isHidden = true }
		await waitForRows(in: list.tableViewForTesting, count: 2)
		XCTAssertEqual(list.heroViewForTesting?.titleLabel.text, localized(.smartAllUnread))
		XCTAssertEqual(list.sourceFeed(for: first)?.title, "Alpha")
		XCTAssertEqual(list.sourceFeed(for: second)?.title, "Beta")
		list.tableViewForTesting.layoutIfNeeded()
		// 来源名在行里按设计大写显示
		let labels = list.tableViewForTesting.visibleCells.flatMap { $0.contentView.allSubviews.compactMap { ($0 as? UILabel)?.text?.lowercased() } }
		XCTAssertTrue(labels.contains("alpha") && labels.contains("beta"), "each row shows its own source: \(labels)")
		XCTAssertTrue(list.titleTranslationToggleForTesting.isHidden)
		XCTAssertEqual(list.compactBarForTesting?.moreButton.isHidden, true)

		NotificationCenter.default.post(name: .babel2LibraryDidChange, object: nil)
		for _ in 0..<150 {
			if await !provider.articleSnapshotRequests.isEmpty { break }
			try await Task.sleep(for: .milliseconds(10))
		}
		let statusRequests = await provider.articleSnapshotRequests
		XCTAssertEqual(statusRequests.first.map(Set.init), Set([first.id, second.id]), "fresh statuses by the listed IDs")

		let readAll = try XCTUnwrap(descendant(of: list.view, matching: UIButton.self) { $0.accessibilityIdentifier == "babel2.feed.read-all" })
		readAll.sendActions(for: .touchUpInside)
		for _ in 0..<100 {
			if await !handler.actions.isEmpty { break }
			try await Task.sleep(for: .milliseconds(20))
		}
		let actions = await handler.actions
		XCTAssertEqual(actions, [.markArticlesRead([first.id])], "only the listed unread articles, in one batch")
	}

	// MARK: - 首页整理（ADR-045）

	/// 长按文件夹：顶部写「文件夹名 · N 个订阅源」；重命名弹输入框（原名预填）；删除先问里面的源怎么办
	/// （只删文件夹、源移到顶层 / 连同源一起删）；空文件夹也列在首页，删除时只问删不删。
	func testHomeLongPressFolderRenamesAndDeletesWithChoice() async throws {
		let home = try await makeOrganizableHome()
		defer { home.window.isHidden = true }
		let root = home.root
		let editor = try XCTUnwrap(root.libraryEditor)
		XCTAssertEqual(root.rowDescriptionsForTesting(scope: .unread), [
			"folder:account:2", "folder:account:3", "feed:a@account:3",
			"folder:account:1", "feed:a@account:1", "feed:b@account:1", "feed:c@top"
		], "the empty folder is listed; Alpha is listed under both folders it is in")

		XCTAssertTrue(root.longPressRowForTesting(scope: .unread, row: 3))
		let menu = try XCTUnwrap(editor.lastMenuForTesting)
		XCTAssertEqual(menuTitle(menu), String(format: localized(.quotedName), "Tech") + " · " + String(format: localized(.folderFeedCount), 2))
		XCTAssertEqual(menu.itemControlsForTesting.map(\.accessibilityIdentifier), ["babel2.library.folder.rename", "babel2.library.folder.delete"])
		menu.selectForTesting("babel2.library.folder.delete")
		let delete = try XCTUnwrap(editor.lastAlertForTesting)
		XCTAssertEqual(delete.title, String(format: localized(.deleteFolderConfirm), "Tech"))
		XCTAssertEqual(delete.message, String(format: localized(.deleteFolderContents), 2))
		XCTAssertEqual(delete.actions.map(\.title), [localized(.deleteFolderKeepFeeds), localized(.deleteFolderAndFeeds), localized(.cancel)])
		XCTAssertEqual(delete.actions.map(\.style), [.default, .destructive, .cancel])
		await dismissPresented(home.navigation)
		let starts = await home.provider.libraryStarts.filter { $0 == .unread }.count
		await editor.performDeleteFolder("account:1", keepFeeds: true)
		XCTAssertEqual(home.editing.calls, ["deleteFolder:account:1:keep"])
		await waitForLibraryStart(home.provider, .unread, after: starts + 1)

		XCTAssertTrue(root.longPressRowForTesting(scope: .unread, row: 3))
		try XCTUnwrap(editor.lastMenuForTesting).selectForTesting("babel2.library.folder.rename")
		let rename = try XCTUnwrap(editor.lastAlertForTesting)
		XCTAssertEqual(rename.title, localized(.renameFolder))
		XCTAssertEqual(rename.textFields?.first?.text, "Tech", "the current name is prefilled")
		await dismissPresented(home.navigation)
		await editor.performRenameFolder("account:1", to: "Technology")
		XCTAssertEqual(home.editing.calls.last, "renameFolder:account:1->Technology")

		XCTAssertTrue(root.longPressRowForTesting(scope: .unread, row: 0))
		try XCTUnwrap(editor.lastMenuForTesting).selectForTesting("babel2.library.folder.delete")
		let deleteEmpty = try XCTUnwrap(editor.lastAlertForTesting)
		XCTAssertNil(deleteEmpty.message)
		XCTAssertEqual(deleteEmpty.actions.map(\.title), [localized(.delete), localized(.cancel)])
		await dismissPresented(home.navigation)
	}

	/// 长按订阅源：顶部写它在哪（多账户时加账户名），同时也在别的文件夹里的写出来（首页「重复」的来由）；
	/// 菜单是「编辑 / 换图标（/ 恢复默认）/ 取消订阅」——原来的「移到文件夹」「移出」「重命名」并入编辑页（ADR-061）；失败时弹出原因。
	func testHomeLongPressFeedExplainsDuplicatesAndOffersEdit() async throws {
		let home = try await makeOrganizableHome()
		defer { home.window.isHidden = true }
		let root = home.root
		let editing = home.editing
		let editor = try XCTUnwrap(root.libraryEditor)

		XCTAssertTrue(root.longPressRowForTesting(scope: .unread, row: 4))
		let menu = try XCTUnwrap(editor.lastMenuForTesting)
		XCTAssertEqual(menuTitle(menu), String(format: localized(.feedInFolder), "Tech") + "\n"
			+ String(format: localized(.feedAlsoIn), String(format: localized(.quotedName), "News")))
		XCTAssertEqual(menu.itemControlsForTesting.map(\.accessibilityIdentifier), [
			"babel2.library.feed.edit", "babel2.library.feed.icon", "babel2.library.feed.unsubscribe"
		])
		XCTAssertEqual(menu.itemControlsForTesting[0].accessibilityLabel, localized(.editFeedMenu))
		menu.removeFromSuperview()

		// 另一个账户里的源：顶部带账户名
		XCTAssertTrue(root.longPressRowForTesting(scope: .unread, row: 5))
		let beta = try XCTUnwrap(editor.lastMenuForTesting)
		XCTAssertEqual(menuTitle(beta), "iCloud · " + String(format: localized(.feedInFolder), "Tech"))
		beta.removeFromSuperview()

		// 顶层的源：「不在文件夹里」；换过图标的有「恢复默认图标」；取消订阅先确认
		XCTAssertTrue(root.longPressRowForTesting(scope: .unread, row: 6))
		let top = try XCTUnwrap(editor.lastMenuForTesting)
		XCTAssertEqual(menuTitle(top), localized(.notInFolder))
		XCTAssertTrue(top.itemControlsForTesting.contains { $0.accessibilityIdentifier == "babel2.library.feed.icon-reset" })
		top.selectForTesting("babel2.library.feed.icon-reset")
		XCTAssertEqual(editing.calls.last, "icon:c:reset")
		XCTAssertTrue(root.longPressRowForTesting(scope: .unread, row: 6))
		try XCTUnwrap(editor.lastMenuForTesting).selectForTesting("babel2.library.feed.unsubscribe")
		let confirm = try XCTUnwrap(editor.lastAlertForTesting)
		XCTAssertEqual(confirm.message, String(format: localized(.unsubscribeConfirm), "Gamma"))
		await dismissPresented(home.navigation)
		await editor.performUnsubscribe(FeedSnapshot.ID(accountID: "account", feedID: "c"))
		XCTAssertEqual(editing.calls.last, "unsubscribe:c")
	}

	/// 长按手感（ADR-060）：按住那一行慢慢缩小；没按满就松手 / 手指挪开 → 恢复原大、不弹菜单、不震；
	/// 按满 → 弹回原大、震一下、菜单弹性展开；「减弱动态效果」时不缩放、菜单照常淡入、照样震。
	func testLongPressChargesThenReleasesWithHapticAndPoppingMenu() async throws {
		let home = try await makeOrganizableHome()
		defer {
			home.window.isHidden = true
			Babel2Motion.reduceMotionOverride = nil
		}
		Babel2Motion.reduceMotionOverride = false
		let root = home.root
		let editor = try XCTUnwrap(root.libraryEditor)
		let feedback = try XCTUnwrap(root.longPressFeedbackForTesting(scope: .unread))
		let tableView = try XCTUnwrap(feedback.longPressGesture.view as? UITableView)
		XCTAssertEqual(feedback.longPressGesture.minimumPressDuration, Babel2LongPressMotion.commitDuration)
		let cell = try XCTUnwrap(tableView.cellForRow(at: IndexPath(row: 4, section: 0)))
		let point = CGPoint(x: cell.frame.midX, y: cell.frame.midY)

		// 蓄力：缩到 96%
		feedback.simulateTouchBeganForTesting(at: point)
		feedback.simulateChargeForTesting()
		XCTAssertEqual(cell.transform.a, Babel2LongPressMotion.chargeScale, accuracy: 0.001, "the row is pressed in")
		// 没按满就松手：回原大，不弹、不震
		feedback.simulateTouchEndedForTesting()
		XCTAssertEqual(cell.transform, .identity)
		XCTAssertNil(editor.lastMenuForTesting)
		XCTAssertEqual(feedback.hapticCountForTesting, 0)
		// 手指挪开（开始滚动）：同样回原大
		feedback.simulateTouchBeganForTesting(at: point)
		feedback.simulateChargeForTesting()
		feedback.simulateTouchMovedForTesting(to: CGPoint(x: point.x, y: point.y + 30))
		XCTAssertEqual(cell.transform, .identity)

		// 按满：弹回、震一下、菜单弹性展开
		feedback.simulateTouchBeganForTesting(at: point)
		feedback.simulateChargeForTesting()
		feedback.simulateCommitForTesting(at: point)
		XCTAssertEqual(cell.transform, .identity, "the row springs back")
		XCTAssertEqual(feedback.hapticCountForTesting, 1)
		let menu = try XCTUnwrap(editor.lastMenuForTesting)
		XCTAssertTrue(menu.didPopForTesting, "long-press menus pop with a spring")
		XCTAssertEqual(menu.itemControlsForTesting.first?.accessibilityIdentifier, "babel2.library.feed.edit")
		// 松手（菜单已经弹出）：什么也不变
		feedback.simulateTouchEndedForTesting()
		XCTAssertNotNil(menu.superview)
		menu.removeFromSuperview()

		// 「+」点按弹出的菜单照旧不回弹
		let plus = Babel2GlassMenu.present(sections: [[Babel2MenuItem(title: "X", image: nil, identifier: "x") {}]], from: tableView, in: root.view)
		XCTAssertFalse(plus.didPopForTesting)
		plus.removeFromSuperview()

		// 减弱动态效果：不缩放；按满照样震、菜单不弹性
		Babel2Motion.reduceMotionOverride = true
		feedback.simulateTouchBeganForTesting(at: point)
		feedback.simulateChargeForTesting()
		XCTAssertEqual(cell.transform, .identity)
		feedback.simulateCommitForTesting(at: point)
		XCTAssertEqual(feedback.hapticCountForTesting, 2)
		XCTAssertFalse(try XCTUnwrap(editor.lastMenuForTesting).didPopForTesting)
		editor.lastMenuForTesting?.removeFromSuperview()
	}

	/// 图片查看器长按分享：同一套手感——按住图片缩小，按满弹回、震一下、出分享面板。
	func testImageViewerLongPressUsesTheSameFeel() async throws {
		defer { Babel2Motion.reduceMotionOverride = nil }
		Babel2Motion.reduceMotionOverride = false
		let format = UIGraphicsImageRendererFormat()
		format.scale = 1
		let image = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 300), format: format).image { context in
			UIColor.gray.setFill()
			context.fill(CGRect(x: 0, y: 0, width: 400, height: 300))
		}
		let viewer = Babel2ImageViewerViewController(
			source: .init(placeholder: image, imageURL: nil, linkURL: nil, originFrame: nil, altText: ""), loadImage: nil)
		let window = hostInWindow(viewer)
		defer { window.isHidden = true }
		viewer.view.layoutIfNeeded()
		let feedback = try XCTUnwrap(viewer.longPressFeedbackForTesting)
		var shared: UIImage?
		viewer.shareForTesting = { shared = $0 }
		XCTAssertTrue(feedback.longPressGesture.view === viewer.imageView)
		let point = CGPoint(x: viewer.imageView.bounds.midX, y: viewer.imageView.bounds.midY)
		feedback.simulateTouchBeganForTesting(at: point)
		feedback.simulateChargeForTesting()
		let pressed = try XCTUnwrap(viewer.imageView.superview as? UIScrollView)
		XCTAssertEqual(pressed.transform.a, Babel2LongPressMotion.chargeScale, accuracy: 0.001)
		XCTAssertEqual(viewer.imageView.transform, .identity, "the zoomable image itself is left alone")
		feedback.simulateCommitForTesting(at: point)
		XCTAssertEqual(pressed.transform, .identity)
		XCTAssertEqual(feedback.hapticCountForTesting, 1)
		XCTAssertTrue(shared === viewer.imageView.image, "the share sheet is asked for with this image")
	}

	/// 编辑页（ADR-061）：名字 + 订阅地址；「名称」可改；「文件夹」列出这个账户的全部文件夹（不列最外层），
	/// 现在在的打勾、可多选；「新建文件夹…」建好自动选上；✓ 保存：先改名、再设文件夹；✕ / 什么都没改 → 不写；失败说明原因。
	/// （测试窗口里带动画的页面切换不会结束，所以入口只核对「推上去了」，保存流程直接建页面核对「写了什么、要求返回了没有」。）
	func testFeedEditPageRenamesAndAssignsSeveralFolders() async throws {
		let home = try await makeOrganizableHome()
		defer { home.window.isHidden = true }
		let root = home.root
		let editing = home.editing
		let editor = try XCTUnwrap(root.libraryEditor)
		func feed(_ id: String, _ title: String) -> FeedSnapshot {
			makeFeed(id: FeedSnapshot.ID(accountID: "account", feedID: id), title: title)
		}
		func open(_ snapshot: FeedSnapshot) throws -> (Babel2FeedEditViewController, UIWindow) {
			let page = try XCTUnwrap(Babel2FeedEditViewController.make(feed: snapshot, editing: editing.editing))
			let window = hostInWindow(page)
			return (page, window)
		}

		// 入口：长按 Alpha（在 News 和 Tech 里）→ 编辑 → 编辑页推上导航栈
		XCTAssertTrue(root.longPressRowForTesting(scope: .unread, row: 4))
		try XCTUnwrap(editor.lastMenuForTesting).selectForTesting("babel2.library.feed.edit")
		let pushed = try XCTUnwrap(editor.lastEditorForTesting)
		XCTAssertTrue(home.navigation.viewControllers.last === pushed, "the edit page is pushed")

		// 页面内容
		var (page, window) = try open(feed("a", "Alpha"))
		XCTAssertEqual(descendant(of: page.view, matching: UILabel.self) { $0.accessibilityIdentifier == "babel2.feed-edit.title" }?.text, "Alpha")
		XCTAssertEqual(descendant(of: page.view, matching: UILabel.self) { $0.accessibilityIdentifier == "babel2.feed-edit.url" }?.text,
			"example.com/a/feed.xml", "address shown without https://")
		XCTAssertEqual(page.nameFieldForTesting.text, "Alpha")
		XCTAssertEqual(page.folderTitlesForTesting, ["Empty", "News", "Tech"], "all folders of the account, no top-level row")
		XCTAssertEqual(page.selectionForTesting, ["account:1", "account:3"])
		XCTAssertNotNil(descendant(of: page.view, matching: UIView.self) { $0.accessibilityIdentifier == "babel2.feed-edit.new-folder" })
		// 什么都没改就 ✓：不写任何东西、直接返回
		let callsBefore = editing.calls.count
		page.saveForTesting()
		XCTAssertTrue(page.didCloseForTesting)
		XCTAssertEqual(editing.calls.count, callsBefore)
		window.isHidden = true

		// 改名 + 加进 Empty、从 News 拿掉 → 先改名、再设文件夹（按列表顺序）；保存后告诉列表页新名字
		(page, window) = try open(feed("a", "Alpha"))
		var savedName: String??
		page.onSaved = { savedName = $0 }
		page.nameFieldForTesting.text = "  Alpha Weekly  "
		page.tapFolderForTesting("account:2")
		page.tapFolderForTesting("account:3")
		XCTAssertEqual(page.selectionForTesting, ["account:1", "account:2"])
		page.saveForTesting()
		await waitUntil { page.didCloseForTesting }
		XCTAssertEqual(Array(editing.calls.suffix(2)), ["renameFeed:a->Alpha Weekly", "folders:a:account:2,account:1"])
		XCTAssertEqual(savedName, .some("Alpha Weekly"))
		window.isHidden = true

		// ✕：不写
		(page, window) = try open(feed("a", "Alpha"))
		page.tapFolderForTesting("account:2")
		let callsBeforeCancel = editing.calls.count
		page.cancelForTesting()
		XCTAssertTrue(page.didCloseForTesting)
		XCTAssertEqual(editing.calls.count, callsBeforeCancel)
		window.isHidden = true

		// 最外层的 Gamma：新建文件夹建在这个源自己的账户里，插进列表并选上
		(page, window) = try open(feed("c", "Gamma"))
		XCTAssertEqual(page.selectionForTesting, [], "a top-level feed has no folder ticked")
		await page.createFolder(named: "Art")
		XCTAssertEqual(editing.calls.last, "create:Art@account")
		XCTAssertEqual(page.folderTitlesForTesting, ["Art", "Empty", "News", "Tech"])
		XCTAssertEqual(page.selectionForTesting, ["account:99"])
		// 保存失败：说明原因，页面留着
		editing.failNext = "Server said no"
		page.saveForTesting()
		await waitUntil { page.lastAlertForTesting?.message == "Server said no" }
		XCTAssertEqual(editing.calls.last, "folders:c:account:99")
		XCTAssertFalse(page.didCloseForTesting)
		await dismissPresented(page)
		// 又把新文件夹的勾去掉：回到原样（本来就在最外层），✓ 不再写、直接返回
		let callsAfterFailure = editing.calls.count
		page.tapFolderForTesting("account:99")
		page.saveForTesting()
		XCTAssertTrue(page.didCloseForTesting)
		XCTAssertEqual(editing.calls.count, callsAfterFailure)
		window.isHidden = true

		// 在文件夹里的源全部去掉勾 = 放到最外层（空列表）
		(page, window) = try open(feed("b", "Beta"))
		XCTAssertEqual(page.selectionForTesting, ["account:1"])
		page.tapFolderForTesting("account:1")
		page.saveForTesting()
		await waitUntil { page.didCloseForTesting }
		XCTAssertEqual(editing.calls.last, "folders:b:")
		window.isHidden = true
	}

	/// 文章列表页「更多」：「重命名」换成「编辑」，打开同一个编辑页（显示当前名字）；保存改名后列表顶部的名字跟着变。
	func testFeedMoreMenuEditOpensTheSameEditPage() async throws {
		let home = try await makeOrganizableHome()
		// 挂在测试程序自己的场景上的窗口：页面切换动画才会真的播完（没有场景的测试窗口不绘制，切换永远停在半路）
		let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
		home.window.rootViewController = nil
		home.window.isHidden = true
		let window = UIWindow(windowScene: scene)
		window.rootViewController = home.navigation
		window.makeKeyAndVisible()
		defer { window.isHidden = true }
		let alpha = makeFeed(id: FeedSnapshot.ID(accountID: "account", feedID: "a"), title: "Alpha", count: 3)
		home.root.onFeedRequested?(alpha, .unread)
		let list = try XCTUnwrap(home.navigation.viewControllers.last as? Babel2FeedViewController)
		await waitUntil { home.navigation.transitionCoordinator == nil }
		list.loadViewIfNeeded()
		let items = list.moreMenuSectionsForTesting.flatMap { $0 }
		XCTAssertTrue(items.contains { $0.identifier == "babel2.feed.more.edit" })
		XCTAssertFalse(items.contains { $0.identifier == "babel2.feed.more.rename" }, "Edit replaces Rename")
		list.applyRenamedTitle("Alpha Now")
		try XCTUnwrap(items.first { $0.identifier == "babel2.feed.more.edit" }).handler()
		let page = try XCTUnwrap(home.navigation.viewControllers.last as? Babel2FeedEditViewController)
		page.loadViewIfNeeded()
		XCTAssertEqual(page.nameFieldForTesting.text, "Alpha Now", "shows the list's current name")
		XCTAssertEqual(page.selectionForTesting, ["account:1", "account:3"])
		page.nameFieldForTesting.text = "Alpha Later"
		page.saveForTesting()
		await waitUntil { page.didCloseForTesting }
		XCTAssertEqual(home.editing.calls.last, "renameFeed:a->Alpha Later")
		XCTAssertEqual(list.heroViewForTesting?.titleLabel.text, "Alpha Later", "the list shows the new name")
	}

	/// 纯规则：名字留空 / 没变不改名；文件夹没动过不改位置；动过就按列表顺序给出（空 = 最外层）。
	func testFeedEditChangeRules() {
		let order = ["f:1", "f:2", "f:3"]
		var plan = Babel2FeedEditViewController.changes(originalName: "A", typedName: " A ", initial: ["f:2"], selection: ["f:2"], order: order)
		XCTAssertNil(plan.rename)
		XCTAssertNil(plan.folders)
		plan = Babel2FeedEditViewController.changes(originalName: "A", typedName: "   ", initial: ["f:2"], selection: [], order: order)
		XCTAssertNil(plan.rename, "an empty name keeps the old one")
		XCTAssertEqual(plan.folders, [], "no folder ticked → top level")
		plan = Babel2FeedEditViewController.changes(originalName: "A", typedName: "B", initial: [], selection: ["f:3", "f:1"], order: order)
		XCTAssertEqual(plan.rename, "B")
		XCTAssertEqual(plan.folders, ["f:1", "f:3"])
		XCTAssertEqual(Babel2FeedEditViewController.displayAddress("https://marginalrevolution.com/feed"), "marginalrevolution.com/feed")
		XCTAssertEqual(Babel2FeedEditViewController.displayAddress("feed://x"), "feed://x")
	}

	/// 「+」：添加订阅 / 新建文件夹；多个账户时新建文件夹先选账户，再输入名字。
	func testHomeAddMenuOffersSubscriptionAndNewFolderAskingForAccount() async throws {
		let home = try await makeOrganizableHome()
		defer { home.window.isHidden = true }
		home.editing.accountList.append(Babel2AccountChoice(id: "cloud", title: "iCloud"))
		let editor = try XCTUnwrap(home.root.libraryEditor)
		home.root.addButtonForTesting.sendActions(for: .touchUpInside)
		let menu = try XCTUnwrap(editor.lastMenuForTesting)
		XCTAssertEqual(menu.itemControlsForTesting.map(\.accessibilityIdentifier), ["babel2.add.subscription", "babel2.add.folder"])
		menu.selectForTesting("babel2.add.folder")
		let accounts = try XCTUnwrap(editor.lastMenuForTesting)
		XCTAssertEqual(menuTitle(accounts), localized(.newFolderInAccount))
		XCTAssertEqual(accounts.itemControlsForTesting.map(\.accessibilityIdentifier), ["babel2.add.folder.account.account", "babel2.add.folder.account.cloud"])
		accounts.selectForTesting("babel2.add.folder.account.cloud")
		let alert = try XCTUnwrap(editor.lastAlertForTesting)
		XCTAssertEqual(alert.title, localized(.newFolder))
		XCTAssertEqual(alert.actions.map(\.title), [localized(.cancel), localized(.create)])
		await dismissPresented(home.navigation)
		await editor.performCreateFolder(named: "Later", accountID: "cloud")
		XCTAssertEqual(home.editing.calls.last, "create:Later@cloud")

		home.root.addButtonForTesting.sendActions(for: .touchUpInside)
		try XCTUnwrap(editor.lastMenuForTesting).selectForTesting("babel2.add.subscription")
		XCTAssertTrue(home.navigation.topViewController is Babel2AddSubscriptionViewController)
	}

	/// 回到首页时补一次重新加载：在别的页面期间数据变了（读了文章、改了名、换了图标），首页不再停在旧的。
	func testHomeReloadsWhenReturningAfterChangesItMissed() async throws {
		let home = try await makeOrganizableHome()
		defer { home.window.isHidden = true }
		// 模拟进入别的页面（首页消失）再返回（首页重新出现）
		home.root.beginAppearanceTransition(false, animated: false)
		home.root.endAppearanceTransition()
		let starts = await home.provider.libraryStarts.filter { $0 == .unread }.count
		NotificationCenter.default.post(name: .babel2LibraryDidChange, object: nil)
		try await Task.sleep(for: .milliseconds(100))
		let whileAway = await home.provider.libraryStarts.filter { $0 == .unread }.count
		XCTAssertEqual(whileAway, starts, "not reloaded while another page is showing")
		home.root.beginAppearanceTransition(true, animated: false)
		home.root.endAppearanceTransition()
		await waitForLibraryStart(home.provider, .unread, after: starts + 1)
	}

	/// 不在显示的那一档数据变了：切过去时先显示原来的（切换不等加载），切完再补一次重新加载。
	func testSwitchingToAScopeWhoseDataChangedMeanwhileRefreshesItAfterTheSwitch() async throws {
		let home = try await makeOrganizableHome()
		defer { home.window.isHidden = true }
		let root = home.root
		root.applyScope(.all)
		await waitUntil { root.isScopeTransitionSettledForTesting && root.selectedScope == .all }
		root.applyScope(.unread)
		await waitUntil { root.isScopeTransitionSettledForTesting && root.selectedScope == .unread }
		let allStarts = await home.provider.libraryStarts.filter { $0 == .all }.count
		NotificationCenter.default.post(name: .babel2LibraryDidChange, object: nil)
		root.applyScope(.all)
		await waitUntil { root.isScopeTransitionSettledForTesting && root.selectedScope == .all }
		await waitForLibraryStart(home.provider, .all, after: allStarts + 1)
	}

	/// 菜单项多到屏幕放不下（文件夹很多的「移到文件夹」）：卡片高度封顶、可以滚；项少时照旧按内容高度、不滚。
	func testGlassMenuScrollsOnlyWhenTallerThanTheScreen() {
		let host = UIViewController()
		let window = hostInWindow(host)
		defer { window.isHidden = true }
		let anchor = UIView(frame: CGRect(x: 180, y: 400, width: 44, height: 44))
		host.view.addSubview(anchor)
		let items = (0..<30).map { index in Babel2MenuItem(title: "Folder \(index)", identifier: "item.\(index)") {} }
		let tall = Babel2GlassMenu.present(sections: [items], title: "Move", from: anchor, in: host.view)
		XCTAssertTrue(tall.isScrollableForTesting)
		XCTAssertGreaterThanOrEqual(tall.cardFrameForTesting.minY, host.view.safeAreaInsets.top)
		XCTAssertLessThanOrEqual(tall.cardFrameForTesting.maxY, host.view.bounds.height - host.view.safeAreaInsets.bottom)
		tall.removeFromSuperview()
		let short = Babel2GlassMenu.present(sections: [Array(items.prefix(3))], from: anchor, in: host.view)
		XCTAssertFalse(short.isScrollableForTesting)
		XCTAssertEqual(short.cardFrameForTesting.height, 3 * Babel2Type.menuRowHeight + 12, accuracy: 1)
		short.removeFromSuperview()
	}

	// MARK: - 自定义订阅源图标（ADR-046）

	/// 选的图居中裁成正方形：边长取短边、最多 512 像素。
	func testCustomIconIsCenterCroppedToASquareOfAtMost512Pixels() throws {
		let format = UIGraphicsImageRendererFormat()
		format.scale = 1
		let wide = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 100), format: format).image { context in
			UIColor.red.setFill()
			context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
			UIColor.green.setFill()
			context.fill(CGRect(x: 100, y: 0, width: 100, height: 100))
			UIColor.blue.setFill()
			context.fill(CGRect(x: 200, y: 0, width: 100, height: 100))
		}
		let cropped = try XCTUnwrap(Babel2FeedIconImage.squarePNG(from: wide).flatMap(UIImage.init(data:)))
		XCTAssertEqual(cropped.size.width * cropped.scale, 100)
		XCTAssertEqual(cropped.size.height * cropped.scale, 100)
		for x in [3, 50, 96] {
			let pixel = pixelColor(cropped, x: x, y: 50)
			XCTAssertGreaterThan(pixel.green, 200, "only the middle third is kept (x=\(x))")
			XCTAssertLessThan(pixel.red, 40)
			XCTAssertLessThan(pixel.blue, 40)
		}
		let big = solidImage(size: CGSize(width: 2000, height: 1000), color: .gray)
		let scaled = try XCTUnwrap(Babel2FeedIconImage.squarePNG(from: big).flatMap(UIImage.init(data:)))
		XCTAssertEqual(scaled.size.width * scaled.scale, 512)
		XCTAssertEqual(scaled.size.height * scaled.scale, 512)
	}

	/// 存在手机上：列表用 96 像素小图、大图用原图；图标缓存与大图都优先用它；重新启动后照样读回；
	/// 不是图片的数据不收；恢复默认删掉文件。
	func testCustomFeedIconIsStoredCompactedPreferredAndReset() throws {
		let directory = FileManager.default.temporaryDirectory.appendingPathComponent("babel2-icons-\(UUID().uuidString)")
		Babel2LiveCustomFeedIcons.directoryOverrideForTesting = directory
		Babel2LiveCustomFeedIcons.forgetCachedForTesting()
		defer {
			Babel2LiveCustomFeedIcons.directoryOverrideForTesting = nil
			Babel2LiveCustomFeedIcons.forgetCachedForTesting()
			try? FileManager.default.removeItem(at: directory)
		}
		let id = FeedSnapshot.ID(accountID: "test-account", feedID: "https://example.com/feed/\(UUID().uuidString)")
		XCTAssertFalse(Babel2LiveCustomFeedIcons.hasCustomIcon(id))
		let data = try XCTUnwrap(Babel2FeedIconImage.squarePNG(from: solidImage(size: CGSize(width: 800, height: 800), color: .systemRed)))
		XCTAssertTrue(Babel2LiveCustomFeedIcons.set(data, for: id))
		XCTAssertTrue(Babel2LiveCustomFeedIcons.hasCustomIcon(id))
		let small = try XCTUnwrap(Babel2LiveCustomFeedIcons.iconData(for: id).flatMap(UIImage.init(data:)))
		XCTAssertEqual(max(small.size.width * small.scale, small.size.height * small.scale), 96)
		XCTAssertEqual(Babel2LiveIconCache.currentIconData(for: id), Babel2LiveCustomFeedIcons.iconData(for: id), "the custom icon wins")
		let hero = try XCTUnwrap(Babel2LiveFeedHeroImage.cached(id))
		XCTAssertEqual(hero.size.width * hero.scale, 512)

		Babel2LiveCustomFeedIcons.forgetCachedForTesting()
		XCTAssertTrue(Babel2LiveCustomFeedIcons.hasCustomIcon(id), "read back from disk after a restart")
		XCTAssertFalse(Babel2LiveCustomFeedIcons.set(Data("not an image".utf8), for: id))
		XCTAssertTrue(Babel2LiveCustomFeedIcons.hasCustomIcon(id), "a bad image leaves the old icon alone")

		XCTAssertTrue(Babel2LiveCustomFeedIcons.set(nil, for: id))
		XCTAssertFalse(Babel2LiveCustomFeedIcons.hasCustomIcon(id))
		XCTAssertFalse(FileManager.default.fileExists(atPath: Babel2LiveCustomFeedIcons.fileURL(for: id).path))
	}

	/// 文章列表「更多」：更换图标后窄栏、每一行、顶部大图立即换上；换过才有「恢复默认图标」，恢复后换回（没有网站图就回纸色底）；
	/// 读不出的图弹出说明。
	func testFeedMoreMenuChangesAndResetsIconImmediately() async throws {
		final class StoredIcon { var data: Data? }
		let stored = StoredIcon()
		let feedID = FeedSnapshot.ID(accountID: "account", feedID: "feed")
		let articles = [ArticleSnapshot(id: ArticleSnapshot.ID(accountID: "account", feedID: "feed", articleID: "1"), title: "T", url: nil, feedID: feedID)]
		let actions = Babel2FeedActions(
			refresh: {}, isSyncing: { false }, homePageURL: { nil }, feedURL: { nil },
			isAlwaysReadingMode: { false }, setAlwaysReadingMode: { _ in },
			notificationsEnabled: { false }, setNotificationsEnabled: { _ in },
			hasCustomIcon: { stored.data != nil },
			setCustomIcon: { data in
				stored.data = data
				return true
			},
			rename: { _ in nil }, unsubscribe: { nil }, openURL: { _ in }
		)
		let controller = Babel2FeedViewController(
			feed: makeFeed(id: feedID, title: "Feed"), scope: .all,
			environment: makeEnvironment(provider: FakeDataProvider(feeds: [feedID: articles])),
			heroImage: Babel2FeedHeroImageSource(cached: { stored.data.flatMap(UIImage.init(data:)) }, fetch: { _ in }),
			feedActions: actions,
			currentIcon: { stored.data }
		)
		let window = hostInWindow(controller)
		defer { window.isHidden = true }
		await waitForRows(in: controller.tableViewForTesting, count: 1)
		func identifiers() -> [String] { controller.moreMenuSectionsForTesting.flatMap { $0.map(\.identifier) } }
		XCTAssertTrue(identifiers().contains("babel2.feed.more.icon"))
		XCTAssertFalse(identifiers().contains("babel2.feed.more.icon-reset"))
		XCTAssertFalse(controller.hasFeedIconForTesting)

		let icon = try XCTUnwrap(Babel2FeedIconImage.squarePNG(from: solidImage(size: CGSize(width: 300, height: 300), color: .systemOrange)))
		controller.applyPickedIcon(icon)
		XCTAssertTrue(controller.hasFeedIconForTesting, "the compact bar and rows switch right away")
		let hero = try XCTUnwrap(controller.heroViewForTesting)
		await waitUntil { hero.hasArtForTesting }
		XCTAssertTrue(identifiers().contains("babel2.feed.more.icon-reset"))

		let reset = try XCTUnwrap(controller.moreMenuSectionsForTesting.flatMap { $0 }.first { $0.identifier == "babel2.feed.more.icon-reset" })
		reset.handler()
		XCTAssertNil(stored.data)
		XCTAssertFalse(controller.hasFeedIconForTesting)
		await waitUntil { !hero.hasArtForTesting }

		controller.applyPickedIcon(nil)
		await waitUntil { controller.presentedViewController is UIAlertController }
		XCTAssertEqual((controller.presentedViewController as? UIAlertController)?.message, localized(.unableToUseImage))
		controller.dismiss(animated: false)
	}

	/// 接入层（真实账户）：新建的空文件夹出现在首页未读 / 全部档（星标档不列）；改名；
	/// 有顶层的源时：放进这个文件夹、同时放进两个、一个都不选回到顶层（ADR-061），再放进去后「只删文件夹」——源回到顶层，一个也不丢。
	func testLiveLibraryEditingFolderLifecycleKeepsFeeds() async throws {
		guard let account = Babel2LiveLibraryEditing.accounts().first else { throw XCTSkip("no account in the test host") }
		let name = "Babel2 Test \(UUID().uuidString.prefix(6))"
		let folderID = try await Babel2LiveLibraryEditing.createFolder(named: name, accountID: account.id).get()
		var deleted = false
		defer {
			if !deleted { Task { @MainActor in _ = await Babel2LiveLibraryEditing.deleteFolder(folderID, keepFeeds: true) } }
		}
		XCTAssertEqual(Babel2LiveLibraryEditing.folderInfo(folderID)?.title, name)
		XCTAssertEqual(Babel2LiveLibraryEditing.folderInfo(folderID)?.feedCount, 0)
		let renameError = await Babel2LiveLibraryEditing.renameFolder(folderID, to: name + " R")
		XCTAssertNil(renameError)
		XCTAssertEqual(Babel2LiveLibraryEditing.folderInfo(folderID)?.title, name + " R")

		let provider = Babel2LiveDataProvider()
		let unread = try await provider.librarySnapshot(for: .unread)
		XCTAssertTrue(unread.folders.contains { $0.id == folderID && $0.feedIDs.isEmpty }, "an empty folder is listed")
		let starred = try await provider.librarySnapshot(for: .starred)
		XCTAssertFalse(starred.folders.contains { $0.id == folderID })

		let all = try await provider.librarySnapshot(for: .all)
		let topLevel = all.feeds.first { feed in
			feed.id.accountID == account.id && Babel2LiveLibraryEditing.placement(feed.id)?.current.map(\.folderID) == [nil]
		}
		if let feed = topLevel {
			XCTAssertTrue(Babel2LiveLibraryEditing.placement(feed.id)?.destinations.contains { $0.folderID == folderID } ?? false)
			// 编辑页（ADR-061）：放进这个文件夹 → 只在这里（从最外层移走）
			let moveError = await Babel2LiveLibraryEditing.setFolders(feed.id, to: [folderID])
			XCTAssertNil(moveError)
			XCTAssertEqual(Babel2LiveLibraryEditing.placement(feed.id)?.current.map(\.folderID), [folderID])
			XCTAssertEqual(Babel2LiveLibraryEditing.folderInfo(folderID)?.feedCount, 1)
			// 同时放进第二个文件夹：一个源可以在几个文件夹里
			let secondID = try await Babel2LiveLibraryEditing.createFolder(named: name + " 2", accountID: account.id).get()
			let bothError = await Babel2LiveLibraryEditing.setFolders(feed.id, to: [folderID, secondID])
			XCTAssertNil(bothError)
			XCTAssertEqual(Set(Babel2LiveLibraryEditing.placement(feed.id)?.current.map(\.folderID) ?? []), [folderID, secondID])
			// 一个都不选：回到最外层，不会被取消订阅
			let topError = await Babel2LiveLibraryEditing.setFolders(feed.id, to: [])
			XCTAssertNil(topError)
			XCTAssertEqual(Babel2LiveLibraryEditing.placement(feed.id)?.current.map(\.folderID), [nil])
			let deleteSecondError = await Babel2LiveLibraryEditing.deleteFolder(secondID, keepFeeds: true)
			XCTAssertNil(deleteSecondError)
			// 再放进去，然后「只删文件夹」：源回到最外层
			let againError = await Babel2LiveLibraryEditing.setFolders(feed.id, to: [folderID])
			XCTAssertNil(againError)
			let deleteError = await Babel2LiveLibraryEditing.deleteFolder(folderID, keepFeeds: true)
			deleted = true
			XCTAssertNil(deleteError)
			XCTAssertEqual(Babel2LiveLibraryEditing.placement(feed.id)?.current.map(\.folderID), [nil], "the feed is back at the top level")
		} else {
			let deleteError = await Babel2LiveLibraryEditing.deleteFolder(folderID, keepFeeds: true)
			deleted = true
			XCTAssertNil(deleteError)
		}
		XCTAssertNil(Babel2LiveLibraryEditing.folderInfo(folderID))
	}

	// MARK: - 添加订阅页（2026-09-25，ADR-030）

	/// 首页「+」→「添加订阅」打开添加订阅页（路由恢复 home → addSubscription）。
	func testAddButtonOpensAddSubscriptionPage() throws {
		let navigation = Babel2SceneComposition.makeRoot(environment: makeEnvironment(provider: FakeDataProvider()),
			settingsService: FakeSettingsService(), subscriptionService: FakeSubscriptionService())
		let window = hostInWindow(navigation)
		defer { window.isHidden = true }
		let root = try XCTUnwrap(navigation.viewControllers.first as? Babel2RootViewController)
		root.loadViewIfNeeded()
		let add = try XCTUnwrap(descendant(of: root.view, matching: UIButton.self) { $0.accessibilityIdentifier == "babel2.add" })
		add.sendActions(for: .touchUpInside)
		// 「+」先弹菜单（添加订阅 / 新建文件夹，ADR-045），选「添加订阅」进添加订阅页
		let menu = try XCTUnwrap(root.view.subviews.compactMap { $0 as? Babel2GlassMenu }.last)
		XCTAssertEqual(menu.itemControlsForTesting.map(\.accessibilityIdentifier), ["babel2.add.subscription", "babel2.add.folder"])
		menu.selectForTesting("babel2.add.subscription")
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
	/// 模型页排行（ADR-038）：热门前 10；按服务商总热度挑 12 家，每家最热 3 个 + 剩下最便宜 2 个；
	/// 模型少的服务商也列出；每行行尾显示价格；超过 3 天没刷新算过期。
	func testTranslationModelRankingAndEditor() throws {
		var models = [Babel2TranslationModel]()
		for vendor in 0..<14 {
			for index in 0..<(vendor == 13 ? 2 : 7) {
				// 热度随编号递减；价格：编号越大越便宜（最便宜的两个是 m6、m5）
				models.append(Babel2TranslationModel(id: "v\(vendor)/m\(index)", name: "V\(vendor) M\(index)", vendor: "v\(vendor)",
					popularity: Double(100 - vendor * 5 - index), created: 0,
					usdPerArticle: Double(10 - index) / 1000, priceText: "≈¥0.0\(10 - index)/篇"))
			}
		}
		let top = Babel2TranslationModelRanking.top(models)
		XCTAssertEqual(top.count, 10)
		XCTAssertEqual(top.first?.id, "v0/m0")
		XCTAssertEqual(top.map(\.popularity), top.map(\.popularity).sorted(by: >))
		let groups = Babel2TranslationModelRanking.vendorGroups(models)
		XCTAssertEqual(groups.count, 12, "at most 12 vendors")
		XCTAssertEqual(groups.first?.vendor, "v0", "ordered by the vendor's total popularity")
		XCTAssertEqual(groups.first?.models.map(\.id), ["v0/m0", "v0/m1", "v0/m2", "v0/m6", "v0/m5"], "3 most popular + 2 cheapest")
		XCTAssertTrue(groups.allSatisfy { $0.models.count <= 5 })

		// 模型少的服务商也要列出（以前不足 3 个就整家不显示——小米就是这样没了）
		let fewModels = [
			Babel2TranslationModel(id: "xiaomi/mimo", name: "MiMo", vendor: "xiaomi", popularity: 0.3, created: 0, usdPerArticle: 0.001),
			Babel2TranslationModel(id: "big/a", name: "A", vendor: "big", popularity: 0.1, created: 0, usdPerArticle: 0.01),
			Babel2TranslationModel(id: "big/b", name: "B", vendor: "big", popularity: 0.1, created: 0, usdPerArticle: 0.02),
			Babel2TranslationModel(id: "big/c", name: "C", vendor: "big", popularity: 0.05, created: 0, usdPerArticle: 0.03)
		]
		let fewGroups = Babel2TranslationModelRanking.vendorGroups(fewModels)
		XCTAssertEqual(fewGroups.map(\.vendor), ["xiaomi", "big"])
		XCTAssertEqual(fewGroups.first?.models.map(\.id), ["xiaomi/mimo"])

		XCTAssertTrue(Babel2SettingsTranslationModelViewController.isStale(nil))
		XCTAssertFalse(Babel2SettingsTranslationModelViewController.isStale(Date().addingTimeInterval(-2 * 24 * 3600)))
		XCTAssertTrue(Babel2SettingsTranslationModelViewController.isStale(Date().addingTimeInterval(-4 * 24 * 3600)))

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
		let row = try XCTUnwrap(descendant(of: editor.view, matching: Babel2SettingsChoiceRow.self) { $0.accessibilityIdentifier == "babel2.settings.translation-model.option.v0/m6" })
		XCTAssertEqual(row.detailLabel.text, "≈¥0.04/篇", "price shown at the end of the row")
		editor.chooseForTesting("v3/m1")
		XCTAssertEqual(service.translationModelID, "v0/m0", "not applied before save")
		editor.saveTapped()
		XCTAssertEqual(service.translationModelID, "v3/m1")
	}

	/// 模型目录（ADR-038）：热度记在正主模型上，不被共用同一带日期写法的 `:batch` / `:free` 变体吃掉；
	/// 用量榜只算 standard 变体，分数是占总用量的比例。
	func testModelCatalogCreditsPopularityToBaseModelsNotVariants() throws {
		let catalog = #"{"data":[{"id":"deepseek/deepseek-v4.1-flash","canonical_slug":"deepseek/deepseek-v4.1-flash-20260910"},{"id":"deepseek/deepseek-v4.1-flash:batch","canonical_slug":"deepseek/deepseek-v4.1-flash-20260910"},{"id":"xiaomi/mimo-v2.5:free","canonical_slug":"xiaomi/mimo-v2.5-20260422"},{"id":"xiaomi/mimo-v2.5","canonical_slug":"xiaomi/mimo-v2.5-20260422"}]}"#
		let map = OpenRouterCatalog.canonicalMap(from: Data(catalog.utf8))
		XCTAssertEqual(map["deepseek/deepseek-v4.1-flash-20260910"], "deepseek/deepseek-v4.1-flash", "a later :batch variant must not take over")
		XCTAssertEqual(map["xiaomi/mimo-v2.5-20260422"], "xiaomi/mimo-v2.5", "the base model replaces an earlier :free variant")

		let usage = #"{"data":[{"model_permaslug":"deepseek/deepseek-v4.1-flash-20260910","variant":"standard","rankingMetricValue":300},{"model_permaslug":"deepseek/deepseek-v4.1-flash-20260910","variant":"batch","rankingMetricValue":900},{"model_permaslug":"xiaomi/mimo-v2.5-20260422","variant":"standard","rankingMetricValue":100}]}"#
		let scores = OpenRouterRankings.parseUsage(Data(usage.utf8), canonicalMap: map)
		XCTAssertEqual(scores["deepseek/deepseek-v4.1-flash"] ?? 0, 0.75, accuracy: 0.0001)
		XCTAssertEqual(scores["xiaomi/mimo-v2.5"] ?? 0, 0.25, accuracy: 0.0001)
		XCTAssertNil(scores["deepseek/deepseek-v4.1-flash:batch"])
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
			// 第一行字的中线 = 标题顶 + 半个行高（行高固定 20，ADR-033）
			XCTAssertEqual(icon.frame.midY, title.frame.minY + Babel2Type.rowTitleLineHeight / 2, accuracy: 1.5, "icon aligned with first title line (row \(row))")
			heights.append(cell.bounds.height)
		}
		// ADR-054（2026-09-27）起标题 + 摘要合计 3 行：一行标题的行摘要显示两行，与两行标题的行一样高（原先断言「更矮」）
		XCTAssertEqual(heights[1], heights[0], accuracy: 0.5, "one-line and two-line title rows are equally tall (title + summary share three lines)")
		// 行顶留白 16 + 来源行 14 + 间距 4 → 标题顶；缩略图比标题低 3、边长 64，下面再留 16
		XCTAssertGreaterThanOrEqual(heights[2], 16 + 14 + 4 + 3 + 64 + 16, "thumbnail row still fits the thumbnail")
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
	/// 没有订阅源图标时显示首字母方块；标题一行时摘要两行（标题 + 摘要合计 3 行）；不再有「英文 → 简体中文」提示行。
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
		XCTAssertEqual(try label("babel2.article.summary").numberOfLines, 2, "one-line title leaves two lines for the summary")
		XCTAssertFalse(labels.contains { $0.text == "英文 → 简体中文" }, "no translation hint line")
		let date = try label("babel2.article.date")
		XCTAssertEqual(date.convert(date.bounds, to: cell.contentView).maxX, cell.contentView.bounds.width - 20, accuracy: 0.5)
		let icon = try XCTUnwrap(descendant(of: cell, matching: UIImageView.self) { $0.accessibilityIdentifier == "babel2.article.feed-icon" })
		XCTAssertEqual(icon.bounds.size, CGSize(width: 20, height: 20))
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
		let capHeight = Babel2Type.rowTitle(read: false).capHeight
		XCTAssertEqual(icon.convert(icon.bounds, to: cell.contentView).midY, firstBaseline - capHeight / 2, accuracy: 1)
	}

	/// 标题 + 摘要合计 3 行（2026-09-27 用户选定）：标题一行 → 摘要两行，标题两行 → 摘要一行；
	/// 两种行一样高（没有缩略图时都是 16 + 14 + 4 + 3×20 + 2 + 16 = 112pt），摘要真的显示成两行。
	func testRowTitleAndSummaryShareThreeLines() async throws {
		let feedID = FeedSnapshot.ID(accountID: "account", feedID: "feed")
		let now = Date()
		let longSummary = String(repeating: "A long summary sentence. ", count: 20)
		let short = ArticleSnapshot(id: ArticleSnapshot.ID(accountID: "account", feedID: "feed", articleID: "short"), title: "Short title",
			summary: longSummary, url: nil, feedID: feedID, publishedAt: now)
		let long = ArticleSnapshot(id: ArticleSnapshot.ID(accountID: "account", feedID: "feed", articleID: "long"),
			title: String(repeating: "A very long headline that wraps ", count: 6),
			summary: longSummary, url: nil, feedID: feedID, publishedAt: now.addingTimeInterval(-60))
		let controller = Babel2FeedViewController(feed: makeFeed(id: feedID, title: "Feed"), scope: .all,
			environment: makeEnvironment(provider: FakeDataProvider(feeds: [feedID: [short, long]])))
		let window = hostInWindow(controller)
		defer { window.isHidden = true }
		let tableView = try XCTUnwrap(descendant(of: controller.view, matching: UITableView.self))
		await waitForRows(in: tableView, count: 2)
		tableView.layoutIfNeeded()
		func row(_ index: Int) throws -> (cell: UITableViewCell, title: UILabel, summary: UILabel) {
			let cell = try XCTUnwrap(tableView.cellForRow(at: IndexPath(row: index, section: 0)))
			let labels = cell.contentView.subviews.compactMap { $0 as? UILabel }
			return (cell,
				try XCTUnwrap(labels.first { $0.accessibilityIdentifier == "babel2.article.title" }),
				try XCTUnwrap(labels.first { $0.accessibilityIdentifier == "babel2.article.summary" }))
		}
		let first = try row(0), second = try row(1)
		XCTAssertEqual(first.title.bounds.height, 20, accuracy: 0.5, "short title is one line")
		XCTAssertEqual(first.summary.numberOfLines, 2)
		XCTAssertEqual(first.summary.bounds.height, 40, accuracy: 0.5, "summary actually shows two lines")
		XCTAssertEqual(second.title.bounds.height, 40, accuracy: 0.5, "long title is capped at two lines")
		XCTAssertEqual(second.summary.numberOfLines, 1)
		XCTAssertEqual(second.summary.bounds.height, 20, accuracy: 0.5)
		XCTAssertEqual(first.cell.bounds.height, second.cell.bounds.height, accuracy: 0.5, "both rows are equally tall")
		XCTAssertEqual(first.cell.bounds.height, 112, accuracy: 1)
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
		XCTAssertEqual(loaded.bounds.size, CGSize(width: 64, height: 64))
		XCTAssertEqual(loaded.layer.cornerRadius, 5)
		let pixelWidth = CGFloat(image.cgImage?.width ?? 0), pixelHeight = CGFloat(image.cgImage?.height ?? 0)
		XCTAssertLessThanOrEqual(max(pixelWidth, pixelHeight), 64 * max(controller.traitCollection.displayScale, 1), "decoded at thumbnail size, not 2400px")
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

	// MARK: - 内置浏览器：去广告与翻译此页（ADR-047）

	/// 去广告规则能编译；只拦第三方请求；按域名匹配（含子域），网址参数里出现这些字样不误伤；另有一条收起广告空位的规则。
	func testAdBlockRulesCompileAndMatchAdHostsOnly() async throws {
		let list = await Babel2AdBlocker.ruleList()
		XCTAssertNotNil(list, "the rule list compiles")
		let rules = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(Babel2AdBlocker.encodedRules.utf8)) as? [[String: Any]])
		XCTAssertEqual(rules.count, Babel2AdBlocker.blockedDomains.count + 1)
		for rule in rules.dropLast() {
			let trigger = try XCTUnwrap(rule["trigger"] as? [String: Any])
			XCTAssertEqual(trigger["load-type"] as? [String], ["third-party"])
			XCTAssertEqual((rule["action"] as? [String: Any])?["type"] as? String, "block")
		}
		let hide = try XCTUnwrap(rules.last?["action"] as? [String: Any])
		XCTAssertEqual(hide["type"] as? String, "css-display-none")
		XCTAssertTrue((hide["selector"] as? String)?.contains("ins.adsbygoogle") ?? false)

		func blocked(_ address: String) -> Bool {
			Babel2AdBlocker.blockedDomains.contains { domain in
				guard let regex = try? NSRegularExpression(pattern: Babel2AdBlocker.urlFilter(for: domain)) else { return false }
				return regex.firstMatch(in: address, range: NSRange(address.startIndex..., in: address)) != nil
			}
		}
		for address in ["https://securepubads.g.doubleclick.net/tag/js/gpt.js",
			"https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client=ca-pub-1",
			"https://adservice.google.com/adsid/integrator.js", "http://cdn.taboola.com:443/libtrc/loader.js",
			"https://pos.baidu.com/s?hei=250"] {
			XCTAssertTrue(blocked(address), address)
		}
		for address in ["https://www.google.com/search?q=doubleclick.net", "https://example.com/story?ref=taboola.com",
			"https://notdoubleclick.net/", "https://www.google.com/", "https://news.baidu.com/", "https://www.nytimes.com/"] {
			XCTAssertFalse(blocked(address), address)
		}
	}

	/// 浏览器右上角「•••」：翻译此页（注入了处理方时才有）/ 去广告（默认开，可临时关、再打开）。
	func testBrowserMoreMenuOffersTranslatePageAndTogglesAdBlock() async throws {
		let browser = Babel2BrowserViewController(url: URL(string: "https://nonexistent.invalid/")!, openExternally: { _ in }, onTranslatePage: { _ in })
		let window = hostInWindow(browser)
		defer { window.isHidden = true }
		let more = try XCTUnwrap(descendant(of: browser.view, matching: UIButton.self) { $0.accessibilityIdentifier == "babel2.browser.more" })
		XCTAssertEqual(more.convert(CGPoint(x: more.bounds.midX, y: 0), to: browser.view).x, browser.view.bounds.width - 32, accuracy: 0.5,
			"mirrors the close button")
		await waitUntil { browser.isAdBlockReadyForTesting }
		func items() -> [Babel2MenuItem] { browser.makeMoreMenuSections().flatMap { $0 } }
		XCTAssertEqual(items().map(\.identifier), ["babel2.browser.translate-page", "babel2.browser.adblock"])
		XCTAssertEqual(items().last?.isOn, true, "ad blocking is on by default")
		browser.setAdBlock(false)
		XCTAssertFalse(browser.isAdBlockOn)
		XCTAssertEqual(items().last?.isOn, false)
		items().last?.handler()
		XCTAssertTrue(browser.isAdBlockOn, "can be turned back on")

		let plain = Babel2BrowserViewController(url: URL(string: "https://nonexistent.invalid/")!, openExternally: { _ in })
		plain.loadViewIfNeeded()
		XCTAssertEqual(plain.makeMoreMenuSections().flatMap { $0 }.map(\.identifier), ["babel2.browser.adblock"])
	}

	/// 「翻译此页」：在当前网页里抽出正文（去掉导航、被隐藏的浮层），开一个独立阅读页并自动翻译；
	/// 独立阅读页没有已读 / 星标 / 下一篇 / 阅读模式，打开时不发任何状态请求。
	func testTranslatePageExtractsArticleAndOpensStandaloneReaderThatTranslates() async throws {
		let restore = useFakeTranslationServer()
		defer { restore() }
		final class Captured { var page: Babel2BrowserViewController.PageContent? }
		let captured = Captured()
		let browser = Babel2BrowserViewController(url: URL(string: "https://nonexistent.invalid/")!, openExternally: { _ in },
			onTranslatePage: { captured.page = $0 })
		let window = hostInWindow(browser)
		defer { window.isHidden = true }
		let paragraphs = (0..<8).map { index in
			"<p>Paragraph \(index) of the story explains how a small team rebuilt its reading app, step by step, with care and patience.</p>"
		}.joined()
		let html = """
		<html><head><title>Rebuilding a Reader | Example News</title></head><body>
		<nav><a href="/">Home</a> <a href="/tech">Tech</a> Site navigation menu</nav>
		<article><h1>Rebuilding a Reader</h1>\(paragraphs)
		<p>Inline <span style="display:none">HIDDEN FLOATER that only shows on hover</span> terms stay readable.</p></article>
		<footer>Copyright footer text</footer></body></html>
		"""
		let address = URL(string: "https://example.com/2026/09/rebuilding-\(UUID().uuidString)")!
		browser.loadHTMLForTesting(html, baseURL: address)
		try await Task.sleep(for: .milliseconds(300))
		await waitUntil { !browser.isPageLoadingForTesting }
		browser.translatePageForTesting()
		for _ in 0..<100 where captured.page == nil { try await Task.sleep(for: .milliseconds(50)) }
		let page = try XCTUnwrap(captured.page, "the article is extracted")
		XCTAssertEqual(page.url, address)
		XCTAssertTrue(page.title.contains("Rebuilding a Reader"), page.title)
		XCTAssertTrue(page.html.contains("Paragraph 0 of the story"))
		XCTAssertFalse(page.html.contains("HIDDEN FLOATER"), "elements hidden on the page are dropped")
		XCTAssertFalse(page.html.contains("Site navigation menu"))
		XCTAssertTrue(page.articleID.hasPrefix("web-"))
		XCTAssertEqual(page.articleID, Babel2BrowserViewController.PageContent(url: address, title: "x", html: "y", byline: nil).articleID,
			"the same address always gets the same ID (reuses the translation cache)")

		let handler = RecordingActionHandler()
		let reader = Babel2SceneComposition.makeWebPageReader(page, navigationController: nil,
			environment: makeEnvironment(provider: FakeDataProvider(), actionHandler: handler), settings: FakeSettingsService(), openURL: { _ in })
		let readerWindow = hostInWindow(reader)
		defer { readerWindow.isHidden = true }
		await waitForReaderRender(reader)
		await waitForTranslation(reader, toReach: .translated)
		let translated = await reader.readerContentView.articleTextForTesting() ?? ""
		XCTAssertGreaterThan(Self.cjkRatio(translated), 0.9, "translated automatically")
		XCTAssertFalse(reader.toolbarView.readButton.isEnabled)
		XCTAssertFalse(reader.toolbarView.starButton.isEnabled)
		XCTAssertFalse(reader.toolbarView.readingModeButton.isEnabled)
		XCTAssertFalse(reader.toolbarView.nextButton.isEnabled)
		let actions = await handler.actions
		XCTAssertTrue(actions.isEmpty, "a standalone page is never marked read / starred: \(actions)")
	}

	/// 抽不出正文的页面（只有几个链接）：不开阅读页，说明原因。
	func testTranslatePageExplainsWhenThereIsNoArticle() async throws {
		final class Captured { var page: Babel2BrowserViewController.PageContent? }
		let captured = Captured()
		let browser = Babel2BrowserViewController(url: URL(string: "https://nonexistent.invalid/")!, openExternally: { _ in },
			onTranslatePage: { captured.page = $0 })
		let window = hostInWindow(browser)
		defer { window.isHidden = true }
		browser.loadHTMLForTesting("<html><body><a href='/a'>A</a> <a href='/b'>B</a></body></html>", baseURL: URL(string: "https://example.com/")!)
		try await Task.sleep(for: .milliseconds(300))
		await waitUntil { !browser.isPageLoadingForTesting }
		browser.translatePageForTesting()
		await waitUntil { browser.presentedViewController is UIAlertController }
		XCTAssertNil(captured.page)
		XCTAssertEqual((browser.presentedViewController as? UIAlertController)?.message, localized(.unableToExtractPage))
		browser.dismiss(animated: false)
	}

	// MARK: - 统一图标集（ADR-065，取代 ADR-052 的逐个视觉修正）

	/// 47 个图标都在、都是 24pt 模板图；三条底栏的图标一律 21pt（首页 / 列表档位没选中 21、选中 16）；
	/// 「全部标为已读」是空心圆 + 勾；翻译「文A」右下角空着给角标，实心 / 空心角标都落在那里；
	/// 阅读模式四道线与图标集同一组坐标（最后一道短）；图标颜色「深一档」。
	func testUnifiedIconSetAcrossBars() {
		for icon in Babel2Icon.allCases {
			let asset = icon.asset
			XCTAssertNotNil(asset, icon.assetName)
			XCTAssertEqual(asset?.size, CGSize(width: 24, height: 24), icon.assetName)
			XCTAssertEqual(icon.image(size: 18)?.renderingMode, .alwaysTemplate, icon.assetName)
		}
		let toolbar = Babel2ReaderToolbarView()
		for button in [toolbar.readButton, toolbar.starButton, toolbar.nextButton] {
			XCTAssertEqual(button.image(for: .normal)?.size, CGSize(width: 21, height: 21))
			XCTAssertEqual(button.tintColor, Babel2Icon.tint)
		}
		XCTAssertEqual(toolbar.starIconName, Babel2Icon.star.rawValue)
		XCTAssertEqual(toolbar.readIconName, Babel2Icon.readOff.rawValue)

		let filter = Babel2ScopeFilterControl(selectedScope: .unread)
		XCTAssertEqual(filter.buttons[.starred]?.icon?.size, CGSize(width: 21, height: 21), "same size as the reader star")
		XCTAssertEqual(filter.buttons[.all]?.icon?.size, CGSize(width: 21, height: 21))
		filter.setSelectedScope(.starred, animated: false)
		XCTAssertEqual(filter.buttons[.starred]?.icon?.size, CGSize(width: 16, height: 16), "the selected star sits in the capsule")

		// 24 网格坐标 → 21pt 画布
		func grid(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * 21 / 24, y: y * 21 / 24) }
		let readAll = try! XCTUnwrap(Babel2Icon.readAll.image(size: 21))
		// 第八轮 Reeder 式（ADR-066）：实心圆 + 反白的勾（Reeder 列表底栏左 1 同款）
		XCTAssertGreaterThan(alphaAt(readAll, grid(12, 4)), 0.5, "the circle is drawn")
		XCTAssertGreaterThan(alphaAt(readAll, grid(8, 9)), 0.8, "solid disc")
		XCTAssertLessThan(alphaAt(readAll, grid(10.9, 14.9)), 0.2, "the check is knocked out of the disc")

		let plain = Babel2TranslateGlyph.image(.none)
		XCTAssertEqual(plain.size, CGSize(width: 21, height: 21))
		XCTAssertLessThan(alphaAt(plain, grid(20, 20)), 0.1, "bottom-right corner left free for the badge")
		XCTAssertGreaterThan(alphaAt(Babel2TranslateGlyph.image(.solidDot), grid(20, 20)), 0.8, "solid badge = whole translation cached")
		let hollow = Babel2TranslateGlyph.image(.hollowDot)
		XCTAssertLessThan(alphaAt(hollow, grid(20, 20)), 0.3, "hollow badge = partly translated")
		XCTAssertGreaterThan(alphaAt(hollow, grid(20, 18.4)), 0.4)

		XCTAssertEqual(Babel2ReaderModeIconButton.lineLengthsForTesting, [13, 13, 13, 7.5])

		func rgb(_ color: UIColor, _ style: UIUserInterfaceStyle) -> [Int] {
			var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
			color.resolvedColor(with: UITraitCollection(userInterfaceStyle: style)).getRed(&r, green: &g, blue: &b, alpha: &a)
			return [r, g, b].map { Int(($0 * 255).rounded()) }
		}
		XCTAssertEqual(rgb(Babel2Icon.tint, .light), [94, 94, 94])
		XCTAssertEqual(rgb(Babel2Icon.tint, .dark), [168, 168, 168])
	}

	// MARK: - 位置记忆（ADR-053）

	/// 文章里：记下读到第几段，重新打开（新的阅读页、存盘后重读）回到同一段；回到顶部再离开就清掉。
	func testReaderRemembersReadingPositionAcrossOpens() async throws {
		let file = FileManager.default.temporaryDirectory.appendingPathComponent("babel2-positions-\(UUID().uuidString).json")
		defer { try? FileManager.default.removeItem(at: file) }
		let store = Babel2PositionStore(fileURL: file)
		let body = Self.longArticleBody(paragraphs: 30)
		let first = makeReader(body: body, positionStore: store)
		var window = hostInWindow(first)
		await waitForReaderRender(first)
		await waitForScrollableLength(first, atLeast: 2000)
		first.readerContentView.scrollView.setContentOffset(CGPoint(x: 0, y: 1500), animated: false)
		await first.capturePosition()
		let saved = try XCTUnwrap(store.articlePosition(for: ArticleSnapshot.ID(accountID: "account", feedID: "feed", articleID: "reader-article")))
		XCTAssertGreaterThanOrEqual(saved.block, 2, "well into the article body")
		window.isHidden = true

		store.saveNow()
		let reopenedStore = Babel2PositionStore(fileURL: file)
		let second = makeReader(body: body, positionStore: reopenedStore)
		window = hostInWindow(second)
		defer { window.isHidden = true }
		XCTAssertTrue(second.isRestoringPositionForTesting)
		await waitForReaderRender(second)
		await waitUntil { abs(second.readerContentView.scrollView.contentOffset.y - 1500) < 40 }
		XCTAssertEqual(second.readerContentView.scrollView.contentOffset.y, 1500, accuracy: 40, "back to the same paragraph")
		XCTAssertEqual(second.barVisibilityProgress, 0, "jumping back does not hide the bars")

		second.readerContentView.scrollView.setContentOffset(CGPoint(x: 0, y: -second.readerContentView.scrollView.adjustedContentInset.top), animated: false)
		// 用户自己滑回顶部（相当于自己动手滑过）再离开：清掉，下次从头开始
		second.endPositionRestoreForTesting()
		await second.capturePosition()
		XCTAssertNil(reopenedStore.articlePosition(for: ArticleSnapshot.ID(accountID: "account", feedID: "feed", articleID: "reader-article")))
	}

	/// 开着阅读模式离开的文章：重新打开时先排的是摘要，全文到了之后才对到记下的那一段（全文比摘要长得多也对得上）。
	func testReaderRestoresPositionAfterFullTextArrives() async throws {
		let file = FileManager.default.temporaryDirectory.appendingPathComponent("babel2-positions-\(UUID().uuidString).json")
		defer { try? FileManager.default.removeItem(at: file) }
		let store = Babel2PositionStore(fileURL: file)
		let full = Self.longArticleBody(paragraphs: 30, prefix: "Full")
		let setting = Babel2FeedReaderModeSetting(isAlwaysOn: { true }, setAlwaysOn: { _ in })
		let first = makeReader(body: "<p>Summary only.</p>", fullTextProvider: { _, _ in full }, feedReaderModeSetting: setting, positionStore: store)
		var window = hostInWindow(first)
		await waitUntil { first.isReaderModeOn }
		await waitForReaderRender(first)
		await waitForScrollableLength(first, atLeast: 2500)
		first.readerContentView.scrollView.setContentOffset(CGPoint(x: 0, y: 2000), animated: false)
		await first.capturePosition()
		XCTAssertNotNil(store.articlePosition(for: ArticleSnapshot.ID(accountID: "account", feedID: "feed", articleID: "reader-article")))
		window.isHidden = true

		let gate = Babel2TestGate()
		let second = makeReader(body: "<p>Summary only.</p>", fullTextProvider: { _, _ in
			await gate.wait()
			return full
		}, feedReaderModeSetting: setting, positionStore: store)
		window = hostInWindow(second)
		defer { window.isHidden = true }
		await waitForReaderRender(second)
		XCTAssertTrue(second.isRestoringPositionForTesting, "still waiting for the full text")
		gate.open()
		await waitUntil { second.isReaderModeOn }
		await waitUntil { abs(second.readerContentView.scrollView.contentOffset.y - 2000) < 40 }
		XCTAssertEqual(second.readerContentView.scrollView.contentOffset.y, 2000, accuracy: 40)
	}

	/// 文章列表：记下可视区最上面那一篇，重新打开回到同一篇、同样的位置；
	/// 上次离开之后新来的文章在上面时，底栏上方提示「↑ N 篇新文章」，点一下回到顶部并收起。
	func testListRemembersPositionAndOffersNewArticles() async throws {
		let file = FileManager.default.temporaryDirectory.appendingPathComponent("babel2-positions-\(UUID().uuidString).json")
		defer { try? FileManager.default.removeItem(at: file) }
		let store = Babel2PositionStore(fileURL: file)
		let feedID = FeedSnapshot.ID(accountID: "account", feedID: "feed")
		let now = Date()
		func article(_ index: Int) -> ArticleSnapshot {
			ArticleSnapshot(id: ArticleSnapshot.ID(accountID: "account", feedID: "feed", articleID: "a\(index)"),
				title: "Article \(index)", summary: "Summary of article \(index).", url: nil, feedID: feedID,
				publishedAt: now.addingTimeInterval(-Double(index) * 600))
		}
		let older = (0..<40).map(article)
		let first = Babel2FeedViewController(feed: makeFeed(id: feedID, title: "Feed"), scope: .all,
			environment: makeEnvironment(provider: FakeDataProvider(feeds: [feedID: older])), positionStore: store)
		var window = hostInWindow(first)
		await waitForRows(in: first.tableViewForTesting, count: 40)
		let table = first.tableViewForTesting
		table.scrollToRow(at: try XCTUnwrap(indexPathOfArticle("a20", in: table)), at: .top, animated: false)
		table.layoutIfNeeded()
		first.savePositionForTesting()
		let saved = try XCTUnwrap(store.listPosition(for: Babel2PositionStore.listKey(feed: feedID)))
		window.isHidden = true

		// 同样的文章再打开：回到同一篇、同样的位置
		let second = Babel2FeedViewController(feed: makeFeed(id: feedID, title: "Feed"), scope: .unread,
			environment: makeEnvironment(provider: FakeDataProvider(feeds: [feedID: older])), positionStore: store)
		window = hostInWindow(second)
		await waitForRows(in: second.tableViewForTesting, count: 40)
		let restored = try XCTUnwrap(second.currentPositionForTesting)
		XCTAssertEqual(restored.articleID, saved.articleID, "the same article is at the top (the three ranges share one position)")
		XCTAssertEqual(restored.offset, saved.offset, accuracy: 2)
		XCTAssertFalse(second.newArticlesPillForTesting.isShowing, "nothing new")
		// 从未读档离开（也记一次）：不影响下面回到全部档时数新文章
		second.savePositionForTesting()
		window.isHidden = true

		// 上面来了 3 篇新文章：停在原处，提示「↑ 3 篇新文章」；点一下回到顶部、提示收起
		let fresh = (1...3).map { index in
			ArticleSnapshot(id: ArticleSnapshot.ID(accountID: "account", feedID: "feed", articleID: "new\(index)"),
				title: "New \(index)", url: nil, feedID: feedID, publishedAt: now.addingTimeInterval(Double(index) * 60))
		}.reversed()
		let third = Babel2FeedViewController(feed: makeFeed(id: feedID, title: "Feed"), scope: .all,
			environment: makeEnvironment(provider: FakeDataProvider(feeds: [feedID: Array(fresh) + older])), positionStore: store)
		window = hostInWindow(third)
		defer { window.isHidden = true }
		await waitForRows(in: third.tableViewForTesting, count: 43)
		XCTAssertEqual(third.currentPositionForTesting?.articleID, saved.articleID)
		XCTAssertTrue(third.newArticlesPillForTesting.isShowing)
		XCTAssertEqual(third.newArticlesPillForTesting.count, 3)
		XCTAssertEqual(third.newArticlesPillForTesting.accessibilityLabel, String(format: localized(.newArticles), 3))
		third.tapNewArticlesPillForTesting()
		let top = -third.tableViewForTesting.adjustedContentInset.top
		await waitUntil { abs(third.tableViewForTesting.contentOffset.y - top) < 1 }
		XCTAssertFalse(third.newArticlesPillForTesting.isShowing)
	}

	/// 在「全部」档停在顶部、读了第一篇；换到「未读」档（那篇已读、不在了）：换成紧挨着的下一篇——
	/// 它就是第一篇，所以回到展开的顶部，大图和篇数照常显示（2026-09-27 真实数据 UI 自动测试发现的问题）。
	func testFallbackToFirstArticleKeepsTheExpandedTop() async throws {
		let file = FileManager.default.temporaryDirectory.appendingPathComponent("babel2-positions-\(UUID().uuidString).json")
		defer { try? FileManager.default.removeItem(at: file) }
		let store = Babel2PositionStore(fileURL: file)
		let feedID = FeedSnapshot.ID(accountID: "account", feedID: "feed")
		let now = Date()
		let all = (0..<12).map { index in
			ArticleSnapshot(id: ArticleSnapshot.ID(accountID: "account", feedID: "feed", articleID: "a\(index)"),
				title: "Article \(index)", url: nil, feedID: feedID, publishedAt: now.addingTimeInterval(-Double(index) * 600))
		}
		let first = Babel2FeedViewController(feed: makeFeed(id: feedID, title: "Feed"), scope: .all,
			environment: makeEnvironment(provider: FakeDataProvider(feeds: [feedID: all])), positionStore: store)
		var window = hostInWindow(first)
		await waitForRows(in: first.tableViewForTesting, count: 12)
		// 往下滑了一点（大图收起、第一篇还露着）再离开：不算「停在最上面」，走「按文章找回」这条路
		let firstTable = first.tableViewForTesting
		firstTable.setContentOffset(CGPoint(x: 0, y: -firstTable.adjustedContentInset.top + 100), animated: false)
		firstTable.layoutIfNeeded()
		first.savePositionForTesting()
		let saved = try XCTUnwrap(store.listPosition(for: Babel2PositionStore.listKey(feed: feedID)))
		XCTAssertEqual(saved.articleID, "a0")
		XCTAssertEqual(saved.atTop, false)
		window.isHidden = true

		let unread = Babel2FeedViewController(feed: makeFeed(id: feedID, title: "Feed"), scope: .unread,
			environment: makeEnvironment(provider: FakeDataProvider(feeds: [feedID: Array(all.dropFirst())])), positionStore: store)
		window = hostInWindow(unread)
		defer { window.isHidden = true }
		await waitForRows(in: unread.tableViewForTesting, count: 11)
		XCTAssertEqual(unread.tableViewForTesting.contentOffset.y, -unread.tableViewForTesting.adjustedContentInset.top, accuracy: 0.5)
		XCTAssertEqual(unread.heroProgressForTesting, 0, "the big header stays expanded")
	}

	/// 上次停在最上面（没往下滑过）：换一档再打开，即使那一篇不在第一位，也从最上面开始、大图展开
	///（2026-09-27 真实数据 UI 自动测试发现：以前会为了把那篇放回原位而收起大图、把前一篇压在窄栏下面）。
	func testListLeftAtTopReopensAtTop() async throws {
		let file = FileManager.default.temporaryDirectory.appendingPathComponent("babel2-positions-\(UUID().uuidString).json")
		defer { try? FileManager.default.removeItem(at: file) }
		let store = Babel2PositionStore(fileURL: file)
		let feedID = FeedSnapshot.ID(accountID: "account", feedID: "feed")
		let now = Date()
		let all = (0..<12).map { index in
			ArticleSnapshot(id: ArticleSnapshot.ID(accountID: "account", feedID: "feed", articleID: "a\(index)"),
				title: "Article \(index)", url: nil, feedID: feedID, publishedAt: now.addingTimeInterval(-Double(index) * 600))
		}
		// 未读档：第一篇已读、不在；停在最上面离开（最上面那篇是 a1）
		let unread = Babel2FeedViewController(feed: makeFeed(id: feedID, title: "Feed"), scope: .unread,
			environment: makeEnvironment(provider: FakeDataProvider(feeds: [feedID: Array(all.dropFirst())])), positionStore: store)
		var window = hostInWindow(unread)
		await waitForRows(in: unread.tableViewForTesting, count: 11)
		unread.savePositionForTesting()
		let saved = try XCTUnwrap(store.listPosition(for: Babel2PositionStore.listKey(feed: feedID)))
		XCTAssertEqual(saved.articleID, "a1")
		XCTAssertEqual(saved.atTop, true)
		window.isHidden = true

		// 全部档：a1 排在第二位，照样从最上面开始
		let allList = Babel2FeedViewController(feed: makeFeed(id: feedID, title: "Feed"), scope: .all,
			environment: makeEnvironment(provider: FakeDataProvider(feeds: [feedID: all])), positionStore: store)
		window = hostInWindow(allList)
		defer { window.isHidden = true }
		await waitForRows(in: allList.tableViewForTesting, count: 12)
		XCTAssertEqual(allList.tableViewForTesting.contentOffset.y, -allList.tableViewForTesting.adjustedContentInset.top, accuracy: 0.5)
		XCTAssertEqual(allList.heroProgressForTesting, 0)
		XCTAssertFalse(allList.newArticlesPillForTesting.isShowing)
	}

	/// 「新文章」只跟同一档比：星标档里滑到中间离开，换到全部档打开同一个源——回到同一篇，
	/// 但上面那些没加星标的（本来就有的）文章不算新文章，不弹提示；回到星标档、真有新加星标的才弹。
	func testNewArticlesHintOnlyComparesTheSameScope() async throws {
		let file = FileManager.default.temporaryDirectory.appendingPathComponent("babel2-positions-\(UUID().uuidString).json")
		defer { try? FileManager.default.removeItem(at: file) }
		let store = Babel2PositionStore(fileURL: file)
		let feedID = FeedSnapshot.ID(accountID: "account", feedID: "feed")
		let now = Date()
		func article(_ id: String, minutesAgo: Double) -> ArticleSnapshot {
			ArticleSnapshot(id: ArticleSnapshot.ID(accountID: "account", feedID: "feed", articleID: id), title: id,
				summary: "Summary of \(id).", url: nil, feedID: feedID, publishedAt: now.addingTimeInterval(-minutesAgo * 60))
		}
		// 星标档：40 篇加了星标的旧文章（一天前起）；全部档：上面还有 10 篇较新的、没加星标的
		let starred = (0..<40).map { article("s\($0)", minutesAgo: 1440 + Double($0) * 10) }
		let recent = (0..<10).map { article("r\($0)", minutesAgo: Double($0) * 10) }
		let starredList = Babel2FeedViewController(feed: makeFeed(id: feedID, title: "Feed"), scope: .starred,
			environment: makeEnvironment(provider: FakeDataProvider(feeds: [feedID: starred])), positionStore: store)
		var window = hostInWindow(starredList)
		await waitForRows(in: starredList.tableViewForTesting, count: 40)
		starredList.tableViewForTesting.scrollToRow(at: try XCTUnwrap(indexPathOfArticle("s20", in: starredList.tableViewForTesting)), at: .top, animated: false)
		starredList.tableViewForTesting.layoutIfNeeded()
		starredList.savePositionForTesting()
		let saved = try XCTUnwrap(store.listPosition(for: Babel2PositionStore.listKey(feed: feedID)))
		XCTAssertEqual(saved.seenByScope?.keys.sorted(), [Babel2FeedScope.starred.rawValue])
		window.isHidden = true

		let allList = Babel2FeedViewController(feed: makeFeed(id: feedID, title: "Feed"), scope: .all,
			environment: makeEnvironment(provider: FakeDataProvider(feeds: [feedID: recent + starred])), positionStore: store)
		window = hostInWindow(allList)
		await waitForRows(in: allList.tableViewForTesting, count: 50)
		XCTAssertEqual(allList.currentPositionForTesting?.articleID, saved.articleID, "the three ranges share one position")
		XCTAssertFalse(allList.newArticlesPillForTesting.isShowing, "older unstarred articles are not new")
		// 从全部档离开：全部档的记下来，星标档上次记下的留着
		allList.savePositionForTesting()
		XCTAssertEqual(store.listPosition(for: Babel2PositionStore.listKey(feed: feedID))?.seenByScope?.keys.sorted(),
			[Babel2FeedScope.all.rawValue, Babel2FeedScope.starred.rawValue].sorted())
		window.isHidden = true

		// 回到星标档：新加了 2 篇星标（比离开时星标档里最新的一篇新）→ 提示「↑ 2 篇新文章」
		let backToStarred = Babel2FeedViewController(feed: makeFeed(id: feedID, title: "Feed"), scope: .starred,
			environment: makeEnvironment(provider: FakeDataProvider(feeds: [feedID: Array(recent.prefix(2)) + starred])), positionStore: store)
		window = hostInWindow(backToStarred)
		defer { window.isHidden = true }
		await waitForRows(in: backToStarred.tableViewForTesting, count: 42)
		XCTAssertEqual(backToStarred.currentPositionForTesting?.articleID, saved.articleID)
		XCTAssertTrue(backToStarred.newArticlesPillForTesting.isShowing)
		XCTAssertEqual(backToStarred.newArticlesPillForTesting.count, 2)
	}

	/// 找回位置的规则：那篇还在就是它；不在了按时间找紧挨着的下一篇（新的在前 → 更早的第一篇）；
	/// 一篇都没有更早的就停在最后。今日未读和全部未读（今天 / 全部文章）共用一个位置，外文源、星标各一个。
	func testListPositionAnchorRulesAndSharedKeys() {
		let feedID = FeedSnapshot.ID(accountID: "account", feedID: "feed")
		let now = Date()
		func article(_ id: String, minutesAgo: Double) -> ArticleSnapshot {
			ArticleSnapshot(id: ArticleSnapshot.ID(accountID: "account", feedID: "feed", articleID: id), title: id, url: nil,
				feedID: feedID, publishedAt: now.addingTimeInterval(-minutesAgo * 60))
		}
		let list = [article("a", minutesAgo: 0), article("b", minutesAgo: 10), article("c", minutesAgo: 20), article("d", minutesAgo: 30)]
		func stored(_ id: String, minutesAgo: Double) -> Babel2PositionStore.ListPosition {
			.init(accountID: "account", feedID: "feed", articleID: id, publishedAt: now.addingTimeInterval(-minutesAgo * 60),
				offset: -12, savedAt: now)
		}
		let exact = Babel2FeedViewController.restoreAnchor(for: stored("c", minutesAgo: 20), in: list)
		XCTAssertEqual(exact?.index, 2)
		XCTAssertEqual(exact?.exact, true)
		let gone = Babel2FeedViewController.restoreAnchor(for: stored("gone", minutesAgo: 15), in: list)
		XCTAssertEqual(gone?.index, 2, "read and filtered out: the next older one")
		XCTAssertEqual(gone?.exact, false)
		let old = Babel2FeedViewController.restoreAnchor(for: stored("old", minutesAgo: 90), in: list)
		XCTAssertEqual(old?.index, 3, "everything here is newer: stop at the end")
		XCTAssertEqual(Babel2FeedViewController.newArticles(in: list, since: now.addingTimeInterval(-15 * 60)).map(\.id.articleID), ["a", "b"])
		XCTAssertEqual(Babel2PositionStore.listKey(smart: .today), Babel2PositionStore.listKey(smart: .all))
		XCTAssertNotEqual(Babel2PositionStore.listKey(smart: .today), Babel2PositionStore.listKey(smart: .foreign))
		XCTAssertNotEqual(Babel2PositionStore.listKey(smart: .starred), Babel2PositionStore.listKey(smart: .foreign))
	}

	/// 今日未读里看到哪，打开全部未读就接着那一篇（反过来也一样）。
	func testTodayAndAllUnreadShareTheirPosition() async throws {
		let file = FileManager.default.temporaryDirectory.appendingPathComponent("babel2-positions-\(UUID().uuidString).json")
		defer { try? FileManager.default.removeItem(at: file) }
		let store = Babel2PositionStore(fileURL: file)
		let now = Date()
		func article(_ index: Int) -> ArticleSnapshot {
			let feedID = FeedSnapshot.ID(accountID: "account", feedID: "f\(index % 3)")
			return ArticleSnapshot(id: ArticleSnapshot.ID(accountID: "account", feedID: feedID.feedID, articleID: "s\(index)"),
				title: "Story \(index)", summary: "Summary \(index).", url: nil, feedID: feedID, publishedAt: now.addingTimeInterval(-Double(index) * 900))
		}
		let today = (0..<30).map(article)
		let all = (0..<60).map(article)
		let feeds = (0..<3).map { makeFeed(id: FeedSnapshot.ID(accountID: "account", feedID: "f\($0)"), title: "Feed \($0)") }
		let provider = FakeDataProvider()
		await provider.setSmartArticles(SmartFeedArticlesSnapshot(articles: today, feeds: feeds), for: .today)
		await provider.setSmartArticles(SmartFeedArticlesSnapshot(articles: all, feeds: feeds), for: .all)

		let todayList = Babel2FeedViewController(smartFeed: .today, scope: .unread, environment: makeEnvironment(provider: provider), positionStore: store)
		var window = hostInWindow(todayList)
		await waitForRows(in: todayList.tableViewForTesting, count: 30)
		todayList.tableViewForTesting.scrollToRow(at: try XCTUnwrap(indexPathOfArticle("s18", in: todayList.tableViewForTesting)), at: .top, animated: false)
		todayList.tableViewForTesting.layoutIfNeeded()
		todayList.savePositionForTesting()
		let saved = try XCTUnwrap(todayList.currentPositionForTesting)
		window.isHidden = true

		let allList = Babel2FeedViewController(smartFeed: .all, scope: .unread, environment: makeEnvironment(provider: provider), positionStore: store)
		window = hostInWindow(allList)
		defer { window.isHidden = true }
		await waitForRows(in: allList.tableViewForTesting, count: 60)
		XCTAssertEqual(allList.currentPositionForTesting?.articleID, saved.articleID, "opens where Today's Unread was left")
	}

	// MARK: - 整页左滑进原文、点标题进原文（ADR-048）

	/// 整页往左划进原文的开始条件：明显往左横滑才开始；往右 / 竖着 / 进行中 / 在还能往左滚的横向滚动区里都不开始。
	func testFullSurfaceSwipeToBrowserRules() {
		XCTAssertTrue(Babel2ReaderBrowserMotion.shouldBegin(velocity: CGPoint(x: -600, y: 100), isBusy: false, startsInHorizontalScroller: false))
		XCTAssertFalse(Babel2ReaderBrowserMotion.shouldBegin(velocity: CGPoint(x: 600, y: 0), isBusy: false, startsInHorizontalScroller: false), "rightward = back")
		XCTAssertFalse(Babel2ReaderBrowserMotion.shouldBegin(velocity: CGPoint(x: -300, y: 400), isBusy: false, startsInHorizontalScroller: false), "mostly vertical = scroll")
		XCTAssertFalse(Babel2ReaderBrowserMotion.shouldBegin(velocity: CGPoint(x: -600, y: 0), isBusy: true, startsInHorizontalScroller: false))
		XCTAssertFalse(Babel2ReaderBrowserMotion.shouldBegin(velocity: CGPoint(x: -600, y: 0), isBusy: false, startsInHorizontalScroller: true))

		let root = UIView(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
		let wide = UIScrollView(frame: CGRect(x: 0, y: 0, width: 300, height: 100))
		wide.contentSize = CGSize(width: 900, height: 100)
		let cell = UIView(frame: CGRect(x: 0, y: 0, width: 50, height: 50))
		wide.addSubview(cell)
		root.addSubview(wide)
		XCTAssertTrue(Babel2ReaderBrowserMotion.startsInHorizontalScroller(cell, stopAt: root), "a wide table scrolls first")
		wide.contentOffset = CGPoint(x: 600, y: 0)
		XCTAssertFalse(Babel2ReaderBrowserMotion.startsInHorizontalScroller(cell, stopAt: root), "scrolled to its end: the swipe opens the original")
		let tall = UIScrollView(frame: CGRect(x: 0, y: 200, width: 400, height: 400))
		tall.contentSize = CGSize(width: 400, height: 3000)
		root.addSubview(tall)
		XCTAssertFalse(Babel2ReaderBrowserMotion.startsInHorizontalScroller(tall, stopAt: root), "the article body only scrolls vertically")
	}

	/// 点大标题：和往左划一样，浏览器整页滑进来、成为当前页；标题对读屏说明「打开原文」。
	func testTappingTitleOpensOriginalLikeTheSwipe() async throws {
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
		let title = try XCTUnwrap(descendant(of: reader.view, matching: UILabel.self) { $0.accessibilityIdentifier == "babel2.article.title" })
		XCTAssertTrue(title.isUserInteractionEnabled)
		XCTAssertTrue(title.gestureRecognizers?.contains { $0 is UITapGestureRecognizer } ?? false)
		XCTAssertTrue(title.accessibilityTraits.contains(.link))
		XCTAssertEqual(title.accessibilityHint, localized(.openOriginal))

		reader.tapTitleForTesting()
		let browser = try XCTUnwrap(made.last)
		XCTAssertTrue(browser.didPrepare, "the browser is prepared first, like the swipe")
		XCTAssertNotNil(browser.view.superview, "both pages slide together")
		try XCTUnwrap(reader.browserMotionForTesting).finishSettleImmediatelyForTesting()
		XCTAssertTrue(navigation.topViewController === browser)
		XCTAssertEqual(browser.url, URL(string: "https://example.com/post"))
		XCTAssertEqual(reader.view.transform, .identity)
	}

	// MARK: - 不输出思考过程（ADR-050）

	/// 回复开头的「思考」段（<think>…</think>）去掉，只留正式回复；思考还没写完时什么也不显示；
	/// 不在开头的、或没有思考段的回复原样不动。
	func testThinkingAtTheStartOfAReplyIsStripped() {
		XCTAssertEqual(OpenAICompatibleTranslator.strippingThinking("<think>Hmm [1]</think><p>译文</p>"), "<p>译文</p>")
		XCTAssertEqual(OpenAICompatibleTranslator.strippingThinking("\n  <thinking>plan</thinking>\n<p>译文</p>"), "\n<p>译文</p>")
		XCTAssertEqual(OpenAICompatibleTranslator.strippingThinking("<think>still thinking"), "", "nothing to show until the answer starts")
		XCTAssertEqual(OpenAICompatibleTranslator.strippingThinking("<p>译文</p>"), "<p>译文</p>")
		XCTAssertEqual(OpenAICompatibleTranslator.strippingThinking("<p>a <think>b</think></p>"), "<p>a <think>b</think></p>", "only a leading block is thinking")
		XCTAssertEqual(OpenAICompatibleTranslator.cleanUp("<think>x</think>\n```html\n<p>译文</p>\n```", original: "<p>Text</p>"), "<p>译文</p>")
	}

	/// 真实流程：模型把思考写在回复开头时，正文照样翻完、页面上没有一个思考的字（流式上屏与最终译文都没有）。
	func testThinkingWrittenIntoTheReplyNeverReachesThePage() async throws {
		let restore = useFakeTranslationServer(.thinkingFirst)
		defer { restore() }
		let viewController = makeReader(body: Self.longArticleBody(paragraphs: 8), hostArticle: NSObject())
		let window = hostInWindow(viewController)
		defer { window.isHidden = true }
		await waitForReaderRender(viewController)
		await waitUntil { viewController.isTranslationReadyForTesting }
		viewController.toolbarView.translationToggle.sendActions(for: .touchUpInside)
		await waitForTranslation(viewController, toReach: .translated)
		let text = await viewController.readerContentView.articleTextForTesting() ?? ""
		XCTAssertFalse(text.contains("think"), "no thinking on the page")
		XCTAssertGreaterThan(Self.cjkRatio(text), 0.9)
	}

	/// 标题翻译：回复开头的思考里有方括号，也不会把标题数组抠错。
	func testTitleTranslationIgnoresThinkingBeforeTheArray() async throws {
		URLProtocol.registerClass(CapturingTranslationProtocol.self)
		defer {
			URLProtocol.unregisterClass(CapturingTranslationProtocol.self)
			CapturingTranslationProtocol.replyContent = "[\"一个标题\"]"
		}
		CapturingTranslationProtocol.replyContent = "<think>The user wants [one] title as [JSON].</think>[\"一个标题\"]"
		let translated = try await NNWTitleBatchTranslator.translate(
			["A headline"],
			config: TranslationConfig(baseURL: "https://api.example-provider.com/v1", apiKey: "test"),
			model: "some/model"
		)
		XCTAssertEqual(translated, ["一个标题"])
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

	/// ADR-043：取全文时底栏阅读模式图标本身在动（不再在标题下写「正在获取全文…」）；失败时图标轻晃、底栏上方小胶囊提示。
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
		// 获取中：图标在动，标题下不再有状态字，正文照常
		XCTAssertEqual(viewController.toolbarView.readingModeButton.accessibilityValue, "loading")
		XCTAssertNil(viewController.statusTextForTesting)
		await waitUntil { !viewController.isFetchingFullTextForTesting }
		XCTAssertEqual(viewController.toastTextForTesting, Babel2Localization.text(.unableToFetchFullText))
		XCTAssertEqual(viewController.toolbarView.readingModeButton.accessibilityValue, "off")
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

	// MARK: - 重开 App 回到上次的页面（2026-09-27，Babel2LastPlace）

	/// 从导航栈读「现在在哪」：列表 + 上面打开着的文章；停在浏览器里仍算那篇文章；独立网页不算文章；只有首页 → 不记。
	func testLastPlaceCapturesListAndArticleFromTheStack() {
		let feedID = FeedSnapshot.ID(accountID: "account", feedID: "feed")
		let environment = makeEnvironment(provider: FakeDataProvider())
		let root = UIViewController()
		let list = Babel2FeedViewController(feed: makeFeed(id: feedID, title: "Feed"), scope: .all, environment: environment)
		let reader = makeReader(body: "<p>Body</p>")
		let browser = UIViewController()
		let now = Date(timeIntervalSince1970: 1_800_000_000)

		XCTAssertNil(Babel2LastPlace.capture(from: [root], now: now), "home only → start from home")
		let listOnly = Babel2LastPlace.capture(from: [root, list], now: now)
		XCTAssertEqual(listOnly?.feedSnapshotID, feedID)
		XCTAssertEqual(listOnly?.feedScope, .all)
		XCTAssertNil(listOnly?.article)
		let inBrowser = Babel2LastPlace.capture(from: [root, list, reader, browser], now: now)
		XCTAssertEqual(inBrowser?.articleSnapshotID, ArticleSnapshot.ID(accountID: "account", feedID: "feed", articleID: "reader-article"),
			"left from the built-in browser → back to the article")
		XCTAssertEqual(inBrowser?.savedAt, now)

		let smart = Babel2FeedViewController(feed: makeFeed(id: feedID, title: "Today"), scope: .unread, environment: environment, smartFeed: .today)
		let smartPlace = Babel2LastPlace.capture(from: [root, smart], now: now)
		XCTAssertEqual(smartPlace?.smartFeedKind, .today)
		XCTAssertNil(smartPlace?.feedSnapshotID)

		// 24 小时以内才用
		XCTAssertTrue(listOnly!.isFresh(now: now.addingTimeInterval(23 * 3600)))
		XCTAssertFalse(listOnly!.isFresh(now: now.addingTimeInterval(25 * 3600)))
	}

	/// 冷启动：记录不超过 24 小时 → 首页 → 列表 → 文章直接搭好（文章按编号取，不依赖它还在列表里）；
	/// 超过 24 小时、订阅源已经不在 → 停在首页；退到后台时记下当前位置。
	func testColdStartResumesLastPlaceWithinOneDay() async throws {
		let feedID = FeedSnapshot.ID(accountID: "account", feedID: "feed")
		let feed = makeFeed(id: feedID, title: "Feed")
		let first = makeArticle(accountID: "account", feedID: "feed", articleID: "a1", title: "First", body: "<p>First</p>", url: nil)
		let second = makeArticle(accountID: "account", feedID: "feed", articleID: "a2", title: "Second", body: "<p>Second</p>", url: nil)
		let provider = FakeDataProvider(feeds: [feedID: [first, second]],
			librarySnapshots: [.all: LibrarySnapshot(feeds: [feed])])
		let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("babel2-lastplace-\(UUID().uuidString).json")
		defer { try? FileManager.default.removeItem(at: fileURL) }
		let store = Babel2LastPlaceStore(fileURL: fileURL)

		func launch() -> (Babel2NavigationController, UIWindow) {
			let navigation = Babel2SceneComposition.makeRoot(environment: makeEnvironment(provider: provider), lastPlace: store)
			let window = hostInWindow(navigation)
			return (navigation, window)
		}

		// 1 小时前停在「全部」档的这个源、看着第二篇
		store.save(Babel2LastPlace(accountID: "account", feedID: "feed", scope: "all",
			article: .init(accountID: "account", feedID: "feed", articleID: "a2"), savedAt: Date().addingTimeInterval(-3600)))
		var (navigation, window) = launch()
		XCTAssertNotNil(descendant(of: navigation.view, matching: Babel2ResumeCover.self), "paper cover hides the home screen while resuming")
		await waitUntil { navigation.viewControllers.count == 3 }
		XCTAssertEqual(navigation.viewControllers.count, 3)
		let list = try XCTUnwrap(navigation.viewControllers[1] as? Babel2FeedViewController)
		XCTAssertEqual(list.placeFeedID, feedID)
		XCTAssertEqual(list.scope, .all)
		let reader = try XCTUnwrap(navigation.viewControllers[2] as? Babel2ArticleViewController)
		XCTAssertEqual(reader.placeArticleID?.articleID, "a2")
		let root = try XCTUnwrap(navigation.viewControllers.first as? Babel2RootViewController)
		XCTAssertEqual(root.selectedScope, .all, "home follows the resumed scope")
		await waitUntil { descendant(of: navigation.view, matching: Babel2ResumeCover.self) == nil }
		XCTAssertNil(descendant(of: navigation.view, matching: Babel2ResumeCover.self), "cover goes away")

		// 退到后台：记下当前位置（返回列表后 → 只记列表）
		_ = navigation.popBabel2(animated: false)
		NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
		XCTAssertEqual(store.load()?.feedSnapshotID, feedID)
		XCTAssertNil(store.load()?.article)
		_ = navigation.popBabel2(animated: false)
		NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
		XCTAssertNil(store.load(), "back on home → next launch starts from home")
		navigation.tearDown()
		window.isHidden = true

		// 超过 24 小时：从首页开始
		store.save(Babel2LastPlace(accountID: "account", feedID: "feed", scope: "all", savedAt: Date().addingTimeInterval(-25 * 3600)))
		(navigation, window) = launch()
		XCTAssertNil(descendant(of: navigation.view, matching: Babel2ResumeCover.self))
		try await Task.sleep(for: .milliseconds(300))
		XCTAssertEqual(navigation.viewControllers.count, 1)
		navigation.tearDown()
		window.isHidden = true

		// 订阅源已经不在了（退订）：停在首页，底板照样揭开
		store.save(Babel2LastPlace(accountID: "account", feedID: "gone", scope: "all", savedAt: Date()))
		(navigation, window) = launch()
		await waitUntil { descendant(of: navigation.view, matching: Babel2ResumeCover.self) == nil }
		XCTAssertEqual(navigation.viewControllers.count, 1)
		navigation.tearDown()
		window.isHidden = true
	}

	/// 阅读模式全文缓存（2026-09-27）：第一次抽到就存；再打开（上次开着阅读模式）直接排存着的全文——
	/// 不再抓网页、不先排摘要；关掉再开也直接用；网址变了不用；抓失败不存；最多存 300 篇。
	func testReaderModeReusesCachedFullTextInsteadOfFetchingAgain() async throws {
		let directory = FileManager.default.temporaryDirectory.appendingPathComponent("babel2-fulltext-\(UUID().uuidString)")
		defer { try? FileManager.default.removeItem(at: directory) }
		let cache = Babel2FullTextCache(directory: directory)
		var fetches = 0
		let provider: @MainActor (URL, UIView) async throws -> String = { _, _ in
			fetches += 1
			return "<p>Cached full text from the web page.</p><p>Second paragraph.</p>"
		}
		// 第一次：手动开阅读模式 → 抓一次、存下
		let first = makeReader(body: "<p>Summary only.</p>", fullTextProvider: provider, fullTextCache: cache)
		var window = hostInWindow(first)
		await waitForReaderRender(first)
		first.toggleReaderMode()
		await waitUntil { first.isReaderModeOn }
		await waitUntil { first.lastRenderResult?.textLength ?? 0 > 30 }
		XCTAssertEqual(fetches, 1)
		window.isHidden = true

		// 再打开（这篇记着阅读模式）：一打开就是阅读模式，第一次排版就是全文，不再抓
		let second = makeReader(body: "<p>Summary only.</p>", fullTextProvider: provider, fullTextCache: cache)
		window = hostInWindow(second)
		defer { window.isHidden = true }
		XCTAssertTrue(second.isReaderModeOn, "reader mode is on right away")
		XCTAssertFalse(second.isFetchingFullTextForTesting)
		XCTAssertEqual(second.toolbarView.readingModeButton.accessibilityValue, "on")
		await waitForReaderRender(second)
		let text = await second.readerContentView.articleTextForTesting()
		XCTAssertTrue(text?.hasPrefix("Cached full text") == true, "first render is the cached full text, got \(text ?? "nil")")
		XCTAssertEqual(fetches, 1, "no second fetch")

		// 关掉再开：直接用存的
		second.toggleReaderMode()
		await waitUntil { second.lastRenderResult?.textLength ?? 99 < 30 }
		second.toggleReaderMode()
		XCTAssertTrue(second.isReaderModeOn)
		await waitUntil { second.lastRenderResult?.textLength ?? 0 > 30 }
		XCTAssertEqual(fetches, 1)

		// 网址变了 → 当没存过
		let id = ArticleSnapshot.ID(accountID: "account", feedID: "feed", articleID: "reader-article")
		XCTAssertNotNil(cache.html(for: id, url: URL(string: "https://example.com/post")!))
		XCTAssertNil(cache.html(for: id, url: URL(string: "https://example.com/moved")!))

		// 抓失败不存
		struct Blocked: Error {}
		let failingDirectory = directory.appendingPathComponent("failing")
		let failingCache = Babel2FullTextCache(directory: failingDirectory)
		let third = makeReader(body: "<p>Summary only.</p>", fullTextProvider: { _, _ in throw Blocked() }, fullTextCache: failingCache)
		let thirdWindow = hostInWindow(third)
		defer { thirdWindow.isHidden = true }
		await waitForReaderRender(third)
		third.toggleReaderMode()
		await waitUntil { !third.isFetchingFullTextForTesting }
		XCTAssertNil(failingCache.html(for: id, url: URL(string: "https://example.com/post")!))

		// 上限：多存的删最久没用过的
		for index in 0..<(Babel2FullTextCache.maxEntries + 5) {
			cache.store("<p>\(index)</p>", for: ArticleSnapshot.ID(accountID: "a", feedID: "f", articleID: "\(index)"),
				url: URL(string: "https://example.com/\(index)")!)
		}
		let files = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasSuffix(".json") }
		XCTAssertEqual(files.count, Babel2FullTextCache.maxEntries)
		XCTAssertNotNil(cache.html(for: ArticleSnapshot.ID(accountID: "a", feedID: "f", articleID: "\(Babel2FullTextCache.maxEntries + 4)"),
			url: URL(string: "https://example.com/\(Babel2FullTextCache.maxEntries + 4)")!), "newest entry is kept")
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

	/// 翻译图标（ADR-043，取代 Figma 的「原 / 译」文字开关）：引擎六种状态 → 图标三态；失败轻晃后回平时。
	func testTranslateIconMapsEngineStatesToThreePhases() {
		let toolbar = Babel2ReaderToolbarView()
		toolbar.setTranslationAvailable(true)
		let expected: [(TranslationButtonState, Babel2StatusIconControl.Phase, String, String)] = [
			(.original, .idle, "original", Babel2Localization.text(.translate)),
			(.cachedAvailable, .idle, "cached", Babel2Localization.text(.translate)),
			(.partialCacheAvailable, .idle, "partial", Babel2Localization.text(.translate)),
			(.working, .working, "working", Babel2Localization.text(.cancelTranslation)),
			(.translated, .on, "translated", Babel2Localization.text(.showOriginal)),
			(.failed, .idle, "failed", Babel2Localization.text(.translate))
		]
		let toggle = toolbar.translationToggle
		// 1.x 的角标拿回来（2026-09-27 用户）：完整缓存 = 实心小圆点，翻到一半 = 空心小圆点，其它没有角标
		let badges: [TranslationButtonState: Babel2TranslateIconButton.Badge] = [.cachedAvailable: .solidDot, .partialCacheAvailable: .hollowDot]
		for (state, phase, value, label) in expected {
			toolbar.setTranslationState(state)
			XCTAssertEqual(toggle.badge, badges[state] ?? .none, "\(value) badge")
			XCTAssertNotNil(toggle.glyphImageForTesting, "the translate glyph (文A) is shown")
			XCTAssertEqual(toggle.phase, phase)
			XCTAssertEqual(toggle.accessibilityValue, value)
			XCTAssertEqual(toggle.accessibilityLabel, label)
			XCTAssertTrue(toggle.isEnabled, "\(value) stays tappable (working = cancel)")
			XCTAssertEqual(toggle.chip.alpha, phase == .on ? 1 : 0, "filled chip only when translated")
			XCTAssertEqual(toggle.isAnimatingWorkForTesting, phase == .working, "the glyph itself animates while working")
		}
		// 阅读模式图标：取全文时在动，开着 = 墨色方块底
		toolbar.setReaderModeLoading()
		XCTAssertEqual(toolbar.readingModeButton.accessibilityValue, "loading")
		XCTAssertTrue(toolbar.readingModeButton.isAnimatingWorkForTesting)
		toolbar.setReaderMode(true, available: true)
		XCTAssertEqual(toolbar.readingModeButton.phase, .on)
		XCTAssertFalse(toolbar.readingModeButton.isAnimatingWorkForTesting)
		XCTAssertEqual(toolbar.readingModeButton.chip.alpha, 1)
		toolbar.setReaderMode(false, available: false)
		XCTAssertFalse(toolbar.readingModeButton.isEnabled)
		XCTAssertEqual(toolbar.readingModeButton.chip.alpha, 0)
		// 阅读模式图标只剩横线（没有纸页外框）：四道，前三道一样长，最后一道略短（2026-09-27 用户）
		let lengths = Babel2ReaderModeIconButton.lineLengthsForTesting
		XCTAssertEqual(lengths.count, 4)
		XCTAssertEqual(Set(lengths.dropLast()).count, 1)
		XCTAssertLessThan(lengths.last ?? 0, lengths[0])
		// 统一图标集（ADR-065，用户审过）最后一道是前三道的 58%——比原来短一些，但仍是「一段文字的最后一行」
		XCTAssertGreaterThan(lengths.last ?? 0, lengths[0] * 0.5, "shorter, but still reads as the last line of a paragraph")
		XCTAssertEqual(toolbar.readingModeButton.glyph.layer.sublayers?.count, 4, "no page outline, just the lines")
	}

	// MARK: - 图片查看器（ADR-040，2026-09-27 用户反馈第 3 条）

	/// 点正文里的图：弹出卡片式查看器，不再顺着图片外面的链接进浏览器。
	func testTappingImageOpensCardViewerInsteadOfFollowingItsLink() async throws {
		var opened = [URL]()
		let png = pngDataURI(size: CGSize(width: 400, height: 300))
		let viewController = makeReader(
			body: "<p>Intro paragraph with some words.</p><a href=\"https://example.com/photo.jpg\"><img src=\"\(png)\" alt=\"A photo\"></a><p>After the image.</p>",
			makeBrowser: { url in
				opened.append(url)
				return StubBrowser(url: url)
			}
		)
		let window = hostInWindow(viewController)
		defer { window.isHidden = true }
		await waitForReaderRender(viewController)
		await viewController.readerContentView.tapImageForTesting(at: 0)
		await waitUntil { viewController.presentedViewController is Babel2ImageViewerViewController }
		XCTAssertTrue(opened.isEmpty, "the link around the image is not followed")
		let viewer = try XCTUnwrap(viewController.presentedViewController as? Babel2ImageViewerViewController)
		viewer.view.layoutIfNeeded()
		XCTAssertFalse(viewer.hasOpenLinkButton, "a link to the image file itself is not offered")
		XCTAssertEqual(viewer.imageView.accessibilityLabel, "A photo")
		XCTAssertEqual(viewer.imageView.layer.cornerRadius, 0, "square corners (ADR-051)")
		let size = viewer.imageView.bounds.size
		XCTAssertEqual(size.width / size.height, 4.0 / 3.0, accuracy: 0.03, "keeps the image's shape")
		XCTAssertEqual(size.width, window.bounds.width, accuracy: 0.5, "a landscape image runs edge to edge")

		viewer.dismissViewer()
		await waitUntil { viewController.presentedViewController == nil }
	}

	/// 查看器规则：什么时候给「打开链接」；卡片位置；小图最多放大 3 倍；拖多远 / 甩多快算关闭；双击放大。
	func testImageViewerRules() async throws {
		let image = URL(string: "https://example.com/a.jpg")
		XCTAssertEqual(Babel2ImageViewerViewController.meaningfulLink(URL(string: "https://example.com/post"), imageURL: image), URL(string: "https://example.com/post"))
		XCTAssertNil(Babel2ImageViewerViewController.meaningfulLink(URL(string: "https://cdn.example.com/big.PNG"), imageURL: image))
		XCTAssertNil(Babel2ImageViewerViewController.meaningfulLink(image, imageURL: image))
		XCTAssertNil(Babel2ImageViewerViewController.meaningfulLink(URL(string: "mailto:a@b.c"), imageURL: image))

		let bounds = CGRect(x: 0, y: 0, width: 402, height: 874)
		let safe = UIEdgeInsets(top: 62, left: 0, bottom: 34, right: 0)
		// 横图贴满屏幕两边（2026-09-27 用户验收时要求，ADR-051），竖直方向在安全区里居中
		let wide = Babel2ImageViewerViewController.fittedFrame(imageSize: CGSize(width: 400, height: 300), in: bounds, safeArea: safe)
		XCTAssertEqual(wide.minX, 0, accuracy: 0.5)
		XCTAssertEqual(wide.width, 402, accuracy: 0.5, "landscape images run edge to edge")
		XCTAssertEqual(wide.midY, (62 + 16 + 874 - 34 - 16) / 2, accuracy: 0.5, "centered in the safe area")
		let smallWide = Babel2ImageViewerViewController.fittedFrame(imageSize: CGSize(width: 120, height: 80), in: bounds, safeArea: safe)
		XCTAssertEqual(smallWide.width, 402, accuracy: 0.5, "even small landscape images fill the width")
		// 竖图 / 方图：左右留 16pt；小图最多放大 3 倍
		let tall = Babel2ImageViewerViewController.fittedFrame(imageSize: CGSize(width: 300, height: 600), in: bounds, safeArea: safe)
		XCTAssertEqual(tall.width, 370, accuracy: 0.5)
		XCTAssertEqual(tall.midX, 201, accuracy: 0.5)
		let tiny = Babel2ImageViewerViewController.fittedFrame(imageSize: CGSize(width: 40, height: 40), in: bounds, safeArea: safe)
		XCTAssertEqual(tiny.width, 120, accuracy: 0.5, "small portrait / square images are enlarged at most 3x")
		// 横着拿手机：整宽放不下高度时按高度缩
		let sideways = Babel2ImageViewerViewController.fittedFrame(imageSize: CGSize(width: 1600, height: 900),
			in: CGRect(x: 0, y: 0, width: 874, height: 402), safeArea: UIEdgeInsets(top: 0, left: 62, bottom: 21, right: 62))
		XCTAssertEqual(sideways.height, 402 - 21 - 32, accuracy: 0.5)
		XCTAssertLessThan(sideways.width, 874)

		XCTAssertFalse(Babel2ImageViewerViewController.shouldDismiss(dragDistance: 60, velocity: 200))
		XCTAssertTrue(Babel2ImageViewerViewController.shouldDismiss(dragDistance: 130, velocity: 0))
		XCTAssertTrue(Babel2ImageViewerViewController.shouldDismiss(dragDistance: -20, velocity: -1200))

		let format = UIGraphicsImageRendererFormat()
		format.scale = 1
		let placeholder = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 300), format: format).image { context in
			UIColor.gray.setFill()
			context.fill(CGRect(x: 0, y: 0, width: 400, height: 300))
		}
		let viewer = Babel2ImageViewerViewController(
			source: .init(placeholder: placeholder, imageURL: nil, linkURL: URL(string: "https://example.com/story"), originFrame: nil, altText: ""),
			loadImage: nil
		)
		let window = hostInWindow(viewer)
		defer { window.isHidden = true }
		viewer.view.layoutIfNeeded()
		XCTAssertEqual(viewer.imageView.layer.cornerRadius, 0, "square corners")
		XCTAssertEqual(viewer.imageView.layer.borderWidth, 0, "no card outline")
		XCTAssertEqual(viewer.imageView.convert(viewer.imageView.bounds, to: viewer.view).width, viewer.view.bounds.width, accuracy: 0.5,
			"the 4:3 image fills the screen width")
		XCTAssertTrue(viewer.hasOpenLinkButton, "an image linking to another page offers Open Link")
		XCTAssertEqual(viewer.maximumZoomScale, 4)
		viewer.toggleZoom(at: CGPoint(x: viewer.imageView.bounds.midX, y: viewer.imageView.bounds.midY))
		for _ in 0..<100 where viewer.zoomScale <= 1.01 {
			try await Task.sleep(for: .milliseconds(20))
		}
		XCTAssertGreaterThan(viewer.zoomScale, 1.5, "double tap zooms in")
	}

	// MARK: - 播客 / YouTube 播放器（ADR-041，2026-09-27 用户反馈第 1 条）

	func testYouTubeVideoIDRecognition() {
		XCTAssertEqual(Babel2ArticleMedia.youTubeVideoID(from: URL(string: "https://www.youtube.com/watch?v=DkUuOr21v4s")), "DkUuOr21v4s")
		XCTAssertEqual(Babel2ArticleMedia.youTubeVideoID(from: URL(string: "https://m.youtube.com/watch?feature=share&v=DkUuOr21v4s")), "DkUuOr21v4s")
		XCTAssertEqual(Babel2ArticleMedia.youTubeVideoID(from: URL(string: "https://youtu.be/DkUuOr21v4s?t=10")), "DkUuOr21v4s")
		XCTAssertEqual(Babel2ArticleMedia.youTubeVideoID(from: URL(string: "https://www.youtube.com/shorts/DkUuOr21v4s")), "DkUuOr21v4s")
		XCTAssertNil(Babel2ArticleMedia.youTubeVideoID(from: URL(string: "https://www.youtube.com/watch?v=short")), "invalid ids are ignored")
		XCTAssertNil(Babel2ArticleMedia.youTubeVideoID(from: URL(string: "https://example.com/watch?v=DkUuOr21v4s")))
		XCTAssertEqual(Babel2ArticleMedia.baseURL(for: URL(string: "https://www.youtube.com/watch?v=DkUuOr21v4s")), URL(string: "https://netnewswire.com/"),
			"a YouTube article must not claim to be youtube.com (embed error 152)")
		XCTAssertEqual(Babel2ArticleMedia.baseURL(for: URL(string: "https://example.com/post")), URL(string: "https://example.com/post"))
	}

	/// YouTube 文章：正文上方放 16:9、贴满屏幕两边的播放器（文章里原地播放），不再显示「没有正文」；
	/// 视频简介到了就填进空正文（网址可点），之后可以翻译。
	func testYouTubeArticleShowsEdgeToEdgePlayerAndFillsDescription() async throws {
		let viewController = makeMediaReader(
			url: URL(string: "https://www.youtube.com/watch?v=DkUuOr21v4s"),
			body: "",
			mediaProvider: { _ in Babel2ArticleMediaExtras(youTubeDescription: "Line one\nhttps://example.com/sponsor\n\nSecond paragraph here.") }
		)
		let window = hostInWindow(viewController)
		defer { window.isHidden = true }
		await waitForReaderRender(viewController)
		XCTAssertTrue(viewController.readerContentView.pageWebView.configuration.allowsInlineMediaPlayback, "video plays inside the article")
		let player = await viewController.readerContentView.evaluateForTesting("""
			const frame = document.querySelector('#babel2-media iframe');
			if (!frame) { return null; }
			const rect = document.getElementById('babel2-media').getBoundingClientRect();
			return { src: frame.src, width: rect.width, height: rect.height, base: document.baseURI };
			""") as? [String: Any]
		let info = try XCTUnwrap(player, "a YouTube player is placed above the body")
		XCTAssertTrue((info["src"] as? String)?.contains("youtube.com/embed/DkUuOr21v4s") == true)
		XCTAssertEqual((info["width"] as? NSNumber)?.doubleValue ?? 0, 402, accuracy: 1, "edge to edge")
		XCTAssertEqual((info["height"] as? NSNumber)?.doubleValue ?? 0, 402 * 9 / 16, accuracy: 2, "16:9")
		XCTAssertEqual(info["base"] as? String, "https://netnewswire.com/")
		let message = try XCTUnwrap(descendant(of: viewController.view, matching: UIStackView.self) { $0.subviews.contains { $0.accessibilityIdentifier == "babel2.article.message" } })
		XCTAssertTrue(message.isHidden, "no 'this article has no content' under a video")

		await waitUntil { viewController.lastRenderResult?.textLength ?? 0 > 20 }
		let text = await viewController.readerContentView.articleTextForTesting() ?? ""
		XCTAssertTrue(text.contains("Second paragraph here."))
		let linkCount = await viewController.readerContentView.evaluateForTesting("return document.querySelectorAll('#babel2-article a').length;") as? Int
		XCTAssertEqual(linkCount, 1, "addresses in the description are tappable")
		await waitUntil { viewController.isTranslationReadyForTesting }
	}

	/// 播客：音频条到了放在正文上方、居中；正文为空时原本的「没有正文」提示随之收起。
	func testPodcastArticleGetsCenteredAudioPlayer() async throws {
		let viewController = makeMediaReader(
			url: URL(string: "https://podcast.example.com/episode-1"),
			body: "",
			mediaProvider: { _ in Babel2ArticleMediaExtras(audioURL: URL(string: "https://cdn.example.com/episode-1.mp3")) }
		)
		let window = hostInWindow(viewController)
		defer { window.isHidden = true }
		await waitForReaderRender(viewController)
		let message = try XCTUnwrap(descendant(of: viewController.view, matching: UIStackView.self) { $0.subviews.contains { $0.accessibilityIdentifier == "babel2.article.message" } })
		await waitUntil { message.isHidden }
		let audio = await viewController.readerContentView.evaluateForTesting("""
			const audio = document.querySelector('#babel2-media audio');
			if (!audio) { return null; }
			const rect = audio.getBoundingClientRect();
			return { src: audio.src, left: rect.left, width: rect.width, controls: audio.controls };
			""") as? [String: Any]
		let info = try XCTUnwrap(audio)
		XCTAssertEqual(info["src"] as? String, "https://cdn.example.com/episode-1.mp3")
		XCTAssertEqual(info["controls"] as? Bool, true)
		let left = (info["left"] as? NSNumber)?.doubleValue ?? 0
		let width = (info["width"] as? NSNumber)?.doubleValue ?? 0
		XCTAssertEqual(left + width / 2, 201, accuracy: 1, "centered")
		XCTAssertEqual(width, 362, accuracy: 1)
	}

	// MARK: - 整页右滑返回（ADR-042，2026-09-27 用户反馈第 2 条）

	func testFullSurfaceBackSwipeRules() throws {
		typealias Motion = Babel2NavigationPopMotion
		func begins(velocity: CGPoint, start: CGPoint = CGPoint(x: 200, y: 400), canPop: Bool = true, page: Bool = true, scroller: Bool = false) -> Bool {
			Motion.shouldBeginContentPan(velocity: velocity, start: start, canPop: canPop, pageAllowsContentPan: page, startsInHorizontalScroller: scroller)
		}
		XCTAssertTrue(begins(velocity: CGPoint(x: 600, y: 80)), "a rightward horizontal swipe anywhere goes back")
		XCTAssertFalse(begins(velocity: CGPoint(x: 100, y: 600)), "vertical scrolling never starts it")
		XCTAssertFalse(begins(velocity: CGPoint(x: 300, y: 290)), "diagonal swipes are left to scrolling")
		XCTAssertFalse(begins(velocity: CGPoint(x: -600, y: 0)), "leftward (the Reader's right-edge browser swipe) is not a back swipe")
		XCTAssertFalse(begins(velocity: CGPoint(x: 600, y: 0), start: CGPoint(x: 10, y: 400)), "the left edge belongs to the edge recognizer")
		XCTAssertFalse(begins(velocity: CGPoint(x: 600, y: 0), canPop: false), "nothing to go back to")
		XCTAssertFalse(begins(velocity: CGPoint(x: 600, y: 0), page: false), "edge-only pages (the in-app browser)")
		XCTAssertFalse(begins(velocity: CGPoint(x: 600, y: 0), scroller: true), "a horizontal scroller scrolls first")

		let root = UIView(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
		let scroller = UIScrollView(frame: CGRect(x: 0, y: 100, width: 402, height: 200))
		scroller.contentSize = CGSize(width: 1000, height: 200)
		let inner = UIView(frame: CGRect(x: 0, y: 0, width: 1000, height: 200))
		scroller.addSubview(inner)
		root.addSubview(scroller)
		XCTAssertFalse(Motion.startsInHorizontalScroller(inner, stopAt: root), "already at its leading edge: swiping right cannot scroll it, so it goes back")
		scroller.contentOffset = CGPoint(x: 300, y: 0)
		XCTAssertTrue(Motion.startsInHorizontalScroller(inner, stopAt: root), "scrolled: a rightward swipe scrolls it back first")
		let list = UITableView(frame: root.bounds)
		root.addSubview(list)
		XCTAssertFalse(Motion.startsInHorizontalScroller(list, stopAt: root), "vertical lists do not block the back swipe")

		let browser: Any = Babel2BrowserViewController(url: URL(string: "https://example.com")!, openExternally: { _ in })
		XCTAssertTrue(browser is Babel2EdgeOnlyBackGesture, "the in-app browser keeps edge-only back")
		let navigation = Babel2NavigationController(rootViewController: UIViewController())
		navigation.loadViewIfNeeded()
		let popMotion = try XCTUnwrap(navigation.popMotion)
		let pan = try XCTUnwrap(popMotion.contentPanForTesting)
		XCTAssertTrue(navigation.view.gestureRecognizers?.contains { $0 === pan } ?? false)
		XCTAssertTrue(pan.delegate === popMotion)
		popMotion.tearDown()
		XCTAssertFalse(navigation.view.gestureRecognizers?.contains { $0 === pan } ?? false, "removed on tear down")
	}

	// MARK: - 长文翻译可靠性（ADR-037，2026-09-27 用户报「长文翻译失败 / 依然显示原文 / 空白」）

	/// 同一网页里重排正文（切阅读模式）后，翻译脚本不能再记着上一版正文：
	/// 以前这时点「原文」会跳回摘要，点「翻译」会直接“还原”成英文。
	func testRerenderClearsTranslationScriptMemory() async throws {
		let viewController = makeReader(body: "<p>Summary only, a short excerpt of the piece.</p>", hostArticle: NSObject(), fullTextProvider: { _, _ in
			Self.longArticleBody(paragraphs: 3, prefix: "Full")
		})
		let window = hostInWindow(viewController)
		defer { window.isHidden = true }
		await waitForReaderRender(viewController)
		_ = try await viewController.nnwTranslationApply("<p>摘要的译文。</p>")
		let showingBefore = try await viewController.nnwTranslationIsShowingTranslation()
		XCTAssertTrue(showingBefore)

		viewController.toggleReaderMode()
		await waitUntil { viewController.lastRenderResult?.textLength ?? 0 > 200 }
		let showingAfter = try await viewController.nnwTranslationIsShowingTranslation()
		XCTAssertFalse(showingAfter, "re-render must forget the previous translation")
		let restored = try await viewController.nnwTranslationRestore()
		XCTAssertFalse(restored, "nothing to restore on a freshly rendered body")
		let text = await viewController.readerContentView.articleTextForTesting() ?? ""
		XCTAssertTrue(text.hasPrefix("Full 0"), "full text stays; got \(text.prefix(40))")
	}

	/// 「总是阅读模式」的源：全文还没到就点了翻译 → 先排队（显示「生成中」、不翻摘要），
	/// 全文排好后自动翻全文；再点「原文」回到的是全文而不是摘要。
	func testTranslateTappedBeforeFullTextArrivesWaitsThenTranslatesFullText() async throws {
		let restore = useFakeTranslationServer()
		defer { restore() }
		let gate = Babel2TestGate()
		var alwaysOn = true
		let setting = Babel2FeedReaderModeSetting(isAlwaysOn: { alwaysOn }, setAlwaysOn: { alwaysOn = $0 })
		let viewController = makeReader(body: "<p>Summary only, a short excerpt of the piece that is long enough to translate here.</p>", hostArticle: NSObject(), fullTextProvider: { _, _ in
			await gate.wait()
			return Self.longArticleBody(paragraphs: 12, prefix: "Full")
		}, feedReaderModeSetting: setting)
		let window = hostInWindow(viewController)
		defer { window.isHidden = true }
		await waitForReaderRender(viewController)
		await waitUntil { viewController.isTranslationReadyForTesting }

		viewController.toolbarView.translationToggle.sendActions(for: .touchUpInside)
		XCTAssertTrue(viewController.isTranslationQueuedForTesting)
		XCTAssertEqual(viewController.toolbarView.translationToggle.accessibilityValue, "working", "queued translation shows the working icon")
		try await Task.sleep(for: .milliseconds(300))
		XCTAssertEqual(FakeTranslationServer.requestCount, 0, "the summary is not translated while the full text is on its way")

		gate.open()
		await waitForTranslation(viewController, toReach: .translated)
		XCTAssertFalse(viewController.isTranslationQueuedForTesting)
		let translated = await viewController.readerContentView.articleTextForTesting() ?? ""
		XCTAssertGreaterThan(Self.cjkRatio(translated), 0.9, "the full text is translated")

		viewController.toolbarView.translationToggle.sendActions(for: .touchUpInside)
		await waitForTranslation(viewController, toReach: .original)
		let original = await viewController.readerContentView.articleTextForTesting() ?? ""
		XCTAssertTrue(original.hasPrefix("Full 0"), "show original returns the full text, not the summary; got \(original.prefix(40))")
	}

	/// 正在看译文时切到全文：新正文自动接着翻（不再变回英文）。
	func testSwitchingReaderModeWhileViewingTranslationTranslatesNewText() async throws {
		let restore = useFakeTranslationServer()
		defer { restore() }
		let viewController = makeReader(body: "<p>Summary only, a short excerpt of the piece that is long enough to translate here.</p>", hostArticle: NSObject(), fullTextProvider: { _, _ in
			Self.longArticleBody(paragraphs: 8, prefix: "Full")
		})
		let window = hostInWindow(viewController)
		defer { window.isHidden = true }
		await waitForReaderRender(viewController)
		await waitUntil { viewController.isTranslationReadyForTesting }
		viewController.toolbarView.translationToggle.sendActions(for: .touchUpInside)
		await waitForTranslation(viewController, toReach: .translated)

		viewController.toggleReaderMode()
		await waitUntil { viewController.lastRenderResult?.textLength ?? 0 > 500 }
		await waitForTranslation(viewController, toReach: .translated)
		let text = await viewController.readerContentView.articleTextForTesting() ?? ""
		XCTAssertGreaterThan(text.count, 500)
		XCTAssertGreaterThan(Self.cjkRatio(text), 0.9, "the new full text is translated automatically")
	}

	/// 模型对多段的组总是漏段（被拒收）：失败的组拆成一段一组重翻，最终整篇译完。
	func testFailedGroupsAreSplitIntoSingleParagraphsAndRetried() async throws {
		let restore = useFakeTranslationServer(.dropParagraphs(atLeast: 2))
		defer { restore() }
		let viewController = makeReader(body: Self.longArticleBody(paragraphs: 30), hostArticle: NSObject())
		let window = hostInWindow(viewController)
		defer { window.isHidden = true }
		await waitForReaderRender(viewController)
		await waitUntil { viewController.isTranslationReadyForTesting }
		viewController.toolbarView.translationToggle.sendActions(for: .touchUpInside)
		await waitForTranslation(viewController, toReach: .translated)
		let text = await viewController.readerContentView.articleTextForTesting() ?? ""
		XCTAssertGreaterThan(Self.cjkRatio(text), 0.9, "every paragraph ends up translated")
		let skeletons = await viewController.readerContentView.evaluateForTesting("return document.querySelectorAll('.nnw-tr-skel').length;") as? Int
		XCTAssertEqual(skeletons, 0)
	}

	/// 模型回「标签在、文字空」的译文：拒收，原文留在页面上（不能出现一片空白却显示「已译」）。
	func testBlankModelOutputIsRejectedAndOriginalTextStays() async throws {
		let restore = useFakeTranslationServer(.blankText)
		defer { restore() }
		let viewController = makeReader(body: Self.longArticleBody(paragraphs: 6), hostArticle: NSObject())
		let window = hostInWindow(viewController)
		defer { window.isHidden = true }
		await waitForReaderRender(viewController)
		await waitUntil { viewController.isTranslationReadyForTesting }
		viewController.toolbarView.translationToggle.sendActions(for: .touchUpInside)
		await waitForTranslation(viewController, toReach: .failed)
		let text = await viewController.readerContentView.articleTextForTesting() ?? ""
		XCTAssertTrue(text.hasPrefix("Paragraph 0"), "original text stays visible; got \(text.prefix(40))")
		let skeletons = await viewController.readerContentView.evaluateForTesting("return document.querySelectorAll('.nnw-tr-skel').length;") as? Int
		XCTAssertEqual(skeletons, 0)
		viewController.presentedViewController?.dismiss(animated: false)
	}

	/// 网页脚本两道新闸：空白译文拒收；拆组时交出去的原文不带骨架色条那层皮。
	func testTranslationScriptRejectsBlankGroupsAndSplitsWithoutSkeletonMarkup() async throws {
		let viewController = makeReader(body: "<p>First paragraph with enough words to count.</p><p>Second paragraph with enough words too.</p><p>Third paragraph closes the piece nicely.</p>", hostArticle: NSObject())
		let window = hostInWindow(viewController)
		defer { window.isHidden = true }
		await waitForReaderRender(viewController)
		let splitResult = try await viewController.nnwTranslationSplitBody(leadChars: 10, firstGroupChars: 10_000, maxGroupChars: 10_000)
		let json = try XCTUnwrap(splitResult)
		let groups = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]])
		XCTAssertEqual(groups.count, 2, "lead paragraph + one group with the other two")
		_ = try await viewController.nnwTranslationMarkPending()

		let blankApplied = try await viewController.nnwTranslationApplyGroup(group: 1, translatedHTML: "<p></p><p> </p>")
		XCTAssertFalse(blankApplied, "tags without text are rejected")

		let piecesResult = try await viewController.nnwTranslationSplitGroup(1)
		let piecesJSON = try XCTUnwrap(piecesResult)
		let pieces = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(piecesJSON.utf8)) as? [[String: Any]])
		XCTAssertEqual(pieces.count, 2)
		for piece in pieces {
			let html = try XCTUnwrap(piece["html"] as? String)
			XCTAssertFalse(html.contains("nnw-tr-skel"), "pieces are sent without the skeleton wrapper")
			XCTAssertGreaterThanOrEqual(piece["group"] as? Int ?? 0, 1000)
		}
		let firstPiece = try XCTUnwrap(pieces.first?["group"] as? Int)
		let applied = try await viewController.nnwTranslationApplyGroup(group: firstPiece, translatedHTML: "<p>第二段的译文，足够长。</p>")
		XCTAssertTrue(applied)
		let singlePieces = try await viewController.nnwTranslationSplitGroup(firstPiece)
		XCTAssertEqual(singlePieces, "[]", "a single paragraph cannot be split further")
	}

	private static func longArticleBody(paragraphs: Int, prefix: String = "Paragraph") -> String {
		(0..<paragraphs).map { index in
			let sentence = "\(prefix) \(index) talks about writing, craft and the long road of getting good at something difficult. "
			return (index % 9 == 4 ? "<h2>Section heading number \(index)</h2>" : "") + "<p>" + String(repeating: sentence, count: 6) + "</p>"
		}.joined()
	}

	/// 中文字符在字母 + 中文里的占比（判断「翻完了没有」）。
	private static func cjkRatio(_ text: String) -> Double {
		var cjk = 0
		var latin = 0
		for scalar in text.unicodeScalars {
			if (0x4E00...0x9FFF).contains(scalar.value) { cjk += 1 } else if CharacterSet.letters.contains(scalar), scalar.isASCII { latin += 1 }
		}
		return cjk + latin == 0 ? 0 : Double(cjk) / Double(cjk + latin)
	}

	/// 等翻译流程到达某个状态（最多约 15 秒；假服务每个请求约 0.05 秒）。
	private func waitForTranslation(_ viewController: Babel2ArticleViewController, toReach state: TranslationButtonState) async {
		for _ in 0..<150 {
			if viewController.translationController.state == state, !viewController.isTranslationQueuedForTesting { return }
			try? await Task.sleep(for: .milliseconds(100))
		}
		XCTFail("Timed out waiting for translation state \(state); now \(viewController.translationController.state)")
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
		// 底栏：设计稿图标资源；翻译改为与其它格同样 44×44 的状态图标（ADR-043，取代 58×44 文字开关）
		let toolbar = viewController.toolbarView
		XCTAssertEqual(toolbar.starIconName, Babel2Icon.star.rawValue)
		XCTAssertNotNil(toolbar.readButton.image(for: .normal))
		XCTAssertEqual(toolbar.translationToggle.bounds.size, CGSize(width: 44, height: 44))
		// 署名两行：作者 / 订阅源（大写）
		let byline = try XCTUnwrap(descendant(of: viewController.view, matching: UILabel.self) { $0.accessibilityIdentifier == "babel2.article.byline" })
		XCTAssertEqual(byline.text, "JOHN GRUBER\nFEED")
		let subtitle = try XCTUnwrap(descendant(of: viewController.view, matching: UILabel.self) { $0.accessibilityIdentifier == "babel2.article.compact-subtitle" })
		XCTAssertEqual(subtitle.text, "FEED · JOHN GRUBER")
		// 正文用专用正文色（2026-09-27 加深：浅色 #626262 / 深色 #B4B4B4），不是主墨色
		await waitForReaderRender(viewController)
		let color = await viewController.readerContentView.evaluateForTesting(
			"return getComputedStyle(document.querySelector('#babel2-article p')).color;"
		) as? String
		var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
		Babel2ReaderContentView.bodyInk.resolvedColor(with: viewController.view.traitCollection).getRed(&r, green: &g, blue: &b, alpha: &a)
		XCTAssertEqual(color, "rgb(\(Int((r * 255).rounded())), \(Int((g * 255).rounded())), \(Int((b * 255).rounded())))")
	}

	/// 深色模式正文看不清（2026-09-27 用户反馈）：正文与底色的对比度，深色至少 7:1、浅色至少 5:1；
	/// 深色下正文不能比日期 / 作者这类次要文字更暗；外壳页的样式里两套外观都用上了正文色。
	func testReaderBodyTextHasReadableContrastInBothAppearances() {
		func luminance(_ color: UIColor, _ style: UIUserInterfaceStyle) -> CGFloat {
			var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
			color.resolvedColor(with: UITraitCollection(userInterfaceStyle: style)).getRed(&r, green: &g, blue: &b, alpha: &a)
			func channel(_ c: CGFloat) -> CGFloat { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
			return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
		}
		func contrast(_ fg: UIColor, _ bg: UIColor, _ style: UIUserInterfaceStyle) -> CGFloat {
			let l1 = luminance(fg, style), l2 = luminance(bg, style)
			return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
		}
		let body = Babel2ReaderContentView.bodyInk
		XCTAssertGreaterThanOrEqual(contrast(body, BabelPalette.background, .dark), 7)
		XCTAssertGreaterThanOrEqual(contrast(body, BabelPalette.background, .light), 5)
		// 深色下：正文比次要文字亮，图注不比次要文字暗
		XCTAssertGreaterThan(luminance(body, .dark), luminance(BabelPalette.tertiaryInk, .dark))
		XCTAssertGreaterThanOrEqual(luminance(Babel2ReaderContentView.captionInk, .dark), luminance(BabelPalette.tertiaryInk, .dark) - 0.0001)
		// 外壳页：正文、引用用正文色，浅色 #626262 / 深色 #B4B4B4 两套都写进去了
		let shell = Babel2ReaderContentView.shellHTML()
		XCTAssertTrue(shell.contains("--body: #626262;"))
		XCTAssertTrue(shell.contains("--body: #B4B4B4;"))
		XCTAssertTrue(shell.contains("body { background: var(--bg); color: var(--body);"))
		XCTAssertTrue(shell.contains("color: var(--body); }"))
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
		// 5 个按钮的中心依次对应参考画布 x = 32 / 116.5 / 201 / 285.5 / 370（窗口宽 402，ADR-033 等距底栏）
		let centers = ([toolbar.readButton, toolbar.starButton, toolbar.nextButton, toolbar.readingModeButton, toolbar.translationToggle] as [UIView]).map { $0.center.x }
		for (actual, expected) in zip(centers, [32, 116.5, 201, 285.5, 370] as [CGFloat]) {
			XCTAssertEqual(actual, expected, accuracy: 0.5)
		}
		// 左右对称：第 1 与第 5 格、第 2 与第 4 格关于屏幕中线对称；中间三格等距
		XCTAssertEqual(centers[0] + centers[4], 402, accuracy: 0.5)
		XCTAssertEqual(centers[1] + centers[3], 402, accuracy: 0.5)
		XCTAssertEqual(centers[2] - centers[1], centers[3] - centers[2], accuracy: 0.5)
		// 所有控件同一条中线（y = 24）
		for control in [toolbar.readButton, toolbar.starButton, toolbar.nextButton, toolbar.readingModeButton, toolbar.translationToggle] as [UIView] {
			XCTAssertEqual(control.center.y, 24, accuracy: 0.5)
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

	/// 冷启动图标（ADR-039）：重算进行中又来了后台通知（图标一张张到、同步进度），不打断正在进行的重算，
	/// 只在它算完后再补一次——以前每来一个通知就从头再来，要等通知停了才出结果。
	func testBackgroundChangesDuringReloadDoNotRestartIt() async throws {
		let feedID = FeedSnapshot.ID(accountID: "account", feedID: "feed")
		let feed = makeFeed(id: feedID, title: "Feed", count: 2)
		let provider = FakeDataProvider(librarySnapshots: [.unread: LibrarySnapshot(feeds: [feed])])
		let root = try XCTUnwrap(Babel2SceneComposition.makeRoot(environment: makeEnvironment(provider: provider)).viewControllers.first as? Babel2RootViewController)
		root.loadViewIfNeeded()
		root.viewDidAppear(false)
		await waitForRootState(root, scope: .unread, state: "loaded", rows: 1)

		await provider.delayNextLibraryRequest(.unread)
		NotificationCenter.default.post(name: .babel2LibraryDidChange, object: nil)
		await waitForLibraryStart(provider, .unread, after: 2)
		for _ in 0..<5 {
			NotificationCenter.default.post(name: .babel2LibraryDidChange, object: nil)
		}
		try await Task.sleep(for: .milliseconds(200))
		let restarted = await provider.hasStarted(.unread, atLeast: 3)
		XCTAssertFalse(restarted, "a reload in progress is not restarted by background changes")

		await provider.releaseLibraryRequest(.unread, snapshot: LibrarySnapshot(feeds: [feed]))
		await waitForLibraryStart(provider, .unread, after: 3)
		try await Task.sleep(for: .milliseconds(200))
		let extra = await provider.hasStarted(.unread, atLeast: 4)
		XCTAssertFalse(extra, "the changes that arrived meanwhile are folded into exactly one follow-up reload")
		await waitForRootState(root, scope: .unread, state: "loaded", rows: 1)
	}

	/// 冷启动图标（ADR-039）：小图标备份存到手机上、冷启动读回；存之前缩到最长边 96 像素。
	func testFeedIconBackupIsDownscaledAndSurvivesColdStart() async throws {
		let format = UIGraphicsImageRendererFormat()
		format.scale = 1
		let big = UIGraphicsImageRenderer(size: CGSize(width: 512, height: 256), format: format).image { context in
			UIColor.red.setFill()
			context.fill(CGRect(x: 0, y: 0, width: 512, height: 256))
		}
		let data = try XCTUnwrap(Babel2LiveIconCache.compactData(for: big))
		let decoded = try XCTUnwrap(UIImage(data: data))
		XCTAssertEqual(decoded.size.width * decoded.scale, 96, accuracy: 0.5)
		XCTAssertEqual(decoded.size.height * decoded.scale, 48, accuracy: 0.5)
		let small = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 40), format: format).image { context in
			UIColor.blue.setFill()
			context.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
		}
		let smallDecoded = try XCTUnwrap(Babel2LiveIconCache.compactData(for: small).flatMap(UIImage.init(data:)))
		XCTAssertEqual(smallDecoded.size.width * smallDecoded.scale, 40, accuracy: 0.5, "small icons are not enlarged")

		let key = "test-account|icon-\(UUID().uuidString)"
		Babel2LiveIconCache.storeForTesting(data, key: key)
		await Babel2LiveIconCache.saveNowForTesting()
		Babel2LiveIconCache.reloadFromDiskForTesting()
		XCTAssertEqual(Babel2LiveIconCache.cachedForTesting(key), data, "the backup is read back after a cold start")
		Babel2LiveIconCache.removeForTesting(key)
		await Babel2LiveIconCache.saveNowForTesting()
	}

	/// 冷启动图标（ADR-039）：文章列表打开时图标还没到，之后到了要补上（以前一直显示首字母）。
	func testFeedPageFillsInIconThatArrivesLater() async throws {
		let feedID = FeedSnapshot.ID(accountID: "account", feedID: "feed")
		let article = ArticleSnapshot(id: ArticleSnapshot.ID(accountID: "account", feedID: "feed", articleID: "a"), title: "A", url: nil, feedID: feedID)
		let provider = FakeDataProvider(feeds: [feedID: [article]])
		let format = UIGraphicsImageRendererFormat()
		format.scale = 1
		let iconData = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 40), format: format).pngData { context in
			UIColor.green.setFill()
			context.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
		}
		final class IconBox { var data: Data? }
		let available = IconBox()
		let feedViewController = Babel2FeedViewController(feed: makeFeed(id: feedID, title: "Feed"), scope: .all, environment: makeEnvironment(provider: provider),
			currentIcon: { available.data })
		let window = hostInWindow(feedViewController)
		defer { window.isHidden = true }
		let tableView = try XCTUnwrap(descendant(of: feedViewController.view, matching: UITableView.self))
		await waitForRows(in: tableView, count: 1)
		XCTAssertFalse(feedViewController.hasFeedIconForTesting)
		feedViewController.refreshFeedIconForTesting()
		XCTAssertFalse(feedViewController.hasFeedIconForTesting, "still no icon")
		available.data = iconData
		feedViewController.refreshFeedIconForTesting()
		XCTAssertTrue(feedViewController.hasFeedIconForTesting)
		let icon = try XCTUnwrap(descendant(of: tableView, matching: UIImageView.self) { $0.accessibilityIdentifier == "babel2.article.feed-icon" })
		XCTAssertNotNil(icon.image, "visible rows get the icon")
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
	/// 跨源列表（ADR-044）：各入口的文章、收到的请求（"入口/档位"）、按编号取状态的请求
	private var smartArticles = [Babel2SmartFeed: SmartFeedArticlesSnapshot]()
	private(set) var smartRequests = [String]()
	private(set) var articleSnapshotRequests = [[ArticleSnapshot.ID]]()

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
		(feedArticles.values.flatMap { $0 } + smartArticles.values.flatMap(\.articles)).first { $0.id == id }
	}

	func setSmartArticles(_ snapshot: SmartFeedArticlesSnapshot, for kind: Babel2SmartFeed) {
		smartArticles[kind] = snapshot
	}

	func smartFeedArticles(_ kind: Babel2SmartFeed, scope: Babel2FeedScope) async throws -> SmartFeedArticlesSnapshot {
		smartRequests.append("\(kind.rawValue)/\(scope.rawValue)")
		return smartArticles[kind] ?? SmartFeedArticlesSnapshot()
	}

	func articleSnapshots(for ids: [ArticleSnapshot.ID]) async throws -> [ArticleSnapshot] {
		articleSnapshotRequests.append(ids)
		var result = [ArticleSnapshot]()
		for id in ids {
			if let article = try await articleSnapshot(for: id) { result.append(article) }
		}
		return result
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
	makeBrowser: ((URL) -> (any Babel2PreparableRoute))? = nil,
	positionStore: Babel2PositionStore? = nil,
	fullTextCache: Babel2FullTextCache? = nil
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
		makeBrowser: makeBrowser,
		positionStore: positionStore,
		fullTextCache: fullTextCache
	)
}

/// 播放器测试用的阅读页（自定义原文地址与播放器信息来源）。
@MainActor
private func makeMediaReader(
	url: URL?,
	body: String,
	mediaProvider: @escaping @MainActor (ArticleSnapshot.ID) async -> Babel2ArticleMediaExtras?
) -> Babel2ArticleViewController {
	let feedID = FeedSnapshot.ID(accountID: "account", feedID: "feed")
	let article = ArticleSnapshot(
		id: ArticleSnapshot.ID(accountID: "account", feedID: "feed", articleID: "media-article"),
		title: "Media",
		content: body,
		url: url,
		feedID: feedID
	)
	return Babel2ArticleViewController(
		article: article,
		environment: makeEnvironment(provider: FakeDataProvider(), actionHandler: NoopActionHandler()),
		feedTitle: "Feed",
		hostArticleProvider: { _ in NSObject() },
		fullTextProvider: { _, _ in throw CancellationError() },
		mediaProvider: mediaProvider
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
	/// 模型回复的正文（默认是一个合法的标题数组）。
	nonisolated(unsafe) static var replyContent = "[\"一个标题\"]"

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
		let payload = (try? JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": Self.replyContent]]]])) ?? Data()
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
	var translationModelsLastRefreshed: Date? = Date()
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


// MARK: - 假的翻译服务（ADR-037 的长文翻译测试用，不联网、不花钱）

/// 让一段异步等待停在那里，直到测试手动放行（模拟「全文还在路上」）。
@MainActor
private final class Babel2TestGate {
	private var continuation: CheckedContinuation<Void, Never>?
	private var isOpen = false

	func wait() async {
		if isOpen { return }
		await withCheckedContinuation { continuation = $0 }
	}

	func open() {
		isOpen = true
		continuation?.resume()
		continuation = nil
	}
}

/// 把翻译设置临时指向假服务；返回的闭包把设置原样还回去（API Key 在钥匙串里，也要还原）。
@MainActor
private func useFakeTranslationServer(_ mode: FakeTranslationServer.Mode = .normal) -> () -> Void {
	let defaults = UserDefaults.standard
	let savedKey = TranslationConfigStore.apiKey
	let savedBaseURL = defaults.string(forKey: "nnwTranslationBaseURL")
	let savedModel = defaults.string(forKey: "nnwTranslationSelectedModel")
	TranslationConfigStore.apiKey = "fake-key"
	TranslationConfigStore.baseURL = "https://" + FakeTranslationServer.host + "/v1"
	TranslationConfigStore.selectedModel = "fake/model"
	FakeTranslationServer.reset(mode: mode)
	URLProtocol.registerClass(FakeTranslationServer.self)
	return {
		URLProtocol.unregisterClass(FakeTranslationServer.self)
		TranslationConfigStore.apiKey = savedKey
		if let savedBaseURL { defaults.set(savedBaseURL, forKey: "nnwTranslationBaseURL") } else { defaults.removeObject(forKey: "nnwTranslationBaseURL") }
		if let savedModel { defaults.set(savedModel, forKey: "nnwTranslationSelectedModel") } else { defaults.removeObject(forKey: "nnwTranslationSelectedModel") }
	}
}

/// 假的 OpenAI 兼容翻译服务：把 HTML 里的文字换成等量约六成的「译」字，标签原样保留；支持流式与非流式。
/// - dropParagraphs：一组里有 N 段以上时只还第一段（模拟模型漏段）
/// - blankText：标签照还、文字全空（模拟「结构完整、一个字没有」）
private final class FakeTranslationServer: URLProtocol {
	enum Mode {
		case normal
		case dropParagraphs(atLeast: Int)
		case blankText
		/// 回复开头先写一段 <think>…</think>（有的服务商把模型的思考直接写在正式回复前面）
		case thinkingFirst
	}

	static let host = "fake-llm.babel2.test"
	nonisolated(unsafe) static var requestCount = 0
	nonisolated(unsafe) static var mode = Mode.normal
	private var isStopped = false
	private var payload: (response: HTTPURLResponse, data: Data)?

	static func reset(mode: Mode) {
		requestCount = 0
		self.mode = mode
	}

	override class func canInit(with request: URLRequest) -> Bool {
		request.url?.host == host
	}

	override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

	override func startLoading() {
		Self.requestCount += 1
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
		let json = (body.flatMap { try? JSONSerialization.jsonObject(with: $0) }) as? [String: Any]
		let messages = json?["messages"] as? [[String: Any]] ?? []
		let user = messages.last?["content"] as? String ?? ""
		let marker = "请翻译下面这段 HTML 片段:\n\n"
		let chunk = user.range(of: marker).map { String(user[$0.upperBound...]) } ?? user
		var translated = Self.fakeTranslate(chunk, blank: { if case .blankText = Self.mode { return true } else { return false } }())
		if case .dropParagraphs(let limit) = Self.mode, chunk.components(separatedBy: "<p").count - 1 >= limit,
			let firstClose = translated.range(of: "</p>") {
			translated = String(translated[..<firstClose.upperBound])
		}
		if case .thinkingFirst = Self.mode {
			translated = "<think>Let me think about [this] first. The reader wants Chinese.</think>\n" + translated
		}
		let isStream = json?["stream"] as? Bool == true
		let data: Data
		if isStream {
			var text = ""
			let characters = Array(translated)
			let size = max(1, characters.count / 3 + 1)
			for start in stride(from: 0, to: characters.count, by: size) {
				let part = String(characters[start..<min(start + size, characters.count)])
				let delta = (try? JSONSerialization.data(withJSONObject: ["choices": [["delta": ["content": part]]]])) ?? Data()
				text += "data: " + (String(data: delta, encoding: .utf8) ?? "") + "\n\n"
			}
			text += "data: [DONE]\n\n"
			data = Data(text.utf8)
		} else {
			data = (try? JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": translated]]]])) ?? Data()
		}
		guard let url = request.url,
			let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
				headerFields: ["Content-Type": isStream ? "text/event-stream" : "application/json"]) else { return }
		payload = (response, data)
		// 模拟一点网络延迟；回调必须回到发起加载的那个线程上
		let delivery = FakeTranslationDelivery(target: self, thread: Thread.current)
		DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) { delivery.fire() }
	}

	@objc fileprivate func deliver() {
		guard !isStopped, let payload else { return }
		client?.urlProtocol(self, didReceive: payload.response, cacheStoragePolicy: .notAllowed)
		client?.urlProtocol(self, didLoad: payload.data)
		client?.urlProtocolDidFinishLoading(self)
	}

	override func stopLoading() { isStopped = true }

	/// 逐段扫：`<…>` 原样保留，标签之间的文字换成「译」字（blank 时换成空）。
	static func fakeTranslate(_ html: String, blank: Bool) -> String {
		var result = ""
		var index = html.startIndex
		while index < html.endIndex {
			if html[index] == "<", let close = html[index...].firstIndex(of: ">") {
				result += html[index...close]
				index = html.index(after: close)
			} else {
				let next = html[index...].firstIndex(of: "<") ?? html.endIndex
				let text = html[index..<next]
				if blank || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
					result += blank ? "" : text
				} else {
					result += String(repeating: "译", count: max(2, text.count * 6 / 10))
				}
				index = next
			}
		}
		return result
	}
}

/// 假翻译服务的回调必须回到发起加载的那个线程上：把「对象 + 线程」打包成一件可以跨线程带过去的东西（只在那个线程上用）。
private final class FakeTranslationDelivery: @unchecked Sendable {
	weak var target: FakeTranslationServer?
	let thread: Thread

	init(target: FakeTranslationServer, thread: Thread) {
		self.target = target
		self.thread = thread
	}

	func fire() {
		guard let target else { return }
		target.perform(#selector(FakeTranslationServer.deliver), on: thread, with: nil, waitUntilDone: false, modes: [RunLoop.Mode.default.rawValue])
	}
}

// MARK: - 首页整理测试用（ADR-045 / 046）

@MainActor
private func localized(_ key: Babel2LocalizationKey) -> String {
	Babel2Localization.text(key)
}

/// 毛玻璃菜单顶部的说明文字。
@MainActor
private func menuTitle(_ menu: Babel2GlassMenu) -> String? {
	descendant(of: menu, matching: UILabel.self) { $0.accessibilityIdentifier == "babel2.menu.title" }?.text
}

/// 等弹出的对话框完全出现后，把它收起（不做动画）。
@MainActor
private func dismissPresented(_ viewController: UIViewController) async {
	for _ in 0..<100 {
		if let presented = viewController.presentedViewController, !presented.isBeingPresented { break }
		try? await Task.sleep(for: .milliseconds(10))
	}
	viewController.dismiss(animated: false)
	for _ in 0..<100 where viewController.presentedViewController != nil {
		try? await Task.sleep(for: .milliseconds(10))
	}
}

@MainActor
private func solidImage(size: CGSize, color: UIColor) -> UIImage {
	let format = UIGraphicsImageRendererFormat()
	format.scale = 1
	return UIGraphicsImageRenderer(size: size, format: format).image { context in
		color.setFill()
		context.fill(CGRect(origin: .zero, size: size))
	}
}

/// 读图上某个像素（左上角为原点）的颜色。
@MainActor
private func pixelColor(_ image: UIImage, x: Int, y: Int) -> (red: UInt8, green: UInt8, blue: UInt8) {
	guard let cgImage = image.cgImage else { return (0, 0, 0) }
	var pixel = [UInt8](repeating: 0, count: 4)
	pixel.withUnsafeMutableBytes { buffer in
		guard let context = CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
			space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
		context.draw(cgImage, in: CGRect(x: -CGFloat(x), y: -CGFloat(cgImage.height - 1 - y),
			width: CGFloat(cgImage.width), height: CGFloat(cgImage.height)))
	}
	return (pixel[0], pixel[1], pixel[2])
}

/// 记录首页整理操作的假实现。failNext：下一次操作返回的失败说明。
@MainActor
private final class FakeLibraryEditing {
	var calls = [String]()
	var failNext: String?
	var accountList = [Babel2AccountChoice(id: "account", title: "On My iPhone")]
	var folderInfos = [FolderSnapshot.ID: Babel2FolderInfo]()
	var placements = [FeedSnapshot.ID: Babel2FeedPlacement]()
	var customIconIDs = Set<FeedSnapshot.ID>()

	private func record(_ call: String) -> String? {
		calls.append(call)
		defer { failNext = nil }
		return failNext
	}

	var editing: Babel2LibraryEditing {
		Babel2LibraryEditing(
			accounts: { self.accountList },
			folderInfo: { self.folderInfos[$0] },
			placement: { self.placements[$0] },
			createFolder: { name, accountID in
				if let message = self.record("create:\(name)@\(accountID)") { return .failure(Babel2EditFailure(message: message)) }
				return .success("\(accountID):99")
			},
			renameFolder: { id, name in self.record("renameFolder:\(id)->\(name)") },
			deleteFolder: { id, keepFeeds in self.record("deleteFolder:\(id):\(keepFeeds ? "keep" : "all")") },
			setFeedFolders: { id, folderIDs in self.record("folders:\(id.feedID):\(folderIDs.joined(separator: ","))") },
			renameFeed: { id, name in self.record("renameFeed:\(id.feedID)->\(name)") },
			unsubscribe: { id in self.record("unsubscribe:\(id.feedID)") },
			customIcons: Babel2CustomFeedIconStore(
				hasCustomIcon: { self.customIconIDs.contains($0) },
				setCustomIcon: { id, data in
					self.calls.append("icon:\(id.feedID):\(data == nil ? "reset" : "set")")
					if data == nil { self.customIconIDs.remove(id) } else { self.customIconIDs.insert(id) }
					return true
				}
			),
			feedURL: { "https://example.com/\($0.feedID)/feed.xml" }
		)
	}
}

/// 可整理的首页：文件夹 Empty（空）、News（Alpha）、Tech（Alpha、Beta），顶层 Gamma。
/// Alpha 同时在 News 和 Tech 里（首页「重复」）；Beta 标成另一个账户（菜单顶部带账户名）；Gamma 换过图标。
@MainActor
private func makeOrganizableHome() async throws -> (navigation: Babel2NavigationController, root: Babel2RootViewController,
	editing: FakeLibraryEditing, provider: FakeDataProvider, window: UIWindow) {
	func id(_ feedID: String) -> FeedSnapshot.ID { FeedSnapshot.ID(accountID: "account", feedID: feedID) }
	let alpha = makeFeed(id: id("a"), title: "Alpha", count: 3)
	let beta = makeFeed(id: id("b"), title: "Beta", count: 2)
	let gamma = makeFeed(id: id("c"), title: "Gamma", count: 1)
	let folders = [
		FolderSnapshot(id: "account:1", title: "Tech", feedIDs: [alpha.id, beta.id], articleCount: 5),
		FolderSnapshot(id: "account:2", title: "Empty", feedIDs: [], articleCount: 0),
		FolderSnapshot(id: "account:3", title: "News", feedIDs: [alpha.id], articleCount: 3)
	]
	let snapshot = LibrarySnapshot(feeds: [alpha, beta, gamma], folders: folders)
	let provider = FakeDataProvider(librarySnapshots: [.unread: snapshot, .all: snapshot, .starred: LibrarySnapshot()])
	let editing = FakeLibraryEditing()
	let top = Babel2FeedLocation(folderID: nil, title: "")
	let tech = Babel2FeedLocation(folderID: "account:1", title: "Tech")
	let empty = Babel2FeedLocation(folderID: "account:2", title: "Empty")
	let news = Babel2FeedLocation(folderID: "account:3", title: "News")
	let destinations = [top, empty, news, tech]
	editing.folderInfos = [
		"account:1": Babel2FolderInfo(title: "Tech", feedCount: 2, accountTitle: nil),
		"account:2": Babel2FolderInfo(title: "Empty", feedCount: 0, accountTitle: nil),
		"account:3": Babel2FolderInfo(title: "News", feedCount: 1, accountTitle: nil)
	]
	editing.placements = [
		alpha.id: Babel2FeedPlacement(accountTitle: nil, current: [news, tech], destinations: destinations),
		beta.id: Babel2FeedPlacement(accountTitle: "iCloud", current: [tech], destinations: destinations),
		gamma.id: Babel2FeedPlacement(accountTitle: nil, current: [top], destinations: destinations)
	]
	editing.customIconIDs = [gamma.id]
	let navigation = Babel2SceneComposition.makeRoot(environment: makeEnvironment(provider: provider),
		settingsService: FakeSettingsService(), subscriptionService: FakeSubscriptionService(), libraryEditing: editing.editing)
	let window = hostInWindow(navigation)
	let root = try XCTUnwrap(navigation.viewControllers.first as? Babel2RootViewController)
	await waitForRootState(root, scope: .unread, state: "loaded", rows: 7)
	return (navigation, root, editing, provider, window)
}


// MARK: - 位置记忆测试用（ADR-053）

/// 列表里某篇文章所在的行。
@MainActor
private func indexPathOfArticle(_ articleID: String, in tableView: UITableView) -> IndexPath? {
	for section in 0..<tableView.numberOfSections {
		for row in 0..<tableView.numberOfRows(inSection: section) {
			let path = IndexPath(row: row, section: section)
			if let cell = tableView.dataSource?.tableView(tableView, cellForRowAt: path),
				cell.accessibilityIdentifier?.hasSuffix(".\(articleID)") == true {
				return path
			}
		}
	}
	return nil
}

/// 读图上某一点（点坐标）的不透明度。
@MainActor
private func alphaAt(_ image: UIImage, _ point: CGPoint) -> CGFloat {
	guard let cgImage = image.cgImage else { return 0 }
	let x = Int(point.x * image.scale), y = Int(point.y * image.scale)
	var pixel = [UInt8](repeating: 0, count: 4)
	pixel.withUnsafeMutableBytes { buffer in
		guard let context = CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
			space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
		context.draw(cgImage, in: CGRect(x: -CGFloat(x), y: -CGFloat(cgImage.height - 1 - y), width: CGFloat(cgImage.width), height: CGFloat(cgImage.height)))
	}
	return CGFloat(pixel[3]) / 255
}
