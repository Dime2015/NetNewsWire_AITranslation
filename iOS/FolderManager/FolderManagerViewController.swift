//
//  FolderManagerViewController.swift
//  NetNewsWire — AI 翻译 fork
//
//  [管理] 本 fork 新增,上游没有这个文件,也没有这个页面。
//
//  ## 这个页面是干什么的
//
//  订阅列表页右下角 `+` →「文件夹管理」。集中整理**已有的**文件夹和订阅源
//  (与之并列的「搜索订阅源」负责**添加新的**)。
//
//  ## 为什么要单独做一个页面(上游明明有左滑删除/重命名)
//
//  上游主列表的左滑只能**一次操作一个**。用户有 77 个源、7 个文件夹,
//  真正缺的是**批量**和**整理**:批量移动、批量删除、删文件夹时把里面的源留下。
//  这些上游一个都没有。所以本页的定位是「批量与整理」。
//
//  📌 顺带也做了左滑的单个操作(重命名 / 删除):既然人已经在这一页整理,
//  为了删一个源再退回主列表去左滑很别扭。但**单个删除复用批量那条路的实现**
//  (见「删除」那一节的 `beginDelete`),不另写一套。
//
//  ## 现在做到哪了(三个阶段都已完成,2026-07-23)
//
//  - Phase A:展示 + 新建文件夹 + 重命名
//  - Phase B:移动(多选「移动到…」为主,拖拽为辅)
//  - Phase C:批量删除(可撤销)+ 删文件夹时把里面的源释放到顶层
//  - 之后又按用户反馈做了:文件夹与源混排、拖动排序(顶层和文件夹内两层)、
//    落点分「上下边缘带」、落点与动画的一串修正
//  - **「悬停自动展开文件夹」做过又整个拿掉了**(2026-07-23),原因见下面
//    `isDragInProgress` 附近那段长注释。**别再加回来。**
//
//  ## 两条硬约束(来自 CLAUDE.md,别越界)
//
//  1. **Account 模块是 A 级禁区**:本页**只调用**它的公开接口
//     (`addFolder` / `renameFolder` / `moveFeed` / …),**一行实现都不改**。
//  2. **没有子文件夹**:上游模型里写死了 `subfolders are not supported`
//     (`Folder.folders` 恒为 nil),所以层级永远只有「账户 → 文件夹 → 源」两层。
//     「释放到上一层级」= 释放到账户顶层,不存在更上面一层。
//
//  ## ⚠️ 改这个文件前必读(都是付出过代价的,详见 NOTES-lessons L65 / L66)
//
//  1. **别在 cell 的 accessories 里加 `isEditing` 条件** —— 一加就需要在进出编辑模式时
//     手动重新配置每一行,而那个调用**接连崩过两次**(它要求"列表看到的世界"和
//     "数据源里的世界"完全一致,可退出编辑常发生在刚搬完源、两边还没对齐的那一刻)。
//  2. **拖放相关的调用,顺序即语义**:凡是会改动 collectionView 内部状态的调用
//     (`coordinator.drop` 之类),必须放在所有数据计算**之后**(现在用 `defer`)。
//  3. **落点判断只有一个入口**(`dropDecision`),悬停和放手共用它 ——
//     分开写过一次,口径对不齐就成了"看着能放、松手没反应"。
//     它的**纯规则部分**住在 `DropZoneResolver.swift`(不碰 UIKit),
//     所以能用 `tools/sim-dropzone.swift` 离线跑决策表 —— 改完落点规则请顺手跑一次。
//  4. 这块的时序问题**离线模拟不出来**,只能靠实测;所以**改动要克制**,
//     尤其别为了美化动画去动已经好用的逻辑(那样弄坏过一次)。
//

#if os(iOS)

import UIKit
import Account
import RSCore
import RSTree		// 上游那条可撤销的删除命令认的是 RSTree 的 Node,见 makeNode(for:)

@MainActor final class FolderManagerViewController: UIViewController {

	// MARK: - 列表里的一行

	/// 一行的身份。
	///
	/// 刻意用**值类型的标识**(账户 id / 文件夹 id / 源 id),而不是直接拿 Folder、Feed 对象:
	/// 列表刷新时要靠它比较「哪些行变了」,而对象会被上游随时重建,拿对象比会误判成全变了。
	private enum Item: Hashable {
		case folder(accountID: String, folderID: Int)
		/// `folderID == nil` 表示这个源直接挂在账户下(不在任何文件夹里)
		case feed(accountID: String, feedID: String, folderID: Int?)
	}

	/// 一个分组 = 一个账户。**文件夹和没归档的源混在同一个列表里**,可以互相调顺序。
	///
	/// ## 这里有过一次来回,别再走回头路(2026-07-23)
	///
	/// 中途曾把每个账户**拆成两组**(上面文件夹、下面「不在文件夹里」),
	/// 原因是用户报「编辑模式下分不清某个源到底归没归档」——
	/// 一进编辑模式每行前面要插勾选圈、内容整体右移,**恰好把 outline 那点缩进差吃掉了**。
	///
	/// 但用户随后要求**文件夹本身也要能拖动排序、并且和散源混排**,
	/// 分成两组就做不到了(跨组拖动只会被当成"搬家")。所以合并回一个列表,
	/// 而当初那个"分不清"的问题改用另一招解决:
	/// **给文件夹里的源手动补一段缩进**(`nestedFeedExtraIndent`),
	/// 补的量比勾选圈吃掉的还多,编辑模式下照样一眼看得出层级。
	private enum SectionID: Hashable {
		case account(accountID: String)
	}

	/// 文件夹里的源额外往右缩进多少。
	/// ⚠️ 别调太小:编辑模式下勾选圈会吃掉系统自带的 outline 缩进,
	/// 这一段是用来把层级差**重新拉开**的(见 SectionID 的说明)。
	private static let nestedFeedExtraIndent: CGFloat = 20

	// MARK: - 界面部件

	private var collectionView: UICollectionView!
	private var dataSource: UICollectionViewDiffableDataSource<SectionID, Item>!

	/// 哪些文件夹当前是展开的。列表刷新时要照着它把展开状态复原,
	/// 否则每次收到一条通知,用户手动展开的文件夹就会全部合上。
	private var expandedFolders = Set<Item>()

	/// 正在等待执行的刷新(用来做防抖,见 `scheduleReload`)
	private var pendingReloadTask: Task<Void, Never>?

	/// 手指正拖着东西。**拖动期间一律不重画列表。**
	///
	/// ⚠️ 不冻结的话:后台抓取随便来一条通知就整棵重画一次,而重画会重置滚动位置 ——
	/// 用户报的「拖到需要滚屏的地方、手一停,屏幕唰地弹回去,根本没法瞄准」就是这么来的。
	fileprivate var isDragInProgress = false

	// ⚠️⚠️ **「悬停自动展开文件夹」(弹簧加载)已于 2026-07-23 整个拿掉,别再加回来。**
	//
	// 它存在过大约一天,期间给用户添了两次麻烦、让 app 崩了一次:
	//   1. **挡住落点**:拖到「A 和 B 之间的顶层」时,手指必然要靠近 B,
	//      于是 B 总是先自己展开,那条缝就没了(用户原话:「几乎没机会触发」)。
	//   2. **列表越撑越长**:展开之后不会自己合上,要够到靠下的位置得拖很远
	//      (用户原话:「悬停滑动很长一段距离才能放下」)。
	//   3. **崩过一次**(L65):展开 = 拖动途中改数据源,而那时列表里常有一个
	//      UIKit 插的占位空隙(那条"让开的缝"),改数据源就撞断言。
	//
	// 而"合上"受同一条约束限制:**手指刚离开文件夹时的落点几乎都带占位,
	// 那一刻根本没有安全的时机去删行**。也就是说这个机制天生只能开、不能关。
	//
	// 于是按 L66 的原则处理:**一个需要不断打补丁才能不崩、不别扭的机制,
	// 通常说明它本来就不该存在** —— 直接删掉,而不是继续加保险。
	//
	// 删掉之后白拿的三件事:
	//   · **拖动全程不再修改数据源** → L65 那条崩溃路径从代码里消失了
	//   · 拖动期间列表长度恒定 → 落点不会在手指底下移动
	//   · 想放进文件夹里的**指定位置**:先点开那个文件夹,再拖。少一个便利,换来全程可预测。

	/// 拖动中「现在松手就会放进去」的那个文件夹行。
	///
	/// 用户 2026-07-23:「我不知道我松手,它是会落在两个文件夹中间,还是某个文件夹里面」——
	/// 系统对这两种落点本来就有区分(让开一条缝 / 目标行高亮),
	/// 但那层系统高亮压在我们自铺的暖纸底色上**几乎看不见**,所以自己画一层。
	private var dropTargetFolder: Item?

	/// 编辑模式下已勾选的行(源和文件夹都可能在里面)。
	///
	/// ⚠️ 为什么不直接问 `collectionView.indexPathsForSelectedItems`:
	/// 列表随时会因为一条通知整棵重画,重画后 UIKit 那边的选中就没了。
	/// 自己记一份,刷新后还能把勾恢复上。
	private var selectedItems = Set<Item>()

	// MARK: - 生命周期

	override func viewDidLoad() {
		super.viewDidLoad()

		title = "文件夹管理"
		// 用小标题:推入式页面会继承上一页的大标题模式,而本页内容多、还有两层分组标题,
		// 再顶一个大标题会把可视区域压掉一大截。
		navigationItem.largeTitleDisplayMode = .never
		view.backgroundColor = AppAppearance.paperBackground

		configureNavigationItem()
		configureCollectionView()
		configureDataSource()
		reloadFromAccounts(animated: false)

		// 结构变了(增删源/文件夹、移动)或者名字变了,都要重画。
		// 这两个通知上游本来就在发,我们只是搭个便车,不需要它改任何代码。
		NotificationCenter.default.addObserver(self, selector: #selector(modelDidChange(_:)),
											   name: .ChildrenDidChange, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(modelDidChange(_:)),
											   name: .DisplayNameDidChange, object: nil)
	}

