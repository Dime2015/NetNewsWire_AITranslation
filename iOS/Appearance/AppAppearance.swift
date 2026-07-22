//
//  AppAppearance.swift
//  NetNewsWire — AI 翻译 fork
//
//  [外观] 本 fork 新增,上游没有这个文件。
//
//  全 app 原生界面(UIKit)的「外观中心」。第一步只有一个东西:暖色纸张背景。
//
//  为什么要有这个文件:NetNewsWire 的背景色**没有统一来源**,散落在各个
//  view controller / cell / storyboard 里(有的写 .systemGroupedBackground、
//  有的干脆不设走系统白)。想把整个 app 换成暖色,必须先有一个集中的颜色,
//  再让各处指到这里 —— 这样以后调色、加「Reeder 风格 / 原版」可切换开关,
//  都只改这一个文件,不会散得到处都是(和 TimelineStyle.swift 是同一个思路)。
//
//  注意:文章正文阅读页是 WKWebView,背景由主题 CSS / nnw_appearance.js 管,
//  不在这里,是另一条杆。
//

#if os(iOS)

import UIKit

enum AppAppearance {

	/// 暖色纸张背景,自动跟随系统浅色 / 深色。
	///
	/// 取色来源(命令行从用户提供的截图取样,不是肉眼猜):
	///   - 浅色 #F3F0EB —— Reeder 订阅列表截图的纸张底色(更暖那一档)
	///   - 深色 #1E1E1E —— 用户提供的「订阅列表_深色」截图
	///
	/// 想调整暖度只改这两行。用动态 UIColor,系统切换深浅色时自动跟随。
	static let paperBackground = UIColor { traits in
		traits.userInterfaceStyle == .dark
			? UIColor(red: 30.0 / 255.0, green: 30.0 / 255.0, blue: 30.0 / 255.0, alpha: 1)      // #1E1E1E
			: UIColor(red: 243.0 / 255.0, green: 240.0 / 255.0, blue: 235.0 / 255.0, alpha: 1)   // #F3F0EB
	}

	// 说明:曾经用全局 UINavigationBarAppearance 把导航栏铺成暖底,但那样会
	// 用 configureWithOpaqueBackground() 重置大标题和 iOS 26 的 subtitle(副标题),
	// 导致「Feed」标题和「刚刚更新」副标题消失。已改回正路:
	// 导航栏保持系统默认(大标题态是透明的),下面各列表把自己的 config.backgroundColor
	// 设成暖纸色 —— 透明导航栏就会透出暖背景,标题/副标题也原样保留。
}

#endif
