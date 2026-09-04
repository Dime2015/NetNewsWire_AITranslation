import Foundation

public enum Babel2Generation: String, Codable, CaseIterable, Sendable {
	case babel2 = "babel-2"
	/// Used only to reject stale restoration payloads. It is not a runnable
	/// generation and is never selected by the application.
	case legacy = "legacy"
}

public enum Babel2BuildChannel: String, Codable, Sendable, CaseIterable {
	case debug
	case test
	case release
}

public enum Babel2FeatureGateReason: String, Codable, Sendable, Equatable {
	case babel2OnlyRuntime
}

public struct Babel2FeatureGateDecision: Sendable, Equatable {
	public let generation: Babel2Generation
	public let reason: Babel2FeatureGateReason
	public let diagnostics: [String]

	public init(
		generation: Babel2Generation,
		reason: Babel2FeatureGateReason,
		diagnostics: [String] = []
	) {
		self.generation = generation
		self.reason = reason
		self.diagnostics = diagnostics
	}

	public var isBabel2: Bool { generation == .babel2 }
}

public enum Babel2LaunchTraceEventKind: String, Codable, Sendable, Equatable {
	case processEntry
	case decision
	case sceneConfigurationSelected
	case sceneConfigurationObserved
	case rootInstalled
	case rootVisible
	case containerAppeared
	case contentFirstFramePresented
	case legacyUILifecycle
	case legacyBootstrap
	case legacyStoryboardDecode
	case legacySceneCoordinator
	case legacyWebViewBootstrap
	case teardown
}

public enum Babel2LaunchTraceInvalidReason: String, Codable, Sendable, Equatable, CaseIterable {
	case processEntryMissing
	case processEntryEvidenceInvalid
	case decisionMissing
	case decisionUptimeMismatch
	case eventOrderInvalid
	case eventSequenceInvalid
	case eventUptimeInvalid
	case eventSessionMismatch
	case nonBabel2Decision
	case sceneConfigurationSelectionMissing
	case sceneConfigurationObservationMissing
	case sceneConfigurationNameMissing
	case sceneConfigurationMismatch
	case sceneConfigurationStoryboardPresent
	case sceneConfigurationStoryboardEvidenceMissing
	case sceneConfigurationDelegateInvalid
	case launchMilestoneDuplicate
	case launchMilestoneSurfaceInvalid
	case rootInstallationMissing
	case rootVisibleMissing
	case containerAppearanceMissing
	case contentFirstFrameMissing
	case legacyUILifecycle
	case legacyBootstrap
	case legacyStoryboardDecode
	case legacySceneCoordinator
	case legacyWebViewBootstrap
}

public struct Babel2TraceRect: Codable, Sendable, Equatable {
	public let x: Double
	public let y: Double
	public let width: Double
	public let height: Double

	public init(x: Double, y: Double, width: Double, height: Double) {
		self.x = x
		self.y = y
		self.width = width
		self.height = height
	}
}

public struct Babel2TraceInsets: Codable, Sendable, Equatable {
	public let top: Double
	public let left: Double
	public let bottom: Double
	public let right: Double

	public init(top: Double, left: Double, bottom: Double, right: Double) {
		self.top = top
		self.left = left
		self.bottom = bottom
		self.right = right
	}
}

private extension Babel2TraceRect {
	var isFiniteAndPositive: Bool {
		x.isFinite && y.isFinite && width.isFinite && height.isFinite && width > 0 && height > 0
	}
}

private extension Babel2TraceInsets {
	var isFiniteAndNonnegative: Bool {
		top.isFinite && left.isFinite && bottom.isFinite && right.isFinite && top >= 0 && left >= 0 && bottom >= 0 && right >= 0
	}
}

private extension Babel2TraceSurface {
	var hasValidGeometry: Bool {
		guard let windowBounds,
			  let rootBounds,
			  let rootFrame,
			  let contentBounds,
			  let contentFrame,
			  let safeAreaInsets,
			  rootMatchesExpected == true else { return false }
		return [windowBounds, rootBounds, rootFrame, contentBounds, contentFrame].allSatisfy(\.isFiniteAndPositive)
			&& safeAreaInsets.isFiniteAndNonnegative
	}