	// MARK: - 导航栏

	private func configureNavigationItem() {
		updateNavigationItems()
	}

	/// 按「在不在编辑模式」摆导航栏按钮。
	///
	/// ⚠️ 本页是**推入式页面**(2026-07-23 从卡片式弹出改的),所以左上角
	/// **不放自己的「完成 / 关闭」** —— 回上一页是系统返回按钮的事。
	/// 编辑模式下则把返回按钮**藏起来**:那时右上角是「完成(退出多选)」,
	/// 左边再摆一个「< Feed」,两个都是"离开"的意思、去处却不同,必然点错。
	/// 想走人就先点「完成」退出多选,返回按钮自己会回来。
	private func updateNavigationItems() {

		navigationItem.hidesBackButton = isEditing

		if isEditing {
			navigationItem.rightBarButtonItems = [editButtonItem]
			return
		}

		let addFolderItem = UIBarButtonItem(
			image: UIImage(systemName: "folder.badge.plus"),
			style: .plain, target: self, action: #selector(addFolderTapped))
		addFolderItem.accessibilityLabel = "新建文件夹"
		// 顺序是「编辑」在最右、「新建文件夹」在它左边
		navigationItem.rightBarButtonItems = [editButtonItem, addFolderItem]
	}

	/// 进出本页时管好底部工具栏。
	///
	/// 工具栏是**整个导航栈共用的一条**,所以推进来时得把主列表那套(设置 / `+`)先收起来,
	/// 否则会看到一条内容不对的残留工具栏。
	/// 离开时不用自己恢复 —— 主列表页在它的 `viewWillAppear` 里本来就会把工具栏设回来。
	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		navigationController?.setToolbarHidden(!isEditing, animated: false)
	}

	/// 进出编辑(多选)模式。`editButtonItem` 会自动调到这里。
	override func setEditing(_ editing: Bool, animated: Bool) {
		super.setEditing(editing, animated: animated)

		collectionView.isEditing = editing
		selectedItems.removeAll()
		updateNavigationItems()
		updateToolbar()

		// ⚠️ **这里刻意不做任何"重新配置每一行"的动作**(2026-07-23,接连崩两次后的结论):
		// 每行的外观已经完全不依赖编辑状态了(勾选圈由 `.whenEditing` 自己管、
		// 展开三角样式固定),所以进出编辑模式什么都不用刷 —— 系统会自己让圈露面/收起。
		// 曾经在这里调 `reconfigureItems`,它要求"列表看到的世界"和"数据源里的世界"完全一致,
		// 而退出编辑常常发生在刚搬完源、两边还没对齐的那一刻 → 直接撞断言。
	}


	// MARK: - 底部工具栏(只在编辑模式出现)

