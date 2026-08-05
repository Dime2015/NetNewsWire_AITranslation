//
//  NNWFeedIconStyle.swift
//  NetNewsWire — AI 翻译 fork
//
//  [外观] 本 fork 新增,上游没有这个文件。
//
//  ## 这个文件做什么
//
//  给订阅源图标(favicon)做统一化处理。**两件事,各有各的开关**:
//
//  1. **补底(默认开)**:有些 favicon 是**透明背景**的图形
//     (比如 Julia Evans 那颗星、Public Books 那个书签),没有方块边界,
//     于是它在一列图标里显得「飘」、左边缘比别人靠右几个像素,
//     一列扫下来边缘是锯齿状的。
//     → 给这类图标补一层**半透明的中性灰底**,让它也成为一个方块。
//     满铺型的图标(绝大多数)会把这层底完全盖住,**看不出任何变化**,
//     所以这一步只精确命中真正需要的那几个。
//
//  2. **去色(默认关 —— ⚠️ 用户 2026-07-28 明确决定,别改回去)**:
//     把彩色 favicon 转成灰度。
//
//     这条的来历值得写清楚,免得后人以为是没做完的半成品:
//     参考物 Reeder 的「外观」设置里有一个开关叫 **Grayscale favicons**,
//     我据此提议并默认打开了它 —— 理由是一屏十几个来自不同网站的彩色图标
//     (彩虹渐变、橙星、大红、亮橙、蓝底星空……)会互相争抢注意力。
//     实装之后**用户看了实物,明确表示希望图标保留颜色**,于是改为默认关闭。
//
//     **我从中该学到的**:Reeder 把它做成**开关**而不是直接去色,
//     本身就说明这是个**口味问题,不是最佳实践**。
//     参考物提供了开关的地方,默认值该跟用户走,而不是跟我的审美走。
//
//     代码保留着,因为将来若做成设置页里的开关,这里一行都不用改
//     (把 UserDefaults 的 `NNWFeedIconGrayscale` 置 true 即可生效)。
//
//  ## 三个实现上的坑(都是本项目教训里写过的,别重蹈)
//
//  - **不能用 CoreImage 做灰度**。本工程开着「表达式类型检查限时 1 秒 +
//    警告当错误」,`CIImage` / `CIFilter` 的初始化器重载太多,**直接编译失败**
//    (L50)。
//  - **也不能用 `.color` 混合模式做灰度** —— 那是网上最常见的写法,理论也对,
//    但在本工程的渲染上下文里**实测完全无效**(加工后取样,饱和度仍是 1.00,
//    一个字节没变,详见 L90)。所以这里是**逐像素自己算**的。**别"优化"回去。**
//  - **读像素必须用 `withUnsafeMutableBytes`**,不能把 Swift 数组的指针
//    传给 `CGContext(data:)` 后逃逸使用 —— 那是未定义行为(L52 踩过)。
//  - **补底的颜色要用半透明灰,不能用深/浅两套色**。因为处理结果是一张
//    **静态图片**,图片本身不会跟着系统深浅色变;而半透明灰底下透出的是
//    列表背景,于是浅色模式下它是浅灰、深色模式下它是深灰,**自动就对了**。
//    (同一个思路见 L59:能让系统自适应的,就别自己缓存+重建。)
//

#if os(iOS)

import UIKit
import Images

enum NNWFeedIconStyle {

	// MARK: - 开关

	/// 是否把订阅源图标去色。
	///
	/// ⚠️ **默认关闭 —— 用户 2026-07-28 看过实物后明确要求「图标要有颜色」。**
	/// 这是用户的口味决定,不是没做完,**别改回默认开启**(理由见文件头)。
	///
	/// 将来若做成设置页里的开关:把 UserDefaults 的 `NNWFeedIconGrayscale`
	/// 置 true 即可生效,本文件一行都不用改;记得切换后调一次 `invalidateCache()`,
	/// 否则看到的还是上一次加工好的缓存图。
	static var isGrayscaleEnabled: Bool {
		// 允许用 UserDefaults 覆盖(将来接设置页开关时,这里不用改)。
		if UserDefaults.standard.object(forKey: grayscaleKey) != nil {
			return UserDefaults.standard.bool(forKey: grayscaleKey)
		}
		return false	// 默认关闭:保留图标原本的颜色
	}

