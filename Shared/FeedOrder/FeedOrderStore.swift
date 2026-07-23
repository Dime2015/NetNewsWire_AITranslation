//
//  FeedOrderStore.swift
//  NetNewsWire — AI 翻译 fork
//
//  [管理] 本 fork 新增,上游没有这个文件。
//
//  ## 这是干什么的:让用户能自己决定订阅源的先后顺序
//
//  ⚠️ **上游根本不存"顺序"这回事**,先把这个前提说清楚,否则后面的设计看不懂:
//  `Folder.topLevelFeeds` 和 `Account.topLevelFeeds` 都是 **`Set<Feed>`** ——
//  集合本身无序,模型里压根没有可以写顺序的地方。
//  你在列表里看到的排列,是**每次显示时现算**的(上游 `sortedAlphabeticallyWithFoldersAtEnd()`,
//  强制按字母排、文件夹在后)。
//
//  所以要支持"拖动排序",只能**由我们自己在旁边存一份顺序**,再让显示时按它排。
//  这个文件就是那份顺序。
//
//  ## 为什么必须让**主列表**也按它排
//
//  只在管理页里排是没有意义的:用户真正读文章的地方是主列表,
//  两处顺序对不上只会更糊涂。所以上游的排序入口要改一行,指到这里来
//  (`SidebarTreeControllerDelegate` 里那句 sortedAlphabeticallyWithFoldersAtEnd)。
//
//  ## 存法:给每一项记一个"排序权重",而不是按容器存一份名单
//
//  看起来按容器(某文件夹里的顺序)存更直观,但**做不到** ——
//  `Folder.folderID` 上游明确标注了 `not saved: per-run only`,
//  **每次启动都会变**,拿它当持久化的键,重启就全乱。
//  所以改成给每一项记一个权重,排序时只在同一层内部比较 —— 天然不需要容器的键。
//
//  ## 排序的范围:**文件夹和没归档的源是平级的,混在一起排**
//
//  (2026-07-23 按用户要求扩大:原本只排源、文件夹固定在最后。)
//  于是账户底下是一串"条目",每一项要么是文件夹、要么是散源,顺序由用户拖出来;
//  文件夹**内部**的源另算一层,单独排。
//
//  ## 四条边界(都是明知的取舍,不是漏做)
//
//  1. **顺序存在本机**:导出 OPML 不带它,换设备 / 重装后回到字母序。
//  2. **没排过的按老规矩排在后面**(源按名字在前、文件夹按名字在后)——
//     所以**一次都没拖过时,列表和上游原来一模一样**,新订阅的源也不会插进已排好的中间。
//  3. **源被移到别的文件夹时会清掉它的权重**,回到"按名字排在后面"。
//     不清的话,它会带着旧位置插进新文件夹中间,看起来像随机乱跳。
//  4. **文件夹的键是它的名字**(见下方 `folderKeyPrefix` 的说明),
//     所以从主列表左滑改名会让它丢掉位置;管理页里改名则会把顺序一起搬过去。
//

import Foundation
import Account
import RSTree

@MainActor final class FeedOrderStore {

	static let shared = FeedOrderStore()

	private static let defaultsKey = "nnwFeedDisplayOrder"

	/// 排序键 → 权重(小的排前面)。没记录的 = 没被拖过,按上游的老规矩排在所有排过的后面。
	private var weights: [String: Double]

	private init() {
		weights = UserDefaults.standard.dictionary(forKey: Self.defaultsKey) as? [String: Double] ?? [:]
	}

	private func save() {
		UserDefaults.standard.set(weights, forKey: Self.defaultsKey)
	}

	// MARK: - 排序键