	private func updateToolbar() {

		guard isEditing else {
			navigationController?.setToolbarHidden(true, animated: true)
			return
		}

		let count = selectedItems.count
		let hasFolderSelected = selectedItems.contains { if case .folder = $0 { return true }; return false }

		// 「移动」只对源有意义 —— 文件夹没地方可搬(没有子文件夹)。
		// 所以一旦勾中了文件夹就把它置灰,而不是搬一半再报错。
		let moveTitle = count == 0 ? "移动到…" : "移动 \(count) 项到…"
		let moveItem = UIBarButtonItem(title: moveTitle, style: .plain, target: self, action: #selector(moveTapped))
		moveItem.isEnabled = count > 0 && !hasFolderSelected

		let deleteItem = UIBarButtonItem(title: count == 0 ? "删除" : "删除 \(count) 项",
										 style: .plain, target: self, action: #selector(deleteTapped))
		deleteItem.isEnabled = count > 0
		deleteItem.tintColor = .systemRed		// 破坏性操作要一眼看出来

		toolbarItems = [
			moveItem,
			UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
			deleteItem
		]
		navigationController?.setToolbarHidden(false, animated: true)
	}

	// MARK: - 列表

	private func configureCollectionView() {

		var config = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
		config.headerMode = .supplementary		// 每个账户一个分组头
		config.backgroundColor = AppAppearance.paperBackground
		config.showsSeparators = false			// 和 app 其它列表一致的无边界暖纸风

		// 左滑:删除(靠边)+ 重命名。
		//
		// 📌 **2026-07-23 加上了删除**(用户要求)。这里原先**故意只有重命名**,
		// 注释写的是「删除留给 Phase C 统一做,现在放一个语义不完整的删除反而误导」。
		// 现在 Phase C 已经做完,那套东西(可撤销 + 删文件夹的两条路)是现成的,
		// 左滑只是**接上同一条路**,而不是另写一套删除 —— 所以两处的行为永远一致。
		//
		// ⚠️ 三个刻意的选择:
		// 1. **风格用 `.normal` + 自己涂红,不用 `.destructive`**。
		//    `.destructive` 会让 UIKit 自作主张把那一行**立刻抽走**,而本页的行是
		//    「等账户发通知 → 重画列表」才消失的 —— 两边抢着删同一行,正是 L65 / L66 崩过的那类。
		//    涂成红色观感一模一样,但删行的事仍然只有数据源一个人做。
		// 2. **关掉「一滑到底自动执行」**:最靠边的键现在是删除,不关的话手滑一大下就直奔删除。
		// 3. **删除排在最靠边**(数组第一个 = 最右),和系统邮件一致,肌肉记忆对得上。
		config.trailingSwipeActionsConfigurationProvider = { [weak self] indexPath in
			guard let self, let item = self.dataSource.itemIdentifier(for: indexPath) else { return nil }

			let deleteAction = UIContextualAction(style: .normal, title: nil) { [weak self] _, _, completion in
				self?.beginDelete(items: [item], anchor: .row(indexPath))
				completion(true)		// 只是把左滑收回去;真正删掉那一行的是数据源
			}
			deleteAction.image = UIImage(systemName: "trash")
			deleteAction.backgroundColor = .systemRed
			deleteAction.accessibilityLabel = "删除"

			let renameAction = UIContextualAction(style: .normal, title: nil) { [weak self] _, _, completion in
				self?.promptRename(item)
				completion(true)
			}
			renameAction.image = UIImage(systemName: "pencil")
			renameAction.backgroundColor = .systemOrange
			renameAction.accessibilityLabel = "重命名"

			let configuration = UISwipeActionsConfiguration(actions: [deleteAction, renameAction])
			configuration.performsFirstActionWithFullSwipe = false
			return configuration
		}

		let layout = UICollectionViewCompositionalLayout.list(using: config)
		collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
		collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
		collectionView.backgroundColor = AppAppearance.paperBackground
		collectionView.delegate = self
		collectionView.allowsMultipleSelectionDuringEditing = true	// 编辑模式下能勾多个

		// 拖拽:把源拖进文件夹 / 拖出到顶层。
		// `dragInteractionEnabled` 在 iPhone 上默认是关的(只有 iPad 开),必须显式打开。
		// ⚠️ 拖拽是**辅助**手段(用户拍板):77 个源的规模下,拖到屏幕外的文件夹要边拖边等滚屏,
		// 批量整理仍以「勾选 + 移动到…」为主。所以这里只做最直接的两种落点,不搞复杂的自动滚动。
		collectionView.dragDelegate = self
		collectionView.dropDelegate = self
		collectionView.dragInteractionEnabled = true

		view.addSubview(collectionView)
	}

	private func configureDataSource() {

		// 文件夹那一行:带一个可展开的小三角
		let folderRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, Item> { [weak self] cell, _, item in
			guard let self else { return }
			cell.contentConfiguration = self.rowContent(for: item, base: cell.defaultContentConfiguration())
			cell.backgroundConfiguration = self.paperCellBackground(highlighted: item == self.dropTargetFolder)

			// ⚠️ **这一行的外观刻意完全不看 isEditing**(2026-07-23 第三次改这里,别再加条件):
			//
			// 曾经让展开三角跟着编辑模式换样式(`.header` ↔ `.cell`),
			// 结果每次进出编辑模式都得手动 `reconfigureItems` 重跑一遍外观 ——
			// 而那个调用**接连崩了两次**(它要求"列表看到的世界"和"数据源里的世界"完全一致,
			// 可退出编辑模式常常发生在刚搬完源、两边还没对齐的那一刻)。
			//
			// 现在发现根本不用换:两个附件各管各的点击,天然不冲突 ——
			//   · 点**勾选圈** → 勾选(`.whenEditing` 保证它只在编辑模式露面)
			//   · 点**整行**  → 展开/收起(`.header` 样式)
			// 编辑模式下"点整行仍是展开"反而更顺手:想勾文件夹里的某个源,本来就得先展开看看。
			cell.accessories = [
				.multiselect(displayed: .whenEditing),
				.outlineDisclosure(options: .init(style: .header))
			]
		}

		// 订阅源那一行
		let feedRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, Item> { [weak self] cell, _, item in
			guard let self else { return }
			cell.contentConfiguration = self.rowContent(for: item, base: cell.defaultContentConfiguration())
			cell.backgroundConfiguration = self.paperCellBackground()
			// 勾选圈**不加条件**:`displayed: .whenEditing` 已经保证了"只在编辑模式露面",
			// 交给系统判断比自己看 isEditing 可靠 —— 后者要求每次进出编辑模式都重新配置这一行,
			// 漏一次就变成"有的行有圈、有的没有"(2026-07-23 踩过)。
			cell.accessories = [.multiselect(displayed: .whenEditing)]
		}

		dataSource = UICollectionViewDiffableDataSource<SectionID, Item>(collectionView: collectionView) { collectionView, indexPath, item in
			switch item {
			case .folder:
				return collectionView.dequeueConfiguredReusableCell(using: folderRegistration, for: indexPath, item: item)
			case .feed:
				return collectionView.dequeueConfiguredReusableCell(using: feedRegistration, for: indexPath, item: item)
			}
		}

		// 分组头
		let headerRegistration = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(
			elementKind: UICollectionView.elementKindSectionHeader) { [weak self] headerView, _, indexPath in
			guard let self else { return }
			let sectionID = self.dataSource.snapshot().sectionIdentifiers[indexPath.section]
			var content = headerView.defaultContentConfiguration()
			content.text = self.headerTitle(for: sectionID)
			headerView.contentConfiguration = content
		}
		dataSource.supplementaryViewProvider = { collectionView, kind, indexPath in
			collectionView.dequeueConfiguredReusableSupplementary(using: headerRegistration, for: indexPath)
		}

		// 记住用户展开了哪些文件夹。
		//
		// ⚠️ 为什么非记不可:每收到一条 `ChildrenDidChange` 我们都会整棵重画,
		// 而新画出来的快照默认全是收起的 —— 不记的话,后台随便来条通知
		// (抓取完成、未读数变化都会发),用户刚展开的文件夹就自己合上了。
		dataSource.sectionSnapshotHandlers.willExpandItem = { [weak self] item in
			self?.expandedFolders.insert(item)
		}
		dataSource.sectionSnapshotHandlers.willCollapseItem = { [weak self] item in
			self?.expandedFolders.remove(item)
		}
	}

	/// 一行显示的文字与图标。
	///
	/// ⚠️ **只有这一份**:创建 cell 时用它,刷新时也用它
	/// (`refreshVisibleRowContents`)。分成两处写迟早会长歪 —— 到时候
	/// "新画出来的行"和"原地更新的行"会长得不一样,还极难看出是哪儿不一致。
	private func rowContent(for item: Item, base: UIListContentConfiguration) -> UIListContentConfiguration? {

		var content = base

		switch item {

		case .folder:
			guard let folder = folder(for: item) else { return nil }
			content.text = folder.nameForDisplay
			let count = folder.topLevelFeeds.count
			content.secondaryText = count == 0 ? "空文件夹" : "\(count) 个订阅源"
			// 图标不显式设颜色,让它继承全局强调色(陶土红)。
			// ⚠️ 强调色的真源是 Assets 里的 primaryAccentColor 色板,不在 AppAppearance 里 ——
			// 那是为了让 storyboard 也能按名字引到同一个颜色(见 L46)。
			//
			// 拖动中「松手就会放进这个文件夹」时换成**实心**图标 —— 和底色高亮是两条独立的线索,
			// 一深一浅、一色一形,哪种屏幕条件下都至少能认出一个。
			content.image = UIImage(systemName: item == dropTargetFolder ? "folder.fill" : "folder")

		case .feed(_, _, let folderID):
			guard let feed = feed(for: item) else { return nil }
			content.text = feed.nameForDisplay
			content.image = IconImageCache.shared.imageForFeed(feed)?.image
			content.imageProperties.maximumSize = CGSize(width: 24, height: 24)
			content.imageProperties.cornerRadius = 4
			// ⚠️ 给图标**留一块固定宽度**,文字才会从同一条竖线开始(2026-07-23 用户发现)。
			// 只设 maximumSize 是不够的:那只管"最大别超过 24",
			// 而各家 favicon 的长宽比五花八门(圆的、扁的),实际占宽各不相同,
			// 紧跟其后的标题就会参差不齐 —— 截图里 AVNo.1 比下面几行往左突出一截,就是这么来的。
			content.imageProperties.reservedLayoutSize = CGSize(width: 24, height: 24)

			// ⚠️ **文件夹里的源要额外往右缩一段**,否则编辑模式下认不出层级:
			// 那时每行前面插了勾选圈、内容整体右移,恰好把系统 outline 自带的缩进差抹平,
			// 于是"文件夹里的源"和"没归档的源"看起来一样深(用户 2026-07-23 实测报过)。
			// 现在两种源混排在同一个列表里,这段缩进就是唯一的层级线索,别去掉。
			if folderID != nil {
				content.directionalLayoutMargins.leading += Self.nestedFeedExtraIndent
			}
		}

		return content
	}

	/// 把**当前可见的**每一行的文字重算一遍。
	///
	/// ## 为什么非有这一步不可(2026-07-23 用户报的 bug)
	///
	/// 用户报:「文件夹底下那个『x 个订阅源』的数字,在拖出拖入之后不会马上更新。」
	///
	/// 病根在**行的身份**:一行的标识是值类型的
	/// (账户id / 文件夹id / 源id),而"文件夹里有几个源""源叫什么名字"
	/// **都不在身份里**。于是把一个源搬进搬出之后,文件夹那一行的身份**一个字都没变** →
	/// diffable 判定"这一行没变" → 屏幕上现有的那一行原样保留、不重新配置 →
	/// 副标题里的数字**停在旧值**,要等它滚出屏幕再滚回来才更新。
	/// (同一类病之前的表现是"按了编辑,勾选圈有的出现有的不出现"。)
	///
	/// ## 为什么用这种"土办法",而不是 UIKit 的 reconfigure
	///
	/// - `NSDiffableDataSourceSectionSnapshot` **没有** `reconfigureItems`(只有普通快照有);
	///   而普通快照**装不下文件夹的层级**(它只含当前可见的行),套回去会把展开结构压平。
	/// - `collectionView.reconfigureItems(at:)` 有,但它是**直接对列表下命令**,
	///   要求"列表看到的世界"和"数据源里的世界"当场一致 ——
	///   在刚搬完源的那一刻调用会撞断言,**2026-07-23 为此崩过两次**(L66)。
	///
	/// 这里只是**给已经存在的 cell 换一份文字**:不新增行、不删除行、不动层级,
	/// 完全不经过 UIKit 的批量更新机制,所以不存在上面那条崩溃路径。
	/// 拿不到 cell(行不可见)就跳过 —— 那种行下次画出来时本来就是新算的。
	///
	/// ⚠️ **必须在 `apply` 的完成回调里调**:那时动画和布局才落定,
	/// "第几行是谁"才是准的。动画途中去问,可能把 A 的文字写进 B 的那一行。
	private func refreshVisibleRowContents() {

		for indexPath in collectionView.indexPathsForVisibleItems {
			guard let item = dataSource.itemIdentifier(for: indexPath),
				  let cell = collectionView.cellForItem(at: indexPath) as? UICollectionViewListCell,
				  // ⚠️ 基底必须取**全新的默认配置**,不能拿 cell 现有的那份来改:
				  // 文件夹里的源那段额外缩进是 `+=` 上去的,拿旧的当基底
				  // 会**每刷新一次就再往右挪 20pt**,几次之后整行缩到屏幕外面去。
				  let content = rowContent(for: item, base: cell.defaultContentConfiguration()) else { continue }
			cell.contentConfiguration = content
		}
	}

	/// 分组标题 = 账户名。
	/// (曾经还有个「不在文件夹里」的标题,那是分成两组时期的产物;
	///  现在文件夹和散源混排在同一组,不需要那个分界了。)
	private func headerTitle(for sectionID: SectionID) -> String {
		switch sectionID {
		case .account(let accountID):
			return AccountManager.shared.existingAccount(accountID: accountID)?.nameForDisplay ?? ""
		}
	}

	/// cell 的暖纸底色(和设置页等其它列表一致)。
	///
	/// `highlighted` = 拖动中「现在松手就会放进这个文件夹」,给它铺一层强调色。
	/// 为什么要自己画:系统对「放进这一项」的落点只做**很淡的一层高亮**,
	/// 而我们给每一行都铺了自定义暖纸底色,那层系统高亮几乎看不出来
	/// (用户 2026-07-23:「我不知道我松手,它是会落在两个文件夹中间,还是某个文件夹里面」)。
	private func paperCellBackground(highlighted: Bool = false) -> UIBackgroundConfiguration {
		var background = UIBackgroundConfiguration.listPlainCell()
		background.backgroundColor = highlighted
			? Assets.Colors.primaryAccent.withAlphaComponent(Self.dropTargetTintAlpha)
			: AppAppearance.paperBackground
		return background
	}

	/// 落点高亮的浓度。要够显眼(一眼分得出"进去"还是"插在旁边"),又不能盖住文字。
	///
	/// 定这个数时是**算过的**,不是拍脑袋(我点不了模拟器,但色差可以直接算):
	/// 把强调色按不同浓度叠在暖纸底上,和普通行比每通道的差值 ——
	/// | 浓度 | 浅色下的色差 | 深色下的色差 |
	/// |---|---|---|
	/// | 0.18 | (9, 26, 32) | (33, 17, 10) |
	/// | 0.22 | (11, 32, 39) | (40, 20, 12) |
	/// | **0.28** | **(14, 40, 50)** | **(51, 26, 15)** |
	/// 0.18 / 0.22 在浅色下偏弱(这是个**转瞬即逝**的提示,宁可过一点也别看不见),
	/// 所以取 0.28。文字仍是深色压在浅底上,可读性不受影响。
	private static let dropTargetTintAlpha: CGFloat = 0.28

	// MARK: - 把账户里的内容读成列表

	/// 重新从 Account 读一遍当前的文件夹 / 源,画到列表上。
	///
	/// 每次都整棵重建(而不是精细地增删某一行):这个页面的规模最多几百行,
	/// diffable 自己会算出差异、只动变了的那几行,没必要自己维护增量逻辑 ——
	/// 那正是最容易出错的地方。
	private func reloadFromAccounts(animated: Bool) {

		let accounts = AccountManager.shared.sortedActiveAccounts

		// 一个账户一组。空账户不放(会出现只有标题、底下什么都没有的空壳)。
		let desiredSections: [SectionID] = accounts
			.filter { !($0.sortedFolders ?? []).isEmpty || !$0.topLevelFeeds.isEmpty }
			.map { .account(accountID: $0.accountID) }
		applySectionsIfChanged(desiredSections, animated: animated)

		for account in accounts {

			let entries = FeedOrderStore.shared.sortedTopLevel(
				folders: account.sortedFolders ?? [],
				looseFeeds: Array(account.topLevelFeeds))
			guard !entries.isEmpty else { continue }

			// **文件夹和没归档的源混在同一串里**,按用户排的顺序 ——
			// 主列表也用同一套排序(`nnwSortedForDisplay`),两边看到的先后必然一致。
			var section = NSDiffableDataSourceSectionSnapshot<Item>()
			for entry in entries {
				switch entry {
				case .folder(let folder):
					let folderItem = Item.folder(accountID: account.accountID, folderID: folder.folderID)
					section.append([folderItem])
					let feedItems = sortedForDisplay(folder.topLevelFeeds).map {
						Item.feed(accountID: account.accountID, feedID: $0.feedID, folderID: folder.folderID)
					}
					section.append(feedItems, to: folderItem)
					if expandedFolders.contains(folderItem) {
						section.expand([folderItem])
					}
				case .feed(let feed):
					section.append([Item.feed(accountID: account.accountID, feedID: feed.feedID, folderID: nil)])
				}
			}

			// ⚠️ apply **完事之后**要把可见行的文字重算一遍,见 `refreshVisibleRowContents`。
			// 放在完成回调里,是为了等动画和布局都落定 —— 那时"第几行是谁"才是准的。
			dataSource.apply(section, to: .account(accountID: account.accountID),
							 animatingDifferences: animated) { [weak self] in
				self?.refreshVisibleRowContents()
			}
		}

		restoreSelection()
	}

	/// 重画之后把勾选恢复上 —— UIKit 那边的选中会随着重画丢掉,而用户勾了半天不该白勾。
	private func restoreSelection() {
		guard isEditing else { return }
		for item in selectedItems {
			guard let indexPath = dataSource.indexPath(for: item) else { continue }
			collectionView.selectItem(at: indexPath, animated: false, scrollPosition: [])
		}
		// 选中的源可能已经被别处删掉了,顺手把已经不存在的清掉,免得计数虚高
		selectedItems = selectedItems.filter { dataSource.indexPath(for: $0) != nil }
		updateToolbar()
	}

	/// 只在分组结构**真的变了**时才动它。
	///
	/// ⚠️ 这是 2026-07-23 修「拖完之后画面闪一下、滚动位置还错位」的关键。
	/// 原来每次刷新都先套一个"只有分组、没有内容"的空快照,再把内容逐组填回去 ——
	/// 那等于**把整张列表清空再重建**:中间那一帧是空的(闪烁),
	/// 内容高度归零又撑回来(滚动位置被顶掉)。
	/// 而绝大多数刷新(移动一个源、改个名)根本不改变分组结构,这一步完全是白费。
	///
	/// 改成基于**现有**快照增删,分组没变就一步都不动;真变了也只动那一个分组,
	/// 剩下的内容原地不动。
	private func applySectionsIfChanged(_ desired: [SectionID], animated: Bool) {

		var snapshot = dataSource.snapshot()
		guard snapshot.sectionIdentifiers != desired else { return }

		let obsolete = snapshot.sectionIdentifiers.filter { !desired.contains($0) }
		if !obsolete.isEmpty {
			snapshot.deleteSections(obsolete)
		}

		// 按期望的先后顺序把缺的补进去(挨着它前面那个放,保证顺序不乱)
		for (index, section) in desired.enumerated() where !snapshot.sectionIdentifiers.contains(section) {
			if index > 0, snapshot.sectionIdentifiers.contains(desired[index - 1]) {
				snapshot.insertSections([section], afterSection: desired[index - 1])
			} else if let first = snapshot.sectionIdentifiers.first {
				snapshot.insertSections([section], beforeSection: first)
			} else {
				snapshot.appendSections([section])
			}
		}

		dataSource.apply(snapshot, animatingDifferences: animated)
	}

	/// 本页显示用的排序:**和主列表用同一套规则**(用户拖出来的顺序优先,没排过的按名字)。
	/// ⚠️ 两处必须一致 —— 管理页排好了、主列表却另按一套排,等于白排。
	private func sortedForDisplay(_ feeds: Set<Feed>) -> [Feed] {
		FeedOrderStore.shared.sortedFeeds(Array(feeds))
	}

	// MARK: - 从「一行」找回真正的对象

	private func account(for item: Item) -> Account? {
		switch item {
		case .folder(let accountID, _), .feed(let accountID, _, _):
			return AccountManager.shared.existingAccount(accountID: accountID)
		}
	}

	private func folder(for item: Item) -> Folder? {
		guard case .folder(_, let folderID) = item, let account = account(for: item) else { return nil }
		return account.folders?.first { $0.folderID == folderID }
	}

	private func feed(for item: Item) -> Feed? {
		guard case .feed(_, let feedID, let folderID) = item, let account = account(for: item) else { return nil }
		if let folderID {
			let folder = account.folders?.first { $0.folderID == folderID }
			return folder?.topLevelFeeds.first { $0.feedID == feedID }
		}
		return account.topLevelFeeds.first { $0.feedID == feedID }
	}

	// MARK: - 新建文件夹

	@objc private func addFolderTapped() {

		let accounts = AccountManager.shared.sortedActiveAccounts
		guard !accounts.isEmpty else { return }

		// 只有一个账户就别多问一步,直接让用户输名字
		guard accounts.count > 1 else {
			promptNewFolderName(in: accounts[0])
			return
		}

		let picker = UIAlertController(title: "在哪个账户下新建?", message: nil, preferredStyle: .actionSheet)
		picker.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItem
		for account in accounts {
			picker.addAction(UIAlertAction(title: account.nameForDisplay, style: .default) { [weak self] _ in
				self?.promptNewFolderName(in: account)
			})
		}
		picker.addAction(UIAlertAction(title: "取消", style: .cancel))
		present(picker, animated: true)
	}

	private func promptNewFolderName(in account: Account) {

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
			self?.createFolder(named: name, in: account)
		}
		alert.addAction(createAction)
		alert.preferredAction = createAction
		present(alert, animated: true)
	}

	private func createFolder(named name: String, in account: Account) {
		Task { @MainActor in
			do {
				_ = try await account.addFolder(name)
				// 成功后不用手动刷新:上游会发 ChildrenDidChange,我们已经在听
			} catch {
				presentFailure("新建文件夹失败", error)
			}
		}
	}

	// MARK: - 重命名

	private func promptRename(_ item: Item) {

		// 文件夹和源共用一套对话框 —— 对用户来说是同一件事,没必要分两种写法
		let currentName: String
		if let folder = folder(for: item) {
			currentName = folder.nameForDisplay
		} else if let feed = feed(for: item) {
			currentName = feed.nameForDisplay
		} else {
			return
		}

		let alert = UIAlertController(title: "重命名", message: nil, preferredStyle: .alert)
		alert.addTextField { textField in
			textField.text = currentName
			textField.autocapitalizationType = .words
			textField.clearButtonMode = .whileEditing
		}
		alert.addAction(UIAlertAction(title: "取消", style: .cancel))

		let renameAction = UIAlertAction(title: "保存", style: .default) { [weak self, weak alert] _ in
			let name = (alert?.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
			guard !name.isEmpty, name != currentName else { return }
			self?.performRename(item, to: name)
		}
		alert.addAction(renameAction)
		alert.preferredAction = renameAction
		present(alert, animated: true)
	}

	private func performRename(_ item: Item, to name: String) {

		let handleResult: (Result<Void, Error>) -> Void = { [weak self] result in
			if case .failure(let error) = result {
				self?.presentFailure("重命名失败", error)
			}
		}

		if let folder = folder(for: item) {
			// 文件夹的排序键就是它的名字,改名要把顺序一起搬过去,否则它会掉回末尾
			let oldName = folder.nameForDisplay
			FeedOrderStore.shared.renameFolderKey(from: oldName, to: name)
			folder.rename(to: name, completion: handleResult)
		} else if let feed = feed(for: item) {
			feed.rename(to: name, completion: handleResult)
		}
	}

	// MARK: - 刷新与报错

	/// 待处理的刷新。用来把短时间内的一串通知合并成一次重画。
	///
	/// ⚠️ 为什么要合并:一次同步/导入会连着发几十条 `ChildrenDidChange`
	/// (每个源、每个文件夹各一条)。不合并的话每条都整棵重建一次列表,页面会明显卡住。
	private static let reloadDebounceSeconds = 0.2

	@objc private func modelDidChange(_ note: Notification) {
		// 通知可能来自后台线程,统一回主线程再动界面
		Task { @MainActor [weak self] in
			self?.scheduleReload()
		}
	}

	fileprivate func scheduleReload() {
		pendingReloadTask?.cancel()
		pendingReloadTask = Task { @MainActor [weak self] in
			try? await Task.sleep(for: .seconds(Self.reloadDebounceSeconds))
			guard !Task.isCancelled, let self else { return }
			// 手指还拖着就别重画 —— 重画会把滚动位置顶回去(见 isDragInProgress)。
			// 拖动结束时会再调一次这里,攒下的变化那时统一补上。
			guard !self.isDragInProgress else { return }
			self.reloadFromAccounts(animated: true)
		}
	}

	/// 出错就明说。**不要静默失败** —— 同步账户下这些操作会真的发网络请求,
	/// 失败了不吭声的话,用户会以为改成功了(教训 L43)。
	private func presentFailure(_ title: String, _ error: Error) {
		presentMessage(title, error.localizedDescription)
	}

	private func presentMessage(_ title: String, _ message: String) {
		let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
		alert.addAction(UIAlertAction(title: "好", style: .default))
		present(alert, animated: true)
	}
}

// MARK: - 点击行为

extension FolderManagerViewController: UICollectionViewDelegate {

	func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {

		// 非编辑模式:一律放行。
		// ⚠️ **故意不返回 false 来禁止选中** —— 文件夹行的展开三角用的是 `.header` 样式
		// (点整行就能展开),那个样式搭在 cell 的点击上,把选中整个禁掉很可能连展开也点不动。
		// 用「允许选中、马上取消」绕开这个耦合(已由用户实测确认能展开)。
		guard isEditing else { return true }

		// 编辑模式:源和文件夹都能勾(Phase C 起文件夹也能批量删)。
		// 文件夹的展开改由三角负责,不再和"点行选中"抢同一个点击。
		return true
	}

	func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {

		guard isEditing else {
			collectionView.deselectItem(at: indexPath, animated: true)
			return
		}
		guard let item = dataSource.itemIdentifier(for: indexPath) else { return }
		selectedItems.insert(item)
		updateToolbar()
	}

	func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
		guard isEditing, let item = dataSource.itemIdentifier(for: indexPath) else { return }
		selectedItems.remove(item)
		updateToolbar()
	}
}

// MARK: - 移动源:选好了往哪儿放

extension FolderManagerViewController {

