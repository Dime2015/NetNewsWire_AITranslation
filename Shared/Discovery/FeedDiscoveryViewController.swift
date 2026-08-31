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
///   搜索框(底部,系统摆的位置)——不用先选类型,`FeedQueryRouter` 自己判断输入是什么
///   ┌ section 0:放进哪个文件夹        ← 点一下弹动作单选(默认顶层)
///   └ section 1…N:按类别分组的搜索结果(网站/播客/YouTube/Reddit),
///     组标题可点击收起/展开。**点行 = 试读**(Phase B);行尾 ⊕ = 订阅;
///     已订阅的显示绿勾,**再点绿勾 = 取消订阅**
///
/// ⚠️ 2026-08-12 拿掉了顶部的分类滑块选单(播客/Reddit/YouTube/网站/全部 五选一)——
/// `FeedQueryRouter` 早就会自己判断输入是什么,滑块选单只是多一次点击、
/// 不提供额外能力,用户反馈"现在不需要了"。
///
/// 订阅成功后**留在本页**(2026-07-29 用户要求):刻意不发 .UserDidAddFeed,
/// 不让协调器把用户带进新源的文章列表 —— 订阅完通常还要继续挑下一个。
///
/// **订阅走上游公开接口,禁区一行没改**:
///   - 订阅        Account.createFeed(...)                 公开接口
///   - 选文件夹     ~~AddFeedFolderViewController~~ → 2026-07-24 改自绘动作单
///     (上游那套在推入式页面下只显示账户、选不了文件夹,详见 showFolderPicker 注释;
///      数据仍只走 sortedActiveAccounts / sortedFolders 公开接口)
///   - ~~记住上次的文件夹~~ → 每次默认顶层(用户拍板),不再读写 AddFeedDefaultContainer
@MainActor final class FeedDiscoveryViewController: UITableViewController {

