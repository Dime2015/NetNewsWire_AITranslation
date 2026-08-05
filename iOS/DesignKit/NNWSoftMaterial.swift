//
//  NNWSoftMaterial.swift
//  NetNewsWire — AI 翻译 fork
//
//  [外观] 本 fork 新增。2026-08-04 设计试验:参考图那套「软面板」材质。
//
//  ## 数值不是估的,是从参考图逐像素采样来的
//
//  用一个自写的取色工具扫了用户提供的三张参考图
//  (`external resources/references/`),得到这些硬事实 ——
//  之前凭目测画的几版都不像,病根就在下面这四条全都猜反了:
//
//  | | 目测版(错) | 采样实测 |
//  |---|---|---|
//  | 白边粗细 | 1.5pt,整圈均匀 | **0.8pt hairline**(见下方更正) |
//  | 层间色差 | 相差 10–15 级灰 | **只差 2–5 级**(面板 #E5 vs 画布 #EA) |
//  | 渐变方向 | 上亮下暗 | **由上向下变亮**(#E5→#E7) |
//  | 阴影 | 短而重 | **极淡极宽**(贴边只暗 7–10 级,扩散约 5pt) |
//
//  **最反直觉的一条**:面板和背景几乎同色,层次全靠那道 hairline 撑起来。
//  色差一拉大就立刻变回"贴上去的塑料板" —— 越想做出层次越要克制色差。
//
//  ## ⚠️ 2026-08-04 二次采样的更正:亮边是**整圈**,不是"只有上缘"
//
//  第一次采样**只扫了上缘**,就下结论说"上缘最亮、往下迅速衰减",于是这里把
//  下半圈画到了 3% 透明度 —— 等于没有。用户的反馈是「玻璃的感觉都不强」。
//
//  重扫参考图 IMG_2440 那条轨道的四条边(逐像素),实测:
//
//  | 边 | 峰值 |
//  |---|---|
//  | 上缘 y=1142 | **#FFFFFF** |
//  | 下缘 y=1418 | **#FFFFFF** |
//  | 左缘 x=664–667 | #F6→#F9(246–249) |
//  | 右缘 x=1665–1670 | **#FFFFFF** |
//
//  四条边都是 246–255、宽 4–6px(@6.4px/pt ≈ 0.7–0.9pt)。
//  **"玻璃感"就出在这一圈完整的亮边上** —— 它是"一块有厚度的透明片"的唯一线索。
//  只画上缘 = 一张贴纸。**别再把它衰减掉。**(教训见 L104)
//
//  ## 一处开关
//
//  `isEnabled` 设成 false 就整体退回原样(不画面板、不画高光、不画阴影),
//  方便和旧版对比、也方便快速回滚。整轮改动都在 `design/soft-dock` 分支上。
//

#if os(iOS)

import UIKit
import ObjectiveC	// 工具栏外观的存/还原用关联对象

enum NNWSoftMaterial {

	/// 总开关。false = 完全不生效,控件回到改动前的样子。
	static let isEnabled = true

