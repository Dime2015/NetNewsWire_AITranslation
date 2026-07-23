//
//  TimelineStyle.swift
//  NetNewsWire-iOS
//
//  [界面] 本 fork 新增,上游没有这个文件。
//

import UIKit
import CoreText

/// 文章列表(时间线)的外观参数,集中一处。
///
/// **这是本 fork 唯一允许调整列表外观的地方。**
///
/// 为什么要有这个文件:列表的布局是上游用手写坐标算出来的,所有数字原本散落在
/// `MainTimelineCellLayout.swift` 和 `MainTimelineCell.swift` 这两个**上游文件**里。
/// 如果每次想调字号、调间距都直接去改那两个文件,上游一更新就会到处冲突。
/// 所以把这些数字搬到这里,上游文件里只留一行「引用 TimelineStyle.xxx」——
/// 它们的改动量永远停在几行,`git pull upstream` 时冲突好读、好解。
///
/// 本文件初次建立时,每个值都与上游原值**完全一致**,界面不应有任何变化。
/// 之后要调整外观,只改这里的数字,不要回头去动上游文件。
///
/// 相关约定见 CLAUDE.md 第 2 节「D 级 · 界面改造专用」。
enum TimelineStyle {

	// MARK: - 整条的内边距

	/// 每条文章四周留白。left 是最左侧(未读圆点之前)的留白,right 是右边缘留白。
	static let cellPadding = UIEdgeInsets(top: 12, left: 8, bottom: 12, right: 20)

	// MARK: - 左侧的未读圆点 / 星标

	/// 未读圆点左边额外的缩进(在 cellPadding.left 之外再加)。
	static let unreadCircleMarginLeft = CGFloat(0)
	/// 未读圆点的直径。
	static let unreadCircleDimension = CGFloat(12)
	/// 未读圆点右边到下一个元素(图标或文字)的距离。
	static let unreadCircleMarginRight = CGFloat(8)
	/// 未读圆点相对该行文字顶部的垂直下移量。
	static let unreadCircleTopOffset = CGFloat(5)

	/// 星标图形的边长(星标与未读圆点占同一位置,二选一显示)。
	static let starDimension = CGFloat(16)
	/// 星标相对该行文字顶部的垂直下移量。
	static let starTopOffset = CGFloat(3)

	// MARK: - 订阅源图标

	/// 图标右边到标题文字的距离。
	static let iconMarginRight = CGFloat(8)
	/// 图标相对该行文字顶部的垂直下移量。
	static let iconTopOffset = CGFloat(4)

	// MARK: - 字体
	//
	// 这些用的都是系统的「动态字体」样式,会跟随 iOS 设置里的字号大小自动缩放。
	// 想整体调大调小,可以换成别的 textStyle(例如 .title3 比 .headline 大),
	// 或者用 UIFont.systemFont(ofSize:weight:) 写死一个字号(但那样就不跟随系统了)。

	/// 标题字体。
	static var titleFont: UIFont { UIFont.preferredFont(forTextStyle: .headline) }
	/// 摘要字体。
	static var summaryFont: UIFont { UIFont.preferredFont(forTextStyle: .body) }
	/// 订阅源名 / 作者名字体。
	static var feedNameFont: UIFont { UIFont.preferredFont(forTextStyle: .footnote) }
	/// 日期字体。
	static var dateFont: UIFont { UIFont.preferredFont(forTextStyle: .footnote) }

	// MARK: - 元素之间的间距

	/// 标题底部到摘要之间的距离。
	static let titleBottomMargin = CGFloat(1)
	/// 订阅源名右边到日期之间的最小距离。
	static let feedRightMargin = CGFloat(8)

	// MARK: - 颜色

