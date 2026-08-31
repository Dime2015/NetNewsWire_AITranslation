import Foundation
import Testing
@testable import Babel2Core

@Suite struct GesturePolicyTests {
	private let policy = MotionGesturePolicy(
		thresholds: MotionGestureThresholds(
			minimumTranslation: 10,
			minimumVelocity: 300,
			axisDominanceRatio: 1.2
		),
		edgeWidth: MotionRangeToken(lowerBound: 24, upperBound: 32, provenance: .toTune, note: "test")
	)

	@Test func edgeChecksRespectLeftAndRightBounds() {
		#expect(policy.isInsideEdge(location: 20, containerExtent: 100, edge: .left, width: 24))
		#expect(!policy.isInsideEdge(location: 25, containerExtent: 100, edge: .left, width: 24))
		#expect(policy.isInsideEdge(location: 80, containerExtent: 100, edge: .right, width: 24))
		#expect(!policy.isInsideEdge(location: 75, containerExtent: 100, edge: .right, width: 24))
	}

	@Test func priorityMatchesMotionContract() {
		#expect(MotionGestureIntent.navigationPop.priority > .verticalArticlePager)
		#expect(MotionGestureIntent.verticalArticlePager.priority > .readerToBrowser)
		#expect(MotionGestureIntent.readerToBrowser.priority > .contentScroll)
		#expect(MotionGestureIntent.contentScroll.priority > .controlTap)
	}

	@Test func axisRequiresDominance() {
		#expect(policy.axis(translation: (12, 2), velocity: (0, 0)) == .horizontal)
		#expect(policy.axis(translation: (2, 12), velocity: (0, 0)) == .vertical)
		#expect(policy.axis(translation: (12, 11), velocity: (0, 0)) == nil)
		#expect(policy.axis(translation: (2, 2), velocity: (0, 0)) == nil)
	}

