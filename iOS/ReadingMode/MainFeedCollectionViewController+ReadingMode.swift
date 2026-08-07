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
	/// [外观] 「切深浅色要重画工具栏那两颗圆钮」的观察者只注册一次
	private static var nnwToolbarTraitObserverKey: UInt8 = 0

	/// 装好的两个切档手势。
	///
	/// ⚠️ 原来这里只存一个 `Bool` 标记(装没装过)。**2026-07-28 改成存手势对象本身** ——
	/// 因为原地编辑模式期间必须把它们**禁掉**(编辑态下横向手势到底是"切档"还是"拖行"
	/// 没法预期;而且切档会重建整棵树,将来加了拖放就是必崩路径,见 L65)。
	/// 只留一个 Bool 的话,拿不到手势对象,就没法开关。
	private var nnwModeSwipeGestures: [UISwipeGestureRecognizer]? {
		get { objc_getAssociatedObject(self, &Self.nnwGesturesKey) as? [UISwipeGestureRecognizer] }
		set { objc_setAssociatedObject(self, &Self.nnwGesturesKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
	}

	private var nnwGesturesInstalled: Bool { nnwModeSwipeGestures != nil }

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

		collectionView.nnwEnableSoftBottomEdgeFade()	// [外观] 补回被拍平的那道边缘渐隐
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

	/// [阅读档][外观] 2026-08-05:**控件不再插进工具栏,改成浮在页面之上。**
	///
	/// 为什么搬(用户报的「内圈比外圈小很多」+ T43 陀螺仪的前置条件)、
	/// 以及位置是怎么算的,全写在 `NNWFloatingModeBar.swift` 的文件头。
	///
	/// ⚠️ 顺带的好处:`toolbarItems` 回到故事板原样的 3 项 ——
	/// 原来我们往里插了 [控件][空白] 两项,把 `expectedItemCount == 3` 那条守卫撑破了
	/// (那时是靠"排在上游那句之后"绕开的)。现在连绕都不用绕。
	private func nnwInstallModeBarIfNeeded() {

		// [编辑] 编辑模式下工具栏整条换成 [新建文件夹][移动到…][删除],浮层要收起来
		if nnwIsEditingFeeds {
			nnwSetFloatingModeBarHidden(true)
			return
		}

		nnwInstallFloatingModeBar { [weak self] mode in
			self?.nnwSelectReadingMode(mode)
		}
		nnwSetFloatingModeBarHidden(false)
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

		// [编辑] 编辑模式期间右上角是「完成」,这里别去动它(否则一进编辑就被 viewWillAppear 冲掉)
		if nnwIsEditingFeeds { return }

		// 已经装过就别重造(viewWillAppear 会调很多次)
		// ⚠️ 判据从「第一项的 action 是不是放大镜」改成「第一项是不是我们的圆钮」——
		// 2026-08-04 改成 customView 之后 `item.action` 恒为 nil,老判据会永远判"没装过",
		// 每次 viewWillAppear 都重造一对按钮。
		if navigationItem.rightBarButtonItems?.first?.customView is NNWSoftGlassButton { return }

		// [外观] 2026-08-04:手绘图标 + 橙色(这一页的控件统一重绘)
		// [外观] 2026-08-04 二版:装进**磨砂圆钮**,并拆掉 iOS 26 的系统玻璃胶囊 ——
		// 和底栏中间那条三档同一套材质(整圈亮边 + 极淡阴影)。
		// ⚠️ 这两颗压在**头图**上,所以底必须是真磨砂,不能用工具栏那种烘焙的不透明圆盘
		// (试过,是两张贴纸)。缘由见 NNWSoftGlassButton 的文件头。
		let search = UIBarButtonItem(customView: nnwGlassButton(icon: Self.nnwNavSymbol("magnifyingglass"),
															   action: #selector(nnwGlobalSearchTapped),
															   label: "搜索全部订阅源"))
		search.nnwHideSystemGlassCapsule()
		search.accessibilityLabel = "搜索全部订阅源"

		// [管理] 「编辑订阅」入口(2026-07-25 用户拍板的方案乙):
		// 原来藏在右下角 + 的第二层选单里,不直觉 —— 提到导航栏,和放大镜并排。
		// 点开的就是文件夹管理页(批量移动/删除、建改删文件夹、拖拽重排都在那),
		// 页面标题已改叫「编辑订阅」,心智上 = 本列表的编辑模式。
		// 方框 + 从右上角伸出来的铅笔(2026-07-28 用户指定的样子,第三版才对)。
		// 先试过光秃秃的 `pencil`,又试过实心圆的 `pencil.circle.fill`(用户说丑),
		// 最后定在这个 —— 它也是 iOS 各处"编辑/撰写"的通用图标,辨识度最高。
		// [外观] 2026-08-05 **改回定过案的那版**(用户:「重绘左边的这个,太丑了」)。
		// ⚠️ 这个图标 2026-07-28 已经三版定案:光秃秃的 pencil → pencil.circle.fill(用户说丑)
		// → **square.and.pencil**(方框 + 从右上角伸出的铅笔,用户指定)。
		// 2026-08-04 那轮"全套手绘"又把它换掉了 —— 和分享/长图/翻译是同一个错误(L110)。
		let edit = UIBarButtonItem(customView: nnwGlassButton(icon: Self.nnwNavSymbol("square.and.pencil"),
															 action: #selector(nnwEditSubscriptionsTapped),
															 label: "编辑订阅"))
		edit.nnwHideSystemGlassCapsule()
		edit.accessibilityLabel = "编辑订阅"

		// 数组第一个在最右:搜索用得更勤,占最右;编辑在它左边
		navigationItem.rightBarButtonItems = [search, edit]
	}

	/// [外观] 导航栏圆钮里的系统符号。字号跟着圆钮直径走(约 45%),
	/// 这样以后改 `NNWSoftMaterial.controlDiameter`,图标会自己按比例变。
	static func nnwNavSymbol(_ name: String) -> UIImage {
		let size = (NNWSoftMaterial.controlDiameter * 0.45).rounded()
		let config = UIImage.SymbolConfiguration(pointSize: size, weight: .medium)
		return UIImage(systemName: name, withConfiguration: config) ?? UIImage()
	}

	/// [外观] 造一颗导航栏用的磨砂圆钮。
	private func nnwGlassButton(icon: UIImage, action: Selector, label: String) -> NNWSoftGlassButton {
		let button = NNWSoftGlassButton(icon: icon)
		button.addTarget(self, action: action, for: .touchUpInside)
		button.accessibilityLabel = label
		return button
	}

	/// [外观] 2026-08-04:把底部工具栏那两个系统图标(设置齿轮、加号)换成手绘橙图标。
	///
	/// ⚠️ **只换 image 和 tintColor,不碰 toolbarItems 的结构** ——
	/// 那个数组有两个硬约束:① `configureToolbarWithProgressView` 里
	/// `expectedItemCount == 3` 的守卫(数量一变刷新进度条就永久装不上,L19 那一族);
	/// ② `addNewItemButton` 是 storyboard 的 IBOutlet,别处还往它身上挂 menu 和 isEnabled。
	/// 换整个 item 会同时踩这两条。
	///
	/// [外观] 2026-08-04 二版:这两个键也换成**软面板圆钮**,和底栏中间那条三档同一套材质。
	/// 面板是**画进图片里**的 —— 因为这里只有 image 这一条通道可走
	/// (换 customView 会把加号身上上游挂的 `menu` 弄丢)。做法见
	/// `NNWSoftMaterial.roundButtonImage(icon:tint:diameter:)`。
	func nnwRestyleToolbarIcons() {

		nnwObserveStyleChangesForToolbarIcons()

		guard let items = toolbarItems else { return }

		for item in items {
			guard let action = item.action else { continue }
			switch action {
			case #selector(MainFeedCollectionViewController.add(_:)):
				item.image = NNWSoftMaterial.roundButtonImage(icon: NNWDockIcons.plus(),
															  traits: traitCollection)
				item.nnwHideSystemGlassCapsule()
			case #selector(MainFeedCollectionViewController.settings(_:)):
				item.image = NNWSoftMaterial.roundButtonImage(icon: NNWDockIcons.gear(),
															  traits: traitCollection)
				item.nnwHideSystemGlassCapsule()
			default:
				break
			}
		}
	}

	/// [外观] 切深浅色时把这两颗圆钮重画一遍。
	///
	/// ⚠️ 为什么必须自己盯着:面板是**画进图片**里的,而图片不会跟随深浅色。
	/// 试过用 `UIImageAsset` 登记浅/深两张让 UIKit 自己挑 —— **实测不生效**
	/// (2026-08-04 深色下截图,两颗仍是浅色的,重启 app 也一样)。
	/// 所以退回最笨的做法:自己监听,自己重画。
	private func nnwObserveStyleChangesForToolbarIcons() {
		guard objc_getAssociatedObject(self, &Self.nnwToolbarTraitObserverKey) == nil else { return }
		objc_setAssociatedObject(self, &Self.nnwToolbarTraitObserverKey, true, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
		registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (controller: MainFeedCollectionViewController, _) in
			controller.nnwRestyleToolbarIcons()
		}
		// [外观] 换强调色之后同样要重画(理由完全一样:面板是烘焙进图片的)
		nnwObserveAccentChanges { [weak self] in
			self?.nnwRestyleToolbarIcons()
			self?.nnwReinstallDefaultRightBarButtons()
			// 分组头与文件夹行的三角色是**配装 cell 时**写进去的,不重画就还是旧颜色
			self?.collectionView.reloadData()
		}
	}

	/// [编辑] 退出编辑模式时**显式**把右上角装回去。
	///
	/// ⚠️ 不能指望 `nnwInstallGlobalSearchButton()` 的幂等判断自己恢复 ——
	/// 那个判断看的是"第一个按钮是不是放大镜",而编辑模式把它换成了「完成」,
	/// 判断会误以为"没装过"→ 装回去;但顺序和时机都不由我们控制。显式重装最稳。
	func nnwReinstallDefaultRightBarButtons() {
		navigationItem.rightBarButtonItems = nil		// 先清掉「完成」,让下面的幂等判断必然放行
		nnwInstallGlobalSearchButton()
	}

	@objc private func nnwGlobalSearchTapped() {
		coordinator.nnwShowGlobalSearch()
	}

	/// [编辑] 铅笔的行为:**原地**进入编辑模式(2026-07-28 用户要求)。
	/// 旧「编辑订阅」页已于 2026-07-30 整个删除 —— 它做的每件事
	/// (新建/改名文件夹、拖放排序、批量删除/移动、删文件夹释放源)编辑模式都有了。
	@objc private func nnwEditSubscriptionsTapped() {
		nnwToggleFeedEditing()
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

		// ⚠️ 这两个手势能成立的前提是**行上的左滑已经拿掉**(见 configureCollectionView 里那行)。
		// 两者共存的话,手指往左一划到底是"划出行操作"还是"切档"没法区分 —— 用户 2026-07-23 也是这么要求的。
		var installed = [UISwipeGestureRecognizer]()
		for direction in [UISwipeGestureRecognizer.Direction.left, .right] {
			let gesture = UISwipeGestureRecognizer(target: self, action: #selector(nnwHandleModeSwipe(_:)))
			gesture.direction = direction
			// 竖直滚动不受影响:UISwipeGestureRecognizer 只认单一方向的快速划动,
			// 列表自己的 pan 该滚照滚(两者天生共存,不需要设 require-to-fail)。
			collectionView.addGestureRecognizer(gesture)
			installed.append(gesture)
		}
		nnwModeSwipeGestures = installed
	}

	/// [编辑] 进出原地编辑模式时开关切档手势。理由见 `nnwModeSwipeGestures` 的注释。
	func nnwSetModeSwipeGesturesEnabled(_ enabled: Bool) {
		nnwModeSwipeGestures?.forEach { $0.isEnabled = enabled }
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

		let previous = NNWReadingModeStore.shared.mode
		guard NNWReadingModeStore.shared.setMode(mode) else { return }

		// 控件外观不用管 —— 它自己盯着通知(两个页面各一条,谁改了大家都跟上)
		NNWReadingModeApply.modeDidChange(coordinator: coordinator)

		// 三个档各一张头图(Phase 3):换档时把画也换掉,交叉淡入
		nnwUpdateFeedListHeader(crossfade: true)

		// 内容整片换了,给一段**带方向的**过渡(两个页面共用同一份实现)
		NNWReadingModeApply.animateSwitch(collectionView,
										  forward: NNWReadingModeApply.isForward(from: previous, to: mode))

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
