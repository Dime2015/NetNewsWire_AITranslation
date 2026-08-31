#if canImport(UIKit)
import UIKit
import Babel2Core

@MainActor
protocol Babel2Animator: AnyObject {
	var fractionComplete: CGFloat { get }
	func startAnimation()
	func stopAnimation(withoutFinishing: Bool)
	func addCompletion(_ completion: @escaping () -> Void)
}

@MainActor
private final class UIKitBabel2Animator: Babel2Animator {
	private let animator: UIViewPropertyAnimator

	init(duration: TimeInterval, animations: @escaping () -> Void) {
		animator = UIViewPropertyAnimator(duration: duration, curve: .linear, animations: animations)
	}

	var fractionComplete: CGFloat { animator.fractionComplete }
	func startAnimation() { animator.startAnimation() }
	func stopAnimation(withoutFinishing: Bool) {
		animator.stopAnimation(withoutFinishing)
	}
	func addCompletion(_ completion: @escaping () -> Void) {
		animator.addCompletion { _ in completion() }
	}
}

@MainActor
protocol Babel2AnimatorFactory: AnyObject {
	func make(duration: TimeInterval, animations: @escaping () -> Void) -> any Babel2Animator
}

@MainActor
private final class UIKitBabel2AnimatorFactory: Babel2AnimatorFactory {
	func make(duration: TimeInterval, animations: @escaping () -> Void) -> any Babel2Animator {
		UIKitBabel2Animator(duration: duration, animations: animations)
	}
}

/// A single-owner UIKit motion driver. `update` writes the current render state
/// directly; only terminal methods create a property animator.
@MainActor
public final class Babel2MotionDriver {
	public typealias Renderer = @MainActor (_ progress: MotionProgress) -> Void

	private let renderer: Renderer
	private let recorder: any Babel2MotionRecording
	private let animatorFactory: any Babel2AnimatorFactory
	private var animator: (any Babel2Animator)?
	private var animatorStart = MotionProgress.zero
	private var animatorEnd = MotionProgress.zero
	private var currentProgress = MotionProgress.zero
	private var sequence: UInt64 = 0
	private var activeToken: MotionInteractionToken?
	private var pendingOutcome: MotionOutcome?
	private var terminalOutcome: MotionOutcome?
	private var lastTerminalToken: MotionInteractionToken?
	private var activeRecognizer: String?
	private var activeSettleDuration: TimeInterval?
	private var activeProjectedProgress: MotionProgress?

	public private(set) var state: MotionState = .idle

	public init(
		renderer: @escaping Renderer,
		recorder: any Babel2MotionRecording = Babel2NullMotionRecorder()
	) {
		self.renderer = renderer
		self.recorder = recorder
		self.animatorFactory = UIKitBabel2AnimatorFactory()
	}

	init(
		renderer: @escaping Renderer,
		recorder: any Babel2MotionRecording,
		animatorFactory: any Babel2AnimatorFactory
	) {
		self.renderer = renderer
		self.recorder = recorder
		self.animatorFactory = animatorFactory
	}

	public var token: MotionInteractionToken? { activeToken }

	@discardableResult
	public func begin(
		interaction: MotionInteractionID,
		route: MotionRouteIdentity = .default,
		recognizer: String? = nil
	) -> MotionInteractionToken {
		if let activeToken, state != .idle, let replacement = interrupt(token: activeToken, newIntent: interaction, route: route, recognizer: recognizer) {
			return replacement
		}
		// A completed interaction is a new origin. Do not carry the previous
		// route's endpoint into an unrelated gesture.
		if activeToken == nil, state.isTerminal {
			currentProgress = .zero
		}
		return startNewInteraction(interaction: interaction, route: route, recognizer: recognizer)
	}

	@discardableResult
	public func update(token: MotionInteractionToken, progress: MotionProgress) -> Bool {
		guard activeToken == token, case .tracking = state else { return false }
		currentProgress = progress
		state = .tracking(progress: progress)
		renderer(progress)
		recorder.record(MotionSignpostEvent(
			baseName: .track,
			interaction: token.interaction,
			route: token.route,
			recognizer: activeRecognizer,
			token: token,
			progress: progress
		))
		return true
	}

	@discardableResult
	public func update(token: MotionInteractionToken, rawProgress: Double) -> MotionUpdateResult {
		guard rawProgress.isFinite else { return .rejected }
		return update(token: token, progress: MotionProgress(rawProgress)) ? .accepted : .ignored
	}

	@discardableResult
	public func finish(token: MotionInteractionToken, duration: TimeInterval? = nil) -> MotionCommandResult {
		guard duration.map(\.isFinite) ?? true else { return .rejected }
		return settle(token: token, to: .one, outcome: .finished, duration: duration)
	}