	/// ⚠️ **源和文件夹的键来源不同,原因写在这里,别统一**:
	/// · 源用 `feedID` —— 稳定(本地账户就是订阅地址)。
	/// · 文件夹只能用**名字** —— 上游的 `folderID` 明确标着 `not saved: per-run only`,
	///   **每次启动都会变**,拿它当持久化的键,重启后顺序全乱。
	///   代价是**文件夹改名后会丢掉自己的位置**(退回按名字排在末尾);
	///   管理页里改名会顺手把顺序迁过去,但从主列表左滑改名则不会 —— 重拖一次即可。
	private static let folderKeyPrefix = "folder\u{1}"		// \u{1} 不可能出现在订阅地址里,不会和 feedID 撞

	static func orderKey(forFolderNamed name: String) -> String {
		folderKeyPrefix + name
	}

	/// 一个树节点对应的排序键(既不是源也不是文件夹时返回 nil)。
	static func orderKey(for node: Node) -> String? {
		if let feed = node.representedObject as? Feed { return feed.feedID }
		if let folder = node.representedObject as? Folder { return orderKey(forFolderNamed: folder.nameForDisplay) }
		return nil
	}

	// MARK: - 读

	/// 按用户排的顺序排列;没排过的排在后面、彼此按名字排。
	func sortedFeeds(_ feeds: [Feed]) -> [Feed] {
		feeds.sorted { compare(weights[$0.feedID], $0.nameForDisplay, weights[$1.feedID], $1.nameForDisplay) }
	}

	/// 树节点的排序(给主列表用)。**文件夹和源混在一起排** ——
	/// 用户在管理页把文件夹拖到哪儿,主列表就跟到哪儿。
	func sortedNodes(_ nodes: [Node]) -> [Node] {
		let fallback = fallbackWeights(for: nodes)
		return nodes.sorted { left, right in
			let l = Self.orderKey(for: left).flatMap { weights[$0] } ?? fallback[ObjectIdentifier(left)] ?? 0
			let r = Self.orderKey(for: right).flatMap { weights[$0] } ?? fallback[ObjectIdentifier(right)] ?? 0
			return l < r
		}
	}

	/// 没被拖过的东西该排在哪 —— **完全照搬上游原来的规矩**:
	/// 源在前(按名字),文件夹在后(按名字)。
	///
	/// 手法是给它们发一个很大的"兜底权重",于是天然排在所有**拖过的**(权重 0、1、2…)后面。
	/// 这样一来:**一次都没拖过时,整个列表和上游原来一模一样**;
	/// 拖过的东西则按用户的意思插到前面。
	private func fallbackWeights(for nodes: [Node]) -> [ObjectIdentifier: Double] {

		func name(_ node: Node) -> String {
			(node.representedObject as? Feed)?.nameForDisplay
				?? (node.representedObject as? Folder)?.nameForDisplay ?? ""
		}

		let feeds = nodes.filter { !($0.representedObject is Folder) }
			.sorted { name($0).localizedStandardCompare(name($1)) == .orderedAscending }
		let folders = nodes.filter { $0.representedObject is Folder }
			.sorted { name($0).localizedStandardCompare(name($1)) == .orderedAscending }

		var result: [ObjectIdentifier: Double] = [:]
		for (index, node) in feeds.enumerated() {
			result[ObjectIdentifier(node)] = 1_000_000 + Double(index)
		}
		for (index, node) in folders.enumerated() {
			result[ObjectIdentifier(node)] = 2_000_000 + Double(index)		// 文件夹兜底排在源后面
		}
		return result
	}

	/// 排序规则的唯一出处:**排过的在前(按权重),没排过的在后(按名字)**。
	private func compare(_ leftWeight: Double?, _ leftName: String,
						 _ rightWeight: Double?, _ rightName: String) -> Bool {
		switch (leftWeight, rightWeight) {
		case (let l?, let r?):
			return l == r ? leftName.localizedStandardCompare(rightName) == .orderedAscending : l < r
		case (.some, .none):
			return true
		case (.none, .some):
			return false
		case (.none, .none):
			return leftName.localizedStandardCompare(rightName) == .orderedAscending
		}
	}

	// MARK: - 顶层的混排(管理页用)

