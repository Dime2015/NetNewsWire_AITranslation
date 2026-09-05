import UIKit
import Babel2Core
import Babel2UI

/// [动效] M1 页面消费者：把 `Babel2MotionDriver`（手势动效引擎）接到
/// `Babel2NavigationController` 的左边缘滑动返回手势上。
///
/// 只接管"从左边缘手指拖拽返回"这一条交互路径；点按返回按钮触发的
/// `popBabel2(animated:)` 仍然走系统默认动画，完全不受影响——这个类只在
/// 边缘手势真正开始时才把自己安插进导航控制器的转场代理里，手势不触发时
/// `animationControllerFor`/`interactionControllerFor` 都返回 nil。
///
/// 对应 MOTION-CONTRACT.md 第 6 节"Navigation pop"：
/// `p = clamp(x / W, 0, 1)`，`currentX = W*p`，`previousX = -0.22*W*(1-p)`，
/// `shadowOpacity = 0.18*(1-p)`；松手后的 finish/cancel 判定复用 M1 已经过
/// 独立测试的 `MotionProjection`/`Babel2MotionDriver`，这个类本身不重新实现
/// 任何投影/阈值数学，只负责把手势事件翻译成 driver 调用、把 driver 的进度
/// 渲染成真实的 view transform，并驱动 UIKit 转场上下文的生命周期。
@MainActor
final class Babel2NavigationPopMotion: NSObject {

	private unowned let navigationController: Babel2NavigationController
	private lazy var driver = Babel2MotionDriver(renderer: { [weak self] progress in
		self?.render(progress)
	})

	private weak var edgeGesture: UIScreenEdgePanGestureRecognizer?
	private(set) var activeToken: MotionInteractionToken?
	private var transitionContext: (any UIViewControllerContextTransitioning)?
	private var fromView: UIView?
	private var toView: UIView?
	private var shadowView: UIView?
	private var containerWidth: CGFloat = 1
	private var isInteractivelyPopping = false

	/// Exposed for tests only: the driver's current lifecycle state.
	var motionState: MotionState { driver.state }

	/// Exposed for tests only. `UINavigationController.interactivePopGestureRecognizer`
	/// is itself implemented as a `UIScreenEdgePanGestureRecognizer`, so counting
	/// instances of that type on `navigationController.view` is not a reliable way
	/// to identify this consumer's own recognizer -- tests must compare identity
	/// against this reference instead.
	var edgeGestureForTesting: UIScreenEdgePanGestureRecognizer? { edgeGesture }

