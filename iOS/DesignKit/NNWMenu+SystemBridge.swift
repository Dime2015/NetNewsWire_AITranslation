//
//  NNWMenu+SystemBridge.swift
//  NetNewsWire — AI 翻译 fork
//
//  [外观] 本 fork 新增。把**系统的 UIMenu 树**原封不动地转成我们自绘的选单卡片。
//
//  ## 为什么要有这个文件(整件事的地基)
//
//  用户要求长按菜单也长成参考图 IMG_2442 那套质感。但:
//  **系统长按菜单(`UIContextMenuInteraction`)是由系统进程渲染的,
//  没有任何公开接口能改它的底色、圆角、行排布。** 只能整个换成自绘。
//
//  换的时候有两条路:
//
//  | 路 | 代价 |
//  |---|---|
//  | ❌ 照抄一遍菜单内容 | 上游每个菜单有 5–10 个 action,分散在 4 个文件里;
//  |   | 抄一份 = 几百行重复逻辑,**而且会和上游漂移**(上游加一项我们不知道) |
//  | ✅ **把上游构造好的 `UIMenu` 转过来** | 上游内容一行不用抄,加项自动跟上 |
//
//  走第二条路要解决一个问题:**`UIAction` 的 handler 是私有的,拿不到,也没有公开的
//  "执行这个 action"的方法。** 解法在 `perform(_:)` 里 —— 用的是公开 API。
//
//  ## 接入方式:上游只改一行
//
//  上游每个菜单的 `actionProvider` 闭包结尾都是
//  `return UIMenu(title: "", children: menuElements)`。
//  把那一行换成 `return self.nnwSoftMenu(UIMenu(...), anchor: ...)`:
//  它把菜单转成我们的卡片弹出来,并**返回 nil**让系统菜单不显示。
//  —— 正好落在 CLAUDE.md 允许的「一行换一行」通道里,
//  而且**够不到上游那些 private 的 action 构造函数也没关系**,我们要的是它们的产物。
//
//  ## 已知代价(用户 2026-08-04 知情并拍板接受)
//
//  换掉系统菜单就会失去系统的:长按预览抬起动画、触感反馈、
//  菜单自带的无障碍朗读节奏、以及和拖放手势的联动。
//  功能项一个不少,丢的是这些"系统自带的包装"。
//

#if os(iOS)

import UIKit

extension NNWMenu {

	/// 总开关:false = 长按恢复系统菜单(出问题时一处回滚)。
	static let replacesSystemContextMenus = true

	// MARK: - UIMenu → 我们的选单

	/// 把一棵 `UIMenu` 树摊平成我们的分组。
	///
	/// 规则:
	/// - `options` 含 `.displayInline` 的子菜单 = **一个分组**(系统菜单里那些
	///   用细线隔开的小组,本来就是这么表达的)
	/// - 直接挂在下面的 `UIAction` = 归入当前这个散装分组
	/// - **非** inline 的子菜单(真·二级菜单)= v1 也摊平成一个分组
	///   （我们的卡片不做二级页;摊平至少不丢功能）
	@MainActor
	static func sections(from menu: UIMenu) -> [[Item]] {

		var groups: [[Item]] = []
		var loose: [Item] = []

		func flush() {
			if !loose.isEmpty { groups.append(loose); loose = [] }
		}

		for element in menu.children {
			switch element {
			case let action as UIAction:
				loose.append(Item(action))
			case let submenu as UIMenu:
				flush()
				let nested = sections(from: submenu).flatMap { $0 }
				if !nested.isEmpty { groups.append(nested) }
			default:
				// UICommand / UIDeferredMenuElement 等:拿不到可执行的内容,跳过
				continue
			}
		}
		flush()
		return groups
	}

