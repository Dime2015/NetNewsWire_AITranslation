//
//  TranslationAPIKeyViewController.swift
//  NetNewsWire — AI 翻译 fork
//
//  设置 → Articles → 翻译 API Key,点进来填 key 的页面。
//
//  纯代码创建,不涉及 Storyboard。
//
//  这个文件不属于上游 NetNewsWire,是本 fork 新增的。
//

#if os(iOS)

import UIKit

@MainActor final class TranslationAPIKeyViewController: UITableViewController {

	private enum Row: Int, CaseIterable {
		case apiKey = 0
		case baseURL = 1
		case clear = 2
	}

	private let apiKeyField = UITextField()
	private let baseURLField = UITextField()

	override func viewDidLoad() {
		super.viewDidLoad()

		title = "翻译 API Key"
		tableView.register(UITableViewCell.self, forCellReuseIdentifier: "TranslationKeyCell")

		configureAPIKeyField()
		configureBaseURLField()
	}

	/// 离开页面时自动保存,省得用户还要找"完成"按钮。
	override func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)
		save()
	}

	private func configureAPIKeyField() {
		apiKeyField.placeholder = "sk-or-v1-..."
		apiKeyField.text = TranslationConfigStore.apiKey
		apiKeyField.autocapitalizationType = .none
		apiKeyField.autocorrectionType = .no
		apiKeyField.spellCheckingType = .no
		apiKeyField.clearButtonMode = .whileEditing
		apiKeyField.returnKeyType = .done
		// 用密码键盘样式,输入时显示成圆点,肩窥看不到
		apiKeyField.isSecureTextEntry = true
		apiKeyField.delegate = self
	}

	private func configureBaseURLField() {
		baseURLField.placeholder = TranslationConfigStore.defaultBaseURL
		baseURLField.text = TranslationConfigStore.baseURL
		baseURLField.autocapitalizationType = .none
		baseURLField.autocorrectionType = .no
		baseURLField.spellCheckingType = .no
		baseURLField.keyboardType = .URL
		baseURLField.clearButtonMode = .whileEditing
		baseURLField.returnKeyType = .done
		baseURLField.delegate = self
	}

	private func save() {
		TranslationConfigStore.apiKey = apiKeyField.text
		TranslationConfigStore.baseURL = baseURLField.text ?? ""
	}

	// MARK: - 表格

	override func numberOfSections(in tableView: UITableView) -> Int {
		1
	}

	override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		Row.allCases.count
	}

	override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
		"""
		API Key 存在本机的钥匙串里(加密),不会进入代码库,也不会随 app 分发出去。

		在 Mac 上复制 key 之后,在模拟器里长按输入框即可粘贴(或按 ⌘V)。

		服务地址留空表示使用 OpenRouter。换成其他兼容 OpenAI 格式的服务商时才需要改。
		"""
	}

	override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {

		let cell = tableView.dequeueReusableCell(withIdentifier: "TranslationKeyCell", for: indexPath)
		cell.contentConfiguration = nil
		cell.accessoryView = nil
		cell.accessoryType = .none
		cell.textLabel?.text = nil
		cell.textLabel?.textColor = .label
		cell.textLabel?.textAlignment = .natural
		cell.selectionStyle = .none

		switch Row(rawValue: indexPath.row) {

		case .apiKey:
			embed(apiKeyField, in: cell)

		case .baseURL:
			embed(baseURLField, in: cell)

		case .clear:
			cell.textLabel?.text = "清除 API Key"
			cell.textLabel?.textColor = .systemRed
			cell.textLabel?.textAlignment = .center
			cell.selectionStyle = .default

		case .none:
			break
		}

		return cell
	}

	override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {

		tableView.deselectRow(at: indexPath, animated: true)

		guard Row(rawValue: indexPath.row) == .clear else { return }

		apiKeyField.text = ""
		TranslationConfigStore.apiKey = nil

		let alert = UIAlertController(title: "已清除",
									  message: "API Key 已从钥匙串中删除。",
									  preferredStyle: .alert)
		alert.addAction(UIAlertAction(title: "好", style: .default))
		present(alert, animated: true)
	}

	/// 把输入框铺满整个 cell。
	private func embed(_ field: UITextField, in cell: UITableViewCell) {

		field.removeFromSuperview()
		field.translatesAutoresizingMaskIntoConstraints = false
		cell.contentView.addSubview(field)

		NSLayoutConstraint.activate([
			field.leadingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.leadingAnchor),
			field.trailingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.trailingAnchor),
			field.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 8),
			field.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -8)
		])
	}
}

extension TranslationAPIKeyViewController: UITextFieldDelegate {

	func textFieldShouldReturn(_ textField: UITextField) -> Bool {
		textField.resignFirstResponder()
		save()
		return true
	}
}

#endif
