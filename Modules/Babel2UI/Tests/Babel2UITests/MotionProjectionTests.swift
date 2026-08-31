import Foundation
import Testing
@testable import Babel2Core

@Suite struct MotionProjectionTests {
	private let configuration = MotionProjectionConfiguration(duration: 0.2, finishThreshold: .half)

	@Test func positiveVelocityProjectsTowardEnd() {
		let result = MotionProjection.projectedProgress(
			progress: .quarter,
			velocity: 250,
			extent: 1000,
			duration: 0.2
		)
		#expect(result == MotionProgress(0.295))
	}

	@Test func negativeVelocityProjectsTowardStartAndClamps() {
		#expect(MotionProjection.projectedProgress(progress: .quarter, velocity: -10_000, extent: 100, duration: 0.2) == .zero)
		#expect(MotionProjection.projectedProgress(progress: .threeQuarters, velocity: 10_000, extent: 100, duration: 0.2) == .one)
	}

	@Test func invalidExtentAndNonFiniteVelocityLeaveProgressUntouched() {
		#expect(MotionProjection.validatedProjection(progress: .half, velocity: 100, extent: 0, duration: 0.15) == .rejected)
		#expect(MotionProjection.validatedProjection(progress: .half, velocity: .nan, extent: 100, duration: 0.15) == .rejected)
		#expect(MotionProjection.validatedProjection(progress: .half, velocity: .infinity, extent: 100, duration: 0.15) == .rejected)
		#expect(MotionProjection.validatedProjection(progress: .half, velocity: 100, extent: 100, duration: .nan) == .rejected)
		#expect(MotionProjection.validatedProjection(progress: .half, velocity: 100, extent: 100, duration: -.infinity) == .rejected)
		#expect(MotionProjection.projectedProgress(progress: .half, velocity: 100, extent: 0, duration: 1) == .half)
		#expect(MotionProjection.projectedProgress(progress: .half, velocity: .nan, extent: 100, duration: 1) == .half)
		#expect(MotionProjection.projectedProgress(progress: .half, velocity: 100, extent: .infinity, duration: 1) == .half)
	}

	@Test func projectionDurationIsClampedToBoundedWindow() {
		let bounds = MotionRangeToken(lowerBound: 0.12, upperBound: 0.18, provenance: .toTune, note: "test")
		let short = MotionProjection.projectedProgress(progress: .zero, velocity: 100, extent: 100, duration: -1, durationBounds: bounds)
		let long = MotionProjection.projectedProgress(progress: .zero, velocity: 100, extent: 100, duration: 10, durationBounds: bounds)
		let nan = MotionProjection.projectedProgress(progress: .zero, velocity: 100, extent: 100, duration: .nan, durationBounds: bounds)
		let positiveInfinity = MotionProjection.projectedProgress(progress: .zero, velocity: 100, extent: 100, duration: .infinity, durationBounds: bounds)
		let negativeInfinity = MotionProjection.projectedProgress(progress: .zero, velocity: 100, extent: 100, duration: -.infinity, durationBounds: bounds)
		#expect(short == MotionProgress(0.12))
		#expect(long == MotionProgress(0.18))
		#expect(nan == MotionProgress(0.12))
		#expect(positiveInfinity == MotionProgress(0.18))
		#expect(negativeInfinity == MotionProgress(0.12))
	}

	@Test func malformedOrWidenedProjectionBoundsCannotEscapeContractWindow() {
		let widened = MotionRangeToken(
			lowerBound: -.infinity,
			upperBound: .infinity,
			provenance: .toTune,
			note: "malformed"
		)
		#expect(MotionProjection.boundedProjectionDuration(-100, bounds: widened) == 0.12)
		#expect(MotionProjection.boundedProjectionDuration(100, bounds: widened) == 0.18)
		#expect(MotionProjection.boundedProjectionDuration(.nan, bounds: widened) == 0.12)
		#expect(MotionProjection.boundedProjectionDuration(.infinity, bounds: widened) == 0.18)
		#expect(MotionProjection.effectiveProjectionBounds(widened) == Babel2MotionTokens.projectionDuration)
	}

	@Test func browserNegativeVelocityIsNormalizedTowardEnd() {
		#expect(MotionProjection.velocityTowardEnd(-500, direction: .negative) == 500)
		#expect(MotionProjection.normalizedVelocity(-500, toward: .negative) == 500)
		#expect(MotionProjection.velocityTowardEnd(500, direction: .negative) == -500)
		#expect(MotionProjection.velocityTowardEnd(.infinity, direction: .negative) == 0)
	}

	@Test func finishDecisionUsesProjectedProgress() {
		#expect(MotionProjection.finishDecision(progress: .quarter, velocity: 1_400, extent: 1_000, configuration: configuration) == .finish)
		#expect(MotionProjection.finishDecision(progress: .quarter, velocity: 100, extent: 1_000, configuration: configuration) == .cancel)
		#expect(MotionProjection.finishDecision(progress: .half, velocity: 0, extent: 1_000, configuration: configuration) == .finish)
		#expect(MotionProjection.validatedFinishDecision(progress: .quarter, velocity: 1_400, extent: 1_000, configuration: configuration) == .decision(.finish))
		#expect(MotionProjection.validatedFinishDecision(progress: .quarter, velocity: .nan, extent: 1_000, configuration: configuration) == .rejected)
		#expect(MotionProjection.validatedFinishDecision(progress: .quarter, velocity: 100, extent: .infinity, configuration: configuration) == .rejected)
	}

	@Test func zeroDurationAndNegativeDurationAreSafe() {
		let zero = MotionProjection.projectedProgress(progress: .quarter, velocity: 100, extent: 1_000, duration: 0)
		let negative = MotionProjection.projectedProgress(progress: .quarter, velocity: 100, extent: 1_000, duration: -1)
		#expect(zero == MotionProgress(0.262))
		#expect(negative == MotionProgress(0.262))
	}
}
