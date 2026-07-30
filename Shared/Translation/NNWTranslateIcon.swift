//
//  NNWTranslateIcon.swift
//  NetNewsWire — AI 翻译 fork
//
//  [翻译] 本 fork 新增,上游没有这个文件。
//
//  翻译按钮的图标(2026-07-30 用户四轮选型定案):
//  1. 单气泡「字」(character.bubble)→ 用户想要双气泡 →
//  2. 自绘双气泡「文/A」→ 缩小到和邻居同尺寸后用户觉得不好看 →
//  3. 系统 SF 符号「translate」—— 用户拍板"效果很好" →
//  4. "已翻译"状态曾用自绘实心方块+镂空字形,用户否掉("效果很差")。
//     **定案:图标永远用同一个 translate 符号,"已翻译"由按钮加淡色底衬表达**
//     (见 TranslationButton.applyDisplayState)—— 大小、描边全程不变。
//
//  用系统符号的连带好处:控件板的 17pt 统一配置对它原生生效,
//  尺寸和已读/星标那些键严格一致,没有手调成分。
//

#if os(iOS)

import UIKit

@MainActor enum NNWTranslateIcon {

	/// 系统「translate」符号(A/文 双气泡)。所有状态共用这一个 ——
	/// 状态差异由按钮的底衬/转圈/角标表达,图标本身不变。
	/// 万一系统里没有这个名字(理论上 iOS 17.4+ 都有),退回老的单气泡,不崩。
	static let outline: UIImage = UIImage(systemName: "translate")
		?? UIImage(systemName: "character.bubble")!
}

#endif