	/// **iOS 27 起:栏里那层胶囊由系统画,我们不再自己画** —— 这是唯一真源,别在各处重复判断版本。
	///
	/// ## 为什么必须分版本(2026-08-05,在用户的 iOS 27 真机上逐条件实测出来的)
	///
	/// iOS 26/27 会给栏里的每一项(或一组)垫一层液态玻璃胶囊。我们原本用
	/// `hidesSharedBackground = true` 把它拆掉,好让自己那层软面板成为唯一的一层。
	/// **但在 iOS 27 上,那层"共享背景"顺带管着「内容能不能从栏底下穿过去」** ——
	/// 一拆,正文就在栏上沿被硬切断,栏那块变成一条不透明黑带(用户报的「遮罩」和
	/// 「没有渐隐」是同一个病的两个症状)。实测数据见 `nnwHideSystemGlassCapsule` 的注释。
	///
	/// 于是 iOS 27 上只剩两种可能,**不能兼得**:
	///
	/// | | 内容穿过栏底 | 单层 |
	/// |---|---|---|
	/// | 拆掉系统胶囊 + 画我们的面板 | ❌ 硬切断 | ✅ |
	/// | 保留系统胶囊 + 画我们的面板 | ✅ | ❌ **两层套娃**(用户 2026-08-05 截图指出) |
	/// | **保留系统胶囊 + 不画我们的面板** | ✅ | ✅ ← 就是这条 |
	///
	/// ⚠️ 查过 SDK:`hidesSharedBackground` 是唯一相关的开关,
	/// **没有"保留行为、只隐藏外观"的第三种接口**。所以这不是偷懒,是没有别的路。
	///
	/// **iOS 26 保持原样**(那里拆掉系统胶囊没有副作用,不拆反而是套娃),
	/// 已逐像素确认改动前后零差异。
	///
	/// ⚠️ **这个开关只管"栏里的控件"**。自绘选单(`NNWMenu`)不在栏里、
	/// 系统不给它垫胶囊,那里照旧画我们自己的软面板 —— **别把它也关掉**。
	static var systemDrawsBarCapsule: Bool {
		ProcessInfo.processInfo.isOperatingSystemAtLeast(
			OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 0))
	}

	/// **全 app 圆形/胶囊控件的统一尺寸(直径 = 高度)。这是唯一真源。**
	///
	/// ⚠️ 用户 2026-08-05 明确要求:「以后都一直保持一样(如果又要修改任何一方)」。
	/// 所以**别再在别处写死尺寸** —— 下面这些全部读这一个数:
	///   · 首页 / 文章列表页导航栏的磨砂圆钮(`NNWSoftGlassButton.discSize`)
	///   · 底部工具栏的烘焙圆钮(`roundButtonImage` 的 diameter 默认值)
	///   · 三档控件的高度(`NNWReadingModeBar.barHeight`)
	/// 改这一个数,三处一起变;想只改一处 = 违背用户的要求,别这么干。
	static let controlDiameter: CGFloat = 40

	// MARK: - 颜色:**相对于 app 自身的底色**推导,不用参考图的绝对色号
	//
	// ⚠️ 2026-08-04 第一版就栽在这里:直接把参考图的冷灰 #E5/#E7 搬进来,
	// 而本 app 的底是暖纸色 —— 米色纸上糊了一块脏灰(用户原话"改的非常差")。
	//
	// 参考图真正的规律是**相对关系**,不是那几个 hex:
	//   画布 #EA(234) → 面板 #E5–#E7(-5 ~ -3) → 胶囊 #E9–#ED(-1 ~ +3)
	// 所以这里按同样的差值,从 `AppAppearance.paperBackground` 现推 —— 底色是暖是冷都跟得上。

	/// 面板(dock 本体):比底色**暗** 3–5 级,由上向下变亮
	static func panelColors(for traits: UITraitCollection) -> (top: UIColor, bottom: UIColor) {
		let isDark = traits.userInterfaceStyle == .dark
		if isDark {
			// 深色模式下"更暗"无从谈起(底已经很暗),改为比底色亮一档
			return (shift(paper(traits), by: 9), shift(paper(traits), by: 13))
		}
		// [外观] 2026-08-05:**中性玻璃档回到实测的 −2/0**。
		//
		// 参考图的面板(232)和它的画布(234)几乎同色 —— 层次**全靠那道纯白亮边**撑。
		// 之前在暖纸底上把它压到 −9/−6,是因为暖纸太亮、亮边发不出光,
		// 只好用色差硬撑层次 —— 方向反了(L101「越想做层次越要克制色差」只走了一半)。
		// 画布换成中性 #EAEAEA 之后,亮边的对比度从 Δ10 升到 Δ21,色差就该收回去。
		return AppAppearance.isGlassCanvas
			? (shift(paper(traits), by: -2), shift(paper(traits), by: 0))
			: (shift(paper(traits), by: -9), shift(paper(traits), by: -6))
	}

	/// 选中胶囊:比面板亮 4 级左右,做出"嵌在槽里的一块"
	static func capsuleColors(for traits: UITraitCollection) -> (top: UIColor, bottom: UIColor) {
		let isDark = traits.userInterfaceStyle == .dark
		if isDark { return (shift(paper(traits), by: 20), shift(paper(traits), by: 26)) }
		// 实测参考图 IMG_2440:选中胶囊 238–240,画布 234 → **+4/+6**
		return AppAppearance.isGlassCanvas
			? (shift(paper(traits), by: 4), shift(paper(traits), by: 6))
			: (shift(paper(traits), by: 2), shift(paper(traits), by: 6))
	}

	private static func paper(_ traits: UITraitCollection) -> UIColor {
		AppAppearance.paperBackground.resolvedColor(with: traits)
	}

	/// 在 RGB 上整体加减若干级(0–255)。近中性色上等同于只动明度,色相不会跑。
	private static func shift(_ color: UIColor, by delta: CGFloat) -> UIColor {
		var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
		guard color.getRed(&r, green: &g, blue: &b, alpha: &a) else { return color }
		let d = delta / 255
		return UIColor(red: min(max(r + d, 0), 1),
					   green: min(max(g + d, 0), 1),
					   blue: min(max(b + d, 0), 1), alpha: a)
	}

	/// 图标/文字墨色。跟随 app 既有的墨色,别再引第三套。
	static var ink: UIColor { AppAppearance.inkPrimary }

	/// 强调色。默认是实测参考图精确命中的 #FF5A1F。
	///
	/// [外观] 2026-08-05:色号搬进 `NNWAccentPalette`,可在设置里一键换成别的颜色
	///(用户提出的方案)。这里只是转发,**别再往这里写死色号**。
	@MainActor
	static var accent: UIColor { NNWAccentPalette.current }

	// MARK: - 形状与光影(单位:pt)

	/// 亮边线宽 = **1.2pt**。
	///
	/// ## 比例尺是怎么定死的(2026-08-05,第三次采样)
	///
	/// 前两轮换算用的 6.4 px/pt 是**猜的**,没有锚点。这次用一个硬锚点重定:
	/// 参考图 IMG_2442 的菜单文字实测「Hide」升部高 63px。
	/// 拉丁字母升部 ≈ 0.75em,所以 em ≈ 84px;而这显然是 iOS 标准正文 **17pt**
	///(菜单文字全世界都是这个号)。→ **84px ÷ 17pt = 4.94 px/pt**。
	/// 交叉验证:卡片宽 1255px ÷ 4.94 = **254pt** —— 正好是 iOS 系统菜单的标准宽度。
	/// 两条独立的线索对上了,比例尺可信。
	///
	/// 于是亮边 6px ÷ 4.94 = **1.2pt**(原来按 6.4 px/pt 算成 0.8pt,**细了三分之一**)。
	/// 用户 2026-08-05 的原话是「边缘也没有反光效果」—— 就是这条细出来的。
	static let rimWidth: CGFloat = 1.2

	/// 亮边的白色浓度。实测参考图**四条边都是 #FFFFFF**(左右在 y=700 和 y=1200
	/// 两个高度上都量过,一样亮)—— 是一整圈均匀的纯白,不是有方向的高光。
	static func rimAlpha(for traits: UITraitCollection) -> CGFloat {
		traits.userInterfaceStyle == .dark ? 0.20 : 1.0
	}

	/// 选单/卡片里的字色:**近纯黑**。
	///
	/// ⚠️ 不要用 `AppAppearance.inkPrimary`(#2C2823,亮度 40)——
	/// 参考图实测是 **#0A0A0A(亮度 10)**,差了四倍。
	/// 用户 2026-08-05 的原话:「黑色好像也不够深不够通透」。量出来确实如此。
	/// 暖纸底上留一丝暖意即可,不必真的纯黑。
	static var menuInk: UIColor {
		UIColor { $0.userInterfaceStyle == .dark
			? UIColor(red: 0xF2/255, green: 0xEF/255, blue: 0xE9/255, alpha: 1)
			: UIColor(red: 0x0E/255, green: 0x0D/255, blue: 0x0B/255, alpha: 1) }
	}

	/// 选单里的分隔线:比卡片底**暗 21 级**、粗 **1.2pt**(实测 6px ÷ 4.94)。
	/// 原来画的是 1 像素发丝线 + 极淡色,在暖纸上基本看不见 —— 卡片因此显得"平"。
	static let menuSeparatorWidth: CGFloat = 1.2
	static func menuSeparatorColor(for traits: UITraitCollection) -> UIColor {
		let isDark = traits.userInterfaceStyle == .dark
		return shift(paper(traits), by: isDark ? 14 : -30)
	}

	/// 阴影:极淡、极宽。实测贴边比背景暗 7–10 级,扩散约 5pt。
	static let shadowRadius: CGFloat = 6
	static let shadowOffsetY: CGFloat = 2
	/// 浅色下的阴影浓度。0.13 在暖纸底上量到"贴边暗 7 级",正落在实测区间里。
	/// ⚠️ 真正让阴影变明显的从来不是这个数,而是**套娃**(见 NNWSoftPanel 的注释)。
	static func shadowOpacity(for traits: UITraitCollection) -> Float {
		traits.userInterfaceStyle == .dark ? 0.55 : 0.13
	}

	// MARK: - 圆钮:把同一套材质**烘焙进一张图片**

	/// 把一个手绘图标压进一颗「软面板圆钮」,返回可直接塞进 `UIBarButtonItem.image` 的图。
	///
	/// ## 为什么是烘焙图片,而不是 customView
	///
	/// 底部工具栏那两个键(设置齿轮、加号)**只允许换 image 和 tintColor**:
	/// 加号是 storyboard 的 IBOutlet,上游还往它身上挂 `menu` 和 `isEnabled`
	/// (`MainFeedCollectionViewController.swift:897`)—— 换成 customView 会把那个
	/// 长按菜单整个弄丢。CLAUDE.md 点名过这个坑,这里绕开它:面板画进图片里,
	/// 走的还是被允许的那条 image 通道,`toolbarItems` 一个字节都没动。
	///
	/// ## ⚠️ 深浅色:**按传进来的 traits 现画**,调用方负责在深浅色变化时重画
	///
	/// 试过更省事的 `UIImageAsset`(登记浅色/深色两张,让 UIKit 自己挑)——
	/// **实测不生效**:2026-08-04 在深色下截图,齿轮和加号仍是浅色那张,
	/// 重启 app 也一样。`UIBarButtonItem.image` 这条路不会去重新解析 asset。
	///
	/// 所以改成最笨也最可控的做法:画哪一张由参数说了算,
	/// 调用方(`nnwRestyleToolbarIcons`)注册 `registerForTraitChanges` 在切深浅色时重画。
	///
	/// ## ⚠️ 另一个坑:尺寸要按 `displayScale` 算准
	///
	/// 第一版用 `UITraitCollection.current` 取 scale —— 在视图层级之外它是 **1**,
	/// 于是那张 3 倍图被**按 1 倍解释**:54pt 的图变成 162pt,四个按钮全部胀成三倍大,
	/// 导航栏还挤到把搜索折进了「…」溢出菜单。
	/// **这是"点/像素两套坐标对不上"的又一变种(L73)。**
	///
	/// - Parameters:
	///   - icon: 24×24 的模板图(`NNWDockIcons` 那一套)
	///   - traits: 用哪一套深浅色/缩放来画。**传宿主视图的 `traitCollection`**,别传 `.current`
	///   - tint: 图标颜色,默认强调橙
	///   - diameter: 面板直径。默认走 `controlDiameter`(全 app 唯一真源),别单独传值
	@MainActor
	static func roundButtonImage(icon: UIImage,
								 traits: UITraitCollection,
								 tint: UIColor? = nil,
								 diameter: CGFloat = controlDiameter) -> UIImage {

		// [外观] iOS 27+:胶囊由系统的液态玻璃画,这里**只出图标**,
		// 再烘焙一层自己的面板就是两层套娃(用户 2026-08-05 真机截图指出)。
		// 详见 `NNWSoftMaterial.systemDrawsBarCapsule`。
		if systemDrawsBarCapsule {
			return icon.withTintColor((tint ?? accent).resolvedColor(with: traits),
									  renderingMode: .alwaysOriginal)
		}

		let scale = traits.displayScale > 0
			? traits.displayScale
			: (UIScreen.main.scale > 0 ? UIScreen.main.scale : 3)

		return renderRoundButton(icon: icon, tint: tint, diameter: diameter,
								 traits: traits, scale: scale)
			.withRenderingMode(.alwaysOriginal)
	}

	@MainActor
	private static func renderRoundButton(icon: UIImage,
										  tint: UIColor?,
										  diameter: CGFloat,
										  traits: UITraitCollection,
										  scale: CGFloat) -> UIImage {

		// 阴影要画在图片里,所以四周留一点余量(否则会被画布边缘切掉)。
		//
		// ⚠️ **更正(2026-08-05)**:这里曾经写着"UIBarButtonItem 会把图片缩放到
		// 约 28–31pt",还据此把余量抠到 0.5 —— **那个结论是错的**。
		// 它是从一次错误测量推出来的:竖扫圆形量到的是**弦**不是直径(见 L109)。
		// 重测:直径给 44 就真的画出 **44.3pt** —— 图片是 **1:1 渲染,没有上限**。
		// 所以尺寸想给多大就给多大,余量也不必抠;这里留 2pt 够画阴影。
		let pad: CGFloat = 2
		let side = diameter + pad * 2
		let rect = CGRect(x: pad, y: pad, width: diameter, height: diameter)
		let colors = panelColors(for: traits)
		let accentColor = (tint ?? accent).resolvedColor(with: traits)

		let format = UIGraphicsImageRendererFormat()
		format.scale = scale
		format.opaque = false

		return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { context in

			let ctx = context.cgContext
			let circle = UIBezierPath(ovalIn: rect)

			// ① 阴影(先拿一次不透明填充把影子投出来,再用真正的渐变盖上去)
			// 余量只有 5pt,模糊半径按余量收一档,免得影子被画布边缘切出一条硬边
			ctx.saveGState()
			ctx.setShadow(offset: CGSize(width: 0, height: shadowOffsetY),
						  blur: pad * 2,
						  color: UIColor.black.withAlphaComponent(CGFloat(shadowOpacity(for: traits))).cgColor)
			colors.top.resolvedColor(with: traits).setFill()
			circle.fill()
			ctx.restoreGState()

			// ② 填充:由上向下变亮(和面板同一条规律)
			ctx.saveGState()
			circle.addClip()
			if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
										 colors: [colors.top.resolvedColor(with: traits).cgColor,
												  colors.bottom.resolvedColor(with: traits).cgColor] as CFArray,
										 locations: [0, 1]) {
				ctx.drawLinearGradient(gradient,
									   start: CGPoint(x: rect.midX, y: rect.minY),
									   end: CGPoint(x: rect.midX, y: rect.maxY),
									   options: [])
			}
			ctx.restoreGState()

			// ③ **整圈**亮边 —— 玻璃感全靠它,别省
			let rim = UIBezierPath(ovalIn: rect.insetBy(dx: rimWidth / 2, dy: rimWidth / 2))
			rim.lineWidth = rimWidth
			UIColor.white.withAlphaComponent(rimAlpha(for: traits)).setStroke()
			rim.stroke()

			// ④ 图标居中
			let iconSize = icon.size
			icon.withTintColor(accentColor, renderingMode: .alwaysOriginal)
				.draw(in: CGRect(x: rect.midX - iconSize.width / 2,
								 y: rect.midY - iconSize.height / 2,
								 width: iconSize.width, height: iconSize.height))
		}
	}

}

