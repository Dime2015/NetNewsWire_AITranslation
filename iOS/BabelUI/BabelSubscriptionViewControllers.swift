//
//  BabelSubscriptionViewControllers.swift
//  NetNewsWire
//
//  Babel 的订阅录入与管理界面。视觉层遵循 Figma「订阅与发现」(110:340)：
//  暖灰阅读底、58pt 自绘导航、20pt 内容边距和无卡片的细分隔行。
//

import UIKit
import Account
import RSCore
import RSTree

// MARK: - Add subscription

final class BabelAddSubscriptionViewController: UIViewController, UITextFieldDelegate {

	private let urlField = UITextField()
	private let nameField = UITextField()
	private let destinationButton = UIButton(type: .system)
	private let addButton = UIButton(type: .system)
	private let destinationValueLabel = UILabel()
	private var destination: Container?
	private var isCreatingFeed = false

	override func viewDidLoad() {
		super.viewDidLoad()
		view.backgroundColor = BabelPalette.background
		configureNavigation(title: "添加订阅源", trailingTitle: "管理", trailingAction: #selector(openManagement))
		configureForm()
		selectInitialDestination()
	}

	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)
		if urlField.text?.isEmpty ?? true { urlField.becomeFirstResponder() }
	}

	private func configureNavigation(title: String, trailingTitle: String?, trailingAction: Selector?) {
		let header = UIView()
		header.backgroundColor = BabelPalette.background
		header.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(header)

		let back = UIButton(type: .custom)
		back.tintColor = BabelPalette.ink
		back.setImage(UIImage(systemName: "chevron.left", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)), for: .normal)
		back.accessibilityLabel = "返回"
		back.addTarget(self, action: #selector(close), for: .touchUpInside)
		back.translatesAutoresizingMaskIntoConstraints = false
		header.addSubview(back)

		let titleLabel = UILabel()
		titleLabel.text = title
		titleLabel.textColor = BabelPalette.ink
		titleLabel.font = .systemFont(ofSize: 24, weight: .semibold)
		titleLabel.translatesAutoresizingMaskIntoConstraints = false
		header.addSubview(titleLabel)

		let hairline = UIView()
		hairline.backgroundColor = BabelPalette.hairline
		hairline.translatesAutoresizingMaskIntoConstraints = false
		header.addSubview(hairline)

		NSLayoutConstraint.activate([
			header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			// Figma 110:340 fixes this bar at y=59 on the 402×874 canvas.
			header.topAnchor.constraint(equalTo: view.topAnchor, constant: 59),
			header.heightAnchor.constraint(equalToConstant: 58),
			back.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 10),
			back.centerYAnchor.constraint(equalTo: header.topAnchor, constant: 24),
			back.widthAnchor.constraint(equalToConstant: 44),
			back.heightAnchor.constraint(equalToConstant: 44),
			titleLabel.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 58),
			titleLabel.topAnchor.constraint(equalTo: header.topAnchor, constant: 7),
			hairline.leadingAnchor.constraint(equalTo: header.leadingAnchor),
			hairline.trailingAnchor.constraint(equalTo: header.trailingAnchor),
			hairline.bottomAnchor.constraint(equalTo: header.bottomAnchor),
			hairline.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale)
		])

		if let trailingTitle, let trailingAction {
			let trailing = UIButton(type: .system)
			trailing.setTitle(trailingTitle, for: .normal)
			trailing.setTitleColor(BabelPalette.mutedInk, for: .normal)
			trailing.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
			trailing.addTarget(self, action: trailingAction, for: .touchUpInside)
			trailing.translatesAutoresizingMaskIntoConstraints = false
			header.addSubview(trailing)
			NSLayoutConstraint.activate([
				trailing.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -12),
				trailing.centerYAnchor.constraint(equalTo: back.centerYAnchor),
				trailing.widthAnchor.constraint(greaterThanOrEqualToConstant: 44),
				trailing.heightAnchor.constraint(equalToConstant: 44)
			])
		}
	}

	private func configureForm() {
		let content = UIScrollView()
		content.alwaysBounceVertical = true
		content.keyboardDismissMode = .interactive
		content.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(content)

		let stack = UIStackView()
		stack.axis = .vertical
		stack.alignment = .fill
		stack.spacing = 0
		stack.translatesAutoresizingMaskIntoConstraints = false
		content.addSubview(stack)

		let intro = UILabel()
		intro.text = "搜索网站或粘贴 RSS 地址，Babel 会先验证可订阅的新闻源。"
		intro.font = .systemFont(ofSize: 14, weight: .regular)
		intro.textColor = BabelPalette.mutedInk
		intro.numberOfLines = 0
		intro.translatesAutoresizingMaskIntoConstraints = false
		stack.addArrangedSubview(intro)
		intro.heightAnchor.constraint(greaterThanOrEqualToConstant: 46).isActive = true

		stack.addArrangedSubview(sectionLabel("发现订阅源"))
		stack.addArrangedSubview(makeDiscoveryRow())
		stack.addArrangedSubview(sectionLabel("手动添加"))
		stack.addArrangedSubview(makeInputRow(label: "地址", field: urlField, placeholder: "https://example.com/rss", keyboardType: .URL))
		stack.addArrangedSubview(makeInputRow(label: "名称", field: nameField, placeholder: "可选", keyboardType: .default))
		stack.addArrangedSubview(sectionLabel("保存位置"))
		stack.addArrangedSubview(makeDestinationRow())

		let help = UILabel()
		help.text = "选择账户或文件夹；默认沿用你上一次使用的位置。"
		help.font = .systemFont(ofSize: 12, weight: .regular)
		help.textColor = BabelPalette.mutedInk
		help.numberOfLines = 0
		help.translatesAutoresizingMaskIntoConstraints = false
		stack.addArrangedSubview(help)
		help.topAnchor.constraint(equalTo: stack.topAnchor, constant: 0).isActive = false
		help.heightAnchor.constraint(greaterThanOrEqualToConstant: 43).isActive = true

		addButton.setTitle("添加订阅源", for: .normal)
		addButton.setTitleColor(BabelPalette.background, for: .normal)
		addButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
		addButton.backgroundColor = BabelPalette.ink
		addButton.layer.cornerRadius = 9
		addButton.addTarget(self, action: #selector(addFeed), for: .touchUpInside)
		addButton.translatesAutoresizingMaskIntoConstraints = false
		stack.addArrangedSubview(addButton)
		addButton.heightAnchor.constraint(equalToConstant: 48).isActive = true

		NSLayoutConstraint.activate([
			content.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			content.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			content.topAnchor.constraint(equalTo: view.topAnchor, constant: 117),
			content.bottomAnchor.constraint(equalTo: view.bottomAnchor),
			stack.leadingAnchor.constraint(equalTo: content.contentLayoutGuide.leadingAnchor, constant: 20),
			stack.trailingAnchor.constraint(equalTo: content.contentLayoutGuide.trailingAnchor, constant: -20),
			stack.topAnchor.constraint(equalTo: content.contentLayoutGuide.topAnchor, constant: 18),
			stack.bottomAnchor.constraint(equalTo: content.contentLayoutGuide.bottomAnchor, constant: -24),
			stack.widthAnchor.constraint(equalTo: content.frameLayoutGuide.widthAnchor, constant: -40)
		])

		urlField.autocapitalizationType = .none
		urlField.autocorrectionType = .no
		urlField.delegate = self
		nameField.delegate = self
		NotificationCenter.default.addObserver(self, selector: #selector(updateAddAvailability), name: UITextField.textDidChangeNotification, object: urlField)
		updateAddAvailability()
	}

	private func makeDiscoveryRow() -> UIView {
		let row = UIButton(type: .system)
		var configuration = UIButton.Configuration.plain()
		configuration.title = "搜索网站或 RSS 地址"
		configuration.image = UIImage(systemName: "magnifyingglass", withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .regular))
		configuration.imagePadding = 8
		configuration.baseForegroundColor = BabelPalette.ink
		configuration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
		row.configuration = configuration
		row.contentHorizontalAlignment = .leading
		row.titleLabel?.font = .systemFont(ofSize: 16, weight: .regular)
		row.addTarget(self, action: #selector(openDiscovery), for: .touchUpInside)
		row.translatesAutoresizingMaskIntoConstraints = false
		let line = makeHairline()
		row.addSubview(line)
		NSLayoutConstraint.activate([
			row.heightAnchor.constraint(equalToConstant: 52),
			line.leadingAnchor.constraint(equalTo: row.leadingAnchor),
			line.trailingAnchor.constraint(equalTo: row.trailingAnchor),
			line.bottomAnchor.constraint(equalTo: row.bottomAnchor),
			line.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale)
		])
		return row
	}

	private func sectionLabel(_ text: String) -> UIView {
		let container = UIView()
		let label = UILabel()
		label.text = text.uppercased()
		label.font = .systemFont(ofSize: 11, weight: .semibold)
		label.textColor = BabelPalette.mutedInk
		label.translatesAutoresizingMaskIntoConstraints = false
		container.addSubview(label)
		NSLayoutConstraint.activate([
			container.heightAnchor.constraint(equalToConstant: 36),
			label.leadingAnchor.constraint(equalTo: container.leadingAnchor),
			label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8)
		])
		return container
	}

	private func makeInputRow(label: String, field: UITextField, placeholder: String, keyboardType: UIKeyboardType) -> UIView {
		let row = UIView()
		let caption = UILabel()
		caption.text = label
		caption.font = .systemFont(ofSize: 16, weight: .regular)
		caption.textColor = BabelPalette.ink
		caption.translatesAutoresizingMaskIntoConstraints = false
		row.addSubview(caption)
		field.font = .systemFont(ofSize: 16, weight: .regular)
		field.textColor = BabelPalette.ink
		field.placeholder = placeholder
		field.attributedPlaceholder = NSAttributedString(string: placeholder, attributes: [.foregroundColor: BabelPalette.tertiaryInk])
		field.keyboardType = keyboardType
		field.returnKeyType = .next
		field.textAlignment = .right
		field.translatesAutoresizingMaskIntoConstraints = false
		row.addSubview(field)
		let line = makeHairline()
		row.addSubview(line)
		NSLayoutConstraint.activate([
			row.heightAnchor.constraint(equalToConstant: 52),
			caption.leadingAnchor.constraint(equalTo: row.leadingAnchor),
			caption.centerYAnchor.constraint(equalTo: row.centerYAnchor),
			field.leadingAnchor.constraint(greaterThanOrEqualTo: caption.trailingAnchor, constant: 16),
			field.trailingAnchor.constraint(equalTo: row.trailingAnchor),
			field.centerYAnchor.constraint(equalTo: row.centerYAnchor),
			line.leadingAnchor.constraint(equalTo: row.leadingAnchor),
			line.trailingAnchor.constraint(equalTo: row.trailingAnchor),
			line.bottomAnchor.constraint(equalTo: row.bottomAnchor),
			line.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale)
		])
		return row
	}

	private func makeDestinationRow() -> UIView {
		let row = UIView()
		let title = UILabel()
		title.text = "保存到"
		title.font = .systemFont(ofSize: 16, weight: .regular)
		title.textColor = BabelPalette.ink
		title.translatesAutoresizingMaskIntoConstraints = false
		row.addSubview(title)
		destinationValueLabel.font = .systemFont(ofSize: 14, weight: .regular)
		destinationValueLabel.textColor = BabelPalette.mutedInk
		destinationValueLabel.textAlignment = .right
		destinationValueLabel.translatesAutoresizingMaskIntoConstraints = false
		row.addSubview(destinationValueLabel)
		let chevron = UIImageView(image: UIImage(systemName: "chevron.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .regular)))
		chevron.tintColor = BabelPalette.tertiaryInk
		chevron.translatesAutoresizingMaskIntoConstraints = false
		row.addSubview(chevron)
		destinationButton.addTarget(self, action: #selector(chooseDestination), for: .touchUpInside)
		destinationButton.translatesAutoresizingMaskIntoConstraints = false
		row.addSubview(destinationButton)
		let line = makeHairline()
		row.addSubview(line)
		NSLayoutConstraint.activate([
			row.heightAnchor.constraint(equalToConstant: 52),
			title.leadingAnchor.constraint(equalTo: row.leadingAnchor),
			title.centerYAnchor.constraint(equalTo: row.centerYAnchor),
			chevron.trailingAnchor.constraint(equalTo: row.trailingAnchor),
			chevron.centerYAnchor.constraint(equalTo: row.centerYAnchor),
			chevron.widthAnchor.constraint(equalToConstant: 16), chevron.heightAnchor.constraint(equalToConstant: 16),
			destinationValueLabel.leadingAnchor.constraint(greaterThanOrEqualTo: title.trailingAnchor, constant: 16),
			destinationValueLabel.trailingAnchor.constraint(equalTo: chevron.leadingAnchor, constant: -7),
			destinationValueLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor),
			destinationButton.leadingAnchor.constraint(equalTo: row.leadingAnchor),
			destinationButton.trailingAnchor.constraint(equalTo: row.trailingAnchor),
			destinationButton.topAnchor.constraint(equalTo: row.topAnchor),
			destinationButton.bottomAnchor.constraint(equalTo: row.bottomAnchor),
			line.leadingAnchor.constraint(equalTo: row.leadingAnchor), line.trailingAnchor.constraint(equalTo: row.trailingAnchor),
			line.bottomAnchor.constraint(equalTo: row.bottomAnchor), line.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale)
		])
		return row
	}

	private func selectInitialDestination() {
		if let defaultContainer = AddFeedDefaultContainer.defaultContainer {
			destination = defaultContainer
		} else {
			destination = AccountManager.shared.sortedActiveAccounts.first
		}
		updateDestinationLabel()
	}

	@objc private func chooseDestination() {
		let accounts = AccountManager.shared.sortedActiveAccounts
		guard !accounts.isEmpty else { return }
		let sheet = UIAlertController(title: "保存到", message: "选择账户或文件夹", preferredStyle: .actionSheet)
		for account in accounts {
			sheet.addAction(UIAlertAction(title: account.nameForDisplay, style: .default) { [weak self] _ in
				self?.setDestination(account)
			})
			for folder in (account.folders ?? []).sorted(by: { $0.nameForDisplay.localizedCaseInsensitiveCompare($1.nameForDisplay) == .orderedAscending }) {
				sheet.addAction(UIAlertAction(title: "\(account.nameForDisplay) / \(folder.nameForDisplay)", style: .default) { [weak self] _ in
					self?.setDestination(folder)
				})
			}
		}
		sheet.addAction(UIAlertAction(title: "取消", style: .cancel))
		present(sheet, animated: true)
	}

	private func setDestination(_ destination: Container) {
		self.destination = destination
		AddFeedDefaultContainer.saveDefaultContainer(destination)
		updateDestinationLabel()
		updateAddAvailability()
	}

	private func updateDestinationLabel() {
		guard let destination else {
			destinationValueLabel.text = "请先添加账户"
			return
		}
		if let folder = destination as? Folder {
			destinationValueLabel.text = "\(folder.account?.nameForDisplay ?? "") / \(folder.nameForDisplay)"
		} else {
			destinationValueLabel.text = (destination as? DisplayNameProvider)?.nameForDisplay
		}
	}

	@objc private func updateAddAvailability() {
		let normalized = (urlField.text ?? "").normalizedURL
		addButton.isEnabled = !normalized.isEmpty && URL(string: normalized) != nil && destination != nil && !isCreatingFeed
		addButton.alpha = addButton.isEnabled ? 1 : 0.38
	}

	@objc private func addFeed() {
		let normalizedURL = (urlField.text ?? "").normalizedURL
		guard let url = URL(string: normalizedURL), let destination else { return }
		let account: Account? = (destination as? Account) ?? (destination as? Folder)?.account
		guard let account else { return }
		guard !account.hasFeed(withURL: url.absoluteString) else {
			presentError(AccountError.createErrorAlreadySubscribed)
			return
		}
		isCreatingFeed = true
		updateAddAvailability()
		addButton.setTitle("正在添加…", for: .normal)
		let feedName = nameField.text?.trimmingCharacters(in: .whitespacesAndNewlines)
		BatchUpdate.shared.start()
		account.createFeed(url: url.absoluteString, name: feedName?.isEmpty == true ? nil : feedName, container: destination, validateFeed: true) { [weak self] result in
			DispatchQueue.main.async {
				guard let self else { return }
				BatchUpdate.shared.end()
				switch result {
				case .success(let feed):
					NotificationCenter.default.post(name: .UserDidAddFeed, object: self, userInfo: [UserInfoKey.feed: feed])
					self.navigationController?.popViewController(animated: true)
				case .failure(let error):
					self.isCreatingFeed = false
					self.addButton.setTitle("添加订阅源", for: .normal)
					self.updateAddAvailability()
					self.presentError(error)
				}
			}
		}
	}

	@objc private func close() { navigationController?.popViewController(animated: true) }
	@objc private func openManagement() { navigationController?.pushViewController(BabelSubscriptionManagementViewController(), animated: true) }
	@objc private func openDiscovery() {
		let discovery = BabelFeedDiscoveryViewController()
		discovery.onSelect = { [weak self] candidate in
			guard let self else { return }
			self.urlField.text = candidate.urlString
			if self.nameField.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
				self.nameField.text = candidate.title
			}
			self.updateAddAvailability()
		}
		navigationController?.pushViewController(discovery, animated: true)
	}

	func textFieldShouldReturn(_ textField: UITextField) -> Bool {
		if textField === urlField { nameField.becomeFirstResponder() } else { textField.resignFirstResponder() }
		return true
	}

	private func makeHairline() -> UIView {
		let line = UIView()
		line.backgroundColor = BabelPalette.hairline
		line.translatesAutoresizingMaskIntoConstraints = false
		return line
	}
}

