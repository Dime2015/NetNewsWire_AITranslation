import UIKit
import UIKit.UIGestureRecognizerSubclass

/// 长按弹菜单的手感（2026-09-27 用户：「长按要有震动反馈，到一定程度一下子有一种释放的感觉，然后弹出菜单」）。
///
/// 节奏仿 iOS 系统长按：
/// 1. 蓄力：手指按住 chargeDelay 后，被按的那一块开始慢慢缩到 chargeScale（按到阈值时正好缩到底）
/// 2. 释放：按满 commitDuration（长按阈值）时震一下（中等力度），那一块带一点回弹地弹回原大，同时弹出菜单（菜单也带弹性展开）
/// 3. 中途松手 / 手指挪开 / 开始滚动：平滑恢复，不弹菜单、不震
/// 系统「减弱动态效果」打开时不缩放、不回弹，只保留震动与菜单淡入。
///
/// 这是 ADR-034「不回弹」规则的例外，只用于长按弹菜单（ADR-060，用户明确要求「释放的感觉」）。
@MainActor
enum Babel2LongPressMotion {
	/// 按住多久算长按（与系统默认一致）
	static let commitDuration: TimeInterval = 0.5
	/// 按下后多久开始缩（太早的话，普通点按和滑动也会闪一下）
	static let chargeDelay: TimeInterval = 0.1
	/// 蓄力缩到多大
	static let chargeScale: CGFloat = 0.96
	/// 手指挪开多远就不算长按（与系统长按的容差一致）
	static let allowableMovement: CGFloat = 10
	/// 弹回原大的弹簧：阻尼越小回弹越明显
	static let releaseDamping: CGFloat = 0.55
	static let releaseDuration: TimeInterval = 0.38
	/// 菜单弹性展开：从多大开始、弹簧阻尼、时长
	static let menuStartScale: CGFloat = 0.88
	static let menuDamping: CGFloat = 0.72
	static let menuDuration: TimeInterval = 0.42
}

/// 只「看」手指、从不认领手势：按下 / 挪动 / 松开时回调，不影响列表的点按、滚动和其它手势。
@MainActor
final class Babel2TouchObserver: UIGestureRecognizer, UIGestureRecognizerDelegate {
	var onBegan: ((CGPoint) -> Void)?
	var onMoved: ((CGPoint) -> Void)?
	var onEnded: (() -> Void)?

	init() {
		super.init(target: nil, action: nil)
		cancelsTouchesInView = false
		delaysTouchesBegan = false
		delaysTouchesEnded = false
		delegate = self
	}

	override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
		guard touches.count == 1, numberOfTouches <= 1, let touch = touches.first else {
			onEnded?()
			state = .failed
			return
		}
		onBegan?(touch.location(in: view))
	}

	override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
		guard let touch = touches.first else { return }
		onMoved?(touch.location(in: view))
	}

	override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
		onEnded?()
		state = .failed
	}

	override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
		onEnded?()
		state = .failed
	}

	func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
		true
	}
}

/// 装在一个视图上（首页列表、图片查看器里的图片）：蓄力缩小 → 按满震一下回弹 → 交给 onCommit 弹菜单。
/// - target：按在哪个位置时，缩放哪一块（首页是那一行；返回 nil = 这里不能长按）
/// - onCommit：按满时调用，返回是否真的弹出了东西（弹出了才震动）
@MainActor
final class Babel2LongPressFeedback: NSObject {
	private weak var host: UIView?
	private let target: (CGPoint) -> UIView?
	private let onCommit: (CGPoint) -> Bool
	private let observer = Babel2TouchObserver()
	private let longPress: UILongPressGestureRecognizer
	private let haptic: () -> Void
	private var prepareHaptic: () -> Void

	private var startPoint: CGPoint?
	private weak var pressedView: UIView?
	private var chargeTask: Task<Void, Never>?
	private var chargeAnimator: UIViewPropertyAnimator?
	private var didCommit = false

