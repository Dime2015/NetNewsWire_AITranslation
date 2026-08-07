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
//  | 原地进出编辑模式、行抖动、勾选圈 | (2026-07-30 起没有"留给以后"的了: |
//  | 多选 + 批量删除(接上游的撤销) |  拖放排序、行尾⋯改名、新建文件夹 |
//  | 多选 + 批量「移动到…」、新建文件夹 |  都已并入本模式,旧「编辑订阅」页已删) |
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
	private static var nnwSelectionKey: UInt8 = 0

	/// 编辑模式下勾选了哪几行。
	///
	/// ## ⚠️ 为什么**按节点记**,而不用系统的"选中了第几行"(2026-07-28 重写)
	///
	/// 第一版直接用 `collectionView.indexPathsForSelectedItems` 当账本 —— 那是**按行号记的**,
	/// 而这一页的行号随时会变:
	/// · 折叠一个文件夹 → 里面的行整批消失,**勾选静默丢掉**(你以为还勾着,一点删除就少删)
	/// · 后台同步刷新列表、切换字号重画 → 同样会丢
	/// · 底部「删除(N)」的 N 也跟着变陈旧
	///
	/// 改成记**节点本身**之后,这些全都不成立了:行号怎么变、行在不在屏幕上、
	/// 甚至被折叠起来看不见,勾选都还在。节点对象在列表重建时是复用的(不会换新对象),
	/// 所以拿它当身份是稳的。
	private var nnwSelectionBox: NNWNodeSelectionBox {
		if let existing = objc_getAssociatedObject(self, &Self.nnwSelectionKey) as? NNWNodeSelectionBox {
			return existing
		}
		let created = NNWNodeSelectionBox()
		objc_setAssociatedObject(self, &Self.nnwSelectionKey, created, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
		return created
	}

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

		// ① 清空勾选账本。
		//
		// ⚠️ **不再借用系统的"选中了第几行"**(见 nnwSelectionBox 的注释):
		// 那样一来"打开某个源"的高亮会被当成"已勾选"(底部立刻显示「删除(1)」
		// 而屏幕上没有一行看着被勾),折叠文件夹还会把勾选静默丢掉。
		// 现在勾选完全由我们自己记,系统的选中状态只用来做"正在看哪个源"的高亮。
		nnwSelectionBox.nodes.removeAll()

		// 进编辑时把系统那个高亮也撤掉,免得和我们的勾选圈看起来混在一起
		if editing {
			collectionView.indexPathsForSelectedItems?.forEach {
				collectionView.deselectItem(at: $0, animated: false)
			}
		}

		// ② 地雷 1:编辑期间不许左右滑切档。
		// 现在有了拖放,这一条更要紧了:切档会**重建整棵树**,而拖动途中改数据源必崩(L65)。
		nnwSetModeSwipeGesturesEnabled(!editing)

		// ②b 拖放只在编辑模式下开
		nnwSetDragDropEnabled(editing)

		// 退出编辑时**强制解冻**:万一某次长按抬起后用户没动就松手、
		// UIKit 没来收尾回调,冻结会卡在开着(整个首页不再刷新)。这里兜一道底。
		if !editing { nnwEndDragFreeze(generation: nil) }

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
		for indexPath in collectionView.indexPathsForVisibleItems {
			guard let cell = collectionView.cellForItem(at: indexPath) else { continue }
			let editable = nnwIsEditingFeeds && nnwIsEditableRow(indexPath)
			cell.nnwApplyEditDecor(editing: editable,
								   selected: nnwIsChecked(cell.nnwStampedNode),
								   animated: animated,
								   pencilTarget: self,
								   pencilAction: #selector(nnwRowPencilTapped(_:)))
			if editable { cell.nnwStartJiggle() } else { cell.nnwStopJiggle() }
		}
	}

	/// 这个节点勾上了没有。
	func nnwIsChecked(_ node: Node?) -> Bool {
		guard let node else { return false }
		return nnwSelectionBox.nodes.contains { $0 === node }
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

		// 顺手盖钢印:拖放时靠它认"这一行是谁"(不能用行号,理由见 NNWFeedListDragDrop 规矩 3)。
		// 放在这里是因为它对**每一行**都会跑一遍,而且是在配置行的那一刻(行号此时是准的)。
		cell.nnwStampedNode = dataSource?.itemIdentifier(for: indexPath)?.node

		let editable = nnwIsEditingFeeds && nnwIsEditableRow(indexPath)
		cell.nnwApplyEditDecor(editing: editable,
							   selected: nnwIsChecked(cell.nnwStampedNode),
							   animated: false,
							   pencilTarget: self,
							   pencilAction: #selector(nnwRowPencilTapped(_:)))
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

		// 系统的选中我们不用(账本自己记),点完立刻撤掉,免得留下高亮
		collectionView?.deselectItem(at: indexPath, animated: false)

		// 智能组那几行不参与编辑,点了不该有反应
		guard nnwIsEditableRow(indexPath),
			  let node = dataSource?.itemIdentifier(for: indexPath)?.node else { return true }

		if let existing = nnwSelectionBox.nodes.firstIndex(where: { $0 === node }) {
			nnwSelectionBox.nodes.remove(at: existing)
		} else {
			nnwSelectionBox.nodes.append(node)
		}

		nnwRefreshDecor(at: indexPath)
		nnwUpdateEditingChrome()
		return true
	}

	private func nnwRefreshDecor(at indexPath: IndexPath) {
		guard let cell = collectionView?.cellForItem(at: indexPath) else { return }
		cell.nnwApplyEditDecor(editing: true,
							   selected: nnwIsChecked(cell.nnwStampedNode),
							   animated: false,
							   pencilTarget: self,
							   pencilAction: #selector(nnwRowPencilTapped(_:)))
	}

	// MARK: - 导航栏与工具栏

	private func nnwUpdateEditingChrome() {

		// [阅读档] 三档控件 2026-08-05 从工具栏搬成了浮层,不再随 toolbarItems 一起被换掉,
		// 所以进出编辑模式要显式收起 / 放回来(见 NNWFloatingModeBar.swift)。
		nnwSetFloatingModeBarHidden(nnwIsEditingFeeds)

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
			// [编辑] 新建文件夹(2026-07-30,T29 的尾巴):编辑模式补上这最后一件事,
			// 旧「编辑订阅」页(FolderManagerViewController)就完全冗余,已整个删除。
			let newFolder = UIBarButtonItem(title: "新建文件夹", style: .plain,
											target: self, action: #selector(nnwNewFolderTapped))
			let move = UIBarButtonItem(title: "移动到…", style: .plain,
									   target: self, action: #selector(nnwMoveSelectedTapped))
			let delete = UIBarButtonItem(title: count > 0 ? "删除(\(count))" : "删除",
										 style: .plain, target: self, action: #selector(nnwDeleteSelectedTapped))
			delete.tintColor = .systemRed
			move.isEnabled = count > 0
			delete.isEnabled = count > 0
			toolbarItems = [newFolder, .flexibleSpace(), move, .flexibleSpace(), delete]

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

	// MARK: - 新建文件夹(2026-07-30,流程照抄已删除的旧「编辑订阅」页)

	@objc private func nnwNewFolderTapped() {

		let accounts = AccountManager.shared.sortedActiveAccounts
		guard !accounts.isEmpty else { return }

		// 只有一个账户就别多问一步,直接让用户输名字
		guard accounts.count > 1 else {
			nnwPromptNewFolderName(in: accounts[0])
			return
		}

		// 多账户:先问建在哪个账户下(品牌选单,从按钮所在的左下角弹出)
		NNWMenu.show(in: self, anchor: .bottomLeading, title: "在哪个账户下新建?", sections: [
			accounts.map { account in
				NNWMenu.Item(title: account.nameForDisplay, icon: NNWMenu.accountIcon(for: account)) { [weak self] in
					self?.nnwPromptNewFolderName(in: account)
				}
			}
		])
	}

	private func nnwPromptNewFolderName(in account: Account) {

		let alert = UIAlertController(title: "新建文件夹", message: nil, preferredStyle: .alert)
		alert.addTextField { textField in
			textField.placeholder = "文件夹名称"
			textField.autocapitalizationType = .words
			textField.clearButtonMode = .whileEditing
		}
		alert.addAction(UIAlertAction(title: "取消", style: .cancel))

		let createAction = UIAlertAction(title: "新建", style: .default) { [weak self, weak alert] _ in
			let name = (alert?.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
			guard !name.isEmpty else { return }
			self?.nnwCreateFolder(named: name, in: account)
		}
		alert.addAction(createAction)
		alert.preferredAction = createAction
		present(alert, animated: true)
	}

	private func nnwCreateFolder(named name: String, in account: Account) {
		Task { @MainActor in
			do {
				_ = try await account.addFolder(name)
				// 成功后不用手动刷新:上游会发 ChildrenDidChange,列表自己会重建
			} catch {
				presentError(title: "新建文件夹失败", message: error.localizedDescription)
			}
		}
	}

	// MARK: - 批量操作

	/// 当前勾选的那些行对应的树节点。
	///
	/// 首页的 item 本来就是**真的树节点**(带 parent),所以这里比「编辑订阅」页省事得多 ——
	/// 那边要先把自己的值类型 Item 还原成 Node,这里直接拿。
	func nnwSelectedNodes() -> [Node] {
		// 剔掉已经不在树上的(比如被后台同步删掉了)—— 账本按节点记,
		// 它不会自己知道某个源没了,所以取用时校验一次。
		let alive = nnwSelectionBox.nodes.filter { nnwNodeIsAlive($0) }
		if alive.count != nnwSelectionBox.nodes.count {
			nnwSelectionBox.nodes = alive
		}
		return nnwNormalized(alive)
	}

	/// 这个节点还挂在树上吗。
	///
	/// ⚠️ **必须逐级验"父亲认不认这个儿子",不能只顺 `parent` 往上走**
	/// (2026-07-28 审查抓到):`Node.parent` 是弱引用,而"把节点从树上摘下"的动作
	/// 只是父节点**重新赋值了自己的 childNodes** —— **没有任何地方把 parent 置 nil**。
	/// 所以一个已经被摘掉的节点,只要它父亲还活着,顺父链照样能走到根,
	/// 光看父链等于永远判活。表现:后台同步删掉一个源之后,
	/// 底部「删除(N)」的 N 还把它算在内。
	private func nnwNodeIsAlive(_ node: Node) -> Bool {
		guard let root = coordinator?.rootNode else { return false }
		var current: Node = node
		while current !== root {
			guard let parent = current.parent,
				  parent.childNodes.contains(where: { $0 === current }) else { return false }
			current = parent
		}
		return true
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
	func nnwAskHowToDeleteFolderPublic(_ folder: Folder, node: Node) { nnwAskHowToDeleteFolder(folder, node: node) }

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

	func nnwConfirmDeletePublic(message: String, nodes: [Node]) {
		nnwConfirmDelete(message: message, nodes: nodes, exitEditingAfterwards: false)
	}

	private func nnwConfirmDelete(message: String, nodes: [Node], exitEditingAfterwards: Bool = true) {
		let alert = UIAlertController(title: nil, message: message, preferredStyle: .actionSheet)
		alert.addAction(UIAlertAction(title: "删除", style: .destructive) { [weak self] _ in
			self?.nnwPerformDelete(nodes: nodes, exitEditingAfterwards: exitEditingAfterwards)
		})
		alert.addAction(UIAlertAction(title: "取消", style: .cancel))
		nnwPresentSheet(alert)
	}

	/// 真正下删除命令。**用上游的 `DeleteCommand`** —— 它本来就支持一次传多个节点,
	/// 而且自带 UndoManager,于是"摇一摇撤销"是白拿的(用户 2026-07-23 拍板的第 3 条)。
	private func nnwPerformDelete(nodes: [Node], exitEditingAfterwards: Bool = true) {

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

		// 把删掉的这几项从账本里摘掉(它们的节点已经不在树上了)
		nnwSelectionBox.nodes.removeAll { deleted in nodes.contains { $0 === deleted } }

		// 底部那个「删除(N)」是批量操作,删完退出编辑模式(和 iOS 主屏一致);
		// 但**从行尾铅笔删单行时不退** —— 那会顺手把用户已经勾好的一批也清掉(审查抓到)。
		if exitEditingAfterwards {
			nnwSetFeedEditing(false)
		} else {
			nnwRefreshAllVisibleDecor(animated: false)
			nnwUpdateEditingChrome()
		}
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

// MARK: - [编辑] 拖放整理(需求 1 第二步)

extension MainFeedCollectionViewController {

	private static var nnwDragDropKey: UInt8 = 0
	private static var nnwDragFreezeKey: UInt8 = 0
	private static var nnwPendingSnapshotKey: UInt8 = 0
	private static var nnwDragGenKey: UInt8 = 0

	/// 接管两个拖放代理的对象(懒建一次)。
	/// 不用 self 当代理:上游的 `+Drag.swift` / `+Drop.swift` 已经占着那两个协议了,
	/// 而它们的落点逻辑不写我们的顺序 —— 换个对象接管,上游那两个文件保持原样。
	private var nnwDragDrop: NNWFeedListDragDrop {
		if let existing = objc_getAssociatedObject(self, &Self.nnwDragDropKey) as? NNWFeedListDragDrop {
			return existing
		}
		let created = NNWFeedListDragDrop(host: self)
		objc_setAssociatedObject(self, &Self.nnwDragDropKey, created, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
		return created
	}

	/// 拖动进行中 —— 期间**冻结列表重画**(规矩 1、2,见 NNWFeedListDragDrop 文件头)。
	var nnwIsDragInProgress: Bool {
		get { (objc_getAssociatedObject(self, &Self.nnwDragFreezeKey) as? Bool) ?? false }
		set { objc_setAssociatedObject(self, &Self.nnwDragFreezeKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
	}

	/// 冻结期间被挡下来的那次重画(只留最后一次,补画一次就够)。
	private var nnwPendingSnapshotWork: (() -> Void)? {
		get { (objc_getAssociatedObject(self, &Self.nnwPendingSnapshotKey) as? NNWBlockBox)?.block }
		set { objc_setAssociatedObject(self, &Self.nnwPendingSnapshotKey,
									   newValue.map(NNWBlockBox.init), .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
	}

	/// 进出编辑模式时开关拖放。
	func nnwSetDragDropEnabled(_ enabled: Bool) {
		guard let collectionView else { return }
		if enabled {
			collectionView.dragDelegate = nnwDragDrop
			collectionView.dropDelegate = nnwDragDrop
			collectionView.dragInteractionEnabled = true
		} else {
			collectionView.dragInteractionEnabled = false
			// 代理换回上游那两个(它们在 dragInteractionEnabled=false 时不会被调到)
			collectionView.dragDelegate = self
			collectionView.dropDelegate = self
		}
	}

	/// 清空勾选账本并刷新界面。
	func nnwClearSelection() {
		nnwSelectionBox.nodes.removeAll()
		nnwRefreshAllVisibleDecor(animated: false)
		nnwUpdateEditingChrome()
	}

	/// 冻结的"代次"。每次开始拖动 +1;延迟解冻只在代次没变时才生效。
	///
	/// ⚠️ 为什么需要它(2026-07-28 审查抓到的严重 bug):
	/// 解冻是"拖动结束后等 0.6 秒"做的(要等放下动画飞完)。若用户在这 0.6 秒内
	/// **又起了一次拖动**,旧的那个定时器照样会开火 —— 把冻结解掉、
	/// 并把攒下的快照补画出去,而此刻新拖动的占位缝正在列表里 → **必崩**(L65)。
	/// 记一个代次,开火时对不上就什么都不做。
	private var nnwDragGeneration: Int {
		get { (objc_getAssociatedObject(self, &Self.nnwDragGenKey) as? Int) ?? 0 }
		set { objc_setAssociatedObject(self, &Self.nnwDragGenKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
	}

	func nnwBeginDragFreeze() -> Int {
		nnwIsDragInProgress = true
		nnwDragGeneration += 1
		return nnwDragGeneration
	}

	/// - Parameter generation: `nnwBeginDragFreeze()` 当时返回的代次。
	///   传 nil = 强制解冻(退出编辑模式时的兜底)。
	func nnwEndDragFreeze(generation: Int?) {
		if let generation, generation != nnwDragGeneration { return }		// 已经有新一轮拖动了,别插手
		nnwIsDragInProgress = false
		// 把冻结期间攒下的那次重画补上
		let pending = nnwPendingSnapshotWork
		nnwPendingSnapshotWork = nil
		pending?()
	}

	/// 由上游 `applySnapshot` 里加的一行调用。
	/// 返回 true = "现在别画,我先替你记着",拖完再补(规矩 1:拖动途中改数据源会崩)。
	@objc func nnwDeferSnapshotWhileDragging(_ work: @escaping () -> Void) -> Bool {
		guard nnwIsDragInProgress else { return false }
		nnwPendingSnapshotWork = work		// 只留最后一次
		return true
	}

	// MARK: 放手之后

	/// 把拖动的结果落地:该换容器的换容器,然后写新顺序。
	func nnwApplyDrop(movingNodes: [Node], to destination: Container, in account: Account,
					  anchorNode: Node, dropPoint: CGPoint) {

		// 父子同时拖时只留父(同 nnwSelectedNodes 的理由:避免撤销时长出重复文件夹)
		let nodes = nnwNormalizedPublic(movingNodes)
		guard !nodes.isEmpty else { return }

		// 拖文件夹只可能是在最外层换位置 —— 目标容器必须是账户本身
		let draggingFolder = nodes.contains { $0.representedObject is Folder }
		if draggingFolder, !(destination is Account) { return }

		// ① 先算好"搬过去之后这一层该是什么顺序"。
		// ⚠️ **必须在搬之前算**:搬完之后目标层的内容就变了,再算就把自己也算进去了。
		let movingKeys = nodes.compactMap { FeedOrderStore.orderKey(for: $0) }
		let layerKeys = nnwOrderKeys(inContainer: destination, account: account)
		let anchorIndex = FeedOrderStore.orderKey(for: anchorNode).flatMap { layerKeys.firstIndex(of: $0) }
		let insertAfter = nnwShouldInsertAfterAnchor(anchorNode: anchorNode, dropPoint: dropPoint)
		let insertIndex = NNWFeedOrderMath.insertionIndex(anchorIndex: anchorIndex,
														 insertAfter: insertAfter,
														 layerCount: layerKeys.count)
		let plannedOrder = NNWFeedOrderMath.reordered(layerKeys, moving: movingKeys, toIndex: insertIndex)

		// ② 需要换容器的先搬(串行 —— 并发搬会互相踩,同步账户还会被限流)
		let needMove: [(Feed, Container)] = nodes.compactMap { node in
			guard let feed = node.representedObject as? Feed,
				  let source = node.parent?.representedObject as? Container,
				  source !== destination else { return nil }
			return (feed, source)
		}

		Task { @MainActor [weak self] in
			for (feed, source) in needMove {
				try? await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
					account.moveFeed(feed, from: source, to: destination) { result in
						continuation.resume(with: result)
					}
				}
			}
			// ③ 搬完再写顺序
			FeedOrderStore.shared.setOrder(plannedOrder)
			self?.coordinator?.nnwRebuildFeedList()

			// ④ ⚠️ **把勾选账本清掉**(2026-07-28 审查抓到的严重 bug)。
			// 源换了容器之后,树会给它**新建一个节点** —— 账本里存的旧节点从此是"僵尸":
			// 那一行的勾选圈没了(比的是新节点),底部「删除(N)」却还算着它,
			// 点删除会拿旧节点的父容器去删,而那个容器里已经没有它 → **静默什么都没删**。
			// 菜单式「移动到…」结尾本来就会退出编辑模式(顺带清账本),拖放这条路漏了。
			self?.nnwClearSelection()
		}
	}

	/// 这一层现在的顺序(键)。
	/// 首页的树**已经是按 FeedOrderStore 排好的**,所以直接读子节点即可 ——
	/// 不用像「编辑订阅」页那样再排一次。
	private func nnwOrderKeys(inContainer container: Container, account: Account) -> [String] {
		guard let containerNode = nnwNode(for: container, account: account) else { return [] }
		return containerNode.childNodes.compactMap { FeedOrderStore.orderKey(for: $0) }
	}

	private func nnwNode(for container: Container, account: Account) -> Node? {
		guard let root = coordinator?.rootNode else { return nil }
		guard let accountNode = root.childNodes.first(where: { ($0.representedObject as? Account) === account }) else { return nil }
		if container is Account { return accountNode }
		return accountNode.childNodes.first { ($0.representedObject as? Folder) === (container as? Folder) }
	}

	/// 手指落在锚行的上半还是下半 —— 决定插到它前面还是后面。
	private func nnwShouldInsertAfterAnchor(anchorNode: Node, dropPoint: CGPoint) -> Bool {
		guard let collectionView else { return true }
		for cell in collectionView.visibleCells where cell.nnwStampedNode === anchorNode {
			return dropPoint.y >= cell.frame.midY
		}
		return true
	}

	/// `nnwNormalized` 的对外版本(拖放那边要用)。
	func nnwNormalizedPublic(_ nodes: [Node]) -> [Node] {
		let all = Set(nodes.map { ObjectIdentifier($0) })
		return nodes.filter { node in
			var parent = node.parent
			while let current = parent {
				if all.contains(ObjectIdentifier(current)) { return false }
				parent = current.parent
			}
			return true
		}
	}
}

/// 勾选账本(按节点记,不按行号记 —— 理由见 nnwSelectionBox 的注释)。
private final class NNWNodeSelectionBox {
	var nodes: [Node] = []
}

/// 关联对象存不了裸闭包,包一层。
private final class NNWBlockBox {
	let block: () -> Void
	init(_ block: @escaping () -> Void) { self.block = block }
}

// MARK: - [编辑] 行尾那支铅笔:这一行自己的操作

extension MainFeedCollectionViewController {

	/// 点了某一行行尾的铅笔。
	///
	/// **按 cell 上的钢印找出是哪一行**,不用行号 —— 和拖放同一个理由(行号会错位)。
	@objc func nnwRowPencilTapped(_ sender: UIButton) {

		var view: UIView? = sender
		while let current = view, !(current is UICollectionViewCell) { view = current.superview }
		guard let cell = view as? UICollectionViewCell, let node = cell.nnwStampedNode else { return }

		nnwShowRowActions(for: node, from: sender)
	}

	/// 这一行的操作单。
	///
	/// ## 为什么只留这三项
	///
	/// 原来的长按菜单有七项,但其中「全部标为已读」「打开主页」「拷贝订阅地址」
	/// 「拷贝主页地址」都是**读文章时**才用得上的动作,和"整理订阅"没关系。
	/// 编辑模式下只留和整理相关的,菜单短一眼就能选中。
	/// (那四项在**退出编辑模式后**长按仍然全都在,一个都没丢。)
	private func nnwShowRowActions(for node: Node, from anchor: UIView) {

		let item = node.representedObject as? SidebarItem
		let name = item?.nameForDisplay ?? ""
		let alert = UIAlertController(title: name, message: nil, preferredStyle: .actionSheet)

		alert.addAction(UIAlertAction(title: "重命名…", style: .default) { [weak self] _ in
			self?.nnwPromptRename(node)
		})

		// 源信息(顺带就是「每个源的设置」的入口 —— 里面有"始终使用阅读视图"那个开关)
		if let feed = node.representedObject as? Feed {
			alert.addAction(UIAlertAction(title: "源信息与设置…", style: .default) { [weak self] _ in
				self?.coordinator?.showFeedInspector(for: feed)
			})
		}

		alert.addAction(UIAlertAction(title: "删除…", style: .destructive) { [weak self] _ in
			guard let self else { return }
			if let folder = node.representedObject as? Folder {
				self.nnwAskHowToDeleteFolderPublic(folder, node: node)
			} else {
				self.nnwConfirmDeletePublic(message: "确定删除「\(name)」吗?", nodes: [node])
			}
		})

		alert.addAction(UIAlertAction(title: "取消", style: .cancel))

		// iPad 上 actionSheet 必须锚在触发它的那个按钮上
		if let popover = alert.popoverPresentationController {
			popover.sourceView = anchor
			popover.sourceRect = anchor.bounds
		}
		present(alert, animated: true)
	}

	/// 改名。
	///
	/// ⚠️ **不能直接用上游的 `rename(indexPath:)`**:文件夹在我们的排序表里
	/// **是用名字当键的**(上游的 folderID 每次启动都会变,当不了持久化的键)。
	/// 上游那个改名不知道有这回事,改完文件夹就会**丢掉自己的位置**、退回末尾。
	/// 所以这里改完名要顺手把排序位置也搬到新名字上。
	private func nnwPromptRename(_ node: Node) {

		guard let item = node.representedObject as? SidebarItem else { return }
		let oldName = item.nameForDisplay

		let alert = UIAlertController(title: "重命名「\(oldName)」", message: nil, preferredStyle: .alert)
		alert.addTextField { field in
			field.text = oldName
			field.clearButtonMode = .whileEditing
		}
		alert.addAction(UIAlertAction(title: "取消", style: .cancel))

		let confirm = UIAlertAction(title: "改名", style: .default) { [weak self, weak alert] _ in
			guard let newName = alert?.textFields?.first?.text?
				.trimmingCharacters(in: .whitespacesAndNewlines), !newName.isEmpty,
				  newName != oldName else { return }

			if let feed = item as? Feed {
				feed.rename(to: newName) { result in
					if case .failure(let error) = result { self?.presentError(error) }
				}
			} else if let folder = item as? Folder {
				folder.rename(to: newName) { result in
					switch result {
					case .success:
						// 排序键就是名字 —— 不搬过去等于把这个文件夹的位置丢了
						FeedOrderStore.shared.renameFolderKey(from: oldName, to: newName)
						self?.coordinator?.nnwRebuildFeedList()
					case .failure(let error):
						self?.presentError(error)
					}
				}
			}
		}
		alert.addAction(confirm)
		alert.preferredAction = confirm
		present(alert, animated: true)
	}
}

#endif
