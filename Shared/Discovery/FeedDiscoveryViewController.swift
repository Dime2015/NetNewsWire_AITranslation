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
import Images
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

	/// 搜哪一类。
	///
	/// **`.all` 是默认项,也是绝大多数情况下唯一需要用到的。**
	/// 它会自己判断输入是什么(见 `FeedQueryRouter`),所以用户不必先想
	/// 「我要找的是播客还是网站」再去点 tab。
	/// 其余几项的作用只是**缩小范围**,不是必须先选的前置步骤。
	private enum Source: Int, CaseIterable {
		case all
		case podcast
		case reddit
		case youtube
		case website

		var title: String {
			switch self {
			case .all: return "全部"
			case .podcast: return "播客"
			case .reddit: return "Reddit"
			case .youtube: return "YouTube"
			case .website: return "网站"
			}
		}

		var placeholder: String {
			switch self {
			case .all: return "粘网址,或输入名称搜播客"
			case .podcast: return "输入播客名称,例如 Stratechery"
			case .reddit: return "输入版块名,例如 apple 或 r/apple"
			case .youtube: return "粘频道地址,或输入 @名字"
			case .website: return "粘网站地址,例如 stratechery.com"
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

	/// 正在订阅中的那几条。订阅要联网(上游会去验证 feed),慢的时候要几秒,
	/// 期间必须有反馈,否则用户会以为没点上、反复点。
	private var subscribingURLs = Set<String>()

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

		// ⚠️ **这个页面刻意一个「完成 / 取消」按钮都没有**(2026-07-23 改成推入式页面后)。
		//
		// 根本原因是:**这个页面没有「提交」这个动作**。
		// 点一条结果就订阅一条、当场生效,没有需要确认的表单,
		// 所以「完成」是假的(会让人以为不按就没加成功),「取消」也是假的(取消不掉已订阅的)。
		// 改成推入式页面之后,离开就是系统返回按钮的事,不需要我们再放一个。
		//
		// 订阅与否只由结果行自己表达:[订阅] → 转圈 → ✓ 已订阅。一个地方说一件事,不重复。
		//
		// (改造史:最早这里是「完成」,和结果行的「订阅」语义打架;
		//  后来改成「取消」;现在连按钮本身都不需要了。)

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

		NotificationCenter.default.addObserver(self,
											   selector: #selector(imageDidBecomeAvailable(_:)),
											   name: .imageDidBecomeAvailable,
											   object: nil)
	}

	/// 离开页面时把在飞的搜索请求掐掉,别让它回来往已经不在的界面上写东西。
	override func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)
		if isMovingFromParent {		// 真的被返回掉了,而不是被别的页面盖住
			searchTask?.cancel()
		}
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
				case .all:
					// 「全部」不自己干活,只负责判断该交给谁 —— 判断逻辑在
					// FeedQueryRouter 里,单独拆出来是为了能离线跑测试
					// (初版就是靠那批测试抓出「不带 https:// 但带路径的网址
					//  会被误判成关键词」这个 bug)
					switch FeedQueryRouter.route(for: keyword) {
					case .podcastKeyword(let term):
						found = try await PodcastSearcher.search(term)
					case .reddit(let name):
						found = RedditFeedBuilder.results(subreddit: name)
					case .youtube(let text):
						found = [try await YouTubeFeedResolver.resolve(text)]
					case .website(let text):
						found = try await WebsiteFeedResolver.search(text)
					case .unsupportedKeyword(let hint):
						throw FeedSearchError.keywordNotSupported(hint: hint)
					}

				case .podcast:
					found = try await PodcastSearcher.search(keyword)
				case .reddit:
					guard let name = RedditFeedBuilder.subredditName(from: keyword) else {
						throw FeedSearchError.badSubredditName
					}
					// 本地拼地址,不发网络请求 —— 把 Reddit 的请求配额留给真正要紧的订阅那一步。
					// 原因详见 RedditFeedBuilder.results 的注释。
					found = RedditFeedBuilder.results(subreddit: name)

				case .youtube:
					found = [try await YouTubeFeedResolver.resolve(keyword)]

				case .website:
					// 在**搜索阶段**就把 feed 找出来,而不是等订阅时再发现。
					// 初版是后者(把网址原样交给 createFeed,指望上游发现),
					// 实测好几个网站都订不上 —— 详见 WebsiteFeedResolver 的注释。
					found = try await WebsiteFeedResolver.search(keyword)
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

		// 先把行尾换成转圈,让用户知道点上了
		subscribingURLs.insert(result.feedURL)
		tableView.reloadData()

		account.createFeed(url: result.feedURL,
						   name: result.title,
						   container: container,
						   validateFeed: true) { [weak self] createResult in

			BatchUpdate.shared.end()
			guard let self else { return }

			self.subscribingURLs.remove(result.feedURL)

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
				// 失败时也必须刷新,把转圈换回加号 —— 否则那一行会永远转下去
				self.tableView.reloadData()
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
		case .all:
			return "粘一个网址,或者输入名称搜播客 —— 不用先选类型,会自动判断。\n\n"
				+ "YouTube 频道、Reddit 版块、播客、普通网站都从这里加。\n"
				+ "上面几个分类只是用来缩小范围的,平时不用管。\n\n"
				+ "找到后点一下那条结果就订阅,不需要再按别的按钮。"
		case .podcast:
			return "输入播客名称搜索。找到后点一下就能订阅。"
		case .reddit:
			return "Reddit 没有公开的版块搜索接口,所以需要你直接输入版块名(例如 apple、r/apple,或粘一个 Reddit 链接)。会列出「每日 / 每周 / 每月 / 实时热门」四种,挑一个订阅。\n\n版块名对不对要到订阅时才知道 —— 这是有意的,Reddit 限流很严,把请求留给订阅那一步更划算。如果订阅失败,先等一两分钟再试,多半是限流而不是名字错了。"
		case .youtube:
			return "粘频道主页地址(youtube.com/@名字),或者直接输入 @名字。\n\n注意要频道的地址,不是某个视频播放页的地址。订阅的是 YouTube 官方 RSS,每次频道更新都会收到。"
		case .website:
			return "粘网站地址就行,不用自己去找 RSS 地址 —— 订阅时会自动从网页里找出来。\n\n少写 https:// 也没关系,会自动补。"
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
		cell.accessoryView = accessoryView(for: result, row: indexPath.row)
		configureIcon(on: cell, for: result)
		return cell
	}

	/// 结果行左边的小图标。
	///
	/// 有真实图标就用真实的(播客封面 / YouTube 频道头像),没有就退回一个
	/// **按类型区分的符号**。不留空白 —— 一整列都对齐才好扫,
	/// 而且"这条是播客还是网站"本身就是有用的信息。
	private func configureIcon(on cell: UITableViewCell, for result: FeedSearchResult) {

		cell.imageView?.layer.cornerRadius = 6
		cell.imageView?.clipsToBounds = true
		cell.imageView?.contentMode = .scaleAspectFill

		if let iconURL = result.iconURL,
		   let data = ImageDownloader.shared.image(for: iconURL),
		   let image = UIImage(data: data) {
			cell.imageView?.image = image.nnwDiscoveryThumbnail()
			cell.imageView?.tintColor = nil
			return
		}

		// 还没下完(或压根没有):先放类型符号。
		// 图下完了 ImageDownloader 会发通知,我们收到后整表刷新一次。
		let symbol = UIImage(systemName: result.fallbackSymbolName)?
			.withConfiguration(UIImage.SymbolConfiguration(pointSize: 18, weight: .regular))
		cell.imageView?.image = symbol?.nnwDiscoveryPadded()
		cell.imageView?.tintColor = .tertiaryLabel
	}

	/// 图标下载完成时刷新列表。
	///
	/// `ImageDownloader.image(for:)` 是「有就给、没有就去下」的接口,
	/// 下完之后发 `.imageDidBecomeAvailable`。不听这个通知的话,
	/// 图标要等到用户滚动列表才会冒出来。(做法抄的是本 fork 的 ArticleThumbnail。)
	@objc private func imageDidBecomeAvailable(_ note: Notification) {
		guard let url = note.userInfo?["url"] as? String,
			  results.contains(where: { $0.iconURL == url }) else {
			return
		}
		tableView.reloadData()
	}

	/// 结果行右侧那个东西。三种状态,同一个位置,一眼看得出下一步能干什么:
	///
	///   ⊕ 加号   —— 还没订阅,点它(或点整行)就订阅
	///   转圈     —— 正在订阅
	///   ✓ 对勾   —— 已经订阅好了,不再是按钮
	///
	/// 之所以把状态全部收在这一个地方,是因为改造前「订阅到没到」被
	/// 导航栏的「完成」和行尾的对勾两处同时表达,用户不知道该信哪个。
	/// 现在:**一个地方说一件事。**
	private func accessoryView(for result: FeedSearchResult, row: Int) -> UIView {

		if subscribedURLs.contains(result.feedURL) {
			let check = UIImageView(image: UIImage(systemName: "checkmark.circle.fill"))
			check.tintColor = .systemGreen
			check.sizeToFit()
			return check
		}

		if subscribingURLs.contains(result.feedURL) {
			let spinner = UIActivityIndicatorView(style: .medium)
			spinner.startAnimating()
			spinner.sizeToFit()
			return spinner
		}

		var configuration = UIButton.Configuration.plain()
		configuration.image = UIImage(systemName: "plus.circle")
		configuration.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 6)

		let button = UIButton(configuration: configuration)
		button.tintColor = .tintColor
		button.accessibilityLabel = "订阅"
		// 用行号定位是哪一条。安全的前提是:每次结果变化都会 reloadData,
		// 所以按钮上的行号和当前列表永远是一致的。
		button.tag = row
		button.addTarget(self, action: #selector(subscribeButtonTapped(_:)), for: .touchUpInside)
		button.sizeToFit()
		return button
	}

	@objc private func subscribeButtonTapped(_ sender: UIButton) {
		guard sender.tag >= 0, sender.tag < results.count else {
			return
		}
		let result = results[sender.tag]
		guard !subscribedURLs.contains(result.feedURL),
			  !subscribingURLs.contains(result.feedURL) else {
			return
		}
		subscribe(to: result)
	}

	override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		tableView.deselectRow(at: indexPath, animated: true)

		if indexPath.section == 0 {
			showFolderPicker()
			return
		}

		// 点整行和点行尾的加号是同一件事 —— 加号是给「看得出能点」用的,
		// 但整行可点仍然保留,因为那是列表的常规预期。
		let result = results[indexPath.row]
		guard !subscribedURLs.contains(result.feedURL),
			  !subscribingURLs.contains(result.feedURL) else {
			return
		}
		subscribe(to: result)
	}
}

