//
//  AppAppearance.swift
//  NetNewsWire — AI 翻译 fork
//
//  [外观] 本 fork 新增,上游没有这个文件。
//
//  全 app 原生界面(UIKit)的「外观中心 / 调色板」。
//
//  为什么要有这个文件:NetNewsWire 的颜色**没有统一来源**,散落在各个
//  view controller / cell / storyboard 里(有的写 .systemGroupedBackground、
//  有的干脆不设走系统白)。想成体系地换配色,必须先有一个集中的来源,
//  再让各处指到这里(和 TimelineStyle.swift 是同一个思路)。
//
//  ## 结构(两层)—— 目标:换色只动一个地方
//
//  1. `Palette`(调色板层,色号的**唯一真源**):每个颜色的浅色/深色**原始色值**都在这里。
//     想整体换个色系,只改这一层的几个 0xRRGGBB 数字。
//  2. 语义色层(`paperBackground` 等):界面代码只认语义名,不直接碰色号。
//     想单独调某种语义色,改这一层一行。
//
//  以后各页需要新颜色(正文字色、次要文字、强调色…),就往这两层各加一条,
//  边做边长,不空建一个用不上的大调色板。
//
//  注意:文章正文阅读页是 WKWebView,背景由主题 CSS / nnw_appearance.js 管,
//  不在这里,是另一条杆。
//
//  ⚠️ 别用全局 UINavigationBarAppearance 去铺色 —— 会把大标题和 iOS 26 副标题
//  一起冲掉(见 NOTES-lessons L45)。正路:各列表设自己的 config.backgroundColor
//  (见 L44),导航栏保持系统默认透明,自然透出下面已变暖的背景。
//

#if os(iOS)

import UIKit
import SwiftUI

enum AppAppearance {

	// MARK: - 调色板(色号的唯一真源 —— 换色只改这一层的数字)

	private enum Palette {
		/// 暖纸背景。取色为命令行从用户提供的 Reeder / 深色截图取样(不是肉眼)。
		static let paperLight = rgb(0xF3F0EB)
		static let paperDark  = rgb(0x1E1E1E)

		/// 选中高亮(淡暖色):比纸略深/浅一档,给点按反馈又不抢眼。
		static let selectionLight = rgb(0xE8E3DB)
		static let selectionDark  = rgb(0x2E2C28)

		// ⚠️ 强调色(陶土红)**不在这里** —— 它的真源是
		// `iOS/Resources/Assets.xcassets/primaryAccentColor.colorset`(+ secondaryAccentColor)。
		// 原因:5 个 storyboard 按名字直接引这个 colorset,storyboard 读不了代码里的颜色,
		// 所以强调色只能放 colorset 里才能"一处改、全 app(含 storyboard)一起变"。
		// 想调强调色的深浅,改那个 colorset 的 RGB。
		//
		// 之后随各页需要往这里加:inkPrimary(正文字色)、inkSecondary(次要文字)…… 每条写浅+深。

		/// 0xRRGGBB → 不透明 UIColor。
		static func rgb(_ value: UInt32) -> UIColor {
			UIColor(red:   CGFloat((value >> 16) & 0xFF) / 255.0,
					green: CGFloat((value >> 8) & 0xFF) / 255.0,
					blue:  CGFloat(value & 0xFF) / 255.0,
					alpha: 1)
		}
	}

	// MARK: - 语义色(界面代码用这些,不直接碰色号)

	/// 暖色纸张背景,自动跟随系统浅色 / 深色。
	static let paperBackground = dynamic(light: Palette.paperLight, dark: Palette.paperDark)

	/// 表格 cell 选中时的淡暖色高亮(取代系统蓝)。
	static let selectionHighlight = dynamic(light: Palette.selectionLight, dark: Palette.selectionDark)

	// MARK: - 复用:把「分组表格」类页面(设置等)刷成暖纸风

	/// 把一个 UITableView(设置这类 insetGrouped 分组表格)刷成暖纸底、无分隔线。
	/// ⚠️ cell 的卡片底色要在各 VC 的 `willDisplay` 里配合调 `applyPaperStyle(to: cell)` ——
	/// 表格没有"统一设每个 cell 背景"的入口,只能逐 cell 来。
	@MainActor
	static func applyPaperStyle(to tableView: UITableView) {
		tableView.backgroundColor = paperBackground
		tableView.separatorStyle = .none
	}

