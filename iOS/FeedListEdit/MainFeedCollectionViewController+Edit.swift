//
//  MainFeedCollectionViewController+Edit.swift
//  NetNewsWire — AI 翻译 fork
//
//  [编辑] 首页**原地编辑模式**(2026-07-28 用户要求,需求 1 第一步)。
//  本 fork 新增文件,上游没有。
//
//  ## 它取代了什么
//
//  原来点右上角铅笔是**推出一个独立的「编辑订阅」页**。用户反馈那样"要跳一次页,
//  不直觉",希望像 iOS 主屏那样:按一下就地进入编辑模式(行轻微抖动提示可编辑、
//  可多选批量删除),再按一下退出。
//
//  ## 这一步做什么、不做什么
//
//  | 做 | 不做(留给以后) |
//  |---|---|
//  | 原地进出编辑模式、行抖动、勾选圈 | **拖放排序**(风险最高的一块,见下) |
//  | 多选 + 批量删除(接上游的撤销) | 文件夹的新建 / 改名(仍在「编辑订阅」页) |
//  | 多选 + 批量「移动到…」 | |
//
//  **拖放排序为什么这一步不做**:首页的拖动是被显式关掉的,而上游自带的拖放路径
//  **不写我们记的顺序**(`Shared/FeedOrder/`),所以不能靠"把开关打开"白拿;
//  等于要把「编辑订阅」页那场仗(52 个 commit、5 条教训:L65/L66/L87/L88/L89)
//  在首页重打一遍。而顺序**现在就能在「编辑订阅」页里排,首页也已经按它显示**,
//  所以这一步买到的只是"多一个排序入口",性价比最低,放到最后。
//
//  ## ⚠️ 必须一起拆掉的四颗地雷(都是考古时定位到的,别删这些守卫)
//
//  1. **编辑期间禁掉左右滑切档**。切档会重建整棵树 —— 万一将来加了拖放,
//     "拖到一半数据源被换掉"是已知的必崩路径(L65)。现在虽然还没有拖放,
//     但编辑态下横向手势的语义本身就是混乱的(切档?还是拖?),先禁掉。
//  2. **编辑期间禁掉账户分区头的点击**。点它会折叠整个账户 = 中途大批增删行。
//  3. **智能组那一节(今日/星标/全部未读)整节排除**:它们不可删不可移,
//     上游原来的左滑代码里就有同款守卫(`if indexPath.section == 0`)。
//  4. **右上角按钮的安装逻辑靠"第一个是不是放大镜"判断幂等** ——
//     编辑模式换掉按钮会让它失效(退出后重复安装或装不回来)。
//     所以这里改成:进出编辑都由本文件**显式重装**,不再依赖那个判断。
//

#if os(iOS)

import UIKit
import Account
import RSTree
import RSCore

extension MainFeedCollectionViewController {

	// MARK: - 状态

	private static var nnwIsEditingKey: UInt8 = 0
	private static var nnwSavedToolbarKey: UInt8 = 0

