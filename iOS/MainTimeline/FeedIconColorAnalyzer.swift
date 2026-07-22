//
//  FeedIconColorAnalyzer.swift
//  NetNewsWire — AI 翻译 fork
//
//  [外观] 分析订阅源图标:①它的「主色」是什么 ②它够不够格当整片头图用。
//
//  为什么需要「够不够格」这个判断(2026-07-22,用户提方案时没覆盖到的情况):
//  只按尺寸判断是不够的。**拿到了大图、但它是白底的**才是真正会崩的情况 ——
//  白底 logo(Benedict Evans 的白底红字 BE、Stratechery 等)拉满全宽,
//  顶部就是一大片白,"越往上越浓"浓的是白色,比没有图还难看。
//  所以判据是「尺寸够 **且** 非白底像素占比够」,白底图自动落到"主色渐变"那条路 ——
//  而它的主色恰好就是那个字的颜色,观感反而和别的源统一。
//
//  取主色的两个坑(都躲开了):
//  1. **必须跳过接近纯白的像素**。否则白底图的"出现最多的颜色"永远是白色。
//  2. **不能跳过低饱和度的像素**。Daring Fireball 的深灰、许多黑白 logo,
//     那个灰就是它的身份色;按饱和度过滤会把它们全判成"没有颜色"。
//
//  这个文件不属于上游 NetNewsWire,是本 fork 新增的。
//

import UIKit

/// 一次图标分析的结果。
struct FeedIconAnalysis {
	/// 主色:非白像素里出现比例最高的那一档颜色(取该档内的真实平均值,不是量化后的格子中心)。
	let dominantColor: UIColor
	/// 非白像素占比。越高说明图越"铺满"、越适合直接当头图;白底 logo 会很低。
	let coverage: CGFloat
}

enum FeedIconColorAnalyzer {

	/// 分析用的采样边长。32×32 = 1024 个像素,足够统计,又快到可以忽略不计。
	private static let sampleSide = 32

	/// 判定「接近纯白」的门槛:三个通道都高于它就算白底,不参与统计。
	private static let whiteThreshold: Int = 238

	/// 量化档位:每通道压成 16 档(4 bit)。太细会把渐变打散成一堆小票,选不出主色。
	private static let levels: Int = 16

	static func analyze(_ image: UIImage) -> FeedIconAnalysis? {
		guard let pixels = samplePixels(image) else { return nil }

		let total: Int = pixels.count / 4
		guard total > 0 else { return nil }

		// 票箱:量化颜色 → (票数, R/G/B 累加值),累加是为了最后还原成真实平均色
		var counts = [Int: Int]()
		var sums = [Int: (r: Int, g: Int, b: Int)]()
		var qualified: Int = 0

		let step: Int = 256 / levels

		for i in stride(from: 0, to: pixels.count, by: 4) {
			let r: Int = Int(pixels[i])
			let g: Int = Int(pixels[i + 1])
			let b: Int = Int(pixels[i + 2])
			let a: Int = Int(pixels[i + 3])

			// 只收「几乎完全不透明」的像素。位图是 premultipliedLast,半透明像素的 RGB
			// 被 alpha 预乘过(读出来偏暗偏灰),抗锯齿边缘全是这种像素。
			// 只取不透明像素,预乘与否就没有区别,顺带天然跳过边缘过渡色。
			// (注:2026-07-22 用真实图标做过对照,这一条对 Ars / Daring Fireball 的
			//  主色结果**没有影响** —— 它是稳健性改进,不是那次故障的原因。)
			if a < 250 { continue }
			if r > whiteThreshold && g > whiteThreshold && b > whiteThreshold { continue }	// 白底不算

			qualified += 1
			let key: Int = (r / step) * levels * levels + (g / step) * levels + (b / step)
			counts[key, default: 0] += 1
			var acc = sums[key] ?? (0, 0, 0)
			acc.r += r
			acc.g += g
			acc.b += b
			sums[key] = acc
		}

		let coverage: CGFloat = CGFloat(qualified) / CGFloat(total)

		guard let winner = counts.max(by: { $0.value < $1.value }), let acc = sums[winner.key] else {
			// 整张图都是白/透明:没有可用主色,交给调用方兜底
			return FeedIconAnalysis(dominantColor: .systemGray, coverage: coverage)
		}

		let n: CGFloat = CGFloat(winner.value)
		let color = UIColor(
			red: CGFloat(acc.r) / n / 255.0,
			green: CGFloat(acc.g) / n / 255.0,
			blue: CGFloat(acc.b) / n / 255.0,
			alpha: 1
		)
		return FeedIconAnalysis(dominantColor: color, coverage: coverage)
	}

