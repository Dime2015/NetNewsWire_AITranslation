//
//  FeedPreviewViewController.swift
//  NetNewsWire
//
//  [发现] 本 fork 新增,上游没有这个文件。试读 Phase B(2026-07-29)。
//
//  「试读」页:**不订阅**,先看这个源最近的文章,再决定订不订。
//
//  ## 为什么完全不碰账户
//  文章是当场抓 feed → 上游解析器(RSParser)解出来 → 凭空造成内存 Article 的,
//  从头到尾不落库、不创建 Feed、不发任何账户通知 —— 禁区零接触。
//  Article 是纯数据对象(公开构造器),渲染/排版用的字段(标题/正文/链接/日期)都是真的,
//  只有 accountID 是假值("nnw-preview"),所以 article.feed 恒为 nil ——
//  渲染层对此是容错的(考古确认:articleSubstitutions 里全是 `article.feed?.xxx ?? ""`)。
//
//  ## 订阅状态为什么要问发现页
//  账户、选中的文件夹、订阅流程(含转圈/绿勾状态)全部住在发现页一处。
//  预览页只通过 FeedPreviewSubscriptionHandling 问结果、发指令,
//  不维护第二份"订没订"的判断 —— 两处判断迟早打架(T30 那次的教训)。
//

#if os(iOS)

import UIKit
import Account	// [翻译] 身份映射要查"这个源是不是已经订阅了"(见 makeArticles)
import Articles
import RSParser
import os

/// 预览页对「订阅」的全部了解都来自发现页(见文件头注释)。
@MainActor protocol FeedPreviewSubscriptionHandling: AnyObject {

	/// 这个源现在是不是已经订阅了(当场问账户,和结果行绿勾同一个判断)
	func previewIsSubscribed(_ result: FeedSearchResult) -> Bool

	/// 是不是正在订阅/取消订阅中(预览页要显示转圈)
	func previewIsBusy(_ result: FeedSearchResult) -> Bool

	/// 订阅它(订到发现页当前选中的文件夹)。完成后回调 —— **成败都必须调**,
	/// 预览页靠它把转圈换回真实状态。失败时带上适合给用户看的错误,
	/// 由**预览页自己弹** —— 发现页此刻被盖在下面,从那边弹可能静默失败。
	func previewSubscribe(_ result: FeedSearchResult, completion: @escaping (Error?) -> Void)
}

@MainActor final class FeedPreviewViewController: UITableViewController {

