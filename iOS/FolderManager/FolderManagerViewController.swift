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

	// MARK: - 界面部件

	private var collectionView: UICollectionView!
	private var dataSource: UICollectionViewDiffableDataSource<String, Item>!

	/// 哪些文件夹当前是展开的。列表刷新时要照着它把展开状态复原,
	/// 否则每次收到一条通知,用户手动展开的文件夹就会全部合上。
	private var expandedFolders = Set<Item>()

	/// 正在等待执行的刷新(用来做防抖,见 `scheduleReload`)
	private var pendingReloadTask: Task<Void, Never>?

	// MARK: - 生命周期

	override func viewDidLoad() {
		super.viewDidLoad()

		title = "文件夹管理"
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

		navigationItem.leftBarButtonItem = UIBarButtonItem(
			title: "完成", style: .done, target: self, action: #selector(doneTapped))

		// 右上角先只放「新建文件夹」。Phase B 要在这里加「编辑」(多选),
		// 到时候两个按钮并排放,或者把新建收进一个 `…` 菜单里,看那时的拥挤程度再定。
		let addFolderItem = UIBarButtonItem(
			image: UIImage(systemName: "folder.badge.plus"),
			style: .plain, target: self, action: #selector(addFolderTapped))
		addFolderItem.accessibilityLabel = "新建文件夹"
		navigationItem.rightBarButtonItem = addFolderItem
	}

	@objc private func doneTapped() {
		dismiss(animated: true)
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
			cell.accessories = []
		}

		dataSource = UICollectionViewDiffableDataSource<String, Item>(collectionView: collectionView) { collectionView, indexPath, item in
			switch item {
			case .folder:
				return collectionView.dequeueConfiguredReusableCell(using: folderRegistration, for: indexPath, item: item)
			case .feed:
				return collectionView.dequeueConfiguredReusableCell(using: feedRegistration, for: indexPath, item: item)
			}
		}

		// 分组头 = 账户名
		let headerRegistration = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(
			elementKind: UICollectionView.elementKindSectionHeader) { [weak self] headerView, _, indexPath in
			guard let self else { return }
			let accountID = self.dataSource.snapshot().sectionIdentifiers[indexPath.section]
			var content = headerView.defaultContentConfiguration()
			content.text = AccountManager.shared.existingAccount(accountID: accountID)?.nameForDisplay ?? ""
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

		var snapshot = NSDiffableDataSourceSnapshot<String, Item>()
		snapshot.appendSections(accounts.map { $0.accountID })
		dataSource.apply(snapshot, animatingDifferences: false)

		for account in accounts {

			var section = NSDiffableDataSourceSectionSnapshot<Item>()

			// 先文件夹(按名字排),每个文件夹下面挂它自己的源
			for folder in account.sortedFolders ?? [] {
				let folderItem = Item.folder(accountID: account.accountID, folderID: folder.folderID)
				section.append([folderItem])
				let feedItems = sortedByName(folder.topLevelFeeds).map {
					Item.feed(accountID: account.accountID, feedID: $0.feedID, folderID: folder.folderID)
				}
				section.append(feedItems, to: folderItem)
				if expandedFolders.contains(folderItem) {
					section.expand([folderItem])
				}
			}

			// 再是不在任何文件夹里的源
			let looseFeedItems = sortedByName(account.topLevelFeeds).map {
				Item.feed(accountID: account.accountID, feedID: $0.feedID, folderID: nil)
			}
			section.append(looseFeedItems)

			dataSource.apply(section, to: account.accountID, animatingDifferences: animated)
		}
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
		let alert = UIAlertController(title: title, message: error.localizedDescription, preferredStyle: .alert)
		alert.addAction(UIAlertAction(title: "好", style: .default))
		present(alert, animated: true)
	}
}

// MARK: - 点击行为

extension FolderManagerViewController: UICollectionViewDelegate {

	func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
		// Phase A 还没有选中态要表达(多选是 Phase B 的事),点完就取消高亮。
		//
		// ⚠️ 这里**故意不用 `shouldSelectItemAt` 返回 false 来禁止选中**:
		// 文件夹行的展开三角用的是 `.header` 样式(点整行就能展开),
		// 而那个样式是搭在 cell 的点击上的 —— 一旦把选中整个禁掉,
		// 很可能连展开都点不动了。用「允许选中、马上取消」绕开这个耦合更稳。
		collectionView.deselectItem(at: indexPath, animated: true)
	}
}

#endif
