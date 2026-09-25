import UIKit

// MARK: - 账户与同步（Figma 110:320）

/// 「账户」：每个账户一行（进入账户详情）+「添加账户」；「同步」：同步未读文章内容开关。
final class Babel2SettingsAccountsViewController: Babel2SettingsPage {
	init(service: Babel2SettingsService) {
		super.init(service: service, kind: .back, title: Babel2SettingsText.t("Accounts & Sync"))
	}

	required init?(coder: NSCoder) { nil }

	private var lastShownAccounts = [Babel2AccountSummary]()

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		// 删除或新增账户后回到这一页：账户列表变了就重建
		if isViewLoaded, service.accounts != lastShownAccounts {
			rebuildContent()
		}
	}

	static func kindText(_ kind: Babel2AccountSummary.Kind) -> String {
		switch kind {
		case .local: return Babel2SettingsText.t("Local Account")
		case .iCloud: return Babel2SettingsText.t("Syncs Across Devices")
		case .web: return Babel2SettingsText.t("Cloud Sync")
		case .selfHosted: return Babel2SettingsText.t("Self-Hosted")
		}
	}

	override func buildContent() {
		lastShownAccounts = service.accounts
		addSection(Babel2SettingsText.t("Accounts"))
		for account in lastShownAccounts {
			let row = Babel2SettingsDisclosureRow(title: account.name, detail: Self.kindText(account.kind))
			row.onTap = { [weak self] in
				guard let self else { return }
				self.push(Babel2SettingsAccountDetailViewController(service: self.service, account: account))
			}
			add(row, identifier: "babel2.settings.account.\(account.id)")
		}
		let addAccount = Babel2SettingsActionRow(title: Babel2SettingsText.t("Add Account"))
		addAccount.onTap = { [weak self] in
			guard let self else { return }
			self.push(Babel2SettingsAddAccountViewController(service: self.service))
		}
		add(addAccount, identifier: "babel2.settings.accounts.add")

		addSection(Babel2SettingsText.t("Sync"))
		add(Babel2SettingsToggleRow(title: Babel2SettingsText.t("Sync Content of Unread Articles"), isOn: service.syncUnreadArticleContent) { [weak self] on in
			self?.service.syncUnreadArticleContent = on
		}, identifier: "babel2.settings.accounts.sync-content")
	}
}

// MARK: - 账户详情（Figma 110:480）

/// 同步未读文章内容开关 + 删除账户（红色，先确认）。默认的本地账户不能删除，不显示删除。
/// Figma 的「新文章通知」不放：通知按订阅源设置，账户上没有这个开关（用户 2026-09-25 同意的「不放无效开关」原则）。
final class Babel2SettingsAccountDetailViewController: Babel2SettingsPage {
	private let account: Babel2AccountSummary

	init(service: Babel2SettingsService, account: Babel2AccountSummary) {
		self.account = account
		super.init(service: service, kind: .back, title: account.name)
	}

	required init?(coder: NSCoder) { nil }

	override func buildContent() {
		addSection(Babel2SettingsText.t("Sync"))
		add(Babel2SettingsToggleRow(title: Babel2SettingsText.t("Sync Content of Unread Articles"), isOn: service.syncUnreadArticleContent) { [weak self] on in
			self?.service.syncUnreadArticleContent = on
		}, identifier: "babel2.settings.account-detail.sync-content")
		guard !account.isDefault else { return }
		addSection(Babel2SettingsText.t("Account"))
		let delete = Babel2SettingsActionRow(title: Babel2SettingsText.t("Delete Account"), destructive: true)
		delete.onTap = { [weak self] in self?.confirmDelete() }
		add(delete, identifier: "babel2.settings.account-detail.delete")
	}

	private func confirmDelete() {
		let alert = UIAlertController(
			title: Babel2SettingsText.t("Delete Account"),
			message: Babel2SettingsText.t("Are you sure you want to delete this account? This cannot be undone."),
			preferredStyle: .alert
		)
		alert.addAction(UIAlertAction(title: Babel2SettingsText.t("Cancel"), style: .cancel))
		alert.addAction(UIAlertAction(title: Babel2SettingsText.t("Delete"), style: .destructive) { [weak self] _ in
			self?.performDelete()
		})
		present(alert, animated: true)
	}

	/// 仅供自动化测试（跳过确认框）。
	func performDelete() {
		service.deleteAccount(account.id)
		leadingTapped()
	}
}

// MARK: - 新增账户（Figma 110:500）

/// 本地 / iCloud / 网络服务 / 自托管，每类一行；点了弹出现成的账户登录 / 创建页面，成功后回到账户列表。
final class Babel2SettingsAddAccountViewController: Babel2SettingsPage {
	init(service: Babel2SettingsService) {
		super.init(service: service, kind: .back, title: Babel2SettingsText.t("Add Account"))
	}

	required init?(coder: NSCoder) { nil }