	/// 标题颜色。
	static var titleColor: UIColor { .label }
	/// 摘要颜色(文章没有标题时,摘要会顶上来当标题用,那时用 `summaryColorWhenNoTitle`)。
	static var summaryColor: UIColor { .secondaryLabel }
	/// 文章没有标题时,摘要的颜色。
	static var summaryColorWhenNoTitle: UIColor { .label }
	/// 日期颜色。
	static var dateColor: UIColor { .secondaryLabel }
	/// 订阅源名 / 作者名颜色。
	static var feedNameColor: UIColor { .secondaryLabel }
	/// 条与条之间那条细分隔线的颜色。
	/// [外观] 做成无边界暖纸风格:分隔线设为透明(整片无分隔)。
	/// 想恢复分隔线,把这里改回 `.separator.withAlphaComponent(0.1)` 即可(只改这一个值)。
	static var separatorColor: UIColor { .clear }

	// MARK: - ↓↓↓ 以下是 2026-07-21 改成 Reeder 式布局后新增的 ↓↓↓
	//
	// 新的一行长这样:
	//
	//   [favicon] [ 源名 ……………………… 时间 ★ ]  [缩略图]
	//             [ 标题(粗,最多 3 行)      ]
	//             [ 正文(补足到共 4 行)      ]
	//
	// 上面那批老常量里,有几个新布局已经不用了(unreadCircle*、star* 那几个),
	// 但**没有删** —— 上游文件里还引用着它们,删了要动上游更多地方。

	// MARK: 行数规则

	/// 标题 + 正文加起来最多显示几行。
	static let totalTextLines = 4
	/// 标题最多占几行(剩下的给正文,正文至少 1 行)。
	static let maxTitleLines = 3
	/// 正文最少显示几行。
	static let minSummaryLines = 1

	// MARK: favicon(每行最左边那个小图标)

	/// favicon 边长。上游默认是 36(medium),新布局要"缩小"。
	static let faviconDimension = CGFloat(24)
	/// favicon 圆角。
	static let faviconCornerRadius = CGFloat(5)
	/// favicon 右边到文字区的距离。
	static let faviconMarginRight = CGFloat(10)
	/// favicon 相对整行顶部的垂直微调(与顶行文字对齐)。
	static let faviconTopOffset = CGFloat(0)

	// MARK: 缩略图(每行最右边)

	/// 缩略图边长(正方形)。**没有图时这块宽度按 0 算,文字自动铺满。**
	static let thumbnailDimension = CGFloat(72)
	/// 缩略图圆角。
	static let thumbnailCornerRadius = CGFloat(8)
	/// 缩略图左边到文字区的距离。
	static let thumbnailMarginLeft = CGFloat(10)

	// MARK: 三段文字

	/// 顶行:订阅源名。
	static var feedLineFont: UIFont { UIFont.preferredFont(forTextStyle: .caption1) }
	/// 顶行:时间。
	static var timeFont: UIFont { UIFont.preferredFont(forTextStyle: .caption1) }
	/// 标题(加粗)。
	static var headlineFont: UIFont {
		let base = UIFont.preferredFont(forTextStyle: .subheadline)
		let descriptor = base.fontDescriptor.withSymbolicTraits(.traitBold) ?? base.fontDescriptor
		return UIFont(descriptor: descriptor, size: 0)
	}
	/// 正文摘要。
	static var bodyFont: UIFont { UIFont.preferredFont(forTextStyle: .subheadline) }

	/// 顶行底部到标题的距离。
	static let feedLineBottomMargin = CGFloat(3)
	/// 标题底部到正文的距离。
	static let headlineBottomMargin = CGFloat(2)
	/// 时间左边至少留这么多空,免得和很长的源名贴在一起。
	static let timeMarginLeft = CGFloat(8)

	// MARK: 颜色(新布局)

	/// 顶行源名的颜色。
	static var feedLineColor: UIColor { .secondaryLabel }
	/// 时间的颜色。
	static var timeColor: UIColor { .secondaryLabel }
	/// 标题颜色。
	static var headlineColor: UIColor { .label }
	/// 正文摘要颜色。
	static var bodyColor: UIColor { .secondaryLabel }

