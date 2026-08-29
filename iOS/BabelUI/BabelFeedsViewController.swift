//
//  BabelFeedsViewController.swift
//  NetNewsWire
//
//  Reeder Classic 参考中的 Feeds / Folders 层。只读展示。
//

import UIKit
import Account
import Images
import ErrorLog

final class BabelFeedsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {

    private enum Row {
        case unread
        case sectionSpacing
        case foldersHeader
        case folder(Folder)
        case feed(Feed)
    }

    var onSelectUnread: (() -> Void)?
    var onSelectSaved: (() -> Void)?
    var onSelectFeed: ((Feed) -> Void)?
    var onSelectFolder: ((Folder) -> Void)?
    var onOpenGenesisV2: (() -> Void)?
    var onOpenSubscribe: (() -> Void)?
    private var rows = [Row]()
    private var collapsedFolders = Set<String>()
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let emptyLabel = UILabel()
    private let bottomBar = UIView()
    private let customHeader = UIView()
    private let interfaceSwitcher = UISegmentedControl(items: ["Babel", "旧版"])
    private var didApplyInitialOffset = false

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Feeds"
        navigationItem.largeTitleDisplayMode = .never
        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        timeFormatter.dateFormat = "h:mm"
        navigationItem.prompt = "Today at \(timeFormatter.string(from: Date()))"
        interfaceSwitcher.selectedSegmentIndex = 0
        interfaceSwitcher.addTarget(self, action: #selector(switchInterface(_:)), for: .valueChanged)
        let refreshControlButton = UIButton(type: .system)
        refreshControlButton.setImage(UIImage(systemName: "bolt.fill"), for: .normal)
        refreshControlButton.tintColor = .white
        refreshControlButton.backgroundColor = BabelPalette.accent
        refreshControlButton.layer.cornerRadius = 12
        refreshControlButton.addTarget(self, action: #selector(showFeedIssues), for: .touchUpInside)
        refreshControlButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            refreshControlButton.widthAnchor.constraint(equalToConstant: 24),
            refreshControlButton.heightAnchor.constraint(equalToConstant: 24)
        ])
        let refreshButton = UIBarButtonItem(customView: refreshControlButton)
        let subscribeControl = UIButton(type: .custom)
        subscribeControl.preferredBehavioralStyle = .pad
        subscribeControl.setImage(UIImage(systemName: "plus"), for: .normal)
        subscribeControl.tintColor = BabelPalette.ink
        subscribeControl.addTarget(self, action: #selector(showSubscribe), for: .touchUpInside)
        subscribeControl.frame = CGRect(x: 0, y: 0, width: 44, height: 44)
        let subscribeButton = UIBarButtonItem(customView: subscribeControl)
        navigationItem.rightBarButtonItems = [subscribeButton, refreshButton]
        tableView.backgroundColor = BabelPalette.background
        tableView.separatorStyle = .none
        // Keep the first data row below the custom Reeder header. The header is
        // layered above the table, so a small inset would hide the Unread row.
        // The table's automatic safe-area adjustment adds the status/header
        // space.  217pt places the Unread row on the same baseline as Reeder.
        tableView.contentInset = UIEdgeInsets(top: 178, left: 0, bottom: 88, right: 0)
        tableView.rowHeight = 44
        tableView.estimatedRowHeight = 44
        tableView.register(BabelFeedCell.self, forCellReuseIdentifier: BabelFeedCell.reuseIdentifier)
        emptyLabel.text = "No Feeds"
        emptyLabel.textColor = BabelPalette.mutedInk
        emptyLabel.font = BabelTypography.title(size: 17, weight: .regular)
        emptyLabel.textAlignment = .center
        emptyLabel.isHidden = true
        tableView.backgroundView = emptyLabel
        let refresh = UIRefreshControl()
        refresh.addTarget(self, action: #selector(refreshFeeds), for: .valueChanged)
        tableView.refreshControl = refresh
        tableView.dataSource = self
        tableView.delegate = self
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        configureCustomHeader()
        configureBottomBar()
        rebuildRows()
        NotificationCenter.default.addObserver(self, selector: #selector(rebuild), name: .UnreadCountDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(rebuild), name: .AccountDidDownloadArticles, object: nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Apply after UITableView has performed its safe-area/content-size
        // adjustment; doing this during reloadData is clamped by UIKit.
        guard !didApplyInitialOffset else { return }
        didApplyInitialOffset = true
        tableView.setContentOffset(CGPoint(x: 0, y: 300), animated: false)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }

    private func configureCustomHeader() {
        customHeader.translatesAutoresizingMaskIntoConstraints = false
        customHeader.backgroundColor = BabelPalette.background
        view.addSubview(customHeader)

        let back = UIButton(type: .custom)
        back.setImage(UIImage(systemName: "chevron.left", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)), for: .normal)
        back.tintColor = BabelPalette.ink
        back.addTarget(self, action: #selector(closeFeeds), for: .touchUpInside)
        back.translatesAutoresizingMaskIntoConstraints = false
        customHeader.addSubview(back)

        let titleLabel = UILabel()
        titleLabel.text = "Feeds"
        titleLabel.font = .systemFont(ofSize: 32, weight: .bold)
        titleLabel.textColor = BabelPalette.ink
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        customHeader.addSubview(titleLabel)

        let subtitle = UILabel()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "h:mm"
        subtitle.text = "Today at \(formatter.string(from: Date()))"
        subtitle.font = .systemFont(ofSize: 14, weight: .regular)
        subtitle.textColor = BabelPalette.mutedInk
        subtitle.textAlignment = .center
        subtitle.translatesAutoresizingMaskIntoConstraints = false
        customHeader.addSubview(subtitle)

        let refresh = UIButton(type: .custom)
        refresh.setImage(UIImage(systemName: "bolt.fill"), for: .normal)
        refresh.tintColor = .white
        refresh.backgroundColor = BabelPalette.accent
        refresh.layer.cornerRadius = 12
        refresh.addTarget(self, action: #selector(refreshFeeds), for: .touchUpInside)
        refresh.translatesAutoresizingMaskIntoConstraints = false
        customHeader.addSubview(refresh)

        let subscribe = UIButton(type: .custom)
        subscribe.setImage(UIImage(systemName: "plus"), for: .normal)
        subscribe.tintColor = BabelPalette.ink
        subscribe.addTarget(self, action: #selector(showSubscribe), for: .touchUpInside)
        subscribe.translatesAutoresizingMaskIntoConstraints = false
        customHeader.addSubview(subscribe)

        NSLayoutConstraint.activate([
            customHeader.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            customHeader.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            customHeader.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            customHeader.heightAnchor.constraint(equalToConstant: 150),
            back.leadingAnchor.constraint(equalTo: customHeader.leadingAnchor),
            back.centerYAnchor.constraint(equalTo: customHeader.topAnchor, constant: 24),
            back.widthAnchor.constraint(equalToConstant: 44),
            back.heightAnchor.constraint(equalToConstant: 44),
            titleLabel.centerXAnchor.constraint(equalTo: customHeader.centerXAnchor),
            titleLabel.topAnchor.constraint(equalTo: customHeader.topAnchor, constant: 64),
            subtitle.centerXAnchor.constraint(equalTo: customHeader.centerXAnchor),
            subtitle.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 1),
            refresh.trailingAnchor.constraint(equalTo: subscribe.leadingAnchor, constant: -8),
            refresh.centerYAnchor.constraint(equalTo: customHeader.topAnchor, constant: 24),
            refresh.widthAnchor.constraint(equalToConstant: 24),
            refresh.heightAnchor.constraint(equalToConstant: 24),
            subscribe.trailingAnchor.constraint(equalTo: customHeader.trailingAnchor, constant: -12),
            subscribe.centerYAnchor.constraint(equalTo: customHeader.topAnchor, constant: 24),
            subscribe.widthAnchor.constraint(equalToConstant: 44),
            subscribe.heightAnchor.constraint(equalToConstant: 44)
        ])

    }

    private func configureBottomBar() {
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.backgroundColor = BabelPalette.background
        bottomBar.layer.borderColor = BabelPalette.hairline.cgColor
        bottomBar.layer.borderWidth = 0.5
        view.addSubview(bottomBar)

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.alignment = .center
        stack.distribution = .equalSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.addSubview(stack)
        interfaceSwitcher.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.addSubview(interfaceSwitcher)

        let star = toolbarButton(image: UIImage(systemName: "star.fill"))
        star.addTarget(self, action: #selector(openSaved), for: .touchUpInside)
        let unread = makeUnreadToolbarButton()
        unread.addTarget(self, action: #selector(openUnread), for: .touchUpInside)
        unread.backgroundColor = BabelPalette.raisedBackground
        unread.layer.cornerRadius = 22
        let list = toolbarButton(image: UIImage(systemName: "list.bullet"))
        stack.addArrangedSubview(star)
        stack.addArrangedSubview(unread)
        stack.addArrangedSubview(list)

        NSLayoutConstraint.activate([
            bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            bottomBar.heightAnchor.constraint(equalToConstant: 72),
            interfaceSwitcher.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: 8),
            interfaceSwitcher.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),
            interfaceSwitcher.widthAnchor.constraint(equalToConstant: 88),
            interfaceSwitcher.heightAnchor.constraint(equalToConstant: 28),
            stack.centerXAnchor.constraint(equalTo: bottomBar.centerXAnchor),
            stack.widthAnchor.constraint(equalToConstant: 244),
            stack.heightAnchor.constraint(equalToConstant: 36),
            stack.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor, constant: -2)
        ])

        NSLayoutConstraint.activate([
            star.widthAnchor.constraint(equalToConstant: 44), star.heightAnchor.constraint(equalToConstant: 36),
            unread.widthAnchor.constraint(equalToConstant: 76), unread.heightAnchor.constraint(equalToConstant: 36),
            list.widthAnchor.constraint(equalToConstant: 44), list.heightAnchor.constraint(equalToConstant: 36)
        ])
    }

    private func makeUnreadToolbarButton() -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.baseForegroundColor = BabelPalette.ink
        configuration.background.backgroundColor = BabelPalette.raisedBackground
        configuration.background.cornerRadius = 18
        let button = UIButton(configuration: configuration)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.accessibilityLabel = "未读"
        let dot = UIView()
        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.backgroundColor = BabelPalette.ink
        dot.layer.cornerRadius = 6
        button.addSubview(dot)
        let title = UILabel()
        title.translatesAutoresizingMaskIntoConstraints = false
        title.text = "UNREAD"
        title.textColor = BabelPalette.ink
        title.font = UIFont.systemFont(ofSize: 9, weight: .semibold)
        button.addSubview(title)
        NSLayoutConstraint.activate([
            dot.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 8),
            dot.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: 12), dot.heightAnchor.constraint(equalToConstant: 12),
            title.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 4),
            title.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -3),
            title.centerYAnchor.constraint(equalTo: button.centerYAnchor)
        ])
        return button
    }

    private func toolbarButton(image: UIImage?) -> UIButton {
        let button = UIButton(type: .system)
        if let image {
            button.setImage(image.withConfiguration(UIImage.SymbolConfiguration(pointSize: 10, weight: .regular)), for: .normal)
        }
        button.tintColor = BabelPalette.ink
        button.frame.size = CGSize(width: 44, height: 44)
        return button
    }

    @objc private func openUnread() { onSelectUnread?() }
    @objc private func openSaved() { onSelectSaved?() }

    @objc private func closeFeeds() { navigationController?.popViewController(animated: true) }

    private func folderKey(_ folder: Folder) -> String {
        "\(folder.accountID):\(folder.nameForDisplay)"
    }

    private func rebuildRows() {
        rows = [.unread, .sectionSpacing]
        rows.append(.foldersHeader)
        for account in AccountManager.shared.sortedActiveAccounts {
            for folder in (account.folders ?? []).sorted(by: { $0.nameForDisplay < $1.nameForDisplay }) {
                rows.append(.folder(folder))
                if !collapsedFolders.contains(folderKey(folder)) {
                    rows.append(contentsOf: folder.topLevelFeeds.sorted(by: { $0.nameForDisplay < $1.nameForDisplay }).map(Row.feed))
                }
            }
            rows.append(contentsOf: account.topLevelFeeds.sorted(by: { $0.nameForDisplay < $1.nameForDisplay }).map(Row.feed))
        }
        tableView.reloadData()
        emptyLabel.isHidden = rows.contains { row in
            if case .feed = row { return true }
            return false
        }
    }

    @objc private func rebuild() { rebuildRows() }

    @objc private func refreshFeeds() {
        AccountManager.shared.refreshAllWithoutWaiting(errorHandler: ErrorHandler.log)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.tableView.refreshControl?.endRefreshing()
        }
    }

    @objc private func showFeedIssues() {
        let controller = BabelFeedIssuesViewController()
        if let sheet = controller.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 18
        }
        present(controller, animated: true)
    }

    @objc private func showSubscribe() {
        onOpenSubscribe?()
    }

    @objc private func switchInterface(_ sender: UISegmentedControl) {
        guard sender.selectedSegmentIndex == 1 else { return }
        sender.selectedSegmentIndex = 0
        onOpenGenesisV2?()
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { rows.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: BabelFeedCell.reuseIdentifier, for: indexPath) as! BabelFeedCell
        // Spacer rows are intentionally inert, but reused cells must regain
        // interaction before representing a real feed or folder.
        cell.isUserInteractionEnabled = true
        switch rows[indexPath.row] {
        case .unread:
            cell.configure(title: "Unread", count: AccountManager.shared.unreadCount, image: UIImage(systemName: "circle.fill"), indent: 0, isFolder: false)
        case .sectionSpacing:
            cell.configure(title: "", count: nil, image: nil, indent: 0, isFolder: false)
            cell.isUserInteractionEnabled = false
        case .foldersHeader:
            cell.configure(title: "Folders", count: nil, image: nil, indent: 0, isFolder: false, sectionHeader: true)
        case .folder(let folder):
            let expanded = !collapsedFolders.contains(folderKey(folder))
            let key = folderKey(folder)
            cell.configure(title: folder.nameForDisplay, count: folder.unreadCount, image: nil, indent: 0, isFolder: true, expanded: expanded) { [weak self] in
                guard let self else { return }
                if self.collapsedFolders.contains(key) { self.collapsedFolders.remove(key) } else { self.collapsedFolders.insert(key) }
                self.rebuildRows()
            }
        case .feed(let feed):
            let icon = FaviconDownloader.shared.faviconAsIcon(for: feed)?.image ?? UIImage(systemName: "square.fill")
            cell.configure(title: feed.nameForDisplay, count: feed.unreadCount, image: icon, indent: 1, isFolder: false)
        }
        return cell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        if case .sectionSpacing = rows[indexPath.row] { return 14 }
        return 44
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch rows[indexPath.row] {
        case .unread: onSelectUnread?()
        case .sectionSpacing: break
        case .foldersHeader: break
        case .folder(let folder):
            onSelectFolder?(folder)
        case .feed(let feed): onSelectFeed?(feed)
        }
    }
}

