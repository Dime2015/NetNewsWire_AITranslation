import XCTest

@MainActor
final class Babel2FeedReaderUITests: XCTestCase {
	private let appBundleIdentifier = "com.wenbopan.NetNewsWire.iOS"
	private let scopeIdentifiers = ["babel2.scope.all", "babel2.scope.unread", "babel2.scope.starred"]

	func testRealFeedsToArticleAndOpenOriginal() {
		let app = XCUIApplication(bundleIdentifier: appBundleIdentifier)
		app.launch()

		let feedsTable = app.tables[tableIdentifier(for: "babel2.scope.all")]
		guard waitForExistence(feedsTable, timeout: 20) else {
			attachState(app, name: "root")
			fail("SIMULATOR_HARNESS_TIMEOUT", "feeds table did not appear")
			return
		}
		attachState(app, name: "root")

		var rowsByScope = [String: Int]()
		for scopeIdentifier in scopeIdentifiers {
			let scopeTable = app.tables[tableIdentifier(for: scopeIdentifier)]
			let scopeButton = app.buttons[scopeIdentifier]
			guard waitForExistence(scopeButton, timeout: 5) else {
				fail("UI_SELECTOR_TIMEOUT", "scope control \(scopeIdentifier) did not appear")
				return
			}
			scopeButton.tap()
			guard let rootState = waitForRootResolution(in: scopeTable, timeout: 20) else {
				fail("UI_SELECTOR_TIMEOUT", "root scope did not resolve: \(scopeIdentifier)")
				return
			}
			guard waitForSelected(scopeButton, timeout: 5) else {
				fail("UI_SELECTOR_TIMEOUT", "scope control \(scopeIdentifier) was not selected after resolution")
				return
			}
			guard rootState != "error" else {
				attachMetric(app, name: "scope-error-\(scopeIdentifier)", value: "state=error")
				fail("UI_SELECTOR_TIMEOUT", "root scope resolved to error: \(scopeIdentifier)")
				return
			}
			let rootRows = scopeTable.cells.count
			rowsByScope[scopeIdentifier] = rootRows
			for rowIndex in 0..<rootRows {
				let cell = scopeTable.cells.element(boundBy: rowIndex)
				guard positiveCount(in: cell) else {
					fail("UI_SELECTOR_TIMEOUT", "visible source has no positive scope count: \(scopeIdentifier)")
					return
				}
			}
			if rootRows == 0 {
				guard rootState == "empty" else {
					fail("UI_SELECTOR_TIMEOUT", "zero rows without exact empty state: \(scopeIdentifier)")
					return
				}
				attachMetric(app, name: "valid-empty-\(scopeIdentifier)", value: "VALID_EMPTY_SCOPE")
				continue
			}

			scopeTable.cells.firstMatch.tap()
			let articlesTable = app.tables["babel2.feed.articles.table"]
			guard waitForExistence(articlesTable, timeout: 15) else {
				attachState(app, name: "feed-\(scopeIdentifier)")
				fail("UI_SELECTOR_TIMEOUT", "article table did not appear for \(scopeIdentifier)")
				return
			}
			guard let articleState = waitForArticleResolution(in: articlesTable, timeout: 12) else {
				fail("UI_SELECTOR_TIMEOUT", "article list did not resolve for \(scopeIdentifier)")
				return
			}
			guard articleState != "error" else {
				fail("UI_SELECTOR_TIMEOUT", "article list resolved to error for \(scopeIdentifier)")
				return
			}
				let articleRows = articlesTable.cells.count
				if articleRows > 0 {
					let headerCount = app.staticTexts["babel2.feed.count"]
					guard waitForExistence(headerCount, timeout: 5) else {
						fail("UI_SELECTOR_TIMEOUT", "feed header count did not appear for \(scopeIdentifier)")
						return
					}
					let displayedCount = integerValue(of: headerCount)
					let displayedValue = displayedCount.map { String($0) } ?? "nil"
					attachMetric(
						app,
						name: "feed-count-\(scopeIdentifier)",
						value: "scope=\(scopeIdentifier); displayedCount=\(displayedValue); articleRows=\(articleRows)"
					)
					guard displayedCount == articleRows else {
						fail("UI_SELECTOR_TIMEOUT", "feed header count did not match article rows for \(scopeIdentifier): displayed=\(displayedValue), rows=\(articleRows)")
						return
					}
				let feedTitle = app.staticTexts["babel2.feed.title"]
				guard waitForExistence(feedTitle, timeout: 5), feedTitle.value as? String == scopeIdentifier.replacingOccurrences(of: "babel2.scope.", with: "") else {
					fail("UI_SELECTOR_TIMEOUT", "feed scope did not remain \(scopeIdentifier)")
					return
				}
			}
			leaveFeed(app: app, feedsTable: scopeTable)
			guard waitForExistence(scopeTable, timeout: 10), scopeTable.cells.count == rootRows else {
				fail("HANDOFF_FAILURE", "feed back did not restore \(scopeIdentifier) rows")
				return
			}
		}

		let allScope = app.buttons["babel2.scope.all"]
		let unreadScope = app.buttons["babel2.scope.unread"]
		let starredScope = app.buttons["babel2.scope.starred"]
		allScope.tap()
		unreadScope.tap()
		starredScope.tap()
		guard waitForSelected(starredScope, timeout: 5) else {
			fail("UI_SELECTOR_TIMEOUT", "rapid scope taps did not settle on starred")
			return
		}
		allScope.tap()
		guard waitForSelected(allScope, timeout: 5) else {
			fail("UI_SELECTOR_TIMEOUT", "all scope could not be restored")
			return
		}

		guard (rowsByScope["babel2.scope.all"] ?? 0) > 0 else {
			fail("EMPTY_REAL_DATA", "all scope has no cached source")
			return
		}
		var selectedArticle = false
		let feedCount = feedsTable.cells.count
		for feedIndex in 0..<feedCount where !selectedArticle {
			feedsTable.cells.element(boundBy: feedIndex).tap()
			let articlesTable = app.tables["babel2.feed.articles.table"]
			guard waitForExistence(articlesTable, timeout: 15) else {
				fail("UI_SELECTOR_TIMEOUT", "article table did not appear for feed \(feedIndex)")
				return
			}
			guard let articleState = waitForArticleResolution(in: articlesTable, timeout: 12), articleState != "error" else {
				leaveFeed(app: app, feedsTable: feedsTable)
				continue
			}
			for articleIndex in 0..<articlesTable.cells.count where !selectedArticle {
				articlesTable.cells.element(boundBy: articleIndex).tap()
				let bodyView = app.textViews["babel2.article.body"]
				guard waitForExistence(bodyView, timeout: 10), waitForBody(in: bodyView, timeout: 20) != nil else {
					attachState(app, name: "reader")
					fail("ARTICLE_BODY_LOADING_OR_EMPTY", "reader body remained loading or empty")
					return
				}
				attachState(app, name: "reader")
				let originalButton = app.buttons["babel2.article.open-original"]
				guard waitForExistence(originalButton, timeout: 1), originalButton.isEnabled else {
					guard tapAndWait(app.buttons["babel2.article.back"], app: app, timeout: 10), waitForExistence(articlesTable, timeout: 10) else {
						fail("HANDOFF_FAILURE", "could not continue article URL search")
						return
					}
					continue
				}
				originalButton.tap()
				let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
				let safariViewService = XCUIApplication(bundleIdentifier: "com.apple.SafariViewService")
				let safariForeground = safari.wait(for: .runningForeground, timeout: 15)
				let safariViewServiceForeground = safariViewService.wait(for: .runningForeground, timeout: 1)
				attachState(safariForeground ? safari : safariViewService, name: "after-browser")
				guard safariForeground || safariViewServiceForeground else {
					fail("HANDOFF_FAILURE", "system browser did not become foreground")
					return
				}
				app.activate()
				selectedArticle = true
			}
			if !selectedArticle {
				leaveFeed(app: app, feedsTable: feedsTable)
			}
		}

		guard selectedArticle else {
			fail("OPEN_ORIGINAL_NO_URL", "no visible cached article exposed an enabled original URL")
			return
		}
		guard tapAndWait(app.buttons["babel2.article.back"], app: app, timeout: 10),
			waitForExistence(app.buttons["babel2.feed.back"], timeout: 10) else {
			fail("HANDOFF_FAILURE", "article back control did not restore feed")
			return
		}
		app.buttons["babel2.feed.back"].tap()
		guard waitForExistence(feedsTable, timeout: 10), waitForSelected(allScope, timeout: 5) else {
			fail("HANDOFF_FAILURE", "feed back control did not restore root/all scope")
			return
		}
		attachState(app, name: "back")
		XCTAssertEqual(feedsTable.cells.count, rowsByScope["babel2.scope.all"], "HANDOFF_FAILURE: root feed count changed")
	}