	// MARK: 已读 / 未读

	// 用户 2026-07-21 确认:**去掉未读小圆点**,改用整行浓淡区分。
	// 浓 = 未读,淡 = 已读。

	/// 未读文章整行的不透明度。
	static let unreadAlpha = CGFloat(1.0)
	/// 已读文章整行的不透明度。调这个值就能改"已读有多淡"。
	static let readAlpha = CGFloat(0.45)

	// MARK: 星标

	/// 星标图形边长(显示在顶行时间的右边)。
	static let starDimensionInFeedLine = CGFloat(13)
	/// 星标与时间之间的距离。
	static let starMarginLeft = CGFloat(4)

	// MARK: 单源页顶部头图区(见 TimelineFeedHeader.swift)

	// 2026-07-22 v3(v1 水印"太浅太糊"、v2 小 logo"挺丑"都被用户否掉):
	// 图铺满全宽、越往上越浓越往下越淡、整体压纸色蒙版防撞色、标题在最下方最淡处。
	// 抓不到合格大图的源,用 favicon 主色做同样形状的纯色渐变,观感与有图的源一致。
	// **调头图样式只改这一段的数字**。

	/// 总开关。回退时改成 false 即可,一行都不用删。
	static let headerEnabled = true

	/// 三个智能源(今天 / 全部未读 / 已加星标)要不要也有头图。
	/// 关掉它,那三页就回到上游原样(系统大标题、没有头图),订阅源页不受影响。
	static let smartHeaderEnabled = true

	/// 智能源头图的蒙版强度。**故意比订阅源的 0.55 高。**
	///
	/// 理由:订阅源那张图是**抓来的**,什么颜色都可能有,压狠一点是为了防撞色;
	/// 而这三张是**手工挑好、还专门做过白平衡与统一曝光的画**
	/// (见 tools/make-header-assets.swift),压到 0.55 等于白挑。
	/// 嫌太抢眼往下调,嫌太寡淡往上调,1.0 是原色直上。
	static let smartHeaderImageStrength = CGFloat(0.80)
	/// 头图区高度 = 屏高 × 此值(用户点名"约四分之一")。
	static let headerHeightFraction = CGFloat(0.25)

	/// 图/主色的整体强度 = 「蒙版」。1 = 原色直上,越小越被纸色拉回来、越不容易撞色。
	/// 这是**最值得先调的一个值**:嫌太抢眼调小,嫌太寡淡调大。
	static let headerImageStrength = CGFloat(0.55)
	/// 从这个高度比例开始往下淡出(到底边完全消失)。越小 = 淡出得越早、渐变越长。
	static let headerImageFadeStart = CGFloat(0.18)
	/// 柔化程度:先把图缩到这么多像素宽再放大(越小越糊)。
	/// ⚠️ 只在「素材不够大、被拉伸过头」时才用(见下一条),够大的图**一点都不糊**。
	/// 180 是很轻的柔化,只为掩盖放大锯齿;想更糊调小,想全清晰把下一条调到很大。
	static let headerImageDownsampleWidth = CGFloat(180)
	/// 放大倍数超过这个值才启用柔化。素材像素 × 此值 ≥ 屏宽像素时,保持完全清晰。
	/// 举例:iPhone 屏宽约 1179px,此值 4.0 → 素材 ≥295px 就完全不糊
	/// (Daring Fireball 官方最大 314px,正好落在清晰这一侧)。
	/// 用户 2026-07-22 的诉求是「别糊」,所以这个值定得比较宽松;
	/// 若觉得小素材放大后锯齿明显,调小到 3.0 会让更多源走轻柔化。
	static let headerBlurAboveUpscale = CGFloat(4.0)

