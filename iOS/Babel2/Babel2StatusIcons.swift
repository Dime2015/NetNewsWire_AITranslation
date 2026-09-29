import UIKit

/// 底栏「阅读模式」「翻译」两个状态图标（2026-09-27 用户反馈第 6、11 条，ADR-043；同日二改，ADR-049）。
///
/// 两个图标同一套状态语言：
/// - 阅读模式：几道横线、最后一道略短（用户：纸页外框不好看，只要横线）
/// - 翻译：统一图标集的「文A」（ADR-065；原为系统翻译符号），右下角空心 / 实心小圆点表示有没有译文缓存（1.x 的设计拿回来）
/// - 平时：线条图标，次要灰
/// - 进行中：图标本身在动（横线依次明灭、翻译符号明灭）——不用系统转圈，
///   也不在标题下面写「正在获取全文…」
/// - 成功（开着 / 已译）：32pt 圆角方块墨色底、图标反白，出现时从 0.85 倍轻轻放大到位
/// - 失败：图标左右轻晃一下，回到平时；提示文字由页面用底栏上方的小胶囊给
/// 减弱动态效果时不晃、不放大，只做淡入淡出；进行中的明灭只改透明度，保留。
/// 时长与曲线按全 App 动效规则（Babel2Motion：0.22 秒 ease-out）。
@MainActor
class Babel2StatusIconControl: UIControl {
	enum Phase: Equatable {
		case idle
		case working
		case on
	}

	static let chipSide: CGFloat = 32
	static let chipCornerRadius: CGFloat = 9
	/// 图标画在 24 × 24 的设计网格里，显示时缩放到底栏图标尺寸（Babel2Type.toolbarIcon）。
	static let designGrid: CGFloat = 24

	private(set) var phase: Phase = .idle
	/// 成功态的墨色方块底
	let chip = UIView()
	/// 图标画布（设计网格等比缩放到图标尺寸）
	let glyph = UIView()
	var glyphScale: CGFloat { Babel2Type.toolbarIcon / Self.designGrid }

	override init(frame: CGRect) {
		super.init(frame: frame)
		isAccessibilityElement = true
		accessibilityTraits = .button
		chip.backgroundColor = BabelPalette.ink
		chip.layer.cornerRadius = Self.chipCornerRadius
		chip.layer.cornerCurve = .continuous
		chip.alpha = 0
		chip.isUserInteractionEnabled = false
		glyph.isUserInteractionEnabled = false
		addSubview(chip)
		addSubview(glyph)
		registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (control: Babel2StatusIconControl, _: UITraitCollection) in
			control.applyColors()
		}
	}

	required init?(coder: NSCoder) { nil }

	override var intrinsicContentSize: CGSize { CGSize(width: 44, height: 44) }

	override var isEnabled: Bool {
		didSet { applyColors() }
	}

	override func layoutSubviews() {
		super.layoutSubviews()
		let center = CGPoint(x: bounds.midX, y: bounds.midY)
		chip.bounds = CGRect(x: 0, y: 0, width: Self.chipSide, height: Self.chipSide)
		chip.center = center
		let side = Babel2Type.toolbarIcon
		glyph.bounds = CGRect(x: 0, y: 0, width: side, height: side)
		glyph.center = center
	}

	/// 切换状态。animated = false 用于第一次设置与不在屏幕上时。
	func setPhase(_ newPhase: Phase, animated: Bool = true) {
		let old = phase
		phase = newPhase
		let shouldAnimate = animated && window != nil
		if newPhase == .on, old != .on {
			chip.transform = (shouldAnimate && !Babel2Motion.reduceMotion) ? CGAffineTransform(scaleX: 0.85, y: 0.85) : .identity
		}
		let change = {
			self.chip.alpha = newPhase == .on ? 1 : 0
			self.chip.transform = .identity
			self.applyColors()
		}
		if shouldAnimate, old != newPhase {
			Babel2Motion.animate(Babel2Motion.standard, change)
			UIView.transition(with: glyph, duration: Babel2Motion.standard, options: [.transitionCrossDissolve, .allowUserInteraction], animations: {}, completion: nil)
		} else {
			change()
		}
		if newPhase == .working {
			startWorkingAnimation()
		} else {
			stopWorkingAnimation()
		}
	}

	/// 失败：左右轻晃一下（0.4 秒）；减弱动态效果时改为轻轻一闪。
	func shake() {
		guard window != nil else { return }
		if Babel2Motion.reduceMotion {
			let blink = CAKeyframeAnimation(keyPath: "opacity")
			blink.values = [1, 0.35, 1]
			blink.duration = Babel2Motion.standard
			glyph.layer.add(blink, forKey: "babel2.fail")
			return
		}
		let shake = CAKeyframeAnimation(keyPath: "transform.translation.x")
		shake.values = [0, -3, 3, -2, 2, 0]
		shake.duration = 0.4
		shake.timingFunction = CAMediaTimingFunction(name: .easeOut)
		glyph.layer.add(shake, forKey: "babel2.fail")
	}

	/// 图标颜色：成功态反白（纸色），平时次要灰，不可点时更浅的中性灰。
	var glyphColor: UIColor {
		if phase == .on { return BabelPalette.background }
		return isEnabled ? Babel2Icon.tint : BabelPalette.tertiaryInk
	}

	func applyColors() {
		chip.backgroundColor = BabelPalette.ink
		applyGlyphColor(glyphColor.resolvedColor(with: traitCollection))
	}

	// MARK: 子类实现

	func applyGlyphColor(_ color: UIColor) {}
	func startWorkingAnimation() {}
	func stopWorkingAnimation() {}

	/// 明灭动画（进行中）：从 0.25 到 1 来回，delay 秒后开始。
	static func pulse(delay: CFTimeInterval, period: CFTimeInterval) -> CABasicAnimation {
		let animation = CABasicAnimation(keyPath: "opacity")
		animation.fromValue = 0.25
		animation.toValue = 1
		animation.duration = period / 2
		animation.autoreverses = true
		animation.repeatCount = .infinity
		animation.beginTime = CACurrentMediaTime() + delay
		animation.fillMode = .backwards
		animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
		return animation
	}
}

