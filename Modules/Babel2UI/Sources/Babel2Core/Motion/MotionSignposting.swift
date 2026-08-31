import Foundation

public enum MotionSignpostName: String, CaseIterable, Hashable, Sendable {
	case begin = "Babel2.Motion.Begin"
	case track = "Babel2.Motion.Track"
	case settle = "Babel2.Motion.Settle"
	case interrupt = "Babel2.Motion.Interrupt"
	case readerChrome = "Babel2.Reader.Chrome"
	case readerPager = "Babel2.Reader.Pager"
	case feedHero = "Babel2.Feed.Hero"
	case libraryFilter = "Babel2.Library.Filter"
	case webPrepared = "Babel2.Web.Prepared"
	case loadingOwner = "Babel2.Loading.Owner"
}

/// Names that intentionally carry no surface-specific payload. Typed surface
/// names are excluded from this type and must be emitted through a payload.
public enum MotionBaseSignpostName: String, CaseIterable, Sendable {
	case begin = "Babel2.Motion.Begin"
	case track = "Babel2.Motion.Track"
	case settle = "Babel2.Motion.Settle"
	case interrupt = "Babel2.Motion.Interrupt"

	public var signpostName: MotionSignpostName {
		switch self {
		case .begin: return .begin
		case .track: return .track
		case .settle: return .settle
		case .interrupt: return .interrupt
		}
	}
}

public enum MotionSignpostPhase: String, Equatable, Sendable {
	case begin
	case event
	case end
}

public enum MotionReaderChromeState: String, Equatable, Sendable {
	case expanded
	case collapsing
	case compactPinned
	case controlsChanging
}

public struct MotionReaderChromePayload: Equatable, Sendable {
	public let state: MotionReaderChromeState
	public let pCollapse: MotionProgress
	public let barP: MotionProgress

	public init(state: MotionReaderChromeState, pCollapse: MotionProgress, barP: MotionProgress) {
		self.state = state
		self.pCollapse = pCollapse
		self.barP = barP
	}
}

public struct MotionReaderPagerPayload: Equatable, Sendable {
	public let previousID: String?
	public let currentID: String
	public let nextID: String?
	public let progress: MotionProgress

	public init(previousID: String?, currentID: String, nextID: String?, progress: MotionProgress) {
		self.previousID = previousID
		self.currentID = currentID
		self.nextID = nextID
		self.progress = progress
	}
}

public struct MotionFeedHeroPayload: Equatable, Sendable {
	public let pHero: MotionProgress
	public let imageReady: Bool

	public init(pHero: MotionProgress, imageReady: Bool) {
		self.pHero = pHero
		self.imageReady = imageReady
	}
}

public enum MotionLibraryFilter: String, Equatable, Sendable {
	case starred
	case unread
	case all
}

public struct MotionLibraryFilterPayload: Equatable, Sendable {
	public let fromFilter: MotionLibraryFilter
	public let toFilter: MotionLibraryFilter
	public let pFilter: MotionProgress
	public let token: MotionInteractionToken

	public init(
		fromFilter: MotionLibraryFilter,
		toFilter: MotionLibraryFilter,
		pFilter: MotionProgress,
		token: MotionInteractionToken
	) {
		self.fromFilter = fromFilter
		self.toFilter = toFilter
		self.pFilter = pFilter
		self.token = token
	}
}

public enum MotionWebPreparation: String, Equatable, Sendable {
	case warm
	case cold
}

public struct MotionWebPreparedPayload: Equatable, Sendable {
	public let routeToken: MotionInteractionToken
	public let preparation: MotionWebPreparation

	public init(routeToken: MotionInteractionToken, preparation: MotionWebPreparation) {
		self.routeToken = routeToken
		self.preparation = preparation
	}
}

public enum MotionLoadingSurface: String, Equatable, Sendable {
	case sync
	case article
	case translation
	case browser
}

public enum MotionLoadingOwner: String, Equatable, Sendable {
	case syncArrow
	case articleSkeleton
	case translationSkeleton
	case browserPreparation
	case errorRetry
}

