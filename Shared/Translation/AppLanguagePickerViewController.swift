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

	override func viewDidLoad() {
		super.viewDidLoad()
		title = "界面语言"
		tableView.register(UITableViewCell.self, forCellReuseIdentifier: "LanguageCell")
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
		cell.accessoryType = (option.code == AppLanguageController.selectedLanguage) ? .checkmark : .none
		return cell
	}

	override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {

		tableView.deselectRow(at: indexPath, animated: true)

		let option = options[indexPath.row]
		guard option.code != AppLanguageController.selectedLanguage else {
			return
		}

		AppLanguageController.selectedLanguage = option.code
		tableView.reloadData()

		// 界面文字是 app 启动时加载的,改完必须重启才会全部换掉。
		// 这里只提示,不代为退出 —— app 主动退出在 iOS 上是不被鼓励的做法,
		// 而且会让用户以为闪退了。
		let alert = UIAlertController(
			title: "已切换为 \(option.displayName)",
			message: "请手动退出并重新打开 NetNewsWire,新的界面语言才会完全生效。",
			preferredStyle: .alert)
		alert.addAction(UIAlertAction(title: "好", style: .default))
		present(alert, animated: true)
	}
}

#endif
