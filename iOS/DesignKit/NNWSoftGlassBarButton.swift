//
//  NNWSoftGlassBarButton.swift
//  NetNewsWire — AI 翻译 fork
//
//  [外观] 本 fork 新增(2026-08-09)。把**工具栏里已有的那几个按钮项**换上我们自己的
//  玻璃圆钮 —— 不换对象、不动 `toolbarItems` 的结构,只给它设一个 `customView`。
//
//  ## 为什么非改不可(用户 2026-08-09 报的那件事)
//
//  用户看文章列表页:「上下部分的各个控件,玻璃的透明度、层次、质感……都不太一致
//  (特别是在深色模式下)」。查下来这一屏上混着**三套底**:
//
//  | 控件 | 底 |
//  |---|---|
//  | 顶部胶囊 / 底部三档轨道 | 真玻璃(`UIGlassEffect`),内容能透过来 |
//  | 底部左右两颗圆钮 | **不透明,而且是画进一张图片里的** |
//  | 选中那颗胶囊 | **不透明实心色** |
//
//  浅色下三者亮度接近(实心档 232、纸底 234),混得过去;
//  **一到深色就当场分家** —— 玻璃档只补 3–6% 的白、亮度跟着背后的文章浮动,
//  而实心档是恒定的 #272727。用户说的"深色下尤其明显",数字上就是这么来的。
//
//  ## 为什么原来只能画成图片,现在为什么可以不画了
//
//  原来的理由写在 `NNWSoftMaterial.roundButtonImage`:工具栏那两颗**只能换 image** ——
//  加号是 storyboard 的 IBOutlet,上游还往它身上挂 `menu` 和 `isEnabled`,
//  换成 customView 会把那些写入点全打断。
//
//  那个理由**只对"换掉整个 UIBarButtonItem 对象"成立**。
//  本文件走的是另一条路:**对象一个都不换**,只给它设 `customView`,
//  然后把它身上的 `target`/`action`/`menu`/`isEnabled` **转发**到那个视图上。
//  于是:
//
//  - `toolbarItems` 数组一个字节没动 → `expectedItemCount == 3` 那条守卫照旧满足
//    (CLAUDE.md 点名过的坑)
//  - `addNewItemButton` 这个 IBOutlet 还是原来那个对象 → 上游的写入点全部照旧生效
//  - 图片装不下磨砂,而 customView 装得下 → 四颗圆钮终于和顶部胶囊、三档轨道**同一块玻璃**
//
//  ## ⚠️ 唯一的代价:`isEnabled` 和 `menu` 要有人搬运
//
//  UIKit 在一项有 `customView` 时**不会**把 `isEnabled` 传下去(众所周知的老行为),
//  `menu` 同理。所以上游每次写完状态,得叫一次 `nnwSyncSoftGlassToolbarButtons()`。
//  挂点选的是**上游自己那个"写状态"的方法的最后一行**:
//
//  | 页面 | 挂在哪 | 上游在那里写了什么 |
//  |---|---|---|
//  | 首页 | `MainFeedCollectionViewController.updateUI()` | 加号的 `isEnabled` + `configureContextMenu()` 里的 `menu` |
//  | 文章列表页 | `MainTimelineModernViewController.updateToolbar()` | 两颗的 `isEnabled` |
//
//  这是「加一行调用」通道,各一行,带 `[外观]` 标记。
//  ⚠️ 同步函数**幂等**(反复调只是把同样的值再写一遍),所以挂在会被反复调用的方法里是安全的 ——
//  这一条是 L113 的老规矩:给已有函数挂东西之前,先确认它幂等。
//

#if os(iOS)

import UIKit
import os.log

extension UIBarButtonItem {

	/// 把这一项的外观换成玻璃圆钮。**幂等**:装过之后再调只会更新图标并同步一次状态。
	///
	/// - Parameter icon: 图标(手绘的 `NNWDockIcons` 那一套,或按
	///   `NNWSoftMaterial.iconPointSize` 配好的 SF Symbol)
	/// - Returns: 那颗按钮;这一项没有 `action` 时返回 nil(没有动作的项不该被换掉)
	@discardableResult
	func nnwUseSoftGlassButton(icon: UIImage) -> NNWSoftGlassButton? {

		guard NNWSoftMaterial.isEnabled else { return nil }

		// 已经装过 → 只把图标换成新的(换强调色时颜色变了要重画),再同步一次状态
		if let existing = customView as? NNWSoftGlassButton {
			existing.nnwSetIcon(icon)
			nnwSyncSoftGlassButton()
			return existing
		}

		guard let action else { return nil }

		let button = NNWSoftGlassButton(icon: icon)
		// ⚠️ `target` 为 nil 时这样加是**对的**,不是漏了:
		// `addTarget(nil, action:for:)` 的语义就是"沿响应链找谁能处理",
		// 和 storyboard 里连到 First Responder 的按钮完全一致。
		// (`markAllAsRead` 正是 storyboard 里的项,它的 target 可能就是 nil。)
		button.addTarget(target, action: action, for: .touchUpInside)
		button.accessibilityLabel = accessibilityLabel ?? title
		customView = button

		// customView 的项同样要拆掉 iOS 26/27 自动垫的那层系统玻璃胶囊,
		// 否则又是"系统胶囊里套我们的圆钮"两层(三档控件一直是这么做的)。
		nnwHideSystemGlassCapsule()
		nnwSyncSoftGlassButton()
		return button
	}

