import XCTest
import UIKit
import Babel2Core
import Babel2UI
@testable import NetNewsWire

private final class Babel2WeakReference<Object: AnyObject> {
	weak var value: Object?

	init(_ value: Object) {
		self.value = value
	}
}

@MainActor
final class Babel2FeatureGateTests: XCTestCase {
	func testEveryBuildChannelUsesOnlyTheBabel2Runtime() {
		for buildChannel in Babel2BuildChannel.allCases {
			let decision = Babel2FeatureGate.decision(buildChannel: buildChannel)
			XCTAssertEqual(decision.generation, .babel2, "Babel2 is the only runtime for \(buildChannel)")
			XCTAssertEqual(decision.reason, .babel2OnlyRuntime)
			XCTAssertTrue(decision.isBabel2)
			XCTAssertFalse(decision.diagnostics.isEmpty)
		}
	}

	func testLaunchArgumentsAndPersistedGenerationCannotSelectAnotherRuntime() throws {
		// The production decision API deliberately has no arguments or persistence
		// input. This prevents stale launch flags and stored values from becoming a
		// second runtime selector.
		let decision = Babel2FeatureGate.decision(buildChannel: .debug)
		XCTAssertEqual(decision.generation, .babel2)
		XCTAssertTrue(decision.diagnostics.joined(separator: " ").contains("launch arguments ignored"))

		let appDelegateSource = try projectSource(named: "iOS/AppDelegate.swift")
		let sceneDelegateSource = try projectSource(named: "iOS/SceneDelegate.swift")
		for source in [appDelegateSource, sceneDelegateSource] {
			XCTAssertFalse(source.contains("ProcessInfo.processInfo.arguments"))
			XCTAssertFalse(source.contains("BabelGeneration"))
			XCTAssertFalse(source.contains("GenesisV2"))
		}
	}