	/// 把一个 cell 刷成暖纸风:卡片底色 = 暖纸色 + 统一的"药丸"选中高亮(在 `willDisplay` 里调)。
	/// 普通 UITableViewCell 默认没有药丸高亮,这里一并补上;VibrantTableViewCell 已自带同样的,
	/// 被这里覆盖成一模一样的,无害。
	@MainActor
	static func applyPaperStyle(to cell: UITableViewCell) {
		cell.backgroundColor = paperBackground
		cell.selectedBackgroundView = makePillSelectionBackgroundView()
	}

	// MARK: - 工具

	/// 按当前浅 / 深色返回对应的颜色。系统切换深浅色时 UIKit 会自动重解析。
	private static func dynamic(light: UIColor, dark: UIColor) -> UIColor {
		UIColor { traits in traits.userInterfaceStyle == .dark ? dark : light }
	}

	/// 造一个"药丸高亮"选中视图(见 PillSelectionBackgroundView)。
	/// 给 UITableViewCell 当 selectedBackgroundView 用。
	@MainActor
	static func makePillSelectionBackgroundView() -> UIView {
		PillSelectionBackgroundView()
	}
}

// MARK: - SwiftUI 侧(信息页那批是 SwiftUI,不是 UIKit 表格)

extension AppAppearance {
	/// 暖纸背景的 SwiftUI 版。
	static var paperBackgroundColor: Color { Color(uiColor: paperBackground) }
}

extension View {

	/// [外观] 给 SwiftUI 页(VStack / ScrollView 这类)铺暖纸底(铺满整屏,含安全区外)。
	func nnwPaperBackground() -> some View {
		background(AppAppearance.paperBackgroundColor.ignoresSafeArea())
	}

	/// [外观] 给 SwiftUI List 铺暖纸底 + 隐藏系统灰底。
	/// ⚠️ 行/Section 还要各自加 `.nnwPaperRow()`,否则行仍是白卡片浮在暖底上。
	func nnwPaperList() -> some View {
		scrollContentBackground(.hidden)
			.background(AppAppearance.paperBackgroundColor.ignoresSafeArea())
	}

	/// [外观] 把 List 里的行 / Section 刷成暖纸底 + 去掉分隔线(配合 nnwPaperList 用)。
	func nnwPaperRow() -> some View {
		listRowBackground(AppAppearance.paperBackgroundColor)
			.listRowSeparator(.hidden)
	}
}

/// [外观] "药丸"选中高亮:统一四角圆角 + 略微内缩的暖色块。
///
/// 用来取代 iOS `insetGrouped` 那种"首行顶部圆角、末行底部圆角、中间不圆、还随位置变"
/// 的选中形状 —— 那个形状在颜色统一后一点按就冒出来,显得割裂、突兀。
/// 这里改成:**不管第几行,都高亮成同一个四角一致的小圆角块**,像现代菜单项。
///
/// 做法:自己背景透明,里面放一个内缩的圆角块。因为圆角块严格缩在 cell 卡片内部、
/// 碰不到卡片边缘,所以不受 insetGrouped 卡片圆角遮罩的影响,四角圆角总是完整、一致。
final class PillSelectionBackgroundView: UIView {

	// 可调项(想调高亮的圆角 / 内缩,改这三个值即可,一处改全 app 一致)。
	private static let horizontalInset: CGFloat = 6
	private static let verticalInset: CGFloat = 4
	private static let cornerRadius: CGFloat = 10

	private let pill = UIView()

	override init(frame: CGRect) {
		super.init(frame: frame)
		setUp()
	}

	required init?(coder: NSCoder) {
		super.init(coder: coder)
		setUp()
	}

	private func setUp() {
		backgroundColor = .clear
		pill.backgroundColor = AppAppearance.selectionHighlight
		pill.layer.cornerRadius = Self.cornerRadius
		pill.layer.cornerCurve = .continuous
		addSubview(pill)
	}

	override func layoutSubviews() {
		super.layoutSubviews()
		pill.frame = bounds.insetBy(dx: Self.horizontalInset, dy: Self.verticalInset)
	}
}

#endif
