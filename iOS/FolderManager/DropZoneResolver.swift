//
//  DropZoneResolver.swift
//  文件夹管理页 —— 拖放落点判定的「纯规则」部分
//
//  [管理] 本 fork 新增文件,上游不存在。
//
//  ## 这个文件为什么单独存在
//
//  拖放的落点判定是纯粹的**几何 + 规则**:给一个手指位置、给落点那一行是什么,
//  算出「要放进哪个容器」。它不需要 UIKit 的任何东西。
//
//  拆出来有两个实打实的好处:
//  1. **可以离线跑**。我(AI)点不了模拟器,而拖放又恰恰是最容易出错、
//     最难靠肉眼复查的地方。拆出来之后,`tools/sim-dropzone.swift` 能把
//     这个文件**原样一起编译**,对着决策表跑一遍 —— 验的是真代码,不是抄一份副本。
//  2. **不变量能被显式检查**。见下面 `Resolution` 里那条注释:
//     「会触发文件夹展开」和「落点不插占位」必须永远绑定,
//     松掉就会重演 2026-07-23 那次闪退(L65)。
//

import CoreGraphics

/// 手指落在一行的哪一段(纵向)。
enum DropBand {
	/// 上边缘 —— 意思是「插到这一行**前面**」
	case top
	/// 中间 —— 意思是「放**进**这一行」(仅当这一行是文件夹时有意义)
	case middle
	/// 下边缘,或者落在这一行**下方的空白** —— 意思是「插到这一行**后面**」
	case bottom
}

/// 落点那一行是个什么东西。
enum DropAnchorKind: Equatable {
	/// 文件夹行(`expanded` = 它当前是不是展开着)
	case folder(expanded: Bool)
	/// 没归档的源(直接挂在账户下)
	case looseFeed
	/// 某个文件夹**里面**的源
	case nestedFeed
}

/// 判定出来的目标容器。
enum DropTarget: Equatable {
	/// 放进**落点那一行**的那个文件夹
	case anchorFolder
	/// 放进**落点那一行所属**的文件夹(落点是文件夹里的某个源时)
	case enclosingFolder
	/// 放到账户顶层(不属于任何文件夹)
	case topLevel
}

/// 一次落点判定的完整结论。
struct DropResolution: Equatable {

	let target: DropTarget

	/// 用不用「放进这一项」的落点意图(`.insertIntoDestinationIndexPath`)。
	///
	/// 它决定用户看到哪种反馈:
	/// · `true`  → 目标行**高亮**,意思是"放进这一项里面"
	/// · `false` → 周围的行**让开一条缝**,意思是"插到这个位置"
	///
	/// ⚠️ 顺带记一笔:`false` 那种缝是 UIKit 插进列表的一个**占位**,不在数据快照里 ——
	/// 所以**拖动途中改数据源会撞批量更新校验、直接崩**(L65)。
	/// 当时的元凶是「悬停自动展开文件夹」,该机制已于 2026-07-23 整个拿掉,
	/// 现在拖动全程不修改数据源,这条崩溃路径不存在。**别再往回加。**
	let isInsertInto: Bool
}

/// 落点判定的规则表(纯函数,没有任何副作用)。
enum DropZoneResolver {

	// MARK: - 可调的数

	/// 上下边缘带各占一行高度的多少。
	///
	/// 0.3 = 上下各三成、中间留四成。取舍:
	/// **「放进文件夹」是常用动作,得留住中间大半;
	/// 「排到文件夹前面/后面」是新开的路,边缘带只要够手指瞄准就行。**
	static let edgeBandFraction: CGFloat = 0.3

	/// 边缘带最多多高(行特别高时不让边缘带跟着膨胀)
	static let edgeBandMaxHeight: CGFloat = 16

	/// 手指横向退到这个位置以左,就当成「要把源拿出文件夹」。
	///
	/// 取值参照:文件夹里的源,内容大致从 70pt 往右开始
	/// (系统缩进 + 我们额外补的 `nestedFeedExtraIndent`)。
	/// 定在 56 是让它**略微靠左于**内容起点 —— 顺手拖不会误判成"拿出来",
	/// 而有意往左带一截就能拿出来。
	static let outdentThreshold: CGFloat = 56

	// MARK: - 手指落在这一行的哪一段

	/// ⚠️ `point` 有可能**不在** `rowFrame` 里面 —— 落在列表空白处时,
	/// 上层会取「上方最近的那一行」当锚,那时 point 在这一行的下方 → 算 `.bottom`,
	/// 正好就是「排在它后面」的意思,和原来的行为一致。
	static func band(of point: CGPoint, in rowFrame: CGRect) -> DropBand {

		guard rowFrame.height > 0 else { return .middle }

		let bandHeight = min(rowFrame.height * edgeBandFraction, edgeBandMaxHeight)
		if point.y < rowFrame.minY + bandHeight { return .top }
		if point.y > rowFrame.maxY - bandHeight { return .bottom }
		return .middle
	}

	// MARK: - 规则表

	/// 把「落点那一行是什么 + 手指在这一行的哪一段 + 手指的横向位置」翻译成结论。
	///
	/// - Parameters:
	///   - anchor: 落点归属的那一行是什么
	///   - band: 手指落在那一行的哪一段
	///   - pointX: 手指的横向位置(判断「有没有退出缩进线」)
	///   - draggingFolder: 这次拖的是不是文件夹
	static func resolve(anchor: DropAnchorKind,
						band: DropBand,
						pointX: CGFloat,
						draggingFolder: Bool) -> DropResolution {

		// **拖的是文件夹 → 只可能是在顶层调顺序。**
		// 上游明确不支持子文件夹(`Folder.folders` 恒为 nil),文件夹没有别的地方可去。
		if draggingFolder {
			return DropResolution(target: .topLevel, isInsertInto: false)
		}

		switch anchor {

		case .folder(let expanded):
			// **收起的文件夹**:上边缘 = 排在它前面,中间 = 放进去,下边缘 = 排在它后面。
			//
			// **展开的文件夹**:下边缘不能算「排在它后面」——
			// 那一带在屏幕上紧挨着它的第一个子行,看上去就是"文件夹里面",
			// 而顶层意义上的"它后面"在整片子行的**下方**。所以展开时下边缘并入"放进去"。
			let into = (band == .middle) || (expanded && band == .bottom)
			return into
				? DropResolution(target: .anchorFolder, isInsertInto: true)
				: DropResolution(target: .topLevel, isInsertInto: false)

		case .looseFeed:
			// 顶层的源:落在它身上只可能是顶层内部调位置。
			return DropResolution(target: .topLevel, isInsertInto: false)

		case .nestedFeed:
			// 文件夹里的源:默认算"还在这个文件夹里"
			// (展开后它下面那一片,在观感上就是文件夹里面)。
			//
			// **但手指往左退出缩进线时,算"拿到文件夹外面"** ——
			// 这条缝本身有歧义(既可能是"放进 A 的末尾",也可能是"A 和 B 之间的顶层"),
			// 上下位置分不出来,所以按横向位置分。Files / Finder 挪嵌套项目也是这个手感。
			return pointX < outdentThreshold
				? DropResolution(target: .topLevel, isInsertInto: false)
				: DropResolution(target: .enclosingFolder, isInsertInto: false)
		}
	}
}
