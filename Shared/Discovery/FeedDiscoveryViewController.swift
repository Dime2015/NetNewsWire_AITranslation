//
//  FeedDiscoveryViewController.swift
//  NetNewsWire
//
//  [发现] 本 fork 新增,上游没有这个文件。
//

#if os(iOS)

import UIKit
import Account
import RSCore
import os

/// 「搜索订阅源」页面。
///
/// 界面结构(从上到下):
///   搜索框(导航栏下面)
///   分段控件:播客 / Reddit        ← 决定用哪个后端去搜
///   ┌ 第 0 组:放进哪个文件夹        ← 点一下弹出上游现成的文件夹选择器
///   └ 第 1 组:搜索结果,点一条就订阅
///
/// **订阅、选文件夹这两件事全部复用上游现成的东西,禁区一行没改**:
///   - 订阅        Account.createFeed(...)                 公开接口
///   - 选文件夹     AddFeedFolderViewController             故事板里现成的
///   - 记住上次的文件夹  AddFeedDefaultContainer
@MainActor final class FeedDiscoveryViewController: UITableViewController {

	private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "FeedDiscovery")

	/// 搜哪一类。Phase A 只有播客和 Reddit,Phase B 会加 YouTube 和网站。
	private enum Source: Int, CaseIterable {
		case podcast
		case reddit

		var title: String {
			switch self {
			case .podcast: return "播客"
			case .reddit: return "Reddit"
			}
		}

		var placeholder: String {
			switch self {
			case .podcast: return "输入播客名称,例如 Stratechery"
			case .reddit: return "输入版块名,例如 apple 或 r/apple"
			}
		}
	}

	private let searchController = UISearchController(searchResultsController: nil)
	private lazy var sourceControl: UISegmentedControl = {
		let control = UISegmentedControl(items: Source.allCases.map { $0.title })
		control.selectedSegmentIndex = 0
		control.addTarget(self, action: #selector(sourceChanged), for: .valueChanged)
		return control
	}()

	private var source: Source {
		Source(rawValue: sourceControl.selectedSegmentIndex) ?? .podcast
	}

	private var results = [FeedSearchResult]()

	/// 已经订阅成功的那几条,用来在行上打勾 —— 让用户看得出哪些已经加过了
	private var subscribedURLs = Set<String>()

	private var isSearching = false

	/// 订阅到哪里。沿用上游记住的「上次选的文件夹」,和系统自带的添加订阅页保持一致。
	private var container: Container? = AddFeedDefaultContainer.defaultContainer

	/// 正在搜索的任务。换关键词时要把上一次的取消掉,
	/// 否则慢的那次后回来会把新结果盖掉(L11 那个教训的同类)。
	private var searchTask: Task<Void, Never>?

	deinit {
		searchTask?.cancel()
	}

	override func viewDidLoad() {
		super.viewDidLoad()

		title = "搜索订阅源"

		navigationItem.rightBarButtonItem = UIBarButtonItem(
			barButtonSystemItem: .done, target: self, action: #selector(done))

		searchController.searchBar.delegate = self
		searchController.searchBar.placeholder = source.placeholder
		searchController.searchBar.autocapitalizationType = .none
		searchController.searchBar.autocorrectionType = .no
		searchController.obscuresBackgroundDuringPresentation = false
		navigationItem.searchController = searchController
		navigationItem.hidesSearchBarWhenScrolling = false
		definesPresentationContext = true

		// 分段控件放在表头,始终可见
		let header = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: 52))
		header.addSubview(sourceControl)
		sourceControl.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			sourceControl.leadingAnchor.constraint(equalTo: header.layoutMarginsGuide.leadingAnchor),
			sourceControl.trailingAnchor.constraint(equalTo: header.layoutMarginsGuide.trailingAnchor),
			sourceControl.centerYAnchor.constraint(equalTo: header.centerYAnchor)
		])
		tableView.tableHeaderView = header
	}

	@objc private func done() {
		searchTask?.cancel()
		dismiss(animated: true)
	}

	@objc private func sourceChanged() {
		searchController.searchBar.placeholder = source.placeholder
		results = []
		tableView.reloadData()
	}

	// MARK: - 搜索

	private func performSearch(_ term: String) {

		searchTask?.cancel()

		let keyword = term.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !keyword.isEmpty else {
			results = []
			tableView.reloadData()
			return
		}

		isSearching = true
		results = []
		tableView.reloadData()

		let source = self.source

		searchTask = Task { [weak self] in
			do {
				let found: [FeedSearchResult]
				switch source {
				case .podcast:
					found = try await PodcastSearcher.search(keyword)
				case .reddit:
					guard let name = RedditFeedBuilder.subredditName(from: keyword) else {
						throw FeedSearchError.badSubredditName
					}
					// 本地拼地址,不发网络请求 —— 把 Reddit 的请求配额留给真正要紧的订阅那一步。
					// 原因详见 RedditFeedBuilder.results 的注释。
					found = RedditFeedBuilder.results(subreddit: name)
				}

				// 任务被取消(用户改了关键词)就什么都别做,别把旧结果写回界面
				guard !Task.isCancelled, let self else { return }
				self.isSearching = false
				self.results = found
				self.tableView.reloadData()

			} catch {
				guard !Task.isCancelled, let self else { return }
				self.isSearching = false
				self.results = []
				self.tableView.reloadData()
				self.presentError(error)
			}
		}
	}

	// MARK: - 订阅

	private func subscribe(to result: FeedSearchResult) {

		guard let container else {
			presentError(NSError(domain: "FeedDiscovery", code: 0, userInfo: [
				NSLocalizedDescriptionKey: "还没有可用的账户,无法订阅。"]))
			return
		}

		// 从容器倒推出账户 —— 抄的是上游 AddFeedViewController 的做法
		var account: Account?
		if let containerAccount = container as? Account {
			account = containerAccount
		} else if let containerFolder = container as? Folder, let containerAccount = containerFolder.account {
			account = containerAccount
		}
		guard let account else {
			return
		}

		if account.hasFeed(withURL: result.feedURL) {
			presentError(AccountError.createErrorAlreadySubscribed)
			return
		}

		BatchUpdate.shared.start()

		account.createFeed(url: result.feedURL,
						   name: result.title,
						   container: container,
						   validateFeed: true) { [weak self] createResult in

			BatchUpdate.shared.end()
			guard let self else { return }

			switch createResult {
			case .success(let feed):
				self.subscribedURLs.insert(result.feedURL)
				self.tableView.reloadData()
				// 发这个通知,订阅列表才会刷新并跳到新订阅上(和上游添加页一致)
				NotificationCenter.default.post(name: .UserDidAddFeed,
												object: self,
												userInfo: [UserInfoKey.feed: feed])
				Self.logger.info("[发现] 订阅成功:\(result.feedURL)")
			case .failure(let error):
				Self.logger.error("[发现] 订阅失败:\(result.feedURL) — \(error.localizedDescription)")
				// Reddit 的失败要换成说实话的提示:上游把 429(限流)也报成
				// 「找不到这个 feed」,会让人去反复检查根本没错的版块名。
				if result.kind == .reddit {
					let name = RedditFeedBuilder.subredditName(from: result.feedURL) ?? "该版块"
					self.presentError(RedditFeedBuilder.friendlyError(for: error, subreddit: name))
				} else {
					self.presentError(error)
				}
			}
		}
	}

	private func showFolderPicker() {
		let navController = UIStoryboard.add
			.instantiateViewController(withIdentifier: "AddFeedFolderNavViewController") as! UINavigationController
		navController.modalPresentationStyle = .currentContext
		let folderViewController = navController.topViewController as! AddFeedFolderViewController
		folderViewController.delegate = self
		folderViewController.initialContainer = container
		present(navController, animated: true)
	}

	private var folderLabel: String {
		guard let container else { return "未选择" }
		if let folder = container as? Folder {
			return "\(folder.account?.nameForDisplay ?? "") / \(folder.nameForDisplay)"
		}
		return (container as? Account)?.nameForDisplay ?? "未选择"
	}

	// MARK: - 表格

	override func numberOfSections(in tableView: UITableView) -> Int { 2 }

	override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		section == 0 ? 1 : results.count
	}

	override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
		if section == 0 { return "订阅到" }
		if isSearching { return "搜索中…" }
		return results.isEmpty ? nil : "搜索结果"
	}

	override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
		guard section == 1, !isSearching, results.isEmpty else { return nil }
		switch source {
		case .podcast:
			return "输入播客名称搜索。找到后点一下就能订阅。"
		case .reddit:
			return "Reddit 没有公开的版块搜索接口,所以需要你直接输入版块名(例如 apple、r/apple,或粘一个 Reddit 链接)。会列出「每日 / 每周 / 每月 / 实时热门」四种,挑一个订阅。\n\n版块名对不对要到订阅时才知道 —— 这是有意的,Reddit 限流很严,把请求留给订阅那一步更划算。如果订阅失败,先等一两分钟再试,多半是限流而不是名字错了。"
		}
	}

	override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {

		let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)

		if indexPath.section == 0 {
			cell.textLabel?.text = "文件夹"
			cell.detailTextLabel?.text = folderLabel
			cell.accessoryType = .disclosureIndicator
			return cell
		}

		let result = results[indexPath.row]
		cell.textLabel?.text = result.title
		cell.textLabel?.numberOfLines = 2
		cell.detailTextLabel?.text = result.subtitle
		cell.detailTextLabel?.numberOfLines = 1
		cell.detailTextLabel?.textColor = .secondaryLabel
		cell.accessoryType = subscribedURLs.contains(result.feedURL) ? .checkmark : .none
		return cell
	}

	override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		tableView.deselectRow(at: indexPath, animated: true)

		if indexPath.section == 0 {
			showFolderPicker()
			return
		}

		let result = results[indexPath.row]
		guard !subscribedURLs.contains(result.feedURL) else { return }
		subscribe(to: result)
	}
}

// MARK: - 搜索框

extension FeedDiscoveryViewController: UISearchBarDelegate {

	func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
		searchBar.resignFirstResponder()
		performSearch(searchBar.text ?? "")
	}
}

// MARK: - 文件夹选择器的回调

extension FeedDiscoveryViewController: AddFeedFolderViewControllerDelegate {

	func didSelect(container: Container) {
		self.container = container
		AddFeedDefaultContainer.saveDefaultContainer(container)
		tableView.reloadData()
	}
}

#endif