	private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "FeedDiscovery")

	/// 搜索框的占位提示。
	///
	/// [发现] 2026-08-12:分类滑块选单拿掉了(用户反馈"现在不需要了")——
	/// 曾经它的作用是"缩小搜索范围",但 `FeedQueryRouter` 早就会自己判断输入是什么
	/// (网址按类型直连,关键词并行搜四类),滑块选单只是徒增一次点击、不再提供额外能力。
	/// 现在页面只有一种搜法,提示语也不再需要按 tab 切换。
	private static let searchPlaceholder = "粘网址,或输入关键词搜索"

	/// 搜索栏。
	///
	/// ## ⚠️ 用的是 `UISearchController`,因为**底部那个位置是它自带的**
	///
	/// iOS 26 给导航栏搜索框的新摆法会把它落在**屏幕底部**(和文章列表页那个同一套)。
	/// 2026-07-29 曾经换成普通 `UISearchBar` 放表头,为的是消掉它激活时那"多余的一层" ——
	/// 但用户要那个底部位置,而**位置和那一层是同一个东西的两面**,只能二选一。
	/// 用户拍板:要位置。
	///
	/// 那一层带来的问题(搜索激活期间弹不出选文件夹的卡片、弹不出"已经订阅过了"的提示)
	/// 改在 `NNWMenu.show` 里解决 —— 它现在会顺着 presented 链走到**最顶上那一层**再弹,
	/// 而不是发现"自己名下已经在弹东西"就放弃。详见那个方法的注释。
	private let searchController = UISearchController(searchResultsController: nil)

	/// [发现] 2026-08-11:一组同类别的搜索结果,按类别分节展示、可以点标题收起/展开。
	///
	/// 「全部」tab 输入关键词时,不再只搜播客——播客/Reddit/YouTube 并行搜,
	/// 一次给三组结果,按类别分节摆在同一个列表里(用户 2026-08-11 要求)。
	/// 其余情况(具体 tab、或「全部」tab 里输入的是网址)结果只有一类,
	/// 就是一个只有一组的列表——**统一用同一套数据结构和同一套表格代码**,
	/// 不为"单类别"和"多类别"分别写一遍表格逻辑。
	private struct ResultGroup {
		let kind: FeedSearchResult.Kind
		var results: [FeedSearchResult] = []
		/// 这一类没有结果时,给用户看的原因(没配 API Key / 真的没搜到 / 报错了)。
		/// `results` 非空时这个字段不显示。
		var statusMessage: String?
		var isExpanded = true
	}

	private var groups = [ResultGroup]()

	/// 四个类别按固定顺序摆(2026-08-12 用户拍板:网站最前,其次播客、YouTube、Reddit)。
	private static let unifiedKindOrder: [FeedSearchResult.Kind] = [.website, .podcast, .youtube, .reddit]

	/// 摊平所有组的结果,给"这条搜到过吗"之类跨组的判断用。
	private var allResults: [FeedSearchResult] {
		groups.flatMap { $0.results }
	}

	/// 已经订阅成功的那几条,用来在行上打勾 —— 让用户看得出哪些已经加过了
	private var subscribedURLs = Set<String>()

	/// 正在订阅中的那几条。订阅要联网(上游会去验证 feed),慢的时候要几秒,
	/// 期间必须有反馈,否则用户会以为没点上、反复点。
	private var subscribingURLs = Set<String>()

	/// 正在取消订阅中的那几条(2026-07-29 新增:点绿勾可取消订阅)。
	/// 和订阅同理:同步账户的删除要联网,期间行尾显示转圈。
	private var unsubscribingURLs = Set<String>()

	private var isSearching = false

	/// 这条结果是不是**已经订阅过了**。
	///
	/// ⚠️ **当场问账户,不维护第二份缓存**(2026-07-29 用户要求"已订阅的直接显示绿勾"):
	/// `subscribedURLs` 原本只记"本次会话里刚订阅成功的",所以**早就订阅过的源
	/// 看起来和没订阅的一模一样** —— 只能点下去才知道,而那句提示还可能弹不出来。
	/// 试过在拿到结果时预先算一遍填进缓存,但缓存总会有过期的时候(别处删了源、
	/// 换了账户);直接问账户既简单又永远准,而且**和订阅按钮用的是同一个判断**,
	/// 不可能出现"看着能订阅、点下去说已订阅"的矛盾。
	private func isAlreadySubscribed(_ result: FeedSearchResult) -> Bool {
		if subscribedURLs.contains(result.feedURL) { return true }		// 本次刚订阅成功的
		return AccountManager.shared.activeAccounts.contains { $0.hasFeed(withURL: result.feedURL) }
	}

	/// 订阅到哪里。**默认是账户顶层(不放进文件夹)**,不再沿用"上次选的文件夹"
	/// (2026-07-24 用户拍板:每次打开都从最外层开始,想进文件夹再手动选)。
	private var container: Container? = AccountManager.shared.defaultAccount

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

		// [外观] 和 app 其它列表页统一成暖纸风(2026-07-23 用户反馈这页配色没跟上)。
		// 每个 cell 的底色要在下面的 willDisplay 里逐个刷 —— 表格没有"统一设所有 cell 背景"的入口。
		AppAppearance.applyPaperStyle(to: tableView)

		searchController.searchBar.delegate = self
		searchController.searchBar.placeholder = Self.searchPlaceholder
		searchController.searchBar.autocapitalizationType = .none
		searchController.searchBar.autocorrectionType = .no
		searchController.obscuresBackgroundDuringPresentation = false
		navigationItem.searchController = searchController
		navigationItem.hidesSearchBarWhenScrolling = false
		definesPresentationContext = true

		NotificationCenter.default.addObserver(self,
											   selector: #selector(imageDidBecomeAvailable(_:)),
											   name: .imageDidBecomeAvailable,
											   object: nil)
	}

	/// 从试读页返回时,订阅状态可能已经变了(在那边点了订阅)—— 回来刷一遍,
	/// 让行尾的 ⊕/绿勾立刻对上真实状态。
	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		tableView.reloadData()
	}

	/// 离开页面时把在飞的搜索请求掐掉,别让它回来往已经不在的界面上写东西。
	override func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)
		if isMovingFromParent {		// 真的被返回掉了,而不是被别的页面盖住
			searchTask?.cancel()
		}
	}

	// MARK: - 搜索

	private func performSearch(_ term: String) {

		searchTask?.cancel()

		let keyword = term.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !keyword.isEmpty else {
			groups = []
			tableView.reloadData()
			return
		}

		isSearching = true
		groups = []
		tableView.reloadData()

		searchTask = Task { [weak self] in

			// [发现] 2026-08-11:输入的是**关键词**(不是网址)时,
			// 播客/Reddit/YouTube/网站**并行搜**,一次给四组结果,按类别分组显示。
			// 输入的是网址时结果只有一类(网址按域名直连对应类型),
			// 走下面 do/catch 那条老路,只是把单一结果包成一个只有一组的列表,
			// 表格代码不用分两套。判断逻辑在 FeedQueryRouter 里,
			// 单独拆出来是为了能离线跑测试(初版就是靠那批测试抓出
			// 「不带 https:// 但带路径的网址会被误判成关键词」这个 bug)。
			if case .podcastKeyword(let unified) = FeedQueryRouter.route(for: keyword) {
				let built = await Self.unifiedSearch(unified)
				guard !Task.isCancelled, let self else { return }
				self.isSearching = false
				self.groups = built
				self.tableView.reloadData()
				return
			}

			do {
				let kind: FeedSearchResult.Kind
				let found: [FeedSearchResult]

				switch FeedQueryRouter.route(for: keyword) {
				case .podcastKeyword:
					// 已经在上面处理过、提前 return 了,这里理论上到不了这一支,
					// 留着只是让 switch 完整、不崩。
					kind = .podcast
					found = try await PodcastSearcher.search(keyword)
				case .reddit(let name):
					kind = .reddit
					found = RedditFeedBuilder.results(subreddit: name)
				case .youtube(let text):
					kind = .youtube
					found = [try await YouTubeFeedResolver.resolve(text)]
				case .website(let text):
					// 在**搜索阶段**就把 feed 找出来,而不是等订阅时再发现。
					// 初版是后者(把网址原样交给 createFeed,指望上游发现),
					// 实测好几个网站都订不上 —— 详见 WebsiteFeedResolver 的注释。
					kind = .website
					found = try await WebsiteFeedResolver.search(text)
				case .unsupportedKeyword(let hint):
					throw FeedSearchError.keywordNotSupported(hint: hint)
				}

				// 任务被取消(用户改了关键词)就什么都别做,别把旧结果写回界面
				guard !Task.isCancelled, let self else { return }
				self.isSearching = false
				var group = ResultGroup(kind: kind, results: found)
				if found.isEmpty {
					// 没抛错、但也没搜到东西——给一行说明,别让这一组的 section 光秃秃的。
					group.statusMessage = Self.emptyMessage(for: kind)
				}
				self.groups = [group]
				self.tableView.reloadData()

			} catch {
				guard !Task.isCancelled, let self else { return }
				self.isSearching = false
				self.groups = []
				self.tableView.reloadData()
				self.presentError(error)
			}
		}
	}

	/// 播客/Reddit/YouTube/网站并行搜,**一类失败不连累其它三类**——
	/// 比如没配 Reddit API Key,或者网站那条(Feedly 未公开接口)恰好挂了,
	/// 别的类照常出结果,失败的那一组只显示自己的原因。
	private static func unifiedSearch(_ keyword: String) async -> [ResultGroup] {

		async let podcastOutcome = attempt { try await PodcastSearcher.search(keyword) }
		async let redditOutcome = attempt { try await RedditSearcher.search(keyword) }
		async let youtubeOutcome = attempt { try await YouTubeSearcher.search(keyword) }
		async let websiteOutcome = attempt { try await WebsiteSearcher.search(keyword) }

		let (podcast, reddit, youtube, website) = await (podcastOutcome, redditOutcome, youtubeOutcome, websiteOutcome)

		// 按 kind 取对应的结果——不依赖数组下标位置对齐(那种写法两边顺序一旦
		// 各改各的就会悄悄错位,这里用 switch 直接查,谁改了 unifiedKindOrder 都不会串)。
		func outcome(for kind: FeedSearchResult.Kind) -> (results: [FeedSearchResult], error: Error?) {
			switch kind {
			case .podcast: return podcast
			case .reddit: return reddit
			case .youtube: return youtube
			case .website: return website
			}
		}

		return unifiedKindOrder.map { kind in
			let outcome = outcome(for: kind)
			// [发现] 2026-08-12 用户要求:网站排最前、默认展开;播客/YouTube/Reddit
			// 默认收起——网站是最常搜的一类,其余三类先收着,列表不至于一屏全是结果。
			var group = ResultGroup(kind: kind, results: outcome.results, isExpanded: kind == .website)
			if outcome.results.isEmpty {
				group.statusMessage = outcome.error.map(Self.friendlyMessage(for:))
					?? Self.emptyMessage(for: kind)
			}
			return group
		}
	}

	private static func attempt(_ work: () async throws -> [FeedSearchResult]) async -> (results: [FeedSearchResult], error: Error?) {
		do {
			return (try await work(), nil)
		} catch {
			return ([], error)
		}
	}

	private static func friendlyMessage(for error: Error) -> String {
		(error as? LocalizedError)?.errorDescription ?? error.localizedDescription
	}

	private static func emptyMessage(for kind: FeedSearchResult.Kind) -> String {
		switch kind {
		case .podcast: return "没有找到匹配的播客。"
		case .reddit: return "没有找到匹配的 Reddit 版块。"
		case .youtube: return "没有找到匹配的 YouTube 频道。"
		case .website: return "没有找到匹配的网站。"
		}
	}

	// MARK: - 订阅

	/// completion:订阅流程走完后调一次(成败都调),失败时带上适合给用户看的错误。
	/// 试读页(Phase B)靠它刷新右上角按钮、并**由它自己弹错误** ——
	/// 试读页开着的时候本页被盖在下面,从这里 presentError 可能静默失败(独立审查建议 4)。
	/// 发现页自己调的时候不传 completion,错误照旧从本页弹。
	private func subscribe(to result: FeedSearchResult, completion: ((Error?) -> Void)? = nil) {

		guard let container else {
			presentError(NSError(domain: "FeedDiscovery", code: 0, userInfo: [
				NSLocalizedDescriptionKey: "还没有可用的账户,无法订阅。"]))
			completion?(nil)
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
			completion?(nil)
			return
		}

		if account.hasFeed(withURL: result.feedURL) {
			presentError(AccountError.createErrorAlreadySubscribed)
			completion?(nil)
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
			guard let self else {
				// 本页已被销毁也要把"流程走完了"告诉调用方(试读页可能还活着)
				completion?(nil)
				return
			}

			// ⚠️ 状态清理必须在调 completion **之前**(独立审查必修 1):
			// 试读页的 completion 会来查 subscribingURLs 刷新按钮,
			// 先调 completion 它就会读到"还在订阅中",转圈永远停不下来。
			self.subscribingURLs.remove(result.feedURL)

			switch createResult {
			case .success(let feed):
				self.subscribedURLs.insert(result.feedURL)
				self.tableView.reloadData()
				// [管理] 2026-08-12:新订阅的源排到列表最上面(用户要求)。
				// 这一步和下面"不发 .UserDidAddFeed"没有冲突——那条通知管的是
				// "要不要导航跳过去",这里管的是"排在哪",两件事分开做。
				FeedOrderStore.shared.placeNewFeedAtTop(feedID: feed.feedID)
				// ⚠️ 这里刻意**不发** .UserDidAddFeed(2026-07-29 用户要求):
				// 那个通知会被 SceneCoordinator 接住,带着导航跳进新源的文章列表 ——
				// 而用户订阅完想留在本页继续挑。首页列表的刷新不靠它:
				// 账户加完源自己会发 .ChildrenDidChange,协调器听到就重建首页列表。
				Self.logger.info("[发现] 订阅成功:\(result.feedURL)")
				completion?(nil)
			case .failure(let error):
				// 失败时也必须刷新,把转圈换回加号 —— 否则那一行会永远转下去
				self.tableView.reloadData()
				Self.logger.error("[发现] 订阅失败:\(result.feedURL) — \(error.localizedDescription)")
				// Reddit 的失败要换成说实话的提示:上游把 429(限流)也报成
				// 「找不到这个 feed」,会让人去反复检查根本没错的版块名。
				let displayError: Error
				if result.kind == .reddit {
					let name = RedditFeedBuilder.subredditName(from: result.feedURL) ?? "该版块"
					displayError = RedditFeedBuilder.friendlyError(for: error, subreddit: name)
				} else {
					displayError = error
				}
				if let completion {
					// 试读页发起的:错误交给它自己弹(本页被盖着,弹了也看不见)
					completion(displayError)
				} else {
					self.presentError(displayError)
				}
			}
		}
	}

	// MARK: - 取消订阅(2026-07-29 新增:再点一下绿勾 = 直接取消订阅,不弹确认)

	/// 执行取消订阅:跨账户找到这个源的所有落点,逐个调上游公开接口删掉。
	/// 只用 `removeFeed`(文件夹管理页同款),禁区一行没碰。
	private func unsubscribe(_ result: FeedSearchResult) {

		// 一个源理论上只在一个账户的一个容器里,但"多账户都订了/一源进了多个文件夹"
		// 也都处理掉 —— 全删干净,绿勾才能变回加号
		var targets: [(Account, Feed, [Container])] = []
		for account in AccountManager.shared.activeAccounts {
			if let feed = account.existingFeed(withURL: result.feedURL) {
				targets.append((account, feed, account.existingContainers(withFeed: feed)))
			}
		}

		var pending = targets.reduce(0) { $0 + $1.2.count }
		guard pending > 0 else {
			// 源已经不在了(可能刚在别处删过):刷新一下,让绿勾自己消失
			subscribedURLs.remove(result.feedURL)
			tableView.reloadData()
			return
		}

		// 行尾换成转圈,让用户知道点上了
		unsubscribingURLs.insert(result.feedURL)
		tableView.reloadData()

		BatchUpdate.shared.start()
		var firstError: Error?

		for (account, feed, containers) in targets {
			for container in containers {
				// 回调在主线程(Account.removeFeed 内部走 @MainActor),
				// 所以这个计数器不会有并发问题
				account.removeFeed(feed, from: container) { [weak self] removeResult in
					if case .failure(let error) = removeResult, firstError == nil {
						firstError = error
					}
					pending -= 1
					guard pending == 0, let self else { return }

					BatchUpdate.shared.end()
					self.unsubscribingURLs.remove(result.feedURL)
					self.subscribedURLs.remove(result.feedURL)
					// 不管成败都要刷新:成功了绿勾变回加号;失败了转圈也不能永远转下去
					self.tableView.reloadData()
					if let error = firstError {
						self.presentError(error)
						Self.logger.error("[发现] 取消订阅失败:\(result.feedURL) — \(error.localizedDescription)")
					} else {
						Self.logger.info("[发现] 已取消订阅:\(result.feedURL)")
					}
				}
			}
		}
	}

	/// 🔧 2026-07-24 重写:原来复用上游的 AddFeedFolderViewController(卡片弹出),
	/// 用户实测**列表里只有账户、选不了任何文件夹**。那套界面是给上游自己的添加页
	/// 设计的,被我们改成推入式页面后用 `.currentContext` 弹出,行为不可靠。
	/// 改为自己列数据:只走 Account 公开接口(sortedActiveAccounts / sortedFolders),行为完全归我们管。
	/// 🎛 2026-07-24 深夜:系统动作单换成自绘品牌选单 NNWMenu(文件夹多时卡片内部滚动)。
	/// 每个账户一组:顶层一行 + 它的各个文件夹;多账户时组间有分隔线。点选单外面 = 取消。
	private func showFolderPicker() {

		var sections: [[NNWMenu.Item]] = []
		let accounts = AccountManager.shared.sortedActiveAccounts
		for account in accounts {
			var group: [NNWMenu.Item] = []
			// 顶层(不放进文件夹)。个别同步服务不允许订阅放根层,那就不给这一项
			if !account.behaviors.contains(.disallowFeedInRootFolder) {
				let rootTitle = accounts.count > 1
					? "\(account.nameForDisplay)(不放进文件夹)" : "不放进文件夹"
				group.append(NNWMenu.Item(title: rootTitle, icon: "tray") { [weak self] in
					self?.container = account
					self?.tableView.reloadData()
				})
			}
			for folder in account.sortedFolders ?? [] {
				let title = accounts.count > 1
					? "\(account.nameForDisplay) / \(folder.nameForDisplay)" : folder.nameForDisplay
				group.append(NNWMenu.Item(title: title, icon: "folder") { [weak self] in
					self?.container = folder
					self?.tableView.reloadData()
				})
			}
			if !group.isEmpty { sections.append(group) }
		}

		// 从「订阅到」那一行旁边弹出;万一拿不到那个 cell(理论上不会),就从左下角弹
		let anchor: NNWMenu.Anchor
		if let cell = tableView.cellForRow(at: IndexPath(row: 0, section: 0)) {
			anchor = .view(cell)
		} else {
			anchor = .bottomLeading
		}
		NNWMenu.show(in: self, anchor: anchor, title: "订阅到", sections: sections)
	}

	private var folderLabel: String {
		guard let container else { return "未选择" }
		if let folder = container as? Folder {
			return "\(folder.account?.nameForDisplay ?? "") / \(folder.nameForDisplay)"
		}
		return (container as? Account)?.nameForDisplay ?? "未选择"
	}

	// MARK: - 表格
	//
	// [发现] 2026-08-11:section 0 恒是「订阅到」;从 section 1 起,每个 `groups`
	// 元素占一个 section,标题栏可以点击收起/展开(`viewForHeaderInSection`)。
	// 这一套结构不管是"全部 tab 并行搜出三类"还是"具体 tab / 网址只搜出一类"
	// 都通用——只是分组数量不同,不需要两套表格代码。

	/// 这个 indexPath 指向的到底是什么:一条真实结果,还是一行"这一类没有结果"的说明。
	private enum Row {
		case result(FeedSearchResult)
		case status(String)
	}

	private func row(at indexPath: IndexPath) -> Row? {
		guard indexPath.section >= 1, indexPath.section - 1 < groups.count else { return nil }
		let group = groups[indexPath.section - 1]
		guard group.isExpanded else { return nil }
		if !group.results.isEmpty {
			guard indexPath.row < group.results.count else { return nil }
			return .result(group.results[indexPath.row])
		}
		guard let message = group.statusMessage else { return nil }
		return .status(message)
	}

	override func numberOfSections(in tableView: UITableView) -> Int {
		1 + groups.count
	}

	override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		if section == 0 { return 1 }
		let group = groups[section - 1]
		guard group.isExpanded else { return 0 }
		return group.results.isEmpty ? (group.statusMessage != nil ? 1 : 0) : group.results.count
	}

	override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
		// 分组的头改走自绘 view(见 viewForHeaderInSection),这里只管 section 0。
		section == 0 ? "订阅到" : nil
	}

	override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
		guard section >= 1, section - 1 < groups.count else { return nil }
		let group = groups[section - 1]
		let header = NNWDiscoveryGroupHeaderView()
		header.titleLabel.text = group.results.isEmpty ? group.kind.label : "\(group.kind.label)(\(group.results.count))"
		header.chevron.image = UIImage(systemName: group.isExpanded ? "chevron.down" : "chevron.right")
		header.onTap = { [weak self] in self?.toggleGroup(section: section) }
		return header
	}

	override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
		UITableView.automaticDimension
	}

	/// 点分组标题:收起/展开这一组,只刷新这一个 section。
	private func toggleGroup(section: Int) {
		let index = section - 1
		guard groups.indices.contains(index) else { return }
		groups[index].isExpanded.toggle()
		tableView.reloadSections(IndexSet(integer: section), with: .automatic)
	}

	override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
		// 这段引导文字只在"还没搜过"(groups 是空的)的时候出现,垫在唯一存在的
		// section 0 下面。真的搜过之后,每个分组自己的标题/说明行已经够用了,
		// 不需要再叠一段通用文案。
		guard section == 0, !isSearching, groups.isEmpty else { return nil }
		return "输入关键词会**同时**搜网站 / 播客 / YouTube / Reddit 四类,结果按类别分组显示,\n"
			+ "点分组标题可以收起/展开(网站默认展开,其余三类默认收起)。\n"
			+ "粘一个网址则直接按网址类型处理(YouTube / Reddit / 普通网站),不用先搜索。\n\n"
			+ "Reddit 和 YouTube 需要先在 设置 → 文章 → 订阅发现 API Key 里填好凭据才能搜到结果,\n"
			+ "网站那一类不需要凭据,但走的是一个非官方接口,偶尔搜不到属于正常情况;\n"
			+ "都没配置/都搜不到也不影响播客和粘网址订阅。\n\n"
			+ "点一条结果可以先进去试读;行尾的 ⊕ 才是订阅,绿勾表示已订阅(再点一下取消)。"
	}

	override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {

		let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)

		if indexPath.section == 0 {
			cell.textLabel?.text = "文件夹"
			cell.detailTextLabel?.text = folderLabel
			cell.accessoryType = .disclosureIndicator
			cell.selectionStyle = .default
			return cell
		}

		switch row(at: indexPath) {

		case .status(let message):
			cell.textLabel?.text = message
			cell.textLabel?.numberOfLines = 0
			cell.textLabel?.textColor = .secondaryLabel
			cell.detailTextLabel?.text = nil
			cell.accessoryView = nil
			cell.imageView?.image = nil
			cell.selectionStyle = .none

		case .result(let result):
			cell.textLabel?.text = result.title
			cell.textLabel?.numberOfLines = 2
			cell.detailTextLabel?.text = result.subtitle
			cell.detailTextLabel?.numberOfLines = 1
			cell.detailTextLabel?.textColor = .secondaryLabel
			cell.accessoryView = accessoryView(for: result)
			configureIcon(on: cell, for: result)

			// 已经订阅过的:文字调淡 + 绿勾,一眼认出"这个已经有了"。
			// (T30 时代"点不动"是因为点行=订阅;Phase B 起点行=试读,
			//  已订阅的源也可以进去看,所以行恢复可点,"已订阅"只由绿勾和淡字表达。)
			cell.selectionStyle = .default
			cell.textLabel?.textColor = isAlreadySubscribed(result) ? .secondaryLabel : .label

		case .none:
			break
		}

		return cell
	}

	/// [外观] 把每个 cell 的底色也刷成暖纸色,消除「白卡片 vs 暖背景」的色差,
	/// 并换上和设置页一致的淡暖"药丸"选中效果(取代系统蓝)。
	override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
		AppAppearance.applyPaperStyle(to: cell)
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
			  allResults.contains(where: { $0.iconURL == url }) else {
			return
		}
		tableView.reloadData()
	}

	/// 结果行右侧那个东西。三种状态,同一个位置,一眼看得出下一步能干什么:
	///
	///   ⊕ 加号   —— 还没订阅,点它(或点整行)就订阅
	///   转圈     —— 正在订阅 / 正在取消订阅
	///   ✓ 对勾   —— 已经订阅好了;**再点它一下 = 直接取消订阅**(2026-07-29 加,用户要求不弹确认)
	///
	/// 之所以把状态全部收在这一个地方,是因为改造前「订阅到没到」被
	/// 导航栏的「完成」和行尾的对勾两处同时表达,用户不知道该信哪个。
	/// 现在:**一个地方说一件事。**
	///
	/// [发现] 2026-08-11:结果分组之后,一个"行号"不再能唯一定位一条结果
	/// (同一个行号在不同分组里指的是不同的东西)。原来靠 `button.tag = row`
	/// 定位,现在改成 `UIAction` 闭包直接捕获 `result` 本身,不再需要行号。
	private func accessoryView(for result: FeedSearchResult) -> UIView {

		// 转圈要放在最前面判断:取消订阅进行中时,账户里可能还查得到这个源,
		// 先判断"已订阅"的话就会显示成绿勾,转圈就永远轮不到了
		if subscribingURLs.contains(result.feedURL) || unsubscribingURLs.contains(result.feedURL) {
			let spinner = UIActivityIndicatorView(style: .medium)
			spinner.startAnimating()
			spinner.sizeToFit()
			return spinner
		}

		if isAlreadySubscribed(result) {
			var configuration = UIButton.Configuration.plain()
			configuration.image = UIImage(systemName: "checkmark.circle.fill")
			configuration.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 6)

			let button = UIButton(configuration: configuration)
			button.tintColor = .label
			button.accessibilityLabel = "取消订阅"
			// 点绿勾 = 直接取消订阅。2026-07-29 加;初版有二次确认,用户验收后要求去掉 ——
			// 误触的挽回成本很低:行还在原地,绿勾变回加号,再点一下就订回来了。
			button.addAction(UIAction { [weak self] _ in
				guard let self,
					  !self.subscribingURLs.contains(result.feedURL),
					  !self.unsubscribingURLs.contains(result.feedURL) else { return }
				self.unsubscribe(result)
			}, for: .touchUpInside)
			button.sizeToFit()
			return button
		}

		var configuration = UIButton.Configuration.plain()
		configuration.image = UIImage(systemName: "plus.circle")
		configuration.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 6)

		let button = UIButton(configuration: configuration)
		button.tintColor = .tintColor
		button.accessibilityLabel = "订阅"
		button.addAction(UIAction { [weak self] _ in
			guard let self,
				  !self.subscribedURLs.contains(result.feedURL),
				  !self.subscribingURLs.contains(result.feedURL) else { return }
			self.subscribe(to: result)
		}, for: .touchUpInside)
		button.sizeToFit()
		return button
	}

	override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		tableView.deselectRow(at: indexPath, animated: true)

		if indexPath.section == 0 {
			showFolderPicker()
			return
		}

		// 点整行 = **试读**(Phase B,2026-07-29 起):不订阅,先进去看这个源的文章。
		// 订阅收敛到两个地方:行尾的 ⊕,和试读页右上角的「订阅」按钮。
		// (Phase A 以前"点行=订阅",行为已按用户需求重新分配。)
		guard case .result(let result)? = row(at: indexPath) else { return }
		let preview = FeedPreviewViewController(result: result, subscriptionHandler: self)
		navigationController?.pushViewController(preview, animated: true)
	}
}