private final class BabelFeedIssuesViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = BabelPalette.background

        let close = UIButton(type: .custom)
        close.setImage(UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)), for: .normal)
        close.tintColor = BabelPalette.ink
        close.addTarget(self, action: #selector(closeSheet), for: .touchUpInside)
        close.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(close)

        let title = UILabel()
        title.text = "Feed Issues"
        title.font = BabelTypography.title(size: 36, weight: .bold)
        title.textColor = BabelPalette.ink
        title.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(title)

        let message = UILabel()
        message.text = "No feed issues"
        message.font = BabelTypography.title(size: 17, weight: .regular)
        message.textColor = BabelPalette.mutedInk
        message.textAlignment = .left
        message.numberOfLines = 0
        message.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(message)

        NSLayoutConstraint.activate([
            close.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            close.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            close.widthAnchor.constraint(equalToConstant: 44), close.heightAnchor.constraint(equalToConstant: 44),
            title.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            title.topAnchor.constraint(equalTo: close.bottomAnchor, constant: 20),
            message.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            message.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            message.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            message.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28)
        ])
		Task { @MainActor in
			let entries = await AccountManager.shared.errorLogDatabase.allEntries()
			if entries.isEmpty {
				message.text = "No feed issues"
			} else {
				message.text = entries.prefix(5).map { entry in
					let operation = entry.operation.isEmpty ? "Feed" : entry.operation
					return "\(entry.sourceName) · \(operation)\n\(entry.errorMessage)"
				}.joined(separator: "\n\n")
			}
		}
    }

    @objc private func closeSheet() { dismiss(animated: true) }
}

