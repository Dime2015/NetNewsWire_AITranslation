//
//  make-header-assets.swift
//  把智能源的头图素材加工成能直接放进 app 的样子
//
//  ## 怎么跑
//
//  ```bash
//  swiftc -O -o /tmp/make-header-assets tools/make-header-assets.swift
//  /tmp/make-header-assets "<素材目录>" "<输出目录>"
//  ```
//
//  ## 它做了什么(每一步都是有理由的,不是随手加滤镜)
//
//  原图是浮世绘风格、和纸底色的插画,直接放进 app 会露怯 —— 实测量过的三个问题:
//
//  1. **两张纸对不上**:图里的纸底是 #E8C79B~#F1D796(偏黄、偏饱和),
//     而 app 的暖纸是 #F3F0EB(接近中性)。头图底边要**融进**页面底色,
//     两种纸摆在一起,那条接缝就看得出来。
//     → 按「把图里最亮的那一片(也就是它的纸)对齐到 app 的纸」算一组分通道增益。
//
//  2. **三张之间明暗差太大**:平均色 #9E7E5A / #6A5B40 / #6D5D4B,
//     最亮那张比最暗的高 20% 以上。在三个智能源之间切换时顶部会一亮一暗地跳。
//     → 用 gamma 把三张的平均亮度拉到同一档(gamma 不会像线性缩放那样把亮部压爆)。
//
//  3. **构图不适合 1/4 屏的横条**:头图区实际只有约 210~220pt 高,
//     而「已加星标」那张有上百个小器物,缩到那个尺寸会糊成一团噪点。
//     → 每张单独定一个裁切框,只留读得出的那部分。
//
//  另外出一版**深色模式专用**的素材(压暗 + 略降饱和):
//  深色模式下 app 底色是 #1E1E1E,顶上摆一条明黄的带子会"发光"。
//  预先出好比在运行时压蒙版可控得多 —— 资源目录本来就支持按深浅色自动选。
//
//  ⚠️ 想调效果,改下面 `Recipe` 那张表里的数就行,别改算法。
//

import AppKit

// MARK: - 每张图的配方(要调效果就改这里)

struct Recipe {
	let fileName: String
	/// 裁切框(归一化坐标,原点在**左上角**)。目的是挑焦点,不是构图微调。
	let crop: CGRect
	/// 说明这么裁的理由,免得后人以为是随手划的
	let why: String
}

let recipes: [Recipe] = [
	Recipe(fileName: "今日未读.png",
		   // 落日、海平线、左侧松枝剪影 —— 本来就是三张里视觉最简的,几乎不用动,
		   // 只按头图比例削掉一点上边。
		   crop: CGRect(x: 0.000, y: 0.021, width: 1.000, height: 0.966),
		   why: "视觉最简,保留落日与海平线,只按比例削上边"),

	Recipe(fileName: "全部未读.png",
		   // 主体是"递信"这个动作。全景里两侧的房舍和竹篱缩到 220pt 高之后只剩细线噪音。
		   // ⚠️ 纵向位置是**按头图的渐隐规律定的**:头图上浓下淡、底部还压着标题,
		   // 所以主体必须落在**上三分之二**。这个框让那封信落在约 40% 高度处,
		   // 两个人的头在 8%~23%,都在最浓的那一段里。
		   crop: CGRect(x: 0.196, y: 0.159, width: 0.660, height: 0.638),
		   why: "收到两人与那封信,信落在 40% 高度、头在最浓处,下部留给渐隐与标题"),

	Recipe(fileName: "已加星标.png",
		   // 三张里密度最高的一张(主色占 30%、上百个小器物)。
		   // 收到左半:插花的青花大瓶当主角,配上方的货架 —— 器物大、轮廓清楚,
		   // 缩小之后仍读得出"一屋子收藏"的意思,而不是一片噪点。
		   crop: CGRect(x: 0.048, y: 0.361, width: 0.478, height: 0.462),
		   why: "收到左半,青花大瓶当主角,器物大、轮廓清楚,缩小后仍读得出")
]

// MARK: - 全局参数

/// app 的暖纸底色(浅色模式)。图里的"纸"要对齐到它。
let appPaper = (r: 0xF3 / 255.0, g: 0xF0 / 255.0, b: 0xEB / 255.0)

/// 白平衡校正的力度。1.0 = 完全对齐到 app 的纸(可能显得寡淡),
/// 0 = 完全不动。0.75 是"看不出接缝、又保住画本身暖意"的折中。
let whiteBalanceStrength = 0.75

