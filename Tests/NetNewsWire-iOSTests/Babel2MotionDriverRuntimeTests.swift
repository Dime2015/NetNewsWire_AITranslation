import XCTest
import UIKit
import Babel2Core
@testable import Babel2UI

@MainActor
private final class Babel2RuntimeRecorder: Babel2MotionRecording {
	private(set) var events: [MotionSignpostEvent] = []

	func record(_ event: MotionSignpostEvent) {
		events.append(event)
	}
}

@MainActor
private final class Babel2RuntimeSignpostBackend: Babel2SignpostBackend {
	enum Operation: Equatable {
		case begin(MotionSignpostName)
		case event(MotionSignpostName)
		case end(MotionSignpostName)
	}

	private(set) var operations: [Operation] = []
	private(set) var payloads: [String] = []

	func begin(name: MotionSignpostName, payload: String) {
		operations.append(.begin(name))
		payloads.append(payload)
	}
	func event(name: MotionSignpostName, payload: String) {
		operations.append(.event(name))
		payloads.append(payload)
	}
	func end(name: MotionSignpostName, payload: String) {
		operations.append(.end(name))
		payloads.append(payload)
	}
}

@MainActor
private final class Babel2RuntimeFakeAnimator: Babel2Animator {
	private let animations: () -> Void
	private var completion: (() -> Void)?
	var fractionComplete: CGFloat = 0

	init(animations: @escaping () -> Void) {
		self.animations = animations
	}

	func startAnimation() { animations() }
	func stopAnimation(withoutFinishing: Bool) {}
	func addCompletion(_ completion: @escaping () -> Void) { self.completion = completion }
	func complete() {
		fractionComplete = 1
		completion?()
	}
}

@MainActor
private final class Babel2RuntimeFakeAnimatorFactory: Babel2AnimatorFactory {
	private(set) var created: [Babel2RuntimeFakeAnimator] = []

	func make(duration: TimeInterval, animations: @escaping () -> Void) -> any Babel2Animator {
		let animator = Babel2RuntimeFakeAnimator(animations: animations)
		created.append(animator)
		return animator
	}
}

