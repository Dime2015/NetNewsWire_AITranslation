import Foundation

public enum MotionGestureIntent: Equatable, Sendable {
	case navigationPop
	case readerToBrowser
	case verticalArticlePager
	case contentScroll
	case controlTap

	public var interactionID: MotionInteractionID? {
		switch self {
		case .navigationPop:
			return .navigationPop
		case .readerToBrowser:
			return .readerToBrowser
		case .verticalArticlePager:
			return .verticalArticlePager
		case .contentScroll, .controlTap:
			return nil
		}
	}

	public var priority: MotionGesturePriority {
		switch self {
		case .navigationPop:
			return .navigationPop
		case .verticalArticlePager:
			return .verticalArticlePager
		case .readerToBrowser:
			return .readerToBrowser
		case .contentScroll:
			return .contentScroll
		case .controlTap:
			return .controlTap
		}
	}
}

public enum MotionGesturePriority: Int, Comparable, Sendable {
	case controlTap = 10
	case contentScroll = 20
	case readerToBrowser = 30
	case verticalArticlePager = 40
	case navigationPop = 50

	public static func < (lhs: MotionGesturePriority, rhs: MotionGesturePriority) -> Bool {
		lhs.rawValue < rhs.rawValue
	}
}

public struct MotionGestureThresholds: Equatable, Sendable {
	public let minimumTranslation: Double
	public let minimumVelocity: Double
	public let axisDominanceRatio: Double

	public init(
		minimumTranslation: Double,
		minimumVelocity: Double,
		axisDominanceRatio: Double
	) {
		self.minimumTranslation = minimumTranslation.isFinite ? max(0, minimumTranslation) : 0
		self.minimumVelocity = minimumVelocity.isFinite ? max(0, minimumVelocity) : 0
		self.axisDominanceRatio = axisDominanceRatio.isFinite ? max(1, axisDominanceRatio) : 1
	}
}

public enum MotionGestureDecision: Equatable, Sendable {
	case reject
	case accept(MotionGestureIntent)
	case deferUntilIntentIsClear
}

public struct MotionGestureCandidate: Equatable, Sendable {
	public let intent: MotionGestureIntent
	public let decision: MotionGestureDecision
	/// When true, this candidate owns the arena once accepted and lower-priority
	/// recognizers must yield for the remainder of the interaction.
	public let mustYield: Bool

	public init(
		intent: MotionGestureIntent,
		decision: MotionGestureDecision,
		mustYield: Bool = true
	) {
		self.intent = intent
		self.decision = decision
		self.mustYield = mustYield
	}
}

public enum MotionGestureResolution: Equatable, Sendable {
	case reject
	case deferUntilIntentIsClear
	case accept(MotionGestureIntent)
}

/// Resolves recognizer candidates without owning recognizers. A higher-priority
/// candidate that is still undecided blocks lower-priority candidates, which
/// prevents a content scroll from stealing an edge transition mid-gesture.
public struct MotionGestureArena: Sendable {
	public init() {}

	/// Returns whether `candidate` must yield to an already-owned gesture. The
	/// comparison is strict: a recognizer never yields to itself, while every
	/// lower-priority recognizer yields to a higher-priority owner.
	public func mustYield(
		candidate: MotionGestureIntent,
		to owner: MotionGestureIntent
	) -> Bool {
		candidate != owner && candidate.priority < owner.priority
	}

	public func resolve(_ candidates: [MotionGestureCandidate]) -> MotionGestureResolution {
		let ordered = candidates.enumerated().sorted {
			if $0.element.intent.priority == $1.element.intent.priority {
				return $0.offset < $1.offset
			}
			return $0.element.intent.priority > $1.element.intent.priority
		}.map(\.element)
		var acceptedWithoutOwnership: MotionGestureIntent?
		for candidate in ordered {
			switch candidate.decision {
			case let .accept(intent):
				if candidate.mustYield { return .accept(intent) }
				acceptedWithoutOwnership = acceptedWithoutOwnership ?? intent
			case .deferUntilIntentIsClear: return .deferUntilIntentIsClear
			case .reject: continue
			}
		}
		if let acceptedWithoutOwnership { return .accept(acceptedWithoutOwnership) }
		return .reject
	}

	/// Resolves a new sample while an owner is already tracking. The owner is
	/// exclusive for the interaction; a lower-priority recognizer cannot steal
	/// it, and a different candidate cannot replace it without going through the
	/// motion driver's explicit interruption API.
	public func resolve(
		_ candidates: [MotionGestureCandidate],
		activeOwner: MotionGestureIntent?
	) -> MotionGestureResolution {
		guard let activeOwner else { return resolve(candidates) }
		guard let owner = candidates.first(where: { $0.intent == activeOwner }) else {
			return .reject
		}
		switch owner.decision {
		case .accept:
			return .accept(activeOwner)
		case .deferUntilIntentIsClear:
			return .deferUntilIntentIsClear
		case .reject:
			return .reject
		}
	}
}