// MARK: - Feed discovery

/// 网站发现不是一个预置目录：它把用户给出的站点交给已有的 FeedFinder，展示
/// 找到的候选订阅源，再把用户选中的地址带回添加页。这样不会把“搜索”伪装成
/// 一个没有接入搜索服务的关键词推荐列表。
struct BabelDiscoveredFeed: Hashable {
	let title: String?
	let urlString: String
}

final class BabelFeedDiscoveryViewController: UIViewController, UITextFieldDelegate, UITableViewDataSource, UITableViewDelegate {

	var onSelect: ((BabelDiscoveredFeed) -> Void)?

	private let queryField = UITextField()
	private let searchButton = UIButton(type: .system)
	private let stateLabel = UILabel()
	private let tableView = UITableView(frame: .zero, style: .plain)
	private var results = [BabelDiscoveredFeed]()
	private var searchTask: Task<Void, Never>?

	override func viewDidLoad() {
		super.viewDidLoad()
		view.backgroundColor = BabelPalette.background
		configureHeader()
		configureContent()
	}

	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)
		queryField.becomeFirstResponder()
	}

	deinit { searchTask?.cancel() }

	private func configureHeader() {
		let header = UIView()
		header.backgroundColor = BabelPalette.background
		header.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(header)
		let back = UIButton(type: .custom)
		back.setImage(UIImage(systemName: "chevron.left", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)), for: .normal)
		back.tintColor = BabelPalette.ink
		back.accessibilityLabel = "返回添加订阅源"
		back.addTarget(self, action: #selector(close), for: .touchUpInside)
		back.translatesAutoresizingMaskIntoConstraints = false
		header.addSubview(back)
		let title = UILabel()
		title.text = "搜索订阅源"
		title.font = .systemFont(ofSize: 24, weight: .semibold)
		title.textColor = BabelPalette.ink
		title.translatesAutoresizingMaskIntoConstraints = false
		header.addSubview(title)
		let line = UIView()
		line.backgroundColor = BabelPalette.hairline
		line.translatesAutoresizingMaskIntoConstraints = false
		header.addSubview(line)
		NSLayoutConstraint.activate([
			header.leadingAnchor.constraint(equalTo: view.leadingAnchor), header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			header.topAnchor.constraint(equalTo: view.topAnchor, constant: 59), header.heightAnchor.constraint(equalToConstant: 58),
			back.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 10), back.centerYAnchor.constraint(equalTo: header.topAnchor, constant: 24), back.widthAnchor.constraint(equalToConstant: 44), back.heightAnchor.constraint(equalToConstant: 44),
			title.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 58), title.topAnchor.constraint(equalTo: header.topAnchor, constant: 7),
			line.leadingAnchor.constraint(equalTo: header.leadingAnchor), line.trailingAnchor.constraint(equalTo: header.trailingAnchor), line.bottomAnchor.constraint(equalTo: header.bottomAnchor), line.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale)
		])
	}

	private func configureContent() {
		let intro = UILabel()
		intro.text = "输入网站主页或 RSS 地址。Babel 会从该站点实际可用的订阅链接中寻找候选项。"
		intro.font = .systemFont(ofSize: 14, weight: .regular)
		intro.textColor = BabelPalette.mutedInk
		intro.numberOfLines = 0
		intro.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(intro)

		queryField.font = .systemFont(ofSize: 16, weight: .regular)
		queryField.textColor = BabelPalette.ink
		queryField.placeholder = "example.com 或 https://example.com/rss"
		queryField.attributedPlaceholder = NSAttributedString(string: queryField.placeholder ?? "", attributes: [.foregroundColor: BabelPalette.tertiaryInk])
		queryField.autocapitalizationType = .none
		queryField.autocorrectionType = .no
		queryField.keyboardType = .URL
		queryField.returnKeyType = .search
		queryField.delegate = self
		queryField.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(queryField)
		let fieldLine = UIView()
		fieldLine.backgroundColor = BabelPalette.hairline
		fieldLine.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(fieldLine)

		searchButton.setTitle("查找", for: .normal)
		searchButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
		searchButton.setTitleColor(BabelPalette.background, for: .normal)
		searchButton.backgroundColor = BabelPalette.ink
		searchButton.layer.cornerRadius = 9
		searchButton.addTarget(self, action: #selector(search), for: .touchUpInside)
		searchButton.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(searchButton)
		stateLabel.text = "还没有开始搜索"
		stateLabel.font = .systemFont(ofSize: 14, weight: .regular)
		stateLabel.textColor = BabelPalette.mutedInk
		stateLabel.numberOfLines = 0
		stateLabel.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(stateLabel)

		tableView.backgroundColor = BabelPalette.background
		tableView.separatorStyle = .none
		tableView.dataSource = self
		tableView.delegate = self
		tableView.rowHeight = 64
		tableView.register(BabelFeedDiscoveryCell.self, forCellReuseIdentifier: BabelFeedDiscoveryCell.reuseIdentifier)
		tableView.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(tableView)

		NSLayoutConstraint.activate([
			intro.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20), intro.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20), intro.topAnchor.constraint(equalTo: view.topAnchor, constant: 135),
			queryField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20), queryField.trailingAnchor.constraint(equalTo: searchButton.leadingAnchor, constant: -12), queryField.topAnchor.constraint(equalTo: intro.bottomAnchor, constant: 18), queryField.heightAnchor.constraint(equalToConstant: 48),
			fieldLine.leadingAnchor.constraint(equalTo: queryField.leadingAnchor), fieldLine.trailingAnchor.constraint(equalTo: queryField.trailingAnchor), fieldLine.bottomAnchor.constraint(equalTo: queryField.bottomAnchor), fieldLine.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),
			searchButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20), searchButton.centerYAnchor.constraint(equalTo: queryField.centerYAnchor), searchButton.widthAnchor.constraint(equalToConstant: 70), searchButton.heightAnchor.constraint(equalToConstant: 44),
			stateLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20), stateLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20), stateLabel.topAnchor.constraint(equalTo: queryField.bottomAnchor, constant: 17),
			tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20), tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20), tableView.topAnchor.constraint(equalTo: stateLabel.bottomAnchor, constant: 10), tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
		])
	}

	@objc private func search() {
		let rawQuery = queryField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
		guard !rawQuery.isEmpty else { return }
		let normalized = rawQuery.contains("://") ? rawQuery : "https://\(rawQuery)"
		guard let url = URL(string: normalized), url.host != nil else {
			stateLabel.text = "请输入完整的网站或 RSS 地址。"
			return
		}
		searchTask?.cancel()
		results = []
		tableView.reloadData()
		stateLabel.text = "正在验证 \(url.host ?? normalized)…"
		searchButton.setTitle("查找中…", for: .normal)
		searchButton.isEnabled = false
		searchTask = Task { [weak self] in
			do {
				let found = try await BabelFeedDiscovery.find(url: url)
				guard !Task.isCancelled else { return }
				let ordered = found.sorted { $0.urlString.localizedCaseInsensitiveCompare($1.urlString) == .orderedAscending }
				await MainActor.run {
					guard let self else { return }
					self.results = ordered
					self.finishSearch(message: ordered.isEmpty ? "未找到可订阅的 RSS 或 Atom 地址。" : "找到 \(ordered.count) 个候选订阅源，选择一个继续。")
				}
			} catch {
				guard !Task.isCancelled else { return }
				await MainActor.run { [weak self] in
					self?.finishSearch(message: "无法从这个地址找到订阅源：\(error.localizedDescription)")
				}
			}
		}
	}

	private func finishSearch(message: String) {
		searchButton.setTitle("查找", for: .normal)
		searchButton.isEnabled = true
		stateLabel.text = message
		tableView.reloadData()
	}

	@objc private func close() { navigationController?.popViewController(animated: true) }

	func textFieldShouldReturn(_ textField: UITextField) -> Bool { search(); return true }
	func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { results.count }
	func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		let cell = tableView.dequeueReusableCell(withIdentifier: BabelFeedDiscoveryCell.reuseIdentifier, for: indexPath) as! BabelFeedDiscoveryCell
		cell.configure(with: results[indexPath.row])
		return cell
	}
	func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		let result = results[indexPath.row]
		tableView.deselectRow(at: indexPath, animated: true)
		onSelect?(result)
		navigationController?.popViewController(animated: true)
	}
}