private final class BabelFeedCell: UITableViewCell {
	static let reuseIdentifier = "BabelFeedCell"
	private let iconView = UIImageView()
	private let titleLabel = UILabel()
	private let countLabel = UILabel()
	private let disclosureButton = UIButton(type: .custom)
	private var toggleFolder: (() -> Void)?

	override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
		super.init(style: style, reuseIdentifier: reuseIdentifier)
		backgroundColor = .clear
		let selection = UIView()
		selection.backgroundColor = BabelPalette.raisedBackground
		selection.layer.cornerRadius = 12
		selectedBackgroundView = selection
		iconView.contentMode = .scaleAspectFit
		iconView.tintColor = BabelPalette.mutedInk
		titleLabel.font = BabelTypography.title(size: 17, weight: .regular)
		titleLabel.textColor = BabelPalette.ink
		titleLabel.lineBreakMode = .byTruncatingTail
        countLabel.font = BabelTypography.title(size: 15, weight: .regular)
		countLabel.textColor = BabelPalette.mutedInk
		countLabel.textAlignment = .right
		for subview in [iconView, titleLabel, countLabel] {
			subview.translatesAutoresizingMaskIntoConstraints = false
			contentView.addSubview(subview)
		}
		disclosureButton.addTarget(self, action: #selector(disclosureTapped), for: .touchUpInside)
		disclosureButton.tintColor = BabelPalette.mutedInk
		disclosureButton.translatesAutoresizingMaskIntoConstraints = false
		contentView.addSubview(disclosureButton)
	}

