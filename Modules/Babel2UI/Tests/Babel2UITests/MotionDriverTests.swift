#if canImport(UIKit)
import UIKit
import Testing
@testable import Babel2Core
@testable import Babel2UI

@MainActor
private final class TestAnimator: Babel2Animator {
	var fractionComplete: CGFloat = 0
	private let animations: () -> Void
	private(set) var started = false
	private(set) var stoppedWithoutFinishing = false
	private var completion: (() -> Void)?

	init(animations: @escaping () -> Void) {
		self.animations = animations
	}

	func startAnimation() {
		started = true
		animations()
	}

	func stopAnimation(withoutFinishing: Bool) {
		stoppedWithoutFinishing = withoutFinishing
	}

	func addCompletion(_ completion: @escaping () -> Void) {
		self.completion = completion
	}

	func complete() {
		fractionComplete = 1
		completion?()
	}
}

@MainActor
private final class TestAnimatorFactory: Babel2AnimatorFactory {
	private(set) var created: [TestAnimator] = []

	func make(duration: TimeInterval, animations: @escaping () -> Void) -> any Babel2Animator {
		let animator = TestAnimator(animations: animations)
		created.append(animator)
		return animator
	}
}

@MainActor
private final class TestRecorder: Babel2MotionRecording {
	private(set) var events: [MotionSignpostEvent] = []

	func record(_ event: MotionSignpostEvent) {
		events.append(event)
	}
}

@Suite struct MotionDriverTests {
	@Test @MainActor func updateNeverCreatesAnimatorAndClampsProgress() {
		let factory = TestAnimatorFactory()
		let recorder = TestRecorder()
		var renders: [MotionProgress] = []
		let driver = Babel2MotionDriver(
			renderer: { renders.append($0) },
			recorder: recorder,
			animatorFactory: factory
		)

		let token = driver.begin(interaction: .navigationPop)
		#expect(driver.update(token: token, rawProgress: 2) == .accepted)
		#expect(driver.state == .tracking(progress: .one))
		#expect(factory.created.isEmpty)
		#expect(renders.last == .one)
		#expect(recorder.events.map(\.name) == [.begin, .track, .track])
		#expect(recorder.events.map(\.phase) == [.begin, .begin, .event])
	}

	@Test @MainActor func nonFiniteExternalInputsAreRejectedBeforeRenderingOrAnimating() {
		let factory = TestAnimatorFactory()
		var renders: [MotionProgress] = []
		let driver = Babel2MotionDriver(
			renderer: { renders.append($0) },
			recorder: Babel2NullMotionRecorder(),
			animatorFactory: factory
		)
		let token = driver.begin(interaction: .readerToBrowser)
		#expect(driver.update(token: token, progress: .half))
		let stateBefore = driver.state
		let renderCountBefore = renders.count
		#expect(driver.update(token: token, rawProgress: .nan) == .rejected)
		#expect(driver.update(token: token, rawProgress: .infinity) == .rejected)
		#expect(driver.update(token: token, rawProgress: -.infinity) == .rejected)
		#expect(driver.state == stateBefore)
		#expect(renders.count == renderCountBefore)
		#expect(driver.end(token: token, velocity: .nan) == .rejected)
		#expect(driver.end(token: token, velocity: .infinity) == .rejected)
		#expect(driver.end(token: token, extent: .nan) == .rejected)
		#expect(driver.end(token: token, extent: .infinity) == .rejected)
		#expect(driver.end(token: token, extent: -.infinity) == .rejected)
		#expect(driver.end(token: token, duration: .nan) == .rejected)
		#expect(driver.end(token: token, duration: .infinity) == .rejected)
		#expect(driver.finish(token: token, duration: .nan) == .rejected)
		#expect(driver.cancel(token: token, duration: -.infinity) == .rejected)
		#expect(driver.state == stateBefore)
		#expect(factory.created.isEmpty)
	}