	static func title(_ kind: Babel2AddAccountKind) -> String {
		switch kind {
		case .local: return Babel2SettingsText.t("On My iPhone")
		case .iCloud: return "iCloud"
		case .bazQux: return "BazQux Reader"
		case .feedbin: return "Feedbin"
		case .feedly: return "Feedly"
		case .inoreader: return "Inoreader"
		case .newsBlur: return "NewsBlur"
		case .theOldReader: return "The Old Reader"
		case .freshRSS: return "FreshRSS"
		}
	}

	static func detail(_ kind: Babel2AddAccountKind) -> String {
		switch kind {
		case .local: return Babel2SettingsText.t("Does not sync across devices")
		case .iCloud: return Babel2SettingsText.t("Syncs across your Apple devices")
		case .freshRSS: return Babel2SettingsText.t("Connect your own server")
		default: return Babel2SettingsText.t("Cloud Sync")
		}
	}

	override func buildContent() {
		let available = Set(service.addableAccountKinds)
		let sections: [(String, [Babel2AddAccountKind])] = [
			(Babel2SettingsText.t("Local"), [.local]),
			("iCloud", [.iCloud]),
			(Babel2SettingsText.t("Web Services"), [.bazQux, .feedbin, .feedly, .inoreader, .newsBlur, .theOldReader]),
			(Babel2SettingsText.t("Self-Hosted"), [.freshRSS])
		]
		for (title, kinds) in sections {
			let shown = kinds.filter(available.contains)
			guard !shown.isEmpty else { continue }
			addSection(title)
			for kind in shown {
				let row = Babel2SettingsDisclosureRow(title: Self.title(kind), detail: Self.detail(kind))
				row.onTap = { [weak self] in
					guard let self else { return }
					self.service.presentAddAccount(kind, from: self) { [weak self] in
						self?.leadingTapped()
					}
				}
				add(row, identifier: "babel2.settings.add-account.\(kind.rawValue)")
			}
		}
	}
}

// MARK: - 订阅与发现（Figma 110:340）

/// 「订阅」：导入 / 导出（OPML）；「发现服务」：订阅发现 API Key（已设置 n/2）。
/// 「添加 Babel 新闻源」不放：它属于 1.x 界面，Babel 2.0 的添加订阅页尚未完成（用户 2026-09-25 同意）。
final class Babel2SettingsSubscriptionsViewController: Babel2SettingsPage {
	private var discoveryRow: Babel2SettingsValueRow?

	init(service: Babel2SettingsService) {
		super.init(service: service, kind: .back, title: Babel2SettingsText.t("Subscriptions & Discovery"))
	}

	required init?(coder: NSCoder) { nil }

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		discoveryRow?.setValue(discoveryStatus)
	}

	override func buildContent() {
		addSection(Babel2SettingsText.t("Subscriptions"))
		let importRow = Babel2SettingsActionRow(title: Babel2SettingsText.t("Import Subscriptions"))
		importRow.onTap = { [weak self, weak importRow] in
			guard let self, let importRow else { return }
			self.chooseAccount(from: importRow) { [weak self] id in
				guard let self else { return }
				self.service.importOPML(into: id, from: self)
			}
		}
		add(importRow, identifier: "babel2.settings.subscriptions.import")
		let exportRow = Babel2SettingsActionRow(title: Babel2SettingsText.t("Export Subscriptions"))
		exportRow.onTap = { [weak self, weak exportRow] in
			guard let self, let exportRow else { return }
			self.chooseAccount(from: exportRow) { [weak self] id in
				guard let self else { return }
				self.service.exportOPML(from: id, host: self)
			}
		}
		add(exportRow, identifier: "babel2.settings.subscriptions.export")

		addSection(Babel2SettingsText.t("Discovery Services"))
		let discovery = Babel2SettingsValueRow(title: Babel2SettingsText.t("Discovery API Keys"), value: discoveryStatus)
		discovery.onTap = { [weak self] in
			guard let self else { return }
			self.push(Babel2SettingsDiscoveryKeysViewController(service: self.service))
		}
		discoveryRow = add(discovery, identifier: "babel2.settings.subscriptions.discovery")
	}

	/// 只有一个账户时直接用；有多个时在本页弹出菜单选（不跳页）。
	private func chooseAccount(from row: UIView, completion: @escaping (String) -> Void) {
		let accounts = service.accounts
		guard let first = accounts.first else {
			presentMessage(title: Babel2SettingsText.t("No Accounts"), message: Babel2SettingsText.t("Add an account first."))
			return
		}
		guard accounts.count > 1 else {
			completion(first.id)
			return
		}
		presentChoices(accounts.map { .init(title: $0.name, isSelected: false) }, from: row) { index in
			completion(accounts[index].id)
		}
	}

	/// 已设置 n/2：Reddit（需 ID 与密钥都有）算 1 项，YouTube 算 1 项。
	private var discoveryStatus: String {
		let reddit = !(service.redditClientID ?? "").isEmpty && !(service.redditClientSecret ?? "").isEmpty
		let youtube = !(service.youTubeAPIKey ?? "").isEmpty
		let count = (reddit ? 1 : 0) + (youtube ? 1 : 0)
		return count == 0 ? Babel2SettingsText.t("Not Set") : Babel2SettingsText.f("Set %d/2", count)
	}
}
