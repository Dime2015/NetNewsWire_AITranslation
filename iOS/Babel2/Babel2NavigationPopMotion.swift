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
/// 只认左边缘返回的页面（ADR-042）：内置浏览器——网页里常有左右滑的轮播图、地图，整页右滑会抢它们的手势。
@MainActor
protocol Babel2EdgeOnlyBackGesture: AnyObject {}

@MainActor
final class Babel2NavigationPopMotion: NSObject {

	private unowned let navigationController: Babel2NavigationController
	private lazy var driver = Babel2MotionDriver(renderer: { [weak self] progress in
		self?.render(progress)
	})

	private weak var edgeGesture: UIScreenEdgePanGestureRecognizer?
	/// 整页右滑返回（ADR-042，2026-09-27 用户要求、同意修订 MOTION-CONTRACT）：
	/// 页面任何位置明显往右横滑都能返回。不让任何滚动区等它失败（1.x 全屏手势拖慢滚动就是这么来的），
	/// 只在开始那一刻判断方向：竖着滑直接不开始，滚动照常；横着滑才接管。
	private weak var contentPan: UIPanGestureRecognizer?
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
		let pan = UIPanGestureRecognizer(target: self, action: #selector(handleEdgePan(_:)))
		pan.maximumNumberOfTouches = 1
		pan.delegate = self
		navigationController.view.addGestureRecognizer(pan)
		contentPan = pan
	}

	/// 仅供自动化测试。
	var contentPanForTesting: UIPanGestureRecognizer? { contentPan }

	func tearDown() {
		if let edgeGesture {
			navigationController.view.removeGestureRecognizer(edgeGesture)
		}
		edgeGesture = nil
		if let contentPan {
			navigationController.view.removeGestureRecognizer(contentPan)
		}
		contentPan = nil
		activeToken = nil
		transitionContext = nil
		fromView = nil
		toView = nil
		shadowView?.removeFromSuperview()
		shadowView = nil
	}

	/// 左边缘手势与整页右滑共用：两者只是「从哪里开始」不同，跟手与松手判定完全一样。
	@objc private func handleEdgePan(_ gesture: UIPanGestureRecognizer) {
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
		let capturedFromView = fromView
		let delay = result == .started ? duration : 0
		DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
			capturedContext?.completeTransition(didComplete)
			capturedShadow?.removeFromSuperview()
			// 取消时当前页留在屏幕上：去掉左边缘投影，恢复原样
			capturedFromView?.layer.shadowOpacity = 0
			capturedFromView?.layer.shadowPath = nil
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

		// 2026-09-25 修正（用户报告设置页右滑返回时当前页变暗、屏幕闪一下）：
		// 以前把黑色遮罩盖在「当前页」上，手势一开始当前页整页突然变暗 18%，看起来像闪烁。
		// 合同的 shadowOpacity 指当前页左边缘的投影；按系统返回手势的通行做法：
		// 当前页只加左边缘投影，暗色遮罩改盖在「上一页」上（一开始被当前页挡住，不会闪），随滑开逐渐变亮。
		let shadow = UIView(frame: toVC.view.bounds)
		shadow.autoresizingMask = [.flexibleWidth, .flexibleHeight]
		shadow.backgroundColor = .black
		shadow.alpha = 0
		shadow.isUserInteractionEnabled = false
		toVC.view.addSubview(shadow)
		let edge = fromVC.view.layer
		edge.shadowColor = UIColor.black.cgColor
		edge.shadowRadius = 8
		edge.shadowOffset = CGSize(width: -2, height: 0)
		edge.shadowOpacity = 0
		edge.shadowPath = UIBezierPath(rect: CGRect(x: 0, y: 0, width: 8, height: fromVC.view.bounds.height)).cgPath

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
		// 合同：shadowOpacity = 0.18 × (1 − p)。当前页左边缘投影与上一页的暗色同步变淡
		fromView.layer.shadowOpacity = Float(0.18 * (1 - p))
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

// MARK: - 整页右滑返回（ADR-042）

extension Babel2NavigationPopMotion: UIGestureRecognizerDelegate {
	/// 左边缘那一条留给边缘手势（它从第一下触摸就认得出来）；整页右滑从边缘以外开始。
	static let edgeZoneWidth: CGFloat = 24
	/// 横向速度至少是竖向的这么多倍才算「往右横滑」。
	static let horizontalDominance: CGFloat = 1.2

	/// 整页右滑该不该开始（纯函数，方便测试）：
	/// 有上一页可回、这一页没有声明只认边缘、手指明显往右横滑、不是从左边缘开始、
	/// 起点不在一个还能往左滚的横向滚动区里（正文里的宽表格 / 代码块先滚它自己，滚到头才返回）。
	static func shouldBeginContentPan(
		velocity: CGPoint,
		start: CGPoint,
		canPop: Bool,
		pageAllowsContentPan: Bool,
		startsInHorizontalScroller: Bool
	) -> Bool {
		guard canPop, pageAllowsContentPan, !startsInHorizontalScroller else { return false }
		guard start.x >= edgeZoneWidth else { return false }
		return velocity.x > 0 && velocity.x > abs(velocity.y) * horizontalDominance
	}

	/// 从触点往上找：有没有一个能横向滚动、而且此刻还没滚到最左边的滚动区。
	/// （已经在最左边的不算——这时往右滑本来就滚不动，交给返回。）也不从弹出菜单上开始。
	static func startsInHorizontalScroller(_ hitView: UIView?, stopAt root: UIView) -> Bool {
		var view = hitView
		while let current = view, current !== root {
			if current is Babel2GlassMenu { return true }
			if let scrollView = current as? UIScrollView,
				scrollView.contentSize.width > scrollView.bounds.width + 2,
				scrollView.contentOffset.x > -scrollView.adjustedContentInset.left + 1 {
				return true
			}
			view = current.superview
		}
		return false
	}

	func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
		guard let pan = gestureRecognizer as? UIPanGestureRecognizer, pan === contentPan, let view = pan.view else { return true }
		let translation = pan.translation(in: view)
		let location = pan.location(in: view)
		let start = CGPoint(x: location.x - translation.x, y: location.y - translation.y)
		let top = navigationController.topViewController
		return Self.shouldBeginContentPan(
			velocity: pan.velocity(in: view),
			start: start,
			canPop: activeToken == nil && navigationController.viewControllers.count > 1 && navigationController.presentedViewController == nil,
			pageAllowsContentPan: !(top is Babel2EdgeOnlyBackGesture),
			startsInHorizontalScroller: Self.startsInHorizontalScroller(view.hitTest(start, with: nil), stopAt: view)
		)
	}

	/// 竖向滚动区（列表、正文）横不动：它的拖动和整页右滑同时进行也无妨（最多顺带滚一两点），
	/// 这样即使它先认出了拖动，整页右滑也不会被挡掉。能横向滚动的滚动区不在此列。
	func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
		guard gestureRecognizer === contentPan, let scrollView = otherGestureRecognizer.view as? UIScrollView,
			otherGestureRecognizer === scrollView.panGestureRecognizer else { return false }
		return scrollView.contentSize.width <= scrollView.bounds.width + 2
	}
}
