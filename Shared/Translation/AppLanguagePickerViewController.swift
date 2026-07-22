//
//  AppLanguagePickerViewController.swift
//  NetNewsWire — AI 翻译 fork
//
//  设置 → 界面语言,点进来选语言的页面。
//
//  列表内容来自 AppLanguageController.availableOptions —— 也就是 app 包里
//  实际带的语言。以后加日语,这个页面自动多一行,不用改代码。
//
//  这个文件不属于上游 NetNewsWire,是本 fork 新增的。
//

#if os(iOS)

import UIKit

@MainActor final class AppLanguagePickerViewController: UITableViewController {

	private let options = AppLanguageController.availableOptions
	private var pendingLanguage: String?			// [交互] 待应用的语言(nil = 跟随系统);点右上角勾才生效

	override func viewDidLoad() {
		super.viewDidLoad()
		title = "界面语言"
		pendingLanguage = AppLanguageController.selectedLanguage
		tableView.register(UITableViewCell.self, forCellReuseIdentifier: "LanguageCell")
		AppAppearance.applyPaperStyle(to: tableView)	// [外观] 暖纸风
		nnwInstallCancelSaveItems(saveAction: #selector(saveTapped), cancelAction: #selector(cancelTapped))	// [交互] 左上取消 / 右上勾
	}

	@objc private func cancelTapped() {
		navigationController?.popViewController(animated: true)		// 不改语言,直接退回
	}

	@objc private func saveTapped() {
		let changed = pendingLanguage != AppLanguageController.selectedLanguage
		AppLanguageController.selectedLanguage = pendingLanguage
		guard changed else {
			navigationController?.popViewController(animated: true)
			return
		}
		// 界面文字是 app 启动时加载的,改完必须重启才会全部换掉 —— 只提示,不代为退出。
		let alert = UIAlertController(
			title: "已切换语言",
			message: "请手动退出并重新打开 NetNewsWire,新的界面语言才会完全生效。",
			preferredStyle: .alert)
		alert.addAction(UIAlertAction(title: "好", style: .default) { [weak self] _ in
			self?.navigationController?.popViewController(animated: true)
		})
		present(alert, animated: true)
	}

	// [外观] cell 暖底 + 药丸选中
	override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
		AppAppearance.applyPaperStyle(to: cell)
	}

	override func numberOfSections(in tableView: UITableView) -> Int {
		1
	}

	override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		options.count
	}

	override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
		"更改语言后需要重新启动 NetNewsWire 才会生效。\n\n未翻译的文字会自动回退到英文。"
	}

	override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		let cell = tableView.dequeueReusableCell(withIdentifier: "LanguageCell", for: indexPath)
		let option = options[indexPath.row]
		cell.textLabel?.text = option.displayName
		cell.accessoryType = (option.code == pendingLanguage) ? .checkmark : .none
		return cell
	}

	override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		tableView.deselectRow(at: indexPath, animated: true)
		pendingLanguage = options[indexPath.row].code		// 只标记待选,点勾才生效
		tableView.reloadData()
	}
}

#endif