// MARK: - 图标尺寸归一

private extension UIImage {

	/// 结果行图标的统一边长。
	///
	/// **必须统一**:UITableViewCell 自带的 imageView 会按图片原始尺寸撑开,
	/// 各家封面尺寸不一,会导致每行文字的起点参差不齐,列表看着很脏。
	/// (和列表页 favicon 永远占位是同一个道理,见 NOTES-progress 里列表那一节。)
	static let nnwDiscoveryIconSide: CGFloat = 40

	/// 把图片缩放并裁剪成正方形缩略图
	func nnwDiscoveryThumbnail() -> UIImage {
		let side = Self.nnwDiscoveryIconSide
		let target = CGSize(width: side, height: side)
		return UIGraphicsImageRenderer(size: target).image { _ in
			// scaleAspectFill 的等效算法:按较长边铺满,多出来的部分裁掉
			let scale = max(side / size.width, side / size.height)
			let scaled = CGSize(width: size.width * scale, height: size.height * scale)
			draw(in: CGRect(x: (side - scaled.width) / 2,
							y: (side - scaled.height) / 2,
							width: scaled.width,
							height: scaled.height))
		}
	}

	/// 把符号放进同样大小的透明方框里居中,这样它和真实图标占位一致
	func nnwDiscoveryPadded() -> UIImage {
		let side = Self.nnwDiscoveryIconSide
		let target = CGSize(width: side, height: side)
		return UIGraphicsImageRenderer(size: target).image { _ in
			draw(in: CGRect(x: (side - size.width) / 2,
							y: (side - size.height) / 2,
							width: size.width,
							height: size.height))
		}.withRenderingMode(.alwaysTemplate)
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