	/// 把这一项身上的 `isEnabled` / `menu` 搬到它的玻璃圆钮上。没装过的项直接跳过。
	func nnwSyncSoftGlassButton() {
		guard let button = customView as? NNWSoftGlassButton else { return }
		button.isEnabled = isEnabled
		// ⚠️ 只在真有菜单时才接管首要动作 —— 否则会把普通点击(比如加号的 `add(_:)`)
		// 变成"点一下弹个空菜单"。上游是**先装按钮、后设菜单**的
		// (`configureContextMenu()` 在 `updateUI()` 里),所以这里每次都要重读一遍。
		if let menu {
			button.menu = menu
			button.showsMenuAsPrimaryAction = true
		}
	}
}

extension UIViewController {

	/// 把本页工具栏里所有玻璃圆钮的状态同步一遍。**幂等**,可以放心挂在会被反复调用的方法后面。
	func nnwSyncSoftGlassToolbarButtons() {
		for item in toolbarItems ?? [] {
			item.nnwSyncSoftGlassButton()
		}
		nnwLogGlassAlignment()
	}

	// MARK: - ⚠️ 临时探针(2026-08-09,量完就删)

	/// 把底部这一排控件的**窗口坐标外接框**打进日志。
	///
	/// ## 为什么非量不可
	///
	/// 这一改把左右两颗从「一张图片」换成了「自绘视图」,而 **UIToolbar 摆这两种东西
	/// 用的不是同一套规矩**。T50 那一轮量到过:图片型 bar item 的圆盘下缘是 **841.67**,
	/// 比窗口安全区上沿(840)还低 1.67pt —— 工具栏允许图片圆盘**略微探入 Home 条**。
	/// 首页那条浮起来的三档正是按这个差校准的(`NNWFloatingModeBarHost.nnwBarItemOvershoot = 2`)。
	///
	/// **如果换成自绘视图之后工具栏改为按栏中心摆,那两颗会上移约 2pt,
	/// 而首页那条三档还停在为旧摆法补的位置上 → 变成它偏低。**
	/// 这是**换实现顺带把别处的校准前提作废**的典型(L122),不量就等着用户来报。
	///
	/// 📌 顺带白拿的好处:四颗都变成自绘视图之后,**直接读 frame 就行了** ——
	/// 不必再像 T50 那样靠截图扫亮边反推(那才是 L123「量的不是它」的温床)。
	///
	/// 看日志:
	/// ```
	/// xcrun simctl spawn <UDID> log show --last 2m --info \
	///   --predicate 'category == "NNWGlassAlign"' --style compact
	/// ```
	/// ⚠️ **必须带 `--info`**,否则 `Logger.info` 根本不落盘。
	func nnwLogGlassAlignment() {

		guard let window = view.window else { return }

		// 排到这一帧末尾再读 —— 现在读到的多半还是上一轮的旧 frame
		DispatchQueue.main.async { [weak self] in
			guard let self, let window = self.view.window else { return }
			var lines: [String] = []
			for item in self.toolbarItems ?? [] {
				guard let custom = item.customView, custom.bounds.height > 0 else { continue }
				let frame = custom.convert(custom.bounds, to: window)
				let kind = (custom as? NNWSoftGlassButton) != nil ? "圆钮" : "\(type(of: custom))"
				lines.append(String(format: "%@ 上%.2f 下%.2f 高%.2f 中心%.2f 宽%.2f",
									kind, frame.minY, frame.maxY, frame.height, frame.midY, frame.width))
			}
			guard !lines.isEmpty else { return }
			let safeBottom = window.safeAreaInsets.bottom
			let page = String(describing: type(of: self))
			NNWGlassAlignLog.logger.info(
				"[对齐] \(page, privacy: .public) 安全区底=\(safeBottom, privacy: .public) | \(lines.joined(separator: " || "), privacy: .public)")
		}
		_ = window
	}
}

/// ⚠️ 临时探针的日志频道,量完连同 `nnwLogGlassAlignment` 一起删。
enum NNWGlassAlignLog {
	static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "NNWGlassAlign")
}

#endif
