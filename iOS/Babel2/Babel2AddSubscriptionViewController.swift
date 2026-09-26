import UIKit
import Babel2Core

// 添加订阅页（2026-09-25，用户“按照你的建议来”；ADR-030）。
// Figma 只有首页「+」按钮、没有这一页的设计稿：样式按列表搜索框与设置页行近似（LESSONS 35，已告知用户）。
// 沿用 1.x 发现页用户拍板过的规则：一个搜索框（网址直连 / 关键词并行搜四类）、结果按类别分组可收起、
// 顶部「订阅到」选文件夹（默认顶层、不记住）、点行试读、行尾 ⊕ 订阅 / 勾 = 已订阅、订阅后留在本页。

// MARK: - 接口与数据

/// 添加订阅页读写的全部东西；正式实现在接入层（对接 1.x 发现引擎与账户公开接口），测试用假的实现。
@MainActor
protocol Babel2SubscriptionService: AnyObject {
	/// 按输入搜索：网址直连对应类型，关键词并行搜四类。每组带自己的状态说明（无结果 / 未配置 / 出错）。
	func search(_ query: String) async -> [Babel2DiscoveryGroup]
	var destinations: [Babel2SubscriptionDestination] { get }
	func isSubscribed(_ result: Babel2DiscoveryResult) -> Bool
	/// 订阅到指定位置。成功返回 nil，失败返回给用户看的说明。
	func subscribe(_ result: Babel2DiscoveryResult, to destinationID: String) async -> String?
	/// 取消订阅。成功返回 nil，失败返回说明。
	func unsubscribe(_ result: Babel2DiscoveryResult) async -> String?
	/// 试读页（现成页面，以底部卡片弹出）。页面里的「订阅」按钮回调到这里给的 subscribe。
	func makePreview(_ result: Babel2DiscoveryResult, isBusy: @escaping () -> Bool, subscribe: @escaping (@escaping (String?) -> Void) -> Void) -> UIViewController?
}

enum Babel2DiscoveryKind: String, CaseIterable {
	case website, podcast, youtube, reddit
}

struct Babel2DiscoveryResult: Equatable {
	let kind: Babel2DiscoveryKind
	let title: String
	let subtitle: String?
	let feedURL: String
	let iconURL: URL?
}

struct Babel2DiscoveryGroup: Equatable {
	let kind: Babel2DiscoveryKind
	var results: [Babel2DiscoveryResult]
	/// 这一组没有结果时的说明（无结果 / 未配置 Key / 限流 / 网络错误）。
	var statusMessage: String?
	var isExpanded: Bool
}

struct Babel2SubscriptionDestination: Equatable {
	let id: String
	let title: String
}

// MARK: - 页面

final class Babel2AddSubscriptionViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate {
	private let service: Babel2SubscriptionService
	private let imageProvider: (any ImageProviding)?
	private let tableView = UITableView(frame: .zero, style: .plain)
	private let searchField = UITextField()
	private let statusLabel = UILabel()
	private var groups = [Babel2DiscoveryGroup]()
	private var destinationID: String?
	private var busyURLs = Set<String>()
	private var searchTask: Task<Void, Never>?
	private var isSearching = false
	private var lastQuery = ""

	init(service: Babel2SubscriptionService, imageProvider: (any ImageProviding)? = nil) {
		self.service = service
		self.imageProvider = imageProvider
		super.init(nibName: nil, bundle: nil)
		// 沿用原占位页的路由恢复标识（重启后能回到这一页）
		restorationIdentifier = "babel2.add-subscription"
		// 默认订阅到第一个位置（通常是顶层），不记住上次的选择（1.x 用户决定）
		destinationID = service.destinations.first?.id
	}

	required init?(coder: NSCoder) { nil }

	deinit { searchTask?.cancel() }

