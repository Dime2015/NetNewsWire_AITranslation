//
//  NNWGlobalSearchViewController.swift
//  NetNewsWire — AI 翻译 fork
//
//  [阅读档] 全局搜索的独立 modal 页面(方案 D,2026-07-28)。
//  本 fork 新增文件,上游没有。
//
//  ## 为什么是一个从下往上弹出的独立页面
//
//  之前的做法(方案 B)是:点首页放大镜 → 先切到「全部未读」→ 在那一页上激活系统搜索框。
//  它有两个用户明确不满意的地方:进搜索前界面会先跳一下「全部未读」;
//  退出搜索后也停在「全部未读」,回不到点搜索时所在的位置。
//
//  而「回到来处」这件事在分栏导航里是一堵实测撞不穿的墙:
//  iPhone 的 collapsed 分栏下 `show(.primary)` 调用无效(7 次日志实证,见 NOTES-lessons L92)。
//
//  modal 天然绕开这一切:它**盖在**当前页面上,关掉就露出原页面 ——
//  「原来在哪,就回哪」不需要任何导航代码,是 dismiss 自带的。
//
//  ## 数据链路(刻意不碰主时间线)
//
//  上游的搜索(coordinator.searchArticles)是"把主时间线整个换成搜索结果"的模式,
//  搜完还要靠 beginSearching/endSearching 存现场、还现场 —— 正是那套机制把我们
//  拖进了上面那堵墙。这一页完全绕开它:直接用上游的 SearchFeedDelegate
//  (全库全文检索,FTS)取一份结果数组,自己显示。主时间线从头到尾不知道有搜索这回事。
//
//  ## 点结果怎么跳文章
//
//  复用上游"点系统通知打开任意一篇文章"的现成配方(SceneCoordinator.handleReadArticle):
//  先关掉本页,再让 coordinator 走 discloseFeed + selectArticleInCurrentFeed。
//  详见 SceneCoordinator.nnwOpenSearchResult(_:) 的注释。
//

#if os(iOS)

import UIKit
import Account
import Articles
import Images

final class NNWGlobalSearchViewController: UITableViewController {

	/// 点结果跳文章要靠它。由 SceneCoordinator.nnwShowGlobalSearch() 在弹出本页时注入。
	weak var coordinator: SceneCoordinator?

	/// 「该列表」这一档能搜的范围(当前文章列表里那些文章的 ID)。
	///
	/// - 从**文章列表页**的放大镜进来:有值 → 顶部出现「该列表 / 全部文章」两档,默认「该列表」
	/// - 从**首页**的放大镜进来:nil(没有"当前列表"这回事)→ 不显示切换条,只搜全部
	///
	/// 由 `SceneCoordinator.nnwShowGlobalSearch(restrictedToCurrentTimeline:)` 注入。
	var timelineArticleIDs: Set<String>?

	/// 搜索范围。两档的语义和上游那条系统范围条一致(Here / All Articles)。
	private enum Scope: Int {
		case timeline = 0	// 该列表
		case global = 1		// 全部文章
	}

	private var scope: Scope = .global

