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
//  这些上游一个都没有。所以本页的定位是「批量与整理」,
//  **不追求把左滑那些单个操作再实现一遍**。
//
//  ## 分三阶段做(用户要求每阶段停下来验收)
//
//  - **Phase A(当前)**:展示 + 新建文件夹 + 重命名
//  - Phase B:移动(多选「移动到…」为主,拖拽为辅)
//  - Phase C:批量删除 + 删文件夹时把源释放到顶层
//
//  ## 两条硬约束(来自 CLAUDE.md,别越界)
//
//  1. **Account 模块是 A 级禁区**:本页**只调用**它的公开接口
//     (`addFolder` / `renameFolder` / `moveFeed` / …),**一行实现都不改**。
//  2. **没有子文件夹**:上游模型里写死了 `subfolders are not supported`
//     (`Folder.folders` 恒为 nil),所以层级永远只有「账户 → 文件夹 → 源」两层。
//     Phase C 说的「释放到上一层级」= 释放到账户顶层,不存在更上面一层。
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

	/// 拖着东西**悬停在收起的文件夹上多久,就自动把它展开**(所谓"弹簧加载")。
	///
	/// 0.6 秒是个折中:系统自带的弹簧加载约 0.5 秒,而这里展开会让下面所有行整体下移、
	/// 落点跟着变,误触的代价比普通按钮高。所以宁可让手指多停一瞬,也不要**路过就展开**。
	fileprivate static let springLoadSeconds = 0.6

	/// 当前悬停着的那个文件夹(用来判断"还是不是同一个",手指微动不该重新计时)
	private var springLoadTarget: Item?
	private var springLoadTask: Task<Void, Never>?

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
		// 重画一遍,好让每行换上/摘掉左边那个勾选圈
		reloadFromAccounts(animated: animated)
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

		// 左滑:重命名。
		// ⚠️ 这里**故意不提供删除** —— 删除留给 Phase C 统一做(要带撤销、
		// 还要处理「删文件夹时里面的源怎么办」)。现在放一个语义不完整的删除,
		// 反而会让人以为已经做好了。
		config.trailingSwipeActionsConfigurationProvider = { [weak self] indexPath in
			guard let self, let item = self.dataSource.itemIdentifier(for: indexPath) else { return nil }
			let renameAction = UIContextualAction(style: .normal, title: nil) { [weak self] _, _, completion in
				self?.promptRename(item)
				completion(true)
			}
			renameAction.image = UIImage(systemName: "pencil")
			renameAction.backgroundColor = .systemOrange
			renameAction.accessibilityLabel = "重命名"
			return UISwipeActionsConfiguration(actions: [renameAction])
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
			guard let self, let folder = self.folder(for: item) else { return }
			var content = cell.defaultContentConfiguration()
			content.text = folder.nameForDisplay
			let count = folder.topLevelFeeds.count
			content.secondaryText = count == 0 ? "空文件夹" : "\(count) 个订阅源"
			// 图标不显式设颜色,让它继承全局强调色(陶土红)。
			// ⚠️ 强调色的真源是 Assets 里的 primaryAccentColor 色板,不在 AppAppearance 里 ——
			// 那是为了让 storyboard 也能按名字引到同一个颜色(见 L46)。
			content.image = UIImage(systemName: "folder")
			cell.contentConfiguration = content
			cell.backgroundConfiguration = self.paperCellBackground()

			if self.isEditing {
				// 编辑模式:文件夹**也能勾**(批量删文件夹)。
				// ⚠️ 展开三角必须从 `.header` 换成 `.cell` 样式 ——
				// `.header` 是"点整行就展开",而编辑模式下点整行的含义已经变成"勾选"了,
				// 两者抢同一个点击必然打架。`.cell` 样式下:**点三角展开,点行选中**,各管各的。
				cell.accessories = [.multiselect(displayed: .whenEditing),
									.outlineDisclosure(options: .init(style: .cell))]
			} else {
				// 平时:`.header` 样式 = 点整行就能展开/收起,不用去瞄那个小三角
				cell.accessories = [.outlineDisclosure(options: .init(style: .header))]
			}
		}

		// 订阅源那一行
		let feedRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, Item> { [weak self] cell, _, item in
			guard let self, let feed = self.feed(for: item) else { return }
			var content = cell.defaultContentConfiguration()
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
			if case .feed(_, _, let folderID) = item, folderID != nil {
				content.directionalLayoutMargins.leading += Self.nestedFeedExtraIndent
			}
			cell.contentConfiguration = content
			cell.backgroundConfiguration = self.paperCellBackground()
			// 编辑模式下每个源前面出现勾选圈;平时什么都不显示
			cell.accessories = self.isEditing ? [.multiselect(displayed: .whenEditing)] : []
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

	/// 分组标题 = 账户名。
	/// (曾经还有个「不在文件夹里」的标题,那是分成两组时期的产物;
	///  现在文件夹和散源混排在同一组,不需要那个分界了。)
	private func headerTitle(for sectionID: SectionID) -> String {
		switch sectionID {
		case .account(let accountID):
			return AccountManager.shared.existingAccount(accountID: accountID)?.nameForDisplay ?? ""
		}
	}

	/// cell 的暖纸底色(和设置页等其它列表一致)
	private func paperCellBackground() -> UIBackgroundConfiguration {
		var background = UIBackgroundConfiguration.listPlainCell()
		background.backgroundColor = AppAppearance.paperBackground
		return background
	}

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
			dataSource.apply(section, to: .account(accountID: account.accountID), animatingDifferences: animated)
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
	private func performMove(_ items: [Item], to destination: Container, in account: Account) {

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

			// 换了容器就忘掉它原来的排序位置,让它按名字落在新容器的末尾。
			// 不忘的话,它会带着旧位置插进新文件夹中间,看起来像随机乱跳。
			FeedOrderStore.shared.forgetOrder(forFeedIDs: items.compactMap {
				guard case .feed(_, let feedID, _) = $0 else { return nil }
				return feedID
			})

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

	@objc fileprivate func deleteTapped() {

		let items = Array(selectedItems)
		guard !items.isEmpty else { return }

		let folders = items.compactMap { folder(for: $0) }
		let feedCount = items.count - folders.count

		// 没选文件夹 → 只是删几个源,确认一下就行
		guard !folders.isEmpty else {
			confirmDelete(title: "删除 \(feedCount) 个订阅源",
						  message: "这些源的文章和已读状态会一起删掉。删错了可以摇一摇撤销。") { [weak self] in
				self?.deleteWithUndo(items)
			}
			return
		}

		// 选了文件夹:先问里面的源怎么办。
		// **空文件夹不用问** —— 没有源要安置,问了反而是噪音。
		let feedsInsideCount = folders.reduce(0) { $0 + $1.topLevelFeeds.count }
		guard feedsInsideCount > 0 else {
			confirmDelete(title: "删除 \(folders.count) 个空文件夹",
						  message: "删错了可以摇一摇撤销。") { [weak self] in
				self?.deleteWithUndo(items)
			}
			return
		}

		askHowToHandleFeedsInside(items: items, folders: folders,
								  feedsInsideCount: feedsInsideCount, alsoDeletingFeeds: feedCount)
	}

	/// 删文件夹时的两条路:把源留下,还是一起删。
	private func askHowToHandleFeedsInside(items: [Item], folders: [Folder],
										   feedsInsideCount: Int, alsoDeletingFeeds: Int) {

		let title = "删除 \(folders.count) 个文件夹"
		let message = "里面还有 \(feedsInsideCount) 个订阅源,要怎么处理?"
		let alert = UIAlertController(title: title, message: message, preferredStyle: .actionSheet)
		alert.popoverPresentationController?.barButtonItem = toolbarItems?.last

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
	/// ⚠️ **被用户勾中的源是例外,不搬** —— 他既勾了文件夹(要释放里面的源)、又单独勾了其中某个源,
	/// 那就是明确想删掉那一个。不搬它,它会随文件夹一起被删,正合其意。
	///
	/// ⚠️ **搬运失败就停手,不往下删** —— 半搬半删会留下一地无法解释的残局。
	private func releaseFeedsThenDelete(items: [Item], folders: [Folder]) {

		Task { @MainActor in

			var failedNames: [String] = []

			for folder in folders {
				guard let account = folder.account else { continue }
				for feed in folder.topLevelFeeds {
					// 这个源自己也被勾了 → 用户想删它,别搬
					let feedItem = Item.feed(accountID: account.accountID, feedID: feed.feedID, folderID: folder.folderID)
					if selectedItems.contains(feedItem) { continue }

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
				setEditing(false, animated: true)
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
		let hovering = item(nearestTo: point)
		let draggingFolder = session.localDragSession?.items.contains {
			if case .folder = ($0.localObject as? Item) { return true }
			return false
		} ?? false

		// 拖的是文件夹时**不做弹簧加载** —— 文件夹不能放进文件夹,展开它没有意义。
		updateSpringLoading(hovering: draggingFolder ? nil : hovering)

		guard dropDestination(at: point) != nil else {
			return UICollectionViewDropProposal(operation: .forbidden)
		}

		// 拖文件夹时一律用"插入到某处"的意图 —— 它只可能是在调顺序。
		if draggingFolder {
			return UICollectionViewDropProposal(operation: .move, intent: .insertAtDestinationIndexPath)
		}

		// ⚠️ **两种落点意图必须分开用,这不只是观感问题,更是防崩溃的硬要求**
		// (2026-07-23 用户实测崩过一次,栈直指 `expandFolder` 里的 apply):
		//
		// · `.insertAtDestinationIndexPath` 会让 UIKit 在列表里**插入一个占位空隙**
		//   —— 就是那条"让开的缝",落点反馈全靠它。
		//   但占位一旦存在,我们再去改数据源(弹簧加载展开文件夹)时,
		//   UIKit 校验批量更新会发现行数对不上 → **断言失败,直接崩**。
		// · `.insertIntoDestinationIndexPath` 不插占位(只把目标行高亮),
		//   所以悬停在文件夹上时用它,展开才是安全的 —— 而且"放进这一项"本来就是它的语义。
		//
		// 于是:**悬停在文件夹行上 → insertInto(可安全展开);其余 → insertAt(让位动画)**。
		if case .folder = hovering {
			return UICollectionViewDropProposal(operation: .move, intent: .insertIntoDestinationIndexPath)
		}
		return UICollectionViewDropProposal(operation: .move, intent: .insertAtDestinationIndexPath)
	}

	func collectionView(_ collectionView: UICollectionView, performDropWith coordinator: UICollectionViewDropCoordinator) {

		// ⚠️ 和悬停时**调用的是同一个函数**,所以"看着能放"和"真的能放"必然一致。
		let point = coordinator.session.location(in: collectionView)
		guard let target = dropDestination(at: point) else { return }

		let items = coordinator.items.compactMap { $0.dragItem.localObject as? Item }
		guard !items.isEmpty else { return }

		// 跨账户拖拽不做(理由见 moveTapped)
		guard items.allSatisfy({ itemAccountID($0) == target.accountID }) else {
			presentMessage("暂不支持跨账户移动", "请分别在各自的账户里整理。")
			return
		}

		// **拖的是文件夹 → 只可能是在顶层调顺序**(上游不支持子文件夹)。
		if items.contains(where: { if case .folder = $0 { return true }; return false }) {
			reorderTopLevel(items, droppedAt: point, in: target.account)
			return
		}

		// **落点就在源自己待着的那个容器里 → 这是"调顺序",不是"搬家"。**
		// 判据是所在容器一致(顶层 ↔ 顶层,或同一个文件夹内),
		// 那种情况下走 moveFeed 是空操作(源容器==目标容器会被跳过),只有排序才有意义。
		if items.allSatisfy({ containerFolderID(of: $0) == targetFolderID(of: target.container) }) {
			if targetFolderID(of: target.container) == nil {
				reorderTopLevel(items, droppedAt: point, in: target.account)	// 顶层:和文件夹混在一起排
			} else {
				reorder(items, droppedAt: point, in: target)					// 文件夹内部:只排源
			}
			return
		}

		performMove(items, to: target.container, in: target.account)
	}

	/// 拖动结束(不管放没放成)都要把弹簧加载的计时收掉,免得手抬起来之后文件夹还自己弹开。
	func collectionView(_ collectionView: UICollectionView, dropSessionDidEnd session: UIDropSession) {
		updateSpringLoading(hovering: nil)
	}

	func collectionView(_ collectionView: UICollectionView, dropSessionDidExit session: UIDropSession) {
		updateSpringLoading(hovering: nil)
	}

	/// 悬停计时:停在同一个收起的文件夹上够久就展开它。
	private func updateSpringLoading(hovering item: Item?) {

		// 悬停对象没变就**不要重新计时** —— 手指总有微动,每次都重置的话永远等不到展开
		guard springLoadTarget != item else { return }

		springLoadTarget = item
		springLoadTask?.cancel()
		springLoadTask = nil

		// 只对**收起着的文件夹**计时
		guard let item, case .folder = item, !expandedFolders.contains(item) else { return }

		springLoadTask = Task { @MainActor [weak self] in
			try? await Task.sleep(for: .seconds(Self.springLoadSeconds))
			guard !Task.isCancelled, let self, self.springLoadTarget == item else { return }
			self.expandFolder(item)
		}
	}

	/// 展开一个文件夹(拖拽途中用)。
	///
	/// ⚠️ 这里**只动这一个分组的快照**,不走 `reloadFromAccounts` ——
	/// 拖动期间整棵重画会把滚动位置顶掉,那正是刚修好的毛病。
	private func expandFolder(_ item: Item) {

		guard case .folder(let accountID, _) = item else { return }
		let sectionID = SectionID.account(accountID: accountID)
		guard dataSource.snapshot().sectionIdentifiers.contains(sectionID) else { return }

		var sectionSnapshot = dataSource.snapshot(for: sectionID)
		guard sectionSnapshot.items.contains(item), !sectionSnapshot.isExpanded(item) else { return }

		sectionSnapshot.expand([item])
		expandedFolders.insert(item)		// 记下来,免得下次整体刷新时又合上
		// ⚠️ 能安全走到这里的前提是:此刻手指悬在**文件夹行**上,
		// 那种落点用的是不插占位的 intent(见 dropSessionDidUpdate 里的长注释)。
		// 别把这个方法改成"任何时候都能调" —— 拖放占位存在时改数据源会直接崩。
		dataSource.apply(sectionSnapshot, to: sectionID, animatingDifferences: true)
	}

	/// 把屏幕上的一个位置,翻译成「要放进哪个容器」。**悬停判定和放手执行共用这一个入口。**
	private func dropDestination(at point: CGPoint) -> (container: Container, account: Account, accountID: String)? {

		guard let item = item(nearestTo: point),
			  let accountID = itemAccountID(item),
			  let account = AccountManager.shared.existingAccount(accountID: accountID) else { return nil }

		switch item {
		case .folder(_, let folderID):
			// 落在文件夹行上 → 进这个文件夹
			guard let folder = account.folders?.first(where: { $0.folderID == folderID }) else { return nil }
			return (folder, account, accountID)

		case .feed(_, _, let folderID):
			guard let folderID else {
				// 落在**顶层的源**上 → 放到账户顶层(也就是"拿出文件夹")
				return (account, account, accountID)
			}
			// 落在**某个文件夹里的源**上 → 也算进那个文件夹。
			// 这条是用户明确要求的:文件夹展开后,它下面那一片在观感上就是"文件夹里面"。
			guard let folder = account.folders?.first(where: { $0.folderID == folderID }) else { return nil }
			return (folder, account, accountID)
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

	// MARK: - 顶层调顺序(文件夹和没归档的源混在一起)

	/// 顶层的排序:**文件夹和散源是平级的**,可以互相插队。
	///
	/// 这和文件夹内部的排序(下面那个 `reorder`)是两件事:
	/// 那里只排源,这里排的是"账户底下那一串条目"。
	private func reorderTopLevel(_ items: [Item], droppedAt point: CGPoint, in account: Account) {

		let entries = FeedOrderStore.shared.sortedTopLevel(
			folders: account.sortedFolders ?? [],
			looseFeeds: Array(account.topLevelFeeds))

		var orderedKeys = entries.map { FeedOrderStore.shared.key(for: $0) }

		// 被拖的那些条目的键
		let movingKeys = items.compactMap { item -> String? in
			switch item {
			case .folder:
				guard let folder = folder(for: item) else { return nil }
				return FeedOrderStore.orderKey(forFolderNamed: folder.nameForDisplay)
			case .feed(_, let feedID, let folderID):
				return folderID == nil ? feedID : nil		// 文件夹**里**的源不参与顶层排序
			}
		}
		guard !movingKeys.isEmpty else { return }

		// 落点那一行 → 插到它后面
		var insertIndex = orderedKeys.count
		if let landedOn = item(nearestTo: point), let landedKey = topLevelKey(of: landedOn),
		   let index = orderedKeys.firstIndex(of: landedKey) {
			insertIndex = index + 1
		}

		// 摘除会让后面的下标前移,插入点要跟着往前挪同样的格数(同 reorder)
		let removedBefore = movingKeys.filter { key in
			guard let index = orderedKeys.firstIndex(of: key) else { return false }
			return index < insertIndex
		}.count
		orderedKeys.removeAll { movingKeys.contains($0) }
		insertIndex = max(0, min(insertIndex - removedBefore, orderedKeys.count))
		orderedKeys.insert(contentsOf: movingKeys, at: insertIndex)

		FeedOrderStore.shared.setOrder(orderedKeys)
		reloadFromAccounts(animated: true)
	}

	/// 这一行在顶层的排序键。**文件夹里的源没有顶层键** ——
	/// 落在它身上时应当归给它所在的那个文件夹(由调用方处理),不参与顶层排序。
	private func topLevelKey(of item: Item) -> String? {
		switch item {
		case .folder:
			guard let folder = folder(for: item) else { return nil }
			return FeedOrderStore.orderKey(forFolderNamed: folder.nameForDisplay)
		case .feed(_, let feedID, let folderID):
			return folderID == nil ? feedID : nil
		}
	}

	// MARK: - 文件夹内部调顺序

	/// 把拖动的源插到落点那一行**后面**,然后把这个容器的新次序记下来。
	///
	/// ⚠️ 顺序是**我们自己存的**(`FeedOrderStore`)—— 上游把源放在 `Set` 里,
	/// 模型层根本没有顺序可言,列表的排列是显示时按名字现算的。
	/// 所以"拖动排序"只能靠旁边存一份次序,再让**管理页和主列表用同一套排序规则**去读它。
	private func reorder(_ items: [Item], droppedAt point: CGPoint,
						 in target: (container: Container, account: Account, accountID: String)) {

		// 这个容器当前显示的全部源(已经是排好序的)
		let folderID = targetFolderID(of: target.container)
		let currentFeeds: [Feed]
		if let folder = target.container as? Folder {
			currentFeeds = sortedForDisplay(folder.topLevelFeeds)
		} else {
			currentFeeds = sortedForDisplay(target.account.topLevelFeeds)
		}

		var orderedIDs = currentFeeds.map { $0.feedID }
		let movingIDs = items.compactMap { item -> String? in
			guard case .feed(_, let feedID, _) = item else { return nil }
			return feedID
		}
		guard !movingIDs.isEmpty else { return }

		// 落点那一行(拖到空白处时是它上方最近的一行)
		var insertIndex = orderedIDs.count
		if let landedOn = item(nearestTo: point),
		   case .feed(_, let landedFeedID, let landedFolderID) = landedOn,
		   landedFolderID == folderID,
		   let index = orderedIDs.firstIndex(of: landedFeedID) {
			insertIndex = index + 1		// 插在它后面 —— 和"让开的那条缝"出现的位置一致
		}

		// 先把被拖的从原位摘掉,再插到新位置。
		// ⚠️ 摘除会让后面的下标前移,所以插入点要跟着往前挪同样的格数,否则会偏。
		let removedBefore = movingIDs.filter { id in
			guard let index = orderedIDs.firstIndex(of: id) else { return false }
			return index < insertIndex
		}.count
		orderedIDs.removeAll { movingIDs.contains($0) }
		insertIndex = max(0, min(insertIndex - removedBefore, orderedIDs.count))
		orderedIDs.insert(contentsOf: movingIDs, at: insertIndex)

		FeedOrderStore.shared.setOrder(orderedIDs)
		reloadFromAccounts(animated: true)
	}

	/// 找这个位置对应的那一行;**落在空白处也不算失败** —— 取它上方最近的一行。
	///
	/// 为什么要这样:行与行之间、一组的末尾,这些地方都没有 cell,
	/// 但用户明明是"往那一片"拖的。取上方最近的一行,正好能把这些空隙
	/// 归给它上面那个区域(文件夹的最后一个子行之下 = 还在这个文件夹的范围内)。
	private func item(nearestTo point: CGPoint) -> Item? {

		if let indexPath = collectionView.indexPathForItem(at: point) {
			return dataSource.itemIdentifier(for: indexPath)
		}

		var bestIndexPath: IndexPath?
		var bestBottom = -CGFloat.greatestFiniteMagnitude
		for indexPath in collectionView.indexPathsForVisibleItems {
			guard let attributes = collectionView.layoutAttributesForItem(at: indexPath) else { continue }
			let bottom = attributes.frame.maxY
			if bottom <= point.y, bottom > bestBottom {
				bestBottom = bottom
				bestIndexPath = indexPath
			}
		}
		// 落在所有内容**上方**(列表最顶端的空白)时返回 nil —— 那里没有明确归属,不猜。
		return bestIndexPath.flatMap { dataSource.itemIdentifier(for: $0) }
	}
}
#endif