	override func viewDidLoad() {
		super.viewDidLoad()
		view.backgroundColor = BabelPalette.background
		let navigation = Babel2SettingsNavigationBar(kind: .back, title: Babel2Localization.text(.addSubscription))
		// 设置页标题仍是 24pt；这一页不属于设置，跟随全 App 收小一档（ADR-033）
		navigation.titleLabel.font = .systemFont(ofSize: Babel2Type.addSubscriptionTitle, weight: .semibold)
		navigation.leadingButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
		navigation.translatesAutoresizingMaskIntoConstraints = false

		let statusBackdrop = UIView()
		statusBackdrop.backgroundColor = BabelPalette.background
		statusBackdrop.translatesAutoresizingMaskIntoConstraints = false

		// 搜索框（顶部，与列表搜索一致）：输入底色、圆角、放大镜
		let box = UIView()
		box.backgroundColor = Babel2SettingsStyle.inputBackground
		box.layer.cornerRadius = 10
		box.layer.cornerCurve = .continuous
		box.translatesAutoresizingMaskIntoConstraints = false
		let glass = UIImageView(image: UIImage(systemName: "magnifyingglass", withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)))
		glass.tintColor = BabelPalette.mutedInk
		glass.contentMode = .scaleAspectFit
		glass.translatesAutoresizingMaskIntoConstraints = false
		searchField.placeholder = Babel2Localization.text(.addSubscriptionPlaceholder)
		searchField.font = Babel2Type.searchField
		searchField.textColor = BabelPalette.ink
		searchField.returnKeyType = .search
		searchField.clearButtonMode = .always
		searchField.autocorrectionType = .no
		searchField.autocapitalizationType = .none
		searchField.keyboardType = .webSearch
		searchField.accessibilityIdentifier = "babel2.add-subscription.field"
		searchField.delegate = self
		searchField.translatesAutoresizingMaskIntoConstraints = false
		box.addSubview(glass)
		box.addSubview(searchField)

		tableView.backgroundColor = BabelPalette.background
		tableView.separatorStyle = .none
		tableView.dataSource = self
		tableView.delegate = self
		tableView.keyboardDismissMode = .onDrag
		tableView.rowHeight = UITableView.automaticDimension
		tableView.estimatedRowHeight = 64
		tableView.sectionHeaderTopPadding = 0
		tableView.accessibilityIdentifier = "babel2.add-subscription.table"
		tableView.register(Babel2DiscoveryResultCell.self, forCellReuseIdentifier: Babel2DiscoveryResultCell.reuseIdentifier)
		tableView.translatesAutoresizingMaskIntoConstraints = false

		statusLabel.font = .systemFont(ofSize: 14, weight: .regular)
		statusLabel.textColor = BabelPalette.mutedInk
		statusLabel.textAlignment = .center
		statusLabel.numberOfLines = 0
		statusLabel.accessibilityIdentifier = "babel2.add-subscription.status"
		statusLabel.translatesAutoresizingMaskIntoConstraints = false

