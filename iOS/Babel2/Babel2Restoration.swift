import Foundation

public enum Babel2RouteState: String, Codable, CaseIterable, Sendable {
	case home
	case settings
	case addSubscription
}

public struct Babel2NavigationRestoration: Codable, Equatable, Sendable {
	public static let currentSchemaVersion = 1

	public let generation: Babel2Generation
	public let schemaVersion: Int
	public let routes: [Babel2RouteState]

	public init(
		generation: Babel2Generation = .babel2,
		schemaVersion: Int = Babel2NavigationRestoration.currentSchemaVersion,
		routes: [Babel2RouteState] = [.home]
	) {
		self.generation = generation
		self.schemaVersion = schemaVersion
		self.routes = routes
	}

	public var isValid: Bool {
		guard generation == .babel2, schemaVersion == Self.currentSchemaVersion else { return false }
		switch routes {
		case [.home], [.home, .settings], [.home, .addSubscription]: return true
		default: return false
		}
	}

	public var safeValue: Babel2NavigationRestoration {
		isValid ? self : Babel2NavigationRestoration()
	}

	public func encoded() throws -> Data {
		try JSONEncoder().encode(self)
	}

	public static func decoded(_ data: Data) -> Babel2NavigationRestoration {
		guard let value = try? JSONDecoder().decode(Self.self, from: data) else {
			return Self()
		}
		return value.safeValue
	}

	/// Returns nil for corrupt, stale, or cross-generation state. Invalid state
	/// is discarded by the single Babel2 scene owner.
	public static func validated(_ data: Data) -> Babel2NavigationRestoration? {
		guard let value = try? JSONDecoder().decode(Self.self, from: data), value.isValid else {
			return nil
		}
		return value
	}
}
