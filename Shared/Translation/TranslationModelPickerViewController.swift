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
	private var pendingModel: String = ""		// [交互] 待应用的选择;点右上角勾才真正生效

	override func viewDidLoad() {
		super.viewDidLoad()

		title = "翻译模型"
		models = TranslationConfigStore.availableModels
		pendingModel = TranslationConfigStore.selectedModel
		tableView.register(UITableViewCell.self, forCellReuseIdentifier: "TranslationModelCell")
		AppAppearance.applyPaperStyle(to: tableView)	// [外观] 暖纸风

		// [交互] 左上取消(不改)、右上勾(应用选择并返回),与 API Key 页一致。
		// 刷新键从右上角移到列表下方单独一行(见最后一个 section)。
		nnwInstallCancelSaveItems(saveAction: #selector(saveTapped), cancelAction: #selector(cancelTapped))
	}

	@objc private func cancelTapped() {
		navigationController?.popViewController(animated: true)		// 不应用,直接退回
	}

	@objc private func saveTapped() {
		TranslationConfigStore.selectedModel = pendingModel			// 应用选择
		navigationController?.popViewController(animated: true)
	}

	// [外观] cell 暖底 + 药丸选中
	override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
		AppAppearance.applyPaperStyle(to: cell)
	}

	// MARK: - 刷新(列表下方那一行)

	@objc private func refreshTapped() {

		guard !isRefreshing else { return }
		isRefreshing = true
		tableView.reloadData()		// 刷新行改成"正在刷新…"

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
				self.tableView.reloadData()
				self.showAlert(title: "已更新",
							   message: "从 OpenRouter 翻译榜拉到 \(ranked.count) 个模型,按热度排序。")

			} catch {
				// 失败:一个字节都不动,只告诉用户为什么
				self.isRefreshing = false
				self.tableView.reloadData()
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
		2	// 0 = 模型列表;1 = 刷新按钮
	}

	override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		section == 0 ? models.count : 1
	}

	/// 配置没配好时,把原因显示在列表下方 —— 而不是给用户一个空白页面让他猜。
	override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {

		guard section == 0 else { return nil }		// 刷新那个 section 不要脚注

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
			lines.append("当前是内置列表。点下方的「刷新模型列表」可从 OpenRouter 拉取翻译任务下最热门的模型。")
		}

		lines.append("说明:OpenRouter 的翻译榜按「花费占比」排序,贵的模型天然靠前 —— 排名高不等于性价比高。")

		return lines.joined(separator: "\n\n")
	}

	override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {

		let cell = tableView.dequeueReusableCell(withIdentifier: "TranslationModelCell", for: indexPath)

		// section 1:列表下方的「刷新模型列表」按钮行(原来在右上角,现移到这里)
		if indexPath.section == 1 {
			var content = cell.defaultContentConfiguration()
			content.text = isRefreshing ? "正在刷新…" : "刷新模型列表"
			content.textProperties.color = Assets.Colors.primaryAccent	// 陶土红,像个按钮
			content.textProperties.alignment = .center
			cell.contentConfiguration = content
			cell.accessoryType = .none
			if isRefreshing {
				let spinner = UIActivityIndicatorView(style: .medium)
				spinner.startAnimating()
				cell.accessoryView = spinner
			} else {
				cell.accessoryView = nil
			}
			return cell
		}

		let model = models[indexPath.row]
		var content = cell.defaultContentConfiguration()
		content.text = TranslationConfigStore.displayName(for: model)
		content.secondaryText = model
		cell.contentConfiguration = content
		cell.accessoryView = nil

		// 待选中的那个打勾(点右上角勾才真正生效)
		cell.accessoryType = (model == pendingModel) ? .checkmark : .none

		return cell
	}

	override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		tableView.deselectRow(at: indexPath, animated: true)

		if indexPath.section == 1 {
			refreshTapped()					// 刷新模型列表
			return
		}

		pendingModel = models[indexPath.row]	// 只标记待选,不落库
		tableView.reloadData()
	}
}

#endif
