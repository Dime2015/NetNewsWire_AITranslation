//
//  ArticleThemesTableViewController.swift
//  NetNewsWire-iOS
//
//  Created by Maurice Parker on 9/12/21.
//  Copyright © 2021 Ranchero Software. All rights reserved.
//

import Foundation
import UniformTypeIdentifiers
import UIKit

extension UTType {
	static var netNewsWireTheme: UTType { UTType(importedAs: "com.ranchero.netnewswire.theme") }
}

final class ArticleThemesTableViewController: UITableViewController {

	private var pendingThemeName: String = ""		// [交互] 待应用的主题;点右上角勾才生效

	override func viewDidLoad() {
		pendingThemeName = ArticleThemesManager.shared.currentTheme.name

		NotificationCenter.default.addObserver(self, selector: #selector(articleThemeNamesDidChangeNotification(_:)), name: .ArticleThemeNamesDidChangeNotification, object: nil)

		AppAppearance.applyPaperStyle(to: tableView)	// [外观] 暖纸风
		// [交互] 左上取消 / 右上勾;原来右上角的「导入主题」移到列表下方一行(见 section 1)。
		nnwInstallCancelSaveItems(saveAction: #selector(saveTapped), cancelAction: #selector(cancelTapped))
	}

	@objc private func cancelTapped() {
		navigationController?.popViewController(animated: true)		// 不改主题,直接退回
	}

	@objc private func saveTapped() {
		ArticleThemesManager.shared.currentThemeName = pendingThemeName	// 应用主题
		navigationController?.popViewController(animated: true)
	}

	// [外观] cell 暖底 + 药丸选中
	override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
		AppAppearance.applyPaperStyle(to: cell)
	}

	// MARK: Notifications

	@objc func articleThemeNamesDidChangeNotification(_ note: Notification) {
		tableView.reloadData()
	}

	@objc func importTheme(_ sender: Any?) {
		let docPicker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.netNewsWireTheme])
		docPicker.delegate = self
		docPicker.modalPresentationStyle = .formSheet
		self.present(docPicker, animated: true)
	}

	// MARK: - Table view data source

	override func numberOfSections(in tableView: UITableView) -> Int {
		return 2	// 0 = 主题列表;1 = 导入按钮
	}

	override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		section == 0 ? ArticleThemesManager.shared.themeNames.count + 1 : 1
	}

	/// 第 0 行是内置默认主题,其余是已安装的主题。
	private func themeName(at indexPath: IndexPath) -> String {
		if indexPath.row == 0 {
			return ArticleTheme.defaultTheme.name
		}
		return ArticleThemesManager.shared.themeNames[indexPath.row - 1]
	}

	override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)

		// section 1:列表下方的「导入主题」按钮行(原来在右上角)
		if indexPath.section == 1 {
			cell.textLabel?.text = NSLocalizedString("Import Theme", comment: "Import Theme")
			cell.textLabel?.textColor = Assets.Colors.primaryAccent	// 陶土红,像个按钮
			cell.textLabel?.textAlignment = .center
			cell.accessoryType = .none
			return cell
		}

		let name = themeName(at: indexPath)
		cell.textLabel?.text = name
		cell.textLabel?.textColor = .label			// 复用的 cell 可能来自导入行,复位
		cell.textLabel?.textAlignment = .natural
		cell.accessoryType = (name == pendingThemeName) ? .checkmark : .none	// 待选打勾
		return cell
	}

	override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		tableView.deselectRow(at: indexPath, animated: true)

		if indexPath.section == 1 {
			importTheme(nil)						// 导入主题
			return
		}

		pendingThemeName = themeName(at: indexPath)	// 只标记待选,点勾才生效
		tableView.reloadData()
	}

	override func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
		guard indexPath.section == 0 else { return nil }		// [交互] 导入行不可滑删
		guard let cell = tableView.cellForRow(at: indexPath),
			  let themeName = cell.textLabel?.text,
			  let theme = ArticleThemesManager.shared.articleThemeWithThemeName(themeName),
			  !theme.isAppTheme	else { return nil }

		let deleteTitle = NSLocalizedString("Delete", comment: "Delete button")
		let deleteAction = UIContextualAction(style: .normal, title: deleteTitle) { [weak self] (_, _, completion) in
			let title = NSLocalizedString("Delete Theme?", comment: "Delete Theme")

			let localizedMessageText = NSLocalizedString("Are you sure you want to delete the theme “%@”?.", comment: "Delete Theme Message")
			let message = NSString.localizedStringWithFormat(localizedMessageText as NSString, themeName) as String

			let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)

			let cancelTitle = NSLocalizedString("Cancel", comment: "Cancel button")
			let cancelAction = UIAlertAction(title: cancelTitle, style: .cancel) { _ in
				completion(true)
			}
			alertController.addAction(cancelAction)

			let deleteTitle = NSLocalizedString("Delete", comment: "Delete button")
			let deleteAction = UIAlertAction(title: deleteTitle, style: .destructive) { _ in
				ArticleThemesManager.shared.deleteTheme(themeName: themeName)
				completion(true)
			}
			alertController.addAction(deleteAction)

			self?.present(alertController, animated: true)
		}

		deleteAction.image = Assets.Images.trash
		deleteAction.backgroundColor = UIColor.systemRed

		return UISwipeActionsConfiguration(actions: [deleteAction])
	}
}

// MARK: UIDocumentPickerDelegate

extension ArticleThemesTableViewController: UIDocumentPickerDelegate {

	func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
		guard let url = urls.first else { return }

		if url.startAccessingSecurityScopedResource() {

			defer {
				url.stopAccessingSecurityScopedResource()
			}

			do {
				try ArticleThemeImporter.importTheme(controller: self, url: url)
			} catch {
				NotificationCenter.default.post(name: .didFailToImportThemeWithError, object: nil, userInfo: ["error": error])
			}
		}
	}
}