/// 阅读模式：四道横线，最后一道略短（像一段文字）。进行中四道线依次明灭。
@MainActor
final class Babel2ReaderModeIconButton: Babel2StatusIconControl {
	/// 设计网格（24 × 24）里的四道线，与统一图标集的 reader-mode 同一组坐标（ADR-065）：
	/// 左端 5.5，前三道到 18.5，最后一道到 13（短一截）；间隔 4，竖直居中；线宽 = 图标集线宽 2。
	static let lineSpecs: [(start: CGFloat, end: CGFloat, y: CGFloat)] = [
		(5.5, 18.5, 6), (5.5, 18.5, 10), (5.5, 18.5, 14), (5.5, 13, 18)
	]
	private let lines = Babel2ReaderModeIconButton.lineSpecs.map { _ in CAShapeLayer() }

	override init(frame: CGRect) {
		super.init(frame: frame)
		let scale = glyphScale
		for (layer, spec) in zip(lines, Self.lineSpecs) {
			let path = UIBezierPath()
			path.move(to: CGPoint(x: spec.start * scale, y: spec.y * scale))
			path.addLine(to: CGPoint(x: spec.end * scale, y: spec.y * scale))
			layer.path = path.cgPath
			layer.fillColor = UIColor.clear.cgColor
			layer.lineWidth = Babel2Icon.stroke * scale
			layer.lineCap = .round
			glyph.layer.addSublayer(layer)
		}
		accessibilityIdentifier = "babel2.article.toolbar.reading-mode"
		accessibilityLabel = Babel2Localization.text(.readingMode)
		accessibilityValue = "off"
		applyColors()
	}

	required init?(coder: NSCoder) { nil }

	override func applyGlyphColor(_ color: UIColor) {
		for layer in lines {
			layer.strokeColor = color.cgColor
		}
	}

	override func startWorkingAnimation() {
		for (index, line) in lines.enumerated() where line.animation(forKey: "babel2.working") == nil {
			line.add(Self.pulse(delay: Double(index) * 0.15, period: 1.2), forKey: "babel2.working")
		}
	}

	override func stopWorkingAnimation() {
		lines.forEach { $0.removeAnimation(forKey: "babel2.working") }
	}

	/// 仅供自动化测试。
	var isAnimatingWorkForTesting: Bool { lines.contains { $0.animation(forKey: "babel2.working") != nil } }
	/// 仅供自动化测试：每道线的长度（设计网格单位）。
	static var lineLengthsForTesting: [CGFloat] { lineSpecs.map { $0.end - $0.start } }
}

/// 翻译：统一图标集的「文A」（ADR-065；ADR-049 时是系统「翻译」符号）+ 右下角角标，
/// 角标规则与 1.x 已定案的 `NNWTranslateIcon` 相同（角标外圈挖一圈透明、小尺寸下也认得出）。
/// 状态沿用翻译引擎的六种：
/// - 原文 → 纯图标；有完整译文缓存 → **实心小圆点**（点一下秒开）；有翻到一半的缓存 → **空心小圆点**（点一下接着翻）
/// - 翻译中 → 图标明灭；已译 → 墨色方块底、图标反白（与阅读模式同一种「成功」）；失败 → 晃一下后回到平时
@MainActor
final class Babel2TranslateIconButton: Babel2StatusIconControl {
	enum Badge: Hashable {
		case none
		case solidDot
		case hollowDot
	}

	private let imageView = UIImageView()
	private(set) var translationState: TranslationButtonState = .original
	private(set) var badge: Badge = .none