	private static let grayscaleKey = "NNWFeedIconGrayscale"

	// MARK: - 对外唯一入口

	/// 把一个订阅源图标处理成「统一风格」的版本。
	///
	/// 传 nil 返回 nil;两件事都不需要做时原样返回 —— 调用点因此可以无脑套一层,不用自己判断。
	@MainActor
	static func styled(_ icon: IconImage?) -> IconImage? {

		guard let icon else { return nil }

		// SF Symbol 类的图标(智能组的「今天」太阳、「全部未读」圆圈、「已加星标」星)
		// **不处理**:它们没有自己的颜色,是靠外面设 tintColor 上色的,
		// 在这里转成位图反而会把那套着色链路弄坏。
		guard !icon.isSymbol else { return icon }

		// 缓存:滚动时每个 cell 每次复用都会走一遍这里,不缓存会很卡。
		// 键用原 IconImage 对象的身份 —— 上游的 IconImageCache 对同一个源
		// 会一直返回同一个实例,所以这个键是稳的。
		let key = ObjectIdentifier(icon)
		if let cached = cache[key] { return cached }

		let processed = process(icon)
		cache[key] = processed
		return processed
	}

	// MARK: - 文件夹图标:软面板方块 + 强调色字形

	/// [外观] 2026-08-05:文件夹行的图标(用户要求:①匹配主题色 ②有玻璃质感 ③简洁)。
	///
	/// 画成「**软面板圆角方块** + 居中的系统 `folder` 字形」——
	/// 方块用的是全 app 同一套材质(上暗下亮的极淡渐变 + 整圈纯白亮边),
	/// 所以"玻璃质感"和 dock / 三档 / 选单同源,不是这里单独调出来的一套。
	/// 尺寸对齐旁边订阅源的 favicon 方块,一列图标大小一致。
	///
	/// ⚠️ **字形用系统 `folder`,不手绘**:用户给的参考就是这个形状,而这一轮已经两次
	/// 因为"全套手绘"把定过案的图标换丑了(L110/L111)。系统字形在小尺寸下的
	/// 描边粗细和圆角也比我们手绘的稳。
	///
	/// ⚠️ 返回的是**烘焙好的位图**(自带颜色),所以 `isSymbol: false`;
	/// 方块本身就是底,不需要宿主再垫一层,所以 `isBackgroundSuppressed: true`。
	@MainActor
	static func folderTile(for traits: UITraitCollection) -> IconImage {

		let side: CGFloat = 28					// 和订阅源 favicon 方块同宽
		let corner: CGFloat = 7					// ≈ side/4,和 favicon 的圆角观感一致
		let glyphSize: CGFloat = 15
		let colors = NNWSoftMaterial.panelColors(for: traits)
		let accent = NNWSoftMaterial.accent.resolvedColor(with: traits)

		let format = UIGraphicsImageRendererFormat()
		format.scale = traits.displayScale > 0 ? traits.displayScale : 3
		format.opaque = false

		let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side),
											format: format).image { context in
			let ctx = context.cgContext
			let rect = CGRect(x: 0, y: 0, width: side, height: side)
			let tile = UIBezierPath(roundedRect: rect, cornerRadius: corner)

			// ① 底:上暗下亮的极淡渐变(和面板同一条规律)
			ctx.saveGState()
			tile.addClip()
			if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
										 colors: [colors.top.resolvedColor(with: traits).cgColor,
												  colors.bottom.resolvedColor(with: traits).cgColor] as CFArray,
										 locations: [0, 1]) {
				ctx.drawLinearGradient(gradient,
									   start: CGPoint(x: rect.midX, y: rect.minY),
									   end: CGPoint(x: rect.midX, y: rect.maxY), options: [])
			}
			ctx.restoreGState()

			// ② **整圈**亮边 —— 玻璃感全靠它(L104)
			let w = NNWSoftMaterial.rimWidth
			let rim = UIBezierPath(roundedRect: rect.insetBy(dx: w / 2, dy: w / 2), cornerRadius: corner - w / 2)
			rim.lineWidth = w
			UIColor.white.withAlphaComponent(NNWSoftMaterial.rimAlpha(for: traits)).setStroke()
			rim.stroke()

			// ③ 字形:系统 folder,强调色,居中
			let config = UIImage.SymbolConfiguration(pointSize: glyphSize, weight: .medium)
			if let glyph = UIImage(systemName: "folder", withConfiguration: config)?
				.withTintColor(accent, renderingMode: .alwaysOriginal) {
				glyph.draw(in: CGRect(x: (side - glyph.size.width) / 2,
									  y: (side - glyph.size.height) / 2,
									  width: glyph.size.width, height: glyph.size.height))
			}
		}

		return IconImage(image, isSymbol: false, isBackgroundSuppressed: true)
	}

	/// 图标缓存失效(将来接设置页开关时,切换开关后要调一次,否则看到的还是旧图)。
	@MainActor
	static func invalidateCache() {
		cache.removeAll()
	}

	@MainActor
	private static var cache: [ObjectIdentifier: IconImage] = [:]

	// MARK: - 实际加工

	@MainActor
	private static func process(_ icon: IconImage) -> IconImage {

		let source = icon.image
		guard let cg = source.cgImage else { return icon }
		let w = cg.width, h = cg.height
		guard w > 0, h > 0 else { return icon }

		// 是不是「透明背景」的图标 —— 决定要不要补底。
		let needsBackplate = hasTransparentBackground(source)
		let wantsGrayscale = isGrayscaleEnabled

		// 两件事都不用做(绝大多数图标:满铺方块 + 去色关着)→ 原图直接放行,
		// 一个像素都不碰。否则每次滚动都为所有图标白跑一遍位图加工。
		guard needsBackplate || wantsGrayscale else { return icon }

		// ⚠️ **为什么是逐像素算,而不是用混合模式**:
		// 第一版写的是「画原图 → 用 `.color` 混合模式盖一层纯灰」——
		// 那是网上最常见的去色写法,理论也对(`.color` = 取上层色相饱和度 + 下层明暗)。
		// **但装机实测完全没生效**:取样加工后的橙色图标,饱和度仍然是 1.00,一个字节没变。
		// 换材质/换写法在同一个维度里试下去是浪费(L62),所以改成这条**结果完全由我们
		// 自己决定**的路:把像素读出来,自己算灰度,再写回去。图标最大 1024²、且有缓存,
		// 成本可以忽略。
		var pixels = [UInt8](repeating: 0, count: w * h * 4)

		let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
			guard let base = buffer.baseAddress,
				  let ctx = CGContext(data: base,
									  width: w, height: h,
									  bitsPerComponent: 8,
									  bytesPerRow: w * 4,
									  space: CGColorSpaceCreateDeviceRGB(),
									  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
			else { return false }
			ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
			return true
		}
		guard drawn else { return icon }

		// 补底用的半透明中性灰(预乘后的值)。
		// 用「半透明」而不是实色,是为了让它在浅色/深色模式下都自动合适 ——
		// 底下透出来的是列表背景,所以浅色下呈浅灰、深色下呈深灰,不用维护两套色。
		let plateAlpha: Double = 42			// 约 16% 不透明
		let plateGray: Double = 128
		let platePremultiplied = UInt8(plateGray * plateAlpha / 255)

		for i in stride(from: 0, to: pixels.count, by: 4) {
			let alpha = pixels[i + 3]
			if alpha < 8 {
				// 完全透明的地方:要么补一块半透明灰底,要么保持透明。
				if needsBackplate {
					pixels[i] = platePremultiplied
					pixels[i + 1] = platePremultiplied
					pixels[i + 2] = platePremultiplied
					pixels[i + 3] = UInt8(plateAlpha)
				}
				continue
			}
			// 有内容的地方:按 Rec.709 亮度权重折成灰(仅在去色开着时)。
			// (这三个系数是人眼对红绿蓝的敏感度差异,直接取平均值会让蓝色显得过亮。)
			guard wantsGrayscale else { continue }
			let r = Double(pixels[i]), g = Double(pixels[i + 1]), b = Double(pixels[i + 2])
			let y = UInt8(min(255, max(0, 0.2126 * r + 0.7152 * g + 0.0722 * b)).rounded())
			pixels[i] = y
			pixels[i + 1] = y
			pixels[i + 2] = y
		}

		let output: CGImage? = pixels.withUnsafeMutableBytes { buffer -> CGImage? in
			guard let base = buffer.baseAddress,
				  let ctx = CGContext(data: base,
									  width: w, height: h,
									  bitsPerComponent: 8,
									  bytesPerRow: w * 4,
									  space: CGColorSpaceCreateDeviceRGB(),
									  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
			else { return nil }
			return ctx.makeImage()
		}
		guard let output else { return icon }

		let rendered = UIImage(cgImage: output, scale: source.scale, orientation: source.imageOrientation)

		// 保留原图标的其余属性(是否 symbol、是否抑制背景、偏好色),
		// 只把图片换成加工过的版本 —— 上游那套取色/着色逻辑照常工作。
		return IconImage(rendered,
						 isSymbol: icon.isSymbol,
						 isBackgroundSuppressed: icon.isBackgroundSuppressed,
						 preferredColor: icon.preferredColor)
	}

	// MARK: - 判断「透明背景」

	/// 采样图片四角与四边中点,若多数点是透明的,判定为「透明背景的图形」。
	///
	/// 为什么采样边缘而不是整张图:满铺型图标(彩虹方块、纯色底 logo)的边缘一定不透明;
	/// 而单个图形(星星、书签、旗帜)的边缘几乎必然是空的。8 个点足够分开这两类,
	/// 而且成本恒定 —— 图标虽小,列表滚动时调用次数不少。
	private static func hasTransparentBackground(_ image: UIImage) -> Bool {

		guard let cg = image.cgImage else { return false }
		let w = cg.width, h = cg.height
		guard w >= 3, h >= 3 else { return false }

		// 重绘到一个**已知像素格式**的画布再读 —— 直接读原图的 dataProvider 是不安全的,
		// 因为 favicon 来自各种网站,位图格式(通道顺序、是否预乘)五花八门。
		var pixels = [UInt8](repeating: 0, count: w * h * 4)
		let ok = pixels.withUnsafeMutableBytes { buffer -> Bool in
			guard let base = buffer.baseAddress,
				  let ctx = CGContext(data: base,
									  width: w, height: h,
									  bitsPerComponent: 8,
									  bytesPerRow: w * 4,
									  space: CGColorSpaceCreateDeviceRGB(),
									  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
			else { return false }
			ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
			return true
		}
		guard ok else { return false }

		// 四角 + 四边中点,各往里缩一点点(正好压在最外圈像素上容易取到抗锯齿的半透明边)。
		let inset = max(1, min(w, h) / 16)
		let xs = [inset, w / 2, w - 1 - inset]
		let ys = [inset, h / 2, h - 1 - inset]
		var samples: [Int] = []
		for (i, x) in xs.enumerated() {
			for (j, y) in ys.enumerated() where !(i == 1 && j == 1) {	// 跳过正中心
				samples.append((y * w + x) * 4 + 3)						// +3 = alpha 通道
			}
		}

		let transparentCount = samples.filter { pixels[$0] < 26 }.count	// 26/255 ≈ 10%
		return transparentCount >= 6	// 8 个点里至少 6 个是空的
	}
}

#endif
