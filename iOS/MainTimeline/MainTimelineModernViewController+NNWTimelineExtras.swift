//
//  MainTimelineModernViewController+NNWTimelineExtras.swift
//  NetNewsWire — AI 翻译 fork
//
//  本 fork 新增,上游没有这个文件。文章列表页的三处小改,都住在这里:
//
//  | 出处 | 干什么 | 上游那边加了几行 |
//  |---|---|---|
//  | 用户 2026-08-08 第 3 件 | [阅读位置] 每个源各自记住滚到哪 + 点顶栏一来一回 | 1 行(reinitializeArticles 里) |
//  | 用户 2026-08-08 第 6 件 | [管理] 长按文章 → 菜单里多一项「订阅源设置」 | 3 行(长按菜单里) |
//  | 用户 2026-08-08 第 10 件 | [外观] 标题不许被右上角控件压住 | 1 行(updateNavigationBarTitle 里) |
//
//  ## 为什么滚动的钩子能写在这个文件里
//
//  `UIScrollViewDelegate` 是 @objc 协议、方法全是可选的,而上游那边**一个都没实现**
//  (`scrollPositionQueue` 那个队列建了但从没人往里加东西 —— 现成的死代码)。
//  所以在这里补上是纯增量:没有覆盖任何上游行为,上游哪天自己实现了会**编译期撞名**,
//  不会静默打架。
//
//  ⚠️ 列表的 `delegate` 在 Main.storyboard 里就连到本控制器(outlet `delegate` →
//  `QJM-al-rDe`),所以这些方法真的会被调到 —— 这一点是查了故事板确认的,不是假设。
//

#if os(iOS)

import UIKit
import os
import Account
import Articles

enum NNWTimelineExtrasLog {
	static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "NNWTimelineExtras")
}

extension MainTimelineModernViewController {

	// MARK: - [阅读位置] 记住每个源滚到哪(用户 2026-08-08 第 3 件)

	/// 当前这一页属于哪个源。智能源 / 文件夹 / 单个源都有各自的键。
	private var nnwScrollMemoryKey: String? {
		NNWTimelineScrollMemory.key(for: coordinator?.timelineFeed)
	}

	/// 列表最顶上那一行是哪篇文章。
	///
	/// ⚠️ 用 `coordinator.articles` 取文章,**不问 `dataSource`** —— 那个属性是 private,
	/// 外部文件够不着。两者是同一份数据:快照就是 `articles` 原样塞进第 0 区的
	/// (见上游 `applyChanges`),所以 `row` 可以直接当下标。
	private func nnwTopVisibleArticleID() -> String? {
		guard let collectionView, let articles = coordinator?.articles else { return nil }
		guard let top = collectionView.indexPathsForVisibleItems.min() else { return nil }
		guard top.section == 0, top.row < articles.count else { return nil }
		return articles[top.row].articleID
	}

	/// 这篇文章现在排在第几行。找不到(已读被过滤掉 / 换了档)返回 nil。
	private func nnwRow(of articleID: String) -> Int? {
		guard let articles = coordinator?.articles else { return nil }
		return articles.firstIndex { $0.articleID == articleID }
	}

	/// 列表是不是已经在最顶上了。
	private var nnwIsScrolledToTop: Bool {
		guard let collectionView else { return true }
		return collectionView.contentOffset.y <= -collectionView.adjustedContentInset.top + 1
	}