	/// 顶部那条范围切换控件。
	///
	/// ## ⚠️ 为什么是我们自己的分段控件,而不是系统搜索栏自带的范围条
	///
	/// 系统那条范围条**只在 `.stacked` 摆法下渲染**(日志实证:`.integratedButton` 下
	/// 状态全对也不画)。而要用 `.stacked` 就得在搜索进出时切摆法 ——
	/// **切摆法 = 让导航栏变高变矮**,下游一连串按安全区算坐标的自绘元素全得跟着重排,
	/// 用户真机(iOS 27 beta)上表现为"退出搜索后顶栏没拆干净、标题卡在半空"。
	/// 修了两轮仍未干净,而且开发机测不到那个系统版本。
	///
	/// 于是换成这条普通的 `UISegmentedControl`:**完全由我们自己摆放和绘制**,
	/// 不牵动导航栏高度,和 UIKit 的搜索栏排版机制彻底脱钩。
	/// (L92 的老规矩:修到第三版还不好,就该消掉这个机制的前提。)
	private lazy var scopeControl: UISegmentedControl = {
		let control = UISegmentedControl(items: ["该列表", "全部文章"])
		control.selectedSegmentIndex = Scope.timeline.rawValue
		control.addTarget(self, action: #selector(scopeChanged), for: .valueChanged)
		return control
	}()

	/// 装着切换控件的分区头。**只造一次** —— 表格每次要头视图都还这一个,
	/// 不然每次 reloadData 都新建一个容器、把控件搬来搬去,白费事还容易出岔子。
	private lazy var scopeHeaderView: UIView = {
		let container = UIView()
		container.backgroundColor = AppAppearance.paperBackground
		scopeControl.translatesAutoresizingMaskIntoConstraints = false
		container.addSubview(scopeControl)
		NSLayoutConstraint.activate([
			scopeControl.leadingAnchor.constraint(equalTo: container.layoutMarginsGuide.leadingAnchor),
			scopeControl.trailingAnchor.constraint(equalTo: container.layoutMarginsGuide.trailingAnchor),
			scopeControl.centerYAnchor.constraint(equalTo: container.centerYAnchor),
		])
		return container
	}()

	/// 有没有"当前列表"可搜 —— 决定顶部那条切换控件显不显示。
	private var canSwitchScope: Bool { timelineArticleIDs != nil }

	private let searchController = UISearchController(searchResultsController: nil)

	/// 当前显示的结果(已按时间倒序排好)。
	private var results = [Article]()

	/// 正在跑的搜索任务。新输入来了就取消旧的,防止旧结果盖掉新结果(和订阅发现页同一套路)。
	private var searchTask: Task<Void, Never>?

	/// 上一次真正执行了搜索的词 —— 同一个词不重复查(照抄上游 searchArticles 的去重)。
	private var lastQuery = ""

	/// 键盘只在第一次进入时自动弹出;之后(比如从文章跳转失败退回来)不再骚扰。
	private var didAutoFocusSearchBar = false

	/// 提示文字(输入太短 / 没有结果)。放在列表的 backgroundView 上,有结果时清掉。
	private let hintLabel = UILabel()

	// MARK: - 生命周期

	init() {
		// plain 风格:结果行通铺整行宽,和主时间线的观感一致(不是设置页那种圆角分组)
		super.init(style: .plain)
	}

	required init?(coder: NSCoder) {
		fatalError("这一页只从代码创建,不走 storyboard")
	}

	override func viewDidLoad() {
		super.viewDidLoad()

		// 从列表页进来时默认搜「该列表」,从首页进来时只有「全部文章」可搜
		scope = canSwitchScope ? .timeline : .global
		title = canSwitchScope ? "搜索文章" : "搜索全部文章"

		view.backgroundColor = AppAppearance.paperBackground
		AppAppearance.applyPaperStyle(to: tableView)

		// 右上角一个明确的「取消」。pageSheet 本身支持下拉关闭,这个按钮是给不知道能下拉的人的。
		navigationItem.rightBarButtonItem = UIBarButtonItem(
			title: "取消", style: .plain, target: self, action: #selector(cancelTapped))

		// 搜索框:挂在导航条上(和订阅发现页同一做法)
		searchController.obscuresBackgroundDuringPresentation = false
		searchController.hidesNavigationBarDuringPresentation = false
		// 搜索框自己的「取消」不要 —— 右上角已经有一个,两个取消会让人不知道点哪个
		searchController.automaticallyShowsCancelButton = false
		searchController.searchResultsUpdater = self
		searchController.searchBar.placeholder = canSwitchScope ? "搜索文章" : "搜索全部订阅源的文章"
		searchController.searchBar.autocapitalizationType = .none
		navigationItem.searchController = searchController
		navigationItem.hidesSearchBarWhenScrolling = false
		if #available(iOS 26, *) {
			// iOS 26 上显式钉死「标题下面一条」的经典摆法,不赌系统默认值(L79 的教训:摆法要显式设)
			navigationItem.preferredSearchBarPlacement = .stacked
		}
		definesPresentationContext = true

		tableView.register(NNWGlobalSearchResultCell.self,
						   forCellReuseIdentifier: NNWGlobalSearchResultCell.reuseIdentifier)
		tableView.rowHeight = UITableView.automaticDimension
		tableView.estimatedRowHeight = 96
		// 一滚动就收键盘,不然键盘挡半屏结果
		tableView.keyboardDismissMode = .onDrag

		hintLabel.font = UIFont.preferredFont(forTextStyle: .subheadline)
		hintLabel.textColor = .secondaryLabel
		hintLabel.textAlignment = .center
		hintLabel.numberOfLines = 0
		showHint("输入至少 3 个字开始搜索")
	}

	/// 换了搜索范围 → 用同一个词立刻重搜一遍。
	@objc private func scopeChanged() {
		scope = Scope(rawValue: scopeControl.selectedSegmentIndex) ?? .global
		lastQuery = ""		// 清掉去重记录,否则同一个词换了范围也不会重搜
		scheduleSearch(searchController.searchBar.text ?? "")
	}

	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)