private final class BabelFeedDiscoveryCell: UITableViewCell {
	static let reuseIdentifier = "BabelFeedDiscoveryCell"
	private let titleLabel = UILabel()
	private let urlLabel = UILabel()
	private let chevron = UIImageView(image: UIImage(systemName: "chevron.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .regular)))
	private let line = UIView()

	override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
		super.init(style: style, reuseIdentifier: reuseIdentifier)
		backgroundColor = .clear
		selectedBackgroundView = { let view = UIView(); view.backgroundColor = BabelPalette.raisedBackground; return view }()
		titleLabel.font = .systemFont(ofSize: 16, weight: .medium)
		titleLabel.textColor = BabelPalette.ink
		titleLabel.numberOfLines = 1
		urlLabel.font = .systemFont(ofSize: 12, weight: .regular)
		urlLabel.textColor = BabelPalette.mutedInk
		urlLabel.numberOfLines = 1
		chevron.tintColor = BabelPalette.tertiaryInk
		line.backgroundColor = BabelPalette.hairline
		for view in [titleLabel, urlLabel, chevron, line] { view.translatesAutoresizingMaskIntoConstraints = false; contentView.addSubview(view) }
		NSLayoutConstraint.activate([
			titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor), titleLabel.trailingAnchor.constraint(equalTo: chevron.leadingAnchor, constant: -10), titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
			urlLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor), urlLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor), urlLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 3),
			chevron.trailingAnchor.constraint(equalTo: contentView.trailingAnchor), chevron.centerYAnchor.constraint(equalTo: contentView.centerYAnchor), chevron.widthAnchor.constraint(equalToConstant: 16), chevron.heightAnchor.constraint(equalToConstant: 16),
			line.leadingAnchor.constraint(equalTo: contentView.leadingAnchor), line.trailingAnchor.constraint(equalTo: contentView.trailingAnchor), line.bottomAnchor.constraint(equalTo: contentView.bottomAnchor), line.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale)
		])
	}

	required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
	func configure(with candidate: BabelDiscoveredFeed) {
		titleLabel.text = candidate.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? candidate.title : "订阅源"
		urlLabel.text = candidate.urlString
	}
}