// MARK: - 把材质套到一个视图上

/// 一份「软面板」装饰:渐变填充 + 上缘 hairline + 极淡阴影。
///
/// 用法:宿主视图持有一个实例,`install(in:)` 一次,
/// 然后在自己的 `layoutSubviews` 里调 `layout(in:cornerRadius:)`。
///
/// ⚠️ 宿主**不能** `clipsToBounds = true` —— 会把阴影裁掉。
@MainActor final class NNWSoftPanel {

	enum Kind {
		/// dock 本体
		case panel
		/// 选中的那一格(比面板亮一档)
		case capsule
	}

	private let kind: Kind
	/// 半透明档:填充降到很低的不透明度,好让**垫在下面的磨砂**透上来。
	///
	/// 什么时候用:控件压在**图片**上时(首页头图上的搜索/编辑)。
	/// 不透明的面板压在照片上会变成一张"贴纸" —— 2026-08-04 实测过,很难看。
	/// 参考图里没有这个场景(它的底永远是纯色),所以这一档是**按本 app 的实际情况推导**的,
	/// 正是 L102 说的"搬相对关系,不搬绝对值"。
	private let isTranslucent: Bool
	private let fill = CAGradientLayer()
	private let rim = CAGradientLayer()
	private let rimMask = CAShapeLayer()
	/// 半透明档垫在最底下的那层真磨砂(不透明档为 nil)
	private var blurView: UIVisualEffectView?
	/// 用的是系统原生玻璃(true)还是退回的手搓模糊(false)。决定上面那层白压多少。
	private var usesNativeGlass = false