		// 下拉关闭也要走"先退搜索态"的路(见 closePage 的注释),挂上代理才能收到下拉通知
		navigationController?.presentationController?.delegate = self

		// 自动弹键盘。**必须在 viewDidAppear** —— 页面完全上屏之后激活搜索框才可靠,
		// 早了就是 L79 记录的那一族排版事故。这也是上游 showSearchAll() 用的同一对调用。
		if !didAutoFocusSearchBar {
			didAutoFocusSearchBar = true
			searchController.isActive = true
			searchController.searchBar.becomeFirstResponder()
		}
	}

	override func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)
		// 页面要走了,还在路上的搜索就别跑了
		searchTask?.cancel()
	}

	/// 统一的关页出口。**这三行的顺序是有讲究的,别动**(死因见 NOTES-lessons L93)。
	///
	/// ### ① 为什么不能直接 `self.dismiss`
	///
	/// 本页设了 `definesPresentationContext = true`,搜索框激活期间,激活着的
	/// UISearchController 就是"self 名下 present 出去的东西" —— 而 UIKit 的 `dismiss`
	/// 优先收掉自己名下的 presented VC。于是 `self.dismiss` 只会退掉搜索态,页面还在:
	/// 「取消」要点两次;点结果则页面不关、跳转发生在它背后。
	/// 所以要**从弹出者那头**发起 dismiss,一次把整摞收干净。
	///
	/// ### ② 为什么"弹出者"必须在退搜索态**之前**取(2026-07-28 用户实测撞出来的)
	///
	/// 第一版把 `presentingViewController` 写在 `isActive = false` 后面。
	/// 那一刻搜索控制器正在拆除、呈现关系处于中间态,**取到的弹出者就不对了**,
	/// dismiss 发给了错的对象 —— 用户看到的是"点取消后停在一张文章空白页上"。
	/// 现在先把弹出者**捞在手里**(那时关系还是稳的),再退搜索态,最后用手里这个发 dismiss。
	/// 日志实证:改完之后「点取消」「点结果」两条路径,关页后导航栈都稳定停在首页。
	private func closePage(completion: (() -> Void)? = nil) {

		// 顺序第 1 步:趁呈现关系还稳,先把弹出者(分栏控制器)捞在手里
		let presenter = presentingViewController

		// 顺序第 2 步:显式退掉搜索态(顺便避免"搜索控制器在激活状态下被连根拆掉"的警告)
		searchController.isActive = false

		// 顺序第 3 步:用手里这个弹出者发 dismiss —— 此时再去读 presentingViewController 就晚了
		presenter?.dismiss(animated: true, completion: completion)
	}

	@objc private func cancelTapped() {
		closePage()
	}

	// MARK: - 搜索

	/// 输入变化 → 掐头去尾 → 门槛检查 → 防抖 250 毫秒 → 全库检索。
	private func scheduleSearch(_ rawText: String) {

		let query = rawText.trimmingCharacters(in: .whitespacesAndNewlines)

		// 不管这次输入最终搜不搜,都先把上一次还在路上的搜索取消掉
		searchTask?.cancel()

		// 门槛:少于 3 个字不搜(照抄上游 searchArticles 的规矩,免得一两个字母搜出整库)
		guard query.count >= 3 else {
			lastQuery = ""
			if !results.isEmpty {
				results = []
				tableView.reloadData()
			}
			showHint("输入至少 3 个字开始搜索")
			return
		}

		// 和上次真正搜过的词一样就不用再搜了
		guard query != lastQuery else { return }

		searchTask = Task { [weak self] in
			// 防抖:等 250 毫秒,期间又有新输入的话本任务已被取消
			try? await Task.sleep(nanoseconds: 250_000_000)
			guard !Task.isCancelled, let self else { return }

			// 用上游那两个全文检索委托(FTS)直接取数,不经过 coordinator,也就不会动主时间线:
			// - 「全部文章」= SearchFeedDelegate:搜全部账户的全部文章
			// - 「该列表」  = SearchTimelineFeedDelegate:把范围限定在给定的文章 ID 集合里,
			//                正是上游那条系统范围条「Here」档用的同一个东西
			// (本类是 UIViewController,Task 继承主线程上下文,满足取数接口的主线程要求。)
			let found: Set<Article>
			if self.scope == .timeline, let ids = self.timelineArticleIDs {
				found = await SearchTimelineFeedDelegate(searchString: query, articleIDs: ids).fetchArticlesAsync()
			} else {
				found = await SearchFeedDelegate(searchString: query).fetchArticlesAsync()
			}
			guard !Task.isCancelled else { return }

			self.lastQuery = query
			// 固定按时间倒序(最新的在最上面),不跟随时间线的排序设置 —— 搜索场景要的就是"最近提过这事的文章"
			self.results = Array(found).sortedByDate(.orderedDescending)
			self.tableView.reloadData()

			if self.results.isEmpty {
				let where_ = (self.scope == .timeline && self.canSwitchScope) ? "该列表里" : ""
				self.showHint("\(where_)没有找到「\(query)」")
			} else {
				self.hideHint()
			}
		}
	}

	private func showHint(_ text: String) {
		hintLabel.text = text
		tableView.backgroundView = hintLabel
	}

	private func hideHint() {
		tableView.backgroundView = nil
	}

	// MARK: - 列表

	override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		return results.count
	}

	/// 范围切换条做成**分区头**而不是表头 —— plain 风格下分区头会自动吸顶,
	/// 滚结果的时候它一直在,不会滑走。没有"当前列表"可搜时(从首页进来)整条不出现。
	override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
		return canSwitchScope ? scopeHeaderView : nil
	}

	override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
		return canSwitchScope ? 48 : 0
	}

	override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		let cell = tableView.dequeueReusableCell(
			withIdentifier: NNWGlobalSearchResultCell.reuseIdentifier, for: indexPath) as! NNWGlobalSearchResultCell
		if indexPath.row < results.count {
			cell.configure(with: results[indexPath.row])
		}
		return cell
	}

	override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
		// 纸色底 + 药丸选中态,全 app 统一(AppAppearance 的规矩:每个 cell 都要在这里刷一遍)
		AppAppearance.applyPaperStyle(to: cell)
	}

	override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		tableView.deselectRow(at: indexPath, animated: true)
		guard indexPath.row < results.count else { return }
		let article = results[indexPath.row]

		// 关掉本页(closePage 会先退搜索态、连键盘一起收),关完再跳文章 ——
		// 跳转的推入动画不能和 dismiss 动画抢时间
		let coordinator = self.coordinator
		closePage {
			coordinator?.nnwOpenSearchResult(article)
		}
	}
}

