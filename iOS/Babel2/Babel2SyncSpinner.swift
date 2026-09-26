import UIKit

/// 同步箭头的转动（ADR-034）：开始时从静止平缓加速，停止时减速转到整圈再停，不再戛然而止。
///
/// 图形本身沿用 1.x 的 `BabelSyncGlyphView`（只借用它的画法，不改它）；转动由这一层自己负责，
/// 所以从不调用它自带的 setSyncing(true)。
@MainActor
final class Babel2SyncSpinner: UIView {
	private static let spinKey = "babel2.sync.spin"
	/// 匀速时一圈 0.9 秒（与 1.x 一致）
	private static let turn: CFTimeInterval = 0.9

	private let glyph = BabelSyncGlyphView()
	private(set) var isSpinning = false
	private var spinToken = 0

	override init(frame: CGRect) {
		super.init(frame: frame)
		isUserInteractionEnabled = false
		isAccessibilityElement = false
		glyph.isHidden = false
		glyph.translatesAutoresizingMaskIntoConstraints = false
		addSubview(glyph)
		NSLayoutConstraint.activate([
			glyph.leadingAnchor.constraint(equalTo: leadingAnchor),
			glyph.trailingAnchor.constraint(equalTo: trailingAnchor),
			glyph.topAnchor.constraint(equalTo: topAnchor),
			glyph.bottomAnchor.constraint(equalTo: bottomAnchor)
		])
	}

	required init?(coder: NSCoder) { nil }

	func setSpinning(_ spinning: Bool) {
		guard spinning != isSpinning else { return }
		isSpinning = spinning
		spinToken &+= 1
		let angle = currentAngle()
		layer.removeAnimation(forKey: Self.spinKey)
		guard window != nil else { return }
		if spinning {
			accelerate(from: angle)
		} else {
			settle(from: angle)
		}
	}

	override func didMoveToWindow() {
		super.didMoveToWindow()
		guard window != nil else {
			layer.removeAnimation(forKey: Self.spinKey)
			return
		}
		if isSpinning, layer.animation(forKey: Self.spinKey) == nil { spinSteadily(from: 0) }
	}

	private func currentAngle() -> CGFloat {
		(layer.presentation()?.value(forKeyPath: "transform.rotation.z") as? CGFloat) ?? 0
	}

	/// 第一圈先慢后快（ease-in，时长是匀速一圈的 1.4 倍），之后匀速；减弱动态效果时直接匀速。
	private func accelerate(from angle: CGFloat) {
		guard !Babel2Motion.reduceMotion else {
			spinSteadily(from: angle)
			return
		}
		let token = spinToken
		let first = CABasicAnimation(keyPath: "transform.rotation.z")
		first.fromValue = angle
		first.toValue = angle + .pi * 2
		first.duration = Self.turn * 1.4
		first.timingFunction = CAMediaTimingFunction(name: .easeIn)
		CATransaction.begin()
		CATransaction.setCompletionBlock { [weak self] in
			guard let self, self.isSpinning, self.spinToken == token else { return }
			self.spinSteadily(from: angle)
		}
		layer.add(first, forKey: Self.spinKey)
		CATransaction.commit()
	}

	private func spinSteadily(from angle: CGFloat) {
		let loop = CABasicAnimation(keyPath: "transform.rotation.z")
		loop.fromValue = angle
		loop.toValue = angle + .pi * 2
		loop.duration = Self.turn
		loop.repeatCount = .infinity
		loop.timingFunction = CAMediaTimingFunction(name: .linear)
		layer.add(loop, forKey: Self.spinKey)
	}

	/// 停止：减速（ease-out）转到下一个整圈停下，图形回到正位。
	private func settle(from angle: CGFloat) {
		let fullTurn = CGFloat.pi * 2
		var remainder = fullTurn - angle.truncatingRemainder(dividingBy: fullTurn)
		if remainder < 0 { remainder += fullTurn }
		guard remainder > 0.05, !Babel2Motion.reduceMotion else { return }
		let stop = CABasicAnimation(keyPath: "transform.rotation.z")
		stop.fromValue = angle
		stop.toValue = angle + remainder
		stop.duration = max(0.25, Double(remainder / fullTurn) * Self.turn * 1.6)
		stop.timingFunction = CAMediaTimingFunction(name: .easeOut)
		layer.add(stop, forKey: Self.spinKey)
	}
}
