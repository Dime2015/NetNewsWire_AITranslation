//
//  MainTimelineModernViewController+ReadingMode.swift
//  NetNewsWire — AI 翻译 fork
//
//  [阅读档] 把三档控件也装到**文章列表页**的底部工具栏上(2026-07-23 用户要求)。
//  本 fork 新增文件,上游没有。
//
//  ## 它占的是「搜索文章」原来的位置
//
//  iOS 26 上这一页的底部工具栏是:
//  ```
//  [全部标为已读]  ⟷  [搜索文章(输入框)]  ⟷  [下一条未读]
//  ```
//  中间那个是 `navigationItem.searchBarPlacementBarButtonItem` ——
//  iOS 26 的新玩法:把系统搜索框直接摆进工具栏。用户要把那块地方让给三档控件。
//
//  ## ⚠️ 搜索没有被删掉,是**换了个摆法**
//
//  搜索仍在,只是从"常驻输入框"变成**导航栏右上角一个放大镜按钮**
//  (`preferredSearchBarPlacement = .integratedButton`,iOS 26 才有的摆法,
//  已查过 SDK 头文件确认存在 —— L70 的教训:别凭印象用系统能力)。
//  点它就展开成输入框,搜完收起。
//
//  右上角原本是「漏斗」,已经被三档接管拿掉了,所以那儿正好空着 ——
//  **净变化为零:漏斗走了,放大镜来了。**
//
//  ## 这一页刻意**不做**左右滑切档
//
//  订阅列表页能做,是因为那一页的行左滑已经拿掉了。
//  而这一页的行左滑是「加星标 / 标为已读」—— 有用,用户也没要求拿掉。
//  两者共存必然打架,所以这一页只有控件,没有手势。
//

#if os(iOS)

import UIKit

extension MainTimelineModernViewController {

	/// 造本页那条三档控件的工具栏项。**由上游 `configureToolbar()` 里"一行换一行"调用**
	///(原来那行是 `navigationItem.searchBarPlacementBarButtonItem`)。
	@objc func nnwReadingModeToolbarItem() -> UIBarButtonItem {
		nnwReadingModeBarItem { [weak self] mode in
			self?.nnwSelectReadingMode(mode)
		}
	}

	/// 把搜索改成"右上角一个放大镜按钮"。
	///
	/// 为什么必须显式设:原来搜索是靠"工具栏里摆了 searchBarPlacementBarButtonItem"才落在底部的。
	/// 我们把那一项换掉之后,系统会按默认摆法处理 —— 多半是**压在标题下面那一条**,
	/// 而这一页的标题区被我们的头图和自绘标题占着,挤进去会打架。
	@objc func nnwUseCompactSearchPlacement() {
		guard #available(iOS 26, *) else { return }

		// ⚠️ **搜索期间不许改回来**(2026-07-28,用户报"范围条不见了")。
		//
		// 这个方法由上游的 `configureToolbar()` 调用,而 `configureToolbar()`
		// 会在选中源、刷新列表等好几个时机被触发。全局搜索改成方案 B(进搜索前先选中
		// 「全部未读」)之后,它就会**在搜索激活前后多跑一次**,把我们设好的 `.stacked`
		// 冲回 `.integratedButton` —— 而范围条(该列表/全部文章)**只在 .stacked 下显示**,
		// 于是范围条整个消失。
		//
		// 日志实锤:didPresent 时读到摆法=4(.integratedButton),而我们想要的 .stacked 是 2。
		//
		// (L71:往别人的方法里插一行,要问"我这行跑完之后还有谁会改同一个东西";
		//  L74:同一个值有几个写入点,得数清楚。)
		if navigationItem.searchController?.isActive == true { return }
		if objc_getAssociatedObject(self, &Self.nnwPendingSearchKey) as? Bool == true { return }

		navigationItem.preferredSearchBarPlacement = .integratedButton
	}

	private static var nnwPendingSearchKey: UInt8 = 0

	// MARK: - [阅读档] 全局搜索的"来处"

	/// 首页点了放大镜,记一笔"待打开搜索"。**真正打开在 `viewDidAppear`。**
	///
	/// ## 为什么最后落到 viewDidAppear(前后错了两版,见 L79)
	///
	/// 首页点放大镜时,这一页正**在被推进来的路上**,而搜索框必须等页面上了屏、
	/// 导航栏排好了才能装 —— 早了要么排在没有安全区的地方,要么干脆不出现。
	///
	/// - **第一版**:照上游 `showSearch()` 的老办法,推完页面等一个 runloop 就打开
	///   → 搜索框整块**上移一个状态栏的高度**,和时间叠在一起。
	/// - **第二版**:改成"每轮 runloop 看一眼是否就绪,最多 30 轮"
	///   → 30 轮 runloop 只有几毫秒,而推入动画要 0.35 秒,**根本没等到就放弃了**;
	///   再改成盯转场协调器,第一次进来时那个协调器又拿不到(推入还没开始)
	///   → 表现成"第一次点没反应、退出再点才出来"。
	/// - **这一版**:不猜时机了。挂到 **`viewDidAppear`** ——
	///   那是系统唯一保证"页面已经在屏幕上、导航栏也排好了"的时刻。
	///   不管推入走的是哪条路、动画多长,它一定在合适的时候到。
	///
	/// **教训:与其算"什么时候好了",不如挂到系统告诉你"好了"的那个回调上。**
	func nnwRequestGlobalSearch() {

		objc_setAssociatedObject(self, &Self.nnwPendingSearchKey, true, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

		// ⚠️⚠️ **摆法必须现在就改,不能等到激活的那一刻**(2026-07-23,第四版才对)。
		//
		// 证据来自用户自己的观察:上一版"第一次点空白、退出再点就正常" ——
		// 第二次之所以正常,正是因为**摆法在第一次点的时候就已经改成 `.stacked` 了**,
		// 到第二次激活时它早就落定。也就是说:
		// **改摆法和激活搜索必须分处两个排版回合**,挤在一起就只生效一半
		// (范围条出来了、搜索框没装上 —— 用户最后那张截图正是这个样子)。
		//
		// 现在:点按钮的这一刻改摆法 → 推入页面(整个动画过程)→ viewDidAppear 里才激活。
		// 中间隔着一整段时间,绝无可能还没落定。
		nnwUseStackedSearchPlacement()

		// 兜底:万一这一页**本来就在屏幕上**(不会推入,也就不会有 viewDidAppear),
		// 等一小会儿还没被消费掉就自己动手。
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
			self?.nnwConsumePendingGlobalSearch()
		}
	}

