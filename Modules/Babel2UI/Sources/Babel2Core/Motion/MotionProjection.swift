import Foundation

public struct MotionProjectionConfiguration: Equatable, Sendable {
	public let duration: TimeInterval
	public let finishThreshold: MotionProgress
	public let durationBounds: MotionRangeToken

	public init(
		duration: TimeInterval = 0.15,
		finishThreshold: MotionProgress = .half,
		durationBounds: MotionRangeToken = Babel2MotionTokens.projectionDuration
	) {
		self.durationBounds = MotionProjection.effectiveProjectionBounds(durationBounds)
		self.duration = self.durationBounds.clamped(duration)
		self.finishThreshold = finishThreshold
	}
}

public enum MotionFinishDecision: Equatable, Sendable {
	case finish
	case cancel
}

/// The result of validating a projection request. Callers at an external
/// gesture boundary must handle rejection explicitly; the compatibility
/// `projectedProgress` helper below retains the last progress only for pure
/// value-level callers that intentionally choose a safe fallback.
public enum MotionProjectionResult: Equatable, Sendable {
	case projected(MotionProgress)
	case rejected
}

public enum MotionFinishDecisionResult: Equatable, Sendable {
	case decision(MotionFinishDecision)
	case rejected
}

public enum MotionProjection {
	/// The projection window is deliberately narrower than a full route settle.
	/// Custom test/tuning ranges may narrow this interval but cannot widen it;
	/// this keeps malformed or stale configuration from creating a long fling.
	public static func effectiveProjectionBounds(_ bounds: MotionRangeToken) -> MotionRangeToken {
		let contract = Babel2MotionTokens.projectionDuration
		let lower = max(contract.lowerBound, bounds.lowerBound)
		let upper = min(contract.upperBound, bounds.upperBound)
		guard lower.isFinite, upper.isFinite, lower <= upper else { return contract }
		return MotionRangeToken(
			lowerBound: lower,
			upperBound: upper,
			provenance: bounds.provenance,
			note: bounds.note
		)
	}

	public static func boundedProjectionDuration(
		_ duration: TimeInterval,
		bounds: MotionRangeToken = Babel2MotionTokens.projectionDuration
	) -> TimeInterval {
		effectiveProjectionBounds(bounds).clamped(duration)
	}

	/// Validates all raw inputs before conversion or clamping. This is the
	/// explicit boundary result used by gesture drivers; NaN, infinities and a
	/// non-positive extent are rejected rather than silently turned into a
	/// legal projection.
	public static func validatedProjection(
		progress: MotionProgress,
		velocity: Double,
		extent: Double,
		duration: TimeInterval,
		durationBounds: MotionRangeToken = Babel2MotionTokens.projectionDuration
	) -> MotionProjectionResult {
		guard velocity.isFinite, extent.isFinite, extent > 0, duration.isFinite else {
			return .rejected
		}
		let boundedDuration = boundedProjectionDuration(duration, bounds: durationBounds)
		guard boundedDuration.isFinite else { return .rejected }
		return .projected(MotionProgress(progress.value + velocity * boundedDuration / extent))
	}

	/// Projects progress using a signed velocity in points per second. Positive
	/// velocity always means movement toward the end state; callers normalize
	/// their gesture direction before calling this function.
	public static func projectedProgress(
		progress: MotionProgress,
		velocity: Double,
		extent: Double,
		duration: TimeInterval,
		durationBounds: MotionRangeToken = Babel2MotionTokens.projectionDuration
	) -> MotionProgress {
		guard extent.isFinite, extent > 0, velocity.isFinite else { return progress }
		// This value-level compatibility helper deliberately clamps a malformed
		// duration into the contract window. Raw gesture entry points use
		// `validatedProjection` (and reject it) before reaching this helper.
		let boundedDuration = boundedProjectionDuration(duration, bounds: durationBounds)
		return MotionProgress(progress.value + velocity * boundedDuration / extent)
	}

	public static func velocityTowardEnd(
		_ velocity: Double,
		direction: MotionVelocityDirection
	) -> Double {
		guard velocity.isFinite else { return 0 }
		return direction == .positive ? velocity : -velocity
	}

	/// Normalizes a raw gesture velocity to the driver's positive-toward-end
	/// convention. This is used by both edge-pop and Reader → Browser so the
	/// browser's leftward gesture is not accidentally treated as a cancellation.
	public static func normalizedVelocity(
		_ velocity: Double,
		toward direction: MotionVelocityDirection
	) -> Double {
		velocityTowardEnd(velocity, direction: direction)
	}

	public static func finishDecision(
		progress: MotionProgress,
		velocity: Double,
		extent: Double,
		configuration: MotionProjectionConfiguration
	) -> MotionFinishDecision {
		let projected = projectedProgress(
			progress: progress,
			velocity: velocity,
			extent: extent,
			duration: configuration.duration,
			durationBounds: configuration.durationBounds
		)
		return projected >= configuration.finishThreshold ? .finish : .cancel
	}

	/// Strict counterpart for gesture boundaries that need to distinguish an
	/// invalid sample from a valid cancellation decision.
	public static func validatedFinishDecision(
		progress: MotionProgress,
		velocity: Double,
		extent: Double,
		configuration: MotionProjectionConfiguration
	) -> MotionFinishDecisionResult {
		switch validatedProjection(
			progress: progress,
			velocity: velocity,
			extent: extent,
			duration: configuration.duration,
			durationBounds: configuration.durationBounds
		) {
		case let .projected(projected):
			return .decision(projected >= configuration.finishThreshold ? .finish : .cancel)
		case .rejected:
			return .rejected
		}
	}
}