	init(kind: Kind, translucent: Bool = false) {
		self.kind = kind
		self.isTranslucent = translucent
	}

	func install(in view: UIView) {

		guard NNWSoftMaterial.isEnabled else { return }

		view.backgroundColor = .clear

		// [外观] 2026-08-05:半透明档在最底下垫一层**真磨砂**,让下面的内容透上来。
		//
		// ⚠️ 图层顺序是这里唯一的坑:`insertSublayer(at: 0)` 加的是**裸图层**,
		// 它永远排在**子视图**的图层下面 —— 磨砂是子视图,会把 fill / rim 整个盖住。
		// 解法:半透明档把 fill / rim 挂到**磨砂自己的 contentView** 上。
		// 于是顺序天然正确:磨砂(底) → fill → rim → 宿主原有的子视图(按钮、文字)。
		let host: UIView
		if isTranslucent {
			// [外观] 2026-08-05:**优先用系统原生的液态玻璃 `UIGlassEffect`**(iOS 26+)。
			//
			// ⚠️ 起因:用户在 **iOS 27 beta 真机**上报"底栏变成了遮罩,不是毛玻璃"。
			// 我的 SDK 与模拟器都是 26,**复现不了**(这个项目在 L94/L95 已经栽过同一件事)。
			// 所以不去"修"手搓的那套,而是**换成系统自己的机制**(L92 的老规矩):
			// 系统材质由系统负责在各版本上渲染正确,比我们拼「模糊 + 白层」稳得多。
			//
			// 配套:走原生玻璃时,上面那层白**必须大幅调低**(见 layout 里的 tint) ——
			// 原生玻璃本身就够亮,再压 52% 的白就正好变成用户说的那种"遮罩"。
			let effect: UIVisualEffect
			if #available(iOS 26, *) {
				let glass = UIGlassEffect(style: .regular)
				effect = glass
				usesNativeGlass = true
			} else {
				effect = UIBlurEffect(style: .systemUltraThinMaterial)
			}
			let blur = UIVisualEffectView(effect: effect)
			blur.isUserInteractionEnabled = false
			blur.layer.masksToBounds = true
			blur.layer.cornerCurve = .continuous
			view.insertSubview(blur, at: 0)
			blurView = blur
			host = blur.contentView
		} else {
			host = view
		}

