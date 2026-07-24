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
		if #available(iOS 26, *) {
			navigationItem.preferredSearchBarPlacement = .integratedButton
		}
	}

	private static var nnwPendingSearchKey: UInt8 = 0
	private static var nnwCameFromGlobalSearchKey: UInt8 = 0

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
		// 记住"这次是从首页的放大镜进来的" —— 退出搜索时要据此直接回首页
		objc_setAssociatedObject(self, &Self.nnwCameFromGlobalSearchKey, true, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

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
		guard navigationItem.preferredSearchBarPlacement != .stacked else { return }
		nnwUseStackedSearchPlacement()
	}

	/// 只负责**激活**。摆法早在点按钮那一刻就改好了(见 `nnwRequestGlobalSearch` 里的说明)。
	private func nnwActivateSearchNow() {
		showSearchAll()
		nnwWatchForSearchDismissal()
	}

	/// 盯着搜索框自己的状态,一旦它不再激活就退出这个空页面。
	///
	/// ## 为什么要用"盯状态"这种笨办法(2026-07-23,前面两版都没修好)
	///
	/// 先后挂过 `willDismissSearchController` 和 `didDismissSearchController`,
	/// 用户实测**点 X 之后仍然停在空白页** —— 说明这两条回调至少有一条在这条路径上没走到
	///(iOS 26 的搜索收起有好几种走法:点 X、下拉、按返回,流程并不一样)。
	///
	/// 与其继续猜是哪一条回调、什么时候来,不如**直接看那个我真正关心的事实**:
	/// 「搜索框还激活着吗」。它是 `navigationItem.searchController.isActive`,
	/// 一个随时可以读的状态,不依赖任何回调时序。
	///
	/// 代价:搜索期间每 0.3 秒问一次。**只在"从首页进来的那次搜索"期间跑**,
	/// 标记一清(退出去了、或判定不该退)循环立刻结束,不会长期空转。
	///
	/// 教训:**当"等某个回调"反复不可靠时,改成"轮询那个你真正关心的状态"往往是对的** ——
	/// 回调是别人承诺的时序,状态是随时可验的事实。
	private func nnwWatchForSearchDismissal() {

		DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in

			guard let self else { return }
			// 标记没了 = 已经处理过(退出去了,或判定这次不该退)→ 循环结束
			guard objc_getAssociatedObject(self, &Self.nnwCameFromGlobalSearchKey) as? Bool == true else { return }

			if self.navigationItem.searchController?.isActive == false {
				self.nnwPopIfCameFromGlobalSearch()
			} else {
				self.nnwWatchForSearchDismissal()
			}
		}
	}

	/// 退出搜索时:如果这次是**从首页的放大镜**进来的,直接回首页。
	///
	/// ## 为什么需要这一手(2026-07-23 用户报「点 X 之后是一片白屏,还得再点返回」)
	///
	/// 全局搜索这条路是上游的:**先取消当前选中的源**、再推出文章列表页。
	/// 所以退出搜索之后,那一页本来就**没有源可显示** —— 一片空白。
	/// 用户是从首页点放大镜进来的,退出搜索理应直接回首页,而不是留在一个空页面上。
	///
	/// ⚠️ **只在"从首页进来"时才回退**:如果是在某个源里点放大镜搜的,
	/// 退出后应该留在那个源的文章列表上(那一页有内容,不是空的)。
	@objc func nnwPopIfCameFromGlobalSearch() {

		guard objc_getAssociatedObject(self, &Self.nnwCameFromGlobalSearchKey) as? Bool == true else { return }
		// **一次性**:不管这次退不退得成,这个标记都到此为止,免得以后莫名其妙地把人弹走
		objc_setAssociatedObject(self, &Self.nnwCameFromGlobalSearchKey, false, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

		// ⚠️ 判据是「**这一页还是不是栈顶**」,不是「时间线上有没有源」。
		// 原来用后者,结果撞上一个时序问题:搜索框刚关、上游的 `endSearching()` 还没跑完,
		// 那一刻 `timelineFeed` 还挂着搜索结果那个临时源(不是 nil)→ 判定成"不该退"→ 永远退不出去。
		// 「还在不在栈顶」是当场就能确定的事实:
		// 还在 = 用户没往别处去过,该退;不在 = 他点进了某篇文章,别打扰他。
		// 已经点进别的页面(比如某篇文章)就别打扰他
		if let navigationController, navigationController.topViewController !== self { return }

		// ⚠️ 用**分栏控制器**的「回到第一栏」,不用 popViewController ——
		// iPhone 上这两页未必在同一个导航栈里,pop 可能是个空操作(详见 SceneCoordinator 里那段注释)。
		coordinator?.nnwReturnToFeedList()
	}

	/// 兜底:搜索开始收起之后再看一眼,该退还没退就自己退。
	///
	/// 为什么要兜底:`didDismissSearchController` 在不同 iOS 版本、不同收起路径下
	/// 不一定都会来(点 X、下拉收起、按返回键,走的流程不一样)。
	/// 这里晚 0.6 秒再确认一次 —— 那个标记只生效一次,所以**不会退两下**。
	@objc func nnwSchedulePopFallbackAfterSearch() {
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
			self?.nnwPopIfCameFromGlobalSearch()
		}
	}

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
