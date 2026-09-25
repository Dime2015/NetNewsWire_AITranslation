import UIKit

/// 设置页的样式常量（Figma「00 · Settings Home」等 22 个画面实测，Slice 6 / 2026-09-25）。
/// 颜色随深浅色自动切换；浅色值即 Figma 变量值。
enum Babel2SettingsStyle {
	// MARK: 几何
	/// 内容左右各留 20pt（Figma Settings Content x=20、宽 362）。
	static let sideInset: CGFloat = 20
	/// 内容区顶部内边距 18pt。
	static let contentTopInset: CGFloat = 18
	/// 导航栏高度 58pt（安全区以下）。
	static let navigationHeight: CGFloat = 58
	static let sectionHeaderHeight: CGFloat = 28
	static let rowHeight: CGFloat = 48
	static let disclosureRowHeight: CGFloat = 56
	static let textFieldHeight: CGFloat = 68

	// MARK: 颜色
	/// color/text/primary #3a3a3a
	static var primaryText: UIColor { BabelPalette.ink }
	/// color/text/secondary #787878（也是图标、勾、箭头的颜色）
	static var secondaryText: UIColor { BabelPalette.mutedInk }
	/// color/border/hairline #e0dddd
	static var hairline: UIColor { BabelPalette.hairline }
	static var background: UIColor { BabelPalette.background }
	/// color/background/input #efeced
	static let inputBackground = UIColor { traits in
		traits.userInterfaceStyle == .dark
			? UIColor(red: 38 / 255, green: 38 / 255, blue: 38 / 255, alpha: 1)
			: UIColor(red: 239 / 255, green: 236 / 255, blue: 237 / 255, alpha: 1)
	}
	/// color/background/elevated #ffffff（弹出选单底色）
	static let elevatedBackground = UIColor { traits in
		traits.userInterfaceStyle == .dark
			? UIColor(red: 46 / 255, green: 46 / 255, blue: 46 / 255, alpha: 0.96)
			: UIColor(white: 1, alpha: 0.96)
	}
	/// 开关关闭时的底色：color/background/selection #d8d5d6
	static var switchOffTrack: UIColor { BabelPalette.raisedBackground }
	/// 开关打开时：用户选的强调色（ADR-008：强调色只用于设置开关与阅读进度环）。Figma 画的灰色是默认中性色画法。
	static var switchOnTrack: UIColor { BabelPalette.themeAccent }
	/// 危险操作：red/500 #e75c57
	static let destructive = UIColor(red: 231 / 255, green: 92 / 255, blue: 87 / 255, alpha: 1)

	// MARK: 字体
	static let navigationTitleFont = UIFont.systemFont(ofSize: 24, weight: .semibold)
	static let sectionHeaderFont = UIFont.systemFont(ofSize: 11, weight: .semibold)
	static let disclosureTitleFont = UIFont.systemFont(ofSize: 16, weight: .semibold)
	static let disclosureDetailFont = UIFont.systemFont(ofSize: 11, weight: .regular)
	static let rowTitleFont = UIFont.systemFont(ofSize: 16, weight: .regular)
	static let valueFont = UIFont.systemFont(ofSize: 13, weight: .regular)
	static let selectValueFont = UIFont.systemFont(ofSize: 15, weight: .regular)
	static let noteFont = UIFont.systemFont(ofSize: 13, weight: .regular)
}

/// 设置页文案：英文作键，中英文都在 Babel2Localizable.xcstrings 里。
enum Babel2SettingsText {
	static func t(_ key: String, bundle: Bundle = .main) -> String {
		bundle.localizedString(forKey: key, value: key, table: "Babel2Localizable")
	}

	/// 带一个参数的文案（键里用 %@ / %d 占位）。
	static func f(_ key: String, _ arguments: CVarArg..., bundle: Bundle = .main) -> String {
		String(format: t(key, bundle: bundle), arguments: arguments)
	}
}