	func testBabel2LaunchTraceDerivesValidityAndMilestonesFromEvents() throws {
		let decision = Babel2FeatureGate.decision(buildChannel: .test)
		let recorder = Babel2LaunchTraceRecorder(
			decision: decision,
			buildChannel: .test,
			gateUptime: 12.5,
			processEntryUptime: 11.25,
			sessionID: "test-session",
			origin: "test-origin",
			bundleIdentifier: "test.bundle",
			bundleVersion: "1.2",
			bundleBuild: "42"
		)
		var trace = recorder.snapshot
		XCTAssertEqual(trace.generation, .babel2)
		XCTAssertEqual(trace.reason, .babel2OnlyRuntime)
		XCTAssertEqual(trace.events.first?.kind, .processEntry)
		XCTAssertEqual(trace.events.first?.sequence, 0)
		XCTAssertEqual(trace.events.first?.uptime, 11.25)
		XCTAssertEqual(trace.events.dropFirst().first?.kind, .decision)
		XCTAssertEqual(trace.events.dropFirst().first?.sequence, 1)
		XCTAssertEqual(trace.events.dropFirst().first?.uptime, 12.5)
		XCTAssertFalse(trace.rootVisible)
		XCTAssertFalse(trace.rootInstalled)
		XCTAssertFalse(trace.firstFramePresented)
		XCTAssertFalse(trace.isValid)
		XCTAssertTrue(trace.invalidReasons.contains(.sceneConfigurationObservationMissing))

		recorder.recordSceneConfigurationSelected(Babel2SceneConfiguration.name)
		recorder.recordSceneConfigurationObserved(
			name: Babel2SceneConfiguration.name,
			delegateClassName: "SceneDelegate",
			delegateMatchesExpected: true,
			storyboardPresent: false
		)
		let surface = Babel2TraceSurface(
			controllerType: "Babel2NavigationController",
			contentType: "UIView",
			windowBounds: Babel2TraceRect(x: 0, y: 0, width: 390, height: 844),
			rootBounds: Babel2TraceRect(x: 0, y: 0, width: 390, height: 844),
			rootFrame: Babel2TraceRect(x: 0, y: 0, width: 390, height: 844),
			contentBounds: Babel2TraceRect(x: 0, y: 0, width: 390, height: 844),
			contentFrame: Babel2TraceRect(x: 0, y: 0, width: 390, height: 844),
			safeAreaInsets: Babel2TraceInsets(top: 59, left: 0, bottom: 34, right: 0),
			windowIsHidden: false,
			windowIsKey: true,
			rootMatchesExpected: true
		)
		recorder.recordRootInstalled(surface: surface)
		recorder.recordRootVisible(surface: surface)
		recorder.recordContainerAppeared(surface: surface)
		recorder.recordContentFirstFramePresented(surface: surface)
		trace = recorder.snapshot
		XCTAssertTrue(trace.rootVisible)
		XCTAssertTrue(trace.rootInstalled)
		XCTAssertTrue(trace.firstFramePresented)
		XCTAssertTrue(trace.isComplete)
		XCTAssertTrue(trace.isValid)
		XCTAssertTrue(trace.invalidReasons.isEmpty)
		XCTAssertLessThanOrEqual(trace.processEntryUptime, trace.gateUptime)
		XCTAssertLessThanOrEqual(trace.gateUptime, trace.rootInstalledUptime!)
		XCTAssertLessThanOrEqual(trace.rootInstalledUptime!, trace.rootVisibleUptime!)
		XCTAssertLessThanOrEqual(trace.rootVisibleUptime!, trace.containerAppearedUptime!)
		XCTAssertLessThanOrEqual(trace.containerAppearedUptime!, trace.contentFirstFrameUptime!)
		XCTAssertTrue(trace.diagnosticSummary.contains("generation=babel-2"))
		XCTAssertEqual(trace.events.map(\.sequence), Array(0..<trace.events.count))
		XCTAssertEqual(Set(trace.events.map(\.sessionID)), Set(["test-session"]))
		XCTAssertEqual(trace.events.map(\.kind), [.processEntry, .decision, .sceneConfigurationSelected, .sceneConfigurationObserved, .rootInstalled, .rootVisible, .containerAppeared, .contentFirstFramePresented])

		let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(trace.structuredJSONLine.utf8)) as? [String: Any])
		XCTAssertEqual(json["origin"] as? String, "test-origin")
		XCTAssertEqual(json["sessionID"] as? String, "test-session")
		XCTAssertEqual(json["bundleBuild"] as? String, "42")
		XCTAssertEqual(json["selectedSceneConfigurationLookupName"] as? String, Babel2SceneConfiguration.name)
		XCTAssertEqual(json["isValid"] as? Bool, true)
		let jsonEvents = try XCTUnwrap(json["events"] as? [[String: Any]])
		let decodedEvents = try jsonEvents.map { try JSONDecoder().decode(Babel2LaunchTraceEvent.self, from: JSONSerialization.data(withJSONObject: $0)) }
		XCTAssertEqual(decodedEvents, trace.events)
		XCTAssertEqual(Set(decodedEvents.map(\.sequence)).count, decodedEvents.count)
		XCTAssertTrue(decodedEvents.allSatisfy { $0.sessionID == trace.sessionID })
		XCTAssertTrue(trace.events.map(\.structuredJSONLine).allSatisfy { $0.utf8.count < 900 })
		let resultJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(trace.resultJSONLine.utf8)) as? [String: Any])
		XCTAssertEqual(resultJSON["sessionID"] as? String, trace.sessionID)
		XCTAssertEqual(resultJSON["isComplete"] as? Bool, true)
		XCTAssertEqual(resultJSON["isValid"] as? Bool, true)
		XCTAssertEqual(resultJSON["eventCount"] as? Int, trace.events.count)
		XCTAssertTrue(trace.resultJSONLine.utf8.count < 900)
		XCTAssertEqual(jsonEvents.first?["source"] as? String, "AppDelegate.init")
		XCTAssertEqual(jsonEvents.last?["kind"] as? String, "contentFirstFramePresented")
	}

	func testLegacyEventsAreDerivedAndInvalidateTheTrace() throws {
		let probes: [(Babel2LaunchTraceEventKind, Babel2LaunchTraceInvalidReason, String, (Babel2LaunchTraceRecorder) -> Void)] = [
			(.legacyUILifecycle, .legacyUILifecycle, "fixture.ui", { $0.recordLegacyUILifecycle(source: "fixture.ui") }),
			(.legacyBootstrap, .legacyBootstrap, "fixture.bootstrap", { $0.recordLegacyBootstrap(source: "fixture.bootstrap") }),
			(.legacyStoryboardDecode, .legacyStoryboardDecode, "fixture.storyboard", { $0.recordLegacyStoryboardDecode(source: "fixture.storyboard") }),
			(.legacySceneCoordinator, .legacySceneCoordinator, "fixture.coordinator", { $0.recordLegacyCoordinatorCreation(source: "fixture.coordinator") }),
			(.legacyWebViewBootstrap, .legacyWebViewBootstrap, "fixture.webview", { $0.recordLegacyWebViewBootstrap(source: "fixture.webview") })
		]

		for (kind, reason, source, inject) in probes {
			let recorder = completeTraceRecorder(
				sessionID: "session-\(source)",
				includeContentFirstFrame: kind != .legacyWebViewBootstrap
			)
			inject(recorder)
			let trace = recorder.snapshot
			XCTAssertEqual(trace.events.last?.kind, kind)
			XCTAssertEqual(trace.events.last?.source, source)
			XCTAssertTrue(trace.invalidReasons.contains(reason))
			XCTAssertFalse(trace.isValid)
			let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(trace.structuredJSONLine.utf8)) as? [String: Any])
			let jsonEvents = try XCTUnwrap(json["events"] as? [[String: Any]])
			XCTAssertEqual(json["sessionID"] as? String, "session-\(source)")
			XCTAssertEqual(jsonEvents.last?["source"] as? String, source)
		}
	}

	func testLegacyWebViewProbeClosesAtContentFirstFrame() {
		let recorder = Babel2LaunchTraceRecorder(
			decision: Babel2FeatureGate.decision(buildChannel: .test),
			buildChannel: .test,
			gateUptime: 12,
			processEntryUptime: 11,
			sessionID: "webview-window"
		)
		XCTAssertTrue(recorder.recordLegacyWebViewBootstrap(source: "before-frame"))
		XCTAssertTrue(recorder.recordLegacyBlankWebViewBootstrap(source: "blank-before-frame"))
		let surface = Babel2TraceSurface(controllerType: "Babel2NavigationController")
		recorder.recordContentFirstFramePresented(surface: surface)
		let eventCountAfterFirstFrame = recorder.snapshot.events.count
		XCTAssertFalse(recorder.recordLegacyWebViewBootstrap(source: "after-frame"))
		XCTAssertFalse(recorder.recordLegacyBlankWebViewBootstrap(source: "blank-after-frame"))
		XCTAssertEqual(recorder.snapshot.events.count, eventCountAfterFirstFrame)
		XCTAssertEqual(recorder.snapshot.legacyWebViewBootstrapCalls, 1)
		XCTAssertEqual(recorder.snapshot.events.filter { $0.kind == .legacyBootstrap }.count, 1)
		XCTAssertEqual(recorder.snapshot.events.last?.kind, .contentFirstFramePresented)
	}

	func testTraceJSONRedactsURLAndAbsolutePathFromEventText() throws {
		let recorder = Babel2LaunchTraceRecorder(
			decision: Babel2FeatureGate.decision(buildChannel: .test),
			buildChannel: .test,
			gateUptime: 12,
			processEntryUptime: 11,
			sessionID: "privacy-session"
		)
		recorder.recordLegacyBootstrap(
			source: "fixture https://example.com/feed.xml",
			detail: "loaded /Users/example/feed/article"
		)
		let trace = recorder.snapshot
		let json = trace.structuredJSONLine
		XCTAssertFalse(json.contains("https://example.com/feed.xml"))
		XCTAssertFalse(json.contains("/Users/example/feed/article"))
		XCTAssertEqual(trace.events.last?.source, "fixture [redacted]")
		XCTAssertEqual(trace.events.last?.detail, "loaded [redacted]")
	}

	func testTraceRejectsInvalidEventIdentityOrderAndConfiguration() {
		let decision = Babel2FeatureGate.decision(buildChannel: .test)
		let surface = Babel2TraceSurface(controllerType: "Babel2NavigationController")
		let events = [
			Babel2LaunchTraceEvent(sessionID: "other-session", sequence: 1, uptime: 15, kind: .decision, source: "test"),
			Babel2LaunchTraceEvent(sessionID: "trace-session", sequence: 0, uptime: 14, kind: .processEntry, source: "test"),
			Babel2LaunchTraceEvent(sessionID: "trace-session", sequence: 2, uptime: 13, kind: .sceneConfigurationObserved, source: "test", configurationName: Babel2SceneConfiguration.name, storyboardPresent: true),
			Babel2LaunchTraceEvent(sessionID: "trace-session", sequence: 3, uptime: 16, kind: .sceneConfigurationSelected, source: "test", configurationName: Babel2SceneConfiguration.name),
			Babel2LaunchTraceEvent(sessionID: "trace-session", sequence: 4, uptime: 17, kind: .rootInstalled, source: "test", surface: surface),
			Babel2LaunchTraceEvent(sessionID: "trace-session", sequence: 5, uptime: 18, kind: .rootVisible, source: "test", surface: surface),
			Babel2LaunchTraceEvent(sessionID: "trace-session", sequence: 6, uptime: 19, kind: .containerAppeared, source: "test", surface: surface),
			Babel2LaunchTraceEvent(sessionID: "trace-session", sequence: 7, uptime: 20, kind: .contentFirstFramePresented, source: "test", surface: surface)
		]
		let trace = Babel2LaunchTrace(
			decision: decision,
			buildChannel: .test,
			gateUptime: 12,
			sessionID: "trace-session",
			events: events,
			processEntryUptime: 11,
			origin: "syntheticTest",
			bundleIdentifier: "test.bundle",
			bundleVersion: "1",
			bundleBuild: "1"
		)
		XCTAssertFalse(trace.isValid)
		XCTAssertTrue(trace.invalidReasons.contains(.eventSequenceInvalid))
		XCTAssertTrue(trace.invalidReasons.contains(.eventUptimeInvalid))
		XCTAssertTrue(trace.invalidReasons.contains(.eventSessionMismatch))
		XCTAssertTrue(trace.invalidReasons.contains(.eventOrderInvalid))
		XCTAssertTrue(trace.invalidReasons.contains(.decisionUptimeMismatch))
		XCTAssertTrue(trace.invalidReasons.contains(.sceneConfigurationStoryboardPresent))
		XCTAssertTrue(trace.invalidReasons.contains(.sceneConfigurationDelegateInvalid))
	}

	func testTraceRejectsInvalidProcessEntryAndDuplicateMilestones() {
		let invalidProcess = Babel2LaunchTraceRecorder(
			decision: Babel2FeatureGate.decision(buildChannel: .test),
			buildChannel: .test,
			gateUptime: 12,
			processEntryUptime: 13,
			sessionID: "invalid-process"
		)
		XCTAssertTrue(invalidProcess.snapshot.invalidReasons.contains(.processEntryEvidenceInvalid))
		XCTAssertFalse(invalidProcess.snapshot.isValid)

		let duplicate = completeTraceRecorder(sessionID: "duplicate-milestone")
		duplicate.recordRootVisible(surface: validTraceSurface())
		XCTAssertTrue(duplicate.snapshot.invalidReasons.contains(.launchMilestoneDuplicate))
		XCTAssertFalse(duplicate.snapshot.isValid)
	}

	func testTraceRequiresValidSurfaceEvidenceForVisibleMilestones() {
		let decision = Babel2FeatureGate.decision(buildChannel: .test)
		let invalidSurface = Babel2TraceSurface(
			controllerType: "Babel2NavigationController",
			windowBounds: Babel2TraceRect(x: 0, y: 0, width: 0, height: 844),
			rootBounds: Babel2TraceRect(x: 0, y: 0, width: 390, height: 844),
			rootFrame: Babel2TraceRect(x: 0, y: 0, width: 390, height: 844),
			contentBounds: Babel2TraceRect(x: 0, y: 0, width: 390, height: 844),
			contentFrame: Babel2TraceRect(x: 0, y: 0, width: 390, height: 844),
			safeAreaInsets: Babel2TraceInsets(top: -1, left: 0, bottom: 34, right: 0),
			windowIsHidden: false,
			windowIsKey: true
		)
		let events = [
			Babel2LaunchTraceEvent(sessionID: "surface-session", sequence: 0, uptime: 11, kind: .processEntry, source: "test"),
			Babel2LaunchTraceEvent(sessionID: "surface-session", sequence: 1, uptime: 12, kind: .decision, source: "test"),
			Babel2LaunchTraceEvent(sessionID: "surface-session", sequence: 2, uptime: 13, kind: .sceneConfigurationSelected, source: "test", configurationName: Babel2SceneConfiguration.name),
			Babel2LaunchTraceEvent(sessionID: "surface-session", sequence: 3, uptime: 14, kind: .sceneConfigurationObserved, source: "test", configurationName: Babel2SceneConfiguration.name, storyboardPresent: false, delegateClassName: "SceneDelegate", delegateMatchesExpected: true),
			Babel2LaunchTraceEvent(sessionID: "surface-session", sequence: 4, uptime: 15, kind: .rootInstalled, source: "test", surface: validTraceSurface()),
			Babel2LaunchTraceEvent(sessionID: "surface-session", sequence: 5, uptime: 16, kind: .rootVisible, source: "test", surface: invalidSurface),
			Babel2LaunchTraceEvent(sessionID: "surface-session", sequence: 6, uptime: 17, kind: .containerAppeared, source: "test", surface: validTraceSurface()),
			Babel2LaunchTraceEvent(sessionID: "surface-session", sequence: 7, uptime: 18, kind: .contentFirstFramePresented, source: "test", surface: validTraceSurface())
		]
		let trace = Babel2LaunchTrace(
			decision: decision,
			buildChannel: .test,
			gateUptime: 12,
			sessionID: "surface-session",
			events: events,
			processEntryUptime: 11,
			origin: "syntheticTest",
			bundleIdentifier: "test.bundle",
			bundleVersion: "1",
			bundleBuild: "1"
		)
		XCTAssertTrue(trace.invalidReasons.contains(.launchMilestoneSurfaceInvalid))
		XCTAssertFalse(trace.isValid)
	}

	func testTraceRejectsSurfaceWithWrongRootIdentity() {
		let surface = Babel2TraceSurface(
			controllerType: "Babel2NavigationController",
			windowBounds: Babel2TraceRect(x: 0, y: 0, width: 390, height: 844),
			rootBounds: Babel2TraceRect(x: 0, y: 0, width: 390, height: 844),
			rootFrame: Babel2TraceRect(x: 0, y: 0, width: 390, height: 844),
			contentBounds: Babel2TraceRect(x: 0, y: 0, width: 390, height: 844),
			contentFrame: Babel2TraceRect(x: 0, y: 0, width: 390, height: 844),
			safeAreaInsets: Babel2TraceInsets(top: 59, left: 0, bottom: 34, right: 0),
			windowIsHidden: false,
			windowIsKey: true,
			rootMatchesExpected: false
		)
		let recorder = completeTraceRecorder(sessionID: "wrong-root")
		recorder.recordRootInstalled(surface: surface)
		XCTAssertTrue(recorder.snapshot.invalidReasons.contains(.launchMilestoneDuplicate))
		XCTAssertTrue(recorder.snapshot.invalidReasons.contains(.launchMilestoneSurfaceInvalid))
		XCTAssertFalse(recorder.snapshot.isValid)
	}

	func testBabel2NavigationHasOneGenerationAndRestorationWritesBabel2() {
		let navigation = Babel2SceneComposition.makeRoot()
		XCTAssertEqual(navigation.generation, .babel2)
		XCTAssertEqual(navigation.restorationValue().generation, .babel2)
	}

	func testMissingObservedSceneConfigurationIsNotSynthesized() {
		let recorder = Babel2LaunchTraceRecorder(
			decision: Babel2FeatureGate.decision(buildChannel: .test),
			buildChannel: .test,
			gateUptime: 12,
			processEntryUptime: 11,
			sessionID: "missing-scene-config"
		)
		recorder.recordSceneConfigurationSelected(Babel2SceneConfiguration.name)
		recorder.recordSceneConfigurationObserved(name: nil, delegateClassName: "SceneDelegate", delegateMatchesExpected: true, storyboardPresent: false)
		XCTAssertEqual(recorder.snapshot.selectedSceneConfigurationName, Babel2SceneConfiguration.name)
		XCTAssertNil(recorder.snapshot.observedSceneConfigurationName)
		XCTAssertFalse(recorder.snapshot.invalidReasons.contains(.sceneConfigurationNameMissing))
		XCTAssertFalse(recorder.snapshot.isComplete)
		XCTAssertFalse(recorder.snapshot.isValid)
		XCTAssertFalse(recorder.snapshot.events.contains { $0.configurationName == Babel2SceneConfiguration.name && $0.kind == .sceneConfigurationObserved })
	}

	func testTraceAllowsNilReturnedConfigurationNameWithExactLookupEvidence() {
		let trace = completeTraceRecorder(sessionID: "nil-returned-name", observedConfigurationName: nil).snapshot
		XCTAssertEqual(trace.selectedSceneConfigurationLookupName, Babel2SceneConfiguration.name)
		XCTAssertNil(trace.observedSceneConfigurationName)
		XCTAssertNil(trace.events.first(where: { $0.kind == .sceneConfigurationObserved })?.configurationNameMatchesExpected)
		XCTAssertFalse(trace.invalidReasons.contains(.sceneConfigurationNameMissing))
		XCTAssertTrue(trace.isValid)
	}

	func testTraceRejectsWrongReturnedConfigurationNameWithoutLeakingIt() throws {
		let recorder = completeTraceRecorder(
			sessionID: "wrong-returned-name",
			observedConfigurationName: "https://private.example/scene-config"
		)
		let trace = recorder.snapshot
		XCTAssertNil(trace.observedSceneConfigurationName)
		XCTAssertEqual(trace.events.first(where: { $0.kind == .sceneConfigurationObserved })?.configurationNameMatchesExpected, false)
		XCTAssertTrue(trace.invalidReasons.contains(.sceneConfigurationMismatch))
		XCTAssertFalse(trace.isValid)
		XCTAssertFalse(trace.structuredJSONLine.contains("private.example"))
	}

	func testTraceRequiresActualDelegateIdentityEvidence() {
		let recorder = Babel2LaunchTraceRecorder(
			decision: Babel2FeatureGate.decision(buildChannel: .test),
			buildChannel: .test,
			gateUptime: 12,
			processEntryUptime: 11,
			sessionID: "wrong-delegate-identity"
		)
		recorder.recordSceneConfigurationSelected(Babel2SceneConfiguration.name)
		recorder.recordSceneConfigurationObserved(
			name: nil,
			delegateClassName: "SceneDelegate",
			delegateMatchesExpected: false,
			storyboardPresent: false
		)
		XCTAssertTrue(recorder.snapshot.invalidReasons.contains(.sceneConfigurationDelegateInvalid))
		XCTAssertFalse(recorder.snapshot.isValid)
	}

	func testTraceRejectsWrongConfigurationLookupNameWithoutLeakingIt() {
		let trace = completeTraceRecorder(
			sessionID: "wrong-lookup-name",
			selectedConfigurationName: "/private/scene-lookup-token"
		).snapshot
		XCTAssertNil(trace.selectedSceneConfigurationLookupName)
		XCTAssertEqual(trace.events.first(where: { $0.kind == .sceneConfigurationSelected })?.configurationNameMatchesExpected, false)
		XCTAssertTrue(trace.invalidReasons.contains(.sceneConfigurationMismatch))
		XCTAssertFalse(trace.isValid)
		XCTAssertFalse(trace.structuredJSONLine.contains("scene-lookup-token"))
	}

	func testSceneConfigurationCannotInstantiateTheLegacyStoryboard() {
		let babel2 = Babel2SceneConfiguration.makeBabel2(for: .windowApplication)
		XCTAssertTrue(babel2.name == nil || babel2.name == Babel2SceneConfiguration.name)
		XCTAssertNil(babel2.storyboard)
		XCTAssertTrue(babel2.delegateClass === SceneDelegate.self)
	}

	func testRestorationRejectsWrongGenerationSchemaAndRoute() throws {
		let accepted = Babel2NavigationRestoration(routes: [.home])
		XCTAssertTrue(accepted.isValid)
		XCTAssertEqual(Babel2NavigationRestoration.decoded(try accepted.encoded()), accepted)
		XCTAssertEqual(Babel2NavigationRestoration.validated(try accepted.encoded()), accepted)

		let wrongGeneration = Babel2NavigationRestoration(generation: .legacy)
		XCTAssertEqual(Babel2NavigationRestoration.decoded(try wrongGeneration.encoded()), Babel2NavigationRestoration())
		XCTAssertNil(Babel2NavigationRestoration.validated(try wrongGeneration.encoded()))
		let wrongSchema = Babel2NavigationRestoration(schemaVersion: 99)
		XCTAssertEqual(Babel2NavigationRestoration.decoded(try wrongSchema.encoded()), Babel2NavigationRestoration())
		let wrongRoute = Babel2NavigationRestoration(routes: [.settings, .home])
		XCTAssertEqual(Babel2NavigationRestoration.decoded(try wrongRoute.encoded()), Babel2NavigationRestoration())
		let duplicateRoute = Babel2NavigationRestoration(routes: [.home, .settings, .settings])
		XCTAssertEqual(Babel2NavigationRestoration.decoded(try duplicateRoute.encoded()), Babel2NavigationRestoration())
	}

	func testCanonicalExternalParserAcceptsOnlyRegisteredTypedActions() throws {
		let unreadURL = try XCTUnwrap(URL(string: "nnw://showunread?id=article-1"))
		let feedURL = try XCTUnwrap(URL(string: "feed:https://example.com/feed.xml"))
		let themeURL = try XCTUnwrap(URL(string: "netnewswire://theme/add?url=https%3A%2F%2Fexample.com%2Ftheme.nnwtheme"))

		XCTAssertEqual(Babel2ExternalActionParser.parse(unreadURL), .showUnread(articleID: "article-1"))
		XCTAssertEqual(Babel2ExternalActionParser.parse(feedURL), .addFeed("https://example.com/feed.xml"))
		XCTAssertEqual(
			Babel2ExternalActionParser.parse(themeURL),
			.downloadTheme(try XCTUnwrap(URL(string: "https://example.com/theme.nnwtheme")))
		)
	}

	func testCanonicalExternalParserMakesLookalikesAndMalformedQueriesNoOp() throws {
		let inputs = [
			"NNW://showunread?id=article-1",
			"https://example.com/path/nnw://showunread?id=article-1",
			"nnw://showunread?id=article-1&unexpected=value",
			"nnw://showunread?id=",
			"netnewswire://theme/add",
			"netnewswire://theme/add?url=ftp%3A%2F%2Fexample.com%2Ftheme.nnwtheme",
			"netnewswire://theme/add?url=https%3A%2F%2Fuser%40example.com%2Ftheme.nnwtheme"
		]

		for input in inputs {
			XCTAssertNil(Babel2ExternalActionParser.parse(try XCTUnwrap(URL(string: input))), input)
		}
	}

	func testSceneDelegateExternalURLHandlerPassesTypedActionToExecutor() throws {
		let sceneDelegate = SceneDelegate()
		var executed = [Babel2LegacyURLAction]()
		sceneDelegate.externalActionExecutionObserverForTesting = { executed.append($0) }
		defer { sceneDelegate.externalActionExecutionObserverForTesting = nil }

		let feedURL = try XCTUnwrap(URL(string: "feed:https://example.com/handler-feed.xml"))
		let expected = Babel2LegacyURLAction.addFeed("https://example.com/handler-feed.xml")
		XCTAssertEqual(
			sceneDelegate.handleExternalActionURL(feedURL),
			expected
		)
		RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
		XCTAssertEqual(executed, [expected])
		let trace = appDelegate.launchTrace
		XCTAssertFalse(trace.events.contains { event in
			switch event.kind {
			case .legacyUILifecycle, .legacyBootstrap, .legacyStoryboardDecode, .legacySceneCoordinator, .legacyWebViewBootstrap:
				return true
			default:
				return false
			}
		}, "direct external-action handling must not add a legacy launch event")

		let malformed = try XCTUnwrap(URL(string: "nnw://showunread?id=one&id=two"))
		XCTAssertNil(sceneDelegate.handleExternalActionURL(malformed))
		RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
		XCTAssertEqual(executed, [expected], "unknown URL must be a typed no-op")
	}

	func testRunningAppDelegateAndSceneDelegateExposeOrderedLaunchTrace() throws {
		let trace = appDelegate.launchTrace
		XCTAssertFalse(trace.sessionID.isEmpty)
		XCTAssertEqual(trace.events.first?.kind, .processEntry)
		XCTAssertEqual(trace.events.dropFirst().first?.kind, .decision)
		XCTAssertTrue(trace.events.allSatisfy { $0.sessionID == trace.sessionID })
		XCTAssertEqual(trace.events.map(\.sequence), Array(0..<trace.events.count))
		if let configurationIndex = trace.events.firstIndex(where: { $0.kind == .sceneConfigurationSelected }) {
			XCTAssertLessThan(trace.events.firstIndex(where: { $0.kind == .decision })!, configurationIndex)
		}
		XCTAssertNotNil(trace.events.first(where: { $0.kind == .sceneConfigurationObserved }))

		let sceneDelegate = try XCTUnwrap(
			UIApplication.shared.connectedScenes.compactMap { $0.delegate as? SceneDelegate }.first
		)
		XCTAssertNotNil(sceneDelegate.window?.rootViewController)
		XCTAssertEqual(trace.generation, .babel2)
		XCTAssertTrue(trace.rootInstalled)
		XCTAssertTrue(trace.containerAppeared)
		XCTAssertTrue(trace.firstFramePresented)
		if trace.selectedSceneConfigurationLookupName == nil {
			XCTAssertFalse(trace.isComplete, "a test-host trace without the UIKit configuration callback is incomplete")
			XCTAssertFalse(trace.isValid, "a test-host trace without the UIKit configuration callback is invalid")
			XCTAssertTrue(trace.invalidReasons.contains(.sceneConfigurationSelectionMissing))
		} else {
			XCTAssertEqual(trace.selectedSceneConfigurationLookupName, Babel2SceneConfiguration.name)
			if let observedName = trace.observedSceneConfigurationName {
				XCTAssertEqual(observedName, Babel2SceneConfiguration.name)
			}
		}
		XCTAssertLessThanOrEqual(trace.processEntryUptime, trace.gateUptime)
		XCTAssertLessThanOrEqual(trace.gateUptime, trace.rootInstalledUptime!)
		XCTAssertLessThanOrEqual(trace.rootInstalledUptime!, trace.rootVisibleUptime!)
		XCTAssertLessThanOrEqual(trace.rootVisibleUptime!, trace.containerAppearedUptime!)
		XCTAssertLessThanOrEqual(trace.containerAppearedUptime!, trace.contentFirstFrameUptime!)
		let legacyEvents = trace.events.filter { event in
			switch event.kind {
			case .legacyUILifecycle, .legacyBootstrap, .legacyStoryboardDecode, .legacySceneCoordinator, .legacyWebViewBootstrap:
				return true
			default:
				return false
			}
		}
		XCTAssertTrue(legacyEvents.isEmpty, "the live Babel2 launch must contain no legacy event")
		XCTAssertFalse(trace.legacyLifecycleStarted)
		XCTAssertFalse(trace.legacyBootstrapStarted)
		XCTAssertEqual(trace.legacyStoryboardInstantiations, 0)
		XCTAssertEqual(trace.legacyCoordinatorCreations, 0)
		XCTAssertEqual(trace.legacyWebViewBootstrapCalls, 0)
	}

	func testRootCompositionCanBeReenteredThirtyTimesWithoutRetainedControllers() {
		var rootReferences = [Babel2WeakReference<Babel2RootViewController>]()
		var navigationReferences = [Babel2WeakReference<Babel2NavigationController>]()
		var previousLiveRootCount = 0
		var previousLiveNavigationCount = 0

		for cycle in 1...30 {
			autoreleasepool {
				do {
					let navigation = Babel2SceneComposition.makeRoot()
					let root = try! XCTUnwrap(navigation.viewControllers.first as? Babel2RootViewController)
					rootReferences.append(Babel2WeakReference(root))
					navigationReferences.append(Babel2WeakReference(navigation))
					navigation.tearDown()
				}
			}

			// UIKit may retain a transition/gesture/autorelease object until the
			// next main-run-loop turn. This bounded drain observes deallocation;
			// the weak-reference assertions below remain strict and are not a
			// substitute for teardown.
			RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
			let liveRootCount = rootReferences.filter { $0.value != nil }.count
			let liveNavigationCount = navigationReferences.filter { $0.value != nil }.count
			let rootDeinitCount = rootReferences.count - liveRootCount
			let navigationDeinitCount = navigationReferences.count - liveNavigationCount
			print("Babel2 lifecycle cycle=\(cycle) rootDeinitCount=\(rootDeinitCount) navigationDeinitCount=\(navigationDeinitCount) liveRootObjects=\(liveRootCount) liveNavigationObjects=\(liveNavigationCount)")
			XCTAssertEqual(rootDeinitCount, cycle)
			XCTAssertEqual(navigationDeinitCount, cycle)
			XCTAssertLessThanOrEqual(liveRootCount, previousLiveRootCount)
			XCTAssertLessThanOrEqual(liveNavigationCount, previousLiveNavigationCount)
			XCTAssertEqual(liveRootCount, 0)
			XCTAssertEqual(liveNavigationCount, 0)
			previousLiveRootCount = liveRootCount
			previousLiveNavigationCount = liveNavigationCount
		}
		print("Babel2 lifecycle final rootDeinitCount=\(rootReferences.count) navigationDeinitCount=\(navigationReferences.count) liveRootObjects=0 liveNavigationObjects=0")
	}

	func testRootHasFeedsTitleAndTwoReachableActions() {
		let navigation = Babel2SceneComposition.makeRoot()
		let root = try! XCTUnwrap(navigation.viewControllers.first as? Babel2RootViewController)
		root.loadViewIfNeeded()
		root.view.layoutIfNeeded()
		let labels = root.view.subviews.compactMap { $0 as? UILabel }
		XCTAssertTrue(labels.contains { $0.text == "Feeds" || $0.text == "订阅源" })
		let settings = try! XCTUnwrap(root.view.subviews.compactMap { $0 as? UIButton }.first { $0.accessibilityIdentifier == "babel2.settings" })
		let add = try! XCTUnwrap(root.view.subviews.compactMap { $0 as? UIButton }.first { $0.accessibilityIdentifier == "babel2.add" })
		XCTAssertNotNil(settings)
		XCTAssertNotNil(add)
		for identifier in ["babel2.scope.all", "babel2.scope.unread", "babel2.scope.starred"] {
			let scope = try! XCTUnwrap(babel2View(in: root.view, accessibilityIdentifier: identifier) as? UIButton)
			XCTAssertGreaterThanOrEqual(scope.frame.width, 44)
			XCTAssertEqual(scope.frame.height, 44)
		}
		settings.sendActions(for: .touchUpInside)
		XCTAssertEqual(navigation.viewControllers.count, 2)
		XCTAssertEqual(navigation.restorationValue().routes, [.home, .settings])
		navigation.popBabel2(animated: false)
		add.sendActions(for: .touchUpInside)
		XCTAssertEqual(navigation.restorationValue().routes, [.home, .addSubscription])
	}

	private func babel2View(in view: UIView, accessibilityIdentifier: String) -> UIView? {
		if view.accessibilityIdentifier == accessibilityIdentifier { return view }
		for child in view.subviews {
			if let match = babel2View(in: child, accessibilityIdentifier: accessibilityIdentifier) { return match }
		}
		return nil
	}

	func testPlaceholderRoutesRestoreAndNavigationOwnerPopsQuickly() {
		let navigation = Babel2SceneComposition.makeRoot(
			restoration: Babel2NavigationRestoration(routes: [.home, .settings])
		)
		XCTAssertEqual(navigation.viewControllers.count, 2)
		XCTAssertEqual(navigation.restorationValue().routes, [.home, .settings])
		XCTAssertNotNil(navigation.popBabel2(animated: false))
		XCTAssertNil(navigation.popBabel2(animated: false))
		XCTAssertEqual(navigation.viewControllers.count, 1)
	}

	func testBabel2ResourcesContainBilingualKeysAndThreeIconAppearances() throws {
		let projectRoot = URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.deletingLastPathComponent()
		let resourceURL = projectRoot.appendingPathComponent("iOS/Babel2/Resources/Babel2Localizable.xcstrings")
		let resource = try JSONSerialization.jsonObject(with: Data(contentsOf: resourceURL)) as! [String: Any]
		let strings = resource["strings"] as! [String: Any]
		for key in ["Feeds", "Settings", "Add", "Not available yet", "OK"] {
			let entry = strings[key] as! [String: Any]
			let localizations = entry["localizations"] as! [String: Any]
			XCTAssertNotNil(localizations["en"])
			XCTAssertNotNil(localizations["zh-Hans"])
		}

		let iconContentsURL = projectRoot.appendingPathComponent("iOS/Babel2/Assets.xcassets/AppIcon.appiconset/Contents.json")
		let iconContents = try JSONSerialization.jsonObject(with: Data(contentsOf: iconContentsURL)) as! [String: Any]
		let images = iconContents["images"] as! [[String: Any]]
		XCTAssertEqual(Set(images.compactMap { $0["filename"] as? String }), Set(["Babel2AppIcon-Light.png", "Babel2AppIcon-Dark.png", "Babel2AppIcon-Mono.png"]))
		XCTAssertTrue(images.contains { ($0["appearances"] as? [[String: String]])?.first?["value"] == "dark" })
		XCTAssertTrue(images.contains { ($0["appearances"] as? [[String: String]])?.first?["value"] == "tinted" })
	}
}