public enum MotionLoadingState: String, Equatable, Sendable {
	case started
	case active
	case completed
	case failed
}

public struct MotionLoadingPayload: Equatable, Sendable {
	public let surface: MotionLoadingSurface
	public let owner: MotionLoadingOwner
	public let state: MotionLoadingState

	public init(surface: MotionLoadingSurface, owner: MotionLoadingOwner, state: MotionLoadingState) {
		self.surface = surface
		self.owner = owner
		self.state = state
	}
}

public enum MotionSignpostPayload: Equatable, Sendable {
	case readerChrome(MotionReaderChromePayload)
	case readerPager(MotionReaderPagerPayload)
	case feedHero(MotionFeedHeroPayload)
	case libraryFilter(MotionLibraryFilterPayload)
	case webPrepared(MotionWebPreparedPayload)
	case loading(MotionLoadingPayload)

	public var name: MotionSignpostName {
		switch self {
		case .readerChrome: return .readerChrome
		case .readerPager: return .readerPager
		case .feedHero: return .feedHero
		case .libraryFilter: return .libraryFilter
		case .webPrepared: return .webPrepared
		case .loading: return .loadingOwner
		}
	}
}

public struct MotionSignpostEvent: Equatable, Sendable {
	public let name: MotionSignpostName
	public let interaction: MotionInteractionID?
	public let route: MotionRouteIdentity?
	public let recognizer: String?
	public let token: MotionInteractionToken?
	public let oldToken: MotionInteractionToken?
	public let newToken: MotionInteractionToken?
	public let progress: MotionProgress?
	public let sampledProgress: MotionProgress?
	public let projectedProgress: MotionProgress?
	public let duration: TimeInterval?
	public let outcome: MotionOutcome?
	public let phase: MotionSignpostPhase
	public let typedPayload: MotionSignpostPayload?

	/// Contract terminology calls the interaction an intent. Keep the stored
	/// `interaction` name for source compatibility while exposing that alias to
	/// instrumentation clients.
	public var intent: MotionInteractionID? { interaction }

	public init(
		baseName: MotionBaseSignpostName,
		interaction: MotionInteractionID? = nil,
		route: MotionRouteIdentity? = nil,
		recognizer: String? = nil,
		token: MotionInteractionToken? = nil,
		oldToken: MotionInteractionToken? = nil,
		newToken: MotionInteractionToken? = nil,
		progress: MotionProgress? = nil,
		sampledProgress: MotionProgress? = nil,
		projectedProgress: MotionProgress? = nil,
		duration: TimeInterval? = nil,
		outcome: MotionOutcome? = nil,
		phase: MotionSignpostPhase = .event
	) {
		self.name = baseName.signpostName
		self.interaction = interaction
		self.route = route
		self.recognizer = recognizer
		self.token = token
		self.oldToken = oldToken
		self.newToken = newToken
		self.progress = progress
		self.sampledProgress = sampledProgress
		self.projectedProgress = projectedProgress
		self.duration = duration
		self.outcome = outcome
		self.phase = phase
		self.typedPayload = nil
	}

	/// Compatibility entry point for payload-free events. Typed signposts are
	/// intentionally rejected here and must use `init(payload:)`.
	public init?(
		name: MotionSignpostName,
		phase: MotionSignpostPhase = .event
	) {
		switch name {
		case .begin: self.init(baseName: .begin, phase: phase)
		case .track: self.init(baseName: .track, phase: phase)
		case .settle: self.init(baseName: .settle, phase: phase)
		case .interrupt: self.init(baseName: .interrupt, phase: phase)
		default: return nil
		}
	}

