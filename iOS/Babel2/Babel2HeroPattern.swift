import UIKit
import Babel2Core

/// 头部「微光点阵」（ADR-067，2026-09-28 用户从四种淡花纹里选定「D · 微光点阵」，
/// 并要求每个页面的颜色和纹路都不同、贴合各自的含义）。
///
/// 同属一族：一团极淡的色晕 + 一层细点阵，往下渐隐进纸色。六种纹路：
/// - 今日「晨光」暖杏：右侧地平线升起的半扇放射点线（日出）
/// - 全部「方阵」冷灰蓝：整齐的正方点阵（全部、有序）
/// - 外文源「经纬」雾蓝：右上角一颗由点组成、微微倾斜的地球（世界）
/// - 星标「星野」淡金：大小不一的散点，偶尔一颗十字星芒
/// - 订阅源「讯号」取图标主色：从右上角一圈圈扩散的点弧（广播信号）；只用于没有高清图的源
/// - 首页「蜂巢」中性暖灰：以居中标题为中心、左右对称的错位点阵
/// 浅色模式点阵 ×2.4、色晕 ×2.2（2026-09-29 用户真机两次反馈「浅色还不够」）。
///
/// 数字照搬用户看过的 1:1 预览（浓度 100%）。要整体调浓淡，只改 `strength`。
enum Babel2HeroPattern: Equatable {
	case dawn
	case grid
	case globe
	case stars
	case signal(UIColor)
	case hive

	/// 跨源列表各自的纹路。
	init(smartFeed: Babel2SmartFeed) {
		switch smartFeed {
		case .today: self = .dawn
		case .all: self = .grid
		case .foreign: self = .globe
		case .starred: self = .stars
		}
	}

	/// 整体浓度（1 = 预览里的 100%）。
	/// 2026-09-29 用户真机：「再浓一点」→ 1 → 1.3
	static let strength: CGFloat = 1.3

	/// 各纹路的主色（订阅源用传进来的图标主色）。
	var hue: UIColor {
		switch self {
		case .dawn: return Self.rgb(0xE3A56A)
		case .grid: return Self.rgb(0x94A6BA)
		case .globe: return Self.rgb(0x86A3DE)
		case .stars: return Self.rgb(0xDCBC68)
		case .signal(let color): return color
		case .hive: return Self.rgb(0xB6AD9B)
		}
	}

	/// 仅供自动化测试：纹路的名字。
	var nameForTesting: String {
		switch self {
		case .dawn: return "dawn"
		case .grid: return "grid"
		case .globe: return "globe"
		case .stars: return "stars"
		case .signal: return "signal"
		case .hive: return "hive"
		}
	}

	// MARK: - 绘制