	/// 由上游 `viewDidAppear` 里加的一行调用(以及上面那个兜底)。**只会生效一次。**
	@objc func nnwConsumePendingGlobalSearch() {
		guard objc_getAssociatedObject(self, &Self.nnwPendingSearchKey) as? Bool == true else { return }
		objc_setAssociatedObject(self, &Self.nnwPendingSearchKey, false, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
		nnwActivateSearchNow()
	}

	/// 搜索期间换成**经典的「标题下面一条」摆法**(`.stacked`):
	/// 导航栏在上、搜索框在下、范围条再下面 —— 十年来最稳的那条路。
	///
	/// 平时用 `.integratedButton`(只占一个放大镜,把工具栏正中让给三档控件),
	/// 但那个摆法是**给用户点按钮触发**设计的,由代码激活时排版一直不对。
	/// 退出搜索时换回去(见 `nnwRestoreSearchPlacement`)。
	private func nnwUseStackedSearchPlacement() {
		if #available(iOS 26, *) {
			navigationItem.preferredSearchBarPlacement = .stacked
		}
		// 立刻走一遍布局,别把这件事拖到下一次不知道什么时候的排版回合
		view.layoutIfNeeded()
	}

	/// 搜索已经展开了,但摆法还是"内嵌按钮"(从某个源里点放大镜进来的情形)→ 换成 stacked。
	/// **只有这样范围切换条(本列表 / 全部文章)才会显示出来。**
	/// 由上游 `didPresentSearchController` 里加的一行调用。
	@objc func nnwUseStackedSearchPlacementIfNeeded() {
		guard #available(iOS 26, *) else { return }

		let sb = navigationItem.searchController?.searchBar

		// 原来这里有一句 `guard 已经是 stacked 就跳过`。**去掉了** ——
		// 摆法即使已经是 stacked,范围条也可能没跟着装上(它由搜索栏自己管,不是摆法的附属品),
		// 于是这个"省一次调用"的守卫反而把补救的机会也一起省掉了(L77 家族:搭便车,车没开)。
		nnwUseStackedSearchPlacement()

		// 范围条要显式打开:`willPresentSearchController` 里虽然设过一次,
		// 但换摆法会重排搜索栏,那一次设置可能在重排中丢失。这里补一次,幂等无害。
		sb?.showsScopeBar = true
	}

	/// 只负责**激活**。摆法早在点按钮那一刻就改好了(见 `nnwRequestGlobalSearch` 里的说明)。
	private func nnwActivateSearchNow() {
		showSearchAll()
	}

	// ⚠️ 这里原本有约 90 行"退出搜索后自动逃回首页"的机制
	//(轮询 searchController.isActive + 一堆守卫 + nnwPopIfCameFromGlobalSearch)。
	// **2026-07-28 整个删除** —— 方案 B 之后全局搜索背后是「全部未读」那一页(有内容),
	// 空白页不存在了,也就不需要从空白页逃出来。
	// 完整的死因与 6 次试错记录见 `SceneCoordinator.nnwShowGlobalSearch()` 的注释与 L92。

	/// 退出搜索后把摆法换回"右上角一个放大镜"。
	/// 由上游 `willDismissSearchController` 里加的一行调用。
	@objc func nnwRestoreSearchPlacement() {
		if #available(iOS 26, *) {
			navigationItem.preferredSearchBarPlacement = .integratedButton
		}
	}

	private func nnwSelectReadingMode(_ mode: NNWReadingMode) {

		let previous = NNWReadingModeStore.shared.mode
		guard NNWReadingModeStore.shared.setMode(mode), let coordinator else { return }

		// 控件外观不用管 —— 两个页面的控件各自盯着通知
		NNWReadingModeApply.modeDidChange(coordinator: coordinator)

		// 文章整片换了,给一段**带方向的**过渡(和订阅列表页共用同一份实现,观感一致)。
		// 真正把文章换掉的是上面那句里的 refreshTimeline —— 它是**异步取数**,
		// 所以这层动画也顺带遮一下"旧的还在、新的还没到"的那一瞬。
		NNWReadingModeApply.animateSwitch(collectionView,
										  forward: NNWReadingModeApply.isForward(from: previous, to: mode))
	}
}

#endif
