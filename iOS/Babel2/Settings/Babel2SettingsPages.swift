import UIKit

// MARK: - 页面骨架

/// 所有设置页共用的骨架：58pt 导航栏 + 可滚动内容区（左右 20、顶部 18，纵向排列、行间无分隔线）。
/// 页面都推在 Babel 2.0 的导航栈上，返回沿用统一的左边缘返回手势。
class Babel2SettingsPage: UIViewController {
	let service: Babel2SettingsService
	let navigationBar: Babel2SettingsNavigationBar
	let scrollView = UIScrollView()
	let contentStack = UIStackView()
	private let navigationKind: Babel2SettingsNavigationBar.Kind

	init(service: Babel2SettingsService, kind: Babel2SettingsNavigationBar.Kind, title: String) {
		self.service = service
		self.navigationKind = kind
		self.navigationBar = Babel2SettingsNavigationBar(kind: kind, title: title)
		super.init(nibName: nil, bundle: nil)
	}

	required init?(coder: NSCoder) { nil }

	override func viewDidLoad() {
		super.viewDidLoad()
		view.backgroundColor = Babel2SettingsStyle.background
		navigationBar.translatesAutoresizingMaskIntoConstraints = false
		scrollView.translatesAutoresizingMaskIntoConstraints = false
		scrollView.alwaysBounceVertical = true
		scrollView.keyboardDismissMode = .interactive
		contentStack.axis = .vertical
		contentStack.alignment = .fill
		contentStack.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(scrollView)
		view.addSubview(navigationBar)
		scrollView.addSubview(contentStack)

		// 状态栏区域与导航栏同色不透明（内容不从状态栏后透出来）
		let statusBackdrop = UIView()
		statusBackdrop.backgroundColor = Babel2SettingsStyle.background
		statusBackdrop.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(statusBackdrop)

		NSLayoutConstraint.activate([
			statusBackdrop.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			statusBackdrop.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			statusBackdrop.topAnchor.constraint(equalTo: view.topAnchor),
			statusBackdrop.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
			navigationBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			navigationBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			navigationBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
			scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			scrollView.topAnchor.constraint(equalTo: navigationBar.bottomAnchor),
			scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
			contentStack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: Babel2SettingsStyle.sideInset),
			contentStack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -Babel2SettingsStyle.sideInset),
			contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: Babel2SettingsStyle.contentTopInset),
			contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24)
		])
		navigationBar.leadingButton.addTarget(self, action: #selector(leadingTapped), for: .touchUpInside)
		navigationBar.saveButton.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)

		NotificationCenter.default.addObserver(self, selector: #selector(keyboardFrameChanged(_:)), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
		buildContent()
	}

	/// 子类在这里往 contentStack 里放分组与行。
	func buildContent() {}

	/// 清空重建（值变了需要整页刷新时用，如账户列表）。
	func rebuildContent() {
		contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
		buildContent()
	}

	@objc func leadingTapped() {
		view.endEditing(true)
		_ = (navigationController as? Babel2NavigationController)?.popBabel2(animated: true)
			?? navigationController?.popViewController(animated: true)
	}

	/// 编辑页（取消 / 保存）覆盖这里：写入后返回。
	@objc func saveTapped() {}

	// MARK: 组装小工具

	func addSection(_ title: String?) {
		if let title {
			contentStack.addArrangedSubview(Babel2SettingsSectionHeader(title: title))
		}
	}

	@discardableResult
	func add<T: UIView>(_ view: T, identifier: String? = nil) -> T {
		if let identifier { view.accessibilityIdentifier = identifier }
		contentStack.addArrangedSubview(view)
		return view
	}

	func addSpacing(_ height: CGFloat) {
		let spacer = UIView()
		spacer.translatesAutoresizingMaskIntoConstraints = false
		spacer.heightAnchor.constraint(equalToConstant: height).isActive = true
		contentStack.addArrangedSubview(spacer)
	}

	func push(_ page: UIViewController) {
		if let navigation = navigationController as? Babel2NavigationController {
			navigation.pushBabel2(page, animated: true)
		} else {
			navigationController?.pushViewController(page, animated: true)
		}
	}

	/// 弹出单选菜单（锚定在触发行下方）；选完立即回调并关闭。
	func presentChoices(_ options: [Babel2SettingsPopover.Option], from row: UIView, onSelect: @escaping (Int) -> Void) {
		view.endEditing(true)
		Babel2SettingsPopover.present(options: options, from: row, in: view, onSelect: onSelect)
	}

	func presentMessage(title: String, message: String?) {
		let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
		alert.addAction(UIAlertAction(title: Babel2SettingsText.t("OK"), style: .default))
		present(alert, animated: true)
	}

	/// 仅供自动化测试：当前浮着的弹出菜单。
	var presentedPopoverForTesting: Babel2SettingsPopover? {
		view.subviews.compactMap { $0 as? Babel2SettingsPopover }.last
	}

	@objc private func keyboardFrameChanged(_ notification: Notification) {
		guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
		let overlap = max(0, view.bounds.maxY - view.convert(frame, from: nil).minY - view.safeAreaInsets.bottom)
		scrollView.contentInset.bottom = overlap
		scrollView.verticalScrollIndicatorInsets.bottom = overlap
	}
}

