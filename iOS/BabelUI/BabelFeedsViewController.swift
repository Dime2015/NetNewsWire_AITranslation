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
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "feed")
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

    @objc private func showSubscribe() {
        let alert = UIAlertController(title: "Subscribe", message: "订阅发现功能仍由创世版本 2 处理。", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "知道了", style: .default))
        present(alert, animated: true)
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { rows.count }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "feed", for: indexPath)
        var content = cell.defaultContentConfiguration()
        content.textProperties.font = BabelTypography.title(size: 16)
        content.textProperties.color = BabelPalette.ink
        content.secondaryTextProperties.font = UIFont.systemFont(ofSize: 12)
        content.secondaryTextProperties.color = BabelPalette.mutedInk
        content.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: 22, bottom: 0, trailing: 22)
        content.imageProperties.maximumSize = CGSize(width: 34, height: 34)
        content.imageProperties.reservedLayoutSize = CGSize(width: 42, height: 34)
        content.textProperties.adjustsFontForContentSizeCategory = true
        switch rows[indexPath.row] {
        case .unread:
            content.text = "Unread"
            content.secondaryText = "\(AccountManager.shared.unreadCount)"
            content.image = UIImage(systemName: "circle.fill")
            cell.indentationLevel = 0
        case .folder(let folder):
            content.text = folder.nameForDisplay
            content.secondaryText = "\(folder.unreadCount)"
            content.image = UIImage(systemName: "chevron.down")
            cell.indentationLevel = 0
        case .feed(let feed):
            content.text = feed.nameForDisplay
            content.secondaryText = "\(feed.unreadCount)"
            content.image = UIImage(systemName: "square.fill")
            cell.indentationLevel = 1
        }
        content.imageProperties.tintColor = BabelPalette.mutedInk
        cell.contentConfiguration = content
        cell.backgroundColor = .clear
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
