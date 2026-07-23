//
//  MainFeedCollectionViewController+ReadingMode.swift
//  NetNewsWire — AI 翻译 fork
//
//  [阅读档] 把三档控件接到订阅列表页上。本 fork 新增文件,上游没有。
//
//  ## 这个文件负责四件事
//
//  1. 把控件装进底部工具栏正中(⚙️ ⟷ **控件** ⟷ ➕)
//  2. 左滑 / 右滑整页 = 切换档位
//  3. 藏掉右上角那个「漏斗」(它和档位是同一件事,用户要求拿掉)
//  4. 换档时:让上游的「隐藏已读源」跟着对齐 + 把每行的数字重算一遍
//
//  ## ⚠️ 装进工具栏时绕开的一个坑(CLAUDE.md 里专门记过)
//
//  上游 `configureToolbarWithProgressView()` 里有一条守卫:
//  「工具栏必须正好 3 项,否则直接返回」——往故事板里加第 4 个按钮会让
//  刷新进度条**静默装不上**。所以这里的做法是:
//  **不动故事板,在代码里、等上游那句跑完之后再插**。
//  插的位置是"最后一项之前",于是 iOS 26 上得到 [设置][空白][控件][空白][+],
//  正好居中;iOS 26 以下上游会先插进度条,我们排在它右边,也不会把它弄坏。
//  (iOS 26 上那条守卫本来就不生效 —— 那个分支开头就 return,压根不装进度条。)
//
//  ## ⚠️ 换档之后为什么必须手动刷一遍可见行
//
//  **L68**:diffable 判断"这一行要不要重画"只看行的身份,
//  而"右边显示几"不在身份里 —— 换档时行没变、数字却该变,不手动刷就一直是旧的。
//  这里刷的方式和上游 `reloadAllVisibleCells()` 完全一样(那个方法是 private,够不着)。
//

#if os(iOS)

import UIKit
import Account

extension MainFeedCollectionViewController {

	private static var nnwGesturesKey: UInt8 = 0
	private static var nnwRenderedModeKey: UInt8 = 0
	private static var nnwStarredObserverKey: UInt8 = 0

