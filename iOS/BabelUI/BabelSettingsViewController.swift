//
//  BabelSettingsViewController.swift
//  NetNewsWire-iOS
//
//  Runtime implementation of the Settings IA designed in Figma.
//

import UIKit
import SwiftUI
import UniformTypeIdentifiers
import RSCore
import Account
import ErrorLog
import ActivityLog

enum BabelSettingsCategory: CaseIterable {
    case accounts
    case subscriptions
    case timeline
    case reader
    case translation
    case appearance
    case notifications
    case support

    var title: String {
        switch self {
        case .accounts: "账户与同步"
        case .subscriptions: "订阅与发现"
        case .timeline: "文章列表"
        case .reader: "阅读器"
        case .translation: "翻译"
        case .appearance: "外观与语言"
        case .notifications: "通知"
        case .support: "支持与诊断"
        }
    }

    var detail: String {
        switch self {
        case .accounts: "账户、同步状态与服务连接"
        case .subscriptions: "导入导出订阅与发现服务"
        case .timeline: "排序、分组与已读行为"
        case .reader: "主题、链接与网页能力"
        case .translation: "模型、API 与翻译服务"
        case .appearance: "配色、强调色与界面语言"
        case .notifications: "系统通知权限与入口"
        case .support: "日志、统计、帮助与关于"
        }
    }

    var iconAssetName: String? {
        switch self {
        case .accounts: "BabelSettingsAccounts"
        case .subscriptions: "BabelSettingsSubscriptions"
        case .timeline: "BabelSettingsTimeline"
        case .reader: "BabelSettingsReader"
        case .translation: nil
        case .appearance: "BabelSettingsAppearance"
        case .notifications: "BabelSettingsNotifications"
        case .support: "BabelSettingsSupport"
        }
    }
}

final class BabelSettingsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private let tableView = UITableView(frame: .zero, style: .plain)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = BabelPalette.background
        configureNavigation(title: "设置", isRoot: true)

        tableView.backgroundColor = BabelPalette.background
        tableView.separatorStyle = .none
        tableView.contentInsetAdjustmentBehavior = .never
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 56
        tableView.estimatedRowHeight = 56
        tableView.register(BabelSettingsCategoryCell.self, forCellReuseIdentifier: BabelSettingsCategoryCell.reuseIdentifier)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            tableView.topAnchor.constraint(equalTo: view.topAnchor, constant: 117),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func configureNavigation(title: String, isRoot: Bool) {
        let navigation = BabelSettingsNavigationView(title: title, isRoot: isRoot)
        navigation.onClose = { [weak self] in self?.navigationController?.popViewController(animated: true) }
        navigation.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(navigation)
        NSLayoutConstraint.activate([
            navigation.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            navigation.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            navigation.topAnchor.constraint(equalTo: view.topAnchor, constant: 59),
            navigation.heightAnchor.constraint(equalToConstant: 58)
        ])
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { BabelSettingsCategory.allCases.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let category = BabelSettingsCategory.allCases[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: BabelSettingsCategoryCell.reuseIdentifier, for: indexPath) as! BabelSettingsCategoryCell
        cell.configure(category: category)
        cell.accessibilityIdentifier = "babel.settings.category.\(category.title)"
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        navigationController?.pushViewController(BabelSettingsCategoryViewController(category: BabelSettingsCategory.allCases[indexPath.row]), animated: true)
    }
}

final class BabelSettingsCategoryViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, UIDocumentPickerDelegate {
    fileprivate enum RowStyle { case disclosure, value, toggle, action, note }
    fileprivate struct Row {
        let title: String
        let detail: String?
        let style: RowStyle
        let value: String?
        let isOn: Bool
    }

    private let category: BabelSettingsCategory
    private let tableView = UITableView(frame: .zero, style: .plain)
    private var selectedOPMLAccount: Account?

