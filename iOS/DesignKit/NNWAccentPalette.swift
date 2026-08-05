//
//  NNWAccentPalette.swift
//  NetNewsWire — AI 翻译 fork
//
//  [外观] 本 fork 新增。**全 app 强调色的唯一出处**,可在设置里一键换。
//
//  ## 为什么要有这个文件
//
//  2026-08-04 那一轮把橙色 `#FF5A1F` 铺开时,色号是**写死在 NNWSoftMaterial 里**的。
//  用户 2026-08-05 提出:「把这个变成一个基础设施和设置项,之后可以一键换所有橙色的地方」
//  —— 这个提法比"再手动改一遍色号"好得多,所以照做:
//  色号收进这里,界面代码一律只认 `NNWAccentPalette.current`。
//
//  ## 换色之后,谁会跟着变
//
//  凡是走 `NNWSoftMaterial.accent` 的地方全都跟着变:
//  首页搜索/编辑/齿轮/加号、分组头与文件夹三角、三档控件的当前档、
//  dock 上点亮的星标、自绘选单顶部那排快捷图标。
//
//  ⚠️ **暂时跟不上的**:`Assets.xcassets` 里那两个色板
//  (`primaryAccentColor` / `starColor`)—— 它们是**静态资源**,
//  编译进 app 之后改不了。上游代码直接引用它们的地方(列表行的未读点、
//  部分系统控件的 tint)换色后仍是橙的。要一起跟上得把那些引用一个个改成走本文件,
//  属于下一步的活,已记进 NOTES-todo。
//
//  ## 加一个新颜色要做什么
//
//  往 `Choice` 里加一个 case,再在 `colors` 里给它一组「浅色 / 深色」值。
//  深色那份要比浅色亮一档 —— 深底上同一个色号会显得发闷(和 accent 原来的做法一致)。
//

#if os(iOS)

import UIKit

enum NNWAccentPalette {

	/// 可选的强调色。`rawValue` 会存进 UserDefaults,**别改已有的字符串**。
	enum Choice: String, CaseIterable {
		case orange		// 默认:2026-08-04 用户拍板的那个橙
		case terracotta	// 陶土红(这个 fork 更早一版用过的调子)
		case indigo
		case forest
		case plum
		case graphite	// 想要"没有强调色"的观感时用它

		var displayName: String {
			switch self {
			case .orange: return "橙"
			case .terracotta: return "陶土红"
			case .indigo: return "靛蓝"
			case .forest: return "森绿"
			case .plum: return "梅紫"
			case .graphite: return "石墨"
			}
		}

		/// (浅色下的值, 深色下的值)。深色一律比浅色亮一档。
		var colors: (light: UInt32, dark: UInt32) {
			switch self {
			case .orange:		return (0xFF5A1F, 0xFF6A2F)
			case .terracotta:	return (0xC0562F, 0xD4693F)
			case .indigo:		return (0x3B5BA9, 0x5C7CC7)
			case .forest:		return (0x2F6B4F, 0x47886A)
			case .plum:			return (0x7A3F6D, 0x9C5B8C)
			case .graphite:		return (0x4A4741, 0xB4AEA4)
			}
		}
	}

	private static let defaultsKey = "nnwAccentChoice"

	/// 换色之后发这个通知 —— 已经画好的控件(烘焙成图片的圆钮等)要靠它重画。
	static let didChangeNotification = Notification.Name("NNWAccentPaletteDidChange")

	/// 当前选的是哪一个。**只读,而且不绑主线程** ——
	/// `Shared/Assets.swift` 里的 `static let` 会在任意线程第一次被访问,
	/// 而那些颜色要靠它现算(见文件头「谁会跟着变」)。
	static var choice: Choice {
		guard let raw = UserDefaults.standard.string(forKey: defaultsKey),
			  let value = Choice(rawValue: raw) else { return .orange }
		return value
	}

	/// 换色。**只能在主线程调** —— 换完要发通知让界面重画。
	@MainActor
	static func setChoice(_ newValue: Choice) {
		guard newValue != choice else { return }
		UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey)
		NotificationCenter.default.post(name: didChangeNotification, object: nil)
	}

	/// **全 app 的强调色。界面代码只认这一个。**
	static var current: UIColor { color(for: choice) }

	/// 会**自己跟上换色**的那一份:`UIColor` 的动态闭包在每次解析(重画)时才求值,
	/// 所以它读到的永远是当下选的颜色。
	/// `Shared/Assets.swift` 里那些 `static let` 用这一份 —— 那种常量只会构造一次,
	/// 用 `current` 的话会把开机时的颜色永久钉死。
	static var live: UIColor {
		UIColor { traits in color(for: choice).resolvedColor(with: traits) }
	}

	static func color(for choice: Choice) -> UIColor {
		let (light, dark) = choice.colors
		return UIColor { $0.userInterfaceStyle == .dark ? rgb(dark) : rgb(light) }
	}

	private static func rgb(_ hex: UInt32) -> UIColor {
		UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
				green: CGFloat((hex >> 8) & 0xFF) / 255,
				blue: CGFloat(hex & 0xFF) / 255,
				alpha: 1)
	}
}

#endif