	@objc func scrollViewDidScroll(_ scrollView: UIScrollView) {

		guard let key = nnwScrollMemoryKey else { return }

		// ⚠️ **只记用户自己滑出来的位置。** 这一句是这件事的成败所在(2026-08-08 埋日志才看清):
		//
		// 换源时列表会被清空再填上,`contentOffset` 归零 → `scrollViewDidScroll` 照样触发,
		// 而那一刻列表在最顶上 → 我们把"停在最顶上"记下去,**刚要恢复的那条记录当场被自己抹掉**
		// (日志实证:抹除发生在恢复入口的**前 0.14 秒**)。
		// 光靠"正在恢复期间不记"堵不住 —— 那次抹除**发生在恢复开始之前**。
		//
		// 判据:`isDragging / isTracking / isDecelerating` 三个只要有一个为真就是人在滑;
		// 布局、快照落地、`scrollToItem` 这些程序性的滚动三个全是 false。
		let isUserDriven = scrollView.isDragging || scrollView.isTracking || scrollView.isDecelerating
		guard isUserDriven else { return }

		// 人一动手,正在进行的恢复就作废 —— 别把用户拽回去
		NNWTimelineScrollMemory.shared.endRestore(key)

		// 滚回最顶上 = 忘掉记录(下次进来就该在顶上,而不是"还记着第一行")
		NNWTimelineScrollMemory.shared.remember(nnwIsScrolledToTop ? nil : nnwTopVisibleArticleID(), for: key)
	}

	// MARK: - 点顶栏:第一次回顶(并记住原位),第二次回原位

	/// 点**状态栏**时系统会先问这一句。放行让它回顶,顺手把原位记下来。
	///
	/// ⚠️ **这里只能接到"第一次"。** 2026-08-08 埋日志实测:列表**已经在最顶上时,
	/// 系统根本不会问这个方法**(日志里只出现了一次)。所以「第二次点回原位」
	/// 没做成(详见下面那段说明)。
	/// (判据来自 L118 那一族:借别人的回调做事,先量一量那个回调到底会不会响。)
	@objc func scrollViewShouldScrollToTop(_ scrollView: UIScrollView) -> Bool {
		guard let key = nnwScrollMemoryKey else { return true }
		nnwRememberOriginBeforeGoingToTop(key: key)
		return true
	}

	/// 记下"回顶之前停在哪"(留着,等将来那一半做成时直接用),并把这个源的常驻记录清掉
	/// (用户主动回顶了,下次进来就该在顶上)。
	private func nnwRememberOriginBeforeGoingToTop(key: String) {
		NNWTimelineScrollMemory.shared.setTopTapReturn(nnwTopVisibleArticleID(), for: key)
		NNWTimelineScrollMemory.shared.remember(nil, for: key)
	}

	// ⚠️ **「第二次点顶栏回原位」这一半没做成,原因写在这儿,别再重试同样的三条路。**
	//
	// 用户要的是「点顶栏:第一次回顶并记住原位,第二次回原位」。第一半成了(上面那句),
	// 第二半三条路全部实测失败:
	//
	// | 试过什么 | 实测结果 |
	// |---|---|
	// | 靠 `scrollViewShouldScrollToTop` 收第二次 | ❌ 列表已在最顶上时**系统压根不问这个方法**(日志里只出现一次) |
	// | 给 `navigationController.navigationBar` 加点击手势 | ❌ 一次都没触发 |
	// | 给列表加点击手势 + 只收顶栏那一带 | ❌ 一次都没触发(`shouldReceive` 只收到正文区的触摸) |
	//
	// 后两条同一个病根:本 fork 的**头图浮层**(`TimelineFeedHeaderController` 的 overlay)
	// 铺满整个页面、盖在列表之上,顶栏那一带的触摸先落到它身上就没了。
	// 要做成的话得从那一层下手(给 overlay 加手势 / 让它对那一带放行),
	// 那是动"会飞的标题"那套的机制,风险不小 —— 留给下一轮单独评估。
	//
	// **现在的行为**:点状态栏 = 回顶(系统给的),而且原位会被记下来;
	// 离开这个源再回来,仍然回到离开前的位置(这条是 #3 的主体,已验证)。