	private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "FeedPreview")

	private let result: FeedSearchResult
	private weak var subscriptionHandler: FeedPreviewSubscriptionHandling?

	/// 凭空造的内存文章(见 makeArticles),没有一篇进过数据库
	private var articles = [Article]()

	/// 正在抓取/解析的任务。离开页面或下拉重试时把上一次的掐掉。
	private var loadTask: Task<Void, Never>?

	/// 加载中/失败/空列表时,表格中央显示的那行字。nil = 正常显示列表。
	private var statusText: String? {
		didSet { updateBackground() }
	}

	/// - Parameter subscriptionHandler: 订阅动作的处理方(发现页)。
	///   **从文章页的头像进来时传 nil** —— 那条路的源必然已订阅,右上角只有齿轮,没有订阅按钮。
	init(result: FeedSearchResult, subscriptionHandler: FeedPreviewSubscriptionHandling?) {
		self.result = result
		self.subscriptionHandler = subscriptionHandler
		super.init(style: .plain)
	}

	required init?(coder: NSCoder) {
		fatalError("这一页不走 storyboard")
	}

	deinit {
		loadTask?.cancel()
	}

	override func viewDidLoad() {
		super.viewDidLoad()

		title = result.title
		navigationItem.largeTitleDisplayMode = .never

		// [外观] 和发现页一致的暖纸风
		AppAppearance.applyPaperStyle(to: tableView)
		tableView.separatorStyle = .none

		refreshControl = UIRefreshControl()
		refreshControl?.addTarget(self, action: #selector(reloadRequested), for: .valueChanged)

		// [翻译] 标题译文入库时刷新列表 —— 已订阅且开了「标题翻译」的源,
		// 本页的行标题和主时间线一样显示中文(见 cellForRow)
		NotificationCenter.default.addObserver(self, selector: #selector(titleTranslationDidUpdate(_:)),
											   name: .nnwTitleTranslationDidUpdate, object: nil)

		updateNavButtons()
		load()
	}

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		// 从文章页的头像进来时,下面盖着的是带工具栏的文章页 —— 本页没有工具栏,收起来。
		// ⚠️ 如实说明(独立审查纠正过):发现页语境里没人管理工具栏,它的可见性是从
		// 主列表页继承来的 —— 这一句在那条路上是"主动藏一条空栏"(观感更好),
		// pop 回发现页后保持隐藏,直到回主列表页被它的 viewWillAppear 恢复。
		navigationController?.setToolbarHidden(true, animated: animated)
		// 回到本页时刷一下右上角(订阅状态/齿轮可能变了,刷新零成本)
		updateNavButtons()
	}

	@objc private func titleTranslationDidUpdate(_ note: Notification) {
		tableView.reloadData()
	}

	// MARK: - 右上角:订阅状态(发现页进来才有)+ 齿轮(已订阅的源才有)

	private func updateNavButtons() {
		var items = [UIBarButtonItem]()

		// 订阅按钮三态,和结果行行尾同一套语义。处理方是发现页;从文章页进来没有它。
		if let handler = subscriptionHandler {
			if handler.previewIsBusy(result) {
				let spinner = UIActivityIndicatorView(style: .medium)
				spinner.startAnimating()
				items.append(UIBarButtonItem(customView: spinner))
			} else if handler.previewIsSubscribed(result) {
				let item = UIBarButtonItem(title: "已订阅", style: .plain, target: nil, action: nil)
				item.isEnabled = false
				items.append(item)
			} else {
				items.append(UIBarButtonItem(title: "订阅", style: .done,
											 target: self, action: #selector(subscribeTapped)))
			}
		}

		// 齿轮 = 源的简介/设置页(标题翻译、阅读视图等开关都在那)。
		// 设置挂在真实 Feed 上,所以只有已订阅的源才有;发现页里刚订阅完它也会出现。
		if subscribedFeed() != nil {
			let gear = UIBarButtonItem(image: UIImage(systemName: "gearshape"),
									   style: .plain, target: self, action: #selector(gearTapped))
			gear.accessibilityLabel = "源信息与设置"
			items.append(gear)
		}

		navigationItem.rightBarButtonItems = items
	}

	/// 这个源要是已经订阅了,给出真实的 Feed(齿轮和身份映射都靠它)
	private func subscribedFeed() -> Feed? {
		for account in AccountManager.shared.activeAccounts {
			if let feed = account.existingFeed(withURL: result.feedURL) {
				return feed
			}
		}
		return nil
	}

	/// 打开源的简介/设置页。装配照抄 SceneCoordinator.showFeedInspector(for:) ——
	/// 那边绑着协调器,这里独立弹一张同样的 formSheet。
	@objc private func gearTapped() {
		guard let feed = subscribedFeed() else { return }
		guard let nav = UIStoryboard.inspector.instantiateViewController(
				identifier: "FeedInspectorNavigationViewController") as? UINavigationController,
			  let inspector = nav.topViewController as? FeedInspectorViewController else {
			return
		}
		nav.modalPresentationStyle = .formSheet
		nav.preferredContentSize = FeedInspectorViewController.preferredContentSizeForFormSheetDisplay
		inspector.feed = feed
		present(nav, animated: true)
	}

	@objc private func subscribeTapped() {
		guard let handler = subscriptionHandler,
			  !handler.previewIsBusy(result),
			  !handler.previewIsSubscribed(result) else {
			return
		}
		handler.previewSubscribe(result) { [weak self] error in
			guard let self else { return }
			self.updateNavButtons()
			if let error {
				self.presentError(error)
			}
		}
		// 立刻切到转圈,不等回调 —— 订阅要联网,慢的时候要几秒
		updateNavButtons()
	}

	// MARK: - 抓取与解析

	@objc private func reloadRequested() {
		load()
	}

	private func load() {

		loadTask?.cancel()
		if articles.isEmpty {
			statusText = "正在加载…"
		}

		let feedURL = result.feedURL

		loadTask = Task { [weak self] in
			do {
				guard let url = URL(string: feedURL) else {
					throw FeedPreviewError.badURL
				}
				let data = try await Self.fetch(url)

				// 上游解析器,和正式订阅走的是同一套(T30 排查时实测过 canParse 这条路)
				guard let parsed = try await FeedParser.parse(ParserData(url: feedURL, data: data)) else {
					throw FeedPreviewError.notAFeed
				}

				// 任务被取消(用户退出了页面/又下拉了一次)就什么都别做
				guard !Task.isCancelled, let self else { return }

				self.articles = Self.makeArticles(from: parsed, feedURL: feedURL)
				self.statusText = self.articles.isEmpty ? "这个源目前没有文章" : nil
				self.refreshControl?.endRefreshing()
				self.tableView.reloadData()
				Self.logger.info("[发现] 试读加载成功:\(feedURL),共 \(self.articles.count) 篇")

			} catch {
				guard !Task.isCancelled, let self else { return }
				self.refreshControl?.endRefreshing()
				// 已经有内容时(下拉刷新失败)别往背景垫提示字 —— 会从行底下露出来,
				// 而且错误卡片本身已经是一重反馈了(独立审查建议 7)
				if self.articles.isEmpty {
					self.statusText = "加载失败,下拉可重试"
				}
				self.tableView.reloadData()
				Self.logger.error("[发现] 试读加载失败:\(feedURL) — \(error.localizedDescription)")
				self.presentError(error)
			}
		}
	}

	/// 和 WebsiteFeedResolver.fetch 同款:带上 app 自己的 User-Agent(L33),非 2xx 一律当失败。
	private static func fetch(_ url: URL) async throws -> Data {

		var request = URLRequest(url: url)
		request.timeoutInterval = 20
		if let userAgent = Bundle.main.object(forInfoDictionaryKey: "UserAgent") as? String {
			request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
		}

		let (data, response) = try await URLSession.shared.data(for: request)
		guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
			throw FeedPreviewError.serverError
		}
		return data
	}

	/// 把解析出来的条目变成**凭空的内存文章**(要点见文件头注释)。
	private static func makeArticles(from parsed: ParsedFeed, feedURL: String) -> [Article] {

		// [翻译] 身份映射(T35 尾巴,2026-07-30):这个源要是**已经订阅了**,就用真实的
		// 账户ID/源ID 造内存文章 —— 标题翻译的开关与缓存直接命中、article.feed 能解析出
		// 真源(渲染器显示源名/图标)、正文译文缓存和主阅读页同键(articleID 一致)。
		// 没订阅的照旧用 "nnw-preview" 假身份,一切行为不变。
		var accountID = "nnw-preview"
		var feedID = feedURL
		for account in AccountManager.shared.activeAccounts {
			if let feed = account.existingFeed(withURL: feedURL) {
				accountID = account.accountID
				feedID = feed.feedID
				break
			}
		}

		let articles = parsed.items.map { item -> Article in
			let articleID = Article.calculatedArticleID(feedID: feedID, uniqueID: item.uniqueID)
			let status = ArticleStatus(articleID: articleID,
									   read: false,
									   starred: false,
									   dateArrived: item.datePublished ?? Date())
			return Article(accountID: accountID,
						   articleID: articleID,
						   feedID: feedID,
						   uniqueID: item.uniqueID,
						   title: item.title,
						   contentHTML: item.contentHTML,
						   contentText: item.contentText,
						   markdown: item.markdown,
						   url: item.url,
						   externalURL: item.externalURL,
						   summary: item.summary,
						   imageURL: item.imageURL,
						   datePublished: item.datePublished,
						   dateModified: item.dateModified,
						   authors: nil,
						   status: status)
		}

		// 新的在上;最多 100 条 —— 试读不需要全部历史
		return Array(articles.sorted { $0.logicalDatePublished > $1.logicalDatePublished }.prefix(100))
	}

	// MARK: - 表格

	override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		articles.count
	}

	override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {

		// 列表最多 100 行,要走复用(发现页不复用是因为结果通常只有几条)。
		// .subtitle 样式没法 register class,只能"取不到再建"这个经典写法。
		let cell = tableView.dequeueReusableCell(withIdentifier: "PreviewCell")
			?? UITableViewCell(style: .subtitle, reuseIdentifier: "PreviewCell")
		// [翻译] 已订阅且开了「标题翻译」的源(身份映射后判断得出来):行标题显示中文,
		// 和主时间线一致;没翻的这里顺带入队,翻完靠通知刷新(见 viewDidLoad)
		let article = NNWTitleTranslationController.shared.displayArticle(for: articles[indexPath.row])

		// 标题/摘要/日期都走上游的格式化器 —— 和正式时间线同一套截断与清洗规则
		let title = ArticleStringFormatter.shared.truncatedTitle(article)
		let summary = ArticleStringFormatter.shared.truncatedSummary(article)
		let date = ArticleStringFormatter.shared.dateString(article.logicalDatePublished)

		cell.textLabel?.text = title.isEmpty ? (summary.isEmpty ? "(无标题)" : summary) : title
		cell.textLabel?.numberOfLines = 2

		cell.detailTextLabel?.numberOfLines = 2
		cell.detailTextLabel?.textColor = .secondaryLabel
		if title.isEmpty || summary.isEmpty {
			cell.detailTextLabel?.text = date
		} else {
			cell.detailTextLabel?.text = "\(date) · \(summary)"
		}

		cell.accessoryType = .disclosureIndicator
		return cell
	}

	// [外观] cell 底色刷成暖纸色(和发现页同一手)
	override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
		AppAppearance.applyPaperStyle(to: cell)
	}

	override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		tableView.deselectRow(at: indexPath, animated: true)
		let article = articles[indexPath.row]
		let articlePage = FeedPreviewArticleViewController(article: article, iconURL: result.iconURL)
		navigationController?.pushViewController(articlePage, animated: true)
	}

	// MARK: - 背景提示文字

	private func updateBackground() {
		if let statusText {
			let label = UILabel()
			label.text = statusText
			label.textAlignment = .center
			label.numberOfLines = 0
			label.textColor = .secondaryLabel
			label.font = .preferredFont(forTextStyle: .subheadline)
			tableView.backgroundView = label
		} else {
			tableView.backgroundView = nil
		}
	}
}

// MARK: - 错误

private enum FeedPreviewError: LocalizedError {

	case badURL
	case notAFeed
	case serverError

	// 故意不用 NSLocalizedString,理由同 TranslationError(别碰上游的 xcstrings 大文件)
	var errorDescription: String? {
		switch self {
		case .badURL:
			return "这条结果的地址不是合法网址。"
		case .notAFeed:
			return "抓回来的内容不是能识别的 feed 格式。"
		case .serverError:
			return "对方服务器没有正常返回内容,稍后可再试。"
		}
	}
}

#endif