@MainActor
private func completeTraceRecorder(
	sessionID: String,
	includeContentFirstFrame: Bool = true,
	observedConfigurationName: String? = Babel2SceneConfiguration.name,
	selectedConfigurationName: String? = Babel2SceneConfiguration.name
) -> Babel2LaunchTraceRecorder {
	let recorder = Babel2LaunchTraceRecorder(
		decision: Babel2FeatureGate.decision(buildChannel: .test),
		buildChannel: .test,
		gateUptime: 12,
		processEntryUptime: 11,
		sessionID: sessionID,
		origin: "fixture-origin",
		bundleIdentifier: "fixture.bundle",
		bundleVersion: "1",
		bundleBuild: "1"
	)
	recorder.recordSceneConfigurationSelected(selectedConfigurationName)
	recorder.recordSceneConfigurationObserved(
		name: observedConfigurationName,
		delegateClassName: "SceneDelegate",
		delegateMatchesExpected: true,
		storyboardPresent: false
	)
	let surface = validTraceSurface()
	recorder.recordRootInstalled(surface: surface)
	recorder.recordRootVisible(surface: surface)
	recorder.recordContainerAppeared(surface: surface)
	if includeContentFirstFrame {
		recorder.recordContentFirstFramePresented(surface: surface)
	}
	return recorder
}

private func validTraceSurface() -> Babel2TraceSurface {
	let bounds = Babel2TraceRect(x: 0, y: 0, width: 390, height: 844)
	return Babel2TraceSurface(
		controllerType: "Babel2NavigationController",
		contentType: "UIView",
		windowBounds: bounds,
		rootBounds: bounds,
		rootFrame: bounds,
		contentBounds: bounds,
		contentFrame: bounds,
		safeAreaInsets: Babel2TraceInsets(top: 59, left: 0, bottom: 34, right: 0),
		windowIsHidden: false,
		windowIsKey: true,
		rootMatchesExpected: true
	)
}

private func projectSource(named relativePath: String) throws -> String {
	let projectRoot = URL(fileURLWithPath: #filePath)
		.deletingLastPathComponent()
		.deletingLastPathComponent()
		.deletingLastPathComponent()
	return try String(contentsOf: projectRoot.appendingPathComponent(relativePath), encoding: .utf8)
}
