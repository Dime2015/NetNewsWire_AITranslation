import UIKit

/// 能在手势跟手之前「准备好」、取消时「丢弃」的页面（内置浏览器实现它）。
@MainActor
protocol Babel2PreparableRoute: UIViewController {
	func prepare()
	func discard()
}

/// 阅读页 → 内置浏览器：往左划，两页一起跟手（MOTION-CONTRACT §7，ADR-021）。
/// 2026-09-27 起整页任意位置都能划（用户要求，与整页右滑返回左右对称；ADR-048，合同已按用户要求修订）。
///
/// 状态：idle → 起手 → 跟手 → 松手后补完到浏览器 | 弹回阅读页。
/// - 起手时先把浏览器页面建好、网页在后台开始加载；网络加载从不参与跟手动画
/// - 进度 p = clamp(左移距离 / 页宽, 0, 1)；阅读页 x = −W·p，浏览器 x = W·(1−p)
/// - 松手：按「当前进度 + 速度 × 0.15 秒」投影，超过 0.5 补完进入浏览器，否则弹回
///   （与左边缘返回同一规则；0.15 s 与 0.5 在合同中标为可调）
/// - 弹回：丢弃浏览器，阅读页的文章、位置、工具栏状态完全不变
/// - 补完：浏览器成为导航栈上唯一的当前页；返回由统一的左边缘返回手势负责
/// 何时开始（只看第一下移动，与整页右滑返回同一套判断）：明显往左横滑（横向速度 > 竖向 1.2 倍）；
/// 竖着滑直接不开始——正文滚动从不等它（1.x 拖慢滚动的根源）；起点在还能往左滚的横向滚动区里
/// （宽表格 / 代码块）时先滚它自己，滚到头才进浏览器；弹出菜单上、有弹出页面时不开始。
/// 点大标题 / 收起后的小标题栏也走同一段画面（`open()`，不跟手）。
@MainActor
final class Babel2ReaderBrowserMotion: NSObject, UIGestureRecognizerDelegate {
	static let projectionWindow: CGFloat = 0.15
	static let finishThreshold: CGFloat = 0.5

	private weak var reader: UIViewController?
	private let makeBrowser: () -> (any Babel2PreparableRoute)?
	/// 整页往左划（ADR-048；原来是只认右边缘的系统边缘手势）。
	let pan = UIPanGestureRecognizer()
	/// 补完时由阅读页把浏览器推入导航栈（不带动画，画面已经在终点）。
	var onCommit: ((UIViewController) -> Void)?

	private(set) var progress: CGFloat = 0
	private(set) var isTracking = false
	private var browser: (any Babel2PreparableRoute)?
	private var width: CGFloat = 1
	private var animator: UIViewPropertyAnimator?

	init(reader: UIViewController, makeBrowser: @escaping () -> (any Babel2PreparableRoute)?) {
		self.reader = reader
		self.makeBrowser = makeBrowser
		super.init()
		pan.addTarget(self, action: #selector(handlePan(_:)))
		pan.delegate = self
		reader.view.addGestureRecognizer(pan)
	}

	@objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
		let container = reader?.navigationController?.view ?? reader?.view.superview
		switch gesture.state {
		case .began:
			begin()
		case .changed:
			update(translationX: gesture.translation(in: container).x)
		case .ended:
			end(velocityX: gesture.velocity(in: container).x, cancelled: false)
		case .cancelled, .failed:
			end(velocityX: 0, cancelled: true)
		default:
			break
		}
	}

	/// 点大标题 / 小标题栏：和划过去一样的画面——浏览器整页从右边滑进来（不跟手，直接补完）。
	/// 准备不了浏览器（没有原文地址）就返回 false，由调用方退回别的打开方式。
	@discardableResult
	func open() -> Bool {
		guard begin() else { return false }
		isTracking = false
		settle(commit: true)
		return true
	}

	// MARK: - 整页左滑什么时候开始（ADR-048）

	/// 该不该开始（纯函数，方便测试）：没在进行中、起点不在还能往左滚的横向滚动区里、手指明显往左横滑。
	static func shouldBegin(velocity: CGPoint, isBusy: Bool, startsInHorizontalScroller: Bool) -> Bool {
		guard !isBusy, !startsInHorizontalScroller else { return false }
		return velocity.x < 0 && -velocity.x > abs(velocity.y) * Babel2NavigationPopMotion.horizontalDominance
	}

