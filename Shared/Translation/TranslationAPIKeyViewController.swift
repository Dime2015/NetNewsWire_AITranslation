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
		case test = 2
		case clear = 3
	}

	private let apiKeyField = UITextField()
	private let baseURLField = UITextField()

	/// 正在测试连通性时,行内显示转圈并禁止重复点击。
	private var isTesting = false

	override func viewDidLoad() {
		super.viewDidLoad()

		title = "翻译 API Key"
		tableView.register(UITableViewCell.self, forCellReuseIdentifier: "TranslationKeyCell")

		configureAPIKeyField()
		configureBaseURLField()
		AppAppearance.applyPaperStyle(to: tableView)	// [外观] 暖纸风
	}

	// [外观] cell 暖底 + 药丸选中
	override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
		AppAppearance.applyPaperStyle(to: cell)
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

		case .test:
			cell.textLabel?.text = isTesting ? "正在测试…" : "测试连通性"
			cell.textLabel?.textColor = isTesting ? .secondaryLabel : .tintColor
			cell.textLabel?.textAlignment = .center
			cell.selectionStyle = isTesting ? .none : .default
			if isTesting {
				let spinner = UIActivityIndicatorView(style: .medium)
				spinner.startAnimating()
				cell.accessoryView = spinner
			}

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

		switch Row(rawValue: indexPath.row) {

		case .test:
			runConnectionTest()

		case .clear:
			apiKeyField.text = ""
			TranslationConfigStore.apiKey = nil
			showAlert(title: "已清除", message: "API Key 已从钥匙串中删除。")

		default:
			break
		}
	}

	// MARK: - 连通性测试

	/// 用一次极小的真实请求验证"填的东西真的能用"。
	///
	/// 为什么要真发一次请求:能连上服务器不等于能用 ——
	/// key 打错一位、余额用完、模型名不存在,都只有真的调一次才会暴露。
	/// 这一次请求让模型只回两个字,费用可以忽略。
	private func runConnectionTest() {

		guard !isTesting else { return }

		// 先把输入框里的内容存下来,否则测的是上一次保存的旧值
		save()

		guard let config = TranslationConfigStore.config else {
			showAlert(title: "还不能测试",
					  message: TranslationConfigStore.configurationProblem ?? "配置不完整。")
			return
		}

		let model = TranslationConfigStore.selectedModel
		isTesting = true
		tableView.reloadRows(at: [IndexPath(row: Row.test.rawValue, section: 0)], with: .none)

		Task { [weak self] in
			guard let self else { return }
			do {
				let reply = try await OpenAICompatibleTranslator.testConnection(config: config, model: model)
				self.isTesting = false
				self.tableView.reloadRows(at: [IndexPath(row: Row.test.rawValue, section: 0)], with: .none)
				self.showAlert(title: "连接正常",
							   message: "模型 \(TranslationConfigStore.displayName(for: model)) 回复了:\n\n\(reply)")
			} catch {
				self.isTesting = false
				self.tableView.reloadRows(at: [IndexPath(row: Row.test.rawValue, section: 0)], with: .none)
				self.showAlert(title: "连接失败",
							   message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription,
							   note: Self.hint(for: error))
			}
		}
	}

	/// 把常见错误翻成"下一步该怎么办"。
	private static func hint(for error: Error) -> String? {
		guard let translationError = error as? TranslationError else { return nil }
		switch translationError {
		case .serverError(let status, _):
			switch status {
			case 401, 403: return "多半是 API Key 不对或已失效,检查有没有复制完整。"
			case 402:      return "多半是账户余额不足。"
			case 404:      return "多半是服务地址写错了,或当前模型在这个服务商处不存在。"
			case 429:      return "被限流了,过一会儿再试。"
			default:       return nil
			}
		case .networkFailure:
			return "检查网络连接,以及服务地址是否正确。"
		case .invalidResponse:
			return "服务器有响应但格式不对 —— 该地址可能不是 OpenAI 兼容接口。"
		default:
			return nil
		}
	}

	private func showAlert(title: String, message: String, note: String? = nil) {
		let body = note.map { "\(message)\n\n\($0)" } ?? message
		let alert = UIAlertController(title: title, message: body, preferredStyle: .alert)
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