		// ⚠️ **必须开 masksToBounds**:CAGradientLayer 的 cornerRadius 不开这个不裁切,
		// 渐变会画成一块**矩形**压在圆角胶囊上(2026-08-04 第一版那"一坨多余的框"就是它)。
		fill.masksToBounds = true
		fill.needsDisplayOnBoundsChange = true
		host.layer.insertSublayer(fill, at: 0)

		// 上缘高光:用一层「白→透明」的竖向渐变,再用描边形状把它裁成一圈线。
		// 直接用 CAShapeLayer 的 strokeColor 做不到"沿高度衰减"。
		rimMask.fillColor = UIColor.clear.cgColor
		rimMask.strokeColor = UIColor.black.cgColor
		rimMask.lineWidth = NNWSoftMaterial.rimWidth
		rim.mask = rimMask
		host.layer.insertSublayer(rim, above: fill)

		view.layer.shadowRadius = NNWSoftMaterial.shadowRadius
		view.layer.shadowOffset = CGSize(width: 0, height: NNWSoftMaterial.shadowOffsetY)
	}

	/// 尺寸/深浅色变化后重画。**在宿主的 layoutSubviews 里调**。
	func layout(in view: UIView, cornerRadius: CGFloat) {

		guard NNWSoftMaterial.isEnabled else { return }

		let bounds = view.bounds
		let traits = view.traitCollection

		// 磨砂跟着宿主走(它自己裁圆角 —— 宿主不能裁,裁了阴影就没了)
		blurView?.frame = bounds
		blurView?.layer.cornerRadius = cornerRadius

		// —— 填充:由上向下变亮 ——
		let colors = kind == .panel ? NNWSoftMaterial.panelColors(for: traits)
									: NNWSoftMaterial.capsuleColors(for: traits)
		// [外观] 2026-08-05 二版:半透明档在磨砂之上叠一层**白**,而不是叠一层"底色"。
		//
		// ⚠️ 为什么必须是白:磨砂玻璃压在**深色内容**上会跟着变灰 —— 实测三档控件
		// 从不透明版的 233 掉到 230,而且**随背后内容浮动**(参考图是恒定的 232)。
		// 用户的原话是「不够白不够亮」,量出来确实如此,而且是上一版改出来的。
		// 苹果自己的 `*Material` 也是这么干的:模糊之上再压一层浅色,
		// 让面板亮度**基本不受背后内容影响**,同时仍然透得出轮廓。
		//
		// 白的浓度是这里唯一的旋钮:调高 = 更白更亮但更不透,调低 = 更透但会跟着背景变灰。
		let top: UIColor, bottom: UIColor
		if isTranslucent {
			// ⚠️ **提亮层必须分深浅色**(2026-08-05,用户报"深色下这些按钮很丑")。
			// 上一版为了修"不够白不够亮"压了一层 52% 的白,**却没有分深浅色** ——
			// 深色下那层白照样生效,于是 dock、三档、圆钮全变成浅灰塑料板。
			// 深色下要的是反过来的东西:只补一点点白把玻璃"提"出暗底,不能把它刷白。
			// ⚠️ 走**原生玻璃**时这层白要压得很低:玻璃本身已经够亮,
			// 再盖 52% 的白就成了一块遮罩(用户 2026-08-05 在 iOS 27 真机上看到的正是这个)。
			// 退回手搓模糊时才需要那层白去提亮。
			let isDark = traits.userInterfaceStyle == .dark
			if usesNativeGlass {
				top = UIColor.white.withAlphaComponent(isDark ? 0.03 : 0.10)
				bottom = UIColor.white.withAlphaComponent(isDark ? 0.06 : 0.16)
			} else if isDark {
				top = UIColor.white.withAlphaComponent(0.10)
				bottom = UIColor.white.withAlphaComponent(0.16)
			} else {
				top = UIColor.white.withAlphaComponent(0.52)
				bottom = UIColor.white.withAlphaComponent(0.60)
			}
		} else {
			top = colors.top
			bottom = colors.bottom
		}
		fill.frame = bounds
		fill.cornerRadius = cornerRadius
		fill.cornerCurve = .continuous
		fill.colors = [top.cgColor, bottom.cgColor]

		// —— 亮边:**整圈**,几乎不衰减 ——
		// ⚠️ 2026-08-04 更正:原来写的是"上缘最亮、往下衰减到 3%",那是只扫了上缘得出的
		// 错误结论。重扫四条边:上/下/右 都是 #FFFFFF、左 #F6–#F9 —— 整圈都亮。
		// 这一圈就是"玻璃厚度"的全部来源,少了下半圈立刻变成贴纸(用户:"玻璃感不强")。
		// 保留一点点上强下弱(1.0 → 0.88),只为让光看着还是从上面来的。
		let peak = NNWSoftMaterial.rimAlpha(for: traits)
		rim.frame = bounds
		rim.colors = [UIColor.white.withAlphaComponent(peak).cgColor,
					  UIColor.white.withAlphaComponent(peak * 0.88).cgColor,
					  UIColor.white.withAlphaComponent(peak * 0.94).cgColor]
		rim.locations = [0, 0.55, 1]

		let inset = NNWSoftMaterial.rimWidth / 2
		rimMask.frame = bounds
		rimMask.path = UIBezierPath(roundedRect: bounds.insetBy(dx: inset, dy: inset),
									cornerRadius: cornerRadius).cgPath
		rimMask.lineWidth = NNWSoftMaterial.rimWidth

		// —— 阴影 ——
		view.layer.shadowColor = UIColor.black.cgColor
		view.layer.shadowOpacity = NNWSoftMaterial.shadowOpacity(for: traits)
		view.layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: cornerRadius).cgPath
	}
}

