//
//  TranslationModelPickerViewController.swift
//  NetNewsWire — AI 翻译 fork
//
//  设置 → Articles → 翻译模型,点进来的那个列表页。
//
//  纯代码创建,不涉及任何 Storyboard —— Storyboard 是 XML,
//  改它在 git pull upstream 时冲突风险高(CLAUDE.md 第 2 节)。
//
//  这个文件不属于上游 NetNewsWire,是本 fork 新增的。
//

#if os(iOS)

import UIKit

@MainActor final class TranslationModelPickerViewController: UITableViewController {

	private var models: [String] = []

	override func viewDidLoad() {
		super.viewDidLoad()

		title = "翻译模型"
		models = TranslationConfigStore.availableModels
		tableView.register(UITableViewCell.self, forCellReuseIdentifier: "TranslationModelCell")
	}

	override func numberOfSections(in tableView: UITableView) -> Int {
		1
	}

	override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		models.count
	}

	/// 配置没配好时,把原因显示在列表下方 —— 而不是给用户一个空白页面让他猜。
	override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
		if let problem = TranslationConfigStore.configurationProblem {
			return problem
		}
		return "翻译按钮在文章页底部工具栏。要增减这个列表,改 Shared/Translation/TranslationConfig.swift 里的 availableModels。"
	}

	override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {

		let cell = tableView.dequeueReusableCell(withIdentifier: "TranslationModelCell", for: indexPath)
		let model = models[indexPath.row]

		var content = cell.defaultContentConfiguration()
		content.text = TranslationConfigStore.displayName(for: model)
		content.secondaryText = model
		cell.contentConfiguration = content

		// 当前选中的那个打勾
		cell.accessoryType = (model == TranslationConfigStore.selectedModel) ? .checkmark : .none

		return cell
	}

	override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		TranslationConfigStore.selectedModel = models[indexPath.row]
		tableView.reloadData()
		tableView.deselectRow(at: indexPath, animated: true)
	}
}

#endif
