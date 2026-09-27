import UIKit
import Babel2Core

/// 编辑订阅源（2026-09-27 用户给参考截图，ADR-061）：改名 + 分配文件夹（可以同时放在几个文件夹里）。
///
/// 入口：首页长按订阅源 →「编辑」；文章列表页「更多」→「编辑」。推在导航栈上，外观与设置里的编辑页一致：
/// 顶栏 ✕ 取消 / ✓ 保存；订阅源名 + 订阅地址；「名称」输入框；「文件夹」——第一行「新建文件夹…」（建好自动选上），
/// 下面是这个账户的全部文件夹，选中的右侧打勾（可多选）。
/// - 一个都不选 = 放在首页最外层（账户顶层），不会因此取消订阅（用户选定）。
/// - 文件夹一项都没动过就不改位置（首页上它同时在最外层和某个文件夹里的情况原样保留）。
/// - 名字留空 = 不改名。
/// - 多个账户时只列这个源所在账户的文件夹（源不能跨账户放）。
/// - 「新建文件夹…」立即建好（即使之后点 ✕ 取消，文件夹也留着），与首页「+」新建一样。
@MainActor
final class Babel2FeedEditViewController: UIViewController {
	private let feedID: FeedSnapshot.ID
	private let originalName: String
	private let feedURL: String?
	private let accountTitle: String?
	private let libraryEditing: Babel2LibraryEditing
	private let bundle: Bundle
	private let initialSelection: Set<FolderSnapshot.ID>
	private var folders: [Babel2FeedLocation]
	private var selection: Set<FolderSnapshot.ID>
	private var isSaving = false

	/// 保存成功：新名字（没改名时为 nil）。
	var onSaved: ((String?) -> Void)?
	/// 保存成功或新建了文件夹：首页要重新加载。
	var onLibraryChanged: (() -> Void)?

	private let navigationBar: Babel2SettingsNavigationBar
	private let scrollView = UIScrollView()
	private let contentStack = UIStackView()
	private let folderStack = UIStackView()
	private var nameField: Babel2SettingsTextField!
	private var folderRows = [FolderSnapshot.ID: Babel2SettingsChoiceRow]()

	/// 取不到位置（源已经不在了）时返回 nil。
	static func make(feed: FeedSnapshot, currentName: String? = nil, editing: Babel2LibraryEditing, bundle: Bundle = .main) -> Babel2FeedEditViewController? {
		guard let placement = editing.placement(feed.id) else { return nil }
		return Babel2FeedEditViewController(feedID: feed.id, name: currentName ?? feed.title, feedURL: editing.feedURL(feed.id),
			placement: placement, editing: editing, bundle: bundle)
	}

	init(feedID: FeedSnapshot.ID, name: String, feedURL: String?, placement: Babel2FeedPlacement, editing: Babel2LibraryEditing, bundle: Bundle = .main) {
		self.feedID = feedID
		self.originalName = name
		self.feedURL = feedURL
		self.accountTitle = placement.accountTitle
		self.libraryEditing = editing
		self.bundle = bundle
		folders = placement.destinations.filter { $0.folderID != nil }
		let current = Set(placement.current.compactMap(\.folderID))
		initialSelection = current
		selection = current
		navigationBar = Babel2SettingsNavigationBar(kind: .editor, title: Babel2Localization.text(.editFeed, bundle: bundle))
		super.init(nibName: nil, bundle: nil)
		restorationIdentifier = "babel2.feed-edit"
	}

	required init?(coder: NSCoder) { nil }