	private var nnwGesturesInstalled: Bool {
		get { (objc_getAssociatedObject(self, &Self.nnwGesturesKey) as? Bool) ?? false }
		set { objc_setAssociatedObject(self, &Self.nnwGesturesKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
	}

	private var nnwStarredObserverInstalled: Bool {
		get { (objc_getAssociatedObject(self, &Self.nnwStarredObserverKey) as? Bool) ?? false }
		set { objc_setAssociatedObject(self, &Self.nnwStarredObserverKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
	}

	/// 屏幕上这批行**是按哪个档画出来的**。
	///
	/// ⚠️ 有了它才能修掉这个情形:在**文章列表页**把档从「未读」切成「全部」,
	/// 再返回订阅列表 —— 这一页的行还是老样子(行的身份没变,diffable 不会重画,L68)。
	/// 所以每次出现时比一比,不一样就把可见行的数字重算一遍。
	private var nnwRenderedMode: NNWReadingMode? {
		get { (objc_getAssociatedObject(self, &Self.nnwRenderedModeKey) as? String).flatMap(NNWReadingMode.init(rawValue:)) }
		set { objc_setAssociatedObject(self, &Self.nnwRenderedModeKey, newValue?.rawValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
	}

	// MARK: - 每次页面出现时调一次

	/// 装 / 更新阅读档位相关的东西。**幂等** —— `viewWillAppear` 会调很多次。
	func nnwUpdateReadingMode() {

		// ① 右上角:藏掉上游那个漏斗,换成**全局搜索**的放大镜。
		//
		// 藏漏斗:在代码里藏、不去故事板删 —— 故事板是上游高频改动的大文件,动它 merge 冲突风险高(L6)。
		// outlet 仍然连着,上游那两个 setFilterButtonToActive/Inactive 照常能跑,不会崩。
		if !NNWReadingModeStore.showsPerFeedFilterButton {
			nnwInstallGlobalSearchButton()
		}

		nnwInstallModeBarIfNeeded()
		nnwInstallSwipeGesturesIfNeeded()
		nnwObserveStarredIndexIfNeeded()

		// ★ 档要用星标数,而它是**异步查出来的**(L53)。开机就停在★档时,
		// 第一次进来它必然还没装好 —— 催一次,到货后靠通知重画。
		if NNWReadingModeStore.shared.mode == .starred, !NNWStarredIndex.shared.hasLoaded {
			NNWStarredIndex.shared.refresh()
		}

		// 页面每次出现都对齐一次:别的入口(上游别处调了 toggleReadFeedsFilter)可能把状态改跑偏
		nnwSyncReadFeedsFilterToMode()

		// 档位可能是在**文章列表页**改的 —— 那时这一页不在屏幕上,行还停在老档位画的样子
		if nnwRenderedMode != NNWReadingModeStore.shared.mode {
			nnwReloadVisibleRowCounts()
		}
	}

	// MARK: - 装控件

	private func nnwInstallModeBarIfNeeded() {

		var items = toolbarItems ?? []
		guard items.count >= 2 else { return }		// 故事板里至少有 [设置][空白][+]

		// 已经在工具栏里了就什么都不用做(控件自己盯着通知换外观)
		if let bar = nnwReadingModeBar, items.contains(where: { $0.customView === bar }) { return }

		let barItem = nnwReadingModeBarItem { [weak self] mode in
			self?.nnwSelectReadingMode(mode)
		}

		// 插在**最后一项(+)之前**,并补一个可伸缩空白 → 控件被两侧空白挤到正中
		items.insert(contentsOf: [barItem, UIBarButtonItem.flexibleSpace()], at: items.count - 1)
		toolbarItems = items
	}

	// MARK: - 右上角的全局搜索

	/// 首页右上角放一个放大镜:**搜全部订阅源**(2026-07-23 用户要求)。
	///
	/// ## 为什么这一条几乎不花钱
	///
	/// 上游**本来就有**一条完整的全局搜索:`SceneCoordinator.showSearch()` ——
	/// 它会取消当前选中的源 → 推出文章列表页 → 打开搜索框、**把范围设成「全部」**。
	/// 但它现在只有两个入口:**外接键盘 ⌘F**、**长按桌面图标的快捷菜单**。
	/// iPhone 上等于不存在。所以这里只是**把已有能力接出来**,上游一行没改。
	///
	/// ## 和文章列表页那个放大镜的分工
	///
	/// | 从哪进 | 搜什么 |
	/// |---|---|
	/// | **首页**这个 | 全部订阅源(想不起来是哪个源发的,就在这儿搜) |
	/// | **文章列表页**那个 | 只搜当前这个列表 |
	///
	/// 后者是上游默认行为,不用我们做:搜索框底下有个范围切换条,iPhone 上默认停在「本列表」。
	/// ⚠️ 反过来:从首页进的搜索,范围是「全部」,这时那条切换条上的「本列表」是空的
	///(因为首页没有"当前列表")—— 上游 ⌘F 进来也是这个样子,不是我们弄出来的。
	private func nnwInstallGlobalSearchButton() {

		// 已经装过就别重造(viewWillAppear 会调很多次)
		if navigationItem.rightBarButtonItem?.action == #selector(nnwGlobalSearchTapped) { return }

		let item = UIBarButtonItem(image: UIImage(systemName: "magnifyingglass"),
								   style: .plain, target: self, action: #selector(nnwGlobalSearchTapped))
		item.accessibilityLabel = "搜索全部订阅源"
		navigationItem.rightBarButtonItem = item
	}

	@objc private func nnwGlobalSearchTapped() {
		coordinator.showSearch()
	}

	// MARK: - 星标数到货了要重画

	private func nnwObserveStarredIndexIfNeeded() {
		guard !nnwStarredObserverInstalled else { return }
		nnwStarredObserverInstalled = true
		NotificationCenter.default.addObserver(self, selector: #selector(nnwStarredIndexDidChange),
											   name: NNWStarredIndex.didChangeNotification, object: nil)
	}

	/// 星标数重新数完了。**只有★档需要理它** —— 别的档位的行和数字都跟星标无关。
	///
	/// ⚠️ 这条路径是 L53 那类问题的正解:**异步数据到货后主动重画一次**。
	/// 少了它,一进★档看到的是"还没数完"那一版(全都放行、数字全是 0),而且永远不会自己更新。
	@objc private func nnwStarredIndexDidChange() {
		guard NNWReadingModeStore.shared.mode == .starred else { return }
		coordinator.nnwRebuildFeedList()
		nnwReloadVisibleRowCounts()
	}

	// MARK: - 左右滑切换

	private func nnwInstallSwipeGesturesIfNeeded() {

		guard !nnwGesturesInstalled, let collectionView else { return }
		nnwGesturesInstalled = true

		// ⚠️ 这两个手势能成立的前提是**行上的左滑已经拿掉**(见 configureCollectionView 里那行)。
		// 两者共存的话,手指往左一划到底是"划出行操作"还是"切档"没法区分 —— 用户 2026-07-23 也是这么要求的。
		for direction in [UISwipeGestureRecognizer.Direction.left, .right] {
			let gesture = UISwipeGestureRecognizer(target: self, action: #selector(nnwHandleModeSwipe(_:)))
			gesture.direction = direction
			// 竖直滚动不受影响:UISwipeGestureRecognizer 只认单一方向的快速划动,
			// 列表自己的 pan 该滚照滚(两者天生共存,不需要设 require-to-fail)。
			collectionView.addGestureRecognizer(gesture)
		}
	}

	@objc private func nnwHandleModeSwipe(_ gesture: UISwipeGestureRecognizer) {
		let store = NNWReadingModeStore.shared
		// 手指往左划 = 往右边那一档走(和控件上从左到右的排列一致)
		let forward = gesture.direction == .left
		guard let next = store.neighbourMode(after: store.mode, forward: forward) else { return }
		nnwSelectReadingMode(next)
	}

	// MARK: - 真正换档

	private func nnwSelectReadingMode(_ mode: NNWReadingMode) {

		guard NNWReadingModeStore.shared.setMode(mode) else { return }

		// 控件外观不用管 —— 它自己盯着通知(两个页面各一条,谁改了大家都跟上)
		NNWReadingModeApply.modeDidChange(coordinator: coordinator)

		// 三个档各一张头图(Phase 3):换档时把画也换掉,交叉淡入
		nnwUpdateFeedListHeader(crossfade: true)

		// 列表内容整片变了,给一点过渡 —— 否则"手一滑,内容瞬间变样"像是 app 抽了一下。
		// ⚠️ 只做**淡入淡出**,不碰 contentInset / contentOffset(L73:那两个是一对,动一个必须动另一个)。
		if let collectionView {
			UIView.transition(with: collectionView, duration: 0.22,
							  options: [.transitionCrossDissolve, .allowUserInteraction],
							  animations: {}, completion: nil)
		}

		nnwReloadVisibleRowCounts()
	}

	/// 让上游那个「隐藏已读源」跟当前档位对齐。
	///
	/// 上游只给了 `toggleReadFeedsFilter()`(切换),没有 setter ——
	/// 所以这里判断"现在和想要的不一致"才切一下。**这样零上游改动**,
	/// 而且顺带白拿了它内部做的事:重建整棵树、存进 AppDefaults、刷新界面。
	private func nnwSyncReadFeedsFilterToMode() {
		let wanted = NNWReadingModeStore.shared.hidesFullyReadFeeds
		if coordinator.isReadFeedsFiltered != wanted {
			coordinator.toggleReadFeedsFilter()
		}
	}

	/// 把可见行右边那个数字重算一遍(L68:不在身份里的东西不会自己上屏)。
	///
	/// 放在下一轮 runloop:上一步 `toggleReadFeedsFilter` 会重建整棵树并 apply 一次快照,
	/// 动画途中"第几行是谁"还没落定,紧跟着刷可能把 A 的数字写进 B 那一行(L68 的第 2 个坑)。
	private func nnwReloadVisibleRowCounts() {
		DispatchQueue.main.async { [weak self] in
			guard let self, let collectionView = self.collectionView, let dataSource = self.dataSource else { return }

			// 记下"这批行是按哪个档画的",返回本页时才知道要不要重画(见 nnwRenderedMode)
			self.nnwRenderedMode = NNWReadingModeStore.shared.mode

			// ① 每一行
			let identifiers = collectionView.indexPathsForVisibleItems.compactMap { dataSource.itemIdentifier(for: $0) }
			if !identifiers.isEmpty {
				var snapshot = dataSource.snapshot()
				snapshot.reloadItems(identifiers)
				dataSource.apply(snapshot, animatingDifferences: false)
			}

			// ② 账户分组头上的数字。
			// **直接改已经在屏幕上的那个视图**,不走 `reloadSections` —— 后者会把整段行也一并重建,
			// 而"对列表下批量命令"正是这个页面崩过的路(L66/L68 的结论:能不走批量更新就不走)。
			for view in collectionView.visibleSupplementaryViews(ofKind: UICollectionView.elementKindSectionHeader) {
				guard let header = view as? MainFeedCollectionHeaderReusableView,
					  case .account(let accountID)? = header.sectionHeaderType,
					  let account = AccountManager.shared.existingAccount(accountID: accountID) else { continue }
				header.unreadCount = NNWReadingModeStore.shared.displayedCount(unreadCount: account.unreadCount)
			}
		}
	}
}

#endif