	@objc private func moveTapped() {

		let items = Array(selectedItems)
		guard !items.isEmpty else { return }

		// 跨账户移动不做:不同账户背后是不同的同步服务,"移动"在那边没有对应语义,
		// 真要挪只能在目标账户重新订阅一次。与其做一个似是而非的,不如明说不支持。
		let accountIDs = Set(items.compactMap { itemAccountID($0) })
		guard accountIDs.count == 1,
			  let accountID = accountIDs.first,
			  let account = AccountManager.shared.existingAccount(accountID: accountID) else {
			presentMessage("暂不支持跨账户移动", "请分别在各自的账户里整理。")
			return
		}

		let picker = UIAlertController(title: "移动 \(items.count) 项到", message: nil, preferredStyle: .actionSheet)
		picker.popoverPresentationController?.barButtonItem = toolbarItems?.first { $0.isEnabled && $0.title != nil }

		for folder in account.sortedFolders ?? [] {
			picker.addAction(UIAlertAction(title: folder.nameForDisplay, style: .default) { [weak self] _ in
				self?.performMove(items, to: folder, in: account)
			})
		}
		// 「拿出文件夹」就是移到账户本身(顶层)。上游模型里没有更上面一层了。
		picker.addAction(UIAlertAction(title: "不放在文件夹里", style: .default) { [weak self] _ in
			self?.performMove(items, to: account, in: account)
		})
		picker.addAction(UIAlertAction(title: "取消", style: .cancel))
		present(picker, animated: true)
	}

