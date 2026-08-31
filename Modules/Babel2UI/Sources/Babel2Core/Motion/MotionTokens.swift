import Foundation

public enum MotionTokenProvenance: String, Equatable, Sendable {
	case measured
	case reference
	case target
	case toTune
}

public struct MotionScalarToken: Equatable, Sendable {
	public let value: Double
	public let provenance: MotionTokenProvenance
	public let note: String

	public init(value: Double, provenance: MotionTokenProvenance, note: String) {
		if value.isNaN || value == -.infinity {
			self.value = 0
		} else if value == .infinity {
			self.value = Double.greatestFiniteMagnitude
		} else {
			self.value = value
		}
		self.provenance = provenance
		self.note = note
	}

}

public struct MotionRangeToken: Equatable, Sendable {
	public let lowerBound: Double
	public let upperBound: Double
	public let provenance: MotionTokenProvenance
	public let note: String

	public init(
		lowerBound: Double,
		upperBound: Double,
		provenance: MotionTokenProvenance,
		note: String
	) {
		let finiteLower = lowerBound.isFinite ? lowerBound : 0
		let finiteUpper = upperBound.isFinite ? upperBound : finiteLower
		self.lowerBound = max(0, min(finiteLower, finiteUpper))
		self.upperBound = max(self.lowerBound, max(0, max(finiteLower, finiteUpper)))
		self.provenance = provenance
		self.note = note
	}

	public func clamped(_ rawValue: Double) -> Double {
		if rawValue.isNaN || rawValue == -.infinity { return lowerBound }
		if rawValue == .infinity { return upperBound }
		guard rawValue.isFinite else { return lowerBound }
		return min(max(rawValue, lowerBound), upperBound)
	}
}

/// Babel 2.0 motion values. Values marked `toTune` are starting ranges only;
/// none of them claim to be an exact Reeder measurement.
public enum Babel2MotionTokens {
	public static let controlHitTarget = MotionScalarToken(
		value: 44,
		provenance: .reference,
		note: "Figma interaction contract control hit target"
	)

	public static let toolbarDirectionHysteresis = MotionScalarToken(
		value: 12,
		provenance: .reference,
		note: "Figma reader toolbar direction accumulator"
	)

	public static let chromeSettleDuration = MotionScalarToken(
		value: 0.18,
		provenance: .reference,
		note: "Figma reader chrome transition; validate on physical device"
	)

	public static let finishThreshold = MotionScalarToken(
		value: 0.5,
		provenance: .target,
		note: "Babel 2.0 projected-progress acceptance target"
	)

	public static let edgeActivationWidth = MotionRangeToken(
		lowerBound: 24,
		upperBound: 32,
		provenance: .toTune,
		note: "Initial edge-only gesture range; not a Reeder measurement"
	)

	public static let projectionDuration = MotionRangeToken(
		lowerBound: 0.12,
		upperBound: 0.18,
		provenance: .toTune,
		note: "Bounded velocity projection window"
	)

	public static let fullRouteSettleDuration = MotionRangeToken(
		lowerBound: 0.20,
		upperBound: 0.34,
		provenance: .toTune,
		note: "Initial settle range; no frame-by-frame Reeder evidence"
	)
}
