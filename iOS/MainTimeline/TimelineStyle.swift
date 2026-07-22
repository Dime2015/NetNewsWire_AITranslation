//
//  TimelineStyle.swift
//  NetNewsWire-iOS
//
//  [界面] 本 fork 新增,上游没有这个文件。
//

import UIKit

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
	/// 头图区高度 = 屏高 × 此值(用户点名"约四分之一")。
	static let headerHeightFraction = CGFloat(0.25)

	/// 图/主色的整体强度 = 「蒙版」。1 = 原色直上,越小越被纸色拉回来、越不容易撞色。
	/// 这是**最值得先调的一个值**:嫌太抢眼调小,嫌太寡淡调大。
	static let headerImageStrength = CGFloat(0.55)
	/// 从这个高度比例开始往下淡出(到底边完全消失)。越小 = 淡出得越早、渐变越长。
	static let headerImageFadeStart = CGFloat(0.18)
	/// 模糊程度:先把图缩到这么多像素宽再放大(越小越糊)。
	/// 40 左右能看出形和色但不刺眼;想看清图案就调大到 120+。
	static let headerImageDownsampleWidth = CGFloat(40)

	/// 标题底边距离头图区底边的距离(pt)。
	static let headerTitleBottomInset = CGFloat(14)

	/// 往下滚多少点,头图完全淡出、导航栏小标题接棒。
	static let headerScrollFadeDistance = CGFloat(140)

	/// 素材要有这么多像素(最长边)才够格当整片大图,否则走主色渐变。
	static let headerMinHeroPixels = CGFloat(180)
	/// 非白像素还要占到这个比例才够格当大图 —— 挡掉白底 logo
	/// (白底图拉满全宽 = 顶部一片白,比没有图还难看;它们走主色渐变反而好看)。
	static let headerMinCoverage = CGFloat(0.35)
}
