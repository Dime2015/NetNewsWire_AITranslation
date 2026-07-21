//
//  TranslationModelPickerViewController.swift
//  NetNewsWire — AI 翻译 fork
//
//  设置 → Articles → 翻译模型,点进来的那个列表页。
//  右上角可以从 OpenRouter 拉取「翻译任务」分类下最热门的模型来刷新这个列表。
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
	private var isRefreshing = false

	override func viewDidLoad() {
		super.viewDidLoad()

		title = "翻译模型"
		models = TranslationConfigStore.availableModels
		tableView.register(UITableViewCell.self, forCellReuseIdentifier: "TranslationModelCell")
		updateRefreshButton()
	}

	// MARK: - 刷新按钮

	private func updateRefreshButton() {
		if isRefreshing {
			let spinner = UIActivityIndicatorView(style: .medium)
			spinner.startAnimating()
			navigationItem.rightBarButtonItem = UIBarButtonItem(customView: spinner)
		} else {
			navigationItem.rightBarButtonItem = UIBarButtonItem(
				image: UIImage(systemName: "arrow.clockwise"),
				style: .plain,
				target: self,
				action: #selector(refreshTapped))
			navigationItem.rightBarButtonItem?.accessibilityLabel = "从 OpenRouter 刷新模型列表"
		}
	}

	@objc private func refreshTapped() {

		guard !isRefreshing else { return }
		isRefreshing = true
		updateRefreshButton()

		Task { [weak self] in
			guard let self else { return }

			let baseURL = TranslationConfigStore.baseURL
			do {
				let ranked = try await OpenRouterModelCatalog.fetchTopTranslationModels(baseURL: baseURL)

				// 只有真的拿到了非空结果才覆盖 —— 这是用户明确要求的:
				// 拉取失败时上一次的列表必须原封不动。
				TranslationConfigStore.updateFetchedModels(ranked.map(\.id))
				self.models = TranslationConfigStore.availableModels
				self.isRefreshing = false
				self.updateRefreshButton()
				self.tableView.reloadData()
				self.showAlert(title: "已更新",
							   message: "从 OpenRouter 翻译榜拉到 \(ranked.count) 个模型,按热度排序。")

			} catch {
				// 失败:一个字节都不动,只告诉用户为什么
				self.isRefreshing = false
				self.updateRefreshButton()
				self.showAlert(title: "刷新失败",
							   message: (error as? LocalizedError)?.errorDescription
								   ?? error.localizedDescription,
							   note: "已保留原有的模型列表,可以继续正常使用。")
			}
		}
	}

	private func showAlert(title: String, message: String, note: String? = nil) {
		let body = note.map { "\(message)\n\n\($0)" } ?? message
		let alert = UIAlertController(title: title, message: body, preferredStyle: .alert)
		alert.addAction(UIAlertAction(title: "好", style: .default))
		present(alert, animated: true)
	}

	// MARK: - 表格

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

		var lines = ["翻译按钮在文章页底部工具栏。"]

		if let date = TranslationConfigStore.modelsLastRefreshed {
			let formatter = DateFormatter()
			formatter.dateStyle = .medium
			formatter.timeStyle = .short
			lines.append("列表更新于 \(formatter.string(from: date)),来自 OpenRouter 翻译榜。")
		} else {
			lines.append("当前是内置列表。点右上角可从 OpenRouter 拉取翻译任务下最热门的模型。")
		}

		lines.append("说明:OpenRouter 的翻译榜按「花费占比」排序,贵的模型天然靠前 —— 排名高不等于性价比高。")

		return lines.joined(separator: "\n\n")
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
