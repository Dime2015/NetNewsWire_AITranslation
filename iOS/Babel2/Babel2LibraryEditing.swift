import UIKit
import PhotosUI
import Babel2Core

// 首页整理文件夹与订阅源（2026-09-27 用户反馈第 4 条，ADR-045）与自定义订阅源图标（第 8 条后半，ADR-046）。
// 页面只拿到值（编号、名字）；真正的增删改由装配层注入，正式实现走账户公开接口（Babel2LiveLibraryEditing）。

/// 订阅源可以待的位置：某个文件夹，或「不放在文件夹里」（账户顶层，folderID 为 nil）。
struct Babel2FeedLocation: Hashable, Sendable {
	let folderID: FolderSnapshot.ID?
	let title: String
}

/// 一个订阅源在账户里的位置。
struct Babel2FeedPlacement: Equatable, Sendable {
	/// 有多个账户时是哪个账户；只有一个账户时为 nil（不显示）
	let accountTitle: String?
	/// 现在在哪些位置。同一个账户里一个源可以同时在几个文件夹里——首页上看到的「重复」就是这个
	let current: [Babel2FeedLocation]
	/// 可以移去的位置：顶层 + 这个账户的全部文件夹（含空文件夹）
	let destinations: [Babel2FeedLocation]
}

struct Babel2FolderInfo: Equatable, Sendable {
	let title: String
	let feedCount: Int
	/// 有多个账户时是哪个账户
	let accountTitle: String?
}

struct Babel2AccountChoice: Hashable, Sendable {
	let id: String
	let title: String
}

struct Babel2EditFailure: Error, Equatable {
	let message: String
}

/// 自定义订阅源图标的读写（ADR-046），由装配层注入。
struct Babel2CustomFeedIconStore {
	let hasCustomIcon: @MainActor (FeedSnapshot.ID) -> Bool
	/// 传 nil = 恢复默认图标。成功返回 true。
	let setCustomIcon: @MainActor (FeedSnapshot.ID, Data?) -> Bool
}

/// 首页整理用到的全部操作，由装配层注入。失败时返回说明文字（成功为 nil）。
struct Babel2LibraryEditing {
	let accounts: @MainActor () -> [Babel2AccountChoice]
	let folderInfo: @MainActor (FolderSnapshot.ID) -> Babel2FolderInfo?
	let placement: @MainActor (FeedSnapshot.ID) -> Babel2FeedPlacement?
	let createFolder: @MainActor (_ name: String, _ accountID: String) async -> Result<FolderSnapshot.ID, Babel2EditFailure>
	let renameFolder: @MainActor (FolderSnapshot.ID, String) async -> String?
	/// keepFeeds = true：只删文件夹，只在里面的源移到顶层；false：连同只在这个文件夹里的源一起删除。
	let deleteFolder: @MainActor (FolderSnapshot.ID, _ keepFeeds: Bool) async -> String?
	/// from / to 为 nil 表示顶层。目标位置本来就有这个源时，只从原位置移出。
	let moveFeed: @MainActor (FeedSnapshot.ID, _ from: FolderSnapshot.ID?, _ to: FolderSnapshot.ID?) async -> String?
	/// 从某个文件夹移出（只在它同时还在别处时提供，否则等于取消订阅）。
	let removeFeedFromFolder: @MainActor (FeedSnapshot.ID, FolderSnapshot.ID) async -> String?
	let renameFeed: @MainActor (FeedSnapshot.ID, String) async -> String?
	let unsubscribe: @MainActor (FeedSnapshot.ID) async -> String?
	var customIcons: Babel2CustomFeedIconStore?
}

/// 首页长按菜单与「+」菜单的全部交互（ADR-045）。
/// 菜单用全 app 统一的毛玻璃菜单；输入名字、确认删除用屏幕中间的系统对话框（ADR-032，用户同意保留系统样式）。
@MainActor
final class Babel2LibraryEditor {
	let editing: Babel2LibraryEditing
	private weak var host: UIViewController?
	private let bundle: Bundle
	/// 改动成功后调用：首页立即重新加载，不等账户的通知。
	var onChange: (() -> Void)?
	/// 仅供自动化测试：最近一次弹出的菜单 / 系统对话框。
	private(set) weak var lastMenuForTesting: Babel2GlassMenu?
	private(set) var lastAlertForTesting: UIAlertController?

