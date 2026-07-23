//
//  make-header-assets.swift
//  把头图素材加工成能直接放进 app 的样子(4 个页面 × 浅/深两版)
//
//  ## 怎么跑
//
//  ```bash
//  swiftc -O -o /tmp/make-header-assets tools/make-header-assets.swift
//  /tmp/make-header-assets "external resources/headers" "<输出目录>"
//  ```
//
//  ## 素材的设计前提(加工时**绝不能破坏**这一层)
//
//  每一页的浅色 / 深色是**同一场景的两个时刻**:同一构图、同一视角,
//  太阳→月亮、THE NEW YORKER→PLAYBOY、点起烛火。
//  于是"切到深色"不是"变暗了",而是"天黑了"。
//  → **所以浅深两版必须用同一个裁切框**,否则昼夜对应关系就断了。
//
//  ## 它做了什么(每一步都是量过之后才定的,不是随手加滤镜)
//
//  1. **按页面比例挑构图**。头图是一条很扁的横带,而原图是 16:9,
//     直接塞进去会被 aspectFill 从中间再切一刀(第一版就是这么把人头切掉的)。
//     所以每页单独定裁切框,**且裁切框自己就得是目标比例**。
//     ⚠️ 各页比例不同:Feed 页是 1/5 屏(2.30),其余是 1/4 屏(1.84)。
//
//  2. **浅色:白平衡对齐**。画里的"纸"偏黄偏饱和(#C5A670~#E1B479),
//     而 app 的暖纸是 #F3F0EB。头图底边要**融进**页面底色,
//     两种纸摆在一起会露出接缝。→ 把画里最亮的那一片对齐到 app 的纸。
//     **深色版不做这一步** —— 夜景的亮部是月光和烛火,把它们"矫正"成纸色就毁了。
//
//  3. **统一曝光**(浅深各自一组)。实测浅色四张平均亮度 0.40~0.62、
//     深色四张 0.18~0.28,**差到 55%** —— 不统一的话,在页面之间切换时
//     顶部会一亮一暗地跳。用 gamma 拉平(gamma 不会像线性缩放那样把亮部压爆)。
//
//  4. **缺哪版补哪版**。「文件夹」那张标称"深浅共用",但实测它最亮处亮度 0.94、
//     是一张明确的**白天**图,直接用在深色模式下会是一条发光的带子。
//     → 由脚本从白天版生成一版夜色(压暗 + 降饱和),用户已同意。
//
//  另外每张都输出一张**预览**:照抄 app 里真实的合成公式(压蒙版 + 上浓下淡)。
//  ⚠️ **直接看素材是判断不了效果的** —— 页面上看到的是压过、又从 18% 处淡出的版本;
//  尤其构图,不预览就会把主体放进淡出区里。
//
//  ⚠️ 想调效果,改下面 `pages` 那张表和「全局参数」里的数,别改算法。
//

import AppKit

// MARK: - 每个页面的配方(要调效果就改这里)

struct Page {
	/// 输出基名,同时也是资源目录里的图片名
	let assetName: String
	/// 浅色源文件名
	let lightFile: String
	/// 深色源文件名;**nil = 没有手绘夜色版,由脚本从浅色版生成**
	let darkFile: String?
	/// 浅色版的裁切框(归一化,原点左上)
	let crop: CGRect
	/// 深色版单独的裁切框;**nil = 和浅色用同一个**。
	///
	/// ⚠️ 什么时候需要单独裁:**只有当浅深两版画的不是同一个场景时**。
	/// 实测下来,这套素材里只有 Feed 页和今日未读是真正的"同场景昼夜版"
	/// (同构图、太阳→月亮);全部未读的夜版是「提灯夜行的信使」、
	/// 已加星标的夜版是「一箱珍藏」—— 都是另一幅画,焦点位置完全不同,
	/// 沿用浅色的框会裁到没有意义的地方(2026-07-23 用户实测指出)。
	let darkCrop: CGRect?
	/// 目标比例 = 屏宽 ÷ 头图高。头图高 = 屏高 × 比例系数,
	/// 现代 iPhone 宽高比约 0.46,所以:1/4 屏 → 0.46/0.25 ≈ 1.84;1/5 屏 → 0.46/0.20 ≈ 2.30
	let aspect: CGFloat
	let why: String
}