	var isVisibleAndGeometricallyValid: Bool {
		hasValidGeometry && windowIsHidden == false && windowIsKey == true
	}
}

/// A small, privacy-safe snapshot of the root/content surface. It records
/// geometry and UIKit identity only; it is not a data-loaded or screenshot
/// acceptance signal.
public struct Babel2TraceSurface: Codable, Sendable, Equatable {
	public let controllerType: String
	public let contentType: String?
	public let windowBounds: Babel2TraceRect?
	public let rootBounds: Babel2TraceRect?
	public let rootFrame: Babel2TraceRect?
	public let contentBounds: Babel2TraceRect?
	public let contentFrame: Babel2TraceRect?
	public let safeAreaInsets: Babel2TraceInsets?
	public let windowIsHidden: Bool?
	public let windowIsKey: Bool?
	public let rootMatchesExpected: Bool?

	public init(
		controllerType: String,
		contentType: String? = nil,
		windowBounds: Babel2TraceRect? = nil,
		rootBounds: Babel2TraceRect? = nil,
		rootFrame: Babel2TraceRect? = nil,
		contentBounds: Babel2TraceRect? = nil,
		contentFrame: Babel2TraceRect? = nil,
		safeAreaInsets: Babel2TraceInsets? = nil,
		windowIsHidden: Bool? = nil,
		windowIsKey: Bool? = nil,
		rootMatchesExpected: Bool? = nil
	) {
		self.controllerType = controllerType
		self.contentType = contentType
		self.windowBounds = windowBounds
		self.rootBounds = rootBounds
		self.rootFrame = rootFrame
		self.contentBounds = contentBounds
		self.contentFrame = contentFrame
		self.safeAreaInsets = safeAreaInsets
		self.windowIsHidden = windowIsHidden
		self.windowIsKey = windowIsKey
		self.rootMatchesExpected = rootMatchesExpected
	}
}

public struct Babel2LaunchTraceEvent: Codable, Sendable, Equatable {
	public let sessionID: String
	public let sequence: Int
	public let uptime: TimeInterval
	public let kind: Babel2LaunchTraceEventKind
	public let source: String
	public let detail: String?
	/// For a selected event this is the exact name supplied to UIKit's
	/// Info.plist lookup. For an observed event it is UIKit's returned value,
	/// which may be nil under the SDK contract.
	public let configurationName: String?
	/// Tri-state evidence for the raw configuration name: nil means UIKit
	/// returned no name, true is the fixed Babel2 name, and false is any other
	/// non-nil value. A wrong raw string is never serialized; this boolean is
	/// intentionally retained as privacy-safe evidence.
	public let configurationNameMatchesExpected: Bool?
	public let storyboardPresent: Bool?
	public let delegateClassName: String?
	public let delegateMatchesExpected: Bool?
	public let surface: Babel2TraceSurface?

	public init(
		sessionID: String,
		sequence: Int,
		uptime: TimeInterval,
		kind: Babel2LaunchTraceEventKind,
		source: String = "unknown",
		detail: String? = nil,
		configurationName: String? = nil,
		configurationNameMatchesExpected: Bool? = nil,
		storyboardPresent: Bool? = nil,
		delegateClassName: String? = nil,
		delegateMatchesExpected: Bool? = nil,
		surface: Babel2TraceSurface? = nil
	) {
		self.sessionID = sessionID
		self.sequence = sequence
		self.uptime = uptime
		self.kind = kind
		self.source = Babel2TracePrivacy.safeText(source) ?? "unknown"
		self.detail = Babel2TracePrivacy.safeText(detail)
		self.configurationName = Babel2TracePrivacy.safeConfigurationName(configurationName)
		self.configurationNameMatchesExpected = configurationName.map { $0 == Babel2TracePrivacy.expectedConfigurationName } ?? configurationNameMatchesExpected
		self.storyboardPresent = storyboardPresent
		self.delegateClassName = Babel2TracePrivacy.safeDelegateClassName(delegateClassName)
		self.delegateMatchesExpected = delegateMatchesExpected
		self.surface = surface
	}