// MARK: - 拆套娃:让 iOS 26 别再给我们的控件套一层玻璃胶囊

extension UIBarButtonItem {

	/// [外观] 2026-08-04:关掉 iOS 26 自动套在这一项外面的「系统玻璃胶囊」。
	///
	/// ## 为什么必须拆(用户问「底栏中间那三个一定要后面有个阴影吗」的答案)
	///
	/// iOS 26 会给工具栏/导航栏的每一项自动垫一层 Glass 背景。我们的软面板画在**它里面**,
	/// 于是屏幕上是**两层胶囊**:系统那层一圈、我们这层一圈,中间那道缝是灰的,
	/// 两层的阴影还叠在一起。
	///
	/// 逐像素量过(iPhone 17,纸底 #F0EDE8 = 240):
	///
	/// | 控件正下方 | 最暗 | 比背景暗 |
	/// |---|---|---|
	/// | 齿轮(只有系统胶囊) | 233 | 7 级 |
	/// | 加号(只有系统胶囊) | 233 | 7 级 |
	/// | **三档(系统胶囊 + 我们的面板)** | **227** | **13 级** |
	///
	/// 而参考图里那条轨道贴边只暗 7–10 级。**所以问题不在阴影参数,在套娃** ——
	/// 拆掉外面那层,阴影立刻回到参考图的量级,那圈灰也一起没了。
	///
	/// ⚠️ 这是 iOS 26 的正规接口(`hidesSharedBackground`),不是 hack,
	/// 而且是**逐项**的属性 —— `toolbarItems` 数组一个字节都没动,
	/// `expectedItemCount == 3` 的守卫和 `addNewItemButton` 的 IBOutlet 都不受影响。
	///
	/// ## ⚠️ 2026-08-05:iOS 27 起**不能再拆**,拆了会把「内容从栏底下穿过去」一起弄丢
	///
	/// 用户在 iOS 27 真机上报「底栏没有那道柔和的渐隐,是硬切断」。
	/// 在真机上逐条件实测(app 自己截图采样、把数字打进日志)后定位到就是这一句:
	///
	/// | 条件 | 内容→底栏 交界处每行平均亮度 |
	/// |---|---|
	/// | 拆胶囊(原样) | 214 → **55 → 33**(4 个像素掉到底,硬切) |
	/// | **不拆胶囊** | 214 → **195 → 225**(内容一路穿到 dock 底下) |
	///
	/// **病根不是"渐隐丢了",是内容压根没滚到栏底下去** ——
	/// 栏底下没东西,自然没什么可渐隐的,同时那条不透明黑带就是用户之前说的「遮罩」。
	/// 一句话:iOS 27 上「共享背景」顺带管着"内容能不能从栏底下穿过去",拆掉就一起没了。
	/// (这正是 L114 那条判据的又一次:**"让某个系统外壳消失"时,
	///  先想清楚那层外壳还顺带提供了什么** —— 上一轮以为丢的是渐隐,其实丢的是可视区域。)
	///
	/// **两条已实测排除、别再走**:
	/// - `UIScrollView.bottomEdgeEffect`(style/isHidden):对 WKWebView **完全无效** ——
	///   反向强制关掉它,画面逐像素不变。
	/// - `UIScrollEdgeElementContainerInteraction`:挂上去了(有日志),画面**逐行完全不变**。
	///
	/// **为什么按版本分道,而不是干脆不拆**:iOS 26 上不拆就是两层胶囊套娃(已在 26 模拟器上
	/// 复现并截图确认);而 iOS 27 上不拆本来就只有一层,拆了反而坏事。**两个系统要的相反。**
	func nnwHideSystemGlassCapsule() {
		guard NNWSoftMaterial.isEnabled else { return }
		// iOS 27+:不拆。系统只画一层,拆了会连带弄丢"内容穿过栏底"。
		if ProcessInfo.processInfo.isOperatingSystemAtLeast(
			OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 0)) {
			return
		}
		if #available(iOS 26, *) {
			hidesSharedBackground = true
		}
	}
}

