//
//  sim-feedorder.swift
//  首页拖放排序 —— 插入算术的离线验证
//
//  ## 怎么跑
//
//  ```bash
//  swiftc -o /tmp/sim-feedorder \
//    "iOS/FeedListEdit/NNWFeedOrderMath.swift" "tools/sim-feedorder.swift" && /tmp/sim-feedorder
//  ```
//
//  ## 为什么要有它
//
//  和 `sim-dropzone.swift` 同一个理由:拖放是我(AI)没法自己操作的交互路径,
//  而"插入位置算错一位"这种 bug 肉眼复查基本看不出来 —— 往下拖时少挪一位,
//  拖得越多差得越远,用户只会觉得"落点不准"(当年管理页正是这么报的)。
//
//  这里验的是**真代码**:上面那行 swiftc 把 `NNWFeedOrderMath.swift` 原样编译进来。
//

import Foundation

@main
struct SimFeedOrder {

static func main() {

	var failures = 0
	var checks = 0

	func expect(_ actual: [String], _ expected: [String], _ what: String) {
		checks += 1
		if actual == expected {
			print("  ✅ \(what)")
		} else {
			failures += 1
			print("  ❌ \(what)")
			print("     期望: \(expected.joined(separator: ","))")
			print("     实际: \(actual.joined(separator: ","))")
		}
	}

	func expectIndex(_ actual: Int, _ expected: Int, _ what: String) {
		checks += 1
		if actual == expected {
			print("  ✅ \(what)")
		} else {
			failures += 1
			print("  ❌ \(what) —— 期望 \(expected),实际 \(actual)")
		}
	}

	let base = ["A", "B", "C", "D", "E"]

	print("\n【一】单项在同一层里挪动")

	expect(NNWFeedOrderMath.reordered(base, moving: ["A"], toIndex: 0), base,
		   "把第 1 项插到最前 = 没动")

	expect(NNWFeedOrderMath.reordered(base, moving: ["A"], toIndex: 2), ["B", "A", "C", "D", "E"],
		   "A 往下挪到第 3 位之前 → 落在 B 后面(这就是最容易差一位的那个)")

	expect(NNWFeedOrderMath.reordered(base, moving: ["A"], toIndex: 5), ["B", "C", "D", "E", "A"],
		   "A 拖到末尾")

	expect(NNWFeedOrderMath.reordered(base, moving: ["E"], toIndex: 0), ["E", "A", "B", "C", "D"],
		   "E 拖到最前")

	expect(NNWFeedOrderMath.reordered(base, moving: ["C"], toIndex: 1), ["A", "C", "B", "D", "E"],
		   "C 往上挪一位")

	expect(NNWFeedOrderMath.reordered(base, moving: ["C"], toIndex: 4), ["A", "B", "D", "C", "E"],
		   "C 往下挪一位(插入点在自己后面 → 要减 1)")

	print("\n【二】多选挪动:彼此的先后必须保持")

	expect(NNWFeedOrderMath.reordered(base, moving: ["A", "C"], toIndex: 4), ["B", "D", "A", "C", "E"],
		   "A 和 C 一起挪到第 5 位之前(两个都在插入点之前 → 减 2)")

	expect(NNWFeedOrderMath.reordered(base, moving: ["D", "E"], toIndex: 0), ["D", "E", "A", "B", "C"],
		   "D、E 一起拖到最前")

	// 插入点 3 = 原数组里「C 和 D 之间」。抽走 B、D 后剩 A C E,那个位置就是 C 后面。
	// (写这条时我第一次把期望算成了 A,B,D,C,E —— 离线跑一遍当场就照出来了。)
	expect(NNWFeedOrderMath.reordered(base, moving: ["B", "D"], toIndex: 3), ["A", "C", "B", "D", "E"],
		   "跨着挑两项挪到中间")

	print("\n【三】跨容器搬过来:这一层原本没有这几项")

	expect(NNWFeedOrderMath.reordered(["X", "Y"], moving: ["A"], toIndex: 1), ["X", "A", "Y"],
		   "从别的文件夹搬一个进来,插在中间")

	expect(NNWFeedOrderMath.reordered([], moving: ["A", "B"], toIndex: 0), ["A", "B"],
		   "搬进一个空文件夹")

	print("\n【四】边界:越界的插入位置要被夹住,不能崩")

	expect(NNWFeedOrderMath.reordered(base, moving: ["A"], toIndex: 99), ["B", "C", "D", "E", "A"],
		   "插入位置远超长度 → 落到末尾")

	expect(NNWFeedOrderMath.reordered(base, moving: ["A"], toIndex: -5), ["A", "B", "C", "D", "E"],
		   "插入位置为负 → 落到最前")

	expect(NNWFeedOrderMath.reordered(base, moving: [], toIndex: 2), base,
		   "没有要挪的项 = 原样返回")

	expect(NNWFeedOrderMath.reordered(base, moving: ["Z"], toIndex: 2), ["A", "B", "Z", "C", "D", "E"],
		   "挪一个本来不在这层的键 = 当作搬进来")

	print("\n【五】由锚行算插入位置")

	expectIndex(NNWFeedOrderMath.insertionIndex(anchorIndex: 2, insertAfter: false, layerCount: 5), 2,
				"插到锚前面")
	expectIndex(NNWFeedOrderMath.insertionIndex(anchorIndex: 2, insertAfter: true, layerCount: 5), 3,
				"插到锚后面")
	expectIndex(NNWFeedOrderMath.insertionIndex(anchorIndex: nil, insertAfter: false, layerCount: 5), 5,
				"找不到锚 → 排到末尾")
	expectIndex(NNWFeedOrderMath.insertionIndex(anchorIndex: 0, insertAfter: false, layerCount: 5), 0,
				"锚是第一行的上半 → 落到首位")

	print("\n" + String(repeating: "─", count: 46))
	if failures == 0 {
		print("✅ 全部 \(checks) 项通过")
		exit(0)
	} else {
		print("❌ \(checks) 项里有 \(failures) 项没过")
		exit(1)
	}

}
}