	/// **执行一个 `UIAction`** —— 整个桥接方案能成立的关键。
	///
	/// `UIAction.handler` 是私有的,`UIAction` 也没有公开的 `perform()`。
	/// 但 `UIControl.addAction(_:for:)` 接受 `UIAction`(这正是
	/// `UIButton(primaryAction:)` 的底层做法),而 `sendActions(for:)` 会把它触发。
	/// 两个都是公开 API,于是:**造一个不入界面的按钮,把 action 挂上去,再自己触发它。**
	///
	/// ⚠️ `sendActions` 是同步的,所以这个临时按钮活到调用结束就够了;
	/// handler 捕获的是原来那个页面(self),不是这个按钮。
	@MainActor
	static func perform(_ action: UIAction) {
		let relay = UIButton(type: .custom)
		relay.addAction(action, for: .primaryActionTriggered)
		relay.sendActions(for: .primaryActionTriggered)
	}
}

private extension NNWMenu.Item {

	/// 从系统 `UIAction` 转成我们的一行。
	@MainActor
	init(_ action: UIAction) {
		self.init(title: action.title,
				  image: action.image,
				  isDestructive: action.attributes.contains(.destructive),
				  isEnabled: !action.attributes.contains(.disabled),
				  handler: { NNWMenu.perform(action) })
	}
}

// MARK: - 给上游调用点用的一行式入口

extension UIViewController {

	/// [外观] 把系统菜单换成我们自绘的卡片。
	///
	/// **用法(上游一行换一行)**:
	/// ```swift
	/// // 原来:
	/// return UIMenu(title: "", children: menuElements)
	/// // 改成:
	/// return self.nnwSoftMenu(UIMenu(title: "", children: menuElements), anchor: .center)
	/// ```
	///
	/// 返回值恒为 `nil` —— 让系统菜单不要显示。
	///
	/// - Parameter quickActionCount: **开头的几项**提到顶部图标行(参考图 IMG_2442 的结构)。
	///   0 = 不要那一排。
	///
	///   ⚠️ **这个数字由调用点自己定,没有通用默认值**。试过"自动从第一组提" ——
	///   实测不行:订阅源菜单的第一组只有「显示简介」一项,提不出一排;
	///   时间线菜单的第一组有四项,里头「标记以上为已读 / 标记以下为已读」
	///   摘掉文字就**认不出来了**。图标行只装得下那种"一眼认得出"的动作,
	///   这件事机器判断不了,所以交给调用点点名。
	@MainActor
	@discardableResult
	func nnwSoftMenu(_ menu: UIMenu,
					 anchor: NNWMenu.Anchor,
					 title: String? = nil,
					 quickActionCount: Int = 0) -> UIMenu? {

		guard NNWMenu.replacesSystemContextMenus, NNWSoftMaterial.isEnabled else { return menu }

		var groups = NNWMenu.sections(from: menu)
		guard !groups.isEmpty else { return nil }

		// 顶部图标行:按菜单顺序从头取 N 项(系统菜单本来就是最常用的排最前)。
		// 只取带图标的;取完必须还剩得下东西,否则整张卡就成了"只有图标没有文字"的谜语。
		var quick: [NNWMenu.Item] = []
		if quickActionCount > 0 {
			let flat = groups.flatMap { $0 }
			let candidates = flat.prefix(quickActionCount)
			if candidates.count >= 2,
			   candidates.allSatisfy({ $0.resolvedImage != nil }),
			   flat.count > candidates.count {
				quick = Array(candidates)
				// 把取走的那几项从分组里剔掉(保持剩下部分的分组结构)
				var toDrop = quick.count
				groups = groups.compactMap { group in
					guard toDrop > 0 else { return group }
					let drop = min(toDrop, group.count)
					toDrop -= drop
					let rest = Array(group.dropFirst(drop))
					return rest.isEmpty ? nil : rest
				}
			}
		}

		// ⚠️ **异步弹**:这个方法是在系统长按手势的 `actionProvider` 里被调用的,
		// 此刻系统正在走它自己的菜单流程 —— 同步 present 等于在别人的事务中间插一脚。
		// 返回 nil 让系统那套先收干净,下一个 runloop 再弹我们的。
		DispatchQueue.main.async { [weak self] in
			guard let self else { return }
			NNWMenu.show(in: self, anchor: anchor, title: title,
						 quickActions: quick, sections: groups)
		}
		return nil
	}
}

#endif
