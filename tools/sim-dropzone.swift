//
//  sim-dropzone.swift
//  文件夹管理页 —— 拖放落点判定的离线验证
//
//  ## 怎么跑
//
//  ```bash
//  swiftc -o /tmp/sim-dropzone \
//    "iOS/FolderManager/DropZoneResolver.swift" "tools/sim-dropzone.swift" && /tmp/sim-dropzone
//  ```
//
//  ## 为什么要有它
//
//  拖放是我(AI)**没法自己操作**的交互路径,而它又恰恰是这个项目里踩坑最多的地方
//  (L63 / L65 / L66)。CLAUDE.md 第 0 节的分工是「界面上的点按交给用户」,
//  但这不等于"把风险丢给用户去撞" —— 能抽成纯逻辑的部分必须自己先验(L63 的结论)。
//
//  这里验的是**真代码**:上面那行 swiftc 把 `DropZoneResolver.swift` 原样编译进来,
//  不是抄一份副本对着跑(抄副本迟早会和真代码长歪)。
//
//  ⚠️ 但也要清楚它**验不了什么**:UIKit 内部状态机相关的时序问题
//  (`coordinator.drop` 的调用顺序、批量更新时数据源一致性)离线复现不出来,
//  那些只能靠用户实测(L66)。
//

import CoreGraphics
import Foundation