	/// 从触点往上找：有没有一个能横向滚动、而且此刻还没滚到最右边的滚动区（往左划时它还能滚）；也不从弹出菜单上开始。
	static func startsInHorizontalScroller(_ hitView: UIView?, stopAt root: UIView) -> Bool {
		var view = hitView
		while let current = view, current !== root {
			if current is Babel2GlassMenu { return true }
			if let scrollView = current as? UIScrollView,
				scrollView.contentSize.width > scrollView.bounds.width + 2,
				scrollView.contentOffset.x < scrollView.contentSize.width - scrollView.bounds.width + scrollView.adjustedContentInset.right - 1 {
				return true
			}
			view = current.superview
		}
		return false
	}

	func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
		guard gestureRecognizer === pan, let view = pan.view, let reader else { return false }
		let translation = pan.translation(in: view)
		let location = pan.location(in: view)
		let start = CGPoint(x: location.x - translation.x, y: location.y - translation.y)
		return Self.shouldBegin(
			velocity: pan.velocity(in: view),
			isBusy: isTracking || animator != nil || reader.presentedViewController != nil,
			startsInHorizontalScroller: Self.startsInHorizontalScroller(view.hitTest(start, with: nil), stopAt: view)
		)
	}

	/// 竖向滚动区（正文）横不动：和它同时进行无妨（最多顺带滚一两点），这样即使它先认出了拖动也挡不住左滑。
	/// 能横向滚动的滚动区不在此列。
	func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
		guard gestureRecognizer === pan, let scrollView = otherGestureRecognizer.view as? UIScrollView,
			otherGestureRecognizer === scrollView.panGestureRecognizer else { return false }
		return scrollView.contentSize.width <= scrollView.bounds.width + 2
	}

	// MARK: - 状态机（手势与自动化测试共用）

	/// 起手：先准备浏览器；准备不了（例如没有原文地址）就不开始，阅读页保持原样。
	@discardableResult
	func begin() -> Bool {
		guard !isTracking, animator == nil,
			let reader, let container = reader.navigationController?.view ?? reader.view.superview,
			let browser = makeBrowser() else { return false }
		browser.prepare()
		width = max(container.bounds.width, 1)
		browser.view.frame = container.bounds
		container.addSubview(browser.view)
		self.browser = browser
		isTracking = true
		render(0)
		return true
	}

	func update(translationX: CGFloat) {
		guard isTracking else { return }
		render(Self.progress(translationX: translationX, width: width))
	}

	func end(velocityX: CGFloat, cancelled: Bool) {
		guard isTracking else { return }
		isTracking = false
		let commit = !cancelled && Self.shouldFinish(progress: progress, velocityX: velocityX, width: width)
		settle(commit: commit)
	}

	/// 左移距离换算成进度（手指向左 = translation 为负）。
	static func progress(translationX: CGFloat, width: CGFloat) -> CGFloat {
		min(max(-translationX / max(width, 1), 0), 1)
	}

	/// 投影判定：当前进度 + 速度 × 投影窗口，超过阈值即补完。
	static func shouldFinish(progress: CGFloat, velocityX: CGFloat, width: CGFloat) -> Bool {
		let projected = progress + (-velocityX / max(width, 1)) * projectionWindow
		return projected > finishThreshold
	}

	private func render(_ p: CGFloat) {
		progress = p
		reader?.view.transform = CGAffineTransform(translationX: -width * p, y: 0)
		browser?.view.transform = CGAffineTransform(translationX: width * (1 - p), y: 0)
	}

	private func settle(commit: Bool) {
		let target: CGFloat = commit ? 1 : 0
		let remaining = abs(target - progress)
		let animator = UIViewPropertyAnimator(duration: max(0.12, 0.3 * Double(remaining)), curve: .easeOut) { [weak self] in
			self?.render(target)
		}
		animator.addCompletion { [weak self] _ in
			self?.finishSettle(commit: commit)
		}
		self.animator = animator
		animator.startAnimation()
	}

	private func finishSettle(commit: Bool) {
		animator = nil
		guard let browser else { return }
		self.browser = nil
		browser.view.removeFromSuperview()
		browser.view.transform = .identity
		reader?.view.transform = .identity
		progress = 0
		if commit {
			onCommit?(browser)
		} else {
			browser.discard()
		}
	}

	/// 仅供自动化测试：立即结束正在进行的补完动画。
	func finishSettleImmediatelyForTesting() {
		guard let animator else { return }
		animator.stopAnimation(false)
		animator.finishAnimation(at: .end)
	}
}