	/// 现在是不是处于原地编辑模式。
	var nnwIsEditingFeeds: Bool {
		get { (objc_getAssociatedObject(self, &Self.nnwIsEditingKey) as? Bool) ?? false }
		set { objc_setAssociatedObject(self, &Self.nnwIsEditingKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
	}

	/// 进编辑模式之前的工具栏。退出时原样放回去。
	///
	/// ⚠️ **必须存起来再还原,不能退出时"重新拼一个"** ——
	/// 这一页的工具栏是 [设置][阅读档控件][+],其中阅读档控件是本 fork 装的,
	/// 而上游 `configureToolbarWithProgressView()` 里有一条硬守卫:
	/// **工具栏必须正好 3 项**,否则刷新进度条永远装不上(静默失效)。
	/// 存/还原是唯一能保证"回到进来之前那个样子"的做法。
	private var nnwSavedToolbarItems: [UIBarButtonItem]? {
		get { objc_getAssociatedObject(self, &Self.nnwSavedToolbarKey) as? [UIBarButtonItem] }
		set { objc_setAssociatedObject(self, &Self.nnwSavedToolbarKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
	}

	// MARK: - 进出编辑模式

	/// 右上角铅笔的新行为:切换原地编辑模式。
	@objc func nnwToggleFeedEditing() {
		nnwSetFeedEditing(!nnwIsEditingFeeds)
	}

	func nnwSetFeedEditing(_ editing: Bool) {

		guard nnwIsEditingFeeds != editing, let collectionView else { return }

		nnwIsEditingFeeds = editing

		// ① 多选开关。**进出都要把选中清空**。
		//
		// ⚠️ 进入时也必须清(2026-07-28 审查抓到的严重 bug):
		// 打开某个源之后,那一行本来就是**选中**状态(上游用它高亮"正在看的源")。
		// 一进编辑模式,那一行会被直接算成"已勾选" —— 底部立刻显示「删除(1)」,
		// 而屏幕上没有任何一行看着被勾上。用户按下删除,删掉的是正在读的那个源。
		collectionView.allowsMultipleSelection = editing
		collectionView.indexPathsForSelectedItems?.forEach {
			collectionView.deselectItem(at: $0, animated: false)
		}

		// ② 地雷 1:编辑期间不许左右滑切档
		nnwSetModeSwipeGesturesEnabled(!editing)

		// ③ 地雷 2:编辑期间不许点分区头折叠账户。
		//
		// ⚠️ **守卫只做在上游那个点击处理函数里**,这里什么都不做(2026-07-28 审查结论)。
		// 第一版是在这里逐个把可见的分区头调暗 + 禁掉交互,结果会**永久残留**:
		// 分区头是复用视图,而上游的 supplementaryViewProvider 从不重置 alpha /
		// isUserInteractionEnabled —— 把一个调暗的头滚出屏幕再退出编辑,它就再也
		// 恢复不了,那个账户从此折叠不了。cell 那边有 `configure` 每次兜底,头这边没有。

		// ④ 导航栏 / 工具栏
		nnwUpdateEditingChrome()

		// ⑤ 把装饰套到**当前可见的每一行**上(带动画,这是用户按下按钮那一下)
		nnwRefreshAllVisibleDecor(animated: true)

		// ⑥ 切后台再回来时,系统会把 layer 上的动画清掉 —— 回来时补一次,不然编辑模式开着却不抖了
		nnwObserveForegroundForJiggle(editing)
	}

	/// 把编辑装饰重新套一遍当前可见的所有行。
	/// 列表被重建 / 重新配置之后也要调一次,否则会出现"行被选中、圈却是空的"。
	func nnwRefreshAllVisibleDecor(animated: Bool) {
		guard let collectionView else { return }
		let selected = Set(collectionView.indexPathsForSelectedItems ?? [])
		for indexPath in collectionView.indexPathsForVisibleItems {
			guard let cell = collectionView.cellForItem(at: indexPath) else { continue }
			let editable = nnwIsEditingFeeds && nnwIsEditableRow(indexPath)
			cell.nnwApplyEditDecor(editing: editable,
								   selected: selected.contains(indexPath),
								   animated: animated)
			if editable { cell.nnwStartJiggle() } else { cell.nnwStopJiggle() }
		}
	}

	private func nnwObserveForegroundForJiggle(_ editing: Bool) {
		NotificationCenter.default.removeObserver(self, name: UIApplication.didBecomeActiveNotification, object: nil)
		guard editing else { return }
		NotificationCenter.default.addObserver(self, selector: #selector(nnwRestartJiggleAfterForeground),
											   name: UIApplication.didBecomeActiveNotification, object: nil)
	}

	@objc private func nnwRestartJiggleAfterForeground() {
		guard nnwIsEditingFeeds else { return }
		nnwRefreshAllVisibleDecor(animated: false)
	}

	/// 由上游 `configure(_:sidebarItemNode:)` 里加的一行调用 ——
	/// **滚动中新出现的行也要带上装饰**,否则滚下去就"掉出"了编辑模式的样子。
	///
	/// 这里不加动画:新行是滑进来的,再来一段动画会看到它自己抖一下。
	@objc func nnwDecorateCellForEditing(_ cell: UICollectionViewCell, at indexPath: IndexPath) {
		let editable = nnwIsEditingFeeds && nnwIsEditableRow(indexPath)
		let selected = collectionView?.indexPathsForSelectedItems?.contains(indexPath) ?? false
		cell.nnwApplyEditDecor(editing: editable, selected: selected, animated: false)
		if editable { cell.nnwStartJiggle() } else { cell.nnwStopJiggle() }
	}

	/// 地雷 3:第 0 节是智能组(今日 / 全部未读 / 已加星标),它们不可删不可移,不参与编辑。
	func nnwIsEditableRow(_ indexPath: IndexPath) -> Bool {
		return indexPath.section != 0
	}

	// MARK: - 选中变化(由上游的 didSelect / didDeselect 里各加一行调用)

	/// 编辑模式下点一行 = 勾选,**不是**进入那个源。
	/// 返回 true 表示"这一下我已经处理掉了,上游别再往下走"。
	@objc func nnwHandleSelectionWhileEditing(at indexPath: IndexPath) -> Bool {

		guard nnwIsEditingFeeds else { return false }

		guard nnwIsEditableRow(indexPath) else {
			// 智能组那几行:编辑态下点了不该有反应,顺手把选中取消掉
			collectionView?.deselectItem(at: indexPath, animated: false)
			return true
		}

		nnwRefreshDecor(at: indexPath)
		nnwUpdateEditingChrome()
		return true
	}

	@objc func nnwHandleDeselectionWhileEditing(at indexPath: IndexPath) {
		guard nnwIsEditingFeeds else { return }
		nnwRefreshDecor(at: indexPath)
		nnwUpdateEditingChrome()
	}

	private func nnwRefreshDecor(at indexPath: IndexPath) {
		guard let cell = collectionView?.cellForItem(at: indexPath) else { return }
		let selected = collectionView?.indexPathsForSelectedItems?.contains(indexPath) ?? false
		cell.nnwApplyEditDecor(editing: true, selected: selected, animated: false)
	}

	// MARK: - 导航栏与工具栏

	private func nnwUpdateEditingChrome() {

		if nnwIsEditingFeeds {

			// 右上角:换成「完成」。左上角原本没东西,不用动。
			let done = UIBarButtonItem(title: "完成", style: .done,
									   target: self, action: #selector(nnwToggleFeedEditing))
			navigationItem.rightBarButtonItems = [done]

			// 工具栏:存好原样,换成 [移动到…] ⟷ [删除]
			if nnwSavedToolbarItems == nil {
				nnwSavedToolbarItems = toolbarItems
			}
			let count = nnwSelectedNodes().count
			let move = UIBarButtonItem(title: "移动到…", style: .plain,
									   target: self, action: #selector(nnwMoveSelectedTapped))
			let delete = UIBarButtonItem(title: count > 0 ? "删除(\(count))" : "删除",
										 style: .plain, target: self, action: #selector(nnwDeleteSelectedTapped))
			delete.tintColor = .systemRed
			move.isEnabled = count > 0
			delete.isEnabled = count > 0
			toolbarItems = [move, .flexibleSpace(), delete]

		} else {

			// 还原工具栏(见 nnwSavedToolbarItems 的注释:必须还原,不能重拼)
			if let saved = nnwSavedToolbarItems {
				toolbarItems = saved
				nnwSavedToolbarItems = nil
			}
			// 地雷 4:右上角显式重装,不依赖那个"第一个是不是放大镜"的幂等判断
			nnwReinstallDefaultRightBarButtons()
		}
	}

	// MARK: - 批量操作

	/// 当前勾选的那些行对应的树节点。
	///
	/// 首页的 item 本来就是**真的树节点**(带 parent),所以这里比「编辑订阅」页省事得多 ——
	/// 那边要先把自己的值类型 Item 还原成 Node,这里直接拿。
	func nnwSelectedNodes() -> [Node] {
		guard let collectionView, let dataSource else { return [] }
		let paths = collectionView.indexPathsForSelectedItems ?? []
		let nodes = paths
			.filter { nnwIsEditableRow($0) }
			.compactMap { dataSource.itemIdentifier(for: $0)?.node }
		return nnwNormalized(nodes)
	}

	/// 父子同时被勾中时,**只留父**(把已经被祖先覆盖掉的节点剔掉)。
	///
	/// ⚠️ 为什么非做不可(2026-07-28 审查抓到):勾了一个文件夹、又勾了它里面的某个源,
	/// 删除本身不会出错,但**撤销时会出错** —— 还原那个源时它的文件夹已经没了,
	/// 上游会**新建一个同名文件夹**把它放回去;紧接着还原文件夹又把原来那个放回来。
	/// 结果是两个同名文件夹、同一个源出现两次。
	/// 上游 macOS 端正是为此在建删除命令前先做一次归一化,这里照做。
	private func nnwNormalized(_ nodes: [Node]) -> [Node] {
		let all = Set(nodes.map { ObjectIdentifier($0) })
		return nodes.filter { node in
			var parent = node.parent
			while let current = parent {
				if all.contains(ObjectIdentifier(current)) { return false }	// 祖先也被勾了 → 丢掉自己
				parent = current.parent
			}
			return true
		}
	}

	@objc private func nnwDeleteSelectedTapped() {

		let nodes = nnwSelectedNodes()
		guard !nodes.isEmpty else { return }

		let folders = nodes.compactMap { $0.representedObject as? Folder }
		let feedCount = nodes.filter { $0.representedObject is Feed }.count

		// 选中里含文件夹 → 要先问"里面的源怎么办"(和「编辑订阅」页同一套话术)
		if let folder = folders.first, folders.count == 1, nodes.count == 1 {
			nnwAskHowToDeleteFolder(folder, node: nodes[0])
			return
		}

		let what: String
		if folders.isEmpty {
			what = "这 \(feedCount) 个订阅源"
		} else {
			what = "选中的 \(nodes.count) 项(含 \(folders.count) 个文件夹,文件夹里的源会一并删除)"
		}
		nnwConfirmDelete(message: "确定删除\(what)吗?", nodes: nodes)
	}

	/// 删单个文件夹时给两条路:把里面的源放到顶层,或者连里面的源一起删。
	/// (这是用户 2026-07-23 拍板的设计,「编辑订阅」页里也是这么做的。)
	private func nnwAskHowToDeleteFolder(_ folder: Folder, node: Node) {

		let inside = folder.topLevelFeeds.count
		guard inside > 0 else {
			nnwConfirmDelete(message: "确定删除文件夹「\(folder.nameForDisplay)」吗?", nodes: [node])
			return
		}

		let alert = UIAlertController(
			title: "删除文件夹「\(folder.nameForDisplay)」",
			message: "里面还有 \(inside) 个订阅源,要怎么处理?",
			preferredStyle: .actionSheet)

		alert.addAction(UIAlertAction(title: "把源移到最外层,只删文件夹", style: .default) { [weak self] _ in
			self?.nnwReleaseFeedsThenDelete(folder: folder, node: node)
		})
		alert.addAction(UIAlertAction(title: "连里面的源一起删", style: .destructive) { [weak self] _ in
			self?.nnwPerformDelete(nodes: [node])
		})
		alert.addAction(UIAlertAction(title: "取消", style: .cancel))
		nnwPresentSheet(alert)
	}

	/// 先把源搬到账户顶层,搬完再删空文件夹。
	///
	/// ⚠️ **故意串行搬**(照抄「编辑订阅」页的做法,理由写在那边):
	/// 它们改的是同一批容器,并发搬容易互相踩;同步账户下每次是一个网络请求,
	/// 串行还能避免把对方服务器打出限流。
	private func nnwReleaseFeedsThenDelete(folder: Folder, node: Node) {

		guard let account = folder.account else { return }
		let feeds = Array(folder.topLevelFeeds)

		Task { @MainActor [weak self] in
			var failed = [String]()
			for feed in feeds {
				do {
					try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
						account.moveFeed(feed, from: folder, to: account) { result in
							continuation.resume(with: result)
						}
					}
				} catch {
					failed.append(feed.nameForDisplay)
				}
			}

			// ⚠️ **有一个没搬出来就别删**(2026-07-28 审查抓到):
			// 删文件夹会把里面剩下的源一并带走 —— 用户选的明明是"保留这些源",
			// 结果一次网络失败就把它们删了。「编辑订阅」页也是这么防的。
			guard failed.isEmpty else {
				let alert = UIAlertController(
					title: "没有删除这个文件夹",
					message: "有 \(failed.count) 个订阅源没能移出去(\(failed.prefix(3).joined(separator: "、"))),"
						+ "所以文件夹保留着 —— 免得连它们一起删掉。请稍后再试。",
					preferredStyle: .alert)
				alert.addAction(UIAlertAction(title: "知道了", style: .default))
				self?.present(alert, animated: true)
				return
			}

			self?.nnwPerformDelete(nodes: [node])
		}
	}

	private func nnwConfirmDelete(message: String, nodes: [Node]) {
		let alert = UIAlertController(title: nil, message: message, preferredStyle: .actionSheet)
		alert.addAction(UIAlertAction(title: "删除", style: .destructive) { [weak self] _ in
			self?.nnwPerformDelete(nodes: nodes)
		})
		alert.addAction(UIAlertAction(title: "取消", style: .cancel))
		nnwPresentSheet(alert)
	}

	/// 真正下删除命令。**用上游的 `DeleteCommand`** —— 它本来就支持一次传多个节点,
	/// 而且自带 UndoManager,于是"摇一摇撤销"是白拿的(用户 2026-07-23 拍板的第 3 条)。
	private func nnwPerformDelete(nodes: [Node]) {

		guard let undoManager,
			  let command = DeleteCommand(nodesToDelete: nodes,
										  undoManager: undoManager,
										  errorHandler: ErrorHandler.present(self)) else { return }

		for node in nodes {
			if let folder = node.representedObject as? Folder {
				ActivityManager.cleanUp(folder)
			} else if let feed = node.representedObject as? Feed {
				ActivityManager.cleanUp(feed)
			}
		}

		// 删掉的可能正是当前正在看的那个源 —— 先把选中清掉,免得文章列表指着一个不存在的东西
		if let current = coordinator.currentFeedIndexPath,
		   let currentNode = dataSource?.itemIdentifier(for: current)?.node,
		   nodes.contains(where: { $0 === currentNode }) {
			coordinator.selectSidebarItem(indexPath: nil)
		}

		pushUndoableCommand(command)
		command.perform()

		nnwSetFeedEditing(false)		// 删完直接退出编辑模式,和 iOS 主屏一致
	}

	// MARK: - 移动到…

	@objc private func nnwMoveSelectedTapped() {

		// 连**父节点**一起记下来 —— 首页的行是真的树节点,父节点就是它现在所在的容器,
		// 不用像「编辑订阅」页那样从 folderID 反查(那边的 item 是值类型,拿不到父子关系)。
		let moving: [(feed: Feed, source: Container)] = nnwSelectedNodes().compactMap { node in
			guard let feed = node.representedObject as? Feed,
				  let source = node.parent?.representedObject as? Container else { return nil }
			return (feed, source)
		}
		// ⑫ 只勾了文件夹的情形:文件夹没有"移动到"可言(上游模型不支持子文件夹),
		// 但按钮是亮的 —— 得给个说法,不能默默没反应。
		guard !moving.isEmpty else {
			nnwInform(title: "没有可移动的订阅源",
					  message: "文件夹不能移动到别的文件夹里(这个 app 只有两层:账户 → 文件夹 → 源)。请勾选订阅源。")
			return
		}

		// ⚠️ **只在同一个账户内部移动**(2026-07-28 审查抓到的严重 bug)。
		//
		// 第一版把所有账户的文件夹都列了出来,然后统一用「目标账户.moveFeed」搬 ——
		// 而上游对跨账户是**另一条路**(先在目标账户新建、成功后再从源账户删除)。
		// 用错的话:本机账户会出现"源显示在 B 账户下、文章却来自 A"的错乱;
		// 同步账户则会拿一个不属于它的 ID 去请求,报错被吞掉、**静默什么也没发生**。
		// 跨账户搬家不在这一步的范围内,先老老实实挡掉。
		let accounts = Set(moving.compactMap { $0.feed.account?.accountID })
		guard accounts.count == 1, let account = moving.first?.feed.account else {
			nnwInform(title: "不能跨账户移动",
					  message: "这次勾选的订阅源分属不同账户。请分开操作,一次只移动同一个账户里的源。")
			return
		}

		let alert = UIAlertController(title: "把 \(moving.count) 个订阅源移动到…",
									  message: account.nameForDisplay, preferredStyle: .actionSheet)

		alert.addAction(UIAlertAction(title: "最外层(不放进文件夹)", style: .default) { [weak self] _ in
			self?.nnwMove(moving, to: account, in: account)
		})
		for folder in (account.folders ?? []).sorted(by: { $0.nameForDisplay < $1.nameForDisplay }) {
			alert.addAction(UIAlertAction(title: folder.nameForDisplay, style: .default) { [weak self] _ in
				self?.nnwMove(moving, to: folder, in: account)
			})
		}
		alert.addAction(UIAlertAction(title: "取消", style: .cancel))
		nnwPresentSheet(alert)
	}

	private func nnwInform(title: String, message: String) {
		let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
		alert.addAction(UIAlertAction(title: "知道了", style: .default))
		present(alert, animated: true)
	}

	/// 逐个搬,**故意串行**(理由同 `nnwReleaseFeedsThenDelete`)。
	private func nnwMove(_ moving: [(feed: Feed, source: Container)],
						 to destination: Container, in account: Account) {

		Task { @MainActor [weak self] in
			for (feed, source) in moving {
				guard source !== destination else { continue }
				try? await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
					account.moveFeed(feed, from: source, to: destination) { result in
						continuation.resume(with: result)
					}
				}
			}
			// 菜单式的「移动到…」没有"落在第几位"的概念 —— 把旧的排序位置忘掉,
			// 让它按名字落到新容器末尾。不忘的话会带着在旧文件夹里的位置回来,看着莫名其妙。
			FeedOrderStore.shared.forgetOrder(forFeedIDs: moving.map { $0.feed.feedID })
			self?.nnwSetFeedEditing(false)
		}
	}

	// MARK: - 小工具

	/// iPad 上 actionSheet 必须有锚点,否则会崩。锚在工具栏上。
	private func nnwPresentSheet(_ alert: UIAlertController) {
		if let popover = alert.popoverPresentationController {
			popover.sourceView = view
			popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.maxY - 60, width: 1, height: 1)
			popover.permittedArrowDirections = []
		}
		present(alert, animated: true)
	}
}

#endif
