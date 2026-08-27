//
//  NNWForeignFeedIcon.swift
//  NetNewsWire — AI 翻译 fork
//
//  [外文][外观] 本 fork 新增(2026-08-09)。侧栏「外文」那一行的图标。
//
//  ## 为什么要单开一个文件
//
//  用户给了一张彩色地球(`external resources/外文.png`,已缩成 3 倍图放进资源目录),
//  要求是:「不知道这个 icon 在深色模式下好不好看,如果过于 standing out,
//  能否稍微把它在深色模式下调一调色调,加一层蒙版,**保留它的彩色**,
//  但是让它和深色模式更加和谐。」
//
//  也就是要**两张图**:浅色用原图,深色用调和过的。这段合成逻辑加上"谁来切换"的机制,
//  值得从那个纯数据的 `NNWForeignSmartFeed` 里分出来。
//
//  ## ⚠️ 深浅色是怎么切的 —— 用 `UIImageAsset`,不是自己监听
//
//  本项目在这件事上栽过(L105 第 2 条 / L119):**烘焙好的图片不会自己跟深浅色**,
//  凡是自己合成的图,都得有人在切换时叫它重画。
//
//  这里换一条更省心的路:把两张图注册进一个 `UIImageAsset`。
//  从它取出来的 `UIImage` 身上带着这个 asset,**放进 `UIImageView` 之后由 UIKit 自己重解析** ——
//  和资源目录里那些"浅色/深色两张"的图完全同一个机制,不需要我们监听任何通知。
//
//  ⚠️ 这条路**只对 `UIImageView` 成立**。2026-08-04 试过给 `UIBarButtonItem.image`
//  用同样的办法,**实测不生效**(那条路不会去重新解析 asset)。
//  侧栏图标走的正是 `UIImageView`(`FeedListMetrics.iconSize = 28`),所以这里可以用。
//
//  ## 调和的配方(深色那张)
//
//  | 步骤 | 做什么 | 为什么 |
//  |---|---|---|
//  | ① | 画原图 | — |
//  | ② | `.saturation` 叠 40% 的中灰 | **降饱和**,而不是变灰:蓝绿还在,只是不再是全屏最艳的东西 |
//  | ③ | `.sourceAtop` 叠 22% 的黑 | **压亮度**,让它退到深色底的明度区间里 |
//  | ④ | `.destinationIn` 再画一遍原图 | **把 alpha 收回来** —— ② 那一步是铺满整个矩形的,会给透明区染上色 |
//
//  ⚠️ 第 ④ 步不能省。`.saturation` 不像 `.sourceAtop` 那样只作用在已有内容上,
//  它会把圆形之外的透明区也涂上东西,不收一次 alpha 就会多出一个灰方块。
//
//  ⚠️ **不用 CoreImage**(L50):本工程开着「表达式类型检查限时 1 秒 + 警告当错误」,
//  CIFilter 的重载会让编译直接失败。这里全程 CoreGraphics。
//

#if os(iOS)

import UIKit

@MainActor enum NNWForeignFeedIcon {

	/// 资源目录里那张图的名字(3 倍图,120×120 像素 = 40pt)。
	private static let assetName = "nnwForeignFeedIcon"

	/// 侧栏那一行用的图。浅色是原图,深色是调和过的 —— 切换由 UIKit 自己完成。
	static let image: UIImage = {

		guard let base = UIImage(named: assetName) else {
			// 资源丢了也别崩:退回原来那个系统符号,至少那一行还有个图标
			return UIImage(systemName: "character.book.closed") ?? UIImage()
		}

		// ⚠️ 先补留白再谈深浅色 —— 两张图都要一样大
		let sized = paddedToMatchSymbols(base)

		let asset = UIImageAsset()
		asset.register(sized, with: UITraitCollection(userInterfaceStyle: .light))
		asset.register(harmonizedForDark(sized), with: UITraitCollection(userInterfaceStyle: .dark))

		// 从 asset 取出来的图带着这个 asset,放进 UIImageView 后会自己跟深浅色走
		return asset.image(with: UITraitCollection(userInterfaceStyle: .light))
	}()

