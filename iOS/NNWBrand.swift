//
//  NNWBrand.swift
//  NetNewsWire — AI 翻译 fork
//
//  [品牌] app 品牌名的**唯一取用口**。本 fork 新增,上游没有。
//
//  ## 改名操作手册(2026-07-24 用户要求「想换名字时能一键替换」)
//
//  品牌名的唯一真源是 `xcconfig/NetNewsWire_iOSapp_target.xcconfig` 的
//  `APP_DISPLAY_NAME`(它流进 Info.plist 的 CFBundleDisplayName → 主屏名)。
//  改名的完整动作只有一条命令:
//
//      python3 i18n/rebrand.py <新名字>
//
//  它改 xcconfig + 全部中文文案;而**代码里所有出现品牌名的地方都必须走本文件**,
//  运行时从 Bundle 读,于是重编译后自动跟上,零代码改动。
//
//  ## 品牌名的全部落点(2026-07-24 盘点,新增落点请更新此清单)
//
//  | 落点 | 谁管 |
//  |---|---|
//  | 主屏 app 名 | xcconfig APP_DISPLAY_NAME(rebrand.py 改) |
//  | 中文文案(设置页、关于页等 ~17 处) | i18n/zh-Hans.json + Settings.strings(rebrand.py 改) |
//  | 首页头图的报头「Babel」 | 本文件 displayName(自动) |
//  | 将来的新落点(分享页脚等) | **一律引用本文件**,别写死 |
//  | bundle id / target 名 / User-Agent / 英文原文 | **故意不改**,原因见 rebrand.py 开头 |
//
//  ⚠️ **禁止在任何 Swift/JS 文件里写死品牌名字符串** —— 那会让"一键替换"变成谎言。
//  连本文件的兜底值都刻意用中性的「RSS」,不用当前品牌名。
//

import Foundation

enum NNWBrand {

	/// app 的显示名(= 主屏上的名字)。改名后重编译自动生效。
	static var displayName: String {
		(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)?
			.trimmingCharacters(in: .whitespaces)
			.nonEmpty ?? "RSS"
	}
}

private extension String {
	var nonEmpty: String? { isEmpty ? nil : self }
}
