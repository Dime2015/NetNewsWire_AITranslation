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
	static var separatorColor: UIColor { .separator.withAlphaComponent(0.1) }
}