	init(editing: Babel2LibraryEditing, host: UIViewController, bundle: Bundle = .main) {
		self.editing = editing
		self.host = host
		self.bundle = bundle
	}

	private func text(_ key: Babel2LocalizationKey) -> String {
		Babel2Localization.text(key, bundle: bundle)
	}

	private func quoted(_ name: String) -> String {
		String(format: text(.quotedName), name)
	}

	static func cleanName(_ text: String?) -> String {
		(text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
	}

	@discardableResult
	private func showMenu(_ sections: [[Babel2MenuItem]], title: String?, from anchor: UIView) -> Babel2GlassMenu? {
		guard let hostView = host?.viewIfLoaded else { return nil }
		// 触发的那一行在等待期间被列表重用 / 移走了：退到屏幕中间弹出
		let anchorView = anchor.window != nil && anchor.isDescendant(of: hostView) ? anchor : hostView
		let menu = Babel2GlassMenu.present(sections: sections, title: title, from: anchorView, in: hostView)
		lastMenuForTesting = menu
		return menu
	}

	private func showAlert(_ alert: UIAlertController) {
		lastAlertForTesting = alert
		guard let host else { return }
		guard let presented = host.presentedViewController else {
			host.present(alert, animated: true)
			return
		}
		// 上一个对话框刚点完、还在收起：等它收起再弹；否则叠在它上面
		guard presented.isBeingDismissed else {
			presented.present(alert, animated: true)
			return
		}
		Task { @MainActor [weak host] in
			try? await Task.sleep(for: .milliseconds(400))
			guard let host else { return }
			(host.presentedViewController ?? host).present(alert, animated: true)
		}
	}

	/// 执行一个改动：失败弹出说明；成功让首页立即重新加载。
	private func run(_ operation: @MainActor () async -> String?) async {
		if let message = await operation() {
			report(message)
		} else {
			onChange?()
		}
	}

	private func report(_ message: String) {
		let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
		alert.addAction(UIAlertAction(title: text(.ok), style: .default))
		showAlert(alert)
	}

	/// 输入名字的系统对话框（新建文件夹 / 重命名）。名字去掉首尾空白后为空时什么也不做。
	private func presentNameAlert(title: String, initial: String?, placeholder: String?, actionTitle: String,
		identifier: String, onSubmit: @escaping @MainActor (String) async -> Void) {
		let alert = UIAlertController(title: title, message: nil, preferredStyle: .alert)
		alert.addTextField { field in
			field.text = initial
			field.placeholder = placeholder
			field.clearButtonMode = .whileEditing
			field.accessibilityIdentifier = identifier
		}
		alert.addAction(UIAlertAction(title: text(.cancel), style: .cancel))
		let submit = UIAlertAction(title: actionTitle, style: .default) { [weak alert] _ in
			let name = Self.cleanName(alert?.textFields?.first?.text)
			guard !name.isEmpty else { return }
			Task { @MainActor in await onSubmit(name) }
		}
		alert.addAction(submit)
		alert.preferredAction = submit
		showAlert(alert)
	}

	// MARK: - 「+」：添加订阅 / 新建文件夹

	func presentAddMenu(from anchor: UIView, addSubscription: @escaping @MainActor () -> Void) {
		showMenu(addMenuSections(from: anchor, addSubscription: addSubscription), title: nil, from: anchor)
	}

	func addMenuSections(from anchor: UIView, addSubscription: @escaping @MainActor () -> Void) -> [[Babel2MenuItem]] {
		[[
			Babel2MenuItem(title: text(.addSubscription), image: UIImage(systemName: "plus"),
				identifier: "babel2.add.subscription", handler: addSubscription),
			Babel2MenuItem(title: text(.newFolder), image: UIImage(systemName: "folder.badge.plus"),
				identifier: "babel2.add.folder") { [weak self, weak anchor] in
				guard let self, let anchor else { return }
				self.startNewFolder(from: anchor)
			}
		]]
	}

	/// 新建文件夹：有多个账户时先选放进哪个账户，再输入名字。
	/// - accountID：已经确定账户时（「移到文件夹」里新建，只能建在这个源自己的账户里）
	/// - then：建好后接着做的事（例如把源移进新文件夹）
	func startNewFolder(from anchor: UIView, accountID: String? = nil, then: (@MainActor (FolderSnapshot.ID) -> Void)? = nil) {
		if let accountID {
			presentNewFolderAlert(accountID: accountID, then: then)
			return
		}
		let accounts = editing.accounts()
		guard let first = accounts.first else {
			report(text(.noSubscriptionDestination))
			return
		}
		guard accounts.count > 1 else {
			presentNewFolderAlert(accountID: first.id, then: then)
			return
		}
		let items = accounts.map { account in
			Babel2MenuItem(title: account.title, image: UIImage(systemName: "person.crop.circle"),
				identifier: "babel2.add.folder.account.\(account.id)") { [weak self] in
				self?.presentNewFolderAlert(accountID: account.id, then: then)
			}
		}
		showMenu([items], title: text(.newFolderInAccount), from: anchor)
	}

	func presentNewFolderAlert(accountID: String, then: (@MainActor (FolderSnapshot.ID) -> Void)? = nil) {
		presentNameAlert(title: text(.newFolder), initial: nil, placeholder: text(.folderName), actionTitle: text(.create),
			identifier: "babel2.library.folder-name") { [weak self] name in
			await self?.performCreateFolder(named: name, accountID: accountID, then: then)
		}
	}

	func performCreateFolder(named name: String, accountID: String, then: (@MainActor (FolderSnapshot.ID) -> Void)? = nil) async {
		switch await editing.createFolder(name, accountID) {
		case .success(let folderID):
			onChange?()
			then?(folderID)
		case .failure(let failure):
			report(failure.message)
		}
	}

	// MARK: - 长按文件夹：重命名 / 删除

	func presentFolderMenu(_ folder: FolderSnapshot, from anchor: UIView) {
		guard let info = editing.folderInfo(folder.id) else { return }
		showMenu(folderMenuSections(folder.id, info: info), title: folderMenuTitle(info), from: anchor)
	}

	/// 菜单顶部：「文件夹名」· N 个订阅源（多个账户时前面加账户名）。
	func folderMenuTitle(_ info: Babel2FolderInfo) -> String {
		var parts = [quoted(info.title), String(format: text(info.feedCount == 1 ? .folderFeedCountOne : .folderFeedCount), info.feedCount)]
		if let account = info.accountTitle {
			parts.insert(account, at: 0)
		}
		return parts.joined(separator: " · ")
	}

	func folderMenuSections(_ id: FolderSnapshot.ID, info: Babel2FolderInfo) -> [[Babel2MenuItem]] {
		[
			[Babel2MenuItem(title: text(.renameFolder), image: UIImage(systemName: "pencil"),
				identifier: "babel2.library.folder.rename") { [weak self] in
				self?.presentRenameFolder(id, current: info.title)
			}],
			[Babel2MenuItem(title: text(.deleteFolder), image: UIImage(systemName: "trash"),
				identifier: "babel2.library.folder.delete", isDestructive: true) { [weak self] in
				self?.presentDeleteFolder(id, info: info)
			}]
		]
	}

	func presentRenameFolder(_ id: FolderSnapshot.ID, current: String) {
		presentNameAlert(title: text(.renameFolder), initial: current, placeholder: text(.folderName), actionTitle: text(.ok),
			identifier: "babel2.library.folder-name") { [weak self] name in
			guard name != current else { return }
			await self?.performRenameFolder(id, to: name)
		}
	}

	func performRenameFolder(_ id: FolderSnapshot.ID, to name: String) async {
		await run { await editing.renameFolder(id, name) }
	}

	/// 删文件夹前问清楚里面的源怎么办：只删文件夹（源移到顶层）/ 连同源一起删。空文件夹直接问删不删。
	func presentDeleteFolder(_ id: FolderSnapshot.ID, info: Babel2FolderInfo) {
		let alert = UIAlertController(title: String(format: text(.deleteFolderConfirm), info.title),
			message: info.feedCount > 0 ? String(format: text(.deleteFolderContents), info.feedCount) : nil,
			preferredStyle: .alert)
		if info.feedCount > 0 {
			alert.addAction(UIAlertAction(title: text(.deleteFolderKeepFeeds), style: .default) { [weak self] _ in
				Task { @MainActor in await self?.performDeleteFolder(id, keepFeeds: true) }
			})
			alert.addAction(UIAlertAction(title: text(.deleteFolderAndFeeds), style: .destructive) { [weak self] _ in
				Task { @MainActor in await self?.performDeleteFolder(id, keepFeeds: false) }
			})
		} else {
			alert.addAction(UIAlertAction(title: text(.delete), style: .destructive) { [weak self] _ in
				Task { @MainActor in await self?.performDeleteFolder(id, keepFeeds: false) }
			})
		}
		alert.addAction(UIAlertAction(title: text(.cancel), style: .cancel))
		showAlert(alert)
	}

	func performDeleteFolder(_ id: FolderSnapshot.ID, keepFeeds: Bool) async {
		await run { await editing.deleteFolder(id, keepFeeds) }
	}

	// MARK: - 长按订阅源：移到文件夹 / 从这个文件夹移出 / 换图标 / 重命名 / 取消订阅

	func presentFeedMenu(_ feed: FeedSnapshot, in folderID: FolderSnapshot.ID?, from anchor: UIView) {
		let placement = editing.placement(feed.id)
		showMenu(feedMenuSections(feed, in: folderID, placement: placement, anchor: anchor),
			title: placement.map { feedMenuTitle($0, in: folderID) }, from: anchor)
	}

	/// 菜单顶部说明：在哪个账户（多账户时）、在哪个文件夹；同时也在别的文件夹里的写出来——这就是首页上「重复」的来由。
	func feedMenuTitle(_ placement: Babel2FeedPlacement, in folderID: FolderSnapshot.ID?) -> String {
		var line: String
		if let folderID, let here = placement.current.first(where: { $0.folderID == folderID }) {
			line = String(format: text(.feedInFolder), here.title)
		} else {
			line = text(.notInFolder)
		}
		if let account = placement.accountTitle {
			line = account + " · " + line
		}
		let elsewhere = placement.current.filter { $0.folderID != nil && $0.folderID != folderID }
		guard !elsewhere.isEmpty else { return line }
		let names = elsewhere.map { quoted($0.title) }.joined(separator: text(.listSeparator))
		return line + "\n" + String(format: text(.feedAlsoIn), names)
	}

	func feedMenuSections(_ feed: FeedSnapshot, in folderID: FolderSnapshot.ID?, placement: Babel2FeedPlacement?, anchor: UIView) -> [[Babel2MenuItem]] {
		var organize = [Babel2MenuItem]()
		if let placement {
			organize.append(Babel2MenuItem(title: text(.moveToFolder), image: UIImage(systemName: "folder"),
				identifier: "babel2.library.feed.move") { [weak self, weak anchor] in
				guard let self, let anchor else { return }
				self.presentMoveMenu(feed, from: folderID, placement: placement, anchor: anchor)
			})
			if let folderID, placement.current.count > 1,
				let here = placement.current.first(where: { $0.folderID == folderID }) {
				organize.append(Babel2MenuItem(title: String(format: text(.removeFromFolder), here.title),
					image: UIImage(systemName: "folder.badge.minus"), identifier: "babel2.library.feed.remove-from-folder") { [weak self] in
					Task { @MainActor in await self?.performRemoveFromFolder(feed.id, folderID: folderID) }
				})
			}
		}
		var icon = [Babel2MenuItem]()
		if let store = editing.customIcons {
			icon.append(Babel2MenuItem(title: text(.changeIcon), image: UIImage(systemName: "photo"),
				identifier: "babel2.library.feed.icon") { [weak self] in
				self?.pickIcon(for: feed.id)
			})
			if store.hasCustomIcon(feed.id) {
				icon.append(Babel2MenuItem(title: text(.resetIcon), image: UIImage(systemName: "arrow.uturn.backward"),
					identifier: "babel2.library.feed.icon-reset") { [weak self] in
					self?.resetIcon(for: feed.id)
				})
			}
		}
		let manage = [
			Babel2MenuItem(title: text(.rename), image: UIImage(systemName: "pencil"),
				identifier: "babel2.library.feed.rename") { [weak self] in
				self?.presentRenameFeed(feed)
			},
			Babel2MenuItem(title: text(.unsubscribe), image: UIImage(systemName: "trash"),
				identifier: "babel2.library.feed.unsubscribe", isDestructive: true) { [weak self] in
				self?.presentUnsubscribe(feed)
			}
		]
		return [organize, icon, manage]
	}

	/// 「移到文件夹…」：列出顶层与这个账户的全部文件夹（它现在在的打勾），最后一项「新建文件夹」建好直接移进去。
	func presentMoveMenu(_ feed: FeedSnapshot, from folderID: FolderSnapshot.ID?, placement: Babel2FeedPlacement, anchor: UIView) {
		showMenu(moveMenuSections(feed, from: folderID, placement: placement, anchor: anchor),
			title: String(format: text(.moveFeedTo), feed.title), from: anchor)
	}

	func moveMenuSections(_ feed: FeedSnapshot, from folderID: FolderSnapshot.ID?, placement: Babel2FeedPlacement, anchor: UIView) -> [[Babel2MenuItem]] {
		let currentIDs = Set(placement.current.map(\.folderID))
		let places = placement.destinations.map { location in
			Babel2MenuItem(title: location.folderID == nil ? text(.topLevel) : location.title,
				image: UIImage(systemName: location.folderID == nil ? "tray" : "folder"),
				identifier: "babel2.library.move." + (location.folderID ?? "top-level"),
				isOn: currentIDs.contains(location.folderID)) { [weak self] in
				guard location.folderID != folderID else { return }
				Task { @MainActor in await self?.performMove(feed.id, from: folderID, to: location.folderID) }
			}
		}
		let create = Babel2MenuItem(title: text(.newFolder), image: UIImage(systemName: "folder.badge.plus"),
			identifier: "babel2.library.move.new-folder") { [weak self, weak anchor] in
			guard let self, let anchor else { return }
			self.startNewFolder(from: anchor, accountID: feed.id.accountID) { [weak self] newFolderID in
				Task { @MainActor in await self?.performMove(feed.id, from: folderID, to: newFolderID) }
			}
		}
		return [places, [create]]
	}

	func performMove(_ id: FeedSnapshot.ID, from source: FolderSnapshot.ID?, to destination: FolderSnapshot.ID?) async {
		await run { await editing.moveFeed(id, source, destination) }
	}

	func performRemoveFromFolder(_ id: FeedSnapshot.ID, folderID: FolderSnapshot.ID) async {
		await run { await editing.removeFeedFromFolder(id, folderID) }
	}

	func presentRenameFeed(_ feed: FeedSnapshot) {
		presentNameAlert(title: text(.renameFeed), initial: feed.title, placeholder: nil, actionTitle: text(.ok),
			identifier: "babel2.library.feed-name") { [weak self] name in
			guard name != feed.title else { return }
			await self?.performRenameFeed(feed.id, to: name)
		}
	}

	func performRenameFeed(_ id: FeedSnapshot.ID, to name: String) async {
		await run { await editing.renameFeed(id, name) }
	}

	func presentUnsubscribe(_ feed: FeedSnapshot) {
		let alert = UIAlertController(title: text(.unsubscribe),
			message: String(format: text(.unsubscribeConfirm), feed.title), preferredStyle: .alert)
		alert.addAction(UIAlertAction(title: text(.cancel), style: .cancel))
		alert.addAction(UIAlertAction(title: text(.unsubscribe), style: .destructive) { [weak self] _ in
			Task { @MainActor in await self?.performUnsubscribe(feed.id) }
		})
		showAlert(alert)
	}

	func performUnsubscribe(_ id: FeedSnapshot.ID) async {
		await run { await editing.unsubscribe(id) }
	}

	// MARK: - 自定义图标（ADR-046）

	func pickIcon(for id: FeedSnapshot.ID) {
		guard let host, editing.customIcons != nil else { return }
		Babel2FeedIconPicker.present(from: host) { [weak self] data in
			self?.applyPickedIcon(data, for: id)
		}
	}

	/// 选好的图（已裁成正方形）存起来；读不出来 / 存不下时说明原因。
	func applyPickedIcon(_ data: Data?, for id: FeedSnapshot.ID) {
		guard let store = editing.customIcons else { return }
		guard let data, store.setCustomIcon(id, data) else {
			report(text(.unableToUseImage))
			return
		}
		onChange?()
	}

	func resetIcon(for id: FeedSnapshot.ID) {
		guard let store = editing.customIcons, store.setCustomIcon(id, nil) else { return }
		onChange?()
	}
}

// MARK: - 选图

/// 自定义图标的图片处理：居中裁成正方形，边长取图片短边、最多 512 像素（文章列表顶部大图也够清晰），存 PNG（保留透明）。
enum Babel2FeedIconImage {
	static let maxPixelSide: CGFloat = 512