// MARK: - 补回"内容接近栏时的渐隐"

extension UIScrollView {

	/// [外观] 2026-08-05:把**底部边缘的渐隐**打开。
	///
	/// ## ⚠️⚠️ 2026-08-05 更正:**这个函数没有修好任何东西,原来的解释是错的**
	///
	/// 原注释说「为了让 dock 浮起来把工具栏拍平,那道渐隐是随着栏的底一起被拍掉的,
	/// 所以直接向滚动视图要回来」。这套因果**已在 iOS 26 模拟器和 iOS 27 真机上双双证伪**:
	///
	/// - **拍平不拍平根本无关**:iOS 27 真机上,拍平与不拍平两张截图**逐字节完全相同**。
	/// - **这个函数是空操作**:把它反过来、强制 `isHidden = true`(日志回读确认真的写进去了),
	///   画面**逐像素不变**。`bottomEdgeEffect` 对 WKWebView 根本不起作用。
	/// - `UIScrollEdgeElementContainerInteraction` 也试过(有日志确认挂上了),**逐行不变**。
	///
	/// **真正的病根是 `hidesSharedBackground`**(见上面 `nnwHideSystemGlassCapsule` 的注释):
	/// iOS 27 上拆掉共享背景,内容就不再从栏底下穿过去了 —— 栏底下没内容,自然没得渐隐。
	///
	/// ## 那为什么还留着这个函数
	///
	/// 上面的证伪是在**文章页的 WKWebView** 上做的。首页和文章列表页用的是普通
	/// `UICollectionView`,那上面 `bottomEdgeEffect` **有没有用没验过**,
	/// 所以不动它 —— 删一个没验过的东西,风险大于留着一个无害的调用。
	/// ⚠️ **但别再把它当成"渐隐的修法"** —— 它至少在正文页什么都没做。
	/// 清理与否见 NOTES-todo 的 T41。
	func nnwEnableSoftBottomEdgeFade() {
		guard NNWSoftMaterial.isEnabled else { return }
		if #available(iOS 26, *) {
			bottomEdgeEffect.style = .soft
			bottomEdgeEffect.isHidden = false
		}
	}
}