		view.addSubview(tableView)
		view.addSubview(statusLabel)
		view.addSubview(statusBackdrop)
		view.addSubview(navigation)
		view.addSubview(box)
		NSLayoutConstraint.activate([
			statusBackdrop.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			statusBackdrop.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			statusBackdrop.topAnchor.constraint(equalTo: view.topAnchor),
			statusBackdrop.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
			navigation.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			navigation.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			navigation.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
			box.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
			box.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
			box.topAnchor.constraint(equalTo: navigation.bottomAnchor, constant: 12),
			box.heightAnchor.constraint(equalToConstant: 40),
			glass.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 10),
			glass.centerYAnchor.constraint(equalTo: box.centerYAnchor),
			glass.widthAnchor.constraint(equalToConstant: 16),
			glass.heightAnchor.constraint(equalToConstant: 16),
			searchField.leadingAnchor.constraint(equalTo: glass.trailingAnchor, constant: 6),
			searchField.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -6),
			searchField.topAnchor.constraint(equalTo: box.topAnchor),
			searchField.bottomAnchor.constraint(equalTo: box.bottomAnchor),
			tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			tableView.topAnchor.constraint(equalTo: box.bottomAnchor, constant: 8),
			tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
			statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
			statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
			statusLabel.topAnchor.constraint(equalTo: box.bottomAnchor, constant: 140)
		])
		NotificationCenter.default.addObserver(self, selector: #selector(keyboardFrameChanged(_:)), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
		updateStatus()
	}

	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)
		if lastQuery.isEmpty { searchField.becomeFirstResponder() }
	}

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		// 从试读页回来：订阅状态可能变了
		tableView.reloadData()
	}

	@objc private func backTapped() {
		view.endEditing(true)
		_ = (navigationController as? Babel2NavigationController)?.popBabel2(animated: true)
	}

	// MARK: 搜索

	/// 按键盘「搜索」时搜（网址解析与关键词并行搜都要联网，边打边搜会浪费请求与第三方额度）。
	func textFieldShouldReturn(_ textField: UITextField) -> Bool {
		textField.resignFirstResponder()
		runSearch(textField.text ?? "")
		return true
	}

	func runSearch(_ text: String) {
		let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
		searchTask?.cancel()
		lastQuery = query
		groups = []
		isSearching = !query.isEmpty
		tableView.reloadData()
		updateStatus()
		guard !query.isEmpty else { return }
		searchTask = Task { @MainActor [weak self] in
			guard let self else { return }
			let found = await self.service.search(query)
			guard !Task.isCancelled, self.lastQuery == query else { return }
			self.isSearching = false
			self.groups = found
			self.tableView.reloadData()
			self.updateStatus()
		}
	}

	private func updateStatus() {
		if isSearching {
			statusLabel.text = Babel2Localization.text(.searching)
			statusLabel.isHidden = false
		} else if lastQuery.isEmpty {
			statusLabel.text = Babel2Localization.text(.addSubscriptionHint)
			statusLabel.isHidden = false
		} else if groups.isEmpty {
			statusLabel.text = String(format: Babel2Localization.text(.noSearchResults), lastQuery)
			statusLabel.isHidden = false
		} else {
			statusLabel.isHidden = true
		}
		statusLabel.accessibilityValue = isSearching ? "searching" : (statusLabel.isHidden ? "results" : "idle")
	}

	// MARK: 订阅 / 取消订阅

	private func subscribe(_ result: Babel2DiscoveryResult, completion: ((String?) -> Void)? = nil) {
		guard let destinationID, !busyURLs.contains(result.feedURL) else {
			if destinationID == nil { presentMessage(Babel2Localization.text(.noSubscriptionDestination)) }
			completion?(nil)
			return
		}
		busyURLs.insert(result.feedURL)
		tableView.reloadData()
		Task { @MainActor [weak self] in
			guard let self else { return }
			let message = await self.service.subscribe(result, to: destinationID)
			self.busyURLs.remove(result.feedURL)
			self.tableView.reloadData()
			if let completion {
				completion(message)
			} else if let message {
				self.presentMessage(message)
			}
		}
	}

	/// 取消订阅会删掉这个源和它的文章：先确认（用户 2026-09-25 选 A）。
	private func confirmUnsubscribe(_ result: Babel2DiscoveryResult) {
		let alert = UIAlertController(title: Babel2Localization.text(.unsubscribe),
			message: String(format: Babel2Localization.text(.unsubscribeConfirm), result.title), preferredStyle: .alert)
		alert.addAction(UIAlertAction(title: Babel2Localization.text(.cancel), style: .cancel))
		alert.addAction(UIAlertAction(title: Babel2Localization.text(.unsubscribe), style: .destructive) { [weak self] _ in
			self?.performUnsubscribe(result)
		})
		present(alert, animated: true)
	}

	func performUnsubscribe(_ result: Babel2DiscoveryResult) {
		busyURLs.insert(result.feedURL)
		tableView.reloadData()
		Task { @MainActor [weak self] in
			guard let self else { return }
			let message = await self.service.unsubscribe(result)
			self.busyURLs.remove(result.feedURL)
			self.tableView.reloadData()
			if let message { self.presentMessage(message) }
		}
	}

	private func presentMessage(_ message: String) {
		let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
		alert.addAction(UIAlertAction(title: Babel2Localization.text(.ok), style: .default))
		present(alert, animated: true)
	}

	// MARK: 订阅到（文件夹）

	private var destinationTitle: String {
		service.destinations.first { $0.id == destinationID }?.title ?? "—"
	}

	private func chooseDestination(from row: UIView) {
		let destinations = service.destinations
		guard !destinations.isEmpty else { return }
		view.endEditing(true)
		Babel2SettingsPopover.present(options: destinations.map { .init(title: $0.title, isSelected: $0.id == destinationID) }, from: row, in: view) { [weak self] index in
			guard let self, index < destinations.count else { return }
			self.destinationID = destinations[index].id
			self.tableView.reloadSections(IndexSet(integer: 0), with: .none)
		}
	}

	// MARK: 表格：第 0 段「订阅到」，之后每组一段（标题可点，收起 / 展开）

	func numberOfSections(in tableView: UITableView) -> Int { 1 + groups.count }

	func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		guard section > 0 else { return service.destinations.isEmpty ? 0 : 1 }
		let group = groups[section - 1]
		guard group.isExpanded else { return 0 }
		return group.results.isEmpty ? (group.statusMessage == nil ? 0 : 1) : group.results.count
	}

	func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		if indexPath.section == 0 {
			let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
			cell.backgroundColor = .clear
			cell.selectionStyle = .none
			let row = Babel2SettingsSelectRow(title: Babel2Localization.text(.subscribeTo), value: destinationTitle)
			row.accessibilityIdentifier = "babel2.add-subscription.destination"
			row.onTap = { [weak self, weak row] in
				guard let row else { return }
				self?.chooseDestination(from: row)
			}
			row.translatesAutoresizingMaskIntoConstraints = false
			cell.contentView.addSubview(row)
			NSLayoutConstraint.activate([
				row.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 20),
				row.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -20),
				row.topAnchor.constraint(equalTo: cell.contentView.topAnchor),
				row.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor)
			])
			return cell
		}
		let group = groups[indexPath.section - 1]
		if group.results.isEmpty {
			let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
			cell.backgroundColor = .clear
			cell.selectionStyle = .none
			var content = cell.defaultContentConfiguration()
			content.text = group.statusMessage
			content.textProperties.font = .systemFont(ofSize: 13, weight: .regular)
			content.textProperties.color = BabelPalette.mutedInk
			content.textProperties.numberOfLines = 0
			content.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 8, leading: 20, bottom: 12, trailing: 20)
			cell.contentConfiguration = content
			cell.accessibilityIdentifier = "babel2.add-subscription.group-status.\(group.kind.rawValue)"
			return cell
		}
		let result = group.results[indexPath.row]
		let cell = tableView.dequeueReusableCell(withIdentifier: Babel2DiscoveryResultCell.reuseIdentifier, for: indexPath) as! Babel2DiscoveryResultCell
		let state: Babel2DiscoveryResultCell.State = busyURLs.contains(result.feedURL) ? .busy : (service.isSubscribed(result) ? .subscribed : .notSubscribed)
		cell.configure(result: result, state: state, imageProvider: imageProvider)
		cell.onAction = { [weak self] in
			guard let self else { return }
			if self.service.isSubscribed(result) {
				self.confirmUnsubscribe(result)
			} else {
				self.subscribe(result)
			}
		}
		cell.accessibilityIdentifier = "babel2.add-subscription.result.\(result.feedURL)"
		return cell
	}

	func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
		guard section > 0 else { return nil }
		let group = groups[section - 1]
		let header = Babel2DiscoveryGroupHeader(title: Self.title(for: group.kind), count: group.results.count, expanded: group.isExpanded)
		header.accessibilityIdentifier = "babel2.add-subscription.group.\(group.kind.rawValue)"
		header.onTap = { [weak self] in self?.toggleGroup(section - 1) }
		return header
	}

	func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
		section == 0 ? 0 : 40
	}

	func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		tableView.deselectRow(at: indexPath, animated: true)
		guard indexPath.section > 0 else { return }
		let group = groups[indexPath.section - 1]
		guard indexPath.row < group.results.count else { return }
		openPreview(group.results[indexPath.row])
	}

	/// 点行 = 试读（现成页面，底部卡片）。试读页里的「订阅」订到本页当前选的位置。
	private func openPreview(_ result: Babel2DiscoveryResult) {
		guard let preview = service.makePreview(result, isBusy: { [weak self] in
			self?.busyURLs.contains(result.feedURL) ?? false
		}, subscribe: { [weak self] completion in
			guard let self else { completion(nil); return }
			self.subscribe(result, completion: completion)
		}) else { return }
		present(preview, animated: true)
	}

	private func toggleGroup(_ index: Int) {
		guard index < groups.count else { return }
		groups[index].isExpanded.toggle()
		tableView.reloadSections(IndexSet(integer: index + 1), with: .automatic)
	}

	static func title(for kind: Babel2DiscoveryKind) -> String {
		switch kind {
		case .website: return Babel2Localization.text(.discoveryWebsites)
		case .podcast: return Babel2Localization.text(.discoveryPodcasts)
		case .youtube: return "YouTube"
		case .reddit: return "Reddit"
		}
	}

	@objc private func keyboardFrameChanged(_ notification: Notification) {
		guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect, tableView.window != nil else { return }
		let overlap = max(0, tableView.bounds.maxY - tableView.convert(frame, from: nil).minY)
		tableView.contentInset.bottom = overlap
		tableView.verticalScrollIndicatorInsets.bottom = overlap
	}

	// MARK: 仅供自动化测试

	var groupsForTesting: [Babel2DiscoveryGroup] { groups }
	var destinationIDForTesting: String? { destinationID }
	var statusTextForTesting: String? { statusLabel.isHidden ? nil : statusLabel.text }
	func subscribeForTesting(_ result: Babel2DiscoveryResult) { subscribe(result) }
	func toggleGroupForTesting(_ index: Int) { toggleGroup(index) }
	var searchFieldForTesting: UITextField { searchField }
	var tableViewForTesting: UITableView { tableView }
}

