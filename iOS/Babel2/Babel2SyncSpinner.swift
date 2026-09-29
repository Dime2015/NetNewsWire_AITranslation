import UIKit

/// 同步箭头的转动（ADR-034）：开始时从静止平缓加速，停止时减速转到整圈再停，不再戛然而止。
///
/// 图形是统一图标集的「同步」圆弧（ADR-065；以前借用 1.x 的 `BabelSyncGlyphView`），可选一个浅灰圆底
/// （首页标题旁要；文章列表顶部外面已有毛玻璃圆底，不要，ADR-062）。转动由这一层自己负责。
@MainActor
final class Babel2SyncSpinner: UIView {
	private static let spinKey = "babel2.sync.spin"
	/// 匀速时一圈 0.9 秒（与 1.x 一致）
	private static let turn: CFTimeInterval = 0.9

	private let backdrop = UIView()
	private let glyph = UIImageView()
	private let showsBackground: Bool
	private(set) var isSpinning = false
	private var spinToken = 0

	/// - showsBackground：图形自带的灰色圆底。外面已经有圆底的地方（文章列表顶部的毛玻璃圆底）传 false，免得圈外套圈。
	init(frame: CGRect = .zero, showsBackground: Bool = true) {
		self.showsBackground = showsBackground
		super.init(frame: frame)
		isUserInteractionEnabled = false
		isAccessibilityElement = false
		// 圆底：与 1.x 同样的浅灰（raisedBackground 47%），铺满整个画布的圆
		backdrop.backgroundColor = BabelPalette.raisedBackground.withAlphaComponent(0.47)
		backdrop.isHidden = !showsBackground
		backdrop.isUserInteractionEnabled = false
		glyph.image = Babel2Icon.sync.asset?.withRenderingMode(.alwaysTemplate)
		glyph.tintColor = Babel2Icon.tint
		glyph.contentMode = .scaleAspectFit
		for view in [backdrop, glyph] {
			view.translatesAutoresizingMaskIntoConstraints = false
			addSubview(view)
			NSLayoutConstraint.activate([
				view.leadingAnchor.constraint(equalTo: leadingAnchor),
				view.trailingAnchor.constraint(equalTo: trailingAnchor),
				view.topAnchor.constraint(equalTo: topAnchor),
				view.bottomAnchor.constraint(equalTo: bottomAnchor)
			])
		}
	}

	override func layoutSubviews() {
		super.layoutSubviews()
		backdrop.layer.cornerRadius = min(bounds.width, bounds.height) / 2
	}

	required init?(coder: NSCoder) { nil }

	/// 仅供自动化测试。
	var showsBackgroundForTesting: Bool { showsBackground }

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
