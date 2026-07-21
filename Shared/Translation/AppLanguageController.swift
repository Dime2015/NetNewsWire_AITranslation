//
//  AppLanguageController.swift
//  NetNewsWire — AI 翻译 fork
//
//  界面语言的读写:默认跟随系统,也可以手动指定。
//
//  ⚠️ 面向未来:这里**不写死任何语言列表**。
//  可选项直接来自 `Bundle.main.localizations` —— app 包里有哪几种语言就列哪几种。
//  以后加日语时,只要把 ja 的翻译注入字符串目录、并新增 iOS/ja.lproj/Main.strings,
//  日语会自动出现在这个选择器里,**本文件一行都不用改**。
//
//  这个文件不属于上游 NetNewsWire,是本 fork 新增的。
//

import Foundation

enum AppLanguageController {

	/// iOS 读取"App 首选语言"用的系统键。写入它即可覆盖系统语言。
	private static let appleLanguagesKey = "AppleLanguages"

	/// 我们自己记一份用户的选择。
	/// 为什么不直接读 AppleLanguages:系统会把它改写成一个完整的回退链
	/// (例如 ["zh-Hans", "en"]),读回来分不清"用户选了中文"还是"系统本来就是中文"。
	private static let selectedLanguageKey = "nnwSelectedInterfaceLanguage"

	/// 一个可选项。`nil` 代表跟随系统。
	struct Option: Identifiable, Sendable {
		let code: String?
		let displayName: String
		var id: String { code ?? "__system__" }
	}

	/// 当前选择。nil = 跟随系统。
	static var selectedLanguage: String? {
		get { UserDefaults.standard.string(forKey: selectedLanguageKey) }
		set {
			let defaults = UserDefaults.standard
			if let newValue {
				defaults.set(newValue, forKey: selectedLanguageKey)
				defaults.set([newValue], forKey: appleLanguagesKey)
			} else {
				defaults.removeObject(forKey: selectedLanguageKey)
				// 移除覆盖后,系统会重新按设备语言决定
				defaults.removeObject(forKey: appleLanguagesKey)
			}
		}
	}

	/// 可选的语言列表:跟随系统 + app 包里实际带的每种语言。
	static var availableOptions: [Option] {

		// Base 是 Storyboard 的开发语言占位,不是给用户选的
		let codes = Bundle.main.localizations
			.filter { $0 != "Base" }
			.sorted()

		let system = Option(code: nil, displayName: systemDisplayName)

		return [system] + codes.map { code in
			Option(code: code, displayName: displayName(for: code))
		}
	}

	/// 语言的自称,例如 zh-Hans → "简体中文"、ja → "日本語"。
	/// 用目标语言自己的写法(而不是当前界面语言的写法),
	/// 这样即使用户误选了看不懂的语言,也能找回来。
	static func displayName(for code: String) -> String {
		let locale = Locale(identifier: code)
		if let name = locale.localizedString(forIdentifier: code), !name.isEmpty {
			return name.prefix(1).uppercased() + name.dropFirst()
		}
		return code
	}

	/// "跟随系统"这一项的显示文字,带上系统当前实际是什么语言。
	private static var systemDisplayName: String {
		let systemCode = Locale.preferredLanguages.first ?? "en"
		return "跟随系统(\(displayName(for: systemCode)))"
	}

	/// 当前生效语言的显示名,给设置页的那一行做副标题用。
	static var currentDisplayName: String {
		guard let selectedLanguage else {
			return systemDisplayName
		}
		return displayName(for: selectedLanguage)
	}
}
