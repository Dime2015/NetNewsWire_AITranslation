//
//  NNWReadingModeFeedListFilter.swift
//  NetNewsWire — AI 翻译 fork
//
//  [阅读档] ★ 档下,订阅列表该留哪些行。本 fork 新增,上游没有。
//
//  ## 为什么钩在「造快照」那一步,而不是造树那一步
//
//  上游有两层:**树**(`SidebarTreeControllerDelegate`,决定有哪些节点)→
//  **快照**(`SceneCoordinator.createSidebarSnapshot`,决定哪些节点变成屏幕上的行)。
//
//  钩在树那层更"根上",但那个文件在 `Shared/` 下 —— **macOS 也用它**,
//  改那里等于顺手改了 macOS 的侧栏(B 级禁区)。
//  快照这一层是 iOS 独有的,而且**只有一个出口**(`appendItems` 那一行),
//  所以钩在这里:上游净增一行,macOS 一点没碰。
//
//  ## ★ 档下的两条规则
//
//  1. **智能 Feed 组只留「已加星标」那一行**(用户 2026-07-23 拍板)。
//     ★ 档下摆着「全部未读」本来就自相矛盾 —— 那个源在上游是强制只看未读、不许切换的。
//     这样"从常驻列表里拿掉已加星标"的效果达到了,而"看我所有星标"的入口一个没丢。
//  2. **账户里只留有星标的源和文件夹**。
//     ⚠️ 星标数**还没数完之前一律放行** —— 那是异步查询(L53),
//     若把"还没数到"当成"没有星标",一进★档就是一片空白,看起来像功能坏了。
//

#if os(iOS)

import Foundation
import Account

@MainActor enum NNWReadingModeFeedList {

	/// 过滤一个分组里的行。`sectionID` 为空串表示这是「智能 Feed」那一组(上游的约定)。
	static func filtered(_ nodes: [SidebarItemNode], sectionID: String) -> [SidebarItemNode] {

		guard NNWReadingModeStore.shared.mode == .starred else { return nodes }

		// 智能 Feed 组:只留「已加星标」
		if sectionID.isEmpty {
			return nodes.filter { $0.node.representedObject === SmartFeedsController.shared.starredFeed }
		}

		// 账户组:只留有星标的
		return nodes.filter { node in
			guard let sidebarItem = node.node.representedObject as? SidebarItem else { return true }
			return NNWReadingModeStore.shared.shouldShowInFeedList(sidebarItem)
		}
	}
}

#endif
