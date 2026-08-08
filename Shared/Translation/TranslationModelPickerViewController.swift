//
//  TranslationModelPickerViewController.swift
//  NetNewsWire — AI 翻译 fork
//
//  设置 → Articles → 翻译模型,点进来的那个列表页。
//
//  纯代码创建,不涉及任何 Storyboard —— Storyboard 是 XML,
//  改它在 git pull upstream 时冲突风险高(CLAUDE.md 第 2 节)。
//
//  这个文件不属于上游 NetNewsWire,是本 fork 新增的。
//
//  ## 2026-08-08 重做(用户第 7 件)
//
//  以前这一页只有 5–10 个模型:一份出厂内置列表,加一个按钮去拉「OpenRouter 翻译榜」。
//  用户的意见很直接 —— **看不到全貌,也不知道贵不贵**。重做成:
//
//  ```
//  搜索框        ← 常驻,400 个模型靠翻是翻不到的
//  余额          ← 读得到才显示(读不到就整段不出现,绝不猜一个数)
//  当前选择
//  精选          ← 全部模型里**按估算价从低到高的前 10**(排除 :free)
//  <厂商 A>      ← 剩下的全部,按厂商分组(实测 58 个组)
//  <厂商 B>
//  ...
//  刷新模型目录
//  ```
//
//  ## 每一行的第二排字是「≈¥0.02/篇(估算)」
//
//  折算规则和它的不确定性写在 `OpenRouterCatalog` 的文件头。
//  **界面上一定要留着"估算"两个字** —— 汇率是写死的,文章长短也会让实际花费上下浮动。
//
//  ## 拉不到数据时页面不会开天窗
//
//  目录有磁盘缓存,开页面先用缓存秒开,再后台刷一遍。
//  一次都没拉成功过(比如离线首开)→ 退回出厂内置的那 5 个,页面照样能选、能保存。
//

#if os(iOS)

import UIKit

@MainActor final class TranslationModelPickerViewController: UITableViewController {

	// MARK: - 页面状态

	private var catalog: [OpenRouterCatalogModel] = []
	private var balance: OpenRouterBalance?
	private var isRefreshing = false
	private var searchText = ""

	/// 待应用的选择;点右上角勾才真正生效(和 API Key 页一致)
	private var pendingModel = ""

	private let searchController = UISearchController(searchResultsController: nil)

	// MARK: - 表格的分区模型(每次刷新重新算一遍,单一出处,不留状态)

	private enum Row {
		case info(String)					// 余额那种纯展示行
		/// 目录里的模型。`showsVendorIcon` = 这一行要不要在名字前面画厂商 logo。
		///
		/// ⚠️ **只有"脱离了厂商分组"的行才画**(精选 / 当前选择 / 搜索结果)——
		/// 那些地方光看短名(`kimi-k3`、`glm-5.2`)根本看不出是谁家的。
		/// 厂商分组**里面**的行不画:上面几厘米就是那家的分组头,再重复一遍是噪音。
		case model(OpenRouterCatalogModel, showsVendorIcon: Bool)
		case plainModel(String)				// 只有 id、没有价格信息的模型(内置列表 / 目录里已消失的当前选择)
		case refresh						// 「刷新模型目录」
	}

	private struct SectionModel {
		let title: String?
		let footer: String?
		let rows: [Row]
		/// 厂商分组才有值 —— 有值的分区头会画一颗字母徽标(见 OpenRouterVendorStyle)。
		/// 其余分区(余额 / 当前选择 / 精选 / 搜索结果)一律 nil,只有文字。
		var vendor: String?

		init(title: String?, footer: String?, rows: [Row], vendor: String? = nil) {
			self.title = title
			self.footer = footer
			self.rows = rows
			self.vendor = vendor
		}
	}

	private var sections: [SectionModel] = []

	// MARK: - 生命周期