	/// 换了源之后,把这个源上次停的位置找回来。
	/// **由上游 `reinitializeArticles(resetScroll:)` 里加的一行调用。**
	///
	/// - Parameter resetScroll: 上游用它区分「换源了」(true)和「只是数据刷新」(false)。
	///   只有换源那次才需要恢复 —— 数据刷新时列表本来就该原地不动。
	///
	/// ⚠️ **不能只试一次。** 调到本方法这一刻,列表的数据还没落地:
	/// 上游是「先 `replaceArticles`(里面 `dataSource.apply` 是**异步**的)→ 再叫本方法」,
	/// 所以这时 `collectionView.numberOfItems` 往往还是**上一个源**的行数,
	/// 要滚的那一行根本还不存在(2026-08-08 第一版只试一次,表现是"完全没反应")。
	/// 判据就是 L118:借别人的时机做事,先量一量那个状态落定了没 —— 这里落定不了,
	/// 于是改成**每帧重试,直到那一行真的出现**(最多约 1 秒,失败就安静放弃)。
	func nnwRestoreFeedScrollPositionIfNeeded(resetScroll: Bool) {

		guard resetScroll, let key = nnwScrollMemoryKey,
			  let articleID = NNWTimelineScrollMemory.shared.rememberedArticleID(for: key) else { return }

		NNWTimelineScrollMemory.shared.beginRestore(key)
		nnwAttemptScrollRestore(key: key, articleID: articleID, attemptsLeft: 20)
	}

