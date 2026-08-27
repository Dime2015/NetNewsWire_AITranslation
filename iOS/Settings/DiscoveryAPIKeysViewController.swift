//
//  DiscoveryAPIKeysViewController.swift
//  NetNewsWire — AI 翻译 fork
//
//  设置 → 文章 → 订阅发现 API Key,填 Reddit / YouTube 统一搜索要用到的凭据。
//
//  纯代码创建,不涉及 Storyboard。写法照抄 TranslationAPIKeyViewController.swift。
//
//  这个文件不属于上游 NetNewsWire,是本 fork 新增的。
//

#if os(iOS)

import UIKit
import SafariServices

@MainActor final class DiscoveryAPIKeysViewController: UITableViewController {

	private enum Section: Int, CaseIterable {
		case reddit = 0
		case youtube = 1
	}

	private enum RedditRow: Int, CaseIterable {
		case clientID = 0
		case clientSecret = 1
		case openAppsPage = 2
	}

	private enum YouTubeRow: Int, CaseIterable {
		case apiKey = 0
		case openConsole = 1
	}

	private let redditClientIDField = UITextField()
	private let redditClientSecretField = UITextField()
	private let youTubeAPIKeyField = UITextField()

	override func viewDidLoad() {
		super.viewDidLoad()

		title = "订阅发现 API Key"
		tableView.register(UITableViewCell.self, forCellReuseIdentifier: "DiscoveryKeyCell")

		configureField(redditClientIDField, placeholder: "client id", secure: false,
					   value: FeedDiscoveryKeychain.redditClientID)
		configureField(redditClientSecretField, placeholder: "secret", secure: true,
					   value: FeedDiscoveryKeychain.redditClientSecret)
		configureField(youTubeAPIKeyField, placeholder: "AIza...", secure: true,
					   value: FeedDiscoveryKeychain.youTubeAPIKey)

		AppAppearance.applyPaperStyle(to: tableView)	// [外观] 暖纸风
		nnwInstallCancelSaveItems(saveAction: #selector(saveTapped), cancelAction: #selector(cancelTapped))
	}

	private func configureField(_ field: UITextField, placeholder: String, secure: Bool, value: String?) {
		field.placeholder = placeholder
		field.text = value
		field.autocapitalizationType = .none
		field.autocorrectionType = .no
		field.spellCheckingType = .no
		field.clearButtonMode = .whileEditing
		field.returnKeyType = .done
		field.isSecureTextEntry = secure
		field.delegate = self
	}

	@objc private func cancelTapped() {
		navigationController?.popViewController(animated: true)
	}

	@objc private func saveTapped() {
		FeedDiscoveryKeychain.redditClientID = redditClientIDField.text
		FeedDiscoveryKeychain.redditClientSecret = redditClientSecretField.text
		FeedDiscoveryKeychain.youTubeAPIKey = youTubeAPIKeyField.text
		navigationController?.popViewController(animated: true)
	}

	// MARK: - 表格

	override func numberOfSections(in tableView: UITableView) -> Int {
		Section.allCases.count
	}

	override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		switch Section(rawValue: section) {
		case .reddit: return RedditRow.allCases.count
		case .youtube: return YouTubeRow.allCases.count
		case .none: return 0
		}
	}

	override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
		switch Section(rawValue: section) {
		case .reddit: return "Reddit"
		case .youtube: return "YouTube"
		case .none: return nil
		}
	}

	override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
		switch Section(rawValue: section) {
		case .reddit:
			return """
				免费,不需要 Reddit 账号登录 app。去 reddit.com/prefs/apps 创建一个 \
				「script」类型的应用(网站地址随便填,比如 http://localhost),\
				应用名下面那一串是 client id,「secret」是密钥。

				两个都填了,统一搜索才会搜 Reddit;只填一个当作没填。
				"""
		case .youtube:
			return """
				免费,不需要绑定信用卡。去 Google Cloud Console 创建一个项目、\
				启用「YouTube Data API v3」,再创建一个 API Key。

				免费额度每天约 100 次搜索,用完次日太平洋时间午夜恢复。
				"""
		case .none:
			return nil
		}
	}

	override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {

		let cell = tableView.dequeueReusableCell(withIdentifier: "DiscoveryKeyCell", for: indexPath)
		cell.contentConfiguration = nil
		cell.accessoryView = nil
		cell.accessoryType = .none
		cell.textLabel?.text = nil
		cell.textLabel?.textColor = .tintColor
		cell.textLabel?.textAlignment = .natural
		cell.selectionStyle = .none

		switch Section(rawValue: indexPath.section) {

		case .reddit:
			switch RedditRow(rawValue: indexPath.row) {
			case .clientID:
				embed(redditClientIDField, in: cell)
			case .clientSecret:
				embed(redditClientSecretField, in: cell)
			case .openAppsPage:
				cell.textLabel?.text = "打开 reddit.com/prefs/apps"
				cell.selectionStyle = .default
			case .none:
				break
			}

		case .youtube:
			switch YouTubeRow(rawValue: indexPath.row) {
			case .apiKey:
				embed(youTubeAPIKeyField, in: cell)
			case .openConsole:
				cell.textLabel?.text = "打开 Google Cloud Console"
				cell.selectionStyle = .default
			case .none:
				break
			}

		case .none:
			break
		}

		return cell
	}

	// [外观] cell 暖底 + 药丸选中
	override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
		AppAppearance.applyPaperStyle(to: cell)
	}

	override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		tableView.deselectRow(at: indexPath, animated: true)

		let urlString: String?
		switch Section(rawValue: indexPath.section) {
		case .reddit where indexPath.row == RedditRow.openAppsPage.rawValue:
			urlString = "https://www.reddit.com/prefs/apps"
		case .youtube where indexPath.row == YouTubeRow.openConsole.rawValue:
			urlString = "https://console.cloud.google.com/apis/library/youtube.googleapis.com"
		default:
			urlString = nil
		}

		guard let urlString, let url = URL(string: urlString),
			  let safari = SFSafariViewController.safeSafariViewController(url) else {
			return
		}
		present(safari, animated: true)
	}

	/// 把输入框铺满整个 cell(照抄 TranslationAPIKeyViewController 的写法)。
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

extension DiscoveryAPIKeysViewController: UITextFieldDelegate {
	func textFieldShouldReturn(_ textField: UITextField) -> Bool {
		textField.resignFirstResponder()
		return true
	}
}

#endif