	@Test @MainActor func finishAndCancelAreMutuallyExclusive() {
		let factory = TestAnimatorFactory()
		let driver = Babel2MotionDriver(
			renderer: { _ in },
			recorder: Babel2NullMotionRecorder(),
			animatorFactory: factory
		)
		let token = driver.begin(interaction: .readerToBrowser)
		#expect(driver.update(token: token, progress: .quarter))
		#expect(driver.finish(token: token, duration: 0.2) == .started)
		#expect(driver.cancel(token: token, duration: 0.2) == .alreadySettling(.finished))
		#expect(factory.created.count == 1)
		#expect(driver.state == .settlingToEnd(progress: .quarter))

		factory.created[0].complete()
		#expect(driver.state == .settled(progress: .one, outcome: .finished))
		#expect(driver.token == nil)
		#expect(driver.finish(token: token) == .alreadyTerminal(.finished))
	}

	@Test @MainActor func cancelCompletionIsDistinctFromIdleAndFinishIsIdempotent() {
		let factory = TestAnimatorFactory()
		let driver = Babel2MotionDriver(
			renderer: { _ in },
			recorder: Babel2NullMotionRecorder(),
			animatorFactory: factory
		)
		let token = driver.begin(interaction: .navigationPop)
		#expect(driver.cancel(token: token) == .started)
		#expect(driver.state == .settlingToStart(progress: .zero))
		#expect(driver.finish(token: token) == .alreadySettling(.cancelled))
		factory.created[0].complete()
		#expect(driver.state == .cancelled(progress: .zero))
		#expect(driver.state.isTerminal)
		#expect(driver.state != .idle)
		#expect(driver.cancel(token: token) == .alreadyTerminal(.cancelled))
	}