/// 三张图统一到的平均亮度(0~1)。取值参照:原图三张分别约 0.55 / 0.42 / 0.44,
/// 0.52 意味着最亮那张略压、另两张提亮,彼此拉平。
let targetMeanLuminance = 0.52

/// 输出宽度(px)。够用即可:iPhone 最宽 430pt × 3 倍 = 1290px,
/// 给到 1400 留点余量;再大只是白占体积。
let outputWidth = 1400

/// 深色版:压暗到这个倍数 + 往灰里收一点饱和
let darkBrightness = 0.62
let darkSaturation = 0.85

/// —— 下面两个只用于**预览**,是 app 里真实的合成参数,改这里不影响素材本身 ——
/// 蒙版强度:1 = 原色直上,越小越被纸色拉回来。
/// 普通订阅源用 0.55(那是随便抓来的 logo,得防撞色);
/// 这三张是精挑的画,压那么狠等于白挑,所以预览按 0.80 看。
let previewStrength = 0.80
/// 从这个高度比例开始往下淡出(到底边完全消失)
let previewFadeStart = 0.18

// MARK: - 工具

func luminance(_ r: Double, _ g: Double, _ b: Double) -> Double {
	0.2126 * r + 0.7152 * g + 0.0722 * b
}

func hex(_ r: Double, _ g: Double, _ b: Double) -> String {
	String(format: "#%02X%02X%02X",
		   Int(max(0, min(1, r)) * 255), Int(max(0, min(1, g)) * 255), Int(max(0, min(1, b)) * 255))
}

/// 读一张图,顺便把它画成直上直下的 RGBA 缓冲(省得跟各种颜色空间纠缠)
func loadPixels(_ path: String) -> (pixels: [Double], width: Int, height: Int)? {
	guard let image = NSImage(contentsOfFile: path),
		  let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }

	let width = cgImage.width, height = cgImage.height
	var bytes = [UInt8](repeating: 0, count: width * height * 4)
	guard let context = CGContext(data: &bytes, width: width, height: height,
								  bitsPerComponent: 8, bytesPerRow: width * 4,
								  space: CGColorSpaceCreateDeviceRGB(),
								  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
	context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

	return (bytes.map { Double($0) / 255.0 }, width, height)
}

func writePNG(_ pixels: [Double], width: Int, height: Int, to path: String) -> Bool {
	var bytes = pixels.map { UInt8(max(0, min(1, $0)) * 255) }
	guard let context = CGContext(data: &bytes, width: width, height: height,
								  bitsPerComponent: 8, bytesPerRow: width * 4,
								  space: CGColorSpaceCreateDeviceRGB(),
								  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
		  let cgImage = context.makeImage() else { return false }

	let rep = NSBitmapImageRep(cgImage: cgImage)
	guard let data = rep.representation(using: .png, properties: [:]) else { return false }
	return (try? data.write(to: URL(fileURLWithPath: path))) != nil
}

// MARK: - 加工

/// 裁切 + 缩放(用 CoreGraphics 画一次,插值交给系统)
func cropAndResize(path: String, crop: CGRect, width targetWidth: Int, height targetHeight: Int) -> (pixels: [Double], width: Int, height: Int)? {

	guard let image = NSImage(contentsOfFile: path),
		  let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }

	// 归一化坐标(左上原点)换成像素坐标(CGImage 的裁切也是左上原点)
	let sourceRect = CGRect(x: crop.minX * CGFloat(cgImage.width),
							y: crop.minY * CGFloat(cgImage.height),
							width: crop.width * CGFloat(cgImage.width),
							height: crop.height * CGFloat(cgImage.height))
	guard let cropped = cgImage.cropping(to: sourceRect) else { return nil }

	var bytes = [UInt8](repeating: 0, count: targetWidth * targetHeight * 4)
	guard let context = CGContext(data: &bytes, width: targetWidth, height: targetHeight,
								  bitsPerComponent: 8, bytesPerRow: targetWidth * 4,
								  space: CGColorSpaceCreateDeviceRGB(),
								  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
	context.interpolationQuality = .high

	// aspectFill:裁切框和目标比例如果对不上,就再切掉多出来的那一边,绝不拉伸变形
	let sourceAspect = CGFloat(cropped.width) / CGFloat(cropped.height)
	let targetAspect = CGFloat(targetWidth) / CGFloat(targetHeight)
	var drawRect = CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight)
	if sourceAspect > targetAspect {
		let scaledWidth = CGFloat(targetHeight) * sourceAspect
		drawRect = CGRect(x: (CGFloat(targetWidth) - scaledWidth) / 2, y: 0,
						  width: scaledWidth, height: CGFloat(targetHeight))
	} else {
		let scaledHeight = CGFloat(targetWidth) / sourceAspect
		drawRect = CGRect(x: 0, y: (CGFloat(targetHeight) - scaledHeight) / 2,
						  width: CGFloat(targetWidth), height: scaledHeight)
	}
	context.draw(cropped, in: drawRect)

	return (bytes.map { Double($0) / 255.0 }, targetWidth, targetHeight)
}

