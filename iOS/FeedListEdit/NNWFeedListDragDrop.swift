//
//  NNWFeedListDragDrop.swift
//  首页编辑模式下的拖放整理
//
//  [编辑] 本 fork 新增文件,上游不存在。需求 1 第二步(2026-07-28)。
//
//  ## 能做什么
//
//  **只在编辑模式下生效**(点铅笔进入之后)。拖一个源或文件夹:
//  · 在同一层里换位置 → 存进 `FeedOrderStore`,首页立刻按新顺序显示
//  · 把源拖到文件夹上 → 放进那个文件夹(那一行会高亮)
//  · 把文件夹里的源往**左**拖出缩进线 → 拿到最外层
//  · 文件夹只能换位置(上游模型不支持子文件夹,它没有别的地方可去)
//
//  ## 为什么不打开上游那套拖放
//
//  首页本来就挂着上游的 `+Drag.swift` / `+Drop.swift`,只是
//  `dragInteractionEnabled = false` 把它关着。但**不能只把那个开关打开**:
//  上游的落点逻辑只调 `moveFeed` 换容器,**完全不写我们记的顺序**
//  (`Shared/FeedOrder/`)—— 搬完位置会莫名其妙。
//  所以这里另起一个对象接管两个代理,上游那两个文件保持原样、继续当死代码
//  (将来合并上游时零冲突)。
//
//  ## ⚠️ 五条用血换来的规矩(当年在「编辑订阅」页 52 个 commit 踩出来的,一条都别省)
//
//  1. **拖动全程绝不改数据源**(L65)。UIKit 会在列表里插一个"占位缝",
//     它不在我们的数据快照里 —— 这时 apply 新快照会撞批量更新校验、**直接崩**。
//     所以拖动期间要**冻结列表重画**,攒下的变化等拖完再补。
//     (当年的元凶是"悬停自动展开文件夹",那个机制已被永久删除,**别再加回来**。)
//  2. **冻结要盖住拖拽的两端**(L88)。开始得早于会话正式建立(长按抬起那一小段
//     空窗期);结束要晚于放下动画飞完(否则系统的"归位"动画会追着被换掉的 cell
//     追锚几十秒 —— 用户报过"卡死")。
//  3. **别拿行号跨界查询**(L89)。占位缝占着一个行号,从它往下"布局的行号"和
//     "数据里的行号"全部错开一位。所以锚行靠 cell 上的**钢印**认人,不靠 index path。
//  4. **放手时用悬停最后一次的判定,不重算**(L87)。松手瞬间 UIKit 会把缝合拢、
//     行弹回原位,同一个坐标对上弹回后的行框结论会翻(预告"排旁边"、实际落进文件夹)。
//     **例外**:"往左拖出文件夹"这条规则只看手指的横向位置,不受纵向合拢影响,
//     那一条要用松手瞬间的活数据(否则往左拉的最后一段路会被缓存冻掉)。
//  5. **落点判定用纯逻辑文件**(`DropZoneResolver`),它有离线仿真;
//     插入算术也一样(`NNWFeedOrderMath` + `tools/sim-feedorder.swift`)。
//     改了规则**必须重跑那两个脚本**。
//

#if os(iOS)

import UIKit
import Account
import RSTree
import os

@MainActor
final class NNWFeedListDragDrop: NSObject {

	private weak var host: MainFeedCollectionViewController?

	/// 悬停时最后一次的判定 —— 放手时用的就是它(规矩 4)。
	fileprivate var lastHoverDecision: Decision?

	/// 当前被高亮成"松手会放进这里"的那个文件夹节点。
	private var highlightedFolderNode: Node?

	/// 本次冻结的代次(见 host 那边 `nnwDragGeneration` 的注释)。
	private var freezeGeneration = 0

	static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "app", category: "首页拖放")

	init(host: MainFeedCollectionViewController) {
		self.host = host
	}

	/// 一次落点判定的完整结论。
	fileprivate struct Decision {
		let container: Container
		let account: Account
		let resolution: DropResolution
		/// 锚行(落点归属的那一行)。**存节点,不存行号**(规矩 3)。
		let anchorNode: Node
	}
}

// MARK: - cell 钢印(规矩 3:锚行按它认人,不靠行号)

extension UICollectionViewCell {