// MARK: - 设置首页（Figma 110:300）

/// 设置首页：左上角 ×，8 个类别（图标 + 标题 + 一行说明 + 箭头）。
/// 沿用路由恢复标识 babel2.settings（重启后能回到设置页）。
final class Babel2SettingsHomeViewController: Babel2SettingsPage {
	enum Category: CaseIterable {
		case accounts, subscriptions, timeline, reader, translation, appearance, notifications, support

		var titleKey: String {
			switch self {
			case .accounts: return "Accounts & Sync"
			case .subscriptions: return "Subscriptions & Discovery"
			case .timeline: return "Article List"
			case .reader: return "Reader"
			case .translation: return "Translation"
			case .appearance: return "Appearance & Language"
			case .notifications: return "Notifications"
			case .support: return "Support & Diagnostics"
			}
		}

		var detailKey: String {
			switch self {
			case .accounts: return "Accounts, sync status and service connections"
			case .subscriptions: return "Import and export subscriptions, discovery services"
			case .timeline: return "Sorting and read behavior"
			case .reader: return "How links open"
			case .translation: return "Model, API and translation service"
			case .appearance: return "Color mode, accent color and interface language"
			case .notifications: return "System notification permission"
			case .support: return "Logs, statistics, help and about"
			}
		}

		var identifier: String {
			switch self {
			case .accounts: return "babel2.settings.accounts"
			case .subscriptions: return "babel2.settings.subscriptions"
			case .timeline: return "babel2.settings.timeline"
			case .reader: return "babel2.settings.reader"
			case .translation: return "babel2.settings.translation"
			case .appearance: return "babel2.settings.appearance"
			case .notifications: return "babel2.settings.notifications"
			case .support: return "babel2.settings.support"
			}
		}

		/// Figma 只有「翻译」是正式矢量图标；其余 7 个是生成的占位图，按用户决定用系统图标、统一次要灰。
		var icon: UIImage? {
			let configuration = UIImage.SymbolConfiguration(pointSize: 17, weight: .regular)
			switch self {
			case .accounts: return UIImage(systemName: "person.crop.circle", withConfiguration: configuration)
			case .subscriptions: return UIImage(systemName: "dot.radiowaves.up.forward", withConfiguration: configuration)
			case .timeline: return UIImage(systemName: "list.bullet", withConfiguration: configuration)
			case .reader: return UIImage(systemName: "doc.plaintext", withConfiguration: configuration)
			case .translation: return UIImage(named: "Babel2SettingsTranslation")
			case .appearance: return UIImage(systemName: "circle.lefthalf.filled", withConfiguration: configuration)
			case .notifications: return UIImage(systemName: "bell", withConfiguration: configuration)
			case .support: return UIImage(systemName: "questionmark.circle", withConfiguration: configuration)
			}
		}
	}

	init(service: Babel2SettingsService) {
		super.init(service: service, kind: .root, title: Babel2SettingsText.t("Settings"))
		restorationIdentifier = "babel2.settings"
	}

	required init?(coder: NSCoder) { nil }

	override func buildContent() {
		for category in Category.allCases {
			let row = Babel2SettingsDisclosureRow(
				title: Babel2SettingsText.t(category.titleKey),
				detail: Babel2SettingsText.t(category.detailKey),
				icon: category.icon
			)
			row.onTap = { [weak self] in self?.open(category) }
			add(row, identifier: category.identifier)
		}
	}