/// The app target does not link the FeedFinder package directly. Keep discovery
/// inside the UI target by validating a supplied URL and extracting only real
/// alternate RSS/Atom/JSON links from that response; account.createFeed still
/// performs the authoritative server-side feed validation before subscription.
private enum BabelFeedDiscovery {
	static func find(url: URL) async throws -> [BabelDiscoveredFeed] {
		var request = URLRequest(url: url)
		request.timeoutInterval = 20
		request.setValue("Mozilla/5.0 (compatible; Babel RSS discovery)", forHTTPHeaderField: "User-Agent")
		let (data, response) = try await URLSession.shared.data(for: request)
		guard let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode) else {
			throw NSError(domain: "BabelFeedDiscovery", code: 1, userInfo: [NSLocalizedDescriptionKey: "网站没有返回可读取的页面。"])
		}
		guard !data.isEmpty else {
			throw NSError(domain: "BabelFeedDiscovery", code: 2, userInfo: [NSLocalizedDescriptionKey: "网站返回了空内容。"])
		}
		let finalURL = response.url ?? url
		let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
		if looksLikeFeed(text) {
			return [BabelDiscoveredFeed(title: title(in: text), urlString: finalURL.absoluteString)]
		}
		let candidates = alternateLinks(in: text, baseURL: finalURL)
		guard !candidates.isEmpty else {
			throw NSError(domain: "BabelFeedDiscovery", code: 3, userInfo: [NSLocalizedDescriptionKey: "这个网站没有公开可识别的 RSS、Atom 或 JSON Feed 链接。"])
		}
		return candidates
	}

	private static func looksLikeFeed(_ text: String) -> Bool {
		let prefix = text.prefix(2400).lowercased()
		return prefix.contains("<rss") || prefix.contains("<feed") || prefix.contains("jsonfeed.org") || prefix.contains("\"version\": \"https://jsonfeed.org")
	}

	private static func alternateLinks(in html: String, baseURL: URL) -> [BabelDiscoveredFeed] {
		let tagPattern = #"<link\b[^>]*>"#
		guard let regex = try? NSRegularExpression(pattern: tagPattern, options: [.caseInsensitive]) else { return [] }
		let range = NSRange(html.startIndex..., in: html)
		var seen = Set<String>()
		var results = [BabelDiscoveredFeed]()
		for match in regex.matches(in: html, options: [], range: range) {
			guard let swiftRange = Range(match.range, in: html) else { continue }
			let tag = String(html[swiftRange])
			let lower = tag.lowercased()
			guard lower.contains("alternate"), lower.contains("rss") || lower.contains("atom") || lower.contains("json") else { continue }
			guard let href = attribute("href", in: tag), let resolved = URL(string: href, relativeTo: baseURL)?.absoluteURL else { continue }
			let key = resolved.absoluteString
			guard seen.insert(key).inserted else { continue }
			results.append(BabelDiscoveredFeed(title: attribute("title", in: tag), urlString: key))
		}
		return results
	}

	private static func attribute(_ name: String, in tag: String) -> String? {
		let escaped = NSRegularExpression.escapedPattern(for: name)
		let pattern = "\\b\(escaped)\\s*=\\s*(?:\\\"([^\\\"]*)\\\"|'([^']*)'|([^\\s>]+))"
		guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
			  let match = regex.firstMatch(in: tag, options: [], range: NSRange(tag.startIndex..., in: tag)) else { return nil }
		for index in 1..<4 where match.range(at: index).location != NSNotFound {
			if let range = Range(match.range(at: index), in: tag) { return String(tag[range]) }
		}
		return nil
	}

	private static func title(in text: String) -> String? {
		guard let regex = try? NSRegularExpression(pattern: #"<title[^>]*>\s*(.*?)\s*</title>"#, options: [.caseInsensitive, .dotMatchesLineSeparators]),
			  let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)),
			  let range = Range(match.range(at: 1), in: text) else { return nil }
		return String(text[range]).replacingOccurrences(of: "<![CDATA[", with: "").replacingOccurrences(of: "]]>", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
	}
}

