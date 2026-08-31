import Foundation

/// The lifecycle of a user-owned motion.
///
/// `settling*` describes an in-flight terminal decision. The final state is
/// deliberately split into `settled` and `cancelled`: a newly-created driver
/// is `idle`, a completed transition is `settled`, and a cancelled transition
/// is `cancelled`. Keeping those outcomes observable prevents a cancelled
/// interaction from being mistaken for a never-started one.
public enum MotionState: Equatable, Sendable {
	case idle
	case tracking(progress: MotionProgress)
	case settlingToStart(progress: MotionProgress)
	case settlingToEnd(progress: MotionProgress)
	case settled(progress: MotionProgress, outcome: MotionOutcome)
	case cancelled(progress: MotionProgress)

	public var progress: MotionProgress {
		switch self {
		case .idle:
			return .zero
		case let .tracking(progress), let .settlingToStart(progress), let .settlingToEnd(progress), let .settled(progress, _), let .cancelled(progress):
			return progress
		}
	}

	public var isSettling: Bool {
		switch self {
		case .settlingToStart, .settlingToEnd:
			return true
		case .idle, .tracking, .settled, .cancelled:
			return false
		}
	}

	public var isTerminal: Bool {
		switch self {
		case .settled, .cancelled:
			return true
		case .idle, .tracking, .settlingToStart, .settlingToEnd:
			return false
		}
	}

	public var terminalOutcome: MotionOutcome? {
		switch self {
		case let .settled(_, outcome):
			return outcome
		case .cancelled:
			return .cancelled
		case .idle, .tracking, .settlingToStart, .settlingToEnd:
			return nil
		}
	}

	public var isCancelled: Bool {
		terminalOutcome == .cancelled
	}
}

/// A normalized progress value. Construction always clamps to the closed unit
/// interval so renderers do not need to duplicate bounds checks.
public struct MotionProgress: Equatable, Hashable, Comparable, Sendable {
	public let value: Double

	public init(_ rawValue: Double) {
		if rawValue.isNaN {
			value = 0
		} else if rawValue == .infinity {
			value = 1
		} else if rawValue == -.infinity {
			value = 0
		} else {
			value = min(max(rawValue, 0), 1)
		}
	}

	public static let zero = MotionProgress(0)
	public static let quarter = MotionProgress(0.25)
	public static let half = MotionProgress(0.5)
	public static let threeQuarters = MotionProgress(0.75)
	public static let one = MotionProgress(1)

	public static func < (lhs: MotionProgress, rhs: MotionProgress) -> Bool {
		lhs.value < rhs.value
	}
}

public enum MotionInteractionID: String, CaseIterable, Hashable, Sendable {
	case navigationPop = "navigation.pop"
	case readerToBrowser = "reader.browser"
	case verticalArticlePager = "reader.articlePager"
	case readerTitleCollapse = "reader.titleCollapse"
	case readerToolbar = "reader.toolbar"
	case feedHero = "feed.hero"
}

public struct MotionInteractionToken: Equatable, Hashable, Sendable {
	public let interaction: MotionInteractionID
	public let route: MotionRouteIdentity
	public let sequence: UInt64

	public init(
		interaction: MotionInteractionID,
		route: MotionRouteIdentity = .default,
		sequence: UInt64
	) {
		self.interaction = interaction
		self.route = route
		self.sequence = sequence
	}
}

public enum MotionOutcome: Equatable, Sendable {
	case finished
	case cancelled
}

public enum MotionCommandResult: Equatable, Sendable {
	case started
	case ignored
	case rejected
	case alreadySettling(MotionOutcome)
	case alreadyTerminal(MotionOutcome)
}

public enum MotionUpdateResult: Equatable, Sendable {
	case accepted
	case ignored
	case rejected
}

public enum MotionVelocityDirection: Equatable, Sendable {
	case positive
	case negative
}

public struct MotionRouteIdentity: Equatable, Hashable, Sendable {
	public let id: String
	public let generation: UInt64

	public init(id: String, generation: UInt64) {
		self.id = id
		self.generation = generation
	}

	public static let `default` = MotionRouteIdentity(id: "default", generation: 0)
}

public enum MotionAxis: Equatable, Sendable {
	case horizontal
	case vertical
}

public enum MotionEdge: Equatable, Sendable {
	case left
	case right
	case top
	case bottom
}