let pages: [Page] = [

	Page(assetName: "HeaderArtFeedList",
		 lightFile: "Feed页 浅色.png",
		 darkFile: "Feed页 深色.png",
		 // ⚠️ 这一页是 **1/5 屏**(用户定的:订阅列表是拿来找东西的,少占一截),
		 // 比例 2.30 比别页扁得多,能留的上下更少。
		 // 取整幅宽度、纵向收在"脸 + 杂志"这一段:脸在原图 y≈60,
		 // 杂志封面字样在 y≈230~330 —— 都要落在最浓的上半部。
		 crop: CGRect(x: 0.000, y: 0.064, width: 1.000, height: 0.772),
		 darkCrop: nil,		// 同场景昼夜版,共用一个框
		 aspect: 2.30,
		 why: "1/5 屏更扁,纵向收在「脸 + 杂志」这一段,封面字样落在最浓处"),

	// —— 下面两张是**首页专用**的另外两个档位(2026-07-23 加,底部三档切换用) ——
	// 首页三个档各一张画:未读 = 上面那张读杂志的;全部 = 一屋子成捆的杂志;★ = 那具铠甲。
	// ⚠️ 它们必须**单独裁一遍**,不能直接借用「已加星标」现成的资源:
	// 那张是按 1.84(1/4 屏)裁的,而首页是 2.30(1/5 屏),直接拿来 aspectFill
	// 会再从中间切掉两成 —— 正是 L72 那次"把人头切掉"的成因。

	Page(assetName: "HeaderArtFeedListAll",
		 lightFile: "全部Feed 浅色.png",
		 darkFile: "全部Feed 深色.png",
		 // 和「Feed页」那张是同一间屋子的另一幕(用户 2026-07-23 提供),
		 // 所以沿用同一个纵向取法:脸落在最浓的顶部,成捆的杂志往下延伸进渐隐区。
		 // ⚠️ 不敢再往下挪:再挪就切到发髻和头顶了(L72 的教训,宁可让下半部淡掉)。
		 crop: CGRect(x: 0.000, y: 0.064, width: 1.000, height: 0.772),
		 darkCrop: nil,		// 真·同场景昼夜版:同构图、月亮升起、烛火点上(已逐张看过)
		 aspect: 2.30,
		 why: "首页「全部」档:脸在最浓处,成捆的杂志往下淡出;深浅同场景共用一框"),

	Page(assetName: "HeaderArtFeedListStarred",
		 lightFile: "已加星标 浅色.png",
		 darkFile: "已加星标 深色.png",
		 // 浅色是那具铠甲。1/5 屏更扁,只能收得更紧:让头盔与胴甲落在最浓的上半部。
		 crop: CGRect(x: 0.230, y: 0.064, width: 0.770, height: 0.595),
		 // 深色是**另一幅画**(一箱珍藏),焦点完全不同,单独一个框(同 SmartFeedHeaderStarred 的道理)
		 darkCrop: CGRect(x: 0.048, y: 0.361, width: 0.478, height: 0.369),
		 aspect: 2.30,
		 why: "首页★档:和「已加星标」同一幅画,但按 1/5 屏重裁,免得 aspectFill 再切一刀"),

	Page(assetName: "SmartFeedHeaderToday",
		 lightFile: "今日未读 浅色.png",
		 darkFile: "今日未读 深色.png",
		 crop: CGRect(x: 0.000, y: 0.021, width: 1.000, height: 0.966),
		 darkCrop: nil,		// 同场景昼夜版(日出↔月出),共用一个框
		 aspect: 1.84,
		 why: "视觉最简,保留日出/月出与海平线,只按比例削上边"),

	Page(assetName: "SmartFeedHeaderUnread",
		 lightFile: "全部未读 浅色.png",
		 darkFile: "全部未读 深色.png",
		 // 主体是"递信"这个动作。全景里两侧的房舍缩到 220pt 高只剩细线噪音。
		 // 纵向位置按渐隐规律定:信落在约 40% 高度,两人的头在 8%~23%(最浓那一段)。
		 crop: CGRect(x: 0.196, y: 0.159, width: 0.660, height: 0.638),
		 // 夜版是**另一幅画**:提灯夜行的信使。用户 2026-07-23 指出上一版
		 // 「没让手里的灯笼露出来,体会不到这是晚上」—— 复查发现旧框
		 // (y 150~750)把**月亮(y≈95)和灯笼(y≈620~790)同时切掉了**,
		 // 只剩中间一条街景,当然读不出夜。
		 // 现在取整幅宽度、往下贴到底:月亮落在最浓的顶部,灯笼完整保留。
		 darkCrop: CGRect(x: 0.000, y: 0.035, width: 1.000, height: 0.965),
		 aspect: 1.84,
		 why: "收到两人与那封信,信在 40% 高度、头在最浓处,下部留给渐隐与标题"),

	Page(assetName: "SmartFeedHeaderStarred",
		 lightFile: "已加星标 浅色.png",
		 darkFile: "已加星标 深色.png",
		 // ⚠️ **浅色版被用户换过图**(2026-07-23):原来是古玩铺,现在是**一具铠甲**。
		 // 我一开始沿用了旧图的坐标,结果裁到了拉门和山水屏风上,完全没有铠甲 ——
		 // 用户原话:「乍一看不知道是什么意思」。
		 // 现在按用户要求:**让铠甲落在画面中间偏左**(约 41% 处),
		 // 头盔与胴甲在最浓的上半部,脚甲落进渐隐区不要紧。
		 crop: CGRect(x: 0.230, y: 0.064, width: 0.770, height: 0.744),
		 // 夜版是**另一幅画**(一箱珍藏),焦点完全不同,单独一个框
		 darkCrop: CGRect(x: 0.048, y: 0.361, width: 0.478, height: 0.462),
		 aspect: 1.84,
		 why: "浅色让铠甲落在中间偏左;深色是另一幅画(一箱珍藏),单独裁"),

	Page(assetName: "HeaderArtFolder",
		 lightFile: "文件夹 深色浅色共用.png",
		 // ⚠️ 没有手绘夜色版。实测这张最亮处亮度 0.94、是明确的白天图,
		 // 直接用在深色模式下会是一条发光的带子 → 由脚本生成夜色(用户已同意)。
		 darkFile: nil,
		 // 书架、文书箱、案上成捆的纸卷 —— 略往上收,
		 // 让书架的层层排列落在最浓处(那正是"文件夹"的意象)。
		 crop: CGRect(x: 0.000, y: 0.060, width: 1.000, height: 0.940),
		 darkCrop: nil,		// 夜色版是从这张生成的,当然同框
		 aspect: 1.84,
		 why: "书架层层排列落在最浓处,那正是「文件夹」的意象")
]