// MARK: - Subscription management

final class BabelSubscriptionManagementViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {

	private struct Entry {
		let feed: Feed
		let container: Container
		let account: Account
		let location: String
	}

	private let tableView = UITableView(frame: .zero, style: .plain)
	private let emptyLabel = UILabel()
	private var entries = [Entry]()

	override func viewDidLoad() {
		super.viewDidLoad()
		view.backgroundColor = BabelPalette.background
		configureHeader()
		configureTable()
		rebuildEntries()
		NotificationCenter.default.addObserver(self, selector: #selector(rebuildEntries), name: .UnreadCountDidChange, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(rebuildEntries), name: .AccountDidDownloadArticles, object: nil)
	}

	deinit { NotificationCenter.default.removeObserver(self) }

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		rebuildEntries()
	}

	private func configureHeader() {
		let header = UIView()
		header.backgroundColor = BabelPalette.background
		header.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(header)
		let back = UIButton(type: .custom)
		back.tintColor = BabelPalette.ink
		back.setImage(UIImage(systemName: "chevron.left", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)), for: .normal)
		back.addTarget(self, action: #selector(close), for: .touchUpInside)
		back.translatesAutoresizingMaskIntoConstraints = false
		header.addSubview(back)
		let title = UILabel()
		title.text = "管理订阅源"
		title.font = .systemFont(ofSize: 24, weight: .semibold)
		title.textColor = BabelPalette.ink
		title.translatesAutoresizingMaskIntoConstraints = false
		header.addSubview(title)
		let add = UIButton(type: .custom)
		add.setImage(UIImage(systemName: "plus", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)), for: .normal)
		add.tintColor = BabelPalette.ink
		add.accessibilityLabel = "添加订阅源"
		add.addTarget(self, action: #selector(openAdd), for: .touchUpInside)
		add.translatesAutoresizingMaskIntoConstraints = false
		header.addSubview(add)
		let line = UIView()
		line.backgroundColor = BabelPalette.hairline
		line.translatesAutoresizingMaskIntoConstraints = false
		header.addSubview(line)
		NSLayoutConstraint.activate([
			header.leadingAnchor.constraint(equalTo: view.leadingAnchor), header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			header.topAnchor.constraint(equalTo: view.topAnchor, constant: 59), header.heightAnchor.constraint(equalToConstant: 58),
			back.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 10), back.centerYAnchor.constraint(equalTo: header.topAnchor, constant: 24), back.widthAnchor.constraint(equalToConstant: 44), back.heightAnchor.constraint(equalToConstant: 44),
			title.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 58), title.topAnchor.constraint(equalTo: header.topAnchor, constant: 7),
			add.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -10), add.centerYAnchor.constraint(equalTo: back.centerYAnchor), add.widthAnchor.constraint(equalToConstant: 44), add.heightAnchor.constraint(equalToConstant: 44),
			line.leadingAnchor.constraint(equalTo: header.leadingAnchor), line.trailingAnchor.constraint(equalTo: header.trailingAnchor), line.bottomAnchor.constraint(equalTo: header.bottomAnchor), line.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale)
		])
	}

	private func configureTable() {
		tableView.backgroundColor = BabelPalette.background
		tableView.separatorStyle = .none
		tableView.rowHeight = 64
		tableView.estimatedRowHeight = 64
		tableView.dataSource = self
		tableView.delegate = self
		tableView.register(BabelSubscriptionCell.self, forCellReuseIdentifier: BabelSubscriptionCell.reuseIdentifier)
		tableView.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(tableView)
		emptyLabel.text = "还没有订阅源"
		emptyLabel.font = .systemFont(ofSize: 17, weight: .regular)
		emptyLabel.textColor = BabelPalette.mutedInk
		emptyLabel.textAlignment = .center
		tableView.backgroundView = emptyLabel
		NSLayoutConstraint.activate([
			tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
			tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
			tableView.topAnchor.constraint(equalTo: view.topAnchor, constant: 135),
			tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
		])
	}

	@objc private func rebuildEntries() {
		var collected = [Entry]()
		var seen = Set<String>()
		for account in AccountManager.shared.sortedActiveAccounts {
			for folder in (account.folders ?? []).sorted(by: { $0.nameForDisplay.localizedCaseInsensitiveCompare($1.nameForDisplay) == .orderedAscending }) {
				for feed in folder.topLevelFeeds.sorted(by: { $0.nameForDisplay.localizedCaseInsensitiveCompare($1.nameForDisplay) == .orderedAscending }) where seen.insert(feed.feedID).inserted {
					collected.append(Entry(feed: feed, container: folder, account: account, location: "\(account.nameForDisplay) / \(folder.nameForDisplay)"))
				}
			}
			for feed in account.topLevelFeeds.sorted(by: { $0.nameForDisplay.localizedCaseInsensitiveCompare($1.nameForDisplay) == .orderedAscending }) where seen.insert(feed.feedID).inserted {
				collected.append(Entry(feed: feed, container: account, account: account, location: account.nameForDisplay))
			}
		}
		entries = collected.sorted { $0.feed.nameForDisplay.localizedCaseInsensitiveCompare($1.feed.nameForDisplay) == .orderedAscending }
		emptyLabel.isHidden = !entries.isEmpty
		tableView.reloadData()
	}

	func numberOfSections(in tableView: UITableView) -> Int { entries.isEmpty ? 0 : 1 }
	func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { entries.count }
	func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat { 36 }
	func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
		let header = UILabel()
		header.text = ("订阅源  " + String(entries.count)).uppercased()
		header.font = .systemFont(ofSize: 11, weight: .semibold)
		header.textColor = BabelPalette.mutedInk
		return header
	}
	func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		let cell = tableView.dequeueReusableCell(withIdentifier: BabelSubscriptionCell.reuseIdentifier, for: indexPath) as! BabelSubscriptionCell
		let entry = entries[indexPath.row]
		cell.configure(title: entry.feed.nameForDisplay, location: entry.location, unreadCount: entry.feed.unreadCount)
		return cell
	}
	func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
		let entry = entries[indexPath.row]
		let remove = UIContextualAction(style: .destructive, title: "取消订阅") { [weak self] _, _, completion in
			self?.confirmRemove(entry, completion: completion)
		}
		let rename = UIContextualAction(style: .normal, title: "重命名") { [weak self] _, _, completion in
			self?.rename(entry, completion: completion)
		}
		rename.backgroundColor = BabelPalette.mutedInk
		return UISwipeActionsConfiguration(actions: [remove, rename])
	}

	private func confirmRemove(_ entry: Entry, completion: @escaping (Bool) -> Void) {
		let alert = UIAlertController(title: "取消订阅「\(entry.feed.nameForDisplay)」？", message: "已保存的文章不会受影响。", preferredStyle: .actionSheet)
		alert.addAction(UIAlertAction(title: "取消订阅", style: .destructive) { [weak self] _ in
			BatchUpdate.shared.start()
			entry.account.removeFeed(entry.feed, from: entry.container) { result in
				DispatchQueue.main.async {
					BatchUpdate.shared.end()
					switch result {
					case .success: completion(true); self?.rebuildEntries()
					case .failure(let error): completion(false); self?.presentError(error)
					}
				}
			}
		})
		alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completion(false) })
		present(alert, animated: true)
	}

	private func rename(_ entry: Entry, completion: @escaping (Bool) -> Void) {
		let alert = UIAlertController(title: "重命名订阅源", message: entry.location, preferredStyle: .alert)
		alert.addTextField { field in field.text = entry.feed.nameForDisplay; field.autocapitalizationType = .sentences }
		alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completion(false) })
		alert.addAction(UIAlertAction(title: "保存", style: .default) { [weak self] _ in
			let name = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
			guard !name.isEmpty, name != entry.feed.nameForDisplay else { completion(false); return }
			Task { @MainActor [weak self] in
				do {
					try await entry.account.renameFeed(entry.feed, name: name)
					completion(true)
					self?.rebuildEntries()
				} catch {
					completion(false)
					self?.presentError(error)
				}
			}
		})
		present(alert, animated: true)
	}

	@objc private func close() { navigationController?.popViewController(animated: true) }
	@objc private func openAdd() { navigationController?.pushViewController(BabelAddSubscriptionViewController(), animated: true) }
}