	@discardableResult
	public func cancel(token: MotionInteractionToken, duration: TimeInterval? = nil) -> MotionCommandResult {
		guard duration.map(\.isFinite) ?? true else { return .rejected }
		return settle(token: token, to: .zero, outcome: .cancelled, duration: duration)
	}

	/// Ends tracking using the same bounded projected-progress rule for every
	/// directional transition. `velocity` must already be expressed in points
	/// per second toward the driver's end state; use
	/// `MotionProjection.velocityTowardEnd` at the gesture boundary.
	@discardableResult
	public func end(
		token: MotionInteractionToken,
		velocity: Double = 0,
		extent: Double = 1,
		duration: TimeInterval? = nil,
		direction: MotionVelocityDirection = .positive
	) -> MotionCommandResult {
		guard velocity.isFinite, extent.isFinite, extent > 0,
			duration.map(\.isFinite) ?? true else { return .rejected }
		guard activeToken == token, case .tracking = state else {
			if lastTerminalToken == token, let terminalOutcome { return .alreadyTerminal(terminalOutcome) }
			return .ignored
		}
		let normalizedVelocity = MotionProjection.velocityTowardEnd(velocity, direction: direction)
		let projectionDuration = Babel2MotionTokens.projectionDuration.clamped(duration ?? 0.15)
		guard case let .projected(projected) = MotionProjection.validatedProjection(
			progress: currentProgress,
			velocity: normalizedVelocity,
			extent: extent,
			duration: projectionDuration,
			durationBounds: Babel2MotionTokens.projectionDuration
		) else { return .rejected }
		let projectionConfiguration = MotionProjectionConfiguration(
			duration: projectionDuration,
			finishThreshold: MotionProgress(Babel2MotionTokens.finishThreshold.value),
			durationBounds: Babel2MotionTokens.projectionDuration
		)
		guard case let .decision(finishDecision) = MotionProjection.validatedFinishDecision(
			progress: currentProgress,
			velocity: normalizedVelocity,
			extent: extent,
			configuration: projectionConfiguration
		) else { return .rejected }
		let outcome: MotionOutcome = finishDecision == .finish ? .finished : .cancelled
		return settle(
			token: token,
			to: outcome == .finished ? .one : .zero,
			outcome: outcome,
			duration: duration,
			projectedProgress: projected
		)
	}

	/// Stops a settling animator at its actual sampled fraction, invalidates the
	/// old token, and returns a new token for the replacement interaction.
	@discardableResult
	public func interrupt(
		token: MotionInteractionToken,
		newIntent: MotionInteractionID,
		route: MotionRouteIdentity? = nil,
		recognizer: String? = nil
	) -> MotionInteractionToken? {
		guard activeToken == token, isInterruptible else { return nil }
		let oldRecognizer = activeRecognizer
		let oldOutcome = pendingOutcome
		let oldDuration = activeSettleDuration
		let oldProjectedProgress = activeProjectedProgress
		if case .tracking = state {
			recorder.record(MotionSignpostEvent(
				baseName: .track,
				interaction: token.interaction,
				route: token.route,
				recognizer: oldRecognizer,
				token: token,
				progress: currentProgress,
				phase: .end
			))
		}
		if animator != nil { interruptActiveAnimator() }
		if let oldOutcome {
			recorder.record(MotionSignpostEvent(
				baseName: .settle,
				interaction: token.interaction,
				route: token.route,
				recognizer: oldRecognizer,
				token: token,
				progress: currentProgress,
				projectedProgress: oldProjectedProgress,
				duration: oldDuration,
				outcome: oldOutcome,
				phase: .end
			))
		}
		let replacement = startNewInteraction(
			interaction: newIntent,
			route: route ?? token.route,
			recognizer: recognizer ?? activeRecognizer,
			withoutBeginSignpost: true,
			withoutTrackingSignpost: true
		)
		recorder.record(MotionSignpostEvent(
			baseName: .interrupt,
			interaction: newIntent,
			route: replacement.route,
			recognizer: recognizer ?? oldRecognizer,
			oldToken: token,
			newToken: replacement,
			sampledProgress: currentProgress
		))
		recorder.record(MotionSignpostEvent(
			baseName: .begin,
			interaction: replacement.interaction,
			route: replacement.route,
			recognizer: activeRecognizer,
			token: replacement,
			progress: currentProgress,
			phase: .begin
		))
		recorder.record(MotionSignpostEvent(
			baseName: .track,
			interaction: replacement.interaction,
			route: replacement.route,
			recognizer: activeRecognizer,
			token: replacement,
			progress: currentProgress,
			phase: .begin
		))
		return replacement
	}