// MARK: - 全局参数

/// app 的暖纸底色(浅色模式)。**只有浅色素材**要把"纸"对齐到它。
let appPaper = (r: 0xF3 / 255.0, g: 0xF0 / 255.0, b: 0xEB / 255.0)
/// app 的暗底(深色模式),只用于预览
let appPaperDark = (r: 0x1E / 255.0, g: 0x1E / 255.0, b: 0x1E / 255.0)

/// 白平衡校正力度。1.0 = 完全对齐到 app 的纸(会显得寡淡),0 = 完全不动。
let whiteBalanceStrength = 0.75

/// 浅色四张统一到的平均亮度。原图 0.40~0.62,取中间偏亮一档。
let lightTargetMean = 0.52
/// 深色四张统一到的平均亮度。原图 0.18~0.28;深色模式下宁可偏暗,别发光。
let darkTargetMean = 0.22

/// 输出宽度(px)。iPhone 最宽 430pt × 3 倍 = 1290px,给到 1400 留余量。
let outputWidth = 1400

/// 从浅色版生成夜色时用的参数(只有「文件夹」那张走这条)
let derivedDarkBrightness = 0.44
let derivedDarkSaturation = 0.80

/// —— 下面两个只用于**预览**,是 app 里真实的合成参数 ——
let previewStrength = 0.80
let previewFadeStart = 0.18

// MARK: - 工具

func luminance(_ r: Double, _ g: Double, _ b: Double) -> Double {
	0.2126 * r + 0.7152 * g + 0.0722 * b
}