	/// Creates a semantically complete event. The signpost name is derived from
	/// the payload, so a Reader payload cannot be paired with a Loading name.
	public init(
		payload: MotionSignpostPayload,
		interaction: MotionInteractionID? = nil,
		route: MotionRouteIdentity? = nil,
		recognizer: String? = nil,
		token: MotionInteractionToken? = nil,
		oldToken: MotionInteractionToken? = nil,
		newToken: MotionInteractionToken? = nil,
		progress: MotionProgress? = nil,
		sampledProgress: MotionProgress? = nil,
		projectedProgress: MotionProgress? = nil,
		duration: TimeInterval? = nil,
		outcome: MotionOutcome? = nil,
		phase: MotionSignpostPhase = .event
	) {
		self.name = payload.name
		self.interaction = interaction
		self.route = route
		self.recognizer = recognizer
		self.token = token
		self.oldToken = oldToken
		self.newToken = newToken
		self.progress = progress
		self.sampledProgress = sampledProgress
		self.projectedProgress = projectedProgress
		self.duration = duration
		self.outcome = outcome
		self.phase = phase
		self.typedPayload = payload
	}

	/// Validated compatibility initializer for clients that still carry a
	/// separate name. Mismatched name/payload pairs are rejected instead of
	/// producing an event with misleading instrumentation.
	public init?(
		name: MotionSignpostName,
		typedPayload: MotionSignpostPayload,
		phase: MotionSignpostPhase = .event
	) {
		guard name == typedPayload.name else { return nil }
		self.init(payload: typedPayload, phase: phase)
	}

	/// Stable diagnostic fields used by fake recorders and Instruments. Include
	/// route identity in every token so sequence numbers cannot be confused
	/// across route generations.
	public var diagnosticPayload: String {
		[
			"route=\(route?.id ?? "-")",
			"routeGeneration=\(route?.generation.description ?? "-")",
			"intent=\(interaction?.rawValue ?? "-")",
			"recognizer=\(recognizer ?? "-")",
			"token=\(token.map(Self.describeToken) ?? "-")",
			"oldToken=\(oldToken.map(Self.describeToken) ?? "-")",
			"newToken=\(newToken.map(Self.describeToken) ?? "-")",
			"progress=\(progress?.value.description ?? "-")",
			"sampledProgress=\(sampledProgress?.value.description ?? "-")",
			"projectedProgress=\(projectedProgress?.value.description ?? "-")",
			"duration=\(duration?.description ?? "-")",
			"outcome=\(outcome.map(String.init(describing:)) ?? "-")",
			"phase=\(phase.rawValue)",
			"typedPayload=\(typedPayload.map(Self.describePayload) ?? "-")"
		].joined(separator: " ")
	}

	private static func describeToken(_ token: MotionInteractionToken) -> String {
		"\(token.interaction.rawValue):\(token.route.id):\(token.route.generation):\(token.sequence)"
	}

	private static func describePayload(_ payload: MotionSignpostPayload) -> String {
		switch payload {
		case let .readerChrome(value):
			return "readerChrome(state:\(value.state.rawValue),pCollapse:\(value.pCollapse.value),barP:\(value.barP.value))"
		case let .readerPager(value):
			return "readerPager(previousID:\(value.previousID ?? "-"),currentID:\(value.currentID),nextID:\(value.nextID ?? "-"),p:\(value.progress.value))"
		case let .feedHero(value):
			return "feedHero(pHero:\(value.pHero.value),imageReady:\(value.imageReady))"
		case let .libraryFilter(value):
			return "libraryFilter(fromFilter:\(value.fromFilter.rawValue),toFilter:\(value.toFilter.rawValue),pFilter:\(value.pFilter.value),token:\(describeToken(value.token)))"
		case let .webPrepared(value):
			return "webPrepared(routeToken:\(describeToken(value.routeToken)),preparation:\(value.preparation.rawValue))"
		case let .loading(value):
			return "loading(surface:\(value.surface.rawValue),owner:\(value.owner.rawValue),state:\(value.state.rawValue))"
		}
	}
}

@MainActor
public protocol Babel2MotionRecording: AnyObject {
	func record(_ event: MotionSignpostEvent)
}

@MainActor
public final class Babel2NullMotionRecorder: Babel2MotionRecording, @unchecked Sendable {
	public init() {}
	public func record(_ event: MotionSignpostEvent) {}
}