	override init(frame: CGRect) {
		super.init(frame: frame)
		imageView.contentMode = .center
		imageView.isAccessibilityElement = false
		imageView.translatesAutoresizingMaskIntoConstraints = false
		glyph.addSubview(imageView)
		NSLayoutConstraint.activate([
			imageView.centerXAnchor.constraint(equalTo: glyph.centerXAnchor),
			imageView.centerYAnchor.constraint(equalTo: glyph.centerYAnchor)
		])
		accessibilityIdentifier = "babel2.article.toolbar.translate"
		setState(.original)
	}

	required init?(coder: NSCoder) { nil }

	override func applyGlyphColor(_ color: UIColor) {
		imageView.tintColor = color
	}

	func setState(_ newState: TranslationButtonState) {
		let wasFailed = translationState == .failed
		translationState = newState
		let label: Babel2LocalizationKey
		let value: String
		switch newState {
		case .original: label = .translate; value = "original"
		case .cachedAvailable: label = .translate; value = "cached"
		case .partialCacheAvailable: label = .translate; value = "partial"
		case .working: label = .cancelTranslation; value = "working"
		case .translated: label = .showOriginal; value = "translated"
		case .failed: label = .translate; value = "failed"
		}
		accessibilityLabel = Babel2Localization.text(label)
		accessibilityValue = value
		setBadge(newState == .cachedAvailable ? .solidDot : (newState == .partialCacheAvailable ? .hollowDot : .none))
		switch newState {
		case .working: setPhase(.working)
		case .translated: setPhase(.on)
		case .original, .cachedAvailable, .partialCacheAvailable, .failed: setPhase(.idle)
		}
		if newState == .failed, !wasFailed { shake() }
	}

	/// 换角标：图标本体不动，只换右下角（同一组图，各态位置一个像素不差）。
	private func setBadge(_ newBadge: Badge) {
		let image = Babel2TranslateGlyph.image(newBadge)
		let changed = newBadge != badge || imageView.image == nil
		badge = newBadge
		guard changed else { return }
		if imageView.image != nil, window != nil {
			Babel2Motion.crossfade(imageView) { self.imageView.image = image.withRenderingMode(.alwaysTemplate) }
		} else {
			imageView.image = image.withRenderingMode(.alwaysTemplate)
		}
	}

	override func startWorkingAnimation() {
		guard imageView.layer.animation(forKey: "babel2.working") == nil else { return }
		imageView.layer.add(Self.pulse(delay: 0, period: 1.2), forKey: "babel2.working")
	}

	override func stopWorkingAnimation() {
		imageView.layer.removeAnimation(forKey: "babel2.working")
	}

	/// 仅供自动化测试。
	var isAnimatingWorkForTesting: Bool { imageView.layer.animation(forKey: "babel2.working") != nil }
	var glyphImageForTesting: UIImage? { imageView.image }
}

/// 翻译图标 + 右下角角标（ADR-049 的状态规则；图形换成统一图标集的「文A」，ADR-065）。
/// 画布就是底栏图标的 21pt；「文A」在设计时已把右下角约 6×6 空出来，角标（中心在网格 (20, 20)）放在那里：
/// 外圈先挖掉一圈透明（与字保持距离），再画实心小圆点（完整缓存）或空心小圆圈（翻到一半）。
/// 各态的图标位置一个像素不差；输出模板图，随 tintColor 变色。
@MainActor
enum Babel2TranslateGlyph {
	/// 角标在 24 网格里的中心与尺寸
	static let badgeCenter = CGPoint(x: 20, y: 20)
	private static var cache = [Babel2TranslateIconButton.Badge: UIImage]()

	static func image(_ badge: Babel2TranslateIconButton.Badge) -> UIImage {
		if let cached = cache[badge] { return cached }
		let image = compose(badge)
		cache[badge] = image
		return image
	}

	private static func compose(_ badge: Babel2TranslateIconButton.Badge) -> UIImage {
		let side = Babel2Icon.Size.bar
		let k = side / Babel2Icon.designGrid
		let icon = Babel2Icon.translate.asset?.withTintColor(.black, renderingMode: .alwaysOriginal)
		return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: .preferred()).image { rendererContext in
			let context = rendererContext.cgContext
			icon?.draw(in: CGRect(x: 0, y: 0, width: side, height: side))
			guard badge != .none else { return }
			let center = CGPoint(x: badgeCenter.x * k, y: badgeCenter.y * k)
			func circle(_ r: CGFloat) -> CGRect { CGRect(x: center.x - r * k, y: center.y - r * k, width: 2 * r * k, height: 2 * r * k) }
			context.setBlendMode(.destinationOut)
			context.fillEllipse(in: circle(3.2))
			context.setBlendMode(.normal)
			UIColor.black.setFill()
			UIColor.black.setStroke()
			switch badge {
			case .solidDot:
				context.fillEllipse(in: circle(2.2))
			case .hollowDot:
				let ring = UIBezierPath(ovalIn: circle(1.6))
				ring.lineWidth = 1.4 * k
				ring.stroke()
			case .none:
				break
			}
		}.withRenderingMode(.alwaysTemplate)
	}
}
