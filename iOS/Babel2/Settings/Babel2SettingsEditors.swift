import UIKit

// 点保存才生效的编辑页（Figma「Navigation Bar / Settings Editor」：左 × 取消、右 ✓ 保存）。
// 取消 = 丢弃本页所有改动直接返回。

// MARK: - 订阅发现 API（Figma 110:520）

final class Babel2SettingsDiscoveryKeysViewController: Babel2SettingsPage {
	private var redditID: Babel2SettingsTextField!
	private var redditSecret: Babel2SettingsTextField!
	private var youTubeKey: Babel2SettingsTextField!

	init(service: Babel2SettingsService) {
		super.init(service: service, kind: .editor, title: Babel2SettingsText.t("Discovery API"))
	}

	required init?(coder: NSCoder) { nil }

	override func buildContent() {
		contentStack.spacing = 8
		addSection("Reddit")
		redditID = add(Babel2SettingsTextField(label: "Client ID", text: service.redditClientID, secure: false, identifier: "babel2.settings.discovery.reddit-id"))
		redditSecret = add(Babel2SettingsTextField(label: "Client Secret", text: service.redditClientSecret, secure: true, identifier: "babel2.settings.discovery.reddit-secret"))
		let redditLink = Babel2SettingsActionRow(title: Babel2SettingsText.t("Open reddit.com/prefs/apps"))
		redditLink.onTap = { UIApplication.shared.open(URL(string: "https://www.reddit.com/prefs/apps")!) }
		add(redditLink, identifier: "babel2.settings.discovery.reddit-link")

		addSection("YouTube")
		youTubeKey = add(Babel2SettingsTextField(label: "API Key", text: service.youTubeAPIKey, secure: true, identifier: "babel2.settings.discovery.youtube-key"))
		let youTubeLink = Babel2SettingsActionRow(title: Babel2SettingsText.t("Open Google Cloud Console"))
		youTubeLink.onTap = { UIApplication.shared.open(URL(string: "https://console.cloud.google.com/apis/credentials")!) }
		add(youTubeLink, identifier: "babel2.settings.discovery.youtube-link")
	}

	override func saveTapped() {
		view.endEditing(true)
		service.saveDiscoveryKeys(redditClientID: redditID.text, redditClientSecret: redditSecret.text, youTubeAPIKey: youTubeKey.text)
		leadingTapped()
	}

	/// 仅供自动化测试。
	var fieldsForTesting: [Babel2SettingsTextField] { [redditID, redditSecret, youTubeKey] }
}

// MARK: - 翻译 API Key（Figma 110:580）

/// API Key（遮住）+ 服务地址 + 测试连通性（用填写中的值，不保存）+ 清除 API Key（红色；保存后才生效）+ 说明。
final class Babel2SettingsTranslationAPIViewController: Babel2SettingsPage {
	private var keyField: Babel2SettingsTextField!
	private var baseURLField: Babel2SettingsTextField!
	private var testRow: Babel2SettingsActionRow!
	private var testTask: Task<Void, Never>?

	init(service: Babel2SettingsService) {
		super.init(service: service, kind: .editor, title: Babel2SettingsText.t("Translation API Key"))
	}

	required init?(coder: NSCoder) { nil }

	deinit { testTask?.cancel() }

	override func buildContent() {
		contentStack.spacing = 8
		keyField = add(Babel2SettingsTextField(label: "API Key", text: service.translationAPIKey, secure: true, identifier: "babel2.settings.translation-api.key"))
		let baseURL = service.translationBaseURL == service.translationDefaultBaseURL ? nil : service.translationBaseURL
		baseURLField = add(Babel2SettingsTextField(label: Babel2SettingsText.t("Service URL"), text: baseURL,
			placeholder: service.translationDefaultBaseURL, secure: false, keyboard: .URL, identifier: "babel2.settings.translation-api.base-url"))
		testRow = Babel2SettingsActionRow(title: Babel2SettingsText.t("Test Connection"))
		testRow.onTap = { [weak self] in self?.runTest() }
		add(testRow, identifier: "babel2.settings.translation-api.test")
		let clear = Babel2SettingsActionRow(title: Babel2SettingsText.t("Clear API Key"), destructive: true)
		clear.onTap = { [weak self] in
			self?.keyField.textField.text = nil
		}
		add(clear, identifier: "babel2.settings.translation-api.clear")
		add(Babel2SettingsNoteLabel(text: Babel2SettingsText.t("The API key is stored only in this device's keychain. Leave the service URL empty to use OpenRouter."), size: 12))
	}

