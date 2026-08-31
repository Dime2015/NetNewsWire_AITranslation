#if canImport(UIKit)
import Babel2Core
import OSLog

@MainActor
public protocol Babel2SignpostBackend: AnyObject {
	func begin(name: MotionSignpostName, payload: String)
	func event(name: MotionSignpostName, payload: String)
	func end(name: MotionSignpostName, payload: String)
}

@MainActor
public final class Babel2NullSignpostBackend: Babel2SignpostBackend {
	public init() {}
	public func begin(name: MotionSignpostName, payload: String) {}
	public func event(name: MotionSignpostName, payload: String) {}
	public func end(name: MotionSignpostName, payload: String) {}
}

@MainActor
private final class Babel2OSLogSignpostBackend: Babel2SignpostBackend {
	private let log = OSLog(subsystem: "com.wenbopan.Babel2", category: "Motion")

	func begin(name: MotionSignpostName, payload: String) {
		os_signpost(.begin, log: log, name: signpostName(name), "%{public}s", payload)
	}

	func event(name: MotionSignpostName, payload: String) {
		os_signpost(.event, log: log, name: signpostName(name), "%{public}s", payload)
	}

	func end(name: MotionSignpostName, payload: String) {
		os_signpost(.end, log: log, name: signpostName(name), "%{public}s", payload)
	}

	private func signpostName(_ name: MotionSignpostName) -> StaticString {
		switch name {
		case .begin: return "Babel2.Motion.Begin"
		case .track: return "Babel2.Motion.Track"
		case .settle: return "Babel2.Motion.Settle"
		case .interrupt: return "Babel2.Motion.Interrupt"
		case .readerChrome: return "Babel2.Reader.Chrome"
		case .readerPager: return "Babel2.Reader.Pager"
		case .feedHero: return "Babel2.Feed.Hero"
		case .libraryFilter: return "Babel2.Library.Filter"
		case .webPrepared: return "Babel2.Web.Prepared"
		case .loadingOwner: return "Babel2.Loading.Owner"
		}
	}
}

@MainActor
public final class Babel2OSLogMotionRecorder: Babel2MotionRecording {
	private let backend: any Babel2SignpostBackend

	public init(backend: (any Babel2SignpostBackend)? = nil) {
		self.backend = backend ?? Babel2OSLogSignpostBackend()
	}

	public func record(_ event: MotionSignpostEvent) {
		switch event.phase {
		case .begin:
			backend.begin(name: event.name, payload: event.diagnosticPayload)
		case .event:
			backend.event(name: event.name, payload: event.diagnosticPayload)
		case .end:
			backend.end(name: event.name, payload: event.diagnosticPayload)
		}
	}
}
#endif
