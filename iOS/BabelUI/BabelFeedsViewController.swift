//
//  BabelFeedsViewController.swift
//  NetNewsWire
//
//  Reeder Classic 参考中的 Feeds / Folders 层。只读展示。
//

import UIKit
import Account
import Images

final class BabelFeedsViewController: UITableViewController {

    private enum Row {
        case unread
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
    private let emptyLabel = UILabel()
    private let bottomBar = UIView()
    private let customHeader = UIView()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Feeds"
        navigationItem.largeTitleDisplayMode = .never
        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        timeFormatter.dateFormat = "h:mm"
        navigationItem.prompt = "Today at \(timeFormatter.string(from: Date()))"
        let switcher = UISegmentedControl(items: ["Babel", "旧版"])
        switcher.selectedSegmentIndex = 0
        switcher.addTarget(self, action: #selector(switchInterface(_:)), for: .valueChanged)
        navigationItem.titleView = switcher
        let refreshControlButton = UIButton(type: .system)
        refreshControlButton.setImage(UIImage(systemName: "bolt.fill"), for: .normal)
        refreshControlButton.tintColor = .white
        refreshControlButton.backgroundColor = BabelPalette.accent
        refreshControlButton.layer.cornerRadius = 18
        refreshControlButton.addTarget(self, action: #selector(refreshFeeds), for: .touchUpInside)
        refreshControlButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            refreshControlButton.widthAnchor.constraint(equalToConstant: 36),
            refreshControlButton.heightAnchor.constraint(equalToConstant: 36)
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
        tableView.separatorColor = BabelPalette.hairline
        tableView.contentInset = UIEdgeInsets(top: 80, left: 0, bottom: 88, right: 0)
        tableView.rowHeight = 64
        tableView.estimatedRowHeight = 64
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

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }

    private func configureCustomHeader() {
        customHeader.translatesAutoresizingMaskIntoConstraints = false
        customHeader.backgroundColor = BabelPalette.background
        view.addSubview(customHeader)

        let back = UIButton(type: .custom)
        back.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        back.tintColor = BabelPalette.ink
        back.addTarget(self, action: #selector(closeFeeds), for: .touchUpInside)
        back.translatesAutoresizingMaskIntoConstraints = false
        customHeader.addSubview(back)

        let titleLabel = UILabel()
        titleLabel.text = "Feeds"
        titleLabel.font = .systemFont(ofSize: 24, weight: .semibold)
        titleLabel.textColor = BabelPalette.ink
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        customHeader.addSubview(titleLabel)

        let subtitle = UILabel()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "h:mm"
        subtitle.text = "Today at \(formatter.string(from: Date()))"
        subtitle.font = .systemFont(ofSize: 13, weight: .regular)
        subtitle.textColor = BabelPalette.mutedInk
        subtitle.textAlignment = .center
        subtitle.translatesAutoresizingMaskIntoConstraints = false
        customHeader.addSubview(subtitle)

        NSLayoutConstraint.activate([
            customHeader.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            customHeader.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            customHeader.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            customHeader.heightAnchor.constraint(equalToConstant: 74),
            back.leadingAnchor.constraint(equalTo: customHeader.leadingAnchor, constant: 16),
            back.centerYAnchor.constraint(equalTo: customHeader.centerYAnchor),
            back.widthAnchor.constraint(equalToConstant: 44),
            back.heightAnchor.constraint(equalToConstant: 44),
            titleLabel.centerXAnchor.constraint(equalTo: customHeader.centerXAnchor),
            titleLabel.topAnchor.constraint(equalTo: customHeader.topAnchor, constant: 8),
            subtitle.centerXAnchor.constraint(equalTo: customHeader.centerXAnchor),
            subtitle.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 1)
        ])

        let switcher = UISegmentedControl(items: ["Babel", "旧版"])
        switcher.selectedSegmentIndex = 0
        switcher.addTarget(self, action: #selector(switchInterface(_:)), for: .valueChanged)
        switcher.translatesAutoresizingMaskIntoConstraints = false
        customHeader.addSubview(switcher)
        NSLayoutConstraint.activate([
            switcher.centerXAnchor.constraint(equalTo: customHeader.centerXAnchor),
            switcher.centerYAnchor.constraint(equalTo: customHeader.centerYAnchor, constant: 1),
            switcher.widthAnchor.constraint(equalToConstant: 150),
            switcher.heightAnchor.constraint(equalToConstant: 32)
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
        stack.distribution = .equalCentering
        stack.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.addSubview(stack)

        let star = toolbarButton(image: UIImage(systemName: "star.fill"))
        star.addTarget(self, action: #selector(openSaved), for: .touchUpInside)
        let unread = UIButton(type: .system)
        var unreadConfiguration = UIButton.Configuration.plain()
        unreadConfiguration.image = UIImage(systemName: "circle.fill")
        unreadConfiguration.title = "UNREAD"
        unreadConfiguration.imagePadding = 8
        unreadConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 18, bottom: 12, trailing: 18)
        unread.configuration = unreadConfiguration
        unread.titleLabel?.font = BabelTypography.title(size: 14, weight: .semibold)
        unread.tintColor = BabelPalette.ink
        unread.setTitleColor(BabelPalette.ink, for: .normal)
        unread.addTarget(self, action: #selector(openUnread), for: .touchUpInside)
        unread.backgroundColor = BabelPalette.raisedBackground
        unread.layer.cornerRadius = 22
        let list = toolbarButton(image: UIImage(systemName: "line.3.horizontal"))
        stack.addArrangedSubview(star)
        stack.addArrangedSubview(unread)
        stack.addArrangedSubview(list)

        NSLayoutConstraint.activate([
            bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            bottomBar.heightAnchor.constraint(equalToConstant: 72),
            stack.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: 52),
            stack.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: -52),
            stack.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor, constant: -2)
        ])
    }

    private func toolbarButton(image: UIImage?) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(image, for: .normal)
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
        rows = [.unread]
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
        emptyLabel.isHidden = rows.count > 1
    }

    @objc private func rebuild() { rebuildRows() }

    @objc private func refreshFeeds() {
        AccountManager.shared.refreshAllWithoutWaiting(errorHandler: ErrorHandler.log)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.tableView.refreshControl?.endRefreshing()
        }
    }

