import Foundation
import Testing
@testable import Babel2Core

@Suite struct MotionStateTests {
	@Test func progressClampsAtAllBoundaries() {
		#expect(MotionProgress(-100).value == 0)
		#expect(MotionProgress(0).value == 0)
		#expect(MotionProgress(0.25).value == 0.25)
		#expect(MotionProgress(0.5).value == 0.5)
		#expect(MotionProgress(0.75).value == 0.75)
		#expect(MotionProgress(1).value == 1)
		#expect(MotionProgress(100).value == 1)
		#expect(MotionProgress(.nan).value == 0)
		#expect(MotionProgress(.infinity).value == 1)
		#expect(MotionProgress(-.infinity).value == 0)
	}

	@Test func lifecycleExposesNormalizedProgress() {
		#expect(MotionState.idle.progress == .zero)
		#expect(MotionState.tracking(progress: .quarter).progress == .quarter)
		#expect(MotionState.settlingToStart(progress: .half).isSettling)
		#expect(MotionState.settlingToEnd(progress: .threeQuarters).isSettling)
		#expect(!MotionState.tracking(progress: .half).isSettling)
		#expect(MotionState.settled(progress: .one, outcome: .finished).isTerminal)
		#expect(MotionState.settled(progress: .zero, outcome: .cancelled).terminalOutcome == .cancelled)
		#expect(MotionState.cancelled(progress: .zero).isTerminal)
		#expect(MotionState.cancelled(progress: .zero).isCancelled)
		#expect(MotionState.cancelled(progress: .zero).terminalOutcome == .cancelled)
		#expect(!MotionState.idle.isTerminal)
		#expect(!MotionState.idle.isCancelled)
	}

	@Test func rangeTokensRemainFiniteAndNonNegative() {
		let invalid = MotionRangeToken(
			lowerBound: -.infinity,
			upperBound: .nan,
			provenance: .toTune,
			note: "invalid input"
		)
		#expect(invalid.lowerBound.isFinite)
		#expect(invalid.upperBound.isFinite)
		#expect(invalid.lowerBound >= 0)
		#expect(invalid.upperBound >= invalid.lowerBound)
		#expect(invalid.clamped(.nan) == invalid.lowerBound)
		#expect(invalid.clamped(.infinity) == invalid.upperBound)
	}

	@Test func interactionIDsAreStableAndDistinct() {
		let ids = MotionInteractionID.allCases
		#expect(ids.count == 6)
		#expect(Set(ids).count == ids.count)
		#expect(MotionInteractionID.navigationPop.rawValue == "navigation.pop")
		#expect(MotionInteractionID.feedHero.rawValue == "feed.hero")
	}
}