// MARK: - 输入回调

extension NNWGlobalSearchViewController: UISearchResultsUpdating {

	/// 系统在搜索框文字每次变化时调这里(边打字边搜,和上游时间线搜索同一交互)。
	func updateSearchResults(for searchController: UISearchController) {
		scheduleSearch(searchController.searchBar.text ?? "")
	}
}

// MARK: - 下拉关闭

extension NNWGlobalSearchViewController: UIAdaptivePresentationControllerDelegate {

	/// 用户下拉关页(不走「取消」按钮)时,同样先把搜索态退掉,
	/// 别让搜索控制器在激活状态下被连根拆掉。只有用户手势会触发这里,代码 dismiss 不会。
	func presentationControllerWillDismiss(_ presentationController: UIPresentationController) {
		searchController.isActive = false
	}
}

// MARK: - 结果行

/// 一行搜索结果,长相尽量贴近主时间线的文章行:
/// 左边 favicon,顶行「源名 + 日期」,下面加粗标题,再下面两行摘要。
/// 字体、颜色、尺寸全部取自 TimelineStyle(时间线唯一的样式来源),保证两边观感一致。
final class NNWGlobalSearchResultCell: UITableViewCell {

	static let reuseIdentifier = "NNWGlobalSearchResultCell"

	private let iconView = UIImageView()
	private let feedLabel = UILabel()
	private let dateLabel = UILabel()
	private let titleLabel = UILabel()
	private let summaryLabel = UILabel()