	@Test func popIsLeftEdgeRightwardOnly() {
		#expect(policy.decision(
			intent: .navigationPop,
			location: 20,
			containerExtent: 100,
			translation: (12, 2),
			velocity: (0, 0),
			edge: .left,
			edgeWidth: 24,
			transitionInFlight: false,
			interactionInFlight: false
		) == .accept(.navigationPop))
		#expect(policy.decision(
			intent: .navigationPop,
			location: 20,
			containerExtent: 100,
			translation: (-12, 2),
			velocity: (0, 0),
			edge: .left,
			edgeWidth: 24,
			transitionInFlight: false,
			interactionInFlight: false
		) == .reject)
		#expect(policy.decision(
			intent: .navigationPop,
			location: 50,
			containerExtent: 100,
			translation: (12, 2),
			velocity: (0, 0),
			edge: .left,
			edgeWidth: 24,
			transitionInFlight: false,
			interactionInFlight: false
		) == .reject)
	}

	@Test func browserIsRightEdgeLeftwardOnly() {
		#expect(policy.decision(
			intent: .readerToBrowser,
			location: 85,
			containerExtent: 100,
			translation: (-12, 2),
			velocity: (0, 0),
			edge: .right,
			edgeWidth: 24,
			transitionInFlight: false,
			interactionInFlight: false
		) == .accept(.readerToBrowser))
		#expect(policy.decision(
			intent: .readerToBrowser,
			location: 85,
			containerExtent: 100,
			translation: (12, 2),
			velocity: (0, 0),
			edge: .right,
			edgeWidth: 24,
			transitionInFlight: false,
			interactionInFlight: false
		) == .reject)
		#expect(policy.decision(
			intent: .readerToBrowser,
			location: 85,
			containerExtent: 100,
			translation: (-12, 0),
			velocity: (500, 0),
			edge: .right,
			edgeWidth: 24,
			transitionInFlight: false,
			interactionInFlight: false
		) == .reject)
	}

	@Test func pagerRequiresVerticalBoundaryAndClearIntent() {
		#expect(policy.decision(
			intent: .verticalArticlePager,
			location: 50,
			containerExtent: 100,
			translation: (2, 16),
			velocity: (0, 0),
			edge: nil,
			edgeWidth: 0,
			transitionInFlight: false,
			interactionInFlight: false,
			atScrollBoundary: true
		) == .accept(.verticalArticlePager))
		#expect(policy.decision(
			intent: .verticalArticlePager,
			location: 50,
			containerExtent: 100,
			translation: (2, 16),
			velocity: (0, 0),
			edge: nil,
			edgeWidth: 0,
			transitionInFlight: false,
			interactionInFlight: false,
			atScrollBoundary: false
		) == .reject)
	}

	@Test func inFlightTransitionsAlwaysYield() {
		let decision = policy.decision(
			intent: .navigationPop,
			location: 20,
			containerExtent: 100,
			translation: (20, 1),
			velocity: (0, 0),
			edge: .left,
			edgeWidth: 24,
			transitionInFlight: true,
			interactionInFlight: false
		)
		#expect(decision == .reject)
	}

	@Test func nonFiniteTranslationOrVelocityIsRejected() {
		let nan = policy.decision(
			intent: .navigationPop,
			location: 20,
			containerExtent: 100,
			translation: (.nan, 0),
			velocity: (0, 0),
			edge: .left,
			edgeWidth: 24,
			transitionInFlight: false,
			interactionInFlight: false
		)
		let infinity = policy.decision(
			intent: .readerToBrowser,
			location: 85,
			containerExtent: 100,
			translation: (-20, 0),
			velocity: (-.infinity, 0),
			edge: .right,
			edgeWidth: 24,
			transitionInFlight: false,
			interactionInFlight: false
		)
		#expect(nan == .reject)
		#expect(infinity == .reject)
		#expect(policy.axis(translation: (.infinity, 0), velocity: (0, 0)) == nil)
		#expect(policy.axis(translation: (0, 0), velocity: (.nan, 0)) == nil)
		#expect(policy.decision(
			intent: .controlTap,
			location: .nan,
			containerExtent: 100,
			translation: (0, 0),
			velocity: (0, 0),
			edge: nil,
			edgeWidth: 24,
			transitionInFlight: false,
			interactionInFlight: false
		) == .reject)
	}

	@Test func arenaEnforcesPriorityAndMustYield() {
		let arena = MotionGestureArena()
		let conflict = arena.resolve([
			MotionGestureCandidate(intent: .contentScroll, decision: .accept(.contentScroll)),
			MotionGestureCandidate(intent: .navigationPop, decision: .accept(.navigationPop))
		])
		#expect(conflict == .accept(.navigationPop))

		let undecidedHighPriority = arena.resolve([
			MotionGestureCandidate(intent: .contentScroll, decision: .accept(.contentScroll)),
			MotionGestureCandidate(intent: .readerToBrowser, decision: .deferUntilIntentIsClear)
		])
		#expect(undecidedHighPriority == .deferUntilIntentIsClear)

		let rejectedHighPriority = arena.resolve([
			MotionGestureCandidate(intent: .navigationPop, decision: .reject),
			MotionGestureCandidate(intent: .contentScroll, decision: .accept(.contentScroll))
		])
		#expect(rejectedHighPriority == .accept(.contentScroll))
		#expect(arena.mustYield(candidate: .contentScroll, to: .readerToBrowser))
		#expect(!arena.mustYield(candidate: .readerToBrowser, to: .readerToBrowser))
		#expect(arena.resolve(
			[
				MotionGestureCandidate(intent: .contentScroll, decision: .accept(.contentScroll)),
				MotionGestureCandidate(intent: .readerToBrowser, decision: .accept(.readerToBrowser))
			],
			activeOwner: .readerToBrowser
		) == .accept(.readerToBrowser))
	}

	@Test func arenaMustYieldChainAndTiesAreDeterministic() {
		let arena = MotionGestureArena()
		#expect(arena.resolve([
			MotionGestureCandidate(intent: .navigationPop, decision: .accept(.navigationPop), mustYield: false),
			MotionGestureCandidate(intent: .readerToBrowser, decision: .accept(.readerToBrowser), mustYield: true),
			MotionGestureCandidate(intent: .contentScroll, decision: .accept(.contentScroll), mustYield: true)
		]) == .accept(.readerToBrowser))
		#expect(arena.resolve([
			MotionGestureCandidate(intent: .contentScroll, decision: .accept(.contentScroll), mustYield: false),
			MotionGestureCandidate(intent: .controlTap, decision: .accept(.controlTap), mustYield: false)
		]) == .accept(.contentScroll))
	}

	@Test func activeOwnerDeferralCannotLockArena() {
		let arena = MotionGestureArena()
		#expect(arena.resolve([
			MotionGestureCandidate(intent: .readerToBrowser, decision: .deferUntilIntentIsClear),
			MotionGestureCandidate(intent: .contentScroll, decision: .accept(.contentScroll))
		], activeOwner: .readerToBrowser) == .deferUntilIntentIsClear)
		#expect(arena.resolve([
			MotionGestureCandidate(intent: .readerToBrowser, decision: .reject),
			MotionGestureCandidate(intent: .contentScroll, decision: .accept(.contentScroll))
		], activeOwner: .readerToBrowser) == .reject)
	}
}