private final class BabelSubscriptionCell: UITableViewCell {
	static let reuseIdentifier = "BabelSubscriptionCell"
	private let icon = UIImageView(image: UIImage(systemName: "dot.radiowaves.left.and.right"))
	private let titleLabel = UILabel()
	private let locationLabel = UILabel()
	private let countLabel = UILabel()
	private let line = UIView()

	override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
		super.init(style: style, reuseIdentifier: reuseIdentifier)
		backgroundColor = .clear
		selectedBackgroundView = { let view = UIView(); view.backgroundColor = BabelPalette.raisedBackground; return view }()
		icon.tintColor = BabelPalette.mutedInk
		icon.contentMode = .scaleAspectFit
		icon.translatesAutoresizingMaskIntoConstraints = false
		contentView.addSubview(icon)
		titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
		titleLabel.textColor = BabelPalette.ink
		titleLabel.numberOfLines = 1
		titleLabel.translatesAutoresizingMaskIntoConstraints = false
		contentView.addSubview(titleLabel)
		locationLabel.font = .systemFont(ofSize: 11, weight: .regular)
		locationLabel.textColor = BabelPalette.mutedInk
		locationLabel.numberOfLines = 1
		locationLabel.translatesAutoresizingMaskIntoConstraints = false
		contentView.addSubview(locationLabel)
		countLabel.font = .systemFont(ofSize: 13, weight: .regular)
		countLabel.textColor = BabelPalette.mutedInk
		countLabel.translatesAutoresizingMaskIntoConstraints = false
		contentView.addSubview(countLabel)
		line.backgroundColor = BabelPalette.hairline
		line.translatesAutoresizingMaskIntoConstraints = false
		contentView.addSubview(line)
		NSLayoutConstraint.activate([
			icon.leadingAnchor.constraint(equalTo: contentView.leadingAnchor), icon.centerYAnchor.constraint(equalTo: contentView.centerYAnchor), icon.widthAnchor.constraint(equalToConstant: 22), icon.heightAnchor.constraint(equalToConstant: 22),
			titleLabel.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 12), titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: countLabel.leadingAnchor, constant: -10), titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
			locationLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor), locationLabel.trailingAnchor.constraint(equalTo: countLabel.leadingAnchor, constant: -10), locationLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 3),
			countLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor), countLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
			line.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor), line.trailingAnchor.constraint(equalTo: contentView.trailingAnchor), line.bottomAnchor.constraint(equalTo: contentView.bottomAnchor), line.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale)
		])
	}

	required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
	func configure(title: String, location: String, unreadCount: Int) {
		titleLabel.text = title
		locationLabel.text = location
		countLabel.text = unreadCount > 0 ? unreadCount.formatted() : nil
	}
}