	func open(_ category: Category) {
		let page: UIViewController
		switch category {
		case .accounts: page = Babel2SettingsAccountsViewController(service: service)
		case .subscriptions: page = Babel2SettingsSubscriptionsViewController(service: service)
		case .timeline: page = Babel2SettingsTimelineViewController(service: service)
		case .reader: page = Babel2SettingsReaderViewController(service: service)
		case .translation: page = Babel2SettingsTranslationViewController(service: service)
		case .appearance: page = Babel2SettingsAppearanceViewController(service: service)
		case .notifications: page = Babel2SettingsNotificationsViewController(service: service)
		case .support: page = Babel2SettingsSupportViewController(service: service)
		}
		push(page)
	}
}

// MARK: - 文章列表（Figma 110:360）

/// 排序（弹出菜单：最新优先 / 最旧优先）+「全部标为已读前确认」开关。
/// 「分组方式」「刷新时清除已读文章」不放：Babel 2.0 的列表只显示单个订阅源、没有刷新动作（用户 2026-09-25 同意）。
final class Babel2SettingsTimelineViewController: Babel2SettingsPage {
	private var sortRow: Babel2SettingsSelectRow?

	init(service: Babel2SettingsService) {
		super.init(service: service, kind: .back, title: Babel2SettingsText.t("Article List"))
	}

	required init?(coder: NSCoder) { nil }

	override func buildContent() {
		addSection(Babel2SettingsText.t("Sorting"))
		let sort = Babel2SettingsSelectRow(title: Babel2SettingsText.t("Sort Unread Articles"), value: sortText)
		sort.onTap = { [weak self, weak sort] in
			guard let self, let sort else { return }
			let newest = self.service.sortNewestFirst
			self.presentChoices([
				.init(title: Babel2SettingsText.t("Newest First"), isSelected: newest),
				.init(title: Babel2SettingsText.t("Oldest First"), isSelected: !newest)
			], from: sort) { [weak self] index in
				guard let self else { return }
				self.service.sortNewestFirst = index == 0
				self.sortRow?.setValue(self.sortText)
			}
		}
		sortRow = add(sort, identifier: "babel2.settings.timeline.sort")

		addSection(Babel2SettingsText.t("Read Behavior"))
		add(Babel2SettingsToggleRow(title: Babel2SettingsText.t("Confirm Before Marking All as Read"), isOn: service.confirmMarkAllRead) { [weak self] on in
			self?.service.confirmMarkAllRead = on
		}, identifier: "babel2.settings.timeline.confirm-mark-all-read")
	}

	private var sortText: String {
		Babel2SettingsText.t(service.sortNewestFirst ? "Newest First" : "Oldest First")
	}
}

// MARK: - 阅读器（Figma 110:380）

/// 打开链接（弹出菜单：Babel 内置浏览器 / 系统浏览器）。
/// 文章主题、JavaScript、全屏文章不放：Babel 2.0 阅读页不走这三个旧设置（用户 2026-09-25 同意）。
final class Babel2SettingsReaderViewController: Babel2SettingsPage {
	private var linksRow: Babel2SettingsSelectRow?

	init(service: Babel2SettingsService) {
		super.init(service: service, kind: .back, title: Babel2SettingsText.t("Reader"))
	}

	required init?(coder: NSCoder) { nil }

	override func buildContent() {
		addSection(Babel2SettingsText.t("Reading"))
		let links = Babel2SettingsSelectRow(title: Babel2SettingsText.t("Open Links"), value: linksText)
		links.onTap = { [weak self, weak links] in
			guard let self, let links else { return }
			let inApp = self.service.openLinksInApp
			self.presentChoices([
				.init(title: Babel2SettingsText.t("Babel In-App Browser"), isSelected: inApp),
				.init(title: Babel2SettingsText.t("System Browser"), isSelected: !inApp)
			], from: links) { [weak self] index in
				guard let self else { return }
				self.service.openLinksInApp = index == 0
				self.linksRow?.setValue(self.linksText)
			}
		}
		linksRow = add(links, identifier: "babel2.settings.reader.open-links")
	}

	private var linksText: String {
		Babel2SettingsText.t(service.openLinksInApp ? "Babel In-App Browser" : "System Browser")
	}
}