	nonisolated static func squarePNG(from image: UIImage) -> Data? {
		let width = image.size.width * image.scale
		let height = image.size.height * image.scale
		let shortest = min(width, height)
		guard shortest >= 1 else { return nil }
		let side = min(maxPixelSide, shortest).rounded()
		let ratio = side / shortest
		let drawSize = CGSize(width: width * ratio, height: height * ratio)
		let format = UIGraphicsImageRendererFormat()
		format.scale = 1
		format.opaque = false
		return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).pngData { _ in
			image.draw(in: CGRect(x: (side - drawSize.width) / 2, y: (side - drawSize.height) / 2,
				width: drawSize.width, height: drawSize.height))
		}
	}
}

/// 系统照片选择器（PHPicker：不需要相册权限，只拿到用户选中的那一张）。选好后在后台裁图，回到主线程交给调用方；
/// 读不出图时交回 nil；用户点「取消」时什么也不做。
@MainActor
final class Babel2FeedIconPicker: NSObject, PHPickerViewControllerDelegate {
	/// 选择器显示期间保持自己不被释放（PHPicker 对代理是弱引用）。
	private static var active: Babel2FeedIconPicker?
	private let completion: @MainActor (Data?) -> Void

	private init(completion: @escaping @MainActor (Data?) -> Void) {
		self.completion = completion
	}

	static func present(from host: UIViewController, completion: @escaping @MainActor (Data?) -> Void) {
		var configuration = PHPickerConfiguration()
		configuration.filter = .images
		configuration.selectionLimit = 1
		let picker = PHPickerViewController(configuration: configuration)
		let delegate = Babel2FeedIconPicker(completion: completion)
		active = delegate
		picker.delegate = delegate
		host.present(picker, animated: true)
	}

	func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
		picker.dismiss(animated: true)
		Self.active = nil
		guard let provider = results.first?.itemProvider else { return }
		let completion = self.completion
		guard provider.canLoadObject(ofClass: UIImage.self) else {
			completion(nil)
			return
		}
		provider.loadObject(ofClass: UIImage.self) { object, _ in
			let data = (object as? UIImage).flatMap(Babel2FeedIconImage.squarePNG(from:))
			Task { @MainActor in completion(data) }
		}
	}
}
