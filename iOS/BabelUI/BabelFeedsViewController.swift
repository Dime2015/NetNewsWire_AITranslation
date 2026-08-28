//
//  BabelFeedsViewController.swift
//  NetNewsWire
//
//  Reeder Classic 参考中的 Feeds / Folders 层。只读展示。
//

import UIKit
import Account

final class BabelFeedsViewController: UITableViewController {

    private enum Row {
        case unread
        case folder(Folder)
        case feed(Feed)
    }

    var onSelectUnread: (() -> Void)?
    var onSelectFeed: ((Feed) -> Void)?
    var onSelectFolder: ((Folder) -> Void)?
    private var rows = [Row]()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Feeds"
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .add, target: self, action: #selector(showSubscribe)
        )
        tableView.backgroundColor = BabelPalette.background
        tableView.separatorColor = BabelPalette.hairline
        tableView.contentInset = UIEdgeInsets(top: 8, left: 0, bottom: 56, right: 0)
        tableView.rowHeight = 64
        tableView.estimatedRowHeight = 64
        tableView.register(BabelFeedCell.self, forCellReuseIdentifier: BabelFeedCell.reuseIdentifier)
        let refresh = UIRefreshControl()
        refresh.addTarget(self, action: #selector(refreshFeeds), for: .valueChanged)
        tableView.refreshControl = refresh
        rebuildRows()
        NotificationCenter.default.addObserver(self, selector: #selector(rebuild), name: .UnreadCountDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(rebuild), name: .AccountDidDownloadArticles, object: nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    private func rebuildRows() {
        rows = [.unread]
        for account in AccountManager.shared.sortedActiveAccounts {
            for folder in (account.folders ?? []).sorted(by: { $0.nameForDisplay < $1.nameForDisplay }) {
                rows.append(.folder(folder))
                rows.append(contentsOf: folder.topLevelFeeds.sorted(by: { $0.nameForDisplay < $1.nameForDisplay }).map(Row.feed))
            }
            rows.append(contentsOf: account.topLevelFeeds.sorted(by: { $0.nameForDisplay < $1.nameForDisplay }).map(Row.feed))
        }
        tableView.reloadData()
    }

    @objc private func rebuild() { rebuildRows() }

    @objc private func refreshFeeds() {
        AccountManager.shared.refreshAllWithoutWaiting(errorHandler: ErrorHandler.log)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.tableView.refreshControl?.endRefreshing()
        }
    }

    @objc private func showSubscribe() {
        let alert = UIAlertController(title: "Subscribe", message: "订阅发现功能仍由创世版本 2 处理。", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "知道了", style: .default))
        present(alert, animated: true)
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { rows.count }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: BabelFeedCell.reuseIdentifier, for: indexPath) as! BabelFeedCell
        switch rows[indexPath.row] {
        case .unread:
            cell.configure(title: "Unread", count: AccountManager.shared.unreadCount, image: UIImage(systemName: "circle.fill"), indent: 0, isFolder: false)
        case .folder(let folder):
            cell.configure(title: folder.nameForDisplay, count: folder.unreadCount, image: UIImage(systemName: "chevron.down"), indent: 0, isFolder: true)
        case .feed(let feed):
            cell.configure(title: feed.nameForDisplay, count: feed.unreadCount, image: UIImage(systemName: "square.fill"), indent: 1, isFolder: false)
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch rows[indexPath.row] {
        case .unread: onSelectUnread?()
        case .folder(let folder): onSelectFolder?(folder)
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
		selectedBackgroundView = UIView()
		selectedBackgroundView?.backgroundColor = BabelPalette.raisedBackground
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
	required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

	func configure(title: String, count: Int, image: UIImage?, indent: Int, isFolder: Bool) {
		iconView.image = image
		titleLabel.text = title
		countLabel.text = count.formatted()
		let leading: CGFloat = indent == 0 ? 22 : 58
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