// MARK: - 翻译（Figma 110:400）

final class Babel2SettingsTranslationViewController: Babel2SettingsPage {
	private var modelRow: Babel2SettingsValueRow?
	private var keyRow: Babel2SettingsValueRow?

	init(service: Babel2SettingsService) {
		super.init(service: service, kind: .back, title: Babel2SettingsText.t("Translation"))
	}

	required init?(coder: NSCoder) { nil }

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		// 从编辑页保存回来后刷新显示的值
		modelRow?.setValue(service.translationModelDisplayName(service.translationModelID))
		keyRow?.setValue(keyStatus)
	}

	override func buildContent() {
		addSection(Babel2SettingsText.t("Translation Service"))
		let model = Babel2SettingsValueRow(title: Babel2SettingsText.t("Translation Model"), value: service.translationModelDisplayName(service.translationModelID))
		model.onTap = { [weak self] in
			guard let self else { return }
			self.push(Babel2SettingsTranslationModelViewController(service: self.service))
		}
		modelRow = add(model, identifier: "babel2.settings.translation.model")
		let key = Babel2SettingsValueRow(title: Babel2SettingsText.t("Translation API Key"), value: keyStatus)
		key.onTap = { [weak self] in
			guard let self else { return }
			self.push(Babel2SettingsTranslationAPIViewController(service: self.service))
		}
		keyRow = add(key, identifier: "babel2.settings.translation.api")
	}

	private var keyStatus: String {
		Babel2SettingsText.t((service.translationAPIKey ?? "").isEmpty ? "Not Set" : "Set")
	}
}

// MARK: - 外观与语言（Figma 110:420，弹出菜单 06A / 06B / 06C）

final class Babel2SettingsAppearanceViewController: Babel2SettingsPage {
	private var modeRow: Babel2SettingsSelectRow?
	private var accentRow: Babel2SettingsSelectRow?
	private var languageRow: Babel2SettingsSelectRow?

	init(service: Babel2SettingsService) {
		super.init(service: service, kind: .back, title: Babel2SettingsText.t("Appearance & Language"))
	}

	required init?(coder: NSCoder) { nil }

	static func modeText(_ mode: Babel2AppearanceMode) -> String {
		switch mode {
		case .automatic: return Babel2SettingsText.t("Automatic")
		case .light: return Babel2SettingsText.t("Light")
		case .dark: return Babel2SettingsText.t("Dark")
		}
	}

	override func buildContent() {
		addSection(Babel2SettingsText.t("Interface"))

		let mode = Babel2SettingsSelectRow(title: Babel2SettingsText.t("Color Mode"), value: Self.modeText(service.appearance))
		mode.onTap = { [weak self, weak mode] in
			guard let self, let mode else { return }
			let current = self.service.appearance
			self.presentChoices(Babel2AppearanceMode.allCases.map { .init(title: Self.modeText($0), isSelected: $0 == current) }, from: mode) { [weak self] index in
				guard let self else { return }
				self.service.appearance = Babel2AppearanceMode.allCases[index]
				self.modeRow?.setValue(Self.modeText(self.service.appearance))
			}
		}
		modeRow = add(mode, identifier: "babel2.settings.appearance.mode")

		let accent = Babel2SettingsSelectRow(title: Babel2SettingsText.t("Accent Color"), value: accentName)
		accent.onTap = { [weak self, weak accent] in
			guard let self, let accent else { return }
			let options = self.service.accentOptions
			let current = self.service.accentID
			self.presentChoices(options.map { .init(title: $0.name, isSelected: $0.id == current, swatch: $0.color) }, from: accent) { [weak self] index in
				guard let self, index < options.count else { return }
				self.service.accentID = options[index].id
				self.accentRow?.setValue(self.accentName)
			}
		}
		accentRow = add(accent, identifier: "babel2.settings.appearance.accent")

		let language = Babel2SettingsSelectRow(title: Babel2SettingsText.t("Interface Language"), value: languageName)
		language.onTap = { [weak self, weak language] in
			guard let self, let language else { return }
			let options = self.service.languageOptions
			let current = self.service.languageCode
			self.presentChoices(options.map { .init(title: $0.name, isSelected: $0.code == current) }, from: language) { [weak self] index in
				guard let self, index < options.count else { return }
				let changed = options[index].code != self.service.languageCode
				self.service.languageCode = options[index].code
				self.languageRow?.setValue(self.languageName)
				// 界面文字在 app 启动时加载：改完要重启才全部生效（沿用 1.x 做法：只提示，不代为退出）
				if changed {
					self.presentMessage(title: Babel2SettingsText.t("Restart Required"),
										message: Babel2SettingsText.t("The new language takes effect the next time you open Babel."))
				}
			}
		}
		languageRow = add(language, identifier: "babel2.settings.appearance.language")
	}