	private func text(_ key: Babel2LocalizationKey) -> String {
		Babel2Localization.text(key, bundle: bundle)
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		view.backgroundColor = Babel2SettingsStyle.background
		scrollView.alwaysBounceVertical = true
		scrollView.keyboardDismissMode = .interactive
		contentStack.axis = .vertical
		folderStack.axis = .vertical
		let statusBackdrop = UIView()
		statusBackdrop.backgroundColor = Babel2SettingsStyle.background
		for item in [scrollView, navigationBar, statusBackdrop, contentStack] as [UIView] {
			item.translatesAutoresizingMaskIntoConstraints = false
		}
		view.addSubview(scrollView)
		view.addSubview(navigationBar)
		view.addSubview(statusBackdrop)
		scrollView.addSubview(contentStack)
		NSLayoutConstraint.activate([
			statusBackdrop.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			statusBackdrop.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			statusBackdrop.topAnchor.constraint(equalTo: view.topAnchor),
			statusBackdrop.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
			navigationBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			navigationBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			navigationBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
			scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			scrollView.topAnchor.constraint(equalTo: navigationBar.bottomAnchor),
			scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
			contentStack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: Babel2SettingsStyle.sideInset),
			contentStack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -Babel2SettingsStyle.sideInset),
			contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: Babel2SettingsStyle.contentTopInset),
			contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24)
		])
		navigationBar.leadingButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
		navigationBar.saveButton.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)
		buildContent()
	}

	private func buildContent() {
		// 订阅源名 + 订阅地址
		let titleLabel = UILabel()
		titleLabel.text = originalName
		titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
		titleLabel.textColor = Babel2SettingsStyle.primaryText
		titleLabel.numberOfLines = 2
		titleLabel.accessibilityIdentifier = "babel2.feed-edit.title"
		contentStack.addArrangedSubview(titleLabel)
		if let feedURL {
			contentStack.setCustomSpacing(4, after: titleLabel)
			let urlLabel = UILabel()
			urlLabel.text = Self.displayAddress(feedURL)
			urlLabel.font = .systemFont(ofSize: 12, weight: .regular)
			urlLabel.textColor = Babel2SettingsStyle.secondaryText
			urlLabel.lineBreakMode = .byTruncatingMiddle
			urlLabel.accessibilityIdentifier = "babel2.feed-edit.url"
			contentStack.addArrangedSubview(urlLabel)
			contentStack.setCustomSpacing(20, after: urlLabel)
		} else {
			contentStack.setCustomSpacing(20, after: titleLabel)
		}

		// 名称
		nameField = Babel2SettingsTextField(label: text(.feedNameLabel), text: originalName, secure: false,
			identifier: "babel2.feed-edit.name")
		nameField.textField.autocapitalizationType = .sentences
		contentStack.addArrangedSubview(nameField)
		contentStack.setCustomSpacing(16, after: nameField)

		// 文件夹：新建 + 全部文件夹（可多选）
		let header = accountTitle.map { text(.folders) + " · " + $0 } ?? text(.folders)
		contentStack.addArrangedSubview(Babel2SettingsSectionHeader(title: header))
		let newFolder = Babel2SettingsActionRow(title: text(.newFolderEllipsis))
		newFolder.titleLabel.textColor = Babel2SettingsStyle.secondaryText
		newFolder.accessibilityIdentifier = "babel2.feed-edit.new-folder"
		newFolder.onTap = { [weak self] in self?.presentNewFolder() }
		contentStack.addArrangedSubview(newFolder)
		contentStack.addArrangedSubview(folderStack)
		for folder in folders {
			addFolderRow(folder)
		}
		let note = Babel2SettingsNoteLabel(text: text(.feedEditFolderNote), size: 12)
		contentStack.setCustomSpacing(10, after: folderStack)
		contentStack.addArrangedSubview(note)
	}

	private func addFolderRow(_ folder: Babel2FeedLocation) {
		guard let id = folder.folderID else { return }
		let row = Babel2SettingsChoiceRow(title: folder.title, isSelected: selection.contains(id))
		row.accessibilityIdentifier = "babel2.feed-edit.folder." + id
		row.onTap = { [weak self, weak row] in
			guard let self, let row else { return }
			self.toggle(id, row: row)
		}
		folderRows[id] = row
		folderStack.addArrangedSubview(row)
	}

	private func toggle(_ id: FolderSnapshot.ID, row: Babel2SettingsChoiceRow) {
		if selection.contains(id) {
			selection.remove(id)
		} else {
			selection.insert(id)
		}
		row.setSelected(selection.contains(id))
	}

	/// 订阅地址去掉 https:// 前缀显示（截图同样写法），太长时中间省略。
	static func displayAddress(_ url: String) -> String {
		for prefix in ["https://", "http://"] where url.lowercased().hasPrefix(prefix) {
			return String(url.dropFirst(prefix.count))
		}
		return url
	}

	// MARK: 新建文件夹

	private func presentNewFolder() {
		view.endEditing(true)
		let alert = UIAlertController(title: text(.newFolder), message: nil, preferredStyle: .alert)
		alert.addTextField { [weak self] field in
			field.placeholder = self?.text(.folderName)
			field.clearButtonMode = .whileEditing
			field.accessibilityIdentifier = "babel2.feed-edit.folder-name"
		}
		alert.addAction(UIAlertAction(title: text(.cancel), style: .cancel))
		let create = UIAlertAction(title: text(.create), style: .default) { [weak self, weak alert] _ in
			let name = Babel2LibraryEditor.cleanName(alert?.textFields?.first?.text)
			guard !name.isEmpty else { return }
			Task { @MainActor [weak self] in await self?.createFolder(named: name) }
		}
		alert.addAction(create)
		alert.preferredAction = create
		lastAlertForTesting = alert
		present(alert, animated: true)
	}

	/// 在这个源自己的账户里建文件夹，建好插在列表里（按名字排序的位置）并选上。
	func createFolder(named name: String) async {
		switch await libraryEditing.createFolder(name, feedID.accountID) {
		case .success(let id):
			onLibraryChanged?()
			let location = Babel2FeedLocation(folderID: id, title: name)
			selection.insert(id)
			let index = folders.firstIndex { $0.title.localizedCaseInsensitiveCompare(name) == .orderedDescending } ?? folders.count
			folders.insert(location, at: index)
			addFolderRow(location)
			if let row = folderRows[id] {
				folderStack.removeArrangedSubview(row)
				folderStack.insertArrangedSubview(row, at: index)
			}
		case .failure(let failure):
			report(failure.message)
		}
	}

	// MARK: 取消 / 保存

	@objc private func cancelTapped() {
		view.endEditing(true)
		close()
	}

	private func close() {
		didCloseForTesting = true
		// 页面还在滑入 / 滑出的动画里时系统会忽略返回：等这段动画结束再返回
		if let coordinator = navigationController?.transitionCoordinator {
			coordinator.animate(alongsideTransition: nil) { [weak self] _ in self?.close() }
			return
		}
		if let navigation = navigationController as? Babel2NavigationController {
			_ = navigation.popBabel2(animated: true)
		} else {
			navigationController?.popViewController(animated: true)
		}
	}

	/// 要做哪些改动（纯规则，测试直接核对）：
	/// - rename：名字去掉首尾空白后非空、且与原名不同才改
	/// - folders：文件夹选择动过才改（按列表顺序；空 = 放到最外层）
	static func changes(originalName: String, typedName: String, initial: Set<FolderSnapshot.ID>, selection: Set<FolderSnapshot.ID>,
		order: [FolderSnapshot.ID]) -> (rename: String?, folders: [FolderSnapshot.ID]?) {
		let name = typedName.trimmingCharacters(in: .whitespacesAndNewlines)
		let rename = !name.isEmpty && name != originalName ? name : nil
		let folders = selection == initial ? nil : order.filter { selection.contains($0) }
		return (rename, folders)
	}

	@objc private func saveTapped() {
		view.endEditing(true)
		guard !isSaving else { return }
		let plan = Self.changes(originalName: originalName, typedName: nameField.textField.text ?? "", initial: initialSelection,
			selection: selection, order: folders.compactMap(\.folderID))
		guard plan.rename != nil || plan.folders != nil else {
			close()
			return
		}
		isSaving = true
		navigationBar.saveButton.isEnabled = false
		Task { @MainActor [weak self] in
			await self?.apply(plan)
		}
	}

	private func apply(_ plan: (rename: String?, folders: [FolderSnapshot.ID]?)) async {
		defer {
			isSaving = false
			navigationBar.saveButton.isEnabled = true
		}
		if let rename = plan.rename, let message = await libraryEditing.renameFeed(feedID, rename) {
			report(message)
			return
		}
		if let folders = plan.folders, let message = await libraryEditing.setFeedFolders(feedID, folders) {
			// 名字可能已经改好了：照样让首页刷新
			if plan.rename != nil { onLibraryChanged?() }
			report(message)
			return
		}
		onLibraryChanged?()
		onSaved?(plan.rename)
		close()
	}

	private func report(_ message: String) {
		let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
		alert.addAction(UIAlertAction(title: text(.ok), style: .default))
		lastAlertForTesting = alert
		present(alert, animated: true)
	}

	// MARK: 仅供自动化测试

	private(set) var lastAlertForTesting: UIAlertController?
	/// 已经要求返回（点了 ✕、或保存成功 / 没有改动）。
	private(set) var didCloseForTesting = false
	var nameFieldForTesting: UITextField { nameField.textField }
	var folderTitlesForTesting: [String] { folders.map(\.title) }
	var selectionForTesting: Set<FolderSnapshot.ID> { selection }
	func tapFolderForTesting(_ id: FolderSnapshot.ID) {
		guard let row = folderRows[id] else { return }
		toggle(id, row: row)
	}
	func saveForTesting() { saveTapped() }
	func cancelForTesting() { cancelTapped() }
	var isSavingForTesting: Bool { isSaving }
}