    init(category: BabelSettingsCategory) {
        self.category = category
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = BabelPalette.background
        let navigation = BabelSettingsNavigationView(title: category.title, isRoot: false)
        navigation.onClose = { [weak self] in self?.navigationController?.popViewController(animated: true) }
        navigation.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(navigation)

        tableView.backgroundColor = BabelPalette.background
        tableView.separatorStyle = .none
        tableView.contentInsetAdjustmentBehavior = .never
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 56
        tableView.register(BabelSettingsValueCell.self, forCellReuseIdentifier: BabelSettingsValueCell.reuseIdentifier)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            navigation.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            navigation.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            navigation.topAnchor.constraint(equalTo: view.topAnchor, constant: 59),
            navigation.heightAnchor.constraint(equalToConstant: 58),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            tableView.topAnchor.constraint(equalTo: view.topAnchor, constant: 117),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.reloadData()
    }

    private var sections: [(title: String, rows: [Row])] {
        switch category {
        case .accounts:
            let accounts = AccountManager.shared.sortedAccounts.map { Row(title: $0.nameForDisplay, detail: nil, style: .disclosure, value: nil, isOn: false) }
            return [
                ("账户", accounts + [Row(title: "添加账户", detail: nil, style: .action, value: nil, isOn: false)]),
                ("同步", [Row(title: "同步未读文章内容", detail: "在已连接账户之间保留离线可读内容", style: .toggle, value: nil, isOn: AccountManager.shared.syncArticleContentForUnreadArticles)])
            ]
        case .subscriptions:
            return [
                ("订阅", [
                    Row(title: "导入订阅", detail: nil, style: .disclosure, value: nil, isOn: false),
                    Row(title: "导出订阅", detail: nil, style: .disclosure, value: nil, isOn: false),
                    Row(title: "添加 Babel 新闻源", detail: nil, style: .action, value: nil, isOn: false)
                ]),
                ("发现服务", [Row(title: "订阅发现 API Key", detail: nil, style: .disclosure, value: FeedDiscoveryKeychain.configuredServiceCountDescription, isOn: false)])
            ]
        case .timeline:
            return [
                ("排序与分组", [
                    Row(title: "排序", detail: nil, style: .value, value: AppDefaults.shared.timelineSortDirection == .orderedAscending ? "从旧到新" : "从新到旧", isOn: false),
                    Row(title: "按订阅源分组", detail: nil, style: .toggle, value: nil, isOn: AppDefaults.shared.timelineGroupByFeed)
                ]),
                ("已读行为", [
                    Row(title: "刷新时清除已读文章", detail: nil, style: .toggle, value: nil, isOn: AppDefaults.shared.refreshClearsReadArticles),
                    Row(title: "全部标为已读前确认", detail: nil, style: .toggle, value: nil, isOn: AppDefaults.shared.confirmMarkAllAsRead)
                ])
            ]
        case .reader:
            return [("阅读体验", [
                Row(title: "文章主题", detail: nil, style: .disclosure, value: ArticleThemesManager.shared.currentTheme.name, isOn: false),
                Row(title: "在 Babel 中打开链接", detail: nil, style: .toggle, value: nil, isOn: !AppDefaults.shared.useSystemBrowser),
                Row(title: "启用 JavaScript", detail: nil, style: .toggle, value: nil, isOn: AppDefaults.shared.isArticleContentJavascriptEnabled),
                Row(title: "启用全屏文章", detail: nil, style: .toggle, value: nil, isOn: AppDefaults.shared.articleFullscreenAvailable)
            ])]
        case .translation:
            return [("翻译服务", [
                Row(title: "翻译模型", detail: nil, style: .disclosure, value: TranslationConfigStore.displayName(for: TranslationConfigStore.selectedModel), isOn: false),
                Row(title: "翻译 API Key", detail: nil, style: .disclosure, value: TranslationConfigStore.isFullyConfigured ? "已设置" : "未设置", isOn: false)
            ])]
        case .appearance:
            return [("界面", [
                Row(title: "颜色模式", detail: nil, style: .value, value: AppDefaults.userInterfaceColorPalette.description, isOn: false),
                Row(title: "强调色", detail: nil, style: .value, value: NNWAccentPalette.choice.displayName, isOn: false),
                Row(title: "界面语言", detail: nil, style: .disclosure, value: AppLanguageController.currentDisplayName, isOn: false)
            ])]
        case .notifications:
            return [("系统通知", [
                Row(title: "打开系统通知设置", detail: "通知权限由 iOS 管理。订阅源的通知仍在对应账户或订阅源详情中配置。", style: .disclosure, value: nil, isOn: false)
            ])]
        case .support:
            return [
                ("诊断", ["错误日志", "活动日志", "账户统计", "恐龙", "iCloud 存储统计"].map { Row(title: $0, detail: nil, style: .disclosure, value: nil, isOn: false) }),
                ("帮助与关于", ["使用帮助", "社区论坛", "版本说明", "问题追踪", "关于 Babel"].map { Row(title: $0, detail: nil, style: .disclosure, value: nil, isOn: false) })
            ]
        }
    }