	override func saveTapped() {
		view.endEditing(true)
		service.saveTranslationAPI(apiKey: keyField.text, baseURL: baseURLField.text)
		leadingTapped()
	}

	private func runTest() {
		guard testTask == nil else { return }
		let key = keyField.text
		guard !key.isEmpty else {
			presentMessage(title: Babel2SettingsText.t("Can't Test Yet"), message: Babel2SettingsText.t("Enter an API key first."))
			return
		}
		testRow.titleLabel.text = Babel2SettingsText.t("Testing…")
		testRow.isEnabled = false
		testTask = Task { [weak self] in
			guard let self else { return }
			let result = await self.service.testTranslationConnection(apiKey: key, baseURL: self.baseURLField.text)
			self.testTask = nil
			self.testRow.titleLabel.text = Babel2SettingsText.t("Test Connection")
			self.testRow.isEnabled = true
			switch result {
			case .success(let reply):
				self.presentMessage(title: Babel2SettingsText.t("Connection OK"), message: reply)
			case .failure(let message):
				self.presentMessage(title: Babel2SettingsText.t("Connection Failed"), message: message)
			}
		}
	}

	/// 仅供自动化测试。
	var keyFieldForTesting: Babel2SettingsTextField { keyField }
	var baseURLFieldForTesting: Babel2SettingsTextField { baseURLField }
}

// MARK: - 翻译模型（Figma 110:560）

/// 最上方「刷新模型列表」；「热门模型 · Top 10」（每行左侧服务商 logo）；再按服务商分组、每组恰好 3 个；底部说明。
/// 先显示缓存的目录，同时在后台刷新；刷新失败保留旧列表并提示。点保存才生效。
final class Babel2SettingsTranslationModelViewController: Babel2SettingsPage {
	private var pendingModelID: String
	private var models: [Babel2TranslationModel]
	private var refreshTask: Task<Void, Never>?
	private var isRefreshing = false
	private var refreshButton: UIButton?
	private var statusLabel: UILabel?

	init(service: Babel2SettingsService) {
		self.pendingModelID = service.translationModelID
		self.models = service.cachedTranslationModels()
		super.init(service: service, kind: .editor, title: Babel2SettingsText.t("Translation Model"))
	}

	required init?(coder: NSCoder) { nil }

	deinit { refreshTask?.cancel() }

	override func viewDidLoad() {
		super.viewDidLoad()
		// 目录为空时自动刷新一次；有缓存时不打扰（用户可手动刷新）
		if models.isEmpty { refresh() }
	}