// MARK: - 分组标题（点按收起 / 展开）

private final class Babel2DiscoveryGroupHeader: UIControl {
	var onTap: (() -> Void)?

	init(title: String, count: Int, expanded: Bool) {
		super.init(frame: .zero)
		backgroundColor = BabelPalette.background
		let label = UILabel()
		label.text = count > 0 ? "\(title) · \(count)" : title
		label.font = Babel2SettingsStyle.sectionHeaderFont
		label.textColor = Babel2SettingsStyle.secondaryText
		let chevron = UIImageView(image: UIImage(named: "Babel2SettingsChevronDown"))
		chevron.tintColor = Babel2SettingsStyle.secondaryText
		chevron.transform = expanded ? .identity : CGAffineTransform(rotationAngle: -.pi / 2)
		for view in [label, chevron] as [UIView] {
			view.isUserInteractionEnabled = false
			view.translatesAutoresizingMaskIntoConstraints = false
			addSubview(view)
		}
		NSLayoutConstraint.activate([
			label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
			label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
			chevron.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 4),
			chevron.centerYAnchor.constraint(equalTo: label.centerYAnchor),
			chevron.widthAnchor.constraint(equalToConstant: 14),
			chevron.heightAnchor.constraint(equalToConstant: 14)
		])
		isAccessibilityElement = true
		accessibilityLabel = label.text
		accessibilityTraits = .header
		accessibilityValue = expanded ? "expanded" : "collapsed"
		addTarget(self, action: #selector(tapped), for: .touchUpInside)
	}

