import UIKit

/// 能在手势跟手之前「准备好」、取消时「丢弃」的页面（内置浏览器实现它）。
@MainActor
protocol Babel2PreparableRoute: UIViewController {
	func prepare()
	func discard()
}

/// 阅读页 → 内置浏览器：正文右边缘往左滑，两页一起跟手（MOTION-CONTRACT §7，ADR-021）。
///
/// 状态：idle → 右边缘起手 → 跟手 → 松手后补完到浏览器 | 弹回阅读页。
/// - 起手时先把浏览器页面建好、网页在后台开始加载；网络加载从不参与跟手动画
/// - 进度 p = clamp(左移距离 / 页宽, 0, 1)；阅读页 x = −W·p，浏览器 x = W·(1−p)
/// - 松手：按「当前进度 + 速度 × 0.15 秒」投影，超过 0.5 补完进入浏览器，否则弹回
///   （与左边缘返回同一规则；0.15 s 与 0.5 在合同中标为可调）
/// - 弹回：丢弃浏览器，阅读页的文章、位置、工具栏状态完全不变
/// - 补完：浏览器成为导航栈上唯一的当前页；返回由统一的左边缘返回手势负责
/// 只在右边缘起手才触发（系统边缘手势识别器），不会在正文中间左右划时误触。
@MainActor
final class Babel2ReaderBrowserMotion: NSObject {
	static let projectionWindow: CGFloat = 0.15
	static let finishThreshold: CGFloat = 0.5

	private weak var reader: UIViewController?
	private let makeBrowser: () -> (any Babel2PreparableRoute)?
	let edgeGesture = UIScreenEdgePanGestureRecognizer()
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
		edgeGesture.edges = .right
		edgeGesture.addTarget(self, action: #selector(handleEdgePan(_:)))
		reader.view.addGestureRecognizer(edgeGesture)
	}

	@objc private func handleEdgePan(_ gesture: UIScreenEdgePanGestureRecognizer) {
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

	// MARK: - 状态机（手势与自动化测试共用）

	/// 右边缘起手：先准备浏览器；准备不了（例如没有原文地址）就不开始，阅读页保持原样。
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