    func numberOfSections(in tableView: UITableView) -> Int { sections.count }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { sections[section].rows.count }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        let row = sections[indexPath.section].rows[indexPath.row]
        return row.detail == nil ? 56 : UITableView.automaticDimension
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { sections[section].title }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat { section == 0 ? 44 : 48 }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let label = UILabel()
        label.text = sections[section].title.uppercased()
        label.font = .systemFont(ofSize: 10, weight: .semibold)
        label.textColor = BabelPalette.tertiaryInk
        label.translatesAutoresizingMaskIntoConstraints = false
        let container = UIView()
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8)
        ])
        return container
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let row = sections[indexPath.section].rows[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: BabelSettingsValueCell.reuseIdentifier, for: indexPath) as! BabelSettingsValueCell
        cell.configure(row: row)
        cell.onToggle = { [weak self] isOn in self?.setToggle(isOn, at: indexPath) }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let row = sections[indexPath.section].rows[indexPath.row]
        guard row.style != .toggle && row.style != .note else { return }
        performAction(at: indexPath)
    }

    private func setToggle(_ isOn: Bool, at indexPath: IndexPath) {
        switch category {
        case .accounts where indexPath.section == 1:
            AccountManager.shared.syncArticleContentForUnreadArticles = isOn
        case .timeline:
            if indexPath.section == 0 { AppDefaults.shared.timelineGroupByFeed = isOn }
            else if indexPath.row == 0 { AppDefaults.shared.refreshClearsReadArticles = isOn }
            else { AppDefaults.shared.confirmMarkAllAsRead = isOn }
        case .reader:
            switch indexPath.row {
            case 1: AppDefaults.shared.useSystemBrowser = !isOn
            case 2: AppDefaults.shared.isArticleContentJavascriptEnabled = isOn
            case 3: AppDefaults.shared.articleFullscreenAvailable = isOn
            default: break
            }
        default: break
        }
        tableView.reloadRows(at: [indexPath], with: .none)
    }

    private func performAction(at indexPath: IndexPath) {
        switch category {
        case .accounts:
            let accounts = AccountManager.shared.sortedAccounts
            if indexPath.section == 0, indexPath.row < accounts.count {
                let inspector = UIStoryboard.inspector.instantiateController(ofType: AccountInspectorViewController.self)
                inspector.account = accounts[indexPath.row]
                navigationController?.pushViewController(inspector, animated: true)
            } else if indexPath.section == 0 {
                navigationController?.pushViewController(UIStoryboard.settings.instantiateController(ofType: AddAccountViewController.self), animated: true)
            }
        case .subscriptions:
            if indexPath.section == 0 {
                switch indexPath.row {
                case 0: beginOPMLImport()
                case 1: beginOPMLExport()
                case 2: navigationController?.pushViewController(BabelAddSubscriptionViewController(), animated: true)
                default: break
                }
            } else {
                navigationController?.pushViewController(DiscoveryAPIKeysViewController(style: .insetGrouped), animated: true)
            }
        case .timeline:
            if indexPath.section == 0, indexPath.row == 0 { chooseTimelineOrder() }
        case .reader:
            if indexPath.row == 0 {
                navigationController?.pushViewController(UIStoryboard.settings.instantiateController(ofType: ArticleThemesTableViewController.self), animated: true)
            }
        case .translation:
            if indexPath.row == 0 {
                navigationController?.pushViewController(TranslationModelPickerViewController(style: .insetGrouped), animated: true)
            } else {
                navigationController?.pushViewController(TranslationAPIKeyViewController(style: .insetGrouped), animated: true)
            }
        case .appearance:
            switch indexPath.row {
            case 0: chooseColorPalette()
            case 1: chooseAccentColor()
            case 2: navigationController?.pushViewController(AppLanguagePickerViewController(style: .insetGrouped), animated: true)
            default: break
            }
        case .notifications:
            UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
        case .support:
            openSupportDestination(at: indexPath)
        }
    }

    private func chooseTimelineOrder() {
        let alert = UIAlertController(title: "排序", message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "从新到旧", style: .default) { [weak self] _ in
            AppDefaults.shared.timelineSortDirection = .orderedDescending
            self?.tableView.reloadData()
        })
        alert.addAction(UIAlertAction(title: "从旧到新", style: .default) { [weak self] _ in
            AppDefaults.shared.timelineSortDirection = .orderedAscending
            self?.tableView.reloadData()
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(alert, animated: true)
    }

    private func chooseColorPalette() {
        let alert = UIAlertController(title: "颜色模式", message: nil, preferredStyle: .actionSheet)
        for palette in UserInterfaceColorPalette.allCases {
            alert.addAction(UIAlertAction(title: palette.description, style: .default) { [weak self] _ in
                AppDefaults.userInterfaceColorPalette = palette
                self?.tableView.reloadData()
            })
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(alert, animated: true)
    }

    private func chooseAccentColor() {
        let alert = UIAlertController(title: "强调色", message: nil, preferredStyle: .actionSheet)
        for choice in NNWAccentPalette.Choice.allCases {
            alert.addAction(UIAlertAction(title: choice.displayName, style: .default) { [weak self] _ in
                NNWAccentPalette.setChoice(choice)
                self?.tableView.reloadData()
            })
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(alert, animated: true)
    }

    private func beginOPMLImport() {
        chooseAccount(title: "导入到") { [weak self] account in
            self?.selectedOPMLAccount = account
            let contentTypes = [UTType.xml, UTType(filenameExtension: "opml")].compactMap { $0 }
            let picker = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes, asCopy: true)
            picker.delegate = self
            picker.modalPresentationStyle = .formSheet
            self?.present(picker, animated: true)
        }
    }

    private func beginOPMLExport() {
        chooseAccount(title: "导出") { [weak self] account in
            guard let self else { return }
            let filename = "\(account.nameForDisplay).opml"
            let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
            do {
                let opml = OPMLExporter.OPMLString(with: account, title: account.nameForDisplay)
                try opml.write(to: fileURL, atomically: true, encoding: .utf8)
                self.present(UIDocumentPickerViewController(forExporting: [fileURL]), animated: true)
            } catch {
                self.presentError(message: error.localizedDescription)
            }
        }
    }

    private func chooseAccount(title: String, completion: @escaping (Account) -> Void) {
        let accounts = AccountManager.shared.sortedAccounts
        guard let first = accounts.first else {
            presentError(message: "还没有可用于订阅管理的账户。")
            return
        }
        guard accounts.count > 1 else { completion(first); return }
        let alert = UIAlertController(title: title, message: "选择账户", preferredStyle: .actionSheet)
        for account in accounts {
            alert.addAction(UIAlertAction(title: account.nameForDisplay, style: .default) { _ in completion(account) })
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(alert, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first, let account = selectedOPMLAccount else { return }
        account.importOPML(url) { [weak self] result in
            DispatchQueue.main.async {
                if case .failure(let error) = result { self?.presentError(message: error.localizedDescription) }
            }
        }
    }

    private func openSupportDestination(at indexPath: IndexPath) {
        if indexPath.section == 0 {
            let controller: UIViewController?
            switch indexPath.row {
            case 0: controller = UIHostingController(rootView: ErrorLogView())
            case 1: controller = UIHostingController(rootView: ActivityLogView())
            case 2: controller = UIHostingController(rootView: AccountStatsView())
            case 3: controller = UIHostingController(rootView: DinosaursView(dismissAndPresent: { _ in }))
            case 4: controller = UIHostingController(rootView: CloudKitStatsView())
            default: controller = nil
            }
            if let controller { navigationController?.pushViewController(controller, animated: true) }
            return
        }
        let urls = [HelpURL.helpHome.rawValue, HelpURL.discourse.rawValue, HelpURL.releaseNotes.rawValue, HelpURL.bugTracker.rawValue]
        if indexPath.row < urls.count, let url = URL(string: urls[indexPath.row]) {
            UIApplication.shared.open(url)
        } else {
            navigationController?.pushViewController(UIHostingController(rootView: AboutView()), animated: true)
        }
    }

    private func presentError(message: String) {
        let alert = UIAlertController(title: "无法完成操作", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default))
        present(alert, animated: true)
    }
}

private final class BabelSettingsNavigationView: UIView {
    var onClose: (() -> Void)?

    init(title: String, isRoot: Bool) {
        super.init(frame: .zero)
        backgroundColor = BabelPalette.background
        let button = UIButton(type: .custom)
        button.setImage(UIImage(systemName: isRoot ? "xmark" : "chevron.left", withConfiguration: UIImage.SymbolConfiguration(pointSize: isRoot ? 18 : 20, weight: .regular)), for: .normal)
        button.tintColor = BabelPalette.ink
        button.accessibilityLabel = isRoot ? "Close Settings" : "Back"
        button.addTarget(self, action: #selector(close), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        addSubview(button)

        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 24, weight: .semibold)
        label.textColor = BabelPalette.ink
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        let rule = UIView()
        rule.backgroundColor = BabelPalette.hairline
        rule.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rule)
        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            button.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -6),
            button.widthAnchor.constraint(equalToConstant: 44), button.heightAnchor.constraint(equalToConstant: 44),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 58),
            label.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            rule.leadingAnchor.constraint(equalTo: leadingAnchor), rule.trailingAnchor.constraint(equalTo: trailingAnchor),
            rule.bottomAnchor.constraint(equalTo: bottomAnchor), rule.heightAnchor.constraint(equalToConstant: 0.5)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func close() { onClose?() }
}

