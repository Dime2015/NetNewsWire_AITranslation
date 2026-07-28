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
//  ## ⚠️ 搜索没有被删掉,是**换了个去处**
//
//  搜索仍在,只是从"常驻输入框"变成**导航栏右上角一个放大镜按钮**;
//  点它打开我们自己的 modal 搜索页(`NNWGlobalSearchViewController`),
//  在那一页里可以切「该列表 / 全部文章」。
//
//  右上角原本是「漏斗」,已经被三档接管拿掉了,所以那儿正好空着 ——
//  **净变化为零:漏斗走了,放大镜来了。**
//
//  ⚠️ 这一页**刻意不再挂系统的 UISearchController**(2026-07-28,第五轮定案):
//  系统那条范围条只在 `.stacked` 摆法下渲染,而用 `.stacked` 就得在搜索进出时切摆法,
//  等于让导航栏忽高忽低,把头图、会飞的标题、列表内边距一起带乱(用户真机 iOS 27 beta 实测)。
//  详见 `nnwDetachSystemSearchController` 的注释与 NOTES-lessons L94 / L95。
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

	/// 把这一页的搜索从**系统的搜索控制器**换成**我们自己的放大镜按钮**(开 modal 搜索页)。
	/// 由上游 `configureToolbar()` 里加的一行调用(只在 viewDidLoad 跑一次)。
	///
	/// ## ⚠️ 为什么要把系统那套整个摘掉(2026-07-28,第五轮才定案)
	///
	/// 这一页原本用系统的 `UISearchController`,而它自带的**范围条(该列表/全部文章)
	/// 只在 `.stacked` 摆法下才渲染**(日志实证:`.integratedButton` 下状态全对也不画)。
	/// 于是我们只能在搜索进出时切摆法 —— 而**切摆法 = 让导航栏变高变矮**,
	/// 下游一整串按安全区算坐标的自绘元素(头图、会飞的标题、列表内边距)全得跟着重排。
	///
	/// 为此修了两轮(挂 `didDismiss` 收尾、给自绘视图补 `safeAreaInsetsDidChange`),
	/// 用户真机(**iOS 27 beta**)上仍然乱 —— 而开发机的 SDK 与模拟器都是 26,**测不到那个系统**。
	///
	/// 所以按 L92 的老规矩:不修机制,**消掉机制的前提** ——
	/// 这一页不再挂系统搜索控制器,导航栏高度从此**恒定**,那一整族问题连根消失。
	/// 搜索改由我们自己的 modal 页承担(`NNWGlobalSearchViewController`),
	/// 范围切换在那一页里用一条普通的分段控件实现,完全自己掌控。
	@objc func nnwDetachSystemSearchController() {

		// 摘掉系统搜索控制器:导航栏不再会因为搜索而变高。
		// (上游 `configureSearchController()` 在 viewDidLoad 里比本方法早一步装上它,
		//  所以这里摘得掉;它全仓只在那一处装配,摘掉之后不会有人再装回来 —— 已 grep 确认。)
		navigationItem.searchController = nil
	}

	/// 本页右上角那个放大镜。**由上游 `resetUI()` 里「一行换一行」装上**。
	///
	/// ⚠️ 为什么必须装在那一行、而不是自己找个地方装一次:
	/// `resetUI()` 里有一句会把 `rightBarButtonItem` **置空**(漏斗按钮被三档接管后就一直是 nil),
	/// 而它会被反复调用 —— 装在别处会被它一次次擦掉(L74:先数清楚这个位置有几个写入点)。
	@objc func nnwSearchBarButtonItem() -> UIBarButtonItem {
		let item = UIBarButtonItem(image: UIImage(systemName: "magnifyingglass"),
								   style: .plain, target: self, action: #selector(nnwSearchTapped))
		item.accessibilityLabel = "搜索文章"
		return item
	}

	@objc private func nnwSearchTapped() {
		// 带上"当前列表"的范围 —— 搜索页会因此多出「该列表 / 全部文章」两档,默认搜该列表
		coordinator?.nnwShowGlobalSearch(restrictedToCurrentTimeline: true)
	}

	// ⚠️ 这里原本有一整套「搜索栏摆法」的机制(nnwUseCompactSearchPlacement /
	// nnwPrepareSearchBarForPresentation / nnwUseStackedSearchPlacement /
	// nnwUseStackedSearchPlacementIfNeeded / nnwRestoreSearchPlacement),
	// 以及上游 willPresent / didPresent / willDismiss 上的三处钩子。
	// **2026-07-28 全部删除** —— 这一页不再挂系统搜索控制器,摆法这件事整个不存在了。
	// 死因与五轮试错见 NOTES-lessons L94 / L95。别再加回来。

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