	private func itemAccountID(_ item: Item) -> String? {
		switch item {
		case .folder(let accountID, _), .feed(let accountID, _, _):
			return accountID
		}
	}

	/// 这个源现在待在哪个容器里(文件夹,或者账户顶层)。移动时要告诉上游"从哪儿搬"。
	private func sourceContainer(for item: Item, in account: Account) -> Container? {
		guard case .feed(_, _, let folderID) = item else { return nil }
		guard let folderID else { return account }
		return account.folders?.first { $0.folderID == folderID }
	}

	/// 逐个搬。**故意串行**而不是一起发:
	/// 它们改的是同一批容器,并发搬容易互相踩;而且本地账户每次都是瞬时的,串行也不慢。
	/// 同步账户下每次是一个网络请求,串行还能避免把对方服务器打出限流(L33 的教训)。
	/// `insertingAt` = 搬过去之后落在新容器的第几位。
	/// **拖拽**会给出这个位置(用户明确指了地方);**菜单里的「移动到…」**不给(它没有位置概念),
	/// 那时就清掉排序位置、让它按名字落到末尾。
	private func performMove(_ items: [Item], to destination: Container, in account: Account,
							 insertingAt insertIndex: Int? = nil) {

		// 搬过去之后新容器该是什么次序 —— **必须在搬之前算**,
		// 因为搬完之后容器内容就变了,再算就分不清"原有的"和"刚进来的"。
		let plannedOrder: [String]? = insertIndex.map { index in
			var order = orderKeys(in: destination, account: account)
			let movingIDs = items.compactMap { item -> String? in
				guard case .feed(_, let feedID, _) = item else { return nil }
				return feedID
			}
			order.removeAll { movingIDs.contains($0) }
			order.insert(contentsOf: movingIDs, at: max(0, min(index, order.count)))
			return order
		}

		Task { @MainActor in

			var failedNames: [String] = []
			var movedCount = 0

			for item in items {
				guard let feed = feed(for: item),
					  let source = sourceContainer(for: item, in: account) else { continue }
				if source === destination { continue }		// 已经在目标里了,跳过

				do {
					try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
						account.moveFeed(feed, from: source, to: destination) { result in
							continuation.resume(with: result)
						}
					}
					movedCount += 1
				} catch {
					failedNames.append(feed.nameForDisplay)
				}
			}

			if let plannedOrder {
				// 拖拽过来的:落在用户指的那个位置
				FeedOrderStore.shared.setOrder(plannedOrder)
			} else {
				// 从菜单搬过来的:没有位置可言,忘掉旧位置、按名字落到末尾。
				// 不忘的话它会带着**旧容器里的**位置插进新容器中间,看起来像随机乱跳。
				FeedOrderStore.shared.forgetOrder(forFeedIDs: items.compactMap {
					guard case .feed(_, let feedID, _) = $0 else { return nil }
					return feedID
				})
			}

			// 搬完退出编辑模式:选中的东西已经不在原位了,继续留着勾没有意义
			setEditing(false, animated: true)

			// 有失败就说清楚**哪几个**失败了 —— 只说"移动失败"用户不知道该重试哪个
			if !failedNames.isEmpty {
				let list = failedNames.joined(separator: "、")
				presentMessage("有 \(failedNames.count) 项没能移动",
							   "成功 \(movedCount) 项。失败的是:\(list)")
			}
		}
	}
}

// MARK: - 删除(Phase C)
//
// 两条硬要求(用户拍板):
// ① **删文件夹时弹窗给两个选择**:把里面的源移到外面 / 连源一起删。
//    上游只有后者(`removeFolder` 会把里面的源一并带走),前者是本页补的。
// ② **批量删源接上游的撤销** —— 复用 `Shared/Commands/DeleteCommand.swift`,
//    它本来就支持一次删多个 + 注册 UndoManager,于是"摇一摇撤销"是白拿的。

extension FolderManagerViewController {

	/// 删除的弹窗要挂在屏幕的哪个位置。
	/// iPhone 上无所谓,但 **iPad 的 actionSheet 没有锚点会直接崩**,所以两个入口各自报一下自己在哪。
	fileprivate enum DeleteAnchor {
		case toolbar				// 编辑模式:底部工具栏的「删除 N 项」
		case row(IndexPath)			// 左滑:被滑的那一行
	}

	/// 编辑模式下点底部「删除 N 项」。
	@objc fileprivate func deleteTapped() {
		beginDelete(items: Array(selectedItems), anchor: .toolbar)
	}

	/// 删除的**唯一入口**,批量(编辑模式)和单个(左滑)都走这里。
	///
	/// ⚠️ 刻意让两个入口共用同一条路:确认文案、删文件夹的两条路、撤销,
	/// 都只有一份实现 —— 否则左滑那条迟早和批量那条的行为对不上。
	/// 所以这里判断「哪些源不搬」只看**传进来的 items**,不看 `selectedItems`
	/// (左滑时压根没有选中项)。
	private func beginDelete(items: [Item], anchor: DeleteAnchor) {

		guard !items.isEmpty else { return }

		let folders = items.compactMap { folder(for: $0) }
		let feedCount = items.count - folders.count

		// 没有文件夹 → 只是删源,确认一下就行
		guard !folders.isEmpty else {
			// 只删一个时把名字写出来 —— 左滑删的就是这一行,报个名字才对得上
			let title: String
			if items.count == 1, let name = feed(for: items[0])?.nameForDisplay {
				title = "删除「\(name)」"
			} else {
				title = "删除 \(feedCount) 个订阅源"
			}
			confirmDelete(title: title,
						  message: "文章和已读状态会一起删掉。删错了可以摇一摇撤销。") { [weak self] in
				self?.deleteWithUndo(items)
			}
			return
		}

		// 有文件夹:先问里面的源怎么办。
		// **空文件夹不用问** —— 没有源要安置,问了反而是噪音。
		let feedsInsideCount = folders.reduce(0) { $0 + $1.topLevelFeeds.count }
		guard feedsInsideCount > 0 else {
			let title: String
			if items.count == 1, let name = folders.first?.nameForDisplay {
				title = "删除空文件夹「\(name)」"
			} else {
				title = "删除 \(folders.count) 个空文件夹"
			}
			confirmDelete(title: title, message: "删错了可以摇一摇撤销。") { [weak self] in
				self?.deleteWithUndo(items)
			}
			return
		}

		askHowToHandleFeedsInside(items: items, folders: folders,
								  feedsInsideCount: feedsInsideCount,
								  alsoDeletingFeeds: feedCount, anchor: anchor)
	}

	/// 删文件夹时的两条路:把源留下,还是一起删。
	private func askHowToHandleFeedsInside(items: [Item], folders: [Folder],
										   feedsInsideCount: Int, alsoDeletingFeeds: Int,
										   anchor: DeleteAnchor) {

		let isSingle = items.count == 1
		let titleText = isSingle ? "删除文件夹「\(folders[0].nameForDisplay)」" : "删除 \(folders.count) 个文件夹"
		let message = "里面还有 \(feedsInsideCount) 个订阅源,要怎么处理?"
		let alert = UIAlertController(title: titleText, message: message, preferredStyle: .actionSheet)
		switch anchor {
		case .toolbar:
			alert.popoverPresentationController?.barButtonItem = toolbarItems?.last
		case .row(let indexPath):
			if let cell = collectionView.cellForItem(at: indexPath) {
				alert.popoverPresentationController?.sourceView = cell
				alert.popoverPresentationController?.sourceRect = cell.bounds
			}
		}

		// 文案刻意做短(2026-07-23 用户定的)。两项的区别全在"和订阅源"三个字上,
		// 上面那句 message(「里面还有 N 个订阅源,要怎么处理?」)已经交代了处境,
		// 选项里不必再复述一遍"移到外面"。
		alert.addAction(UIAlertAction(title: "删除文件夹", style: .default) { [weak self] _ in
			self?.releaseFeedsThenDelete(items: items, folders: folders)
		})
		alert.addAction(UIAlertAction(title: "删除文件夹和订阅源", style: .destructive) { [weak self] _ in
			self?.deleteWithUndo(items)
		})
		alert.addAction(UIAlertAction(title: "取消", style: .cancel))
		present(alert, animated: true)
	}

