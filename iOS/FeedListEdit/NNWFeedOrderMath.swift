//
//  NNWFeedOrderMath.swift
//  首页拖放排序 —— 「把选中的几项挪到第几位」的纯算术
//
//  [编辑] 本 fork 新增文件,上游不存在。
//
//  ## 为什么单独拆出来
//
//  和 `DropZoneResolver` 同一个理由(那边是落点规则,这边是插入算术):
//  这一段没有任何 UIKit,纯粹是数组操作,但**恰恰最容易算错一位** ——
//  而"差一位"这种 bug 靠肉眼复查基本看不出来,靠点模拟器又要一次次拖。
//
//  拆出来之后 `tools/sim-feedorder.swift` 能把本文件**原样一起编译**跑一遍决策表,
//  验的是真代码不是抄件(L63:能抽成纯逻辑的必须先自己验)。
//
//  ## 唯一那个容易错的地方
//
//  把 A、C 两项挪到"第 4 位"时,插入位置 4 是**基于原数组**算的;
//  可一旦先把 A、C 抽走,数组就短了,原来的第 4 位已经不是那个位置了。
//  所以必须**减去"被抽走的项里,原本排在插入点之前的个数"**。
//  漏掉这一步的表现是:往下拖时总是少挪一位,而且拖得越多差得越远。
//

import Foundation

enum NNWFeedOrderMath {

	/// 把 `movingKeys` 从 `orderedKeys` 里抽出来,整体插到 `insertIndex` 处。
	///
	/// - Parameters:
	///   - orderedKeys: 这一层现在的顺序(可能不含 movingKeys —— 跨容器搬过来时就是这样)
	///   - movingKeys: 要挪的那几项,**保持它们彼此之间的先后**
	///   - insertIndex: 想插到**原数组**的第几位(0 = 最前面)
	/// - Returns: 挪好之后这一层的完整顺序
	static func reordered(_ orderedKeys: [String],
						  moving movingKeys: [String],
						  toIndex insertIndex: Int) -> [String] {

		guard !movingKeys.isEmpty else { return orderedKeys }

		let movingSet = Set(movingKeys)

		// ⚠️ 关键的一步(见文件头):被抽走的项里,有几个原本排在插入点之前?
		// 插入点要往前挪同样多,否则往下拖会少挪一位。
		let removedBefore = orderedKeys.enumerated().filter { index, key in
			movingSet.contains(key) && index < insertIndex
		}.count

		var result = orderedKeys.filter { !movingSet.contains($0) }
		let clamped = max(0, min(insertIndex - removedBefore, result.count))
		result.insert(contentsOf: movingKeys, at: clamped)
		return result
	}

	/// 由「锚在第几位 + 手指在锚行的上半还是下半」算出插入位置。
	///
	/// - Parameters:
	///   - anchorIndex: 锚行在这一层里排第几(找不到锚时传 nil)
	///   - insertAfter: true = 插到锚**后面**,false = 插到锚**前面**
	///   - layerCount: 这一层现在有几项(找不到锚时排到末尾要用)
	static func insertionIndex(anchorIndex: Int?, insertAfter: Bool, layerCount: Int) -> Int {
		guard let anchorIndex else { return layerCount }		// 连锚都没有:排到末尾
		return insertAfter ? anchorIndex + 1 : anchorIndex
	}
}
