import UIKit

/// 上拉翻到下一篇的规则（ADR-035，2026-09-26 用户设计）：纯计算，不依赖界面，便于自动测试。
///
/// 读到底后继续往上拉（橡皮筋区），拉得越多：
/// - 向下的 ∨ 越扁（到临界点正好拉平成一条横线）
/// - 颜色从浅灰越来越深（到临界点是正文标题的墨色）
/// 往上越过临界点时轻震一次；此时松手就进入下一篇。越过后又往回拉，∨ 重新弯回、变浅，松手不翻。
/// 没有下一篇时什么都不显示，只是普通回弹。
struct Babel2ReaderNextPull {
	/// 临界点：拉过底部多少 pt 算数
	static let threshold: CGFloat = 80
	/// 刚出现时 ∨ 的弯曲深度（宽 36pt 时），到临界点降到 0
	static let restingDepth: CGFloat = 7
	/// 拉开这么多以后 ∨ 才完全不透明（避免一碰就冒出来）
	static let fadeInDistance: CGFloat = 16

	/// 0（刚拉过底）… 1（到临界点及以上）
	static func progress(overscroll: CGFloat) -> CGFloat {
		guard overscroll.isFinite, overscroll > 0 else { return 0 }
		return min(overscroll / threshold, 1)
	}

	static func isArmed(overscroll: CGFloat) -> Bool { overscroll >= threshold }

	/// 当前弯曲深度：随进度线性变浅，到 1 时为 0（一条横线）。
	static func depth(progress: CGFloat) -> CGFloat { restingDepth * (1 - min(max(progress, 0), 1)) }

	static func opacity(overscroll: CGFloat) -> CGFloat {
		guard overscroll > 0 else { return 0 }
		return min(overscroll / fadeInDistance, 1)
	}

	/// 松手时是否翻篇：必须有下一篇，且松手那一刻仍在临界点以上。
	static func shouldCommit(overscrollAtRelease: CGFloat, hasNext: Bool) -> Bool {
		hasNext && isArmed(overscroll: overscrollAtRelease)
	}

	/// 滚动区拉过底部多少（正数 = 在底部橡皮筋区）。内容不满一屏时，以顶部为「底」。
	static func overscroll(offsetY: CGFloat, contentHeight: CGFloat, boundsHeight: CGFloat, insetTop: CGFloat, insetBottom: CGFloat) -> CGFloat {
		let maxOffset = max(contentHeight + insetBottom - boundsHeight, -insetTop)
		return offsetY - maxOffset
	}
}

/// 画那个 ∨：36pt 宽、2pt 圆头线；弯曲深度与颜色按进度变化，不带隐式动画（跟手）。
@MainActor
final class Babel2ReaderNextPullView: UIView {
	static let width: CGFloat = 36
	static let height: CGFloat = 16

	private let shape = CAShapeLayer()
	private(set) var progress: CGFloat = 0

	override init(frame: CGRect) {
		super.init(frame: CGRect(origin: frame.origin, size: CGSize(width: Self.width, height: Self.height)))
		isUserInteractionEnabled = false
		isAccessibilityElement = false
		accessibilityIdentifier = "babel2.article.next-pull"
		shape.fillColor = nil
		shape.lineWidth = 2
		shape.lineCap = .round
		shape.lineJoin = .round
		layer.addSublayer(shape)
		alpha = 0
		apply(progress: 0)
		registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Babel2ReaderNextPullView, _) in
			self.apply(progress: self.progress)
		}
	}

	required init?(coder: NSCoder) { nil }

	/// 按进度重画：越接近 1 越扁、越深。
	func apply(progress newProgress: CGFloat) {
		progress = min(max(newProgress, 0), 1)
		let depth = Babel2ReaderNextPull.depth(progress: progress)
		let midY = Self.height / 2
		let path = UIBezierPath()
		path.move(to: CGPoint(x: 1, y: midY - depth / 2))
		path.addLine(to: CGPoint(x: Self.width / 2, y: midY + depth / 2))
		path.addLine(to: CGPoint(x: Self.width - 1, y: midY - depth / 2))
		CATransaction.begin()
		CATransaction.setDisableActions(true)
		shape.frame = bounds
		shape.path = path.cgPath
		shape.strokeColor = Self.blend(BabelPalette.tertiaryInk, BabelPalette.ink, progress)
			.resolvedColor(with: traitCollection).cgColor
		CATransaction.commit()
	}

	/// 两种颜色按比例混合（浅灰 → 墨色）。
	private static func blend(_ from: UIColor, _ to: UIColor, _ t: CGFloat) -> UIColor {
		UIColor { traits in
			var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
			var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
			from.resolvedColor(with: traits).getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
			to.resolvedColor(with: traits).getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
			return UIColor(red: r1 + (r2 - r1) * t, green: g1 + (g2 - g1) * t, blue: b1 + (b2 - b1) * t, alpha: a1 + (a2 - a1) * t)
		}
	}
}