public struct MotionGesturePolicy: Equatable, Sendable {
	public let thresholds: MotionGestureThresholds
	public let edgeWidth: MotionRangeToken

	public init(
		thresholds: MotionGestureThresholds,
		edgeWidth: MotionRangeToken = Babel2MotionTokens.edgeActivationWidth
	) {
		self.thresholds = thresholds
		self.edgeWidth = edgeWidth
	}

	public func isInsideEdge(
		location: Double,
		containerExtent: Double,
		edge: MotionEdge,
		width: Double
	) -> Bool {
		guard location.isFinite, containerExtent.isFinite, containerExtent > 0 else { return false }
		guard width.isFinite, width >= 0 else { return false }
		switch edge {
		case .left:
			return location >= 0 && location <= width
		case .right:
			return location >= containerExtent - width && location <= containerExtent
		case .top, .bottom:
			return false
		}
	}

	public func axis(
		translation: (x: Double, y: Double),
		velocity: (x: Double, y: Double)
	) -> MotionAxis? {
		guard translation.x.isFinite, translation.y.isFinite,
			velocity.x.isFinite, velocity.y.isFinite else { return nil }
		let translationHorizontal = abs(translation.x)
		let translationVertical = abs(translation.y)
		let velocityHorizontal = abs(velocity.x)
		let velocityVertical = abs(velocity.y)
		let horizontal = max(translationHorizontal, velocityHorizontal)
		let vertical = max(translationVertical, velocityVertical)
		guard max(horizontal, vertical) >= thresholds.minimumTranslation else { return nil }
		if horizontal >= vertical * thresholds.axisDominanceRatio {
			return .horizontal
		}
		if vertical >= horizontal * thresholds.axisDominanceRatio {
			return .vertical
		}
		return nil
	}

	public func decision(
		intent: MotionGestureIntent,
		location: Double,
		containerExtent: Double,
		translation: (x: Double, y: Double),
		velocity: (x: Double, y: Double),
		edge: MotionEdge?,
		edgeWidth: Double,
		transitionInFlight: Bool,
		interactionInFlight: Bool,
		atScrollBoundary: Bool = false,
		hasDestination: Bool = true
	) -> MotionGestureDecision {
		guard !transitionInFlight, !interactionInFlight, hasDestination else { return .reject }
		guard location.isFinite, containerExtent.isFinite, containerExtent > 0,
			edgeWidth.isFinite, edgeWidth >= 0 else { return .reject }
		guard translation.x.isFinite, translation.y.isFinite, velocity.x.isFinite, velocity.y.isFinite else {
			return .reject
		}
		if case .controlTap = intent { return .accept(.controlTap) }
		guard let resolvedAxis = axis(translation: translation, velocity: velocity) else {
			return .deferUntilIntentIsClear
		}
		let translationMagnitude = max(abs(translation.x), abs(translation.y))
		let velocityMagnitude = max(abs(velocity.x), abs(velocity.y))
		guard translationMagnitude >= thresholds.minimumTranslation || velocityMagnitude >= thresholds.minimumVelocity else {
			return .reject
		}

		switch intent {
		case .navigationPop:
			guard resolvedAxis == .horizontal, translation.x > 0 else { return .reject }
			guard edge == .left, isInsideEdge(location: location, containerExtent: containerExtent, edge: .left, width: edgeWidth) else {
				return .reject
			}
			guard abs(translation.x) >= thresholds.minimumTranslation || velocity.x >= thresholds.minimumVelocity else {
				return .reject
			}
			return .accept(.navigationPop)

		case .readerToBrowser:
			guard resolvedAxis == .horizontal, translation.x < 0 else { return .reject }
			guard velocity.x <= 0 else { return .reject }
			guard edge == .right, isInsideEdge(location: location, containerExtent: containerExtent, edge: .right, width: edgeWidth) else {
				return .reject
			}
			// Browser opens on a leftward gesture. A positive velocity must not
			// accidentally pass merely because an earlier translation was large.
			guard abs(translation.x) >= thresholds.minimumTranslation || velocity.x <= -thresholds.minimumVelocity else {
				return .reject
			}
			return .accept(.readerToBrowser)

		case .verticalArticlePager:
			guard resolvedAxis == .vertical, atScrollBoundary else { return .reject }
			return .accept(.verticalArticlePager)

		case .contentScroll:
			return resolvedAxis == .horizontal || resolvedAxis == .vertical ? .accept(.contentScroll) : .deferUntilIntentIsClear

		case .controlTap:
			return .accept(.controlTap)
		}
	}
}