	override func viewDidLoad() {
		super.viewDidLoad()

		title = "翻译模型"
		pendingModel = TranslationConfigStore.selectedModel
		catalog = OpenRouterCatalog.cached()

		tableView.register(UITableViewCell.self, forCellReuseIdentifier: "TranslationModelCell")
		tableView.register(UITableViewHeaderFooterView.self, forHeaderFooterViewReuseIdentifier: "VendorHeader")

		// 徽标是**画成图片**的,不会自己跟着深浅色/主题色变 —— 换了就得重画(L105 第 2 条、L119)
		registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (vc: TranslationModelPickerViewController, _) in
			OpenRouterVendorStyle.invalidateBadgeCache()
			vc.tableView.reloadData()
		}
		nnwObserveAccentChanges { [weak self] in
			OpenRouterVendorStyle.invalidateBadgeCache()
			self?.tableView.reloadData()
		}
		AppAppearance.applyPaperStyle(to: tableView)	// [外观] 暖纸风

		// [交互] 左上取消(不改)、右上勾(应用选择并返回),与 API Key 页一致。
		nnwInstallCancelSaveItems(saveAction: #selector(saveTapped), cancelAction: #selector(cancelTapped))

		searchController.searchResultsUpdater = self
		searchController.obscuresBackgroundDuringPresentation = false
		searchController.searchBar.placeholder = "搜索模型或厂商"
		searchController.searchBar.autocapitalizationType = .none
		navigationItem.searchController = searchController
		navigationItem.hidesSearchBarWhenScrolling = false
		// ⚠️ 必须显式要 `.stacked`(标题下面那一条)。iOS 26 默认会把搜索框**吊在屏幕底部**
		// 浮在列表上面(2026-08-08 装机截图看到的),在这种"选一个然后按勾"的页面上很怪。
		// 这里可以放心用 `.stacked` —— L94/L95 那次翻车是**文章列表页**:那一页有头图、
		// 会飞的标题、按安全区算坐标的自绘元素,`.stacked` 会让导航栏忽高忽低把它们带乱。
		// 这一页是个普通的分组表格,导航栏高度变不变都没有下游。**范围不同,结论不能照搬**(L122)。
		navigationItem.preferredSearchBarPlacement = .stacked

		rebuildSections()
		loadBalance()
		// 缓存是空的(第一次进来 / 被系统清了)就立刻拉一次,不用等用户按刷新
		if catalog.isEmpty {
			refreshCatalog(silent: true)
		}
	}

	@objc private func cancelTapped() {
		navigationController?.popViewController(animated: true)		// 不应用,直接退回
	}

	@objc private func saveTapped() {
		TranslationConfigStore.selectedModel = pendingModel			// 应用选择
		// [翻译] 换模型 = 标题缓存键全变:清失败名单并刷新列表,可见行按新模型重翻
		NNWTitleTranslationController.shared.retryAfterConfigChange()
		navigationController?.popViewController(animated: true)
	}

	// MARK: - 拉数据

	private func loadBalance() {
		let baseURL = TranslationConfigStore.baseURL
		guard let apiKey = TranslationConfigStore.apiKey, !apiKey.isEmpty else { return }
		Task { [weak self] in
			let result = await OpenRouterBalanceFetcher.fetch(baseURL: baseURL, apiKey: apiKey)
			guard let self else { return }
			// 读不到就**什么都不显示**(见 OpenRouterBalance 文件头)—— 这里不做任何兜底猜测
			self.balance = result
			self.rebuildSections()
			self.tableView.reloadData()
		}
	}