private final class BabelSettingsCategoryCell: UITableViewCell {
    static let reuseIdentifier = "BabelSettingsCategoryCell"
    private let artwork = UIImageView()
    private let translationMark = UILabel()
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let chevron = UIImageView(image: UIImage(systemName: "chevron.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)))

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        let selection = UIView(); selection.backgroundColor = BabelPalette.raisedBackground; selection.layer.cornerRadius = 10; selectedBackgroundView = selection
        artwork.contentMode = .scaleAspectFit
        translationMark.text = "译"; translationMark.font = .systemFont(ofSize: 20, weight: .semibold); translationMark.textColor = BabelPalette.mutedInk; translationMark.textAlignment = .center
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold); titleLabel.textColor = BabelPalette.ink
        detailLabel.font = .systemFont(ofSize: 11, weight: .regular); detailLabel.textColor = BabelPalette.mutedInk
        chevron.tintColor = BabelPalette.mutedInk; chevron.contentMode = .scaleAspectFit
        [artwork, translationMark, titleLabel, detailLabel, chevron].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; contentView.addSubview($0) }
        NSLayoutConstraint.activate([
            artwork.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 5), artwork.centerYAnchor.constraint(equalTo: contentView.centerYAnchor), artwork.widthAnchor.constraint(equalToConstant: 28), artwork.heightAnchor.constraint(equalToConstant: 28),
            translationMark.leadingAnchor.constraint(equalTo: artwork.leadingAnchor), translationMark.trailingAnchor.constraint(equalTo: artwork.trailingAnchor), translationMark.centerYAnchor.constraint(equalTo: artwork.centerYAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 44), titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8), titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: chevron.leadingAnchor, constant: -12),
            detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor), detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2), detailLabel.trailingAnchor.constraint(lessThanOrEqualTo: chevron.leadingAnchor, constant: -12),
            chevron.trailingAnchor.constraint(equalTo: contentView.trailingAnchor), chevron.centerYAnchor.constraint(equalTo: contentView.centerYAnchor), chevron.widthAnchor.constraint(equalToConstant: 18), chevron.heightAnchor.constraint(equalToConstant: 18)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(category: BabelSettingsCategory) {
        titleLabel.text = category.title
        detailLabel.text = category.detail
        artwork.image = category.iconAssetName.flatMap(UIImage.init(named:))
        artwork.isHidden = category.iconAssetName == nil
        translationMark.isHidden = category != .translation
    }
}