	/// 账户顶层的一项:要么是一个文件夹,要么是一个没归档的源。**两者混在一起排。**
	@MainActor enum TopLevelEntry {
		case folder(Folder)
		case feed(Feed)

		var sortName: String {
			switch self {
			case .folder(let folder): return folder.nameForDisplay
			case .feed(let feed): return feed.nameForDisplay
			}
		}

		var isFolder: Bool {
			if case .folder = self { return true }
			return false
		}
	}

	/// 把文件夹和散源**混在一起**按用户排的顺序排列。
	func sortedTopLevel(folders: [Folder], looseFeeds: [Feed]) -> [TopLevelEntry] {

		let entries = folders.map { TopLevelEntry.folder($0) } + looseFeeds.map { TopLevelEntry.feed($0) }

		// 兜底权重的算法要和 fallbackWeights 保持一致:源在前、文件夹在后,各按名字
		let sortedFeedNames = entries.filter { !$0.isFolder }
			.map { $0.sortName }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
		let sortedFolderNames = entries.filter { $0.isFolder }
			.map { $0.sortName }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }

		func weight(_ entry: TopLevelEntry) -> Double {
			if let stored = weights[key(for: entry)] { return stored }
			switch entry {
			case .feed:
				return 1_000_000 + Double(sortedFeedNames.firstIndex(of: entry.sortName) ?? 0)
			case .folder:
				return 2_000_000 + Double(sortedFolderNames.firstIndex(of: entry.sortName) ?? 0)
			}
		}

		return entries.sorted { weight($0) < weight($1) }
	}

	/// 顶层一项的排序键。
	func key(for entry: TopLevelEntry) -> String {
		switch entry {
		case .folder(let folder): return Self.orderKey(forFolderNamed: folder.nameForDisplay)
		case .feed(let feed): return feed.feedID
		}
	}

	// MARK: - 写

	/// 把一批源按给定的先后次序记下来(用户拖完一次就调一次)。
	///
	/// 权重直接用 0、1、2… 重排整个容器,而不是去插空隙 ——
	/// 容器里最多几十个源,整体重排最省心,也不会出现"插到没有空位可用"的情况。
	func setOrder(_ feedIDs: [String]) {
		for (index, feedID) in feedIDs.enumerated() {
			weights[feedID] = Double(index)
		}
		save()
	}

	/// 源换了容器 → 忘掉它的位置(理由见文件头第 3 条)。
	func forgetOrder(forFeedIDs feedIDs: [String]) {
		guard !feedIDs.isEmpty else { return }
		for feedID in feedIDs {
			weights.removeValue(forKey: feedID)
		}
		save()
	}

	/// 文件夹改名了 → 把顺序跟着搬到新名字上(键就是名字,不搬就等于丢了位置)。
	func renameFolderKey(from oldName: String, to newName: String) {
		let oldKey = Self.orderKey(forFolderNamed: oldName)
		guard let weight = weights[oldKey] else { return }
		weights.removeValue(forKey: oldKey)
		weights[Self.orderKey(forFolderNamed: newName)] = weight
		save()
	}
}

// MARK: - 给主列表用的排序入口

@MainActor extension Array where Element == Node {

	/// [管理] 主列表的排序:**文件夹和源混在一起**,按用户在文件夹管理页拖出来的顺序。
	///
	/// 上游原来那句 `sortedAlphabeticallyWithFoldersAtEnd()` 就换成了这个。
	///
	/// ⚠️ **一次都没拖过时,结果和上游原来完全一致**(源按名字在前、文件夹按名字在后)——
	/// 靠的是没权重的东西会拿到一个很大的"兜底权重",见 `fallbackWeights`。
	/// 所以 macOS 端虽然也编译到这段,但它的顺序表是空的,行为一点不变。
	func nnwSortedForDisplay() -> [Node] {
		FeedOrderStore.shared.sortedNodes(self)
	}
}