	public var structuredJSONLine: String {
		let encoder = JSONEncoder()
		encoder.outputFormatting = [.sortedKeys]
		guard let data = try? encoder.encode(self) else { return "{}" }
		return String(decoding: data, as: UTF8.self)
	}
}

public struct Babel2LaunchTrace: Sendable, Equatable {
	public let origin: String
	public let bundleIdentifier: String
	public let bundleVersion: String
	public let bundleBuild: String
	public let generation: Babel2Generation
	public let reason: Babel2FeatureGateReason
	public let buildChannel: Babel2BuildChannel
	public let processEntryUptime: TimeInterval
	public let gateUptime: TimeInterval
	public let sessionID: String
	public let events: [Babel2LaunchTraceEvent]

	/// The selected event stores the exact lookup input, not a claim about the
	/// nullable name UIKit may return from that lookup.
	public var selectedSceneConfigurationLookupName: String? {
		events.last(where: { $0.kind == .sceneConfigurationSelected })?.configurationName
	}

	/// Compatibility spelling for callers that only need the selected lookup
	/// value. It does not synthesize a returned UIKit configuration name.
	public var selectedSceneConfigurationName: String? { selectedSceneConfigurationLookupName }

	public var observedSceneConfigurationName: String? {
		events.last(where: { $0.kind == .sceneConfigurationObserved })?.configurationName
	}

	/// Compatibility projection intentionally returns only the observed session
	/// value. It never synthesizes the expected app configuration.
	public var sceneConfigurationName: String? { observedSceneConfigurationName }

	public var sceneConfigurationObserved: Bool {
		events.contains { $0.kind == .sceneConfigurationObserved }
	}

	public var rootInstalled: Bool {
		events.contains { $0.kind == .rootInstalled }
	}

	public var rootVisible: Bool {
		events.contains { $0.kind == .rootVisible }
	}

	public var containerAppeared: Bool {
		events.contains { $0.kind == .containerAppeared }
	}

	public var contentFirstFramePresented: Bool {
		events.contains { $0.kind == .contentFirstFramePresented }
	}

	public var firstFramePresented: Bool { contentFirstFramePresented }

	public var rootInstalledUptime: TimeInterval? {
		events.last(where: { $0.kind == .rootInstalled })?.uptime
	}

	public var rootVisibleUptime: TimeInterval? {
		events.last(where: { $0.kind == .rootVisible })?.uptime
	}

	public var containerAppearedUptime: TimeInterval? {
		events.last(where: { $0.kind == .containerAppeared })?.uptime
	}

	public var contentFirstFrameUptime: TimeInterval? {
		events.last(where: { $0.kind == .contentFirstFramePresented })?.uptime
	}

	public var firstFrameUptime: TimeInterval? { contentFirstFrameUptime }

	public var legacyLifecycleStarted: Bool {
		events.contains { $0.kind == .legacyUILifecycle }
	}

	public var legacyBootstrapStarted: Bool {
		events.contains { $0.kind == .legacyBootstrap }
	}

	public var legacyStoryboardInstantiations: Int {
		count(of: .legacyStoryboardDecode)
	}

	public var legacyCoordinatorCreations: Int {
		count(of: .legacySceneCoordinator)
	}

	public var legacyWebViewBootstrapCalls: Int {
		count(of: .legacyWebViewBootstrap)
	}

	/// A trace is complete when expected single-generation launch milestones
	/// have all been observed. Legacy events are represented separately in
	/// `invalidReasons`, so a complete trace can still be invalid fail-closed.
	public var isComplete: Bool {
		let missingReasons: Set<Babel2LaunchTraceInvalidReason> = [
			.processEntryMissing,
			.processEntryEvidenceInvalid,
			.decisionMissing,
			.sceneConfigurationSelectionMissing,
			.sceneConfigurationObservationMissing,
			.sceneConfigurationNameMissing,
			.sceneConfigurationStoryboardEvidenceMissing,
			.sceneConfigurationDelegateInvalid,
			.launchMilestoneDuplicate,
			.launchMilestoneSurfaceInvalid,
			.rootInstallationMissing,
			.rootVisibleMissing,
			.containerAppearanceMissing,
			.contentFirstFrameMissing
		]
		return invalidReasons.allSatisfy { !missingReasons.contains($0) }
	}