private final class BabelSettingsValueCell: UITableViewCell {
    static let reuseIdentifier = "BabelSettingsValueCell"
    var onToggle: ((Bool) -> Void)?
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let valueLabel = UILabel()
    private let chevron = UIImageView(image: UIImage(systemName: "chevron.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)))
    private let toggle = BabelSettingsToggleControl()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        let selection = UIView(); selection.backgroundColor = BabelPalette.raisedBackground; selection.layer.cornerRadius = 10; selectedBackgroundView = selection
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold); titleLabel.textColor = BabelPalette.ink
        detailLabel.font = .systemFont(ofSize: 11, weight: .regular); detailLabel.textColor = BabelPalette.mutedInk; detailLabel.numberOfLines = 0
        valueLabel.font = .systemFont(ofSize: 13, weight: .regular); valueLabel.textColor = BabelPalette.mutedInk; valueLabel.textAlignment = .right
        chevron.tintColor = BabelPalette.mutedInk; chevron.contentMode = .scaleAspectFit
        toggle.addTarget(self, action: #selector(toggleChanged), for: .valueChanged)
        [titleLabel, detailLabel, valueLabel, chevron, toggle].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; contentView.addSubview($0) }
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor), titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: valueLabel.leadingAnchor, constant: -10),
            detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor), detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2), detailLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -30), detailLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -10),
            valueLabel.trailingAnchor.constraint(equalTo: chevron.leadingAnchor, constant: -4), valueLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor), valueLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 132),
            chevron.trailingAnchor.constraint(equalTo: contentView.trailingAnchor), chevron.centerYAnchor.constraint(equalTo: contentView.centerYAnchor), chevron.widthAnchor.constraint(equalToConstant: 18), chevron.heightAnchor.constraint(equalToConstant: 18),
            // Keep the visual switch inside the same right inset as value rows;
            // the control itself still has a 44 pt hit target.
            toggle.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8), toggle.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            toggle.widthAnchor.constraint(equalToConstant: BabelChromeMetrics.minimumHitTarget), toggle.heightAnchor.constraint(equalToConstant: BabelChromeMetrics.minimumHitTarget)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(row: BabelSettingsCategoryViewController.Row) {
        titleLabel.text = row.title
        detailLabel.text = row.detail
        detailLabel.isHidden = row.detail == nil
        valueLabel.text = row.value
        valueLabel.isHidden = row.value == nil
        let isToggle = row.style == .toggle
        toggle.isHidden = !isToggle
        toggle.isOn = row.isOn
        toggle.accessibilityLabel = row.title
        chevron.isHidden = isToggle || row.style == .note
    }

    @objc private func toggleChanged() { onToggle?(toggle.isOn) }
}

