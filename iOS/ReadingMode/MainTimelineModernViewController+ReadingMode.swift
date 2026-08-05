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
import Account	// [翻译] 齿轮按钮要判断"当前时间线是不是单一订阅源"(timelineFeed is Feed)

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

	/// 本页右上角的一组按钮:放大镜(常驻)+ 齿轮(只有单一订阅源的页面有)。
	/// **由上游 `resetUI()` 里「一行换一行」装上**。
	///
	/// ⚠️ 为什么必须装在那一行、而不是自己找个地方装一次:
	/// `resetUI()` 里有一句会把 `rightBarButtonItem` **置空**(漏斗按钮被三档接管后就一直是 nil),
	/// 而它会被反复调用 —— 装在别处会被它一次次擦掉(L74:先数清楚这个位置有几个写入点)。
	///
	/// 数组顺序 = 从右往左:放大镜保持最右(老位置、老习惯),齿轮挨在它左边。
	/// 齿轮 = 这个源的设置页(2026-07-29 用户要求,取代初版头图上的 info 圆钮)。
	@objc func nnwNavBarButtonItems() -> [UIBarButtonItem] {
		var items = [nnwSearchBarButtonItem()]
		if coordinator?.timelineFeed is Feed {
			// [外观] 2026-08-05:和首页那两颗同一套 —— 手绘图标 + 磨砂圆钮 + 拆系统玻璃胶囊。
			// 这两颗也压在**头图**上,所以底必须是真磨砂(理由见 NNWSoftGlassButton 文件头)。
			let button = NNWSoftGlassButton(icon: NNWDockIcons.gear())
			button.addTarget(self, action: #selector(nnwFeedSettingsTapped), for: .touchUpInside)
			button.accessibilityLabel = "源信息与设置"
			let gear = UIBarButtonItem(customView: button)
			gear.nnwHideSystemGlassCapsule()
			gear.accessibilityLabel = "源信息与设置"
			items.append(gear)
		}
		return items
	}

	@objc func nnwSearchBarButtonItem() -> UIBarButtonItem {
		let button = NNWSoftGlassButton(icon: NNWDockIcons.search())
		button.addTarget(self, action: #selector(nnwSearchTapped), for: .touchUpInside)
		button.accessibilityLabel = "搜索文章"
		let item = UIBarButtonItem(customView: button)
		item.nnwHideSystemGlassCapsule()
		item.accessibilityLabel = "搜索文章"
		return item
	}

	/// [外观] 2026-08-05:把本页底部工具栏那两颗(标记全部已读 / 下一篇未读)
	/// 换成和首页齿轮、加号同一套的**软面板圆钮**。
	///
	/// ⚠️ 只换 `image` —— `markAllAsReadButton` 是 storyboard 的 IBOutlet、
	/// `nextUnreadButton` 上游还在改 `isEnabled`,换掉对象会打断那些写入点。
	/// 面板烘焙进图片的做法与首页完全一致(见 NNWSoftMaterial.roundButtonImage)。
	@objc func nnwRestyleTimelineToolbarIcons() {
		guard NNWSoftMaterial.isEnabled else { return }
		for item in toolbarItems ?? [] {
			guard let action = item.action else { continue }
			// 上游给的原图尺寸不一,先压到 20pt 再合成,免得几颗圆钮里的图标大小不齐
			let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
			guard let base = item.image?.applyingSymbolConfiguration(config) ?? item.image else { continue }
			// ⚠️ `markAllAsRead` 有两个重载(sender 版 / articles 版),`#selector` 会歧义,
			// 必须把类型标出来指定是哪一个。
			let markAll = #selector(MainTimelineModernViewController.markAllAsRead(_:)
									as (MainTimelineModernViewController) -> (Any?) -> Void)
			if action == markAll || action == #selector(MainTimelineModernViewController.nextUnread(_:)) {
				item.image = NNWSoftMaterial.roundButtonImage(icon: base, traits: traitCollection)
				item.nnwHideSystemGlassCapsule()
			}
		}
	}

	@objc private func nnwSearchTapped() {
		// 带上"当前列表"的范围 —— 搜索页会因此多出「该列表 / 全部文章」两档,默认搜该列表
		coordinator?.nnwShowGlobalSearch(restrictedToCurrentTimeline: true)
	}

	@objc private func nnwFeedSettingsTapped() {
		// 无参版自己从 timelineFeed 取源;智能源/文件夹根本不会有这个按钮
		coordinator?.showFeedInspector()
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