	public var invalidReasons: [Babel2LaunchTraceInvalidReason] {
		var reasons = [Babel2LaunchTraceInvalidReason]()
		func append(_ reason: Babel2LaunchTraceInvalidReason) {
			if !reasons.contains(reason) { reasons.append(reason) }
		}

		let processEntryEvents = events.filter { $0.kind == .processEntry }
		if events.first?.kind != .processEntry { append(.processEntryMissing) }
		if processEntryEvents.count > 1 { append(.launchMilestoneDuplicate) }
		if let processEntryEvent = processEntryEvents.first,
			(!processEntryUptime.isFinite || !gateUptime.isFinite ||
			 processEntryEvent.uptime != processEntryUptime || processEntryUptime > gateUptime) {
			append(.processEntryEvidenceInvalid)
		}
		if !events.contains(where: { $0.kind == .decision }) { append(.decisionMissing) }
		if let decisionEvent = events.first(where: { $0.kind == .decision }), decisionEvent.uptime != gateUptime {
			append(.decisionUptimeMismatch)
		}
		if events.enumerated().contains(where: { $0.element.sequence != $0.offset }) {
			append(.eventSequenceInvalid)
		}
		if events.contains(where: { !$0.uptime.isFinite }) {
			append(.eventUptimeInvalid)
		} else if zip(events, events.dropFirst()).contains(where: { $0.uptime > $1.uptime }) {
			append(.eventUptimeInvalid)
		}
		if events.contains(where: { $0.sessionID != sessionID }) {
			append(.eventSessionMismatch)
		}
		let milestoneKinds: [Babel2LaunchTraceEventKind] = [
			.processEntry,
			.decision,
			.sceneConfigurationSelected,
			.sceneConfigurationObserved,
			.rootInstalled,
			.rootVisible,
			.containerAppeared,
			.contentFirstFramePresented
		]
		if milestoneKinds.contains(where: { kind in events.filter { $0.kind == kind }.count > 1 }) {
			append(.launchMilestoneDuplicate)
		}
		let milestoneIndices = milestoneKinds.compactMap { kind in
			events.firstIndex(where: { $0.kind == kind })
		}
		if milestoneIndices.count == milestoneKinds.count,
			milestoneIndices != milestoneIndices.sorted() {
			append(.eventOrderInvalid)
		}

		if generation != .babel2 { append(.nonBabel2Decision) }
		let selectedEvents = events.filter { $0.kind == .sceneConfigurationSelected }
		let observedEvents = events.filter { $0.kind == .sceneConfigurationObserved }
		if selectedEvents.isEmpty {
			append(.sceneConfigurationSelectionMissing)
		} else {
			if selectedEvents.contains(where: { $0.configurationName == nil && $0.configurationNameMatchesExpected == nil }) {
				append(.sceneConfigurationNameMissing)
			}
			if selectedEvents.contains(where: {
				$0.configurationName != Babel2TracePrivacy.expectedConfigurationName ||
				$0.configurationNameMatchesExpected != true
			}) {
				append(.sceneConfigurationMismatch)
			}
		}
		if observedEvents.isEmpty {
			append(.sceneConfigurationObservationMissing)
		} else {
			if observedEvents.contains(where: { $0.storyboardPresent == nil }) {
				append(.sceneConfigurationStoryboardEvidenceMissing)
			}
			if observedEvents.contains(where: { $0.storyboardPresent == true }) {
				append(.sceneConfigurationStoryboardPresent)
			}
			if observedEvents.contains(where: {
				$0.delegateClassName != Babel2TracePrivacy.expectedDelegateClassName || $0.delegateMatchesExpected != true
			}) {
				append(.sceneConfigurationDelegateInvalid)
			}
			if observedEvents.contains(where: {
				$0.configurationNameMatchesExpected == false ||
				($0.configurationName != nil && $0.configurationName != Babel2TracePrivacy.expectedConfigurationName) ||
				($0.configurationName == nil && $0.configurationNameMatchesExpected == true)
			}) {
				append(.sceneConfigurationMismatch)
			}
		}
		if let observedSceneConfigurationName,
			observedSceneConfigurationName != Babel2TracePrivacy.expectedConfigurationName {
			append(.sceneConfigurationMismatch)
		}
		if let selectedSceneConfigurationName,
			let observedSceneConfigurationName,
			selectedSceneConfigurationName != observedSceneConfigurationName {
			append(.sceneConfigurationMismatch)
		}
		if !rootInstalled { append(.rootInstallationMissing) }
		if !rootVisible { append(.rootVisibleMissing) }
		if !containerAppeared { append(.containerAppearanceMissing) }
		if !contentFirstFramePresented { append(.contentFirstFrameMissing) }
		let surfaceKinds = [
			Babel2LaunchTraceEventKind.rootInstalled,
			.rootVisible,
			.containerAppeared,
			.contentFirstFramePresented
		]
		if events.contains(where: {
			guard surfaceKinds.contains($0.kind) else { return false }
			switch $0.kind {
			case .rootInstalled:
				return !($0.surface?.hasValidGeometry ?? false)
			case .rootVisible, .containerAppeared, .contentFirstFramePresented:
				return !($0.surface?.isVisibleAndGeometricallyValid ?? false)
			default:
				return false
			}
		}) {
			append(.launchMilestoneSurfaceInvalid)
		}

		for event in events {
			switch event.kind {
			case .legacyUILifecycle: append(.legacyUILifecycle)
			case .legacyBootstrap: append(.legacyBootstrap)
			case .legacyStoryboardDecode: append(.legacyStoryboardDecode)
			case .legacySceneCoordinator: append(.legacySceneCoordinator)
			case .legacyWebViewBootstrap: append(.legacyWebViewBootstrap)
			default: break
			}
		}
		return reasons
	}

