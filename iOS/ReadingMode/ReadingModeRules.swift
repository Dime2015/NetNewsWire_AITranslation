//
//  ReadingModeRules.swift
//  阅读档位 —— 「纯规则」部分
//
//  [阅读档] 本 fork 新增文件,上游不存在。
//
//  ## 这个文件为什么单独存在
//
//  和 `DropZoneResolver.swift` 同一个理由:**左右滑切档是我(AI)没法自己操作的交互路径**。
//  「从当前档往左/往右滑,应该落到哪一档」是纯逻辑,不需要 UIKit、不需要 Account。
//  拆出来之后 `tools/sim-readingmode.swift` 能把这个文件**原样一起编译**跑决策表 ——
//  验的是真代码,不是抄一份副本(抄副本迟早和真代码长歪)。
//
//  ⚠️ 它验不了什么:控件长什么样、手势会不会和列表滚动打架、换档后列表刷不刷得对。
//  那些只能靠实测(而且涉及滚动 → 按 L73,模拟器过了也不算数,要真机)。
//

import Foundation

/// 三个档位。**顺序就是控件上从左到右的顺序**,左右滑也按这个顺序走。
enum NNWReadingMode: String, CaseIterable {

	case starred		// ★ 只看加过星的
	case unread			// 只看没读过的
	case all			// 全都看

	var title: String {
		switch self {
		case .starred:	return "星标"
		case .unread:	return "未读"
		case .all:		return "全部"
		}
	}

	/// 控件上的图标(SF Symbols)。
	/// ⚠️ 这三个都是 iOS 15 就有的老符号 —— L70 的教训:
	/// 「我见过这个名字」不等于「这个系统上有」,新符号必须实测。
	var symbolName: String {
		switch self {
		case .starred:	return "star.fill"
		case .unread:	return "circle.inset.filled"
		case .all:		return "line.3.horizontal"
		}
	}

	/// 相邻的下一档。`forward = true` 表示往右边那一档走(= 手指往左滑)。
	///
	/// 两条刻意的规则:
	/// 1. **跳过还没做好的档**(Phase 1 的★)—— 但只是跳过,不是"当它不存在":
	///    从「未读」往左滑会直接停住,而不是越过★跳到「全部」(那样等于滑了个寂寞还换错档)。
	/// 2. **不循环**。滑到头就停,比"从最右一下弹回最左"好预期 ——
	///    循环切换在快速连滑时几乎必然切过头。
	static func neighbour(after current: NNWReadingMode,
						  forward: Bool,
						  isAvailable: (NNWReadingMode) -> Bool) -> NNWReadingMode? {

		let ordered = NNWReadingMode.allCases
		guard let index = ordered.firstIndex(of: current) else { return nil }

		let candidates: [NNWReadingMode] = forward
			? Array(ordered[(index + 1)...])
			: ordered[..<index].reversed()

		// 只看**紧邻的下一个**:它不可用就停手,不越过它去找更远的
		guard let next = candidates.first else { return nil }
		return isAvailable(next) ? next : nil
	}
}