	override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
		super.init(style: style, reuseIdentifier: reuseIdentifier)

		iconView.contentMode = .scaleAspectFit
		iconView.layer.cornerRadius = TimelineStyle.faviconCornerRadius
		iconView.clipsToBounds = true

		feedLabel.font = TimelineStyle.feedLineFont
		feedLabel.textColor = TimelineStyle.feedLineColor
		// 源名允许被压缩(日期永远完整显示,源名太长就截尾)
		feedLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

		dateLabel.font = TimelineStyle.timeFont
		dateLabel.textColor = TimelineStyle.feedLineColor
		dateLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

		titleLabel.font = TimelineStyle.headlineFont
		titleLabel.textColor = TimelineStyle.headlineColor
		titleLabel.numberOfLines = TimelineStyle.maxTitleLines

		summaryLabel.font = TimelineStyle.bodyFont
		summaryLabel.textColor = TimelineStyle.bodyColor
		summaryLabel.numberOfLines = 2

		for view in [iconView, feedLabel, dateLabel, titleLabel, summaryLabel] {
			view.translatesAutoresizingMaskIntoConstraints = false
			contentView.addSubview(view)
		}

		let padding = TimelineStyle.cellPadding
		let icon = TimelineStyle.faviconDimension
		let layoutGuide = contentView.layoutMarginsGuide

		NSLayoutConstraint.activate([
			iconView.leadingAnchor.constraint(equalTo: layoutGuide.leadingAnchor),
			iconView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: padding.top),
			iconView.widthAnchor.constraint(equalToConstant: icon),
			iconView.heightAnchor.constraint(equalToConstant: icon),

			feedLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: TimelineStyle.faviconMarginRight),
			feedLabel.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),

			dateLabel.leadingAnchor.constraint(greaterThanOrEqualTo: feedLabel.trailingAnchor, constant: TimelineStyle.timeMarginLeft),
			dateLabel.trailingAnchor.constraint(equalTo: layoutGuide.trailingAnchor),
			dateLabel.centerYAnchor.constraint(equalTo: feedLabel.centerYAnchor),

			titleLabel.leadingAnchor.constraint(equalTo: feedLabel.leadingAnchor),
			titleLabel.trailingAnchor.constraint(equalTo: layoutGuide.trailingAnchor),
			titleLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: TimelineStyle.feedLineBottomMargin),

			summaryLabel.leadingAnchor.constraint(equalTo: feedLabel.leadingAnchor),
			summaryLabel.trailingAnchor.constraint(equalTo: layoutGuide.trailingAnchor),
			summaryLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: TimelineStyle.headlineBottomMargin),
			summaryLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -padding.bottom),
		])
	}

	required init?(coder: NSCoder) {
		fatalError("这一行只从代码创建,不走 storyboard")
	}

	func configure(with article: Article) {

		// 文案全部走上游的格式化器(截断、去 HTML、日期规则),和时间线一字不差
		let title = ArticleStringFormatter.shared.truncatedTitle(article)
		let summary = ArticleStringFormatter.shared.truncatedSummary(article)

		feedLabel.text = article.feed?.nameForDisplay ?? ""
		dateLabel.text = ArticleStringFormatter.shared.dateString(article.logicalDatePublished)

		// 没有标题的文章(微博式短文)拿摘要当标题,别让标题行空着
		if title.isEmpty {
			titleLabel.text = summary
			summaryLabel.text = ""
		} else {
			titleLabel.text = title
			summaryLabel.text = summary
		}

		// 图标和首页/时间线走同一个加工入口(透明底补灰底那套),观感统一
		iconView.image = NNWFeedIconStyle.styled(article.iconImage())?.image
	}
}

#endif