	public var isValid: Bool { invalidReasons.isEmpty }

	public var diagnosticSummary: String {
		let selected = selectedSceneConfigurationLookupName ?? "none"
		let observed = observedSceneConfigurationName ?? "none"
		let reasons = invalidReasons.map(\.rawValue).joined(separator: ",")
		return "origin=\(origin) sessionID=\(sessionID) generation=\(generation.rawValue) reason=\(reason.rawValue) buildChannel=\(buildChannel.rawValue) bundleIdentifier=\(bundleIdentifier) bundleVersion=\(bundleVersion) bundleBuild=\(bundleBuild) processEntryUptime=\(processEntryUptime) gateUptime=\(gateUptime) selectedSceneConfigurationLookup=\(selected) observedSceneConfiguration=\(observed) rootInstalled=\(rootInstalled) rootVisible=\(rootVisible) containerAppeared=\(containerAppeared) contentFirstFramePresented=\(contentFirstFramePresented) isComplete=\(isComplete) isValid=\(isValid) invalidReasons=\(reasons.isEmpty ? "none" : reasons) legacyLifecycleStarted=\(legacyLifecycleStarted) legacyBootstrapStarted=\(legacyBootstrapStarted) legacyStoryboardInstantiations=\(legacyStoryboardInstantiations) legacyCoordinatorCreations=\(legacyCoordinatorCreations) legacyWebViewBootstrapCalls=\(legacyWebViewBootstrapCalls) eventCount=\(events.count)"
	}

	public var structuredJSONLine: String {
		let document = Babel2LaunchTraceDocument(
			origin: origin,
			sessionID: sessionID,
			bundleIdentifier: bundleIdentifier,
			bundleVersion: bundleVersion,
			bundleBuild: bundleBuild,
			generation: generation,
			reason: reason,
			buildChannel: buildChannel,
			processEntryUptime: processEntryUptime,
			gateUptime: gateUptime,
			selectedSceneConfigurationLookupName: selectedSceneConfigurationLookupName,
			observedSceneConfigurationName: observedSceneConfigurationName,
			isComplete: isComplete,
			isValid: isValid,
			invalidReasons: invalidReasons,
			events: events
		)
		let encoder = JSONEncoder()
		encoder.outputFormatting = [.sortedKeys]
		guard let data = try? encoder.encode(document) else { return "{}" }
		return String(decoding: data, as: UTF8.self)
	}