    @objc private func showSubscribe() {
        onOpenSubscribe?()
    }

    @objc private func switchInterface(_ sender: UISegmentedControl) {
        guard sender.selectedSegmentIndex == 1 else { return }
        sender.selectedSegmentIndex = 0
        onOpenGenesisV2?()
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { rows.count }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: BabelFeedCell.reuseIdentifier, for: indexPath) as! BabelFeedCell
        switch rows[indexPath.row] {
        case .unread:
            cell.configure(title: "Unread", count: AccountManager.shared.unreadCount, image: UIImage(systemName: "circle.fill"), indent: 0, isFolder: false)
        case .folder(let folder):
            let expanded = !collapsedFolders.contains(folderKey(folder))
            cell.configure(title: folder.nameForDisplay, count: folder.unreadCount, image: UIImage(systemName: expanded ? "chevron.down" : "chevron.right"), indent: 0, isFolder: true)
        case .feed(let feed):
            let icon = FaviconDownloader.shared.faviconAsIcon(for: feed)?.image ?? UIImage(systemName: "square.fill")
            cell.configure(title: feed.nameForDisplay, count: feed.unreadCount, image: icon, indent: 1, isFolder: false)
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch rows[indexPath.row] {
        case .unread: onSelectUnread?()
        case .folder(let folder):
            let key = folderKey(folder)
            if collapsedFolders.contains(key) { collapsedFolders.remove(key) } else { collapsedFolders.insert(key) }
            rebuildRows()
        case .feed(let feed): onSelectFeed?(feed)
        }
    }
}

private final class BabelFeedCell: UITableViewCell {
	static let reuseIdentifier = "BabelFeedCell"
	private let iconView = UIImageView()
	private let titleLabel = UILabel()
	private let countLabel = UILabel()

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
		countLabel.font = BabelTypography.title(size: 16, weight: .regular)
		countLabel.textColor = BabelPalette.mutedInk
		countLabel.textAlignment = .right
		for subview in [iconView, titleLabel, countLabel] {
			subview.translatesAutoresizingMaskIntoConstraints = false
			contentView.addSubview(subview)
		}
	}

	override func layoutSubviews() {
		super.layoutSubviews()
		selectedBackgroundView?.frame = bounds.insetBy(dx: 8, dy: 3)
	}
	required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

	func configure(title: String, count: Int, image: UIImage?, indent: Int, isFolder: Bool) {
		iconView.image = image
		titleLabel.text = title
		countLabel.text = count.formatted()
        let leading: CGFloat = indent == 0 ? 18 : 40
		NSLayoutConstraint.deactivate(contentView.constraints)
		NSLayoutConstraint.activate([
			iconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: leading),
			iconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
			iconView.widthAnchor.constraint(equalToConstant: 28),
			iconView.heightAnchor.constraint(equalToConstant: 28),
			titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
			titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
			titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: countLabel.leadingAnchor, constant: -12),
			countLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -22),
			countLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
			countLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 52)
		])
	}
}
