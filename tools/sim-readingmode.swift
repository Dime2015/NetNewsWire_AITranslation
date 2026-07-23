//
//  sim-readingmode.swift
//  阅读档位 —— 左右滑切档的离线验证
//
//  ## 怎么跑
//
//  ```bash
//  swiftc -o /tmp/sim-readingmode \
//    "iOS/ReadingMode/ReadingModeRules.swift" "tools/sim-readingmode.swift" && /tmp/sim-readingmode
//  ```
//
//  ## 为什么要有它
//
//  左右滑是我(AI)**没法自己操作**的交互路径。CLAUDE.md 第 0 节的分工是
//  「界面上的点按交给用户」,但这不等于把风险丢给用户去撞(L63 的结论)——
//  能抽成纯逻辑的部分自己先验完。
//
//  这里验的是**真代码**:上面那行 swiftc 把 `ReadingModeRules.swift` 原样编译进来。
//
//  ⚠️ 验不了的:手势会不会和列表滚动打架、换档后列表刷没刷对、控件好不好看。
//  那些要实测,而且涉及滚动 → 按 L73,模拟器过了也不算数,要真机。
//

import Foundation

@main
struct SimReadingMode {

	static var failures = 0

	/// 把「哪些档能用」做成参数,于是同一份真代码能在 Phase 1 / Phase 2 两种配置下各跑一遍
	static func availability(starredEnabled: Bool) -> (NNWReadingMode) -> Bool {
		{ mode in mode != .starred || starredEnabled }
	}

	static func check(_ label: String,
					  from: NNWReadingMode,
					  forward: Bool,
					  starredEnabled: Bool,
					  expect: NNWReadingMode?) {

		let result = NNWReadingMode.neighbour(after: from, forward: forward,
											  isAvailable: availability(starredEnabled: starredEnabled))
		let ok = result == expect
		if !ok { failures += 1 }
		let arrow = forward ? "手指往左滑 →" : "手指往右滑 ←"
		let got = result.map { $0.title } ?? "(停住)"
		let want = expect.map { $0.title } ?? "(停住)"
		print("\(ok ? "✅" : "❌")  \(label)：\(from.title) \(arrow) 得到「\(got)」,期望「\(want)」")
	}

	static func main() {

		print("=== Phase 1:★ 还没做好(starredEnabled = false) ===")
		// 这一档下只有「未读」「全部」两档可用,★ 只是个占位
		check("未读 → 全部", from: .unread, forward: true, starredEnabled: false, expect: .all)
		check("全部 → 未读", from: .all, forward: false, starredEnabled: false, expect: .unread)
		// 关键:从未读往右滑,左边那一档是还没做好的★ → 必须停住,
		// 既不能越过它跳到别处,也不能循环回「全部」(那会让用户以为滑反了)
		check("未读 ← 左边是没做好的★,应停住", from: .unread, forward: false, starredEnabled: false, expect: nil)
		check("全部 → 右边到头,应停住", from: .all, forward: true, starredEnabled: false, expect: nil)
		// 兜底:万一状态被弄成了★(开机时本来会回落到未读)
		check("★ → 下一档是未读", from: .starred, forward: true, starredEnabled: false, expect: .unread)
		check("★ ← 左边到头,应停住", from: .starred, forward: false, starredEnabled: false, expect: nil)

		print("")
		print("=== Phase 2 预演:★ 打开(starredEnabled = true) ===")
		check("★ → 未读", from: .starred, forward: true, starredEnabled: true, expect: .unread)
		check("未读 ← ★", from: .unread, forward: false, starredEnabled: true, expect: .starred)
		check("未读 → 全部", from: .unread, forward: true, starredEnabled: true, expect: .all)
		check("全部 ← 未读", from: .all, forward: false, starredEnabled: true, expect: .unread)
		check("★ ← 左边到头,应停住", from: .starred, forward: false, starredEnabled: true, expect: nil)
		check("全部 → 右边到头,应停住", from: .all, forward: true, starredEnabled: true, expect: nil)

		print("")
		print("=== 不变量:朝同一个方向连滑,必须停在端点,不能来回打转 ===")
		var loopFailures = 0
		for starred in [false, true] {
			for forward in [true, false] {
				for start in NNWReadingMode.allCases {
					var current = start
					var steps = 0
					var visited: Set<NNWReadingMode> = [start]
					while let next = NNWReadingMode.neighbour(after: current, forward: forward,
															  isAvailable: availability(starredEnabled: starred)) {
						current = next
						steps += 1
						if !visited.insert(current).inserted || steps > 10 {
							print("❌ starredEnabled=\(starred) forward=\(forward) 从「\(start.title)」连滑出现循环 / 走不完")
							loopFailures += 1
							break
						}
					}
				}
			}
		}
		failures += loopFailures
		if loopFailures == 0 {
			print("✅ 3 种起点 × 2 个方向 × 2 种配置 = 12 条路径,全部停在端点,没有循环")
		}

		print("")
		print(String(repeating: "─", count: 56))
		if failures == 0 {
			print("🎉 全部通过")
			exit(0)
		} else {
			print("💥 有 \(failures) 条没过")
			exit(1)
		}
	}
}