/// 找出这张图的「纸」:按亮度取最亮的一小撮像素,求平均色。
/// 为什么不用整体平均:整体平均会被大片墨色拉走,而我们要对齐的是**纸**,不是画。
func paperColor(_ pixels: [Double], percentile: Double = 0.03) -> (r: Double, g: Double, b: Double) {
	var luminances = [Double]()
	luminances.reserveCapacity(pixels.count / 4)
	for i in stride(from: 0, to: pixels.count, by: 4) {
		luminances.append(luminance(pixels[i], pixels[i + 1], pixels[i + 2]))
	}
	let sorted = luminances.sorted()
	let threshold = sorted[Int(Double(sorted.count - 1) * (1 - percentile))]

	var r = 0.0, g = 0.0, b = 0.0, n = 0.0
	for i in stride(from: 0, to: pixels.count, by: 4) where luminance(pixels[i], pixels[i + 1], pixels[i + 2]) >= threshold {
		r += pixels[i]; g += pixels[i + 1]; b += pixels[i + 2]; n += 1
	}
	return n > 0 ? (r / n, g / n, b / n) : (1, 1, 1)
}

func meanLuminance(_ pixels: [Double]) -> Double {
	var sum = 0.0, n = 0.0
	for i in stride(from: 0, to: pixels.count, by: 4) {
		sum += luminance(pixels[i], pixels[i + 1], pixels[i + 2]); n += 1
	}
	return n > 0 ? sum / n : 0
}

/// ① 白平衡:把这张图的"纸"推向 app 的纸
func applyWhiteBalance(_ pixels: inout [Double], strength: Double) -> (before: String, after: String) {
	let paper = paperColor(pixels)
	// 分通道增益。夹住上限,免得某个通道原本就很暗时被拉爆。
	func gain(_ current: Double, _ target: Double) -> Double {
		guard current > 0.01 else { return 1 }
		let full = target / current
		return 1 + (full - 1) * strength
	}
	let gr = min(gain(paper.r, appPaper.r), 1.6)
	let gg = min(gain(paper.g, appPaper.g), 1.6)
	let gb = min(gain(paper.b, appPaper.b), 1.6)

	for i in stride(from: 0, to: pixels.count, by: 4) {
		pixels[i] = min(1, pixels[i] * gr)
		pixels[i + 1] = min(1, pixels[i + 1] * gg)
		pixels[i + 2] = min(1, pixels[i + 2] * gb)
	}
	let after = paperColor(pixels)
	return (hex(paper.r, paper.g, paper.b), hex(after.r, after.g, after.b))
}

/// ② 统一曝光:用 gamma 把平均亮度拉到同一档
func normalizeExposure(_ pixels: inout [Double], target: Double) -> (before: Double, after: Double, gamma: Double) {
	let before = meanLuminance(pixels)
	guard before > 0.01, before < 0.99 else { return (before, before, 1) }

	// mean^gamma = target → gamma = log(target)/log(mean)
	let gamma = max(0.5, min(2.0, log(target) / log(before)))
	for i in stride(from: 0, to: pixels.count, by: 4) {
		pixels[i] = pow(pixels[i], gamma)
		pixels[i + 1] = pow(pixels[i + 1], gamma)
		pixels[i + 2] = pow(pixels[i + 2], gamma)
	}
	return (before, meanLuminance(pixels), gamma)
}

/// ③ 深色版:压暗 + 略降饱和
func makeDarkVariant(_ pixels: [Double]) -> [Double] {
	var out = pixels
	for i in stride(from: 0, to: out.count, by: 4) {
		let lum = luminance(out[i], out[i + 1], out[i + 2])
		for c in 0..<3 {
			let desaturated = lum + (out[i + c] - lum) * darkSaturation
			out[i + c] = max(0, min(1, desaturated * darkBrightness))
		}
	}
	return out
}