	/// 在 size 大小的画布上画色晕与点阵（坐标原点在左上角）。浅色模式点阵淡一成。
	func draw(in context: CGContext, size: CGSize, dark: Bool) {
		let w = size.width
		let h = size.height
		let color = hue
		// 浅色纸底更吃颜色：点阵、色晕都要比深色更浓才看得出（2026-09-29 用户真机：浅色下太淡）
		let dotStrength = Self.strength * (dark ? 1 : 2.4)
		let glowBoost: CGFloat = dark ? 1 : 2.2
		let painter = DotPainter(context: context, color: color, width: w, height: h)

		switch self {
		case .dawn:
			// 太阳在右侧地平线：半扇 31 道放射线，每道上每 10pt 一个点
			let sun = CGPoint(x: w * 0.9, y: 178)
			Self.glow(context, center: sun, radius: 300, color: color, opacity: glowBoost * 0.30)
			for ray in 0...30 {
				let angle = CGFloat.pi + CGFloat(ray) / 30 * .pi
				for r in stride(from: CGFloat(34), to: 380, by: 10) {
					painter.dot(sun.x + r * cos(angle), sun.y + r * sin(angle), radius: 0.85, alpha: 0.5 * dotStrength * Self.falloff(r, 340))
				}
			}
		case .grid:
			let origin = CGPoint(x: w * 0.82, y: -10)
			Self.glow(context, center: origin, radius: 330, color: color, opacity: glowBoost * 0.24)
			for y in stride(from: CGFloat(6), to: h, by: 12) {
				for x in stride(from: CGFloat(6), to: w, by: 12) {
					painter.dot(x, y, radius: 0.8, alpha: 0.5 * dotStrength * Self.falloff(hypot(x - origin.x, y - origin.y), 330))
				}
			}
		case .globe:
			// 正交投影的地球，绕水平轴倾斜 0.38 弧度；背面的点不画
			let center = CGPoint(x: w * 0.8, y: 58)
			let radius: CGFloat = 150
			let tilt: CGFloat = 0.38
			Self.glow(context, center: center, radius: 300, color: color, opacity: glowBoost * 0.26)
			func put(latitude: CGFloat, longitude: CGFloat) {
				let phi = latitude * .pi / 180
				let lambda = longitude * .pi / 180
				let x = cos(phi) * sin(lambda)
				let y = sin(phi)
				let z = cos(phi) * cos(lambda)
				let tiltedY = y * cos(tilt) - z * sin(tilt)
				let tiltedZ = y * sin(tilt) + z * cos(tilt)
				guard tiltedZ > 0 else { return }
				let px = center.x + radius * x
				let py = center.y - radius * tiltedY
				let fade = Self.falloff(hypot(px - center.x, py - center.y) * 0.6, 260)
				painter.dot(px, py, radius: 0.85, alpha: 0.55 * dotStrength * (0.35 + 0.65 * tiltedZ) * fade)
			}
			for latitude in stride(from: CGFloat(-75), through: 75, by: 15) {
				for longitude in stride(from: CGFloat(0), to: 360, by: 5) { put(latitude: latitude, longitude: longitude) }
			}
			for longitude in stride(from: CGFloat(0), to: 360, by: 20) {
				for latitude in stride(from: CGFloat(-88), through: 88, by: 4) { put(latitude: latitude, longitude: longitude) }
			}
		case .stars:
			Self.glow(context, center: CGPoint(x: w * 0.7, y: -20), radius: 320, color: color, opacity: glowBoost * 0.24)
			var random = SeededRandom(seed: 41)
			for _ in 0..<170 {
				let x = w - w * pow(random.next(), 1.35)
				let y = h * pow(random.next(), 1.2)
				let fade = Self.falloff(hypot(x - w * 0.8, y + 10), 430)
				let isBright = random.next() < 0.06
				let alpha = (0.3 + 0.5 * random.next()) * dotStrength * fade
				let size = isBright ? 1.5 : 0.5 + 0.6 * random.next()
				painter.dot(x, y, radius: size, alpha: alpha * (isBright ? 1.2 : 1))
				if isBright && alpha > 0.06 {
					// 十字星芒：两道 0.6pt 细线
					let arm = 5 + random.next() * 3
					context.setStrokeColor(color.withAlphaComponent(alpha * 0.6).cgColor)
					context.setLineWidth(0.6)
					context.strokeLineSegments(between: [CGPoint(x: x - arm, y: y), CGPoint(x: x + arm, y: y),
						CGPoint(x: x, y: y - arm), CGPoint(x: x, y: y + arm)])
				}
			}
		case .signal:
			// 从右上角屏幕外一点向左下扩散的 26 圈点弧，每第三圈更密更深
			let origin = CGPoint(x: w + 16, y: -16)
			Self.glow(context, center: origin, radius: 340, color: color, opacity: glowBoost * 0.26)
			for ring in 0..<26 {
				let r = 30 + CGFloat(ring) * 13
				let strong = ring % 3 == 0
				let step = (strong ? 6 : 9) / r
				for angle in stride(from: CGFloat.pi / 2, through: .pi, by: step) {
					painter.dot(origin.x + r * cos(angle), origin.y + r * sin(angle), radius: strong ? 0.95 : 0.7,
						alpha: (strong ? 0.6 : 0.32) * dotStrength * Self.falloff(r, 360))
				}
			}
		case .hive:
			// 以正上方为中心、左右对称：每行错开半格
			let center = CGPoint(x: w / 2, y: -24)
			Self.glow(context, center: center, radius: 260, color: color, opacity: glowBoost * 0.22)
			var row = 0
			for y in stride(from: CGFloat(5), to: h, by: 11) {
				for x in stride(from: row % 2 == 1 ? CGFloat(7) : 0, to: w + 7, by: 14) {
					let distance = hypot((x - center.x) * 0.8, (y - center.y) * 1.5)
					painter.dot(x, y, radius: 0.8, alpha: 0.48 * dotStrength * Self.falloff(distance, 260))
				}
				row += 1
			}
		}
	}

	/// 离中心越远越淡：(1 − d/R)^1.35，超出 R 为 0。
	private static func falloff(_ distance: CGFloat, _ reach: CGFloat) -> CGFloat {
		pow(max(0, 1 - distance / reach), 1.35)
	}