	override func layoutSubviews() {
		super.layoutSubviews()
		selectedBackgroundView?.frame = bounds.insetBy(dx: 8, dy: 3)
	}
	required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

	func configure(title: String, count: Int?, image: UIImage?, indent: Int, isFolder: Bool, expanded: Bool = false, sectionHeader: Bool = false, toggleFolder: (() -> Void)? = nil) {
		iconView.image = image
		iconView.isHidden = sectionHeader
		titleLabel.font = sectionHeader ? BabelTypography.title(size: 20, weight: .semibold) : BabelTypography.title(size: 17, weight: .regular)
		self.toggleFolder = toggleFolder
		if isFolder {
			disclosureButton.setImage(UIImage(systemName: expanded ? "chevron.down" : "chevron.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .regular)), for: .normal)
			disclosureButton.isHidden = false
			disclosureButton.accessibilityLabel = title
			disclosureButton.accessibilityValue = expanded ? "Expanded" : "Collapsed"
		} else {
			disclosureButton.isHidden = true
			disclosureButton.accessibilityLabel = nil
			disclosureButton.accessibilityValue = nil
		}
		titleLabel.text = title
		countLabel.text = count?.formatted()
		countLabel.isHidden = count == nil
        let leading: CGFloat = indent == 0 ? 18 : 40
		NSLayoutConstraint.deactivate(contentView.constraints)
		let titleLeading = sectionHeader ? 18 : leading + 32
		NSLayoutConstraint.activate([
			disclosureButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 18),
			disclosureButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
			disclosureButton.widthAnchor.constraint(equalToConstant: 32),
			disclosureButton.heightAnchor.constraint(equalToConstant: 44),
			iconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: leading),
			iconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 20),
            iconView.heightAnchor.constraint(equalToConstant: 20),
			titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: titleLeading),
			titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
			titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: countLabel.leadingAnchor, constant: -12),
			countLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -22),
			countLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
			countLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 52)
		])
	}

	@objc private func disclosureTapped() { toggleFolder?() }
}
