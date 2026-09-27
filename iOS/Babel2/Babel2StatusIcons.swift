import UIKit

/// 底栏「阅读模式」「翻译」两个状态图标（2026-09-27 用户反馈第 6、11 条，ADR-043）。
///
/// 两个图标同一套视觉语言（设计方案里选的是阅读模式「B · 纸页」、翻译「A · 文/A」）：
/// - 平时：线条图标，次要灰
/// - 进行中：图标本身在动（纸页的三行字依次明灭、「文」和「A」交替亮起）——不用系统转圈，
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
		return isEnabled ? BabelPalette.mutedInk : BabelPalette.tertiaryInk
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

/// 阅读模式：纸页（圆角纸 + 三行字）。进行中三行字依次明灭。
@MainActor
final class Babel2ReaderModeIconButton: Babel2StatusIconControl {
	private let page = CAShapeLayer()
	private let lines = [CAShapeLayer(), CAShapeLayer(), CAShapeLayer()]

	override init(frame: CGRect) {
		super.init(frame: frame)
		let scale = glyphScale
		func scaled(_ rect: CGRect) -> CGRect {
			CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale)
		}
		page.path = UIBezierPath(roundedRect: scaled(CGRect(x: 5, y: 3.5, width: 14, height: 17)), cornerRadius: 2.6 * scale).cgPath
		let lineSpecs: [(CGFloat, CGFloat, CGFloat)] = [(8.6, 15.4, 8.5), (8.6, 15.4, 12), (8.6, 13, 15.5)]
		for (layer, spec) in zip(lines, lineSpecs) {
			let path = UIBezierPath()
			path.move(to: CGPoint(x: spec.0 * scale, y: spec.2 * scale))
			path.addLine(to: CGPoint(x: spec.1 * scale, y: spec.2 * scale))
			layer.path = path.cgPath
		}
		for layer in [page] + lines {
			layer.fillColor = UIColor.clear.cgColor
			layer.lineWidth = 1.6 * scale
			layer.lineCap = .round
			layer.lineJoin = .round
			glyph.layer.addSublayer(layer)
		}
		accessibilityIdentifier = "babel2.article.toolbar.reading-mode"
		accessibilityLabel = Babel2Localization.text(.readingMode)
		accessibilityValue = "off"
		applyColors()
	}

	required init?(coder: NSCoder) { nil }

	override func applyGlyphColor(_ color: UIColor) {
		for layer in [page] + lines {
			layer.strokeColor = color.cgColor
		}
	}

	override func startWorkingAnimation() {
		for (index, line) in lines.enumerated() where line.animation(forKey: "babel2.working") == nil {
			line.add(Self.pulse(delay: Double(index) * 0.2, period: 1.2), forKey: "babel2.working")
		}
	}

	override func stopWorkingAnimation() {
		lines.forEach { $0.removeAnimation(forKey: "babel2.working") }
	}

	/// 仅供自动化测试。
	var isAnimatingWorkForTesting: Bool { lines.contains { $0.animation(forKey: "babel2.working") != nil } }
}

/// 翻译：「文」+「A」。进行中两个字交替亮起。状态沿用翻译引擎的六种，按图标的三态显示：
/// 原文 / 有缓存 / 翻了一半 → 平时；翻译中 → 进行中；已译 → 成功（墨色方块底）；失败 → 晃一下后回到平时。
@MainActor
final class Babel2TranslateIconButton: Babel2StatusIconControl {
	private let hanzi = UILabel()
	private let latin = UILabel()
	private(set) var translationState: TranslationButtonState = .original

	override init(frame: CGRect) {
		super.init(frame: frame)
		let scale = glyphScale
		hanzi.text = "文"
		hanzi.font = .systemFont(ofSize: 15 * scale, weight: .medium)
		latin.text = "A"
		latin.font = .systemFont(ofSize: 11 * scale, weight: .semibold)
		for label in [hanzi, latin] {
			label.textAlignment = .center
			label.isAccessibilityElement = false
			glyph.addSubview(label)
		}
		// 设计网格里：「文」中心 (9.5, 11)，「A」中心 (18.5, 15.5)——A 在右下，略小
		hanzi.bounds = CGRect(x: 0, y: 0, width: 16 * scale, height: 18 * scale)
		hanzi.center = CGPoint(x: 9.5 * scale, y: 11 * scale)
		latin.bounds = CGRect(x: 0, y: 0, width: 10 * scale, height: 13 * scale)
		latin.center = CGPoint(x: 18.5 * scale, y: 15.5 * scale)
		accessibilityIdentifier = "babel2.article.toolbar.translate"
		setState(.original)
	}

	required init?(coder: NSCoder) { nil }

	override func applyGlyphColor(_ color: UIColor) {
		hanzi.textColor = color
		latin.textColor = color
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
		switch newState {
		case .working: setPhase(.working)
		case .translated: setPhase(.on)
		case .original, .cachedAvailable, .partialCacheAvailable, .failed: setPhase(.idle)
		}
		if newState == .failed, !wasFailed { shake() }
	}

	override func startWorkingAnimation() {
		guard hanzi.layer.animation(forKey: "babel2.working") == nil else { return }
		hanzi.layer.add(Self.pulse(delay: 0, period: 1.6), forKey: "babel2.working")
		latin.layer.add(Self.pulse(delay: 0.8, period: 1.6), forKey: "babel2.working")
	}

	override func stopWorkingAnimation() {
		hanzi.layer.removeAnimation(forKey: "babel2.working")
		latin.layer.removeAnimation(forKey: "babel2.working")
	}

	/// 仅供自动化测试。
	var isAnimatingWorkForTesting: Bool { hanzi.layer.animation(forKey: "babel2.working") != nil }
}