	/// 重试的一轮。成功、换源、或者次数用光都会结束"正在恢复"那段时间。
	private func nnwAttemptScrollRestore(key: String, articleID: String, attemptsLeft: Int) {

		// 用户在这期间又换了源 —— 那这次恢复作废,别乱滚
		guard nnwScrollMemoryKey == key else {
			NNWTimelineScrollMemory.shared.endRestore(key)
			return
		}

		if let collectionView, let row = nnwRow(of: articleID),
		   row > 0, row < collectionView.numberOfItems(inSection: 0) {
			NNWTimelineExtrasLog.logger.info(
				"[阅读位置] 恢复成功 key=\(key, privacy: .public) 行=\(row, privacy: .public) 还剩\(attemptsLeft, privacy: .public)次")
			collectionView.scrollToItem(at: IndexPath(row: row, section: 0), at: .top, animated: false)
			// 滚完再放开记录 —— 这一帧里还会来几次 didScroll,让它们别把刚落位的结果又改一遍
			DispatchQueue.main.async {
				NNWTimelineScrollMemory.shared.endRestore(key)
			}
			return
		}

		guard attemptsLeft > 1 else {
			// 找不到就算了(那篇可能已读被过滤掉 / 换了档),安静回到顶部,不打扰用户
			NNWTimelineExtrasLog.logger.info(
				"[阅读位置] 重试用光 key=\(key, privacy: .public) 要找=\(articleID, privacy: .public) 行=\(self.nnwRow(of: articleID) ?? -1, privacy: .public) 表里行数=\(self.collectionView?.numberOfItems(inSection: 0) ?? -1, privacy: .public) articles=\(self.coordinator?.articles.count ?? -1, privacy: .public)")
			NNWTimelineScrollMemory.shared.endRestore(key)
			return
		}

		DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
			self?.nnwAttemptScrollRestore(key: key, articleID: articleID, attemptsLeft: attemptsLeft - 1)
		}
	}

	// MARK: - [管理] 长按文章 →「订阅源设置」(用户 2026-08-08 第 6 件)

	/// 长按菜单里的「订阅源设置」。复用上游现成的 `showFeedInspector(for:)`,
	/// 不新建任何页面 —— 那一页(FeedInspectorViewController)本来就是这个源的设置页,
	/// 只是原先只能从订阅列表长按或本页右上角齿轮进去。
	///
	/// 智能源(今天/全部未读/…)的文章也有 `article.feed`,所以这一项在哪个列表里都有效。
	func nnwFeedSettingsAction(_ article: Article) -> UIAction? {
		guard let feed = article.feed else { return nil }
		return UIAction(title: "订阅源设置", image: UIImage(systemName: "gearshape")) { [weak self] _ in
			self?.coordinator?.showFeedInspector(for: feed)
		}
	}

	// MARK: - [外观] 标题不许被右上角控件压住(用户 2026-08-08 第 10 件)

	/// 把导航栏标题的宽度夹在"两边控件之间那段净空"里,超出就打省略号。
	/// **由上游 `updateNavigationBarTitle(_:)` 里加的一行调用。**
	///
	/// ## 为什么光把右上角控件做窄不够
	///
	/// 上游给标题用的是**自定义 titleView**(一个 `UILabel`),而且每次都 `sizeToFit()` ——
	/// 于是标签的宽度 = 文字的完整宽度,源名多长它就多宽。导航栏把 titleView 居中摆,
	/// 一旦它比净空宽,两头就会伸到按钮底下去(用户看到的"齿轮压在标题上")。
	/// 源名可以任意长,所以**必须有一个夹宽度的地方**,否则永远治不干净(T51 里点名要求量一量)。
	///
	/// ## 净空怎么算
	///
	/// 标题是**居中**的,所以左右必须留一样宽 —— 净空 = 栏宽 − 2 ×(右侧控件宽 + 余量)。
	/// 右侧控件宽度直接问它们自己要(`nnwRightBarItemsWidth`),不写死常数:
	/// 双图标胶囊、单个圆钮、什么都没有,三种情况自动各得其所。
	/// 顶栏更新之后要做的两件事。**由上游 `updateNavigationBarTitle(_:)` 里加的一行调用。**
	///
	/// ⚠️ 必须挂在**方法末尾那一句**、而不是里面那个 `if let label = titleView as? UILabel` 分支里
	/// (第一版就挂错了地方,埋日志才发现从来没执行过 —— L123「我量到了 ≠ 我量的是它」的又一例)。
	/// 原因:本 fork 的头图上线之后,**`titleView` 被换成了一个空视图**
	/// (见 `TimelineFeedHeaderController`:titleView 存在时系统就不画 title/subtitle 了),
	/// 所以那个分支在有头图的页面上根本不成立 —— 而有头图的页面恰恰就是全部单源页。
	func nnwTimelineTopBarDidUpdate() {
		nnwClampNavigationTitleWidth()	// 上游那个标题标签(没有头图的页面才用得上)
		// [外观] 2026-08-09:左上角返回键换成我们自己的玻璃圆钮(唯一一个原来不受
		// `NNWSoftMaterial.controlDiameter` 管的控件)。**幂等**,所以放心挂在这个会被
		// 反复调用的地方 —— 而且这里是"viewWillAppear 和切源都必经"的那一处,
		// 转场后系统若把返回键或侧滑 delegate 换回去,下一次经过就会被重新装上。
		nnwInstallSoftGlassBackButton()
	}

	func nnwClampNavigationTitleWidth() {

		guard let label = navigationItem.titleView as? UILabel,
			  let barWidth = navigationController?.navigationBar.bounds.width, barWidth > 0 else { return }

		let available = barWidth - 2 * (nnwRightBarItemsWidth + Self.nnwTitleSideMargin)
		guard available > 40 else { return }

		label.lineBreakMode = .byTruncatingTail
		if label.bounds.width > available {
			label.bounds.size = CGSize(width: available, height: label.bounds.height)
		}
	}

	/// 标题两侧至少留这么宽的空当,免得字和控件贴在一起。
	private static let nnwTitleSideMargin: CGFloat = 12

	/// 右上角那一组控件一共多宽(含它们之间的间距)。
	private var nnwRightBarItemsWidth: CGFloat {
		let items = navigationItem.rightBarButtonItems ?? []
		guard !items.isEmpty else { return 0 }
		let widths = items.map { item -> CGFloat in
			if let view = item.customView {
				let width = view.bounds.width
				return width > 0 ? width : view.intrinsicContentSize.width
			}
			return 44
		}
		// 项与项之间按 8pt 估(系统值,拿不到精确的;宁可估大也不要估小)
		return widths.reduce(0, +) + CGFloat(max(0, items.count - 1)) * 8
	}
}

#endif