	@Test @MainActor func endUsesBoundedProjectionAndBrowserDirection() {
		let factory = TestAnimatorFactory()
		let recorder = TestRecorder()
		let driver = Babel2MotionDriver(
			renderer: { _ in },
			recorder: recorder,
			animatorFactory: factory
		)
		let token = driver.begin(interaction: .readerToBrowser)
		#expect(driver.update(token: token, progress: .quarter))
		#expect(driver.end(
			token: token,
			velocity: -500,
			extent: 1_000,
			direction: .negative
		) == .started)
		#expect(driver.state == .settlingToStart(progress: .quarter))
		#expect(recorder.events.last?.projectedProgress == MotionProgress(0.325))
		factory.created[0].complete()
		#expect(driver.state == .cancelled(progress: .zero))
	}

	@Test @MainActor func interruptSamplesAnimatorAndAllowsFastReverse() throws {
		let factory = TestAnimatorFactory()
		var renders: [MotionProgress] = []
		let driver = Babel2MotionDriver(
			renderer: { renders.append($0) },
			recorder: Babel2NullMotionRecorder(),
			animatorFactory: factory
		)
		let token = driver.begin(interaction: .verticalArticlePager)
		#expect(driver.update(token: token, progress: .quarter))
		#expect(driver.finish(token: token, duration: 1) == .started)
		factory.created[0].fractionComplete = 0.5
		let replacement = driver.interrupt(token: token, newIntent: .readerToBrowser)
		#expect(replacement != nil)
		#expect(replacement != token)
		#expect(factory.created[0].stoppedWithoutFinishing)
		#expect(driver.state == .tracking(progress: MotionProgress(0.625)))
		#expect(renders.last == MotionProgress(0.625))
		#expect(!driver.update(token: token, progress: .threeQuarters))
		let active = try #require(replacement)
		#expect(driver.update(token: active, progress: .threeQuarters))
		#expect(driver.cancel(token: active, duration: 0.1) == .started)
		#expect(driver.state == .settlingToStart(progress: .threeQuarters))
		factory.created[1].complete()
		#expect(driver.state == .cancelled(progress: .zero))
		#expect(renders.last == .zero)
	}

	@Test @MainActor func resetStopsOwnershipAndCanBeginAgain() {
		let factory = TestAnimatorFactory()
		let driver = Babel2MotionDriver(
			renderer: { _ in },
			recorder: Babel2NullMotionRecorder(),
			animatorFactory: factory
		)
		let first = driver.begin(interaction: .feedHero)
		#expect(driver.finish(token: first) == .started)
		driver.reset()
		#expect(driver.state == .idle)
		#expect(driver.token == nil)
		let second = driver.begin(interaction: .feedHero)
		#expect(second.sequence > first.sequence)
		#expect(second != first)
	}

	@Test @MainActor func beginDuringSettlingSamplesAndCreatesNewToken() {
		let factory = TestAnimatorFactory()
		var renders: [MotionProgress] = []
		let recorder = TestRecorder()
		let driver = Babel2MotionDriver(
			renderer: { renders.append($0) },
			recorder: recorder,
			animatorFactory: factory
		)
		let first = driver.begin(interaction: .navigationPop, route: MotionRouteIdentity(id: "reader", generation: 1))
		#expect(driver.update(token: first, progress: .quarter))
		#expect(driver.finish(token: first, duration: 1) == .started)
		factory.created[0].fractionComplete = 0.25
		let second = driver.begin(interaction: .readerToBrowser, route: MotionRouteIdentity(id: "browser", generation: 2))
		#expect(second.sequence > first.sequence)
		#expect(second.route.id == "browser")
		#expect(driver.state == .tracking(progress: MotionProgress(0.4375)))
		#expect(!driver.update(token: first, progress: .one))
		#expect(recorder.events.last?.oldToken == first)
		#expect(recorder.events.last?.newToken == second)
		#expect(recorder.events.last?.sampledProgress == MotionProgress(0.4375))
		#expect(renders.last == MotionProgress(0.4375))
		#expect(recorder.events.map(\.name) == [
			.begin, .track, .track, .track, .settle, .settle, .interrupt, .begin, .track
		])
		#expect(recorder.events[6].oldToken == first)
		#expect(recorder.events[6].newToken == second)
		#expect(recorder.events[7].token == second)
		#expect(recorder.events[8].token == second)
	}

	@Test @MainActor func terminalCommandsAreIdempotentAndRouteTokenIsStrict() {
		let factory = TestAnimatorFactory()
		let driver = Babel2MotionDriver(
			renderer: { _ in },
			recorder: Babel2NullMotionRecorder(),
			animatorFactory: factory
		)
		let route = MotionRouteIdentity(id: "article", generation: 7)
		let token = driver.begin(interaction: .readerTitleCollapse, route: route)
		let wrongRoute = MotionInteractionToken(
			interaction: token.interaction,
			route: MotionRouteIdentity(id: "article", generation: 8),
			sequence: token.sequence
		)
		#expect(!driver.update(token: wrongRoute, progress: .half))
		#expect(driver.cancel(token: token) == .started)
		#expect(driver.cancel(token: token) == .alreadySettling(.cancelled))
		factory.created[0].complete()
		#expect(driver.state == .cancelled(progress: .zero))
		#expect(driver.cancel(token: token) == .alreadyTerminal(.cancelled))
		#expect(driver.finish(token: token) == .alreadyTerminal(.cancelled))
	}

	@Test @MainActor func completionIsIdempotentAndLateOldCompletionCannotChangeReplacement() throws {
		let factory = TestAnimatorFactory()
		let driver = Babel2MotionDriver(
			renderer: { _ in },
			recorder: Babel2NullMotionRecorder(),
			animatorFactory: factory
		)
		let first = driver.begin(interaction: .navigationPop)
		#expect(driver.finish(token: first, duration: 1) == .started)
		factory.created[0].fractionComplete = 0.4
		let second = try #require(driver.interrupt(token: first, newIntent: .readerToBrowser))
		#expect(driver.state.isSettling == false)
		#expect(driver.token == second)
		factory.created[0].complete()
		#expect(driver.token == second)
		#expect(driver.state == .tracking(progress: MotionProgress(0.4)))
		#expect(driver.cancel(token: second, duration: 1) == .started)
		factory.created[0].complete()
		#expect(driver.state.isSettling)
		factory.created[1].complete()
		#expect(driver.state == .cancelled(progress: .zero))
		factory.created[1].complete()
		#expect(driver.state == .cancelled(progress: .zero))
	}
}
#endif