// MARK: - 试读页的订阅回调(Phase B)

extension FeedDiscoveryViewController: FeedPreviewSubscriptionHandling {

	func previewIsSubscribed(_ result: FeedSearchResult) -> Bool {
		isAlreadySubscribed(result)
	}

	func previewIsBusy(_ result: FeedSearchResult) -> Bool {
		subscribingURLs.contains(result.feedURL) || unsubscribingURLs.contains(result.feedURL)
	}

	func previewSubscribe(_ result: FeedSearchResult, completion: @escaping (Error?) -> Void) {
		guard !isAlreadySubscribed(result), !subscribingURLs.contains(result.feedURL) else {
			completion(nil)
			return
		}
		subscribe(to: result, completion: completion)
	}
}

// MARK: - 分组标题(可点击收起/展开)

/// [发现] 2026-08-11 新增。「播客(12)」这样一行,带一个方向随展开状态翻转的箭头,
/// 整行可点。不用 `UIButton.Configuration` 拼标题+图标,直接手摆一个
/// `UILabel` + `UIImageView` 更好控制字号/间距,行为也更好预测。
private final class NNWDiscoveryGroupHeaderView: UIView {

	let titleLabel = UILabel()
	let chevron = UIImageView()
	var onTap: (() -> Void)?

	override init(frame: CGRect) {
		super.init(frame: frame)

		titleLabel.font = .preferredFont(forTextStyle: .footnote).bold()
		titleLabel.textColor = .secondaryLabel
		titleLabel.adjustsFontForContentSizeCategory = true

		chevron.tintColor = .tertiaryLabel
		chevron.contentMode = .scaleAspectFit

		let stack = UIStackView(arrangedSubviews: [titleLabel, chevron])
		stack.axis = .horizontal
		stack.alignment = .center
		stack.spacing = 4
		stack.translatesAutoresizingMaskIntoConstraints = false
		addSubview(stack)

		NSLayoutConstraint.activate([
			stack.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
			stack.trailingAnchor.constraint(lessThanOrEqualTo: layoutMarginsGuide.trailingAnchor),
			// 上下都钉住(不是只用 centerY):`heightForHeaderInSection` 用的是
			// automaticDimension,得靠这两条约束把内容高度一路传到这个 view 的高度上。
			stack.topAnchor.constraint(equalTo: topAnchor, constant: 10),
			stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4)
		])

		isUserInteractionEnabled = true
		addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { fatalError("不从故事板加载") }

	@objc private func tapped() {
		onTap?()
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

// 📌 原来这里有一个 AddFeedFolderViewControllerDelegate 扩展(接上游选择器的回调)。
// 2026-07-24 选择器改为自绘动作单后不再需要;也**不再写 AddFeedDefaultContainer** ——
// 按用户要求,本页每次打开都默认顶层,不记忆上次的选择。

#endif
