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

	/// 一个分组。**每个账户拆成两组**:上面是文件夹,下面是"不在文件夹里"的源。
	///
	/// ⚠️ 为什么非拆不可(2026-07-23 用户实测发现):
	/// 本来是一个账户一组、文件夹在前散源在后,靠**缩进**区分"文件夹里的源"和"散源"。
	/// 但一进编辑模式,每行前面要插一个勾选圈、内容整体右移,
	/// **恰好把那点缩进差吃掉了** —— 展开最后一个文件夹后,里面的源和下面的散源看起来一样深,
	/// 根本分不清某个源到底归没归档。
	/// 与其去调几个点的缩进差(长列表里照样难分辨),不如**从结构上分开**:
	/// 分组标题一摆,不管在不在编辑模式都一目了然,顺便给没归类的源一个明确的名分。
	private enum SectionID: Hashable {
		case folders(accountID: String)
		case looseFeeds(accountID: String)
	}

	// MARK: - 界面部件

	private var collectionView: UICollectionView!
	private var dataSource: UICollectionViewDiffableDataSource<SectionID, Item>!

	/// 哪些文件夹当前是展开的。列表刷新时要照着它把展开状态复原,
	/// 否则每次收到一条通知,用户手动展开的文件夹就会全部合上。
	private var expandedFolders = Set<Item>()

	/// 正在等待执行的刷新(用来做防抖,见 `scheduleReload`)
	private var pendingReloadTask: Task<Void, Never>?

	/// 编辑模式下已勾选的源。
	///
	/// ⚠️ 为什么不直接问 `collectionView.indexPathsForSelectedItems`:
	/// 列表随时会因为一条通知整棵重画,重画后 UIKit 那边的选中就没了。
	/// 自己记一份,刷新后还能把勾恢复上。
	private var selectedFeeds = Set<Item>()

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
		selectedFeeds.removeAll()
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

		let count = selectedFeeds.count
		let title = count == 0 ? "移动到…" : "移动 \(count) 项到…"
		let moveItem = UIBarButtonItem(title: title, style: .plain, target: self, action: #selector(moveTapped))
		moveItem.isEnabled = count > 0		// 一个都没选时置灰,免得点了没反应让人以为坏了

		toolbarItems = [
			UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
			moveItem,
			UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
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
			// `.header` 样式 = **点整行**就能展开/收起,不用去瞄那个小三角
			cell.accessories = [.outlineDisclosure(options: .init(style: .header))]
		}

		// 订阅源那一行
		let feedRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, Item> { [weak self] cell, _, item in
			guard let self, let feed = self.feed(for: item) else { return }
			var content = cell.defaultContentConfiguration()
			content.text = feed.nameForDisplay
			content.image = IconImageCache.shared.imageForFeed(feed)?.image
			content.imageProperties.maximumSize = CGSize(width: 24, height: 24)
			content.imageProperties.cornerRadius = 4
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

	/// 分组标题该写什么。
	///
	/// 「不在文件夹里」这个标题**只在该账户确实有文件夹时才用** ——
	/// 一个文件夹都没有的账户,所有源本来就都是散的,再写"不在文件夹里"是废话,
	/// 那时候把账户名写在这儿更有用(多账户时才分得清是谁的源)。
	private func headerTitle(for sectionID: SectionID) -> String {
		switch sectionID {
		case .folders(let accountID):
			return AccountManager.shared.existingAccount(accountID: accountID)?.nameForDisplay ?? ""
		case .looseFeeds(let accountID):
			guard let account = AccountManager.shared.existingAccount(accountID: accountID) else { return "" }
			let hasFolders = !(account.folders?.isEmpty ?? true)
			return hasFolders ? "不在文件夹里" : account.nameForDisplay
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

		// 先把这一轮要有哪些分组定下来。**空的分组不放** ——
		// 否则会出现一个只有标题、底下什么都没有的空壳。
		var snapshot = NSDiffableDataSourceSnapshot<SectionID, Item>()
		for account in accounts {
			if !(account.sortedFolders ?? []).isEmpty {
				snapshot.appendSections([.folders(accountID: account.accountID)])
			}
			if !account.topLevelFeeds.isEmpty {
				snapshot.appendSections([.looseFeeds(accountID: account.accountID)])
			}
		}
		dataSource.apply(snapshot, animatingDifferences: false)

		for account in accounts {

			// —— 上半组:文件夹,每个文件夹下面挂它自己的源 ——
			let folders = account.sortedFolders ?? []
			if !folders.isEmpty {
				var foldersSection = NSDiffableDataSourceSectionSnapshot<Item>()
				for folder in folders {
					let folderItem = Item.folder(accountID: account.accountID, folderID: folder.folderID)
					foldersSection.append([folderItem])
					let feedItems = sortedByName(folder.topLevelFeeds).map {
						Item.feed(accountID: account.accountID, feedID: $0.feedID, folderID: folder.folderID)
					}
					foldersSection.append(feedItems, to: folderItem)
					if expandedFolders.contains(folderItem) {
						foldersSection.expand([folderItem])
					}
				}
				dataSource.apply(foldersSection, to: .folders(accountID: account.accountID), animatingDifferences: animated)
			}

			// —— 下半组:不在任何文件夹里的源 ——
			let looseFeeds = sortedByName(account.topLevelFeeds)
			if !looseFeeds.isEmpty {
				var looseSection = NSDiffableDataSourceSectionSnapshot<Item>()
				looseSection.append(looseFeeds.map {
					Item.feed(accountID: account.accountID, feedID: $0.feedID, folderID: nil)
				})
				dataSource.apply(looseSection, to: .looseFeeds(accountID: account.accountID), animatingDifferences: animated)
			}
		}

		restoreSelection()
	}

	/// 重画之后把勾选恢复上 —— UIKit 那边的选中会随着重画丢掉,而用户勾了半天不该白勾。
	private func restoreSelection() {
		guard isEditing else { return }
		for item in selectedFeeds {
			guard let indexPath = dataSource.indexPath(for: item) else { continue }
			collectionView.selectItem(at: indexPath, animated: false, scrollPosition: [])
		}
		// 选中的源可能已经被别处删掉了,顺手把已经不存在的清掉,免得计数虚高
		selectedFeeds = selectedFeeds.filter { dataSource.indexPath(for: $0) != nil }
		updateToolbar()
	}

	private func sortedByName(_ feeds: Set<Feed>) -> [Feed] {
		feeds.sorted { $0.nameForDisplay.localizedStandardCompare($1.nameForDisplay) == .orderedAscending }
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

	private func scheduleReload() {
		pendingReloadTask?.cancel()
		pendingReloadTask = Task { @MainActor [weak self] in
			try? await Task.sleep(for: .seconds(Self.reloadDebounceSeconds))
			guard !Task.isCancelled else { return }
			self?.reloadFromAccounts(animated: true)
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

		// 编辑模式:只有**源**能勾。文件夹不参与多选 ——
		// Phase B 只做"移动源",而且文件夹那一行还要留着点开/收起的功能。
		if case .feed = dataSource.itemIdentifier(for: indexPath) { return true }
		return false
	}

	func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {

		guard isEditing else {
			collectionView.deselectItem(at: indexPath, animated: true)
			return
		}
		guard let item = dataSource.itemIdentifier(for: indexPath) else { return }
		selectedFeeds.insert(item)
		updateToolbar()
	}

	func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
		guard isEditing, let item = dataSource.itemIdentifier(for: indexPath) else { return }
		selectedFeeds.remove(item)
		updateToolbar()
	}
}

// MARK: - 移动源:选好了往哪儿放

extension FolderManagerViewController {

	@objc private func moveTapped() {

		let items = Array(selectedFeeds)
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

// MARK: - 拖拽:把源拖进文件夹 / 拖出到顶层
//
// ⚠️ 定位是**辅助手段**(用户拍板):适合"顺手把眼前这个源丢进旁边的文件夹",
// 批量整理仍然走「勾选 + 移动到…」。所以这里刻意只认两种落点、不做自动滚动 ——
// 拖着一个源满屏找文件夹本来就不是好体验,做多了反而鼓励用户走难走的路。

extension FolderManagerViewController: UICollectionViewDragDelegate {

	func collectionView(_ collectionView: UICollectionView,
						itemsForBeginning session: UIDragSession,
						at indexPath: IndexPath) -> [UIDragItem] {

		// 只让**源**能被拖起来。文件夹不能拖 —— 没有子文件夹,拖它没有任何去处。
		guard let item = dataSource.itemIdentifier(for: indexPath),
			  case .feed = item,
			  let feed = feed(for: item) else { return [] }

		let dragItem = UIDragItem(itemProvider: NSItemProvider(object: feed.nameForDisplay as NSString))
		// 真正靠的是这个 localObject(拖到哪儿之后按它找回是哪个源);
		// 上面那个文字 provider 只是为了拖动时有个像样的预览。
		dragItem.localObject = item
		return [dragItem]
	}
}

extension FolderManagerViewController: UICollectionViewDropDelegate {

	func collectionView(_ collectionView: UICollectionView,
						dropSessionDidUpdate session: UIDropSession,
						withDestinationIndexPath destinationIndexPath: IndexPath?) -> UICollectionViewDropProposal {

		// 只接受本页面内部拖过来的东西(从别的 app 拖文字进来没有意义)
		guard session.localDragSession != nil,
			  let destinationIndexPath,
			  let target = dataSource.itemIdentifier(for: destinationIndexPath) else {
			return UICollectionViewDropProposal(operation: .cancel)
		}

		switch target {
		case .folder:
			// 悬停在文件夹行上 → 放进这个文件夹
			return UICollectionViewDropProposal(operation: .move, intent: .insertIntoDestinationIndexPath)
		case .feed(_, _, let folderID):
			// 悬停在**顶层的源**上 → 表示"拿出文件夹,放到顶层"。
			// 悬停在文件夹里的源上则不接受:那种落点很含糊(是想进这个文件夹?还是排序?),
			// 与其猜错不如不接。
			return UICollectionViewDropProposal(operation: folderID == nil ? .move : .forbidden,
												intent: .insertAtDestinationIndexPath)
		}
	}

	func collectionView(_ collectionView: UICollectionView, performDropWith coordinator: UICollectionViewDropCoordinator) {

		guard let destinationIndexPath = coordinator.destinationIndexPath,
			  let target = dataSource.itemIdentifier(for: destinationIndexPath) else { return }

		let items = coordinator.items.compactMap { $0.dragItem.localObject as? Item }
		guard !items.isEmpty else { return }

		// 目标容器:文件夹行 → 那个文件夹;顶层的源 → 账户本身(即拿出文件夹)
		let destination: Container?
		switch target {
		case .folder:
			destination = folder(for: target)
		case .feed(_, _, let folderID):
			destination = folderID == nil ? account(for: target) : nil
		}

		guard let destination,
			  let accountID = itemAccountID(target),
			  let account = AccountManager.shared.existingAccount(accountID: accountID) else { return }

		// 跨账户拖拽同样不做(理由见 moveTapped)
		guard items.allSatisfy({ itemAccountID($0) == accountID }) else {
			presentMessage("暂不支持跨账户移动", "请分别在各自的账户里整理。")
			return
		}

		performMove(items, to: destination, in: account)
	}
}

#endif