	/// 先把文件夹里的源搬到顶层,再删空掉的文件夹。
	///
	/// ⚠️ **顺序不能反**:必须先搬完再删。反过来的话,`removeFolder` 会把里面的源一起带走,
	/// 那就不是"释放"而是"删掉"了。
	///
	/// ⚠️ **这次要删的源是例外,不搬** —— 用户既勾了文件夹(要释放里面的源)、又单独勾了其中某个源,
	/// 那就是明确想删掉那一个。不搬它,它会随文件夹一起被删,正合其意。
	/// (只看**本次要删的 items**,不看 `selectedItems`:左滑删单个文件夹时压根没有选中项。)
	///
	/// ⚠️ **搬运失败就停手,不往下删** —— 半搬半删会留下一地无法解释的残局。
	private func releaseFeedsThenDelete(items: [Item], folders: [Folder]) {

		let deletingItems = Set(items)

		Task { @MainActor in

			var failedNames: [String] = []

			for folder in folders {
				guard let account = folder.account else { continue }
				for feed in folder.topLevelFeeds {
					// 这个源自己也在本次删除名单里 → 用户想删它,别搬
					let feedItem = Item.feed(accountID: account.accountID, feedID: feed.feedID, folderID: folder.folderID)
					if deletingItems.contains(feedItem) { continue }

					do {
						try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
							account.moveFeed(feed, from: folder, to: account) { result in
								continuation.resume(with: result)
							}
						}
					} catch {
						failedNames.append(feed.nameForDisplay)
					}
				}
			}

			guard failedNames.isEmpty else {
				let list = failedNames.joined(separator: "、")
				presentMessage("没能把源移出来,文件夹保留了",
							   "失败的是:\(list)。文件夹没有删除,免得连累里面的源。")
				exitEditingIfNeeded()
				return
			}

			deleteWithUndo(items)
		}
	}

	/// 走上游那条**可撤销**的删除命令。
	///
	/// ⚠️ 撤销能盖住的只有「删除」这一步。若刚才选的是"把源移到外面",
	/// **那个移动不在撤销范围内** —— 撤销后文件夹会回来,但里面是空的、源留在顶层。
	/// (这是取舍:移动和删除是两个独立操作,硬凑成一个可撤销的整体不值当。)
	private func deleteWithUndo(_ items: [Item]) {

		guard let undoManager else {
			presentMessage("删不了", "系统没有给这个页面提供撤销支持,为安全起见没有执行删除。")
			return
		}

		let nodes = items.compactMap { makeNode(for: $0) }
		guard !nodes.isEmpty,
			  let command = DeleteCommand(nodesToDelete: nodes,
										  undoManager: undoManager,
										  errorHandler: { [weak self] error in
										  	self?.presentFailure("删除时出错", error)
										  }) else {
			presentMessage("删不了", "这些项目里没有可以删除的内容。")
			return
		}

		command.perform()
		exitEditingIfNeeded()
	}

	/// 删完收工:**只在真的处于编辑模式时**才退出。
	///
	/// ⚠️ 左滑删除时并不在编辑模式,无条件调 `setEditing(false)` 会顺手重建导航栏按钮、
	/// 再对着本就藏着的工具栏做一次隐藏动画 —— 没必要,也可能闪一下。
	private func exitEditingIfNeeded() {
		guard isEditing else { return }
		setEditing(false, animated: true)
	}

	/// 给上游的删除命令搭一个它认得的「节点」。
	///
	/// 上游那条命令是给主列表的树形结构写的,它靠 `node.parent` 判断这一项属于谁:
	/// **父节点是文件夹 → 从那个文件夹里删;父节点是根 → 从账户顶层删**。
	/// 我们这个页面没有那棵树,所以现搭一个够用的父子关系给它看
	/// (只需要两层,因为上游模型不支持子文件夹)。
	private func makeNode(for item: Item) -> Node? {

		guard let account = account(for: item) else { return nil }
		// 根节点:代表账户本身。`isRoot` 判定的就是"有没有父节点",所以它的 parent 必须是 nil。
		let rootNode = Node(representedObject: account, parent: nil)

		switch item {
		case .folder:
			guard let folder = folder(for: item) else { return nil }
			return Node(representedObject: folder, parent: rootNode)

		case .feed(_, _, let folderID):
			guard let feed = feed(for: item) else { return nil }
			guard let folderID, let folder = account.folders?.first(where: { $0.folderID == folderID }) else {
				// 顶层的源:父节点直接是根 → 上游会从账户顶层删
				return Node(representedObject: feed, parent: rootNode)
			}
			// 文件夹里的源:中间垫一层文件夹节点 → 上游会从那个文件夹里删
			let folderNode = Node(representedObject: folder, parent: rootNode)
			return Node(representedObject: feed, parent: folderNode)
		}
	}

	/// 破坏性操作统一走这个确认框。**删除永远要问一次** —— 批量删尤其。
	private func confirmDelete(title: String, message: String, onConfirm: @escaping () -> Void) {
		let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
		alert.addAction(UIAlertAction(title: "取消", style: .cancel))
		alert.addAction(UIAlertAction(title: "删除", style: .destructive) { _ in onConfirm() })
		present(alert, animated: true)
	}
}
// MARK: - 拖拽:按「区域」判定,而不是「压着哪一行」
//
// ⚠️ **这一整段在 2026-07-23 被推倒重写过,重写前的做法错在哪,值得记住:**
//
// 原来的判定是「手指底下**正好压着**哪一行」。但用户的心智模型是**区域** ——
// 「我把它拖到『不在文件夹里』那一片,松手就该进去」,而不是「我得瞄准某一行」。
// 两者的差距造成了一连串怎么补都补不完的毛病:
//   · 拖到一组的**行与行之间、或末尾空白**时,系统给的位置指不到任何一行 → 放手没反应
//   · 展开的文件夹,拖到它**子行**上不算数 —— 可用户明明觉得那就是"文件夹里面"
//   · 悬停和放手是两段各写一遍的判断,**口径一旦对不齐**就会出现
//     "悬停说能放、松手却没反应"(用户原话)
//
// 重写后的三条规矩:
//   ① **落点先翻译成"要进哪个容器"**,一个函数 `dropDestination(at:)` 说了算;
//      悬停和放手**共用它**,不可能再对不齐。
//   ② **落在空白处不算失败**:取该位置**上方最近**的那一行,按它所属的区域算。
//   ③ **区域归属看这一行是谁**:文件夹行 / 文件夹里的源 → 都算"那个文件夹";
//      顶层的源 → 算"账户顶层"。于是展开的文件夹整片都是有效落点。

extension FolderManagerViewController: UICollectionViewDragDelegate {

	func collectionView(_ collectionView: UICollectionView,
						itemsForBeginning session: UIDragSession,
						at indexPath: IndexPath) -> [UIDragItem] {

		// 源和文件夹都能拖:源可以进出文件夹、也可以调顺序;
		// **文件夹只能调顺序**(上游不支持子文件夹,它没有别的地方可去)。
		guard let item = dataSource.itemIdentifier(for: indexPath) else { return [] }

		let displayName: String
		switch item {
		case .folder:
			guard let folder = folder(for: item) else { return [] }
			displayName = folder.nameForDisplay
		case .feed:
			guard let feed = feed(for: item) else { return [] }
			displayName = feed.nameForDisplay
		}

		let dragItem = UIDragItem(itemProvider: NSItemProvider(object: displayName as NSString))
		// 真正靠的是这个 localObject(拖到哪儿之后按它找回是哪个源);
		// 上面那个文字 provider 只是为了拖动时有个像样的预览。
		dragItem.localObject = item
		return [dragItem]
	}

	/// ⚠️ 拖动期间**冻结列表刷新**。
	///
	/// 不冻的话,后台抓取随便来一条通知就会把整棵列表重画一次 ——
	/// 而重画会重置滚动位置,表现就是用户报的
	/// 「拖到需要滚屏的位置、手一停,屏幕唰地弹回去,根本没法瞄准」。
	func collectionView(_ collectionView: UICollectionView, dragSessionWillBegin session: UIDragSession) {
		isDragInProgress = true
	}

	func collectionView(_ collectionView: UICollectionView, dragSessionDidEnd session: UIDragSession) {
		isDragInProgress = false
		scheduleReload()		// 把冻结期间攒下的变化补画一次
	}
}

extension FolderManagerViewController: UICollectionViewDropDelegate {