	/// A short result record for OSLog. Event details are emitted separately so
	/// the final result cannot be truncated together with the event history.
	public var resultJSONLine: String {
		let document = Babel2LaunchTraceResultDocument(
			origin: origin,
			sessionID: sessionID,
			bundleIdentifier: bundleIdentifier,
			bundleVersion: bundleVersion,
			bundleBuild: bundleBuild,
			generation: generation,
			reason: reason,
			buildChannel: buildChannel,
			processEntryUptime: processEntryUptime,
			gateUptime: gateUptime,
			selectedSceneConfigurationLookupName: selectedSceneConfigurationLookupName,
			observedSceneConfigurationName: observedSceneConfigurationName,
			isComplete: isComplete,
			isValid: isValid,
			invalidReasons: invalidReasons,
			legacyLifecycleStarted: legacyLifecycleStarted,
			legacyBootstrapStarted: legacyBootstrapStarted,
			legacyStoryboardInstantiations: legacyStoryboardInstantiations,
			legacyCoordinatorCreations: legacyCoordinatorCreations,
			legacyWebViewBootstrapCalls: legacyWebViewBootstrapCalls,
			eventCount: events.count
		)
		let encoder = JSONEncoder()
		encoder.outputFormatting = [.sortedKeys]
		guard let data = try? encoder.encode(document) else { return "{}" }
		return String(decoding: data, as: UTF8.self)
	}

	public init(
		decision: Babel2FeatureGateDecision,
		buildChannel: Babel2BuildChannel,
		gateUptime: TimeInterval,
		sessionID: String,
		events: [Babel2LaunchTraceEvent],
		processEntryUptime: TimeInterval? = nil,
		origin: String = "productionLaunch",
		bundleIdentifier: String = "unknown",
		bundleVersion: String = "unknown",
		bundleBuild: String = "unknown"
	) {
		self.origin = origin
		self.bundleIdentifier = bundleIdentifier
		self.bundleVersion = bundleVersion
		self.bundleBuild = bundleBuild
		generation = decision.generation
		reason = decision.reason
		self.buildChannel = buildChannel
		self.processEntryUptime = processEntryUptime ?? gateUptime
		self.gateUptime = gateUptime
		self.sessionID = sessionID
		self.events = events
	}

	private func count(of kind: Babel2LaunchTraceEventKind) -> Int {
		events.lazy.filter { $0.kind == kind }.count
	}
}

private struct Babel2LaunchTraceDocument: Codable {
	let origin: String
	let sessionID: String
	let bundleIdentifier: String
	let bundleVersion: String
	let bundleBuild: String
	let generation: Babel2Generation
	let reason: Babel2FeatureGateReason
	let buildChannel: Babel2BuildChannel
	let processEntryUptime: TimeInterval
	let gateUptime: TimeInterval
	let selectedSceneConfigurationLookupName: String?
	let observedSceneConfigurationName: String?
	let isComplete: Bool
	let isValid: Bool
	let invalidReasons: [Babel2LaunchTraceInvalidReason]
	let events: [Babel2LaunchTraceEvent]
}

private struct Babel2LaunchTraceResultDocument: Codable {
	let origin: String
	let sessionID: String
	let bundleIdentifier: String
	let bundleVersion: String
	let bundleBuild: String
	let generation: Babel2Generation
	let reason: Babel2FeatureGateReason
	let buildChannel: Babel2BuildChannel
	let processEntryUptime: TimeInterval
	let gateUptime: TimeInterval
	let selectedSceneConfigurationLookupName: String?
	let observedSceneConfigurationName: String?
	let isComplete: Bool
	let isValid: Bool
	let invalidReasons: [Babel2LaunchTraceInvalidReason]
	let legacyLifecycleStarted: Bool
	let legacyBootstrapStarted: Bool
	let legacyStoryboardInstantiations: Int
	let legacyCoordinatorCreations: Int
	let legacyWebViewBootstrapCalls: Int
	let eventCount: Int
}