/// ④ 预览:**照抄 app 里的合成公式**,把素材变成它在页面上真正的样子。
///
/// 公式来自 `TimelineFeedHeader.composite(layer:size:paper:)`:
/// 先铺纸色,再以 `strength` 的透明度画素材,然后用一道竖直渐变
/// 从 `fadeStart` 往下把素材逐渐擦掉(露出纸色)。
/// 于是每一行的素材占比 = strength × (1 - 擦除比例)。
///
/// ⚠️ 为什么非做这个预览不可:**直接看素材是判断不了效果的** ——
/// 页面上看到的是"压了蒙版、还从中间开始淡出"的版本,
/// 尤其构图必须把主体放在上三分之二,否则正好落在淡出区里。
func makeCompositePreview(_ pixels: [Double], width: Int, height: Int, paper: (r: Double, g: Double, b: Double)) -> [Double] {
	var out = pixels
	let fadeStartY = Double(height) * previewFadeStart
	for y in 0..<height {
		let erased = y <= Int(fadeStartY) ? 0.0
			: min(1.0, (Double(y) - fadeStartY) / (Double(height) - fadeStartY))
		let alpha = previewStrength * (1 - erased)
		for x in 0..<width {
			let i = (y * width + x) * 4
			out[i] = paper.r * (1 - alpha) + pixels[i] * alpha
			out[i + 1] = paper.g * (1 - alpha) + pixels[i + 1] * alpha
			out[i + 2] = paper.b * (1 - alpha) + pixels[i + 2] * alpha
		}
	}
	return out
}

// MARK: - 主流程

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
	print("用法:make-header-assets <素材目录> <输出目录>")
	exit(2)
}
let sourceDir = arguments[1], outputDir = arguments[2]
try? FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

// 头图区的形状:全宽 × 屏高的 1/4。现代 iPhone 宽高比约 0.46,
// 于是比例 = 0.46 / 0.25 ≈ 1.84。素材按这个比例出,装进去几乎不用再裁。
let outputHeight = Int((Double(outputWidth) / 1.84).rounded())
print("输出尺寸:\(outputWidth)×\(outputHeight)(比例 1.84,对应「全宽 × 1/4 屏」)\n")

for recipe in recipes {
	let inputPath = "\(sourceDir)/\(recipe.fileName)"
	guard var (pixels, width, height) = cropAndResize(path: inputPath, crop: recipe.crop,
													  width: outputWidth, height: outputHeight) else {
		print("❌ 读不了 \(inputPath)")
		continue
	}

	let balance = applyWhiteBalance(&pixels, strength: whiteBalanceStrength)
	let exposure = normalizeExposure(&pixels, target: targetMeanLuminance)

	let baseName = (recipe.fileName as NSString).deletingPathExtension
	let lightPath = "\(outputDir)/\(baseName)-light.png"
	let darkPath = "\(outputDir)/\(baseName)-dark.png"
	let dark = makeDarkVariant(pixels)
	_ = writePNG(pixels, width: width, height: height, to: lightPath)
	_ = writePNG(dark, width: width, height: height, to: darkPath)
	// 预览:素材在页面上真正的样子(压蒙版 + 上浓下淡)
	_ = writePNG(makeCompositePreview(pixels, width: width, height: height, paper: appPaper),
				 width: width, height: height, to: "\(outputDir)/\(baseName)-预览浅色.png")
	_ = writePNG(makeCompositePreview(dark, width: width, height: height,
									  paper: (0x1E / 255.0, 0x1E / 255.0, 0x1E / 255.0)),
				 width: width, height: height, to: "\(outputDir)/\(baseName)-预览深色.png")

	// 裁切框自己要是 1.84 比例,否则 aspectFill 会**再从中间切一刀**,
	// 构图就不是你划的那个了(第一版就是这么把人头切掉的)。
	let cropAspect = (recipe.crop.width * 1672) / (recipe.crop.height * 941)
	if abs(cropAspect - 1.84) > 0.09 {
		print("⚠️ 【\(baseName)】裁切框比例 \(String(format: "%.2f", cropAspect)) 偏离 1.84,aspectFill 会再切一刀")
	}

	print("【\(baseName)】\(recipe.why)")
	print("  纸底 \(balance.before) → \(balance.after)(app 的纸是 #F3F0EB)")
	print(String(format: "  平均亮度 %.3f → %.3f(gamma %.2f)", exposure.before, exposure.after, exposure.gamma))
	print("  输出 \(lightPath)")
	print("      \(darkPath)\n")
}