/// A compact, line-based setting switch. UIKit's stock UISwitch is too large
/// for Babel's deliberately quiet settings rows and ignores the visual scale
/// used by the rest of the app chrome.
private final class BabelSettingsToggleControl: UIControl {
    private let track = UIView()
    private let thumb = UIView()
    private var thumbLeadingConstraint: NSLayoutConstraint!

    var isOn: Bool = false {
        didSet { updateAppearance(animated: window != nil) }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = true
        accessibilityTraits = [.button]

        track.isUserInteractionEnabled = false
        track.layer.cornerRadius = 12
        track.layer.borderWidth = 1.5
        track.translatesAutoresizingMaskIntoConstraints = false
        addSubview(track)

        thumb.isUserInteractionEnabled = false
        thumb.layer.cornerRadius = 10
        thumb.translatesAutoresizingMaskIntoConstraints = false
        track.addSubview(thumb)

        thumbLeadingConstraint = thumb.leadingAnchor.constraint(equalTo: track.leadingAnchor, constant: 2)
        NSLayoutConstraint.activate([
            track.centerXAnchor.constraint(equalTo: centerXAnchor),
            track.centerYAnchor.constraint(equalTo: centerYAnchor),
            track.widthAnchor.constraint(equalToConstant: 42),
            track.heightAnchor.constraint(equalToConstant: 24),
            thumbLeadingConstraint,
            thumb.centerYAnchor.constraint(equalTo: track.centerYAnchor),
            thumb.widthAnchor.constraint(equalToConstant: 20),
            thumb.heightAnchor.constraint(equalToConstant: 20)
        ])
        updateAppearance(animated: false)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(accentDidChange),
            name: NNWAccentPalette.didChangeNotification,
            object: nil
        )
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (control: BabelSettingsToggleControl, _) in
            control.updateAppearance(animated: false)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func accentDidChange() {
        updateAppearance(animated: false)
    }

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        guard isEnabled else { return false }
        alpha = 0.72
        return true
    }

    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        alpha = 1
        guard let touch, bounds.contains(touch.location(in: self)) else { return }
        isOn.toggle()
        sendActions(for: .valueChanged)
    }

    override func cancelTracking(with event: UIEvent?) {
        alpha = 1
    }

    private func updateAppearance(animated: Bool) {
        thumbLeadingConstraint?.constant = isOn ? 20 : 2
        track.backgroundColor = isOn ? BabelPalette.themeAccent : BabelPalette.raisedBackground
        track.layer.borderColor = (isOn ? BabelPalette.themeAccent : BabelPalette.hairline).resolvedColor(with: traitCollection).cgColor
        thumb.backgroundColor = BabelPalette.background
        accessibilityValue = isOn ? "开启" : "关闭"
        if isOn {
            accessibilityTraits.insert(.selected)
        } else {
            accessibilityTraits.remove(.selected)
        }

        let layout = { self.layoutIfNeeded() }
        if animated {
            UIView.animate(
                withDuration: BabelChromeMetrics.selectionDuration,
                delay: 0,
                options: [.curveEaseInOut, .beginFromCurrentState, .allowUserInteraction],
                animations: layout
            )
        } else {
            layout()
        }
    }
}

private extension FeedDiscoveryKeychain {
    static var configuredServiceCountDescription: String {
        let count = [hasRedditCredentials, hasYouTubeCredentials].filter { $0 }.count
        return count == 0 ? "未设置" : "已设置 \(count)/2"
    }
}