private enum Babel2TracePrivacy {
	static let expectedConfigurationName = "Babel2 Configuration"
	static let expectedDelegateClassName = "SceneDelegate"

	static func safeText(_ value: String?) -> String? {
		guard let value else { return nil }
		let normalized = value.split(whereSeparator: { $0.isWhitespace }).map { token in
			let text = String(token)
			if text.contains("://") || text.hasPrefix("/") || text.hasPrefix("~/") {
				return "[redacted]"
			}
			return text
		}.joined(separator: " ")
		return String(normalized.prefix(160))
	}

	static func safeConfigurationName(_ value: String?) -> String? {
		guard value == expectedConfigurationName else { return nil }
		return expectedConfigurationName
	}

	static func safeDelegateClassName(_ value: String?) -> String? {
		guard let value else { return nil }
		let normalized = value.split(separator: ".").last.map(String.init) ?? value
		return normalized == expectedDelegateClassName ? expectedDelegateClassName : "[redacted]"
	}
}

@MainActor
public final class Babel2LaunchTraceRecorder {
	private let decision: Babel2FeatureGateDecision
	private let buildChannel: Babel2BuildChannel
	private let processEntryUptime: TimeInterval
	private let gateUptime: TimeInterval
	private let origin: String
	private let bundleIdentifier: String
	private let bundleVersion: String
	private let bundleBuild: String
	private(set) public var snapshot: Babel2LaunchTrace
	private var nextSequence = 0