@main
enum DropZoneSimulation {

static func main() {

	// MARK: - 测试脚手架

	var failures = 0
	var checks = 0

	func expect(_ actual: DropResolution, _ expectedTarget: DropTarget, _ expectedInsertInto: Bool,
				_ what: String) {
		checks += 1
		let expected = DropResolution(target: expectedTarget, isInsertInto: expectedInsertInto)
		if actual != expected {
			failures += 1
			print("❌ \(what)")
			print("   期望:target=\(expectedTarget) insertInto=\(expectedInsertInto)")
			print("   实际:target=\(actual.target) insertInto=\(actual.isInsertInto)")
		} else {
			print("✅ \(what)")
		}
	}

	func expectBand(_ actual: DropBand, _ expected: DropBand, _ what: String) {
		checks += 1
		if actual != expected {
			failures += 1
			print("❌ \(what) —— 期望 \(expected),实际 \(actual)")
		} else {
			print("✅ \(what)")
		}
	}

	/// 一行的典型尺寸:宽 390(iPhone 17 的点宽)、高 44、从 y=100 开始
	let row = CGRect(x: 0, y: 100, width: 390, height: 44)
	/// 边缘带高度 = min(44 * 0.3, 16) = 13.2 → 上带 [100,113.2) 下带 (130.8,144]
	let yTop: CGFloat = 104
	let yMiddle: CGFloat = 122
	let yBottom: CGFloat = 140
	/// 横向:靠右 = 正常拖动的位置;靠左 = 退出了缩进线(< 56)
	let xRight: CGFloat = 200
	let xLeft: CGFloat = 30

	func resolve(_ anchor: DropAnchorKind, y: CGFloat, x: CGFloat = xRight,
				 draggingFolder: Bool = false) -> DropResolution {
		DropZoneResolver.resolve(anchor: anchor,
								 band: DropZoneResolver.band(of: CGPoint(x: x, y: y), in: row),
								 pointX: x,
								 draggingFolder: draggingFolder)
	}

	// MARK: - 一、分带的几何

	print("\n【一】手指落在一行的哪一段")

	expectBand(DropZoneResolver.band(of: CGPoint(x: xRight, y: 100), in: row), .top, "正好压在行的上边线 → 上带")
	expectBand(DropZoneResolver.band(of: CGPoint(x: xRight, y: yTop), in: row), .top, "行内偏上 → 上带")
	expectBand(DropZoneResolver.band(of: CGPoint(x: xRight, y: yMiddle), in: row), .middle, "行的正中 → 中带")
	expectBand(DropZoneResolver.band(of: CGPoint(x: xRight, y: yBottom), in: row), .bottom, "行内偏下 → 下带")
	expectBand(DropZoneResolver.band(of: CGPoint(x: xRight, y: 144), in: row), .bottom, "正好压在行的下边线 → 下带")
	// ⚠️ 这一条是最容易被忽略的:落在列表空白处时,上层取"上方最近的一行"当锚,
	// 手指其实在那一行的**下方**。必须算成"排在它后面",否则空白处又会变成死区(前几轮的老毛病)。
	expectBand(DropZoneResolver.band(of: CGPoint(x: xRight, y: 300), in: row), .bottom, "落在这一行下方的空白 → 下带")
	expectBand(DropZoneResolver.band(of: CGPoint(x: xRight, y: 113.2), in: row), .middle, "边界:上带的下沿归中带")
	expectBand(DropZoneResolver.band(of: CGPoint(x: xRight, y: 130.8), in: row), .middle, "边界:下带的上沿归中带")

	// MARK: - 二、用户提的那个场景

	print("\n【二】用户场景:A 展开、B 收起,把 A 里的一个源拖到 A 和 B 中间(顶层)")

	// 路线 ①(本轮新开的):瞄 B 的上边缘。这是肉眼看得见的两行分界线。
	expect(resolve(.folder(expanded: false), y: yTop), .topLevel, false,
		   "① 停在收起的文件夹 B 的上边缘 → 顶层(排在 B 前面),不是放进 B")
	// ⚠️ 「悬停自动展开」已于 2026-07-23 整个拿掉(用户:展开后列表越撑越长、够不着靠下的位置),
	// 所以停在这里不会有任何东西自己展开,列表长度在整个拖动过程中恒定。

	// 路线 ②(原有的):停在 A 的最后一个子行上、手指往左退出缩进线
	expect(resolve(.nestedFeed, y: yBottom, x: xLeft), .topLevel, false,
		   "② 停在 A 的子行、手指退到缩进线左边 → 顶层(原有路径仍然有效)")

	// MARK: - 三、文件夹行的三段

	print("\n【三】落点是文件夹行")

	expect(resolve(.folder(expanded: false), y: yMiddle), .anchorFolder, true,
		   "收起的文件夹 · 中带 → 放进这个文件夹")
	expect(resolve(.folder(expanded: false), y: yBottom), .topLevel, false,
		   "收起的文件夹 · 下带 → 顶层(排在它后面)")
	expect(resolve(.folder(expanded: true), y: yTop), .topLevel, false,
		   "展开的文件夹 · 上带 → 顶层(排在它前面)")
	expect(resolve(.folder(expanded: true), y: yMiddle), .anchorFolder, true,
		   "展开的文件夹 · 中带 → 放进这个文件夹")
	// ⚠️ 展开时下带紧挨着它的第一个子行,屏幕上看就是"文件夹里面";
	// 而顶层意义上的"它后面"在整片子行的下方,不在这儿。
	expect(resolve(.folder(expanded: true), y: yBottom), .anchorFolder, true,
		   "展开的文件夹 · 下带 → 放进这个文件夹(不是排在它后面)")

	// MARK: - 四、落点是源

	print("\n【四】落点是源")

	for (name, y) in [("上带", yTop), ("中带", yMiddle), ("下带", yBottom)] {
		expect(resolve(.looseFeed, y: y), .topLevel, false, "顶层的源 · \(name) → 顶层调顺序")
	}
	expect(resolve(.nestedFeed, y: yMiddle, x: xRight), .enclosingFolder, false,
		   "文件夹里的源 · 手指在正常位置 → 还在这个文件夹里")
	expect(resolve(.nestedFeed, y: yMiddle, x: xLeft), .topLevel, false,
		   "文件夹里的源 · 手指退到缩进线左边 → 拿出文件夹")
	expect(resolve(.nestedFeed, y: yMiddle, x: 55), .topLevel, false,
		   "边界:x=55(阈值 56 以内)→ 拿出文件夹")
	expect(resolve(.nestedFeed, y: yMiddle, x: 56), .enclosingFolder, false,
		   "边界:x=56(正好在阈值上)→ 仍算在文件夹里")

	// MARK: - 五、拖的是文件夹

	print("\n【五】拖的是文件夹(上游不支持子文件夹,只可能在顶层调顺序)")

	expect(resolve(.folder(expanded: false), y: yMiddle, draggingFolder: true), .topLevel, false,
		   "拖文件夹 · 落在收起的文件夹中带 → 顶层调顺序,不是套进去")
	expect(resolve(.folder(expanded: true), y: yBottom, draggingFolder: true), .topLevel, false,
		   "拖文件夹 · 落在展开的文件夹下带 → 顶层调顺序")
	expect(resolve(.nestedFeed, y: yMiddle, x: xRight, draggingFolder: true), .topLevel, false,
		   "拖文件夹 · 落在别人文件夹里的源上 → 顶层调顺序")
	expect(resolve(.looseFeed, y: yMiddle, draggingFolder: true), .topLevel, false,
		   "拖文件夹 · 落在顶层的源上 → 顶层调顺序")

	// MARK: - 六、不变量(最要紧的一条)

	print("\n【六】不变量:「放进这一项」的意图只出现在该出现的地方")
	//
	// 这个意图决定用户看到哪种反馈(目标行高亮 vs 让开一条缝),
	// 而它必须**只**在"目标是落点那个文件夹"时出现 —— 否则就会出现
	// "高亮着某一行、松手却插到别处"这种看着能放、放了不对的错位。
	//
	// ⚠️ 曾经这里还有一条更要紧的防崩不变量(「会触发文件夹展开 ⟹ 落点不插占位」,L65)。
	// 「悬停自动展开」已于 2026-07-23 整个拿掉,拖动全程不再修改数据源,
	// 那条崩溃路径不复存在,所以这条不变量也随之消失。**若有人把弹簧加载加回来,
	// 必须把那条不变量一并加回来。**

	let allAnchors: [DropAnchorKind] = [.folder(expanded: false), .folder(expanded: true),
										.looseFeed, .nestedFeed]
	let allBands: [DropBand] = [.top, .middle, .bottom]
	let allX: [CGFloat] = [10, 30, 55, 56, 100, 200, 380]

	var combos = 0
	var violations = 0
	var insertIntoCount = 0
	for anchor in allAnchors {
		for band in allBands {
			for x in allX {
				for draggingFolder in [false, true] {
					combos += 1
					let r = DropZoneResolver.resolve(anchor: anchor, band: band,
													 pointX: x, draggingFolder: draggingFolder)
					if r.isInsertInto {
						insertIntoCount += 1
						// ① "放进这一项"的意图只能出现在"目标是落点那个文件夹"时
						if r.target != .anchorFolder { violations += 1 }
						// ② 拖文件夹时永远不许出现"放进去"(上游不支持子文件夹)
						if draggingFolder { violations += 1 }
					}
					// ③ 反过来:目标是落点那个文件夹时,必须用"放进这一项"的意图
					if r.target == .anchorFolder && !r.isInsertInto { violations += 1 }
				}
			}
		}
	}
	checks += 1
	if violations > 0 {
		failures += 1
		print("❌ 穷举 \(combos) 种组合,发现 \(violations) 处违反不变量")
	} else {
		print("✅ 穷举 \(combos) 种组合,不变量全部成立(其中 \(insertIntoCount) 种是「放进文件夹」)")
	}

	// MARK: - 结果

	print("\n" + String(repeating: "─", count: 56))
	if failures == 0 {
		print("全部通过:\(checks) 项检查")
		exit(0)
	} else {
		print("失败 \(failures) 项 / 共 \(checks) 项")
		exit(1)
	}

}
}
