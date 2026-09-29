import UIKit

/// 全 App 统一图标集（2026-09-27 用户：设置页 / 长按菜单 / 底栏的图标设计、粗细、视觉重心、风格不统一，ADR-065）。
///
/// 47 个图标出自同一套构造规则。2026-09-27 第八轮起是参考 Reeder 画的「Reeder 式」（ADR-066：实心 / 空心成对表示状态、
/// 圆弧箭头用实心三角头；设计源与规则在 Design/Babel2/IconSet/icons_reeder.py，第七轮「瑞士几何」的 icons.py 留作记录），
/// 用 `python3 make.py --export` 导出到 Assets.xcassets/Babel2Icons，每个都是 24×24 的矢量模板图。
/// 用户在手机上比较后定了线宽 2.0、图标颜色「深一档」（`Babel2Icon.tint`）。
///
/// 用法：`Babel2Icon.edit.image(size: Babel2Icon.Size.menu)`——按给定的边长（pt，含设计网格四周的留白）重画成模板图，随 tintColor 变色。
/// 各处的边长：底栏 21、菜单 20、设置 20、首页入口 18、顶栏 22（菜单与入口比审阅页各大 2pt——放进真实界面、挨着文字时原尺寸显小）。
enum Babel2Icon: String, CaseIterable {
	// 导航与通用
	case back, forward, chevronDown = "chevron-down", close, more, check, search, add, settings, share, refresh, sync
	case arrowUp = "arrow-up", openLink = "open-link", browser
	// 阅读与文章状态
	case readOff = "read-off", readOn = "read-on", star, starOn = "star-on", starOff = "star-off"
	case readerMode = "reader-mode", translate, longImage = "long-image", readAll = "read-all", unreadDot = "unread-dot", list
	// 首页入口
	case today, inbox, globe
	// 整理与管理
	case folder, folderAdd = "folder-add", edit, trash, image, undo, copy, bell, shield
	// 设置分类
	case account, feed, appearance, help
	// 添加订阅
	case podcast, video, chat, subscribe, subscribed

	/// 资源名（Assets.xcassets/Babel2Icons 里的 imageset）。
	var assetName: String { "Babel2Icon-" + rawValue }

	/// 设计网格边长与线宽（与 icons.py 的 STROKE 一致）。
	static let designGrid: CGFloat = 24
	static let stroke: CGFloat = 2

	/// 图标颜色「深一档」（用户选定）：浅色 #5E5E5E、深色 #A8A8A8。
	/// 以前图标和次要文字共用 BabelPalette.mutedInk（#787878 / #8E8E8E）——图标变简洁、笔画变少后显得发淡，
	/// 只把图标调深一档，文字不变。
	static let tint = UIColor { traits in
		traits.userInterfaceStyle == .dark
			? UIColor(red: 168.0 / 255.0, green: 168.0 / 255.0, blue: 168.0 / 255.0, alpha: 1)
			: UIColor(red: 94.0 / 255.0, green: 94.0 / 255.0, blue: 94.0 / 255.0, alpha: 1)
	}

	/// 常用边长（pt）。
	enum Size {
		static let bar: CGFloat = Babel2Type.toolbarIcon      // 底栏 21
		static let menu: CGFloat = 20
		static let settings: CGFloat = 20
		static let entry: CGFloat = 18
		static let top: CGFloat = 22
		/// 首页顶栏的设置（开关）与添加：28（2026-09-27 用户真机：「顶部这两个控件太小了，看着好小气」）。
		/// 22 时开关实宽约 15.5pt、加号约 12pt；28 时约 20pt / 15pt，与 Reeder 首页顶栏相当。只用于首页这两颗。
		static let homeTop: CGFloat = 28
	}

	@MainActor private static var cache = [String: UIImage]()

	/// 原始矢量资源（24pt）。
	var asset: UIImage? { UIImage(named: assetName) }

	/// 按边长 size 重画的模板图（矢量重画，不糊）。同一个图标同一边长只画一次。
	@MainActor func image(size: CGFloat) -> UIImage? {
		let key = "\(rawValue)@\(size)"
		if let cached = Self.cache[key] { return cached }
		guard let asset else { return nil }
		let canvas = CGSize(width: size, height: size)
		let drawn = UIGraphicsImageRenderer(size: canvas, format: .preferred()).image { _ in
			asset.draw(in: CGRect(origin: .zero, size: canvas))
		}.withRenderingMode(.alwaysTemplate)
		Self.cache[key] = drawn
		return drawn
	}
}