	func collectionView(_ collectionView: UICollectionView,
						dropSessionDidUpdate session: UIDropSession,
						withDestinationIndexPath destinationIndexPath: IndexPath?) -> UICollectionViewDropProposal {

		// 只接受本页面内部拖过来的东西(从别的 app 拖文字进来没有意义)
		guard session.localDragSession != nil else {
			return UICollectionViewDropProposal(operation: .cancel)
		}
		let point = session.location(in: collectionView)
		let draggingFolder = isDraggingFolder(session.localDragSession)

		guard let decision = dropDecision(at: point, draggingFolder: draggingFolder) else {
			updateDropTargetHighlight(nil)
			return UICollectionViewDropProposal(operation: .forbidden)
		}

		// **让"松手会进这个文件夹"看得见。**
		// 高亮的条件和落点意图**出自同一个 decision**,所以看到的和放手的结果必然一致。
		updateDropTargetHighlight(decision.resolution.target == .anchorFolder ? decision.anchor : nil)

		// 两种落点意图,给的是**两种不同的视觉反馈**:
		// · `.insertAtDestinationIndexPath` —— 周围的行让开一条缝,意思是"插到这个位置"
		// · `.insertIntoDestinationIndexPath` —— 目标行高亮,意思是"放进这一项里面"
		//
		// ⚠️ 顺带记一笔:前者会让 UIKit 在列表里**插一个占位空隙**(那条缝就是它)。
		// 占位不在我们的数据快照里,所以**拖动途中绝不能改数据源** —— 会撞 UIKit 的
		// 批量更新校验,直接崩(L65 为此崩过一次,当时的元凶是"悬停自动展开文件夹")。
		// 现在那个机制已经整个拿掉,拖动全程不改数据源,这条路径不复存在。**别再往回加。**
		return UICollectionViewDropProposal(
			operation: .move,
			intent: decision.resolution.isInsertInto ? .insertIntoDestinationIndexPath
												     : .insertAtDestinationIndexPath)
	}

	/// 这一次拖的是不是文件夹(拖文件夹只可能是在顶层调顺序)
	private func isDraggingFolder(_ session: UIDragSession?) -> Bool {
		session?.items.contains {
			if case .folder = ($0.localObject as? Item) { return true }
			return false
		} ?? false
	}

	/// 手指拖出列表范围了 —— 把落点高亮撤掉,不然它会留在屏幕上。
	func collectionView(_ collectionView: UICollectionView, dropSessionDidExit session: UIDropSession) {
		updateDropTargetHighlight(nil)
	}

	/// 拖放结束(放成了、取消了都算)—— 同上。
	func collectionView(_ collectionView: UICollectionView, dropSessionDidEnd session: UIDropSession) {
		updateDropTargetHighlight(nil)
	}

	func collectionView(_ collectionView: UICollectionView, performDropWith coordinator: UICollectionViewDropCoordinator) {

		// 先把高亮撤掉:接下来这一行的内容就要变了,让它带着"要放进来"的样子被重画很怪。
		// (只是改颜色和图标,不动数据源,放在这里是安全的。)
		updateDropTargetHighlight(nil)

		let point = coordinator.session.location(in: collectionView)

		let items = coordinator.items.compactMap { $0.dragItem.localObject as? Item }
		guard !items.isEmpty else { return }

		// ⚠️ 和悬停时**调用的是同一个函数**,所以"看着能放"和"真的能放"必然一致。
		let draggingFolder = items.contains { if case .folder = $0 { return true }; return false }
		guard let target = dropDecision(at: point, draggingFolder: draggingFolder) else { return }

		// 跨账户拖拽不做(理由见 moveTapped)
		guard items.allSatisfy({ itemAccountID($0) == target.accountID }) else {
			presentMessage("暂不支持跨账户移动", "请分别在各自的账户里整理。")
			return
		}

		// UIKit 自己算好的插入位置 —— **就是视觉上"让开的那条缝"所在的位置**。
		// 拿它当准,松手后的落位才和拖动时看到的一致。
		let dropIndexPath = coordinator.destinationIndexPath

		// 告诉系统"预览就落在手指松开的地方",省得它把预览**缩着飞回原点再消失**
		// (用户原话:「拖动的目标会往画面深处缩小,很影响判断」)。
		//
		// ⚠️⚠️ **这段必须放在所有数据计算之后,所以用 defer。**
		// 曾经把它写在前面,结果同区域排序整个失效、拖进文件夹落点偏两行 ——
		// 因为 `coordinator.drop(...)` 会**当场改动列表的内部状态**,
		// 而下面算插入位置时要拿落点去问"那一行是谁"(`itemIdentifier(for:)`),
		// 问到的就成了错的行:算成原位就表现为"拖了没反应",算偏就表现为"落到第三行"。
		// **调用顺序在这里就是语义的一部分,别再挪到前面去。**
		defer {
			for droppedItem in coordinator.items {
				coordinator.drop(droppedItem.dragItem, to: previewTarget(for: droppedItem, fallback: point))
			}
		}

		// **拖的是文件夹 → 只可能是在顶层调顺序**(上游不支持子文件夹,它没别处可去)。
		// (落点判定那边也保证了这种情况一定给出"顶层",这里再显式走一次,读代码时不用回头查。)
		if draggingFolder {
			reorderWithinLayer(items, at: dropIndexPath, fallbackPoint: point,
							   container: target.account, account: target.account)
			return
		}

		// **落点就在源自己待着的那一层 → 这是"调顺序",不是"搬家"。**
		// 判据是所在容器一致(顶层 ↔ 顶层,或同一个文件夹内);
		// 那种情况下走 moveFeed 是空操作(源容器==目标容器会被跳过),只有排序才有意义。
		if items.allSatisfy({ containerFolderID(of: $0) == targetFolderID(of: target.container) }) {
			reorderWithinLayer(items, at: dropIndexPath, fallbackPoint: point,
							   container: target.container, account: target.account)
			return
		}

		// 搬进别的容器:也要落在**手指指的那个位置**,而不是一律排到末尾
		// (用户 2026-07-23 报「拖进文件夹后总是跑到最底下」)。
		// ⚠️ 这里要按**目标那一层**的次序算位置。顶层是"文件夹和散源混排"的一串,
		// 早先只拿散源来算,于是从文件夹里拖到两个文件夹之间时会排到所有散源的最后。
		let insertIndex = insertionIndex(in: orderKeys(in: target.container, account: target.account),
										 at: dropIndexPath, fallbackPoint: point,
										 layerFolderID: targetFolderID(of: target.container))
		performMove(items, to: target.container, in: target.account, insertingAt: insertIndex)
	}

	/// 预览该落在哪儿。
	///
	/// ⚠️ **落到"它现在真正待的那一行的正中",而不是手指松开的位置**(2026-07-23 用户反馈):
	/// 手指松开时通常并不在行的水平正中,拿它当落点,预览就会**歪在右边**停一下再消失
	/// (用户原话:「会往右边错位停在被放下的那一行,然后卡住一秒」)。
	/// 此时数据已经重排完(本方法在 defer 里、排序之后才调),
	/// 所以直接问"这一项现在在第几行"就能拿到它最终的位置,预览一步到位。
	///
	/// 查不到就退回手指位置 —— **跨容器搬家时就会走这条**:
	/// 源换了文件夹,它的身份(带着所在文件夹)已经变了,按旧身份查不到新行。
	private func previewTarget(for droppedItem: UICollectionViewDropItem, fallback point: CGPoint) -> UIDragPreviewTarget {

		if let item = droppedItem.dragItem.localObject as? Item,
		   let indexPath = dataSource.indexPath(for: item),
		   let attributes = collectionView.layoutAttributesForItem(at: indexPath) {
			return UIDragPreviewTarget(container: collectionView, center: attributes.center)
		}
		return UIDragPreviewTarget(container: collectionView, center: point)
	}

	/// 一次落点判定的结论。
	private struct DropDecision {
		let container: Container
		let account: Account
		let accountID: String
		let resolution: DropResolution
		/// 落点归属的那一行(高亮要知道该点亮谁)
		let anchor: Item
	}

	/// 把屏幕上的一个位置,翻译成「要放进哪个容器」。**悬停判定和放手执行共用这一个入口。**
	///
	/// ## 判定分两步(2026-07-23 重做)
	///
	/// 1. **纯规则**交给 `DropZoneResolver`:给它"落点那一行是什么 + 手指在这一行的哪一段
	///    + 手指的横向位置",它算出"要进哪个容器"。那部分不碰 UIKit,可以离线跑决策表
	///    (`tools/sim-dropzone.swift`)。
	/// 2. **本方法**只负责查真实对象:把结论里的"落点那个文件夹"翻成真正的 `Folder`。
	///
	/// ## 为什么要引入「上下边缘带」
	///
	/// 用户反馈:「想把 A 里的源拖到 A 和 B 之间(顶层),**必然会先触发 B 展开**,
	/// 然后就没法拖到中间了」。属实 —— 原来只要落点压在文件夹行上,
	/// **不管压在哪儿**都判成"放进这个文件夹",而且停 0.6 秒就自动展开它。
	/// 于是"A 和 B 之间的顶层"只剩下一块又窄又看不见的区域(A 的最后一个子行 + 手指靠左)。
	///
	/// 现在给文件夹行分三段:**上边缘 = 排在它前面,中间 = 放进去,下边缘 = 排在它后面**
	/// (Finder / Files / 各种大纲编辑器都是这个手感)。
	/// 边缘带**不触发弹簧加载** —— 手指停在两行的分界线上时,B 不会再自己弹开。
	private func dropDecision(at point: CGPoint, draggingFolder: Bool) -> DropDecision? {

		guard let row = anchorRow(nearestTo: point),
			  let accountID = itemAccountID(row.item),
			  let account = AccountManager.shared.existingAccount(accountID: accountID) else { return nil }

		let resolution = DropZoneResolver.resolve(
			anchor: anchorKind(of: row.item),
			band: DropZoneResolver.band(of: point, in: row.frame),
			pointX: point.x,
			draggingFolder: draggingFolder)

		let container: Container
		switch resolution.target {

		case .topLevel:
			container = account

		case .anchorFolder:		// 放进**落点那一行**的那个文件夹
			guard case .folder(_, let folderID) = row.item,
				  let folder = account.folders?.first(where: { $0.folderID == folderID }) else { return nil }
			container = folder

		case .enclosingFolder:	// 落点是文件夹里的某个源 → 放进它所在的那个文件夹
			guard case .feed(_, _, let folderID) = row.item, let folderID,
				  let folder = account.folders?.first(where: { $0.folderID == folderID }) else { return nil }
			container = folder
		}

		return DropDecision(container: container, account: account, accountID: accountID,
							resolution: resolution, anchor: row.item)
	}