	private var accentName: String {
		service.accentOptions.first { $0.id == service.accentID }?.name ?? ""
	}

	private var languageName: String {
		service.languageOptions.first { $0.code == service.languageCode }?.name ?? ""
	}
}

// MARK: - 通知（Figma 110:440）

final class Babel2SettingsNotificationsViewController: Babel2SettingsPage {
	init(service: Babel2SettingsService) {
		super.init(service: service, kind: .back, title: Babel2SettingsText.t("Notifications"))
	}

	required init?(coder: NSCoder) { nil }

	override func buildContent() {
		addSection(Babel2SettingsText.t("System Notifications"))
		let open = Babel2SettingsActionRow(title: Babel2SettingsText.t("Open System Notification Settings"))
		open.onTap = { [weak self] in self?.service.openSystemNotificationSettings() }
		add(open, identifier: "babel2.settings.notifications.open")
		addSpacing(4)
		add(Babel2SettingsNoteLabel(text: Babel2SettingsText.t("Notification permission is managed by iOS. New-article notifications for each feed are still configured in that account or feed's details.")))
	}
}

// MARK: - 支持与诊断（Figma 110:460）

/// 日志、统计、关于是现成的旧页面（自带右上角「拷贝 / 刷新」等按钮），以底部卡片弹出、保留它们自己的导航栏。
final class Babel2SettingsSupportViewController: Babel2SettingsPage {
	init(service: Babel2SettingsService) {
		super.init(service: service, kind: .back, title: Babel2SettingsText.t("Support & Diagnostics"))
	}

	required init?(coder: NSCoder) { nil }

	private static func title(_ kind: Babel2DiagnosticsKind) -> String {
		switch kind {
		case .errorLog: return Babel2SettingsText.t("Error Log")
		case .activityLog: return Babel2SettingsText.t("Activity Log")
		case .accountStats: return Babel2SettingsText.t("Account Statistics")
		case .dinosaurs: return Babel2SettingsText.t("Dinosaurs")
		case .iCloudStats: return Babel2SettingsText.t("iCloud Storage Statistics")
		}
	}

	private static func title(_ kind: Babel2HelpKind) -> String {
		switch kind {
		case .help: return Babel2SettingsText.t("Help")
		case .forum: return Babel2SettingsText.t("Community Forum")
		case .releaseNotes: return Babel2SettingsText.t("Release Notes")
		case .bugTracker: return Babel2SettingsText.t("Bug Tracker")
		}
	}

	override func buildContent() {
		addSection(Babel2SettingsText.t("Diagnostics"))
		// 没有 iCloud 账户时不显示 iCloud 存储统计（与上游设置页同一规则）
		for kind in Babel2DiagnosticsKind.allCases where kind != .iCloudStats || service.hasICloudAccount {
			let row = Babel2SettingsValueRow(title: Self.title(kind), value: nil)
			row.onTap = { [weak self] in
				guard let self, let page = self.service.makeDiagnosticsPage(kind) else { return }
				self.present(page, animated: true)
			}
			add(row, identifier: "babel2.settings.support.\(kind)")
		}
		addSection(Babel2SettingsText.t("Help & About"))
		for kind in Babel2HelpKind.allCases {
			let row = Babel2SettingsValueRow(title: Self.title(kind), value: nil)
			row.onTap = { [weak self] in self?.service.openHelp(kind) }
			add(row, identifier: "babel2.settings.support.\(kind)")
		}
		let about = Babel2SettingsValueRow(title: Babel2SettingsText.t("About Babel"), value: nil)
		about.onTap = { [weak self] in
			guard let self else { return }
			self.present(self.service.makeAboutPage(), animated: true)
		}
		add(about, identifier: "babel2.settings.support.about")
	}
}