func hex(_ r: Double, _ g: Double, _ b: Double) -> String {
	String(format: "#%02X%02X%02X",
		   Int(max(0, min(1, r)) * 255), Int(max(0, min(1, g)) * 255), Int(max(0, min(1, b)) * 255))
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

/// 裁切 + 缩放(插值交给系统)
func cropAndResize(path: String, crop: CGRect, width targetWidth: Int, height targetHeight: Int)
	-> (pixels: [Double], width: Int, height: Int)? {

	guard let image = NSImage(contentsOfFile: path),
		  let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }

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

	// aspectFill:比例对不上就再切掉多出来的那一边,绝不拉伸变形
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

/// 找出这张图的「纸」:按亮度取最亮的一小撮像素求平均。
/// 不用整体平均 —— 那会被大片墨色拉走,而我们要对齐的是**纸**,不是画。
func paperColor(_ pixels: [Double], percentile: Double = 0.03) -> (r: Double, g: Double, b: Double) {
	var luminances = [Double]()
	luminances.reserveCapacity(pixels.count / 4)
	for i in stride(from: 0, to: pixels.count, by: 4) {
		luminances.append(luminance(pixels[i], pixels[i + 1], pixels[i + 2]))
	}
	let sorted = luminances.sorted()
	let threshold = sorted[Int(Double(sorted.count - 1) * (1 - percentile))]

	var r = 0.0, g = 0.0, b = 0.0, n = 0.0
	for i in stride(from: 0, to: pixels.count, by: 4)
	where luminance(pixels[i], pixels[i + 1], pixels[i + 2]) >= threshold {
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

/// ① 白平衡:把这张图的"纸"推向 app 的纸(**只对浅色素材**)
func applyWhiteBalance(_ pixels: inout [Double], strength: Double) -> (before: String, after: String) {
	let paper = paperColor(pixels)
	func gain(_ current: Double, _ target: Double) -> Double {
		guard current > 0.01 else { return 1 }
		return 1 + (target / current - 1) * strength
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
	let gamma = max(0.4, min(2.5, log(target) / log(before)))
	for i in stride(from: 0, to: pixels.count, by: 4) {
		pixels[i] = pow(pixels[i], gamma)
		pixels[i + 1] = pow(pixels[i + 1], gamma)
		pixels[i + 2] = pow(pixels[i + 2], gamma)
	}
	return (before, meanLuminance(pixels), gamma)
}

/// ③ 从浅色版生成夜色(只有没有手绘夜色版的页面走这条)
func deriveDark(_ pixels: [Double]) -> [Double] {
	var out = pixels
	for i in stride(from: 0, to: out.count, by: 4) {
		let lum = luminance(out[i], out[i + 1], out[i + 2])
		for c in 0..<3 {
			let desaturated = lum + (out[i + c] - lum) * derivedDarkSaturation
			out[i + c] = max(0, min(1, desaturated * derivedDarkBrightness))
		}
	}
	return out
}

/// ④ 预览:**照抄 app 里的合成公式**,把素材变成它在页面上真正的样子。
///
/// 来自 `TimelineFeedHeader.composite(layer:size:paper:strength:)`:
/// 先铺纸色,再以 strength 的透明度画素材,然后用一道竖直渐变从 fadeStart 往下
/// 把素材逐渐擦掉。于是每一行的素材占比 = strength × (1 - 擦除比例)。
func makeCompositePreview(_ pixels: [Double], width: Int, height: Int,
						  paper: (r: Double, g: Double, b: Double)) -> [Double] {
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

for page in pages {

	let outputHeight = Int((Double(outputWidth) / Double(page.aspect)).rounded())

	// 裁切框自己要是目标比例,否则 aspectFill 会**再从中间切一刀**,构图就不是你划的那个了
	for (label, rect) in [("浅色", page.crop), ("深色", page.darkCrop ?? page.crop)] {
		let cropAspect = (rect.width * 1672) / (rect.height * 941)
		if abs(cropAspect - page.aspect) > 0.09 {
			print("⚠️ 【\(page.assetName)】\(label)裁切框比例 \(String(format: "%.2f", cropAspect)) 偏离目标 \(page.aspect)")
		}
	}

	print("【\(page.assetName)】\(page.why)")
	print("  输出 \(outputWidth)×\(outputHeight)(比例 \(page.aspect))")

	// —— 浅色 ——
	guard var (light, width, height) = cropAndResize(path: "\(sourceDir)/\(page.lightFile)",
													 crop: page.crop,
													 width: outputWidth, height: outputHeight) else {
		print("  ❌ 读不了 \(page.lightFile)\n")
		continue
	}
	let balance = applyWhiteBalance(&light, strength: whiteBalanceStrength)
	let lightExposure = normalizeExposure(&light, target: lightTargetMean)
	print("  浅色:纸底 \(balance.before) → \(balance.after);"
		  + String(format: "亮度 %.3f → %.3f", lightExposure.before, lightExposure.after))

	// —— 深色 ——
	var dark: [Double]
	if let darkFile = page.darkFile {
		guard var loaded = cropAndResize(path: "\(sourceDir)/\(darkFile)",
										 crop: page.darkCrop ?? page.crop,
										 width: outputWidth, height: outputHeight)?.pixels else {
			print("  ❌ 读不了 \(darkFile)\n")
			continue
		}
		// ⚠️ 深色**不做白平衡**:夜景的亮部是月光和烛火,矫正成纸色就毁了
		let darkExposure = normalizeExposure(&loaded, target: darkTargetMean)
		print("  深色(手绘):" + String(format: "亮度 %.3f → %.3f(gamma %.2f)",
										 darkExposure.before, darkExposure.after, darkExposure.gamma))
		dark = loaded
	} else {
		dark = deriveDark(light)
		print(String(format: "  深色(脚本生成):亮度 %.3f —— 这张没有手绘夜色版", meanLuminance(dark)))
	}

	_ = writePNG(light, width: width, height: height, to: "\(outputDir)/\(page.assetName)-light.png")
	_ = writePNG(dark, width: width, height: height, to: "\(outputDir)/\(page.assetName)-dark.png")
	_ = writePNG(makeCompositePreview(light, width: width, height: height, paper: appPaper),
				 width: width, height: height, to: "\(outputDir)/\(page.assetName)-预览浅.png")
	_ = writePNG(makeCompositePreview(dark, width: width, height: height, paper: appPaperDark),
				 width: width, height: height, to: "\(outputDir)/\(page.assetName)-预览深.png")
	print("")
}