	/// 给地球补一圈**透明留白**,让它画出来和旁边那几个系统符号一样大。
	///
	/// ## 为什么需要(用户 2026-08-09:「稍微感觉大了点,能否和"全部未读"前面那个一样大」)
	///
	/// **SF Symbol 天生自带一圈留白,而这张 PNG 是满铺的。** 实测(扫不透明像素的外接框):
	///
	/// | | 画布 | 图形 | 占比 |
    /// |---|---|---|---|
	/// | `largecircle.fill.circle`(全部未读) | 75×73 | 65×65 | **0.87** |
	/// | `sun.max.fill`(今天) | 79×77 | 69×69 | 0.87 |
	/// | 地球 PNG | 120×120 | 120×120 | **1.00** |
	///
	/// 侧栏图标盒子是 28pt、按比例缩放,所以圆圈实际画出来 65×(28/75) ≈ **24.3pt**,
	/// 而地球是**整整 28pt** —— 大了 15%,正是用户看出来的那一点。
	///
	/// 修法不是去改盒子(那会连累所有源的 favicon),而是**把这张图也做成 0.87 的占比**。
	/// 📌 判据:**两个东西"看起来一样大"比的是图形,不是画布** —— 满铺的位图和自带留白的
	/// 符号放在一起,画布对齐必然图形不对齐。
	private static func paddedToMatchSymbols(_ image: UIImage) -> UIImage {

		/// 图形该占画布的比例。取自上表里系统符号的实测值。
		let ratio: CGFloat = 0.87

		let side = max(image.size.width, image.size.height) / ratio
		let canvas = CGSize(width: side, height: side)

		let format = UIGraphicsImageRendererFormat()
		format.scale = image.scale
		format.opaque = false

		return UIGraphicsImageRenderer(size: canvas, format: format).image { _ in
			image.draw(in: CGRect(x: (side - image.size.width) / 2,
								  y: (side - image.size.height) / 2,
								  width: image.size.width, height: image.size.height))
		}.withRenderingMode(.alwaysOriginal)
	}

	/// 把彩色图调到"能和深色底共处"的程度:**降饱和 + 压亮度**,颜色本身保留。
	///
	/// 两个数就是全部旋钮 —— 嫌它在深色下还太跳就把它们调大,嫌太灰就调小。
	///
	/// 🔴 2026-08-12 重做:用户反馈深色模式下地球图标背后有一层**灰色背景**。
	///
	/// 病根在原来的"先铺满矩形再收回来"那套四步:第②步 `.saturation` 用一块
	/// **铺满整个画布矩形**的灰色去混合,而 Core Graphics 的合成公式里,
	/// **不管用什么混合模式,结果的 alpha 通道都遵循标准的"盖在上面"算法**
	/// (`αr = αs + αb×(1−αs)`)——那块灰色本身的 alpha(降饱和强度 0.4)会被
	/// **直接**算进结果里,哪怕它盖住的地方原来完全透明(αb=0)也一样,
	/// 于是整块画布(不只是地球图形)都被染上了 0.4 的不透明灰色。
	/// 第④步想靠"再画一遍原图、用 `.destinationIn` 挖回形状"来清掉这块灰,
	/// 在图形内部/外部纯色区域算得对,**但地球边缘那一圈半透明的抗锯齿像素**
	/// 会在这套多步公式里被放大误差,残留成一圈看得见的灰边/灰底。
	///
	/// 现在改成**先按原图的 alpha 形状裁开画布,再叠色**:后面不管怎么混合,
	/// 物理上都画不到图形外面去,不需要再靠最后一步"挖回来"补救,
	/// 也就不存在"挖不干净"这个问题了。
	private static func harmonizedForDark(_ image: UIImage) -> UIImage {

		/// 降饱和的程度(0 = 原样,1 = 全灰)
		let desaturation: CGFloat = 0.40
		/// 压亮度的程度(0 = 原样,1 = 全黑)
		let darkening: CGFloat = 0.22

		let format = UIGraphicsImageRendererFormat()
		format.scale = image.scale
		format.opaque = false

		let rect = CGRect(origin: .zero, size: image.size)
		return UIGraphicsImageRenderer(size: image.size, format: format).image { context in

			let ctx = context.cgContext

			// 先按原图的透明度形状裁一刀——地球轮廓之外(包括半透明的抗锯齿边缘)
			// 从物理上就不会被后面的叠色画到,不再需要"画完再挖回来"这种容易漏的补救。
			if let mask = image.cgImage {
				ctx.clip(to: rect, mask: mask)
			}

			// ① 原图
			image.draw(in: rect)

			// ② 降饱和:拿一块**中灰**按 `.saturation` 混进去。
			// 该混合模式取「源的饱和度 + 目标的色相与明度」—— 源是灰(饱和度 0),
			// 于是按 alpha 的比例把目标往灰的方向拉,色相一点不变。
			ctx.setBlendMode(.saturation)
			UIColor(white: 0.5, alpha: desaturation).setFill()
			ctx.fill(rect)

			// ③ 压亮度。`.sourceAtop` 只落在已有内容上,不碰透明区
			ctx.setBlendMode(.sourceAtop)
			UIColor(white: 0, alpha: darkening).setFill()
			ctx.fill(rect)
		}.withRenderingMode(.alwaysOriginal)
	}
}

#endif