	/// 把图缩到 32×32 并读出原始 RGBA 字节。
	///
	/// ⚠️ **必须在 `withUnsafeMutableBytes` 的闭包里画完**:
	/// 写成 `CGContext(data: &buffer, …)` 是**未定义行为** —— `&buffer` 交出去的指针
	/// 只保证在那一次调用期间有效,函数返回后就可能失效;之后 `context.draw` 写的地址
	/// 已经不受保证,读回来的可能是垃圾,而且不崩溃、不报错。
	///
	/// 说明:2026-07-22 排查"主色算错"时我一度认定是这个 UB 导致的,**那个判断是错的**
	/// (真凶是拿到了占位图标,见 L52)。这里改成安全写法是因为它本来就该这么写,
	/// 不是因为它制造了那次故障 —— 别被注释误导成"改了这里就能修颜色"。
	private static func samplePixels(_ image: UIImage) -> [UInt8]? {
		guard let cgImage = image.cgImage else { return nil }

		let side: Int = sampleSide
		let bytesPerRow: Int = side * 4
		var buffer = [UInt8](repeating: 0, count: bytesPerRow * side)

		let colorSpace = CGColorSpaceCreateDeviceRGB()
		let info: UInt32 = CGImageAlphaInfo.premultipliedLast.rawValue
		let drawRect = CGRect(x: 0, y: 0, width: side, height: side)

		let succeeded: Bool = buffer.withUnsafeMutableBytes { (raw: UnsafeMutableRawBufferPointer) -> Bool in
			guard let base = raw.baseAddress else { return false }
			guard let context = CGContext(
				data: base,
				width: side,
				height: side,
				bitsPerComponent: 8,
				bytesPerRow: bytesPerRow,
				space: colorSpace,
				bitmapInfo: info
			) else {
				return false
			}
			context.interpolationQuality = .medium
			context.draw(cgImage, in: drawRect)
			return true
		}

		return succeeded ? buffer : nil
	}
}

// MARK: - 由主题色推导「读得清的标题颜色」

extension FeedIconColorAnalyzer {

	/// 把订阅源的主题色变成一个**能安全用在纸色背景上**的标题颜色。
	///
	/// ⚠️ 2026-07-22 用户最初的设想是「浅色模式下比主题色**亮**一号、深色模式下**深**一号」,
	/// **这个方向是反的**,实测数字可证(对比度,越大越清楚):
	///
	/// | 源 | 浅色模式 原色 → 亮一号 | 浅色模式 原色 → 暗一号 |
	/// |---|---|---|
	/// | Lawfare 墨绿 | 5.6:1 → **2.7:1** ❌ | 5.6:1 → 12.4:1 ✅ |
	/// | 硅谷101 橙 | 2.8:1 → **2.2:1** ❌ | 2.8:1 → 4.5:1 ✅ |
	///
	/// 原因很直白:标题落在头图**最下方最淡的位置**,那里几乎就是纸色本身。
	/// 浅色模式背景接近白,字必须更**深**;深色模式背景接近黑,字必须更**亮**。
	///
	/// 而且**固定加减一个色号也不够**:Links TV 的主题色是近黑的 #141518,
	/// 深色模式下对比度只有 1.1:1,亮一号也才 1.3:1 —— 等于隐形。
	/// 所以这里的规则是「**保持色相,朝墨色方向压,直到对比度达标为止**」。
	///
	/// - Parameters:
	///   - brand: 源的主题色(由 analyze 得出)
	///   - paper: 标题实际压在上面的背景色(已按明暗解析过的纸色)
	///   - tint: 着色强度,0 = 纯墨色(黑/白),1 = 完全主题色
	///   - minContrast: 最低对比度,达不到就继续往墨色压
	static func readableTitleColor(brand: UIColor, paper: UIColor, tint: CGFloat, minContrast: CGFloat) -> UIColor {

		// 纸是亮的就用黑墨,纸是暗的就用白墨
		let paperIsLight: Bool = relativeLuminance(paper) > 0.5
		let ink: UIColor = paperIsLight ? .black : .white

		// 先按着色强度在「墨色」和「主题色」之间取一个基准色
		let base: UIColor = mix(ink, brand, weightOfSecond: tint)
		if contrastRatio(base, paper) >= minContrast {
			return base
		}

		// 不够清楚:把基准色一点点往墨色压,压到达标为止。
		// ink 和 paper 的对比度天然最大,所以这个循环一定会结束。
		var step: CGFloat = 0.05
		while step < 1 {
			let candidate: UIColor = mix(base, ink, weightOfSecond: step)
			if contrastRatio(candidate, paper) >= minContrast {
				return candidate
			}
			step += 0.05
		}
		return ink
	}

	/// 两色线性混合。weightOfSecond = 0 全取 first,= 1 全取 second。
	private static func mix(_ first: UIColor, _ second: UIColor, weightOfSecond t: CGFloat) -> UIColor {
		var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
		var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
		guard first.getRed(&r1, green: &g1, blue: &b1, alpha: &a1),
			  second.getRed(&r2, green: &g2, blue: &b2, alpha: &a2) else {
			return first
		}
		let k: CGFloat = min(max(t, 0), 1)
		return UIColor(red: r1 + (r2 - r1) * k,
					   green: g1 + (g2 - g1) * k,
					   blue: b1 + (b2 - b1) * k,
					   alpha: 1)
	}

	/// WCAG 相对亮度。
	private static func relativeLuminance(_ color: UIColor) -> CGFloat {
		var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
		guard color.getRed(&r, green: &g, blue: &b, alpha: &a) else { return 0 }
		func channel(_ c: CGFloat) -> CGFloat {
			c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
		}
		return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
	}

	/// WCAG 对比度比值(1:1 ~ 21:1)。
	private static func contrastRatio(_ first: UIColor, _ second: UIColor) -> CGFloat {
		let l1: CGFloat = relativeLuminance(first)
		let l2: CGFloat = relativeLuminance(second)
		let brighter: CGFloat = max(l1, l2)
		let darker: CGFloat = min(l1, l2)
		return (brighter + 0.05) / (darker + 0.05)
	}
}