	/// 色晕：中心 opacity，半径一半处剩三成，边缘为 0。
	private static func glow(_ context: CGContext, center: CGPoint, radius: CGFloat, color: UIColor, opacity: CGFloat) {
		let o = opacity * strength
		let colors = [color.withAlphaComponent(o).cgColor, color.withAlphaComponent(o * 0.3).cgColor, color.withAlphaComponent(0).cgColor] as CFArray
		guard let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 0.5, 1]) else { return }
		context.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
	}

	private static func rgb(_ hex: Int) -> UIColor {
		UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
	}

	/// 画点：画布外的、淡到看不见的点直接跳过。
	private struct DotPainter {
		let context: CGContext
		let color: UIColor
		let width: CGFloat
		let height: CGFloat

		func dot(_ x: CGFloat, _ y: CGFloat, radius: CGFloat, alpha: CGFloat) {
			guard alpha > 0.004, x > -3, x < width + 3, y > -3, y < height + 3 else { return }
			context.setFillColor(color.withAlphaComponent(min(alpha, 1)).cgColor)
			context.fillEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
		}
	}

	/// 固定种子的随机数（星野每次画出来都一样）。
	private struct SeededRandom {
		var state: UInt32
		init(seed: UInt32) { state = seed }
		mutating func next() -> CGFloat {
			state = state &+ 0x6D2B_79F5
			var t = (state ^ (state >> 15)) &* (1 | state)
			t = (t &+ ((t ^ (t >> 7)) &* (61 | t))) ^ t
			return CGFloat(t ^ (t >> 14)) / 4_294_967_296
		}
	}
}

// MARK: - 订阅源图标主色

extension Babel2HeroPattern {
	/// 没有图标或图标是黑白灰时用的中性暖灰。
	static let neutralSignalHue = rgb(0xA8A29A)

	/// 订阅源图标的主色：缩到 12×12，按饱和度加权取平均色相；
	/// 再把饱和度夹在 0.35–0.7、亮度夹在 0.7–0.9，保证深色 / 浅色模式下都是一团「淡而看得见」的颜色。
	/// 黑白灰图标（几乎没有饱和的像素）用中性暖灰。
	static func signalHue(from icon: UIImage?) -> UIColor {
		guard let cgImage = icon?.cgImage else { return neutralSignalHue }
		let side = 12
		var pixels = [UInt8](repeating: 0, count: side * side * 4)
		let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
			guard let space = CGColorSpace(name: CGColorSpace.sRGB),
				let context = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
					space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
			context.interpolationQuality = .medium
			context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
			return true
		}
		guard drawn else { return neutralSignalHue }

		var hueX: CGFloat = 0
		var hueY: CGFloat = 0
		var saturationSum: CGFloat = 0
		var brightnessSum: CGFloat = 0
		var weightSum: CGFloat = 0
		for index in stride(from: 0, to: pixels.count, by: 4) {
			let alpha = CGFloat(pixels[index + 3]) / 255
			guard alpha > 0.5 else { continue }
			let color = UIColor(red: CGFloat(pixels[index]) / 255 / alpha, green: CGFloat(pixels[index + 1]) / 255 / alpha,
				blue: CGFloat(pixels[index + 2]) / 255 / alpha, alpha: 1)
			var hue: CGFloat = 0
			var saturation: CGFloat = 0
			var brightness: CGFloat = 0
			color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: nil)
			// 太暗的像素色相不可靠；越鲜艳的像素说话越算数
			guard brightness > 0.15, saturation > 0.15 else { continue }
			let weight = saturation * saturation * alpha
			hueX += cos(hue * 2 * .pi) * weight
			hueY += sin(hue * 2 * .pi) * weight
			saturationSum += saturation * weight
			brightnessSum += brightness * weight
			weightSum += weight
		}
		// 有颜色的像素太少（黑白灰图标）→ 中性色
		guard weightSum > 1.5 else { return neutralSignalHue }
		var hue = atan2(hueY, hueX) / (2 * .pi)
		if hue < 0 { hue += 1 }
		let saturation = min(max(saturationSum / weightSum, 0.35), 0.7)
		let brightness = min(max(brightnessSum / weightSum, 0.7), 0.9)
		return UIColor(hue: hue, saturation: saturation, brightness: brightness, alpha: 1)
	}
}

// MARK: - 眉题文字