	/// - Parameter silent: true = 后台悄悄刷(失败不弹窗),用于进页面时的自动刷新。
	private func refreshCatalog(silent: Bool) {

		guard !isRefreshing else { return }
		isRefreshing = true
		rebuildSections()
		tableView.reloadData()

		let baseURL = TranslationConfigStore.baseURL
		Task { [weak self] in
			guard let self else { return }
			do {
				let models = try await OpenRouterCatalog.fetchAll(baseURL: baseURL)
				self.catalog = models
				self.isRefreshing = false
				self.rebuildSections()
				self.tableView.reloadData()
				if !silent {
					let vendors = OpenRouterCatalog.grouped(models).count
					self.showAlert(title: "已更新",
								   message: "拉到 \(models.count) 个模型,来自 \(vendors) 个厂商。")
				}
			} catch {
				// 失败:**一个字节都不动**,原来的目录(缓存或内置)原样留着
				self.isRefreshing = false
				self.rebuildSections()
				self.tableView.reloadData()
				if !silent {
					self.showAlert(title: "刷新失败",
								   message: (error as? LocalizedError)?.errorDescription
									   ?? error.localizedDescription,
								   note: "已保留原有的模型列表,可以继续正常使用。")
				}
			}
		}
	}

	private func showAlert(title: String, message: String, note: String? = nil) {
		let body = note.map { "\(message)\n\n\($0)" } ?? message
		let alert = UIAlertController(title: title, message: body, preferredStyle: .alert)
		alert.addAction(UIAlertAction(title: "好", style: .default))
		present(alert, animated: true)
	}

	// MARK: - 算分区

	/// **表格的唯一出处**:所有状态(搜索词、目录、余额、刷新中)在这里一次性变成分区数组。
	/// 这样 `numberOfSections` / `cellForRow` 全是纯查表,不会出现"两处判断不一致"那类错(L74)。
	private func rebuildSections() {

		var result = [SectionModel]()

		// 搜索中:整页只剩结果 —— 400 个模型里翻找时,别的东西都是干扰
		let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
		if !query.isEmpty {
			let hits = OpenRouterCatalog.search(query, in: catalog)
			result.append(SectionModel(
				title: hits.isEmpty ? "没有匹配的模型" : "搜索结果(\(hits.count))",
				footer: catalog.isEmpty ? "模型目录还没拉下来。退出搜索,点最底下的「刷新模型目录」。" : nil,
				rows: hits.map { Row.model($0, showsVendorIcon: true) }))
			sections = result
			return
		}

		// 余额:读到了才有这一段
		if let balance {
			result.append(SectionModel(title: "OpenRouter 账户", footer: nil,
									   rows: [.info(balance.displayText)]))
		}

		// 当前选择:400 个里找回自己选的那个很费劲,单独摆一行
		if let current = catalog.first(where: { $0.id == pendingModel }) {
			result.append(SectionModel(title: "当前选择", footer: nil, rows: [.model(current, showsVendorIcon: true)]))
		} else if !pendingModel.isEmpty {
			result.append(SectionModel(title: "当前选择", footer: nil, rows: [.plainModel(pendingModel)]))
		}

		if catalog.isEmpty {
			// 一次都没拉成功(离线首开):退回出厂内置列表,页面照样能用
			result.append(SectionModel(
				title: "内置列表",
				footer: "还没有拉过 OpenRouter 的模型目录。点下方的「刷新模型目录」可以看到全部模型和每篇的估算价。",
				rows: TranslationConfigStore.builtInModels.map { Row.plainModel($0) }))
		} else {
			// ⚠️ **这一段不要加脚注**(用户 2026-08-08 看了截图后明确说"不需要加这段")。
			// 我原来在这儿写了一大段说明:筛选规则、「热门」是什么、价格怎么估、
			// 没选中的去哪找 —— 洋洋洒洒占了大半屏,把列表挤得没影了。
			// 那些解释该待在代码注释里(`OpenRouterCatalog.featured` / `OpenRouterRankings`),
			// **不是摆在用户脸前**:他要的是一份能挑的清单,不是一篇说明书。
			let featured = OpenRouterCatalog.featured(from: catalog)
			result.append(SectionModel(
				title: "精选(\(featured.count) 个)",
				footer: nil,
				rows: featured.map { Row.model($0, showsVendorIcon: true) }))

			for group in OpenRouterCatalog.grouped(catalog) {
				// 标题走品牌名(`z-ai` → 智谱 Z.AI)。别名已并进对应厂商,不再单独成组。
				//
				// ⚠️ **砍掉的要说出来,不许静默截断**:这一家实际有多少、现在只显示几个,
				// 都写在标题上。不写的话用户会以为"这家就这 5 个"——
				// 2026-08-08 他就是这么被「OpenAI 分类下只有 gpt-latest」骗过一次的。
				let title = OpenRouterVendorStyle.displayName(for: group.vendor)
				let shown = group.models.count
				result.append(SectionModel(
					title: shown < group.total ? "\(title) · 精选 \(shown) / 共 \(group.total)" : title,
					footer: nil,
					rows: group.models.map { Row.model($0, showsVendorIcon: false) },
					vendor: group.vendor))
			}
		}

		result.append(SectionModel(title: nil, footer: refreshFooterText, rows: [.refresh]))
		sections = result
	}