	public init(
		decision: Babel2FeatureGateDecision,
		buildChannel: Babel2BuildChannel,
		gateUptime: TimeInterval,
		processEntryUptime: TimeInterval? = nil,
		sessionID: String = UUID().uuidString,
		origin: String = "productionLaunch",
		bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "unknown",
		bundleVersion: String = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "unknown",
		bundleBuild: String = (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "unknown"
	) {
		self.decision = decision
		self.buildChannel = buildChannel
		self.processEntryUptime = processEntryUptime ?? gateUptime
		self.gateUptime = gateUptime
		self.origin = origin
		self.bundleIdentifier = bundleIdentifier
		self.bundleVersion = bundleVersion
		self.bundleBuild = bundleBuild
		snapshot = Babel2LaunchTrace(
			decision: decision,
			buildChannel: buildChannel,
			gateUptime: gateUptime,
			sessionID: sessionID,
			events: [],
			processEntryUptime: self.processEntryUptime,
			origin: origin,
			bundleIdentifier: bundleIdentifier,
			bundleVersion: bundleVersion,
			bundleBuild: bundleBuild
		)
		append(.processEntry, source: "AppDelegate.init", uptime: self.processEntryUptime)
		// The gate timestamp is captured by AppDelegate before this recorder is
		// created. Keep it exact; append must not read the clock a second time.
		append(.decision, source: "AppDelegate.init", detail: decision.reason.rawValue, uptime: gateUptime)
	}

	public func recordSceneConfigurationSelected(_ name: String?, source: String = "AppDelegate.configurationForConnecting") {
		append(.sceneConfigurationSelected, source: source, configurationName: name)
	}

	public func recordSceneConfigurationObserved(
		name: String?,
		delegateClassName: String?,
		delegateMatchesExpected: Bool,
		storyboardPresent: Bool,
		source: String = "scene.connection.observed"
	) {
		let delegate = Babel2TracePrivacy.safeDelegateClassName(delegateClassName)
		append(
			.sceneConfigurationObserved,
			source: source,
			detail: "delegate=\(delegate ?? "none") storyboardPresent=\(storyboardPresent)",
			configurationName: name,
			storyboardPresent: storyboardPresent,
			delegateClassName: delegate,
			delegateMatchesExpected: delegateMatchesExpected
		)
	}

	public func recordRootInstalled(surface: Babel2TraceSurface, source: String = "scene.root.installed") {
		append(.rootInstalled, source: source, surface: surface)
	}

	public func recordRootVisible(surface: Babel2TraceSurface, source: String = "scene.root.visible") {
		append(.rootVisible, source: source, surface: surface)
	}

	public func recordContainerAppeared(surface: Babel2TraceSurface, source: String = "Babel2NavigationController.viewDidAppear") {
		append(.containerAppeared, source: source, surface: surface)
	}

	public func recordContentFirstFramePresented(surface: Babel2TraceSurface, source: String = "Babel2RootViewController.contentFirstFrame") {
		append(.contentFirstFramePresented, source: source, surface: surface)
	}

	public func recordTeardown(_ detail: String, source: String = "scene.disconnected") {
		append(.teardown, source: source, detail: detail)
	}

	public func recordLegacyUILifecycle(source: String, detail: String? = nil, uptime: TimeInterval? = nil) {
		append(.legacyUILifecycle, source: source, detail: detail, uptime: uptime)
	}

	public func recordLegacyBootstrap(source: String, detail: String? = nil, uptime: TimeInterval? = nil) {
		append(.legacyBootstrap, source: source, detail: detail, uptime: uptime)
	}

	/// A blank WebView is observable only until Babel2 has presented its first
	/// content surface. Later WebView work is outside the launch boundary.
	@discardableResult
	public func recordLegacyBlankWebViewBootstrap(source: String, detail: String? = nil, uptime: TimeInterval? = nil) -> Bool {
		guard !snapshot.contentFirstFramePresented else { return false }
		append(.legacyBootstrap, source: source, detail: detail, uptime: uptime)
		return true
	}

	public func recordLegacyStoryboardDecode(source: String, detail: String? = nil, uptime: TimeInterval? = nil) {
		append(.legacyStoryboardDecode, source: source, detail: detail, uptime: uptime)
	}

	public func recordLegacyCoordinatorCreation(source: String, detail: String? = nil, uptime: TimeInterval? = nil) {
		append(.legacySceneCoordinator, source: source, detail: detail, uptime: uptime)
	}

	@discardableResult
	public func recordLegacyWebViewBootstrap(source: String, detail: String? = nil, uptime: TimeInterval? = nil) -> Bool {
		guard !snapshot.contentFirstFramePresented else { return false }
		append(.legacyWebViewBootstrap, source: source, detail: detail, uptime: uptime)
		return true
	}

	private func append(
		_ kind: Babel2LaunchTraceEventKind,
		source: String,
		detail: String? = nil,
		configurationName: String? = nil,
		configurationNameMatchesExpected: Bool? = nil,
		storyboardPresent: Bool? = nil,
		delegateClassName: String? = nil,
		delegateMatchesExpected: Bool? = nil,
		surface: Babel2TraceSurface? = nil,
		uptime: TimeInterval? = nil
	) {
		let event = Babel2LaunchTraceEvent(
			sessionID: snapshot.sessionID,
			sequence: nextSequence,
			uptime: uptime ?? ProcessInfo.processInfo.systemUptime,
			kind: kind,
			source: source,
			 detail: detail,
			 configurationName: configurationName,
			 configurationNameMatchesExpected: configurationNameMatchesExpected,
			storyboardPresent: storyboardPresent,
			delegateClassName: delegateClassName,
			delegateMatchesExpected: delegateMatchesExpected,
			surface: surface
		)
		nextSequence += 1
		snapshot = Babel2LaunchTrace(
			decision: decision,
			buildChannel: buildChannel,
			gateUptime: gateUptime,
			sessionID: snapshot.sessionID,
			events: snapshot.events + [event],
			processEntryUptime: processEntryUptime,
			origin: origin,
			bundleIdentifier: bundleIdentifier,
			bundleVersion: bundleVersion,
			bundleBuild: bundleBuild
		)
	}
}

/// The application has one runtime. Launch arguments and persisted generation
/// values are intentionally not inputs to this decision.
public enum Babel2FeatureGate {
	public static func decision(buildChannel: Babel2BuildChannel) -> Babel2FeatureGateDecision {
		Babel2FeatureGateDecision(
			generation: .babel2,
			reason: .babel2OnlyRuntime,
			diagnostics: ["single Babel2 runtime; launch arguments ignored"]
		)
	}
}