/// 标题上方那行小字（ADR-067）：今日未读 = 日期；其它跨源列表 =「智能列表」；订阅源 = 网站域名。
enum Babel2HeroEyebrow {
	static func text(smartFeed: Babel2SmartFeed?, feedURL: URL, homePageURL: URL?, now: Date = Date()) -> String? {
		switch smartFeed {
		case .today:
			return date(now)
		case .some:
			return Babel2Localization.text(.smartListEyebrow).uppercased()
		case .none:
			guard let host = (homePageURL ?? feedURL).host?.lowercased(), !host.isEmpty else { return nil }
			let bare = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
			return bare.uppercased()
		}
	}

	/// 「9月28日 星期日」（跟随手机语言；英文为「SUNDAY, SEPTEMBER 28」）。
	static func date(_ date: Date) -> String {
		let formatter = DateFormatter()
		formatter.setLocalizedDateFormatFromTemplate("MMMMdEEEE")
		return formatter.string(from: date).uppercased(with: formatter.locale)
	}

	/// 小字的样式：11pt 中等、字距拉开、浅灰。
	static func attributed(_ text: String, alignment: NSTextAlignment = .natural) -> NSAttributedString {
		let paragraph = NSMutableParagraphStyle()
		paragraph.alignment = alignment
		return NSAttributedString(string: text, attributes: [
			.font: Babel2Type.heroEyebrow,
			.foregroundColor: BabelPalette.tertiaryInk,
			.kern: Babel2Type.heroEyebrowKern,
			.paragraphStyle: paragraph
		])
	}
}

// MARK: - 视图

/// 画纹路的视图：透明底、不接收触摸；往下从 `fadeStart`（占高度的比例）开始渐隐到完全透明。
/// 深浅色切换、尺寸变化时重画。
final class Babel2HeroPatternView: UIView {
	var pattern: Babel2HeroPattern {
		didSet { if pattern != oldValue { setNeedsDisplay() } }
	}
	private let fadeMask = CAGradientLayer()

	init(pattern: Babel2HeroPattern, fadeStart: CGFloat) {
		self.pattern = pattern
		super.init(frame: .zero)
		isOpaque = false
		backgroundColor = .clear
		contentMode = .redraw
		isUserInteractionEnabled = false
		isAccessibilityElement = false
		fadeMask.colors = [UIColor.black.cgColor, UIColor.black.cgColor, UIColor.clear.cgColor]
		fadeMask.locations = [0, NSNumber(value: Double(fadeStart)), 1]
		layer.mask = fadeMask
		registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: Babel2HeroPatternView, _) in
			view.setNeedsDisplay()
		}
	}

	required init?(coder: NSCoder) { nil }

	override func layoutSubviews() {
		super.layoutSubviews()
		CATransaction.begin()
		CATransaction.setDisableActions(true)
		fadeMask.frame = bounds
		CATransaction.commit()
	}

	override func draw(_ rect: CGRect) {
		guard let context = UIGraphicsGetCurrentContext(), bounds.width > 0, bounds.height > 0 else { return }
		pattern.draw(in: context, size: bounds.size, dark: traitCollection.userInterfaceStyle == .dark)
	}

	/// 仅供自动化测试：把当前纹路画成图。
	func renderedImageForTesting() -> UIImage {
		UIGraphicsImageRenderer(bounds: bounds).image { context in
			layer.render(in: context.cgContext)
		}
	}
}

/// 顶栏下沿（ADR-067 取代细线；ADR-068 由黑色阴影改为纸色渐隐）：从纸色渐变到透明，高 30pt，
/// 文章滑到顶栏下面时像淡进纸里，没有「台阶」。不接收触摸。只用于有大图的订阅源与搜索时。
final class Babel2SoftEdgeView: UIView {
	static let height: CGFloat = 30

	override class var layerClass: AnyClass { CAGradientLayer.self }

	override init(frame: CGRect) {
		super.init(frame: frame)
		isUserInteractionEnabled = false
		isAccessibilityElement = false
		updateColors()
		registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: Babel2SoftEdgeView, _) in
			view.updateColors()
		}
	}

	required init?(coder: NSCoder) { nil }

	private func updateColors() {
		guard let gradient = layer as? CAGradientLayer else { return }
		let paper = BabelPalette.background.resolvedColor(with: traitCollection)
		gradient.colors = [paper.cgColor, paper.withAlphaComponent(0).cgColor]
	}
}