	init(navigationController: Babel2NavigationController) {
		self.navigationController = navigationController
		super.init()
		navigationController.delegate = self
		navigationController.interactivePopGestureRecognizer?.isEnabled = false
		let edge = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(handleEdgePan(_:)))
		edge.edges = .left
		navigationController.view.addGestureRecognizer(edge)
		edgeGesture = edge
	}

	func tearDown() {
		if let edgeGesture {
			navigationController.view.removeGestureRecognizer(edgeGesture)
		}
		edgeGesture = nil
		activeToken = nil
		transitionContext = nil
		fromView = nil
		toView = nil
		shadowView?.removeFromSuperview()
		shadowView = nil
	}

	@objc private func handleEdgePan(_ gesture: UIScreenEdgePanGestureRecognizer) {
		guard let view = gesture.view else { return }
		let translation = gesture.translation(in: view)
		let velocity = gesture.velocity(in: view)
		switch gesture.state {
		case .began:
			beginPop()
		case .changed:
			updatePop(translationX: Double(translation.x))
		case .ended:
			endPop(velocityX: Double(velocity.x), forceCancel: false)
		case .cancelled, .failed:
			endPop(velocityX: Double(velocity.x), forceCancel: true)
		default:
			break
		}
	}

	// MARK: - Testable core (no dependency on a live gesture recognizer)

	func beginPop() {
		guard activeToken == nil, navigationController.viewControllers.count > 1 else { return }
		containerWidth = max(navigationController.view.bounds.width, 1)
		isInteractivelyPopping = true
		activeToken = driver.begin(interaction: .navigationPop, recognizer: "Babel2NavigationPopMotion.edgePan")
		navigationController.popViewController(animated: true)
	}

	func updatePop(translationX: Double) {
		guard let token = activeToken else { return }
		let progress = MotionProgress(translationX / Double(containerWidth))
		driver.update(token: token, progress: progress)
	}

	func endPop(velocityX: Double, forceCancel: Bool) {
		guard let token = activeToken else { return }
		activeToken = nil
		isInteractivelyPopping = false

		let outcome: MotionOutcome
		if forceCancel {
			outcome = .cancelled
		} else {
			let normalizedVelocity = MotionProjection.velocityTowardEnd(velocityX, direction: .positive)
			switch MotionProjection.validatedFinishDecision(
				progress: driver.state.progress,
				velocity: normalizedVelocity,
				extent: Double(containerWidth),
				configuration: MotionProjectionConfiguration()
			) {
			case .decision(.finish):
				outcome = .finished
			case .decision(.cancel), .rejected:
				outcome = .cancelled
			}
		}
		settle(token: token, outcome: outcome)
	}

	private func settle(token: MotionInteractionToken, outcome: MotionOutcome) {
		let duration = Babel2MotionTokens.fullRouteSettleDuration.lowerBound
		if outcome == .finished {
			transitionContext?.finishInteractiveTransition()
		} else {
			transitionContext?.cancelInteractiveTransition()
		}
		let result: MotionCommandResult = outcome == .finished
			? driver.finish(token: token, duration: duration)
			: driver.cancel(token: token, duration: duration)
		let didComplete = outcome == .finished
		let capturedContext = transitionContext
		let capturedShadow = shadowView
		let delay = result == .started ? duration : 0
		DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
			capturedContext?.completeTransition(didComplete)
			capturedShadow?.removeFromSuperview()
		}
		transitionContext = nil
		fromView = nil
		toView = nil
		shadowView = nil
	}

	private func setUp(using transitionContext: any UIViewControllerContextTransitioning) {
		self.transitionContext = transitionContext
		guard
			let fromVC = transitionContext.viewController(forKey: .from),
			let toVC = transitionContext.viewController(forKey: .to)
		else {
			transitionContext.completeTransition(false)
			self.transitionContext = nil
			return
		}
		let container = transitionContext.containerView
		toVC.view.frame = transitionContext.finalFrame(for: toVC)
		container.insertSubview(toVC.view, belowSubview: fromVC.view)
		containerWidth = max(container.bounds.width, 1)

		let shadow = UIView(frame: fromVC.view.bounds)
		shadow.autoresizingMask = [.flexibleWidth, .flexibleHeight]
		shadow.backgroundColor = .black
		shadow.alpha = 0
		shadow.isUserInteractionEnabled = false
		fromVC.view.addSubview(shadow)

		fromView = fromVC.view
		toView = toVC.view
		shadowView = shadow
		render(.zero)
	}

	private func render(_ progress: MotionProgress) {
		guard let fromView, let toView else { return }
		let p = CGFloat(progress.value)
		let width = containerWidth
		fromView.transform = CGAffineTransform(translationX: width * p, y: 0)
		toView.transform = CGAffineTransform(translationX: -0.22 * width * (1 - p), y: 0)
		shadowView?.alpha = 0.18 * (1 - p)
		if activeToken != nil {
			transitionContext?.updateInteractiveTransition(p)
		}
	}
}

extension Babel2NavigationPopMotion: UINavigationControllerDelegate {
	func navigationController(
		_ navigationController: UINavigationController,
		animationControllerFor operation: UINavigationController.Operation,
		from fromVC: UIViewController,
		to toVC: UIViewController
	) -> (any UIViewControllerAnimatedTransitioning)? {
		guard operation == .pop, isInteractivelyPopping else { return nil }
		return self
	}

	func navigationController(
		_ navigationController: UINavigationController,
		interactionControllerFor animationController: any UIViewControllerAnimatedTransitioning
	) -> (any UIViewControllerInteractiveTransitioning)? {
		guard isInteractivelyPopping, animationController === self else { return nil }
		return self
	}
}

extension Babel2NavigationPopMotion: UIViewControllerAnimatedTransitioning {
	func transitionDuration(using transitionContext: (any UIViewControllerContextTransitioning)?) -> TimeInterval {
		Babel2MotionTokens.fullRouteSettleDuration.lowerBound
	}

	func animateTransition(using transitionContext: any UIViewControllerContextTransitioning) {
		// UIKit calls startInteractiveTransition(_:) instead of this method for
		// an interactive-driven transition (wantsInteractiveStart == true). This
		// exists only to satisfy the protocol and to fail safely if UIKit ever
		// invoked it directly.
		setUp(using: transitionContext)
	}
}

extension Babel2NavigationPopMotion: UIViewControllerInteractiveTransitioning {
	var wantsInteractiveStart: Bool { true }

	func startInteractiveTransition(_ transitionContext: any UIViewControllerContextTransitioning) {
		setUp(using: transitionContext)
	}
}
