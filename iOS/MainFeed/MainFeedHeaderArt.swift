//
//  MainFeedHeaderArt.swift
//  NetNewsWire — AI 翻译 fork
//
//  [外观] 给**订阅源列表页(首页)**装顶部头图 —— 和文章列表页那套是同一个头图区,
//  只是素材换成手工挑的画、标题写 app 名「Babel」。
//  本 fork 新增文件,上游没有。
//
//  ## 为什么这个文件只有几十行
//
//  头图区那套东西(图铺满全宽 → 上浓下淡 → 压纸色蒙版 → 标题压在最下方 →
//  往下滚标题飞到导航栏)**本来就是通用的** ——
//  `TimelineFeedHeaderController` 接受任意 host 与 collectionView。
//  所以这一页要做的只是:告诉它"用哪张画、写什么字、多高"。
//
//  ## ⚠️ 这一页和文章列表页不同的三件事
//
//  1. **矮一档**:头图占 **1/5 屏**,不是 1/4(用户 2026-07-23 定的)。
//     理由:订阅列表是拿来**找东西**的,77 个源 + 7 个文件夹,
//     让出 1/4 屏的代价比文章列表大 —— 文章列表本来就要往下滚。
//  2. **标题是 app 名「Babel」**,不是页面原名(Feed / 订阅)。首页是整个 app 的门面。
//  3. **这一页有下拉刷新**。头图会往 `contentInset.top` 里加一段,
//     两者叠在一起时刷新圈可能转在头图里 —— 这一条只能靠实测,已列进验收清单。
//
//  ## 对上游文件的改动:只有一行
//
//  `MainFeedCollectionViewController.viewWillAppear` 里加一行调用。
//  按 CLAUDE.md,这个文件原本只允许在 `add(_:)` 里加一行;
//  **用户已于 2026-07-23 同意扩到两行** —— 新增那行只是"调用我们自己的方法",
//  实现全在本文件里,merge 冲突风险仍然极低。
//

#if os(iOS)

import UIKit

extension MainFeedCollectionViewController {

	private static var nnwHeaderKey: UInt8 = 0

	/// 装 / 更新首页顶部的头图区。**每次页面出现时调一次**。
	///
	/// 为什么挂在 `viewWillAppear` 而不是 `viewDidLoad`:从别的页面返回时
	/// 导航栏的外观、工具栏都会被重设一遍,头图这边也要跟着重新接管一次。
	/// (而且它内部有防重入:同一个内容不会重复渲染。)
	/// - Parameter crossfade: 换档引起的换图请传 true —— 整幅插画硬切会像闪了一下
	func nnwUpdateFeedListHeader(crossfade: Bool = false) {
		guard TimelineStyle.headerEnabled, TimelineStyle.smartHeaderEnabled else { return }

		let controller: TimelineFeedHeaderController
		if let existing = objc_getAssociatedObject(self, &Self.nnwHeaderKey) as? TimelineFeedHeaderController {
			controller = existing
		} else {
			controller = TimelineFeedHeaderController()
			objc_setAssociatedObject(self, &Self.nnwHeaderKey, controller, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
		}

		if crossfade {
			controller.nnwCrossfadeNextRender()
		}

		// [阅读档] 三个档各一张画(2026-07-23):换档时头图跟着换,一眼看出自己在哪一档。
		// 换图的淡入淡出由头图控制器自己做(和深浅色切换共用同一套交叉淡入)。
		let entry = SmartFeedHeaderCatalog.feedListEntry(for: NNWReadingModeStore.shared.mode)

		controller.update(subject: .art(entry,
										title: SmartFeedHeaderCatalog.feedListTitle,
										heightFraction: TimelineStyle.feedListHeaderHeightFraction),
						  host: self,
						  collectionView: collectionView)
	}
}

#endif
