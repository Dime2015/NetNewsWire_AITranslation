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

enum AppAppearance {

	// MARK: - 调色板(色号的唯一真源 —— 换色只改这一层的数字)

	private enum Palette {
		/// 暖纸背景。取色为命令行从用户提供的 Reeder / 深色截图取样(不是肉眼)。
		static let paperLight = rgb(0xF3F0EB)
		static let paperDark  = rgb(0x1E1E1E)

		// 之后随各页需要往这里加:inkPrimary(正文字色)、inkSecondary(次要文字)、
		// accent(强调色)…… 每条都写浅色/深色两个值。

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

	// MARK: - 工具

	/// 按当前浅 / 深色返回对应的颜色。系统切换深浅色时 UIKit 会自动重解析。
	private static func dynamic(light: UIColor, dark: UIColor) -> UIColor {
		UIColor { traits in traits.userInterfaceStyle == .dark ? dark : light }
	}
}

#endif