	/// 给「松手就会放进去」的那个文件夹加一层显眼的高亮(底色 + 实心图标)。
	///
	/// ⚠️ **这里只改已经存在的那两行 cell 的外观** —— 不增删行、不动数据源,
	/// 所以不受"拖动途中不能改数据源"那条约束的限制(L65 那条崩溃路径与此无关)。
	/// 这也是为什么落点提示能做,而"悬停自动展开/合上"做不了:一个只是换颜色,
	/// 另一个要增删行。
	///
	/// 只在**目标变了**时才动手,免得每次手指移动都刷一遍。
	private func updateDropTargetHighlight(_ item: Item?) {

		guard dropTargetFolder != item else { return }

		let previous = dropTargetFolder
		dropTargetFolder = item

		// 旧的取消高亮、新的点亮 —— 两行都要刷
		for target in [previous, item].compactMap({ $0 }) {
			guard let indexPath = dataSource.indexPath(for: target),
				  let cell = collectionView.cellForItem(at: indexPath) as? UICollectionViewListCell else { continue }
			cell.backgroundConfiguration = paperCellBackground(highlighted: target == dropTargetFolder)
			cell.contentConfiguration = rowContent(for: target, base: cell.defaultContentConfiguration())
		}
	}

	/// 落点那一行在规则表眼里是个什么东西。
	///
	/// 展开状态取自 `expandedFolders` —— 那是本页唯一的一份展开记录。
	private func anchorKind(of item: Item) -> DropAnchorKind {
		switch item {
		case .folder:
			return .folder(expanded: expandedFolders.contains(item))
		case .feed(_, _, let folderID):
			return folderID == nil ? .looseFeed : .nestedFeed
		}
	}

	/// 这一行现在待在哪个文件夹里(nil = 顶层)。用来判断"拖到的地方是不是它原来的容器"。
	private func containerFolderID(of item: Item) -> Int? {
		if case .feed(_, _, let folderID) = item { return folderID }
		return nil
	}

	/// 目标容器对应的文件夹 id(账户本身 = nil = 顶层)。
	private func targetFolderID(of container: Container) -> Int? {
		(container as? Folder)?.folderID
	}

	// MARK: - 调顺序(顶层 / 文件夹内共用一套)

	/// 把拖动的这些项挪到落点那个位置,并把**所在那一层**的新次序记下来。
	///
	/// ## 「一层」是什么
	///
	/// · **顶层** = 文件夹和没归档的源**混排**的那一串(文件夹可以排在源中间)
	/// · **某个文件夹内** = 它自己那些源
	///
	/// 两层用的是同一套算法,只是"这一层有哪些项"和"项的键怎么取"不同 ——
	/// 所以这里只有一个实现,免得两边各写一遍再慢慢长歪(之前就是分开写的)。
	///
	/// ⚠️ 顺序是**我们自己存的**(`FeedOrderStore`)—— 上游把源放在 `Set` 里,
	/// 模型层根本没有顺序可言,列表的排列是显示时现算的。
	private func reorderWithinLayer(_ items: [Item], at dropIndexPath: IndexPath?, fallbackPoint: CGPoint,
									container: Container, account: Account) {

		let layerFolderID = targetFolderID(of: container)
		var orderedKeys = orderKeys(in: container, account: account)

		// 被拖的那些项在这一层的键(不属于这一层的忽略)
		let movingKeys = items.compactMap { layerKey(of: $0, layerFolderID: layerFolderID) }
		guard !movingKeys.isEmpty else { return }

		var insertIndex = insertionIndex(in: orderedKeys, at: dropIndexPath,
										 fallbackPoint: fallbackPoint, layerFolderID: layerFolderID)

		// 先把被拖的从原位摘掉,再插到新位置。
		// ⚠️ 摘除会让后面的下标前移,所以插入点要跟着往前挪同样的格数,否则会偏。
		let removedBefore = movingKeys.filter { key in
			guard let index = orderedKeys.firstIndex(of: key) else { return false }
			return index < insertIndex
		}.count
		orderedKeys.removeAll { movingKeys.contains($0) }
		insertIndex = max(0, min(insertIndex - removedBefore, orderedKeys.count))
		orderedKeys.insert(contentsOf: movingKeys, at: insertIndex)

		FeedOrderStore.shared.setOrder(orderedKeys)
		// ⚠️ **不要带动画**:系统的拖放收尾动画正在播,再叠一套数据更新动画,
		// 看起来就是"闪一下再跳位"。数据瞬时到位,视觉移动交给系统那套动画收尾。
		reloadFromAccounts(animated: false)
	}

	/// 某一层当前的次序(键)。顶层是文件夹和散源混排,文件夹内只有源。
	private func orderKeys(in container: Container, account: Account) -> [String] {
		if let folder = container as? Folder {
			return sortedForDisplay(folder.topLevelFeeds).map { $0.feedID }
		}
		return FeedOrderStore.shared.sortedTopLevel(
			folders: account.sortedFolders ?? [],
			looseFeeds: Array(account.topLevelFeeds)
		).map { FeedOrderStore.shared.key(for: $0) }
	}

	/// 这一项在指定那一层里的键(不属于这一层就返回 nil)。
	private func layerKey(of item: Item, layerFolderID: Int?) -> String? {
		switch item {
		case .folder:
			guard layerFolderID == nil, let folder = folder(for: item) else { return nil }
			return FeedOrderStore.orderKey(forFolderNamed: folder.nameForDisplay)
		case .feed(_, let feedID, let itemFolderID):
			return itemFolderID == layerFolderID ? feedID : nil
		}
	}

	/// 落点那一行,在指定层里对应"插到谁的位置/谁的后面"。
	private func insertionAnchor(for item: Item, layerFolderID: Int?) -> (key: String, after: Bool)? {

		// 就在这一层里 → 占据它的位置(把它往下推)
		if let key = layerKey(of: item, layerFolderID: layerFolderID) {
			return (key, false)
		}

		// ⚠️ **落在某个文件夹里的源上,而我们要放到顶层** —— 就是用户那个场景:
		// 「A 展开、B 收起,把 A 里的源拖到 A 和 B 中间」。
		// 那一行在顶层没有自己的位置,它所属的**整个文件夹**才是顶层的一项,
		// 所以插到**那个文件夹之后**,正好落在 A 和 B 中间。
		if layerFolderID == nil,
		   case .feed(let accountID, _, let itemFolderID) = item,
		   let itemFolderID,
		   let account = AccountManager.shared.existingAccount(accountID: accountID),
		   let folder = account.folders?.first(where: { $0.folderID == itemFolderID }) {
			return (FeedOrderStore.orderKey(forFolderNamed: folder.nameForDisplay), true)
		}
		return nil
	}

	/// 算出该插到第几个位置。
	///
	/// ⚠️ **优先用 UIKit 自己算好的 `destinationIndexPath`** —— 那就是拖动时看到的
	/// "让开的那条缝",它已经判过手指落在行的上半还是下半。
	/// 早先一律"插在落点那一行的后面",于是拖到第一行会落到第二位(2026-07-23 用户报过)。
	/// 只有它给不出来时(手指落在列表末尾的空白),才退回"排在上方最近那一项之后"。
	private func insertionIndex(in orderedKeys: [String], at dropIndexPath: IndexPath?,
								fallbackPoint: CGPoint, layerFolderID: Int?) -> Int {

		if let dropIndexPath,
		   let item = dataSource.itemIdentifier(for: dropIndexPath),
		   let anchor = insertionAnchor(for: item, layerFolderID: layerFolderID),
		   let index = orderedKeys.firstIndex(of: anchor.key) {
			return anchor.after ? index + 1 : index
		}

		if let landed = item(nearestTo: fallbackPoint),
		   let anchor = insertionAnchor(for: landed, layerFolderID: layerFolderID),
		   let index = orderedKeys.firstIndex(of: anchor.key) {
			return index + 1		// 落在空白:排在上方最近那一项之后
		}

		return orderedKeys.count
	}

	/// 找这个位置对应的那一行;**落在空白处也不算失败** —— 取它上方最近的一行。
	///
	/// 为什么要这样:行与行之间、一组的末尾,这些地方都没有 cell,
	/// 但用户明明是"往那一片"拖的。取上方最近的一行,正好能把这些空隙
	/// 归给它上面那个区域(文件夹的最后一个子行之下 = 还在这个文件夹的范围内)。
	private func item(nearestTo point: CGPoint) -> Item? {
		anchorRow(nearestTo: point)?.item
	}

	/// 同上,但**连那一行的矩形一起给出来** —— 判断"手指落在这一行的上边缘 / 中间 / 下边缘"要用。
	///
	/// ⚠️ 落在空白处时,返回的是**上方最近**那一行,此时 `point` 其实在 `frame` 的**下方**。
	/// 这是有意的:那种位置本来就该算成"排在那一行后面"(`DropZoneResolver.band` 会算成下带)。
	private func anchorRow(nearestTo point: CGPoint) -> (item: Item, frame: CGRect)? {

		if let indexPath = collectionView.indexPathForItem(at: point),
		   let item = dataSource.itemIdentifier(for: indexPath),
		   let frame = collectionView.layoutAttributesForItem(at: indexPath)?.frame {
			return (item, frame)
		}

		var best: (item: Item, frame: CGRect)?
		var bestBottom = -CGFloat.greatestFiniteMagnitude
		for indexPath in collectionView.indexPathsForVisibleItems {
			guard let attributes = collectionView.layoutAttributesForItem(at: indexPath),
				  let item = dataSource.itemIdentifier(for: indexPath) else { continue }
			let bottom = attributes.frame.maxY
			if bottom <= point.y, bottom > bestBottom {
				bestBottom = bottom
				best = (item, attributes.frame)
			}
		}
		// 落在所有内容**上方**(列表最顶端的空白)时返回 nil —— 那里没有明确归属,不猜。
		return best
	}
}
#endif