@MainActor
final class Babel2MotionDriverRuntimeTests: XCTestCase {
	func testRealAnimatorBeginUpdateFinishReachesSettledState() async {
		let renderHost = UIViewController()
		let renderWindow = UIWindow(frame: UIScreen.main.bounds)
		renderWindow.rootViewController = renderHost
		renderWindow.makeKeyAndVisible()
		let renderProbe = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 10))
		renderHost.view.addSubview(renderProbe)
		let driver = Babel2MotionDriver(renderer: { progress in
			renderProbe.alpha = 1 - CGFloat(progress.value)
		})
		let token = driver.begin(
			interaction: .navigationPop,
			route: MotionRouteIdentity(id: "runtime.reader", generation: 1),
			recognizer: "runtime.edgePan"
		)

		XCTAssertTrue(driver.update(token: token, progress: .quarter))
		XCTAssertEqual(driver.finish(token: token, duration: 0.12), .started)
		await waitForTerminal(driver)

		XCTAssertEqual(driver.state, .settled(progress: .one, outcome: .finished))
		XCTAssertEqual(driver.state.terminalOutcome, .finished)
	}

	func testRealAnimatorSettlingInterruptSamplesAndSupportsReverse() async {
		let renderHost = UIViewController()
		let renderWindow = UIWindow(frame: UIScreen.main.bounds)
		renderWindow.rootViewController = renderHost
		renderWindow.makeKeyAndVisible()
		let renderProbe = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 10))
		renderHost.view.addSubview(renderProbe)
		let driver = Babel2MotionDriver(renderer: { progress in
			renderProbe.alpha = 1 - CGFloat(progress.value)
		})
		let original = driver.begin(
			interaction: .verticalArticlePager,
			route: MotionRouteIdentity(id: "runtime.reader", generation: 1),
			recognizer: "runtime.articlePan"
		)

		XCTAssertTrue(driver.update(token: original, progress: .quarter))
		XCTAssertEqual(driver.finish(token: original, duration: 0.18), .started)
		XCTAssertTrue(driver.state.isSettling)

		let replacement = driver.begin(
			interaction: .readerToBrowser,
			route: MotionRouteIdentity(id: "runtime.browser", generation: 2),
			recognizer: "runtime.browserPan"
		)
		XCTAssertNotEqual(replacement, original)
		XCTAssertEqual(replacement.route, MotionRouteIdentity(id: "runtime.browser", generation: 2))
		XCTAssertGreaterThanOrEqual(driver.state.progress.value, MotionProgress.quarter.value)

		XCTAssertTrue(driver.update(token: replacement, progress: .zero))
		XCTAssertEqual(driver.state, .tracking(progress: .zero))
		XCTAssertEqual(driver.cancel(token: replacement, duration: 0.12), .started)
		await waitForTerminal(driver)
		XCTAssertEqual(driver.state, .cancelled(progress: .zero))
	}

	func testRealAnimatorCancelIsTerminalAndFinishCancelAreMutuallyExclusive() async {
		let renderHost = UIViewController()
		let renderWindow = UIWindow(frame: UIScreen.main.bounds)
		renderWindow.rootViewController = renderHost
		renderWindow.makeKeyAndVisible()
		let renderProbe = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 10))
		renderHost.view.addSubview(renderProbe)
		let driver = Babel2MotionDriver(renderer: { progress in
			renderProbe.alpha = 1 - CGFloat(progress.value)
		})
		let token = driver.begin(interaction: .readerToBrowser)

		XCTAssertEqual(driver.cancel(token: token, duration: 0.12), .started)
		XCTAssertEqual(driver.finish(token: token), .alreadySettling(.cancelled))
		XCTAssertEqual(driver.cancel(token: token), .alreadySettling(.cancelled))
		await waitForTerminal(driver)

		XCTAssertTrue(driver.state.isTerminal)
		XCTAssertNotEqual(driver.state, .idle)
		XCTAssertEqual(driver.finish(token: token), .alreadyTerminal(.cancelled))
	}

	func testRealDriverRejectsStaleRouteToken() {
		let driver = Babel2MotionDriver(renderer: { _ in })
		let readerRoute = MotionRouteIdentity(id: "runtime.reader", generation: 10)
		let browserRoute = MotionRouteIdentity(id: "runtime.browser", generation: 11)
		let first = driver.begin(interaction: .readerTitleCollapse, route: readerRoute)
		let second = driver.begin(interaction: .readerToBrowser, route: browserRoute)

		XCTAssertNotEqual(first, second)
		XCTAssertFalse(driver.update(token: first, progress: .one))
		XCTAssertEqual(driver.finish(token: first), .ignored)
		XCTAssertTrue(driver.update(token: second, progress: .half))
		XCTAssertEqual(driver.state, .tracking(progress: .half))
	}

	func testRealDriverRejectsNonfiniteInputsBeforeAnyStateChange() {
		var renderCount = 0
		let driver = Babel2MotionDriver(renderer: { _ in renderCount += 1 })
		let token = driver.begin(interaction: .readerToBrowser)
		XCTAssertTrue(driver.update(token: token, progress: .half))
		let stateBefore = driver.state
		let renderCountBefore = renderCount

		XCTAssertEqual(driver.update(token: token, rawProgress: .nan), .rejected)
		XCTAssertEqual(driver.update(token: token, rawProgress: .infinity), .rejected)
		XCTAssertEqual(driver.update(token: token, rawProgress: -.infinity), .rejected)
		XCTAssertEqual(driver.end(token: token, velocity: .nan), .rejected)
		XCTAssertEqual(driver.end(token: token, velocity: .infinity), .rejected)
		XCTAssertEqual(driver.end(token: token, extent: .nan), .rejected)
		XCTAssertEqual(driver.end(token: token, extent: .infinity), .rejected)
		XCTAssertEqual(driver.end(token: token, duration: .nan), .rejected)
		XCTAssertEqual(driver.finish(token: token, duration: .infinity), .rejected)

		XCTAssertEqual(driver.state, stateBefore)
		XCTAssertEqual(renderCount, renderCountBefore)
	}

	func testFakeAnimatorExecutesRendererAndIgnoresRepeatedCompletion() throws {
		let factory = Babel2RuntimeFakeAnimatorFactory()
		var renders: [MotionProgress] = []
		let driver = Babel2MotionDriver(
			renderer: { renders.append($0) },
			recorder: Babel2NullMotionRecorder(),
			animatorFactory: factory
		)
		let first = driver.begin(interaction: .navigationPop)
		XCTAssertTrue(driver.update(token: first, progress: .quarter))
		XCTAssertEqual(driver.finish(token: first, duration: 1), .started)
		XCTAssertEqual(factory.created.count, 1)
		XCTAssertTrue(renders.contains(.one), "the fake animator must execute the renderer closure")

		factory.created[0].complete()
		XCTAssertEqual(driver.state, .settled(progress: .one, outcome: .finished))
		factory.created[0].complete()
		XCTAssertEqual(driver.state, .settled(progress: .one, outcome: .finished))
	}

	func testRealInterruptRecorderContainsRouteAndOldNewTokenPayload() async throws {
		let recorder = Babel2RuntimeRecorder()
		let renderHost = UIViewController()
		let renderWindow = UIWindow(frame: UIScreen.main.bounds)
		renderWindow.rootViewController = renderHost
		renderWindow.makeKeyAndVisible()
		let renderProbe = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 10))
		renderHost.view.addSubview(renderProbe)
		let driver = Babel2MotionDriver(renderer: { progress in
			renderProbe.alpha = 1 - CGFloat(progress.value)
		}, recorder: recorder)
		let first = driver.begin(
			interaction: .verticalArticlePager,
			route: MotionRouteIdentity(id: "runtime.reader", generation: 3),
			recognizer: "runtime.articlePan"
		)
		XCTAssertTrue(driver.update(token: first, progress: .quarter))
		XCTAssertEqual(driver.finish(token: first, duration: 0.18), .started)
		XCTAssertTrue(driver.state.isSettling)

		let second = driver.begin(
			interaction: .readerToBrowser,
			route: MotionRouteIdentity(id: "runtime.browser", generation: 4),
			recognizer: "runtime.browserPan"
		)
		let interrupt = try XCTUnwrap(recorder.events.last { $0.name == .interrupt })
		XCTAssertEqual(interrupt.oldToken, first)
		XCTAssertEqual(interrupt.newToken, second)
		XCTAssertEqual(interrupt.route, second.route)
		XCTAssertEqual(interrupt.recognizer, "runtime.browserPan")
		XCTAssertNotNil(interrupt.sampledProgress)
		XCTAssertTrue(interrupt.diagnosticPayload.contains("route=runtime.browser"))
		XCTAssertTrue(interrupt.diagnosticPayload.contains("routeGeneration=4"))
		XCTAssertTrue(interrupt.diagnosticPayload.contains("oldToken=reader.articlePager:runtime.reader:3:1"))
		XCTAssertTrue(interrupt.diagnosticPayload.contains("newToken=reader.browser:runtime.browser:4:2"))
		let settleEvents = recorder.events.filter { $0.name == .settle }
		XCTAssertEqual(settleEvents.map(\.phase), [.begin, .end])
		XCTAssertEqual(settleEvents.first?.duration, 0.2)
		XCTAssertEqual(recorder.events.map(\.name), [
			.begin, .track, .track, .track, .settle, .settle, .interrupt, .begin, .track
		])
		XCTAssertEqual(recorder.events[6].oldToken, first)
		XCTAssertEqual(recorder.events[6].newToken, second)
		XCTAssertEqual(recorder.events[7].token, second)
		XCTAssertEqual(recorder.events[8].token, second)

		XCTAssertEqual(driver.cancel(token: second, duration: 0.12), .started)
		await waitForTerminal(driver)
	}

	func testOSLogRecorderBackendMapsIntervalPhases() {
		let backend = Babel2RuntimeSignpostBackend()
		let recorder = Babel2OSLogMotionRecorder(backend: backend)
		recorder.record(MotionSignpostEvent(baseName: .settle, phase: .begin))
		recorder.record(MotionSignpostEvent(baseName: .settle, phase: .event))
		recorder.record(MotionSignpostEvent(baseName: .settle, phase: .end))
		recorder.record(MotionSignpostEvent(
		payload: .loading(.init(surface: .article, owner: .articleSkeleton, state: .active))
		))
		let token = MotionInteractionToken(
			interaction: .readerToBrowser,
			route: MotionRouteIdentity(id: "runtime.library", generation: 1),
			sequence: 1
		)
		recorder.record(MotionSignpostEvent(
			payload: .libraryFilter(.init(fromFilter: .unread, toFilter: .starred, pFilter: .half, token: token))
		))

		XCTAssertEqual(backend.operations, [
			.begin(.settle),
			.event(.settle),
			.end(.settle),
			.event(.loadingOwner),
			.event(.libraryFilter)
		])
		XCTAssertTrue(backend.payloads.last?.contains("fromFilter:unread,toFilter:starred,pFilter:0.5") == true)
	}

	private func waitForTerminal(_ driver: Babel2MotionDriver) async {
		let terminal = expectation(description: "Babel2 motion reaches terminal state")
		for _ in 0..<200 {
			if driver.state.isTerminal {
				terminal.fulfill()
				break
			}
			try? await Task.sleep(nanoseconds: 10_000_000)
		}
		await fulfillment(of: [terminal], timeout: 0.1)
	}
}