	public func reset() {
		if animator != nil { interruptActiveAnimator() }
		activeToken = nil
		pendingOutcome = nil
		terminalOutcome = nil
		lastTerminalToken = nil
		activeRecognizer = nil
		activeSettleDuration = nil
		activeProjectedProgress = nil
		currentProgress = .zero
		state = .idle
		renderer(.zero)
	}

	private var isInterruptible: Bool {
		switch state {
		case .tracking, .settlingToStart, .settlingToEnd:
			return true
		case .idle, .settled, .cancelled:
			return false
		}
	}

	private func startNewInteraction(
		interaction: MotionInteractionID,
		route: MotionRouteIdentity,
		recognizer: String? = nil,
		withoutBeginSignpost: Bool = false,
		withoutTrackingSignpost: Bool = false
	) -> MotionInteractionToken {
		sequence &+= 1
		let token = MotionInteractionToken(interaction: interaction, route: route, sequence: sequence)
		activeToken = token
		pendingOutcome = nil
		terminalOutcome = nil
		lastTerminalToken = nil
		activeRecognizer = recognizer
		activeSettleDuration = nil
		activeProjectedProgress = nil
		state = .tracking(progress: currentProgress)
		if !withoutBeginSignpost {
			recorder.record(MotionSignpostEvent(
				baseName: .begin,
				interaction: interaction,
				route: route,
				recognizer: recognizer,
				token: token,
				progress: currentProgress,
				phase: .begin
			))
		}
		if !withoutTrackingSignpost {
			recorder.record(MotionSignpostEvent(
			baseName: .track,
			interaction: interaction,
			route: route,
			recognizer: recognizer,
			token: token,
			progress: currentProgress,
			phase: .begin
			))
		}
		renderer(currentProgress)
		return token
	}

	private func settle(
		token: MotionInteractionToken,
		to target: MotionProgress,
		outcome: MotionOutcome,
		duration: TimeInterval?,
		projectedProgress: MotionProgress? = nil
	) -> MotionCommandResult {
		guard activeToken == token else {
			if lastTerminalToken == token, let terminalOutcome { return .alreadyTerminal(terminalOutcome) }
			return .ignored
		}
		if let pendingOutcome { return .alreadySettling(pendingOutcome) }
		if let terminalOutcome { return .alreadyTerminal(terminalOutcome) }
		guard case .tracking = state, animator == nil else { return .ignored }
		let start = currentProgress
		animatorStart = start
		animatorEnd = target
		pendingOutcome = outcome
		state = outcome == .finished ? .settlingToEnd(progress: start) : .settlingToStart(progress: start)
		recorder.record(MotionSignpostEvent(
			baseName: .track,
			interaction: token.interaction,
			route: token.route,
			recognizer: activeRecognizer,
			token: token,
			progress: start,
			phase: .end
		))
		let factoryDuration = Babel2MotionTokens.fullRouteSettleDuration.clamped(
			duration ?? Babel2MotionTokens.fullRouteSettleDuration.lowerBound
		)
		activeSettleDuration = factoryDuration
		activeProjectedProgress = projectedProgress ?? target
		recorder.record(MotionSignpostEvent(
			baseName: .settle,
			interaction: token.interaction,
			route: token.route,
			recognizer: activeRecognizer,
			token: token,
			progress: start,
			projectedProgress: projectedProgress ?? target,
			duration: factoryDuration,
			outcome: outcome,
			phase: .begin
		))

		let created = animatorFactory.make(duration: factoryDuration) { [renderer] in
			renderer(target)
		}
		animator = created
		created.addCompletion { [weak self] in
			guard let self, self.activeToken == token else { return }
			self.currentProgress = target
			self.renderer(target)
			self.animator = nil
			self.pendingOutcome = nil
			self.terminalOutcome = outcome
			self.lastTerminalToken = token
			self.recorder.record(MotionSignpostEvent(
				baseName: .settle,
				interaction: token.interaction,
				route: token.route,
				recognizer: self.activeRecognizer,
				token: token,
				progress: target,
				projectedProgress: self.activeProjectedProgress,
				duration: self.activeSettleDuration,
				outcome: outcome,
				phase: .end
			))
			self.activeSettleDuration = nil
			self.activeProjectedProgress = nil
			self.state = outcome == .cancelled
				? .cancelled(progress: target)
				: .settled(progress: target, outcome: outcome)
			self.activeToken = nil
		}
		created.startAnimation()
		return .started
	}

	private func interruptActiveAnimator() {
		guard let animator else { return }
		let rawFraction = Double(animator.fractionComplete)
		let fraction = rawFraction.isFinite ? min(max(rawFraction, 0), 1) : 0
		let delta = animatorEnd.value - animatorStart.value
		currentProgress = MotionProgress(animatorStart.value + delta * fraction)
		animator.stopAnimation(withoutFinishing: true)
		self.animator = nil
		pendingOutcome = nil
		renderer(currentProgress)
	}
}
#endif