	/// - haptic：按满时的震动（测试可注入计数）
	init(on host: UIView,
		target: @escaping (CGPoint) -> UIView?,
		haptic: (() -> Void)? = nil,
		onCommit: @escaping (CGPoint) -> Bool) {
		self.host = host
		self.target = target
		self.onCommit = onCommit
		let generator = UIImpactFeedbackGenerator(style: .medium)
		self.haptic = haptic ?? { generator.impactOccurred() }
		self.prepareHaptic = haptic == nil ? { generator.prepare() } : {}
		longPress = UILongPressGestureRecognizer()
		super.init()
		longPress.minimumPressDuration = Babel2LongPressMotion.commitDuration
		longPress.allowableMovement = Babel2LongPressMotion.allowableMovement
		longPress.addTarget(self, action: #selector(longPressed(_:)))
		observer.onBegan = { [weak self] point in self?.touchBegan(at: point) }
		observer.onMoved = { [weak self] point in self?.touchMoved(to: point) }
		observer.onEnded = { [weak self] in self?.touchEnded() }
		host.addGestureRecognizer(observer)
		host.addGestureRecognizer(longPress)
	}

	/// 已有的手势（例如图片查看器的单击关闭、双击放大）要等长按失败再生效时用。
	var longPressGesture: UILongPressGestureRecognizer { longPress }

	// MARK: 蓄力

	private func touchBegan(at point: CGPoint) {
		cancelCharge(animated: false)
		didCommit = false
		startPoint = point
		guard let view = target(point) else { return }
		pressedView = view
		prepareHaptic()
		chargeTask = Task { @MainActor [weak self] in
			try? await Task.sleep(for: .seconds(Babel2LongPressMotion.chargeDelay))
			guard !Task.isCancelled else { return }
			self?.startCharge()
		}
	}

	private func touchMoved(to point: CGPoint) {
		guard let startPoint, !didCommit else { return }
		if hypot(point.x - startPoint.x, point.y - startPoint.y) > Babel2LongPressMotion.allowableMovement {
			cancelCharge(animated: true)
		}
	}

	private func touchEnded() {
		guard !didCommit else { return }
		cancelCharge(animated: true)
	}

	/// 从现在到长按阈值，慢慢缩到 chargeScale（先慢后快一点，像在往下按）。
	private func startCharge() {
		guard let view = pressedView, !Babel2Motion.reduceMotion else { return }
		let remaining = max(0.1, Babel2LongPressMotion.commitDuration - Babel2LongPressMotion.chargeDelay)
		let scale = Babel2LongPressMotion.chargeScale
		let animator = UIViewPropertyAnimator(duration: remaining, curve: .easeIn) {
			view.transform = CGAffineTransform(scaleX: scale, y: scale)
		}
		chargeAnimator = animator
		animator.startAnimation()
	}

	/// 没按满就松手 / 挪开：从当前大小平滑回到原大。
	private func cancelCharge(animated: Bool) {
		chargeTask?.cancel()
		chargeTask = nil
		startPoint = nil
		if let animator = chargeAnimator {
			animator.stopAnimation(true)
			chargeAnimator = nil
		}
		guard let view = pressedView else { return }
		pressedView = nil
		guard view.transform != .identity else { return }
		if animated {
			Babel2Motion.animate(Babel2Motion.quick) { view.transform = .identity }
		} else {
			view.transform = .identity
		}
	}

	// MARK: 释放

	@objc private func longPressed(_ gesture: UILongPressGestureRecognizer) {
		guard gesture.state == .began, let host else { return }
		commit(at: gesture.location(in: host))
	}

	/// 按满：弹回原大（带回弹）、震一下、弹菜单。
	private func commit(at point: CGPoint) {
		chargeTask?.cancel()
		chargeTask = nil
		chargeAnimator?.stopAnimation(true)
		chargeAnimator = nil
		let view = pressedView ?? target(point)
		pressedView = nil
		startPoint = nil
		didCommit = true
		guard let view else { return }
		release(view)
		if onCommit(point) {
			hapticCountForTesting += 1
			haptic()
		}
	}

	private func release(_ view: UIView) {
		guard !Babel2Motion.reduceMotion else {
			view.transform = .identity
			return
		}
		UIView.animate(withDuration: Babel2LongPressMotion.releaseDuration, delay: 0,
			usingSpringWithDamping: Babel2LongPressMotion.releaseDamping, initialSpringVelocity: 0.6,
			options: [.beginFromCurrentState, .allowUserInteraction]) {
			view.transform = .identity
		}
	}

	// MARK: 仅供自动化测试（与真实手指走同一段逻辑，只是不经过手势识别）

	/// 按满后震了几次。
	private(set) var hapticCountForTesting = 0

	func simulateTouchBeganForTesting(at point: CGPoint) {
		touchBegan(at: point)
	}

	/// 直接开始蓄力（跳过 chargeDelay 的等待）。
	func simulateChargeForTesting() {
		chargeTask?.cancel()
		chargeTask = nil
		startCharge()
	}

	func simulateTouchMovedForTesting(to point: CGPoint) {
		touchMoved(to: point)
	}

	func simulateTouchEndedForTesting() {
		touchEnded()
	}

	func simulateCommitForTesting(at point: CGPoint) {
		commit(at: point)
	}
}
