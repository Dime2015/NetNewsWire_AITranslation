import UIKit

/// 全 App 动效的统一规则（ADR-034，2026-09-26 用户确认「克制、低调、有设计感」方案，第二批）。
///
/// - 只用三种时长：0.15 秒（按压这类微小反馈）/ 0.22 秒（状态变化）/ 0.32 秒（页面级位置变化）
/// - 一种曲线：先快后缓（ease-out），不回弹、不晃动
/// - 移动距离小（最多 8–12pt，下一篇例外），主要靠淡入淡出
/// - 只动位置、缩放和透明度，不在动画里重新排版
/// - 系统「减弱动态效果」打开时：所有移动 / 缩放取消，只留淡入淡出
///
/// 跟手的动作（右滑返回、大图收缩、顶底栏显隐）本来就由手指驱动，不走这里。
@MainActor
enum Babel2Motion {
	static let quick: TimeInterval = 0.15
	static let standard: TimeInterval = 0.22
	static let page: TimeInterval = 0.32

	/// 列表切档时新旧内容横向错开的距离
	static let shift: CGFloat = 12
	/// 首屏文章依次浮起的距离与每行间隔
	static let riseDistance: CGFloat = 6
	static let staggerStep: TimeInterval = 0.02
	/// 按压时缩到的比例
	static let pressedScale: CGFloat = 0.94

	/// 测试可以强制打开 / 关闭；nil = 跟随系统设置。
	static var reduceMotionOverride: Bool?
	static var reduceMotion: Bool { reduceMotionOverride ?? UIAccessibility.isReduceMotionEnabled }

	/// 减弱动态效果时位移一律归零。
	static func offset(_ distance: CGFloat) -> CGFloat { reduceMotion ? 0 : distance }

	/// 统一的 ease-out 动画（可以被新的动画打断，并从当前画面继续）。
	static func animate(
		_ duration: TimeInterval,
		delay: TimeInterval = 0,
		_ animations: @escaping () -> Void,
		completion: ((Bool) -> Void)? = nil
	) {
		UIView.animate(withDuration: duration, delay: delay,
			options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction],
			animations: animations, completion: completion)
	}

	/// 图片 / 文字换内容时交叉淡入（不在窗口里时直接换，不做动画）。
	static func crossfade(_ view: UIView, duration: TimeInterval = standard, _ change: @escaping () -> Void) {
		guard view.window != nil else {
			change()
			return
		}
		UIView.transition(with: view, duration: duration,
			options: [.transitionCrossDissolve, .allowUserInteraction, .beginFromCurrentState],
			animations: change)
	}

	// MARK: 按压反馈

	/// 按下缩到 94%，松手或手指移出后回原（0.15 秒）。减弱动态效果时改为轻微变淡。
	/// 只改 transform（或 alpha），不影响布局与点按区域。
	static func addPressFeedback(to control: UIControl) {
		control.addTarget(Babel2PressFeedback.shared, action: #selector(Babel2PressFeedback.pressDown(_:)),
			for: [.touchDown, .touchDragEnter])
		control.addTarget(Babel2PressFeedback.shared, action: #selector(Babel2PressFeedback.pressUp(_:)),
			for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit])
	}

	// MARK: 首屏依次浮现

	/// 把一组视图（按从上到下的顺序）依次淡入并上浮 riseDistance，每个间隔 staggerStep。
	static func staggerIn(_ views: [UIView]) {
		for (index, view) in views.enumerated() {
			view.alpha = 0
			view.transform = CGAffineTransform(translationX: 0, y: offset(riseDistance))
			animate(standard, delay: reduceMotion ? 0 : Double(index) * staggerStep, {
				view.alpha = 1
				view.transform = .identity
			})
		}
	}
}

/// 按压反馈的共用目标（UIControl 的 target 需要一个对象）。
@MainActor
final class Babel2PressFeedback: NSObject {
	static let shared = Babel2PressFeedback()

	@objc func pressDown(_ control: UIControl) {
		Babel2Motion.animate(Babel2Motion.quick) {
			if Babel2Motion.reduceMotion {
				control.alpha = 0.6
			} else {
				control.transform = CGAffineTransform(scaleX: Babel2Motion.pressedScale, y: Babel2Motion.pressedScale)
			}
		}
	}

	@objc func pressUp(_ control: UIControl) {
		Babel2Motion.animate(Babel2Motion.quick) {
			control.transform = .identity
			if Babel2Motion.reduceMotion { control.alpha = 1 }
		}
	}
}