	private func waitForSelected(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
		let deadline = Date().addingTimeInterval(timeout)
		while Date() < deadline {
			if element.isSelected || (element.value as? String) == "Selected" { return true }
			RunLoop.current.run(until: Date().addingTimeInterval(0.1))
		}
		return element.isSelected || (element.value as? String) == "Selected"
	}

	private func positiveCount(in cell: XCUIElement) -> Bool {
		guard let count = integerValue(of: cell) else { return false }
		return count > 0
	}

	private func integerValue(of element: XCUIElement) -> Int? {
		let value = (element.value as? String) ?? element.label
		return Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
	}

	private func waitForExistence(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
		element.waitForExistence(timeout: timeout)
	}

	private func waitForArticleResolution(in table: XCUIElement, timeout: TimeInterval) -> String? {
		let deadline = Date().addingTimeInterval(timeout)
		while Date() < deadline {
			if let state = table.value as? String, ["loaded", "empty", "error"].contains(state) { return state }
			RunLoop.current.run(until: Date().addingTimeInterval(0.2))
		}
		return nil
	}

	private func waitForRootResolution(in table: XCUIElement, timeout: TimeInterval) -> String? {
		let deadline = Date().addingTimeInterval(timeout)
		while Date() < deadline {
			if let state = table.value as? String, ["loaded", "empty", "error"].contains(state) { return state }
			RunLoop.current.run(until: Date().addingTimeInterval(0.2))
		}
		return nil
	}