	override func buildContent() {
		// 刷新按钮：362×44、圆角 12、浅底 + 0.5pt 细线，文字 15 半粗
		var configuration = UIButton.Configuration.plain()
		configuration.title = Babel2SettingsText.t(isRefreshing ? "Refreshing…" : "Refresh Model List")
		configuration.image = UIImage(systemName: "arrow.clockwise", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold))
		configuration.imagePadding = 8
		configuration.baseForegroundColor = Babel2SettingsStyle.primaryText
		configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
			var attributes = attributes
			attributes.font = .systemFont(ofSize: 15, weight: .semibold)
			return attributes
		}
		let button = UIButton(configuration: configuration)
		button.backgroundColor = Babel2SettingsStyle.hairline.withAlphaComponent(0.52)
		button.layer.cornerRadius = 12
		button.layer.cornerCurve = .continuous
		button.layer.borderWidth = 0.5
		button.layer.borderColor = Babel2SettingsStyle.hairline.resolvedColor(with: traitCollection).cgColor
		button.isEnabled = !isRefreshing
		button.accessibilityIdentifier = "babel2.settings.translation-model.refresh"
		button.addTarget(self, action: #selector(refreshTapped), for: .touchUpInside)
		button.translatesAutoresizingMaskIntoConstraints = false
		button.heightAnchor.constraint(equalToConstant: 44).isActive = true
		refreshButton = button
		add(button)
		addSpacing(12)

		if models.isEmpty {
			let label = Babel2SettingsNoteLabel(text: Babel2SettingsText.t(isRefreshing ? "Loading models…" : "No models yet. Tap Refresh Model List."))
			label.accessibilityIdentifier = "babel2.settings.translation-model.empty"
			statusLabel = add(label)
			addChosenModelIfHidden(inTop: [], groups: [])
			return
		}

		let top = Babel2TranslationModelRanking.top(models)
		let groups = Babel2TranslationModelRanking.vendorGroups(models)
		addChosenModelIfHidden(inTop: top, groups: groups)
		if !top.isEmpty {
			addSection(Babel2SettingsText.t("Popular Models · Top 10"))
			for model in top {
				addModelRow(model, logo: service.vendorLogo(model.vendor, traits: traitCollection))
			}
		}
		for group in groups {
			addVendorHeader(group.vendor)
			for model in group.models {
				addModelRow(model, logo: nil)
			}
		}
		addSpacing(8)
		add(Babel2SettingsNoteLabel(text: Babel2SettingsText.t("The list and popularity are refreshed from OpenRouter."), size: 11))
	}

	/// 当前选择不在热门或分组里时（例如手动填过的冷门模型），单独放在最上面，保证能看到勾。
	private func addChosenModelIfHidden(inTop top: [Babel2TranslationModel], groups: [Babel2TranslationModelRanking.VendorGroup]) {
		let visible = Set(top.map(\.id) + groups.flatMap { $0.models.map(\.id) })
		guard !visible.contains(pendingModelID) else { return }
		addSection(Babel2SettingsText.t("Current Selection"))
		let row = Babel2SettingsChoiceRow(title: service.translationModelDisplayName(pendingModelID), isSelected: true)
		row.accessibilityIdentifier = "babel2.settings.translation-model.current"
		add(row)
	}

	/// 服务商组头：32pt，20pt logo + 名称（12 半粗）。
	private func addVendorHeader(_ vendor: String) {
		let header = UIView()
		let logo = UIImageView(image: service.vendorLogo(vendor, traits: traitCollection))
		logo.contentMode = .scaleAspectFit
		logo.layer.cornerRadius = 4
		logo.clipsToBounds = true
		let label = UILabel()
		label.text = Babel2SettingsText.f("%@ · Top 3", service.vendorDisplayName(vendor))
		label.font = .systemFont(ofSize: 12, weight: .semibold)
		label.textColor = Babel2SettingsStyle.secondaryText
		label.accessibilityTraits = .header
		for view in [logo, label] as [UIView] {
			view.translatesAutoresizingMaskIntoConstraints = false
			header.addSubview(view)
		}
		NSLayoutConstraint.activate([
			header.heightAnchor.constraint(equalToConstant: 32),
			logo.leadingAnchor.constraint(equalTo: header.leadingAnchor),
			logo.topAnchor.constraint(equalTo: header.topAnchor, constant: 6),
			logo.widthAnchor.constraint(equalToConstant: 20),
			logo.heightAnchor.constraint(equalToConstant: 20),
			label.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 28),
			label.centerYAnchor.constraint(equalTo: logo.centerYAnchor),
			label.trailingAnchor.constraint(lessThanOrEqualTo: header.trailingAnchor)
		])
		addSpacing(8)
		add(header, identifier: "babel2.settings.translation-model.vendor.\(vendor)")
	}

	private func addModelRow(_ model: Babel2TranslationModel, logo: UIImage?) {
		let row = Babel2SettingsChoiceRow(title: model.name, isSelected: model.id == pendingModelID, logo: logo)
		row.accessibilityIdentifier = "babel2.settings.translation-model.option.\(model.id)"
		row.onTap = { [weak self] in self?.choose(model.id) }
		add(row)
	}

	private func choose(_ id: String) {
		pendingModelID = id
		for case let row as Babel2SettingsChoiceRow in contentStack.arrangedSubviews {
			if let identifier = row.accessibilityIdentifier, identifier.hasPrefix("babel2.settings.translation-model.option.") {
				row.setSelected(identifier == "babel2.settings.translation-model.option.\(id)")
			}
		}
	}

	@objc private func refreshTapped() { refresh() }

	private func refresh() {
		guard refreshTask == nil else { return }
		isRefreshing = true
		rebuildContent()
		refreshTask = Task { [weak self] in
			guard let self else { return }
			do {
				let fresh = try await self.service.refreshTranslationModels()
				if !fresh.isEmpty { self.models = fresh }
				self.finishRefresh(error: nil)
			} catch {
				self.finishRefresh(error: error)
			}
		}
	}

	private func finishRefresh(error: Error?) {
		refreshTask = nil
		isRefreshing = false
		rebuildContent()
		if let error {
			// 刷新失败保留原来的列表
			presentMessage(title: Babel2SettingsText.t("Couldn't Refresh Models"), message: error.localizedDescription)
		}
	}

	override func saveTapped() {
		service.translationModelID = pendingModelID
		leadingTapped()
	}

	/// 仅供自动化测试。
	func chooseForTesting(_ id: String) { choose(id) }
	var pendingModelIDForTesting: String { pendingModelID }
}