// MARK: - 让 dock 浮起来:把系统工具栏的底抹掉

extension UIViewController {

	private static var nnwSavedToolbarAppearanceKey: UInt8 = 0

	/// [外观] 进/出文章页时切换工具栏的底。
	///
	/// 参考图里的 dock 是**浮在页面上**的一颗胶囊,不是"装在一条栏里"。
	/// 系统工具栏自己会画一层底(iOS 26 上是玻璃),不抹掉的话就成了"胶囊套在栏里"的双层。
	///
	/// ⚠️ **原样存起来再改**:工具栏是整个导航栈共用的一条,
	/// 离开本页必须还原,否则别的页面(列表页的三档、首页的设置/+)会跟着一起变透明。
	func nnwUseFloatingToolbar(_ floating: Bool) {

		guard NNWSoftMaterial.isEnabled, let toolbar = navigationController?.toolbar else { return }

		if floating {
			// 第一次改之前,把原来的三份外观存下来
			if objc_getAssociatedObject(self, &Self.nnwSavedToolbarAppearanceKey) == nil {
				let saved: [UIToolbarAppearance?] = [toolbar.standardAppearance,
													 toolbar.compactAppearance,
													 toolbar.scrollEdgeAppearance]
				objc_setAssociatedObject(self, &Self.nnwSavedToolbarAppearanceKey, saved, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
			}
			let transparent = UIToolbarAppearance()
			transparent.configureWithTransparentBackground()
			toolbar.standardAppearance = transparent
			toolbar.compactAppearance = transparent
			toolbar.scrollEdgeAppearance = transparent
		} else {
			guard let saved = objc_getAssociatedObject(self, &Self.nnwSavedToolbarAppearanceKey) as? [UIToolbarAppearance?] else {
				return
			}
			toolbar.standardAppearance = saved[0] ?? UIToolbarAppearance()
			toolbar.compactAppearance = saved[1]
			toolbar.scrollEdgeAppearance = saved[2]
			objc_setAssociatedObject(self, &Self.nnwSavedToolbarAppearanceKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
		}
	}
}

#endif