	private func waitForBody(in textView: XCUIElement, timeout: TimeInterval) -> String? {
		let deadline = Date().addingTimeInterval(timeout)
		while Date() < deadline {
			let candidate = (textView.value as? String) ?? textView.label
			if isUsableBody(candidate) {
				return candidate
			}
			RunLoop.current.run(until: Date().addingTimeInterval(0.2))
		}
		return nil
	}

	private func isUsableBody(_ value: String) -> Bool {
		let withoutScripts = value.replacingOccurrences(
			of: #"(?is)<(script|style)[^>]*>.*?</\1>"#,
			with: " ",
			options: .regularExpression
		)
		let withoutTags = withoutScripts.replacingOccurrences(
			of: #"<[^>]+>"#,
			with: " ",
			options: .regularExpression
		)
		let normalized = withoutTags
			.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
			.trimmingCharacters(in: .whitespacesAndNewlines)
		return !normalized.isEmpty && normalized != "Loading…" && normalized != "Loading..."
	}

	private func leaveFeed(app: XCUIApplication, feedsTable: XCUIElement) {
		let back = app.buttons["babel2.feed.back"]
		guard waitForExistence(back, timeout: 5) else { return }
		back.tap()
		_ = waitForExistence(feedsTable, timeout: 10)
	}

	private func tableIdentifier(for scopeIdentifier: String) -> String {
		"babel2.feeds.table.\(scopeIdentifier.replacingOccurrences(of: "babel2.scope.", with: ""))"
	}

	@discardableResult
	private func tapAndWait(_ element: XCUIElement, app: XCUIApplication, timeout: TimeInterval) -> Bool {
		guard waitForExistence(element, timeout: timeout) else { return false }
		element.tap()
		return true
	}

	private func attachState(_ app: XCUIApplication, name: String) {
		let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
		screenshot.name = name
		screenshot.lifetime = .keepAlways
		add(screenshot)

		let hierarchy = XCTAttachment(string: app.debugDescription)
		hierarchy.name = "\(name)-ui-hierarchy"
		hierarchy.lifetime = .keepAlways
		add(hierarchy)

		attachMetric(
			app,
			name: "\(name)-metrics",
			value: "tables=\(app.tables.count); feedCells=\(app.tables[tableIdentifier(for: "babel2.scope.all")].cells.count)"
		)
	}

	private func attachMetric(_ app: XCUIApplication, name: String, value: String) {
		let metric = XCTAttachment(string: value)
		metric.name = name
		metric.lifetime = .keepAlways
		add(metric)
	}

	private func fail(_ category: String, _ detail: String) {
		XCTFail("\(category): \(detail)")
	}
}