	private static var nnwStampedNodeKey: UInt8 = 0

	/// 这张 cell 此刻代表哪个节点。在配置行时盖上;
	/// cell 被挤到哪、行号怎么错位,它代表谁都不变。
	var nnwStampedNode: Node? {
		get { objc_getAssociatedObject(self, &Self.nnwStampedNodeKey) as? Node }
		set { objc_setAssociatedObject(self, &Self.nnwStampedNodeKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
	}
}

// MARK: - 拖起来

extension NNWFeedListDragDrop: UICollectionViewDragDelegate {

	func collectionView(_ collectionView: UICollectionView,
						itemsForBeginning session: UIDragSession,
						at indexPath: IndexPath) -> [UIDragItem] {

		guard let host, host.nnwIsEditingFeeds else { return [] }
		// 智能组那一节不参与编辑,也就不能拖
		guard host.nnwIsEditableRow(indexPath) else { return [] }
		guard let node = host.dataSource?.itemIdentifier(for: indexPath)?.node else { return [] }

		// 规矩 2:冻结要从**这里**就开始,不能等 dragSessionWillBegin ——
		// 长按抬起动画期间有一小段空窗,后台通知的整棵重画若落在这一段,
		// 抬起中的 cell 被换掉,拖拽机器当场迷路。
		freezeGeneration = host.nnwBeginDragFreeze()

		// ⚠️ 看门狗:长按抬起之后用户**不动就松手**时,UIKit 不保证还会来
		// dragSessionWillBegin / dragSessionDidEnd —— 没有这个兜底,冻结会永远停在开着,
		// 表现是"整个首页不再刷新、文件夹再也展不开"(2026-07-28 审查抓到)。
		let generation = freezeGeneration
		Task { @MainActor [weak self] in
			try? await Task.sleep(for: .seconds(6))
			guard let self, self.freezeGeneration == generation else { return }
			self.host?.nnwEndDragFreeze(generation: generation)
		}

		let name = (node.representedObject as? SidebarItem)?.nameForDisplay ?? "订阅源"
		let item = UIDragItem(itemProvider: NSItemProvider(object: name as NSString))
		// 真正靠的是 localObject(放手后按它找回拖的是谁);上面那个文字只是为了拖动时有预览
		item.localObject = node
		return [item]
	}

	func collectionView(_ collectionView: UICollectionView, dragSessionWillBegin session: UIDragSession) {
		freezeGeneration = host?.nnwBeginDragFreeze() ?? 0
	}

	func collectionView(_ collectionView: UICollectionView, dragSessionDidEnd session: UIDragSession) {
		// 规矩 2:别立刻解冻 —— 放下动画还要飞几百毫秒,现在重画会把它的目标抽走
		let generation = freezeGeneration
		Task { @MainActor [weak self] in
			try? await Task.sleep(for: .seconds(0.6))
			self?.host?.nnwEndDragFreeze(generation: generation)
		}
	}
}

// MARK: - 放下去

extension NNWFeedListDragDrop: UICollectionViewDropDelegate {

	func collectionView(_ collectionView: UICollectionView,
						dropSessionDidUpdate session: UIDropSession,
						withDestinationIndexPath destinationIndexPath: IndexPath?) -> UICollectionViewDropProposal {

		// 只接受本页面内部拖的东西(从别的 app 拖文字进来没有意义)
		guard session.localDragSession != nil, let host, host.nnwIsEditingFeeds else {
			return UICollectionViewDropProposal(operation: .cancel)
		}

		let point = session.location(in: collectionView)
		let draggingFolder = draggedNodes(session.localDragSession)
			.contains { $0.representedObject is Folder }

		guard let decision = decide(at: point, draggingFolder: draggingFolder) else {
			highlight(nil)
			lastHoverDecision = nil
			return UICollectionViewDropProposal(operation: .forbidden)
		}

		// 让"松手会进这个文件夹"看得见。高亮和落点意图**出自同一个 decision**,
		// 所以看到的和放手的结果必然一致。
		highlight(decision.resolution.target == .anchorFolder ? decision.anchorNode : nil)
		lastHoverDecision = decision

		return UICollectionViewDropProposal(
			operation: .move,
			intent: decision.resolution.isInsertInto ? .insertIntoDestinationIndexPath
													 : .insertAtDestinationIndexPath)
	}

	func collectionView(_ collectionView: UICollectionView, dropSessionDidExit session: UIDropSession) {
		highlight(nil)
		lastHoverDecision = nil		// 出了列表再回来会立刻给一份新的;不清的话在外面松手会用旧账
	}

	func collectionView(_ collectionView: UICollectionView, dropSessionDidEnd session: UIDropSession) {
		highlight(nil)
		lastHoverDecision = nil
	}

	func collectionView(_ collectionView: UICollectionView, performDropWith coordinator: UICollectionViewDropCoordinator) {

		highlight(nil)

		guard let host else { return }

		let movingNodes = coordinator.items.compactMap { $0.dragItem.localObject as? Node }
		guard !movingNodes.isEmpty else { return }

		let point = coordinator.session.location(in: collectionView)
		let draggingFolder = movingNodes.contains { $0.representedObject is Folder }

		// 规矩 4:优先用悬停时最后一次的判定,不在放手瞬间重算。
		guard var decision = lastHoverDecision ?? decide(at: point, draggingFolder: draggingFolder) else { return }

		// 规矩 4 的例外:"往左拖出文件夹"只看手指横向位置,不受纵向合拢影响 ——
		// 这一条要用松手瞬间的活数据,否则往左拉的最后一段路会被缓存冻掉。
		if !draggingFolder, anchorKind(of: decision.anchorNode) == .nestedFeed {
			let live = DropZoneResolver.resolve(anchor: .nestedFeed, band: .middle,
												pointX: point.x, draggingFolder: false)
			if live.target != decision.resolution.target,
			   let container = container(for: live.target, anchorNode: decision.anchorNode, account: decision.account) {
				decision = Decision(container: container, account: decision.account,
									resolution: live, anchorNode: decision.anchorNode)
			}
		}

		Self.logger.info("放手:目标容器=\((decision.container as? Folder)?.nameForDisplay ?? "最外层", privacy: .public) 拖了\(movingNodes.count, privacy: .public)项 x=\(Int(point.x), privacy: .public)")

		host.nnwApplyDrop(movingNodes: movingNodes,
						  to: decision.container,
						  in: decision.account,
						  anchorNode: decision.anchorNode,
						  dropPoint: point)
	}
}

// MARK: - 判定

private extension NNWFeedListDragDrop {

	func draggedNodes(_ session: UIDragSession?) -> [Node] {
		session?.items.compactMap { $0.localObject as? Node } ?? []
	}

	/// 手指落在这个位置 → 该放进哪个容器。
	func decide(at point: CGPoint, draggingFolder: Bool) -> Decision? {

		guard let row = anchorRow(nearestTo: point),
			  let account = account(of: row.node) else { return nil }

		let resolution = DropZoneResolver.resolve(
			anchor: anchorKind(of: row.node),
			band: DropZoneResolver.band(of: point, in: row.frame),
			pointX: point.x,
			draggingFolder: draggingFolder)

		guard let container = container(for: resolution.target, anchorNode: row.node, account: account) else { return nil }

		return Decision(container: container, account: account, resolution: resolution, anchorNode: row.node)
	}

	func container(for target: DropTarget, anchorNode: Node, account: Account) -> Container? {
		switch target {
		case .topLevel:
			return account
		case .anchorFolder:				// 放进**落点那一行**的那个文件夹
			return anchorNode.representedObject as? Folder
		case .enclosingFolder:			// 落点是文件夹里的某个源 → 放进它所在的那个文件夹
			return anchorNode.parent?.representedObject as? Folder
		}
	}

	/// 落点那一行是个什么东西。
	///
	/// 首页这里比「编辑订阅」页省事得多:行本来就是**真的树节点**,
	/// 是不是"文件夹里的源"直接看父节点即可,不用从 folderID 反查。
	func anchorKind(of node: Node) -> DropAnchorKind {
		if node.representedObject is Folder {
			let expanded = host?.coordinator?.isExpanded(node) ?? false
			return .folder(expanded: expanded)
		}
		return node.parent?.representedObject is Folder ? .nestedFeed : .looseFeed
	}

	/// 这个节点属于哪个账户(顺着父链往上找)。
	func account(of node: Node) -> Account? {
		var current: Node? = node
		while let n = current {
			if let account = n.representedObject as? Account { return account }
			current = n.parent
		}
		// 智能组之外的行,父链顶端一定是账户节点;走到这儿说明结构变了
		return (node.representedObject as? Feed)?.account
			?? (node.representedObject as? Folder)?.account
	}

	/// 找落点归属的那一行。**落在空白处也不算失败** —— 取它上方最近的一行。
	///
	/// 规矩 3:只认 cell 上的钢印,不用 `indexPathForItem` ——
	/// 拖动中占位缝占着一个行号,拿行号查会查到错的行。
	func anchorRow(nearestTo point: CGPoint) -> (node: Node, frame: CGRect)? {

		guard let collectionView = host?.collectionView else { return nil }

		var best: (node: Node, frame: CGRect)?
		var bestBottom = -CGFloat.greatestFiniteMagnitude
		var below: (node: Node, frame: CGRect)?
		var belowTop = CGFloat.greatestFiniteMagnitude

		for cell in collectionView.visibleCells {
			// 正在被拖的那张 cell 被 UIKit 藏着 —— 别拿它当锚
			guard !cell.isHidden, let node = cell.nnwStampedNode else { continue }
			let frame = cell.frame
			if frame.contains(point) { return (node, frame) }		// 正压着这一行
			if frame.maxY <= point.y, frame.maxY > bestBottom {		// 否则取上方最近的一行
				bestBottom = frame.maxY
				best = (node, frame)
			}
			if frame.minY >= point.y, frame.minY < belowTop {
				belowTop = frame.minY
				below = (node, frame)
			}
		}
		if let best { return best }
		// 落在所有内容**上方**(第一行头顶、分组头那片):取下方最近的一行当锚 ——
		// point 在它上面,band 会算成 .top,正好是"插到这一行前面",于是能放到首位。
		return below
	}

	/// 给"松手会放进去"的那个文件夹加高亮。
	///
	/// ⚠️ 这里**只改已经存在的那一行的外观**,不增删行、不动数据源 ——
	/// 所以不受规矩 1 的限制。这也是为什么落点提示能做、而"悬停自动展开"做不了:
	/// 一个只是换颜色,另一个要增删行。
	func highlight(_ node: Node?) {

		guard highlightedFolderNode !== node else { return }
		let previous = highlightedFolderNode
		highlightedFolderNode = node

		guard let collectionView = host?.collectionView else { return }
		for cell in collectionView.visibleCells {
			guard let stamped = cell.nnwStampedNode else { continue }
			if stamped === previous || stamped === node {
				cell.nnwSetDropTargetHighlighted(stamped === node)
			}
		}
	}
}

// MARK: - 落点高亮的外观

extension UICollectionViewCell {

	private static var nnwDropHighlightKey: UInt8 = 0

	/// 把这一行画成"松手就放进这里"的样子。
	/// 只改一层浮在底下的色块,不碰 cell 自己的 backgroundConfiguration ——
	/// 后者会被上游的 `updateConfiguration(using:)` 在任意时刻重算,我们写了也留不住。
	func nnwSetDropTargetHighlighted(_ highlighted: Bool) {

		if let existing = objc_getAssociatedObject(self, &Self.nnwDropHighlightKey) as? UIView {
			existing.isHidden = !highlighted
			return
		}
		guard highlighted else { return }

		let overlay = UIView()
		overlay.translatesAutoresizingMaskIntoConstraints = false
		overlay.backgroundColor = Assets.Colors.primaryAccent.withAlphaComponent(0.22)
		overlay.layer.cornerRadius = 8
		overlay.isUserInteractionEnabled = false
		// ⚠️ 插在 **contentView 底下**,不是"所有子视图的最底层"(2026-07-28 审查抓到):
		// cell 的背景视图也在 contentView 之下,而它在 iPhone 上是**不透明的纸色**,
		// 插到最底层会被它整个压住 —— 高亮根本看不见。
		insertSubview(overlay, belowSubview: contentView)
		NSLayoutConstraint.activate([
			overlay.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
			overlay.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
			overlay.topAnchor.constraint(equalTo: topAnchor, constant: 2),
			overlay.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
		])
		objc_setAssociatedObject(self, &Self.nnwDropHighlightKey, overlay, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
	}
}

#endif
