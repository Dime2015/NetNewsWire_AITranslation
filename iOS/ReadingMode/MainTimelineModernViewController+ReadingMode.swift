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
		// 搜索激活着的时候摆法必须停在 `.stacked`(范围条只在这个摆法下显示),
		// 这里若把它冲回 `.integratedButton`,范围条会当场消失。
		// (L71:往别人的方法里插一行,要问"我这行跑完之后还有谁会改同一个东西"。)
		//
		// 📌 2026-07-28 全局搜索改成 modal(方案 D)后,这里原来还有一条
		// "待打开全局搜索期间也不许改"的守卫,已随那套挂起机制一起删除 ——
		// 全局搜索不再经过这一页,剩下的唯一风险就是上面这条 isActive。
		if navigationItem.searchController?.isActive == true { return }

		navigationItem.preferredSearchBarPlacement = .integratedButton

		// 顺手把范围条交还给系统(见 `nnwHandScopeBarBackToSystem`)。
		// ⚠️ 这里**只能调那个小方法,不能调 `nnwPrepareSearchBarForPresentation()`** ——
		// 后者会把摆法改成 `.stacked`,而这一趟是页面初始化,摆法必须停在 `.integratedButton`,
		// 否则搜索框会常驻在标题下面,和头图、自绘标题打架(2026-07-28 自己踩的,L71 的形状)。
		nnwHandScopeBarBackToSystem()
	}

	/// 把范围条的显示/收起交还给系统(`.onSearchActivation` = 搜索一激活就显示)。
	///
	/// ## ⚠️ 为什么"手动打开范围条"反而是范围条不显示的原因(SDK 头文件实证)
	///
	/// 上游原来在 `willPresentSearchController` 里写 `searchBar.showsScopeBar = true`。
	/// 而 `UISearchController.h` 写着:
	///
	/// > 默认情况下 UISearchController **本来就会**在搜索激活时自动显示范围条
	/// > (只要 `scopeButtonTitles` 至少两项),关闭时自动收起。
	/// > **只要你去设 `showsScopeBar`,就等于告诉系统"这事我自己管"**
	/// > (`scopeBarActivation` 变成 `.manual`)—— 从此系统撒手,时机和 `sizeToFit` 全得自己伺候。
	///
	/// 也就是说那句"打开范围条"的代码把系统的自动档关掉了,我们再用一套更脆的手动逻辑去顶,
	/// 换个摆法、重排一次就丢。现在改成显式声明自动档,之后**一行都不碰 `showsScopeBar`**。
	///
	/// (L70 的又一次应验:别凭印象用系统能力,先去读头文件。)
	private func nnwHandScopeBarBackToSystem() {
		if #available(iOS 16, *) {
			navigationItem.searchController?.scopeBarActivation = .onSearchActivation
		}
	}

	// ⚠️ 这里原本有一套「首页点放大镜 → 记一笔待办 → 本页 viewDidAppear 时再激活搜索」的
	// 挂起机制(nnwRequestGlobalSearch / nnwConsumePendingGlobalSearch / nnwActivateSearchNow,
	// 时序试错史见 NOTES-lessons L79)。**2026-07-28 整套删除** ——
	// 全局搜索改成了独立的 modal 页面(方案 D,见 NNWGlobalSearchViewController.swift),
	// 不再借这一页激活搜索框,上游 viewDidAppear 里的那行钩子也一并撤了。
	// 本页保留的搜索钩子只剩「摆法」三件套(下面这几个),服务的是**本页自己的放大镜**。

	/// 搜索**即将展开**时调:把摆法切成 `.stacked`,并把范围条交还给系统。
	/// 由上游 `willPresentSearchController` 里「一行换一行」调用
	///(原来那行是 `searchController.searchBar.showsScopeBar = true`)。
	///
	/// ## ⚠️ 摆法为什么必须在**这里**切,不能在 `didPresent`(2026-07-28,四轮才定案)
	///
	/// 范围条(该列表/全部文章)一度整个不显示。日志实录钉死了原因:
	///
	/// > `实际摆法=4(integratedButton),激活策略=3(正确),选项数=2(够),showsScopeBar=true`
	/// > —— **状态全对,范围条就是不画。**
	///
	/// 结论:**iOS 26 的 `.integratedButton` 摆法根本不渲染范围条**,
	/// 不管开关拨得多正确。范围条只在 `.stacked` 下才有安身之处。
	///
	/// 而摆法之前一直是在 `didPresent`(搜索已经展开之后)才切的 ——
	/// **那时搜索栏早排完版了,来不及**。挪到 `willPresent`(排版之前)当场就好了。
	///
	/// L79 第四版写着「改摆法和激活搜索必须分处两个排版回合」,看着矛盾,其实不冲突:
	/// **那条针对的是「由代码激活」的全局搜索** —— 方案 D 之后全局搜索走独立 modal,
	/// 不再经过这一页;这一页的搜索永远是用户自己点出来的,是系统在推流程,不是我们抢拍。
	@objc func nnwPrepareSearchBarForPresentation() {

		nnwHandScopeBarBackToSystem()

		// 摆法换成 `.stacked`(标题在上、搜索框在下、范围条再下面)。
		// 平时是 `.integratedButton`(把工具栏正中让给三档控件),
		// 退出搜索时由 `nnwRestoreSearchPlacement()` 换回去。
		if #available(iOS 26, *) {
			navigationItem.preferredSearchBarPlacement = .stacked
		}
		view.layoutIfNeeded()	// 逼它当场生效,别拖到下一个不知道什么时候的排版回合
	}

	// ⚠️ 这里原本还有一个 `nnwUseStackedSearchPlacementIfNeeded()`(挂在上游 didPresent 上)。
	// **2026-07-28 删除** —— 切摆法已经提到 `willPresent` 了,didPresent 那一趟无事可做,
	// 上游的 `didPresentSearchController` 方法也一并撤回了原样。

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