	required init?(coder: NSCoder) { nil }

	@objc private func tapped() { onTap?() }
}

// MARK: - 结果行

/// 左侧 36pt 图标（取不到时显示类别符号）、标题（16 半粗）+ 副标题（13 灰，最多 2 行），
/// 行尾按钮：⊕ 订阅 / 灰色勾 = 已订阅（再点取消，先确认）/ 转圈 = 处理中。行间无分隔线。
final class Babel2DiscoveryResultCell: UITableViewCell {
	static let reuseIdentifier = "Babel2DiscoveryResultCell"

	enum State { case notSubscribed, subscribed, busy }

	var onAction: (() -> Void)?
	private let iconView = UIImageView()
	private let titleLabel = UILabel()
	private let subtitleLabel = UILabel()
	let actionButton = UIButton(type: .system)
	private let spinner = UIActivityIndicatorView(style: .medium)
	private var iconTask: Task<Void, Never>?
	private(set) var stateForTesting: State = .notSubscribed

	override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
		super.init(style: style, reuseIdentifier: reuseIdentifier)
		backgroundColor = .clear
		iconView.contentMode = .scaleAspectFill
		iconView.clipsToBounds = true
		iconView.layer.cornerRadius = 8
		iconView.layer.cornerCurve = .continuous
		iconView.tintColor = BabelPalette.mutedInk
		titleLabel.font = Babel2Type.resultTitle
		titleLabel.textColor = BabelPalette.ink
		titleLabel.numberOfLines = 2
		subtitleLabel.font = Babel2Type.resultSubtitle
		subtitleLabel.textColor = BabelPalette.tertiaryInk
		subtitleLabel.numberOfLines = 2
		actionButton.tintColor = BabelPalette.mutedInk
		actionButton.accessibilityIdentifier = "babel2.add-subscription.action"
		actionButton.addTarget(self, action: #selector(actionTapped), for: .touchUpInside)
		spinner.color = BabelPalette.mutedInk
		spinner.hidesWhenStopped = true
		let labels = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
		labels.axis = .vertical
		labels.spacing = 2
		for view in [iconView, labels, actionButton, spinner] as [UIView] {
			view.translatesAutoresizingMaskIntoConstraints = false
			contentView.addSubview(view)
		}
		NSLayoutConstraint.activate([
			iconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
			iconView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
			iconView.widthAnchor.constraint(equalToConstant: 36),
			iconView.heightAnchor.constraint(equalToConstant: 36),
			contentView.bottomAnchor.constraint(greaterThanOrEqualTo: iconView.bottomAnchor, constant: 12),
			labels.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
			labels.trailingAnchor.constraint(equalTo: actionButton.leadingAnchor, constant: -8),
			labels.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
			contentView.bottomAnchor.constraint(greaterThanOrEqualTo: labels.bottomAnchor, constant: 12),
			actionButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -10),
			actionButton.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),
			actionButton.widthAnchor.constraint(equalToConstant: 44),
			actionButton.heightAnchor.constraint(equalToConstant: 44),
			spinner.centerXAnchor.constraint(equalTo: actionButton.centerXAnchor),
			spinner.centerYAnchor.constraint(equalTo: actionButton.centerYAnchor)
		])
	}

	required init?(coder: NSCoder) { nil }

	override func prepareForReuse() {
		super.prepareForReuse()
		iconTask?.cancel()
		iconTask = nil
		iconView.image = nil
	}

	func configure(result: Babel2DiscoveryResult, state: State, imageProvider: (any ImageProviding)?) {
		titleLabel.text = result.title
		subtitleLabel.text = result.subtitle ?? result.feedURL
		stateForTesting = state
		let symbol: String
		switch state {
		case .notSubscribed: symbol = "plus.circle"
		case .subscribed: symbol = "checkmark.circle.fill"
		case .busy: symbol = ""
		}
		actionButton.setImage(symbol.isEmpty ? nil : UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .regular)), for: .normal)
		actionButton.isEnabled = state != .busy
		actionButton.accessibilityLabel = Babel2Localization.text(state == .subscribed ? .unsubscribe : .subscribe)
		if state == .busy { spinner.startAnimating() } else { spinner.stopAnimating() }
		accessibilityLabel = [result.title, result.subtitle].compactMap { $0 }.joined(separator: ", ")

		// 图标：先显示类别符号，取到网络图标再替换
		iconView.image = UIImage(systemName: Self.symbol(for: result.kind), withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .regular))
		iconView.contentMode = .center
		iconView.backgroundColor = Babel2SettingsStyle.inputBackground
		iconTask?.cancel()
		guard let url = result.iconURL, let imageProvider else { return }
		iconTask = Task { @MainActor [weak self] in
			guard let data = try? await imageProvider.imageData(for: url), let image = UIImage(data: data),
				!Task.isCancelled, let self else { return }
			self.iconView.image = image
			self.iconView.contentMode = .scaleAspectFill
			self.iconView.backgroundColor = .clear
		}
	}

	private static func symbol(for kind: Babel2DiscoveryKind) -> String {
		switch kind {
		case .website: return "globe"
		case .podcast: return "mic"
		case .youtube: return "play.rectangle"
		case .reddit: return "bubble.left.and.bubble.right"
		}
	}

	@objc private func actionTapped() { onAction?() }
}