	private var refreshFooterText: String {
		if let problem = TranslationConfigStore.configurationProblem {
			return problem
		}
		var lines = ["翻译按钮在文章页底部工具栏。"]
		if let date = OpenRouterCatalog.lastRefreshed {
			let formatter = DateFormatter()
			formatter.dateStyle = .medium
			formatter.timeStyle = .short
			lines.append("模型目录更新于 \(formatter.string(from: date))。")
		}
		return lines.joined(separator: "\n\n")
	}

	// MARK: - 表格

	override func numberOfSections(in tableView: UITableView) -> Int {
		sections.count
	}

	override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		sections[section].rows.count
	}

	override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
		sections[section].title
	}

	/// 厂商分区头:字母徽标 + 品牌名。别的分区返回 nil,交回给上面那个 `titleForHeader`。
	///
	/// ⚠️ 用 `UIListContentConfiguration.groupedHeader()`,不是自己拼 UIView ——
	/// 它自带系统的字号/内边距/深浅色,和别的分区头长得一模一样,
	/// 我们只是往里塞一张图。自己拼的话这一处迟早和系统样式对不上。
	override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {

		guard let vendor = sections[section].vendor,
			  let header = tableView.dequeueReusableHeaderFooterView(withIdentifier: "VendorHeader") else {
			return nil
		}

		var content = UIListContentConfiguration.groupedHeader()
		content.text = sections[section].title
		content.image = OpenRouterVendorStyle.icon(for: vendor, traits: traitCollection)
		content.imageProperties.maximumSize = CGSize(width: 22, height: 22)
		content.imageProperties.reservedLayoutSize = CGSize(width: 22, height: 22)	// 真 logo 宽窄不一,给它们一个统一的位置,厂商名才对得齐
		// 只对**单色** logo 生效(资源里标了 template 的那 6 个):染成主题色。
		// 彩色 logo 标的是 original,不受这行影响,品牌色原样保留。
		//
		// ⚠️ 为什么染主题色而不是 `.label`:那几个单色 logo 的原色是**纯黑**,
		// 深色模式下会直接消失(L112)。染成主题色一举两得 —— 深浅色都读得出来,
		// 而且和这个 app「单一强调色」的调子是一路的。
		content.imageProperties.tintColor = NNWAccentPalette.live
		content.imageToTextPadding = 8
		header.contentConfiguration = content
		return header
	}

	override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
		sections[section].footer
	}

	// [外观] cell 暖底 + 药丸选中
	override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
		AppAppearance.applyPaperStyle(to: cell)
	}

	override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {

		let cell = tableView.dequeueReusableCell(withIdentifier: "TranslationModelCell", for: indexPath)
		var content = cell.defaultContentConfiguration()
		cell.accessoryView = nil
		cell.accessoryType = .none

		// [外观] 2026-08-08(用户:「字号小一点,现在有点空」):整页收紧一档 ——
		// 主行 body(17)→ subheadline(15),副行 footnote(13)→ caption1(12),
		// 上下内边距 11 → 7、两行之间 3 → 1。一屏能多看到两三个模型,
		// 400 个模型的页面里这很值。⚠️ 仍然用**动态字体**,不写死 pt —— 无障碍放大照样跟。
		content.textProperties.font = .preferredFont(forTextStyle: .subheadline)
		content.secondaryTextProperties.font = .preferredFont(forTextStyle: .caption1)
		content.textToSecondaryTextVerticalPadding = 1
		content.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 7, leading: 0, bottom: 7, trailing: 0)

		switch sections[indexPath.section].rows[indexPath.row] {

		case .info(let text):
			content.text = text
			content.textProperties.color = .secondaryLabel
			cell.selectionStyle = .none

		case .model(let model, let showsVendorIcon):
			// 「热门」= 真的上过 OpenRouter 的任务榜(不是我们排的名次)。
			// 标出来是为了让"按流行度选的"和"按价格补的"一眼能分开(见 OpenRouterRankings)。
			// 行尾的两个小标记:
			// 「始终最新」= OpenRouter 的别名,会自动跟着那一族的最新版走
			//   ⚠️ 它**指向哪个具体模型 OpenRouter 不告诉我们**(见 isLatestAlias 的注释),
			//     所以只能标"是个别名",标不出"= 谁"。用户 2026-08-08 问过这一点。
			// 「热门」= 真的上过 OpenRouter 的任务榜(不是我们排的名次,见 OpenRouterRankings)
			var badges = [String]()
			if model.isLatestAlias { badges.append("始终最新") }
			if model.isPopular { badges.append("热门") }
			content.text = badges.isEmpty ? model.shortID
				: "\(model.shortID)  ·  \(badges.joined(separator: " · "))"
			content.secondaryText = [model.priceDescription, model.contextDescription]
				.compactMap { $0 }
				.joined(separator: " · ")
			if showsVendorIcon {
				// 名字前面放厂商 logo(用户 2026-08-08 要求)。
				// 比分区头那颗小一号 —— 行本身的字号已经收紧过,22pt 会压过模型名。
				content.image = OpenRouterVendorStyle.icon(for: model.vendor, traits: traitCollection)
				content.imageProperties.maximumSize = CGSize(width: 18, height: 18)
				content.imageProperties.reservedLayoutSize = CGSize(width: 18, height: 18)
				content.imageProperties.tintColor = NNWAccentPalette.live	// 只影响标了 template 的那 6 个单色 logo
				content.imageToTextPadding = 8
			}
			cell.selectionStyle = .default
			cell.accessoryType = (model.id == pendingModel) ? .checkmark : .none

		case .plainModel(let id):
			content.text = TranslationConfigStore.displayName(for: id)
			content.secondaryText = id
			cell.selectionStyle = .default
			cell.accessoryType = (id == pendingModel) ? .checkmark : .none

		case .refresh:
			content.text = isRefreshing ? "正在刷新…" : "刷新模型目录"
			content.textProperties.color = NNWAccentPalette.live	// [外观] 走调色板,像个按钮
			content.textProperties.alignment = .center
			cell.selectionStyle = .default
			if isRefreshing {
				let spinner = UIActivityIndicatorView(style: .medium)
				spinner.startAnimating()
				cell.accessoryView = spinner
			}
		}

		cell.contentConfiguration = content
		return cell
	}

	override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		tableView.deselectRow(at: indexPath, animated: true)

		switch sections[indexPath.section].rows[indexPath.row] {
		case .info:
			break
		case .model(let model, _):
			select(model.id)
		case .plainModel(let id):
			select(id)
		case .refresh:
			refreshCatalog(silent: false)
		}
	}

	/// 只标记待选,不落库 —— 点右上角的勾才真正生效。
	private func select(_ modelID: String) {
		pendingModel = modelID
		rebuildSections()	// 「当前选择」那一段要跟着换
		tableView.reloadData()
	}
}

// MARK: - 搜索

extension TranslationModelPickerViewController: UISearchResultsUpdating {

	func updateSearchResults(for searchController: UISearchController) {
		let text = searchController.searchBar.text ?? ""
		guard text != searchText else { return }
		searchText = text
		rebuildSections()
		tableView.reloadData()
	}
}

#endif