	/// 标题**基线**距离头图区底边(渐变消失的那条分界线)的距离(pt)。
	/// 2026-07-22 用户要求「标题往下一点,站在渐变色消失的分界线上」——
	/// 所以用基线定位而不是方框底边:方框底边下面还有一截空的下伸部空间,
	/// 按方框对齐会看起来浮在线上方。**0 = 字正好站在线上**(下伸部略越线,有意为之);
	/// 想抬高就给正值。
	static let headerTitleBaselineInset = CGFloat(0)

	/// 标题字号(pt)。
	/// 2026-07-22 用户反馈「字号大了,缩小一些会更高级」——
	/// 从系统 largeTitle(34pt)降到 27pt。头图区是"身份带"不是页面大标题,
	/// 小一点反而更笃定。
	static let headerTitleFontSize = CGFloat(27)
	/// 标题是否用衬线体(苹果自带的 New York)。
	/// 用衬线的理由:本 app 是暖纸阅读风,衬线更像报头/杂志刊名,
	/// 而且和下面文章标题的无衬线体拉开层次,辨识度更高。
	/// ⚠️ New York **没有中文字形**,中文源名(如「硅谷101」)会自动回退到苹方,
	/// 中英混排的源名会出现两种字体 —— 若觉得别扭,把这里改成 false。
	static let headerTitleUsesSerif = true

	/// 中文标题是否也用衬线体(打包进来的思源宋体)。
	/// 改成 false 就立刻回到苹方黑体,字体文件仍在包里但不会被用到。
	static let headerTitleUsesCJKSerif = true

	/// 打包的中文衬线体的 PostScript 名。
	/// **必须和 `iOS/Fonts/` 里那个文件内部的名字一致**,改字体时一起改(见该目录的 README-vendor.md)。
	private static let bundledCJKSerifName = "NotoSerifCJKsc-Bold"

	/// 标题字体。**要传入实际显示的文字** —— 中文和西文用的是两种字体,
	/// 得看内容才知道该给哪个。
	///
	/// ## ⚠️ 中文衬线是**打包进来的**,iOS 自己一个都没有(2026-07-23 实测)
	///
	/// 我一度写了「中文用宋体(STSongti-SC-Bold)」,毫无效果 ——
	/// **宋体是 macOS 才有的字体**。在 app 里向系统要过一次完整名单:
	/// iOS 26.5 上认识简体字的**只有苹方(PingFang)的四个地区版 × 六个字重,
	/// 全是黑体,一个衬线都没有**。
	///
	/// 试过、都不行的路(**别再重试**,详见 NOTES-lessons L70):
	/// - `STSongti-SC-Bold` / `Songti SC` —— iOS 没有,`UIFont(name:)` 返回 nil,静默回退
	/// - 日文明朝体 `HiraMinProN-W6` —— iOS 确实带,但**缺简体专用字**
	///   (实测「读」「标」「观」「严」「肃」「长」都没有),用了会一个标题里半衬线半黑体
	/// - `withDesign(.serif)` —— 只影响西文(得到 New York),对汉字无效
	///
	/// 所以最后打包了思源宋体的子集(2.1MB,见 `iOS/Fonts/README-vendor.md`)。
	@MainActor static func headerTitleFont(for text: String) -> UIFont {

		let base = UIFont.systemFont(ofSize: headerTitleFontSize, weight: .bold)

		// —— 中文:用打包的思源宋体 ——
		if headerTitleUsesCJKSerif, text.nnwContainsCJK {
			nnwRegisterBundledSerifIfNeeded()
			if let serif = UIFont(name: bundledCJKSerifName, size: headerTitleFontSize),
			   nnwFont(serif, covers: text) {
				return serif
			}
			// ⚠️ **缺字就整条退回黑体**,而不是让系统逐字回退。
			// 打包的是子集(GB2312 全集 6763 字),订阅源名却是任意的 ——
			// 逐字回退会出现"一个标题里半衬线半黑体",那比统一黑体难看得多。
			return base
		}

		// —— 西文:苹果自带的 New York ——
		guard headerTitleUsesSerif,
			  let descriptor = base.fontDescriptor.withDesign(.serif) else {
			return base
		}
		return UIFont(descriptor: descriptor, size: headerTitleFontSize)
	}

	/// 把打包的字体注册给系统(只做一次)。
	///
	/// **故意不走 `Info.plist` 的 `UIAppFonts`** —— 那是上游文件,
	/// 加一条就多一个 merge 冲突点。运行时注册的效果完全一样。
	@MainActor private static var bundledSerifRegistered = false

	@MainActor private static func nnwRegisterBundledSerifIfNeeded() {
		guard !bundledSerifRegistered else { return }
		bundledSerifRegistered = true		// 不管成没成都只试一次,免得每次画标题都重来

		guard let url = Bundle.main.url(forResource: "NotoSerifCJKsc-Bold-subset", withExtension: "otf") else {
			print("[头图] 打包的中文衬线体没找到 —— 中文标题会用黑体")
			return
		}
		var error: Unmanaged<CFError>?
		if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
			// 已经注册过会报错,那不算问题;其余情况记一笔,免得又变成静默回退(L70)
			print("[头图] 中文衬线体注册未成功:\(error?.takeUnretainedValue().localizedDescription ?? "未知")")
		}
	}

	/// 这个字体认不认得全这段文字里的每一个字。
	private static func nnwFont(_ font: UIFont, covers text: String) -> Bool {
		let ctFont = font as CTFont
		for scalar in text.unicodeScalars {
			var utf16 = Array(String(scalar).utf16)
			var glyphs = [CGGlyph](repeating: 0, count: utf16.count)
			guard CTFontGetGlyphsForCharacters(ctFont, &utf16, &glyphs, utf16.count),
				  !glyphs.contains(0) else { return false }
		}
		return true
	}

	/// 标题的水平对齐。**改这一个值就能切换左 / 居中 / 右**,方便对比着挑。
	/// 用户 2026-07-22 选了靠右(觉得更高级)。
	static let headerTitleAlignment: NSTextAlignment = .right
	/// 标题左右两侧的留白(pt)。
	/// 取 20 是**有意和文章行的右边距(cellPadding.right)一致** ——
	/// 这样右对齐时标题的右缘和每行的日期、缩略图排在同一条线上,
	/// 读起来像"有意对齐",而不是"飘到右边去了"。
	static let headerTitleSideMargin = CGFloat(20)

	/// 标题的着色强度:**0 = 纯黑/纯白(完全不着色),1 = 完全用主题色**。
	///
	/// 2026-07-22 调整:初版给了 0.35,用户看完的反馈是「还是黑色的,亮色下的还没做是吗」——
	/// 说明太含蓄了,等于没做。现在给 0.7:颜色明显看得出来,又不到刺眼的地步。
	/// (同轮还修了更根本的问题:原来在 RGB 里混黑白会把饱和度冲掉,
	///  墨绿被洗成灰 —— 现已改为在 HSB 里只调明度,见 readableTitleColor。)
	static let headerTitleTintStrength = CGFloat(0.7)
	/// 标题与背景的最低对比度(WCAG 比值)。大号粗体 3:1 是底线,4.5:1 更舒服。
	/// 达不到时会自动把颜色往黑(浅色模式)或往白(深色模式)压,直到达标。
	static let headerTitleMinContrast = CGFloat(4.5)

	/// 往下滚多少点,头图完全淡出、标题飞到导航栏停靠。
	static let headerScrollFadeDistance = CGFloat(140)
	/// 停靠在导航栏时的字号(pt)。标题一路从 headerTitleFontSize 线性缩到这个大小。
	static let headerDockedTitleFontSize = CGFloat(17)
	// MARK: 停靠时导航栏那条毛玻璃底
	//
	// 必须有底 —— 否则文章正文会直接从标题背后穿过去,字叠字(2026-07-22 用户截图证实)。
	// 但底又不能太厚,否则整条看起来像块挡板(2026-07-23 用户反馈"毛玻璃太厚")。
	// 下面三个值就是调这个平衡的,**调顶栏观感只改这里**。

	/// 毛玻璃**浓度**上限(0=完全没有,1=该材质的完整强度)。**嫌厚就往下调,嫌糊不住字就往上调。**
	///
	/// ⚠️ 这是"浓度"不是"不透明度",两者不是一回事(2026-07-23 改)。
	/// 以前用的是 `scrimView.alpha`,苹果明确说毛玻璃视图的 alpha 小于 1 会让模糊失真 ——
	/// 而且那样调出来的"薄"是**清晰内容和模糊内容叠加**的重影,不是真的薄。
	/// 现在改由 `UIViewPropertyAnimator` 驱动 effect 本身,停在任意档位都是
	/// **系统插值出来的真毛玻璃**(模糊半径和着色一起按比例减弱),alpha 全程保持 1。
	static let headerDockedScrimStrength = CGFloat(0.7)
	/// 毛玻璃在滚动进度的哪一段开始出现(0~1)。留到后半段才现,免得刚一动就压上一片。
	static let headerDockedScrimFadeStart = CGFloat(0.45)
	/// 底边**羽化**高度(pt):毛玻璃在导航栏下沿往下这么多点里渐渐散掉,不留硬边。
	/// 目的是让顶栏看起来像"一层薄雾浮在内容上",而不是"一条切齐的带子"。
	/// 这段羽化在导航栏**下方**,不会削弱标题底下的那块,所以不影响标题可读性。
	static let headerDockedScrimFeather = CGFloat(24)
	/// 毛玻璃材质。ultraThin 是系统里最透的一档;想更实就换 .systemThinMaterial。
	static let headerDockedScrimMaterial = UIBlurEffect.Style.systemUltraThinMaterial

	/// 素材要有这么多像素(最长边)才够格当整片大图,否则走主色渐变。
	/// 主色渐变至少要和纸色差出这么多对比度,否则那片渐变等于不存在。
	/// Six Colors 的主色是近白的 #E6E6E6,不加这条头图会直接"消失"(2026-07-22 实测)。
	/// 只要"看得见"即可,不必像标题那样"读得清",所以定得低。
	static let headerMinGradientContrast = CGFloat(1.5)
	static let headerMinHeroPixels = CGFloat(180)
	/// 抓图时的"够好就收工"门槛:拿到这么大就不再试剩下的候选地址。
	/// 低于它会把所有候选试一遍,挑最大的一张(实测很多站的 iconURL 是 32px 缩略图,
	/// 而去掉尺寸后缀的同一张图有 512px)。
	static let headerPreferredHeroPixels = CGFloat(512)
	/// 候选图的最大宽高比:超过就判定"不是身份图"(多半是文章横幅),打三折参与比较。
	/// 封面 / 头像 / logo 几乎都是正方形,所以 1.35 已经很宽松。
	static let headerMaxHeroAspect = CGFloat(1.35)
	/// 非白像素还要占到这个比例才够格当大图 —— 挡掉白底 logo
	/// (白底图拉满全宽 = 顶部一片白,比没有图还难看;它们走主色渐变反而好看)。
	static let headerMinCoverage = CGFloat(0.35)
}

extension String {

	/// 这段文字里有没有汉字。
	///
	/// 只看**汉字区**(不看假名、标点):判据是"New York 缺不缺这些字",而它缺的正是汉字。
	/// 中英混排(如「硅谷101」)也算 —— 混排时以汉字为主,整条用宋体
	/// 才不会一行里出现两种衬线。
	var nnwContainsCJK: Bool {
		unicodeScalars.contains { scalar in
			(0x4E00...0x9FFF).contains(scalar.value)			// 基本汉字
				|| (0x3400...0x4DBF).contains(scalar.value)	// 扩展 A
				|| (0xF900...0xFAFF).contains(scalar.value)	// 兼容汉字
		}
	}
}
