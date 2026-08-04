//
//  NNWSoftMaterial.swift
//  NetNewsWire — AI 翻译 fork
//
//  [外观] 本 fork 新增。2026-08-04 设计试验:参考图那套「软面板」材质。
//
//  ## 数值不是估的,是从参考图逐像素采样来的
//
//  用一个自写的取色工具扫了用户提供的三张参考图
//  (`external resources/references/`),得到这些硬事实 ——
//  之前凭目测画的几版都不像,病根就在下面这四条全都猜反了:
//
//  | | 目测版(错) | 采样实测 |
//  |---|---|---|
//  | 白边粗细 | 1.5pt,整圈均匀 | **0.55pt hairline**,只在上缘最亮、往下迅速衰减 |
//  | 层间色差 | 相差 10–15 级灰 | **只差 2–5 级**(面板 #E5 vs 画布 #EA) |
//  | 渐变方向 | 上亮下暗 | **由上向下变亮**(#E5→#E7) |
//  | 阴影 | 短而重 | **极淡极宽**(贴边只暗 7 级,扩散约 5pt) |
//
//  **最反直觉的一条**:面板和背景几乎同色,层次全靠那道 hairline 撑起来。
//  色差一拉大就立刻变回"贴上去的塑料板" —— 越想做出层次越要克制色差。
//
//  ## 一处开关
//
//  `isEnabled` 设成 false 就整体退回原样(不画面板、不画高光、不画阴影),
//  方便和旧版对比、也方便快速回滚。整轮改动都在 `design/soft-dock` 分支上。
//

#if os(iOS)

import UIKit
import ObjectiveC	// 工具栏外观的存/还原用关联对象

enum NNWSoftMaterial {

	/// 总开关。false = 完全不生效,控件回到改动前的样子。
	static let isEnabled = true

	// MARK: - 颜色:**相对于 app 自身的底色**推导,不用参考图的绝对色号
	//
	// ⚠️ 2026-08-04 第一版就栽在这里:直接把参考图的冷灰 #E5/#E7 搬进来,
	// 而本 app 的底是暖纸色 —— 米色纸上糊了一块脏灰(用户原话"改的非常差")。
	//
	// 参考图真正的规律是**相对关系**,不是那几个 hex:
	//   画布 #EA(234) → 面板 #E5–#E7(-5 ~ -3) → 胶囊 #E9–#ED(-1 ~ +3)
	// 所以这里按同样的差值,从 `AppAppearance.paperBackground` 现推 —— 底色是暖是冷都跟得上。

	/// 面板(dock 本体):比底色**暗** 3–5 级,由上向下变亮
	static func panelColors(for traits: UITraitCollection) -> (top: UIColor, bottom: UIColor) {
		let isDark = traits.userInterfaceStyle == .dark
		// 深色模式下"更暗"无从谈起(底已经很暗),改为比底色亮一档
		// 实测参考图是 -5/-3;但那是在中性灰底上。本 app 是暖纸底(明度更高),
		// 同样的差值几乎看不见 —— 按屏幕上量到的结果加深到 -9/-6。
		return isDark ? (shift(paper(traits), by: 9), shift(paper(traits), by: 13))
					  : (shift(paper(traits), by: -9), shift(paper(traits), by: -6))
	}

	/// 选中胶囊:比面板亮 4 级左右,做出"嵌在槽里的一块"
	static func capsuleColors(for traits: UITraitCollection) -> (top: UIColor, bottom: UIColor) {
		let isDark = traits.userInterfaceStyle == .dark
		return isDark ? (shift(paper(traits), by: 20), shift(paper(traits), by: 26))
					  : (shift(paper(traits), by: 2), shift(paper(traits), by: 6))
	}

	private static func paper(_ traits: UITraitCollection) -> UIColor {
		AppAppearance.paperBackground.resolvedColor(with: traits)
	}

	/// 在 RGB 上整体加减若干级(0–255)。近中性色上等同于只动明度,色相不会跑。
	private static func shift(_ color: UIColor, by delta: CGFloat) -> UIColor {
		var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
		guard color.getRed(&r, green: &g, blue: &b, alpha: &a) else { return color }
		let d = delta / 255
		return UIColor(red: min(max(r + d, 0), 1),
					   green: min(max(g + d, 0), 1),
					   blue: min(max(b + d, 0), 1), alpha: a)
	}

	/// 图标/文字墨色。跟随 app 既有的墨色,别再引第三套。
	static var ink: UIColor { AppAppearance.inkPrimary }

	/// 强调橙。实测参考图精确命中 #FF5A1F。
	static var accent: UIColor {
		UIColor { $0.userInterfaceStyle == .dark
			? UIColor(red: 1, green: 0x6A/255, blue: 0x2F/255, alpha: 1)
			: UIColor(red: 1, green: 0x5A/255, blue: 0x1F/255, alpha: 1) }
	}

	// MARK: - 形状与光影(单位:pt)

	/// 上缘高光的线宽。实测 3.5px @ 6.4px/pt ≈ 0.55pt —— 是一条 hairline,
	/// 不是"描边"。⚠️ 别加粗,一加粗立刻变塑料。
	static let rimWidth: CGFloat = 0.55

	/// 阴影:极淡、极宽。实测贴边仅比背景暗 7 级,扩散约 5pt。
	static let shadowRadius: CGFloat = 5
	static let shadowOffsetY: CGFloat = 2

}

// MARK: - 把材质套到一个视图上

/// 一份「软面板」装饰:渐变填充 + 上缘 hairline + 极淡阴影。
///
/// 用法:宿主视图持有一个实例,`install(in:)` 一次,
/// 然后在自己的 `layoutSubviews` 里调 `layout(in:cornerRadius:)`。
///
/// ⚠️ 宿主**不能** `clipsToBounds = true` —— 会把阴影裁掉。
@MainActor final class NNWSoftPanel {

	enum Kind {
		/// dock 本体
		case panel
		/// 选中的那一格(比面板亮一档)
		case capsule
	}

	private let kind: Kind
	private let fill = CAGradientLayer()
	private let rim = CAGradientLayer()
	private let rimMask = CAShapeLayer()

	init(kind: Kind) {
		self.kind = kind
	}

	func install(in view: UIView) {

		guard NNWSoftMaterial.isEnabled else { return }

		view.backgroundColor = .clear

		// ⚠️ **必须开 masksToBounds**:CAGradientLayer 的 cornerRadius 不开这个不裁切,
		// 渐变会画成一块**矩形**压在圆角胶囊上(2026-08-04 第一版那"一坨多余的框"就是它)。
		fill.masksToBounds = true
		fill.needsDisplayOnBoundsChange = true
		view.layer.insertSublayer(fill, at: 0)

		// 上缘高光:用一层「白→透明」的竖向渐变,再用描边形状把它裁成一圈线。
		// 直接用 CAShapeLayer 的 strokeColor 做不到"沿高度衰减"。
		rimMask.fillColor = UIColor.clear.cgColor
		rimMask.strokeColor = UIColor.black.cgColor
		rimMask.lineWidth = NNWSoftMaterial.rimWidth
		rim.mask = rimMask
		view.layer.insertSublayer(rim, above: fill)

		view.layer.shadowRadius = NNWSoftMaterial.shadowRadius
		view.layer.shadowOffset = CGSize(width: 0, height: NNWSoftMaterial.shadowOffsetY)
	}

	/// 尺寸/深浅色变化后重画。**在宿主的 layoutSubviews 里调**。
	func layout(in view: UIView, cornerRadius: CGFloat) {

		guard NNWSoftMaterial.isEnabled else { return }

		let bounds = view.bounds
		let traits = view.traitCollection

		// —— 填充:由上向下变亮 ——
		let colors = kind == .panel ? NNWSoftMaterial.panelColors(for: traits)
									: NNWSoftMaterial.capsuleColors(for: traits)
		let top = colors.top, bottom = colors.bottom
		fill.frame = bounds
		fill.cornerRadius = cornerRadius
		fill.cornerCurve = .continuous
		fill.colors = [top.cgColor, bottom.cgColor]

		// —— 上缘 hairline:最亮在顶,往下迅速衰减 ——
		let isDark = traits.userInterfaceStyle == .dark
		let peak: CGFloat = isDark ? 0.12 : 1.0
		rim.frame = bounds
		rim.colors = [UIColor.white.withAlphaComponent(peak).cgColor,
					  UIColor.white.withAlphaComponent(peak * 0.5).cgColor,
					  UIColor.white.withAlphaComponent(peak * 0.1).cgColor,
					  UIColor.white.withAlphaComponent(peak * 0.03).cgColor]
		rim.locations = [0, 0.22, 0.6, 1]

		let inset = NNWSoftMaterial.rimWidth / 2
		rimMask.frame = bounds
		rimMask.path = UIBezierPath(roundedRect: bounds.insetBy(dx: inset, dy: inset),
									cornerRadius: cornerRadius).cgPath
		rimMask.lineWidth = NNWSoftMaterial.rimWidth

		// —— 阴影 ——
		view.layer.shadowColor = UIColor.black.cgColor
		view.layer.shadowOpacity = isDark ? 0.55 : 0.16
		view.layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: cornerRadius).cgPath
	}
}

// MARK: - 让 dock 浮起来:把系统工具栏的底抹掉

extension UIViewController {

	private static var nnwSavedToolbarAppearanceKey: UInt8 = 0

	/// [外观] 进/出文章页时切换工具栏的底。
	///
	/// 参考图里的 dock 是**浮在页面上**的一颗胶囊,不是"装在一条栏里"。
	/// 系统工具栏自己会画一层底(iOS 26 上是玻璃),不抹掉的话就成了"胶囊套在栏里"的双层。
	///
	/// ⚠️ **原样存起来再改**:工具栏是整个导航栈共用的一条,
	/// 离开本页必须还原,否则别的页面(列表页的三档、首页的设置/+)会跟着一起变透明。
	func nnwUseFloatingToolbar(_ floating: Bool) {

		guard NNWSoftMaterial.isEnabled, let toolbar = navigationController?.toolbar else { return }

		if floating {
			// 第一次改之前,把原来的三份外观存下来
			if objc_getAssociatedObject(self, &Self.nnwSavedToolbarAppearanceKey) == nil {
				let saved: [UIToolbarAppearance?] = [toolbar.standardAppearance,
													 toolbar.compactAppearance,
													 toolbar.scrollEdgeAppearance]
				objc_setAssociatedObject(self, &Self.nnwSavedToolbarAppearanceKey, saved, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
			}
			let transparent = UIToolbarAppearance()
			transparent.configureWithTransparentBackground()
			toolbar.standardAppearance = transparent
			toolbar.compactAppearance = transparent
			toolbar.scrollEdgeAppearance = transparent
		} else {
			guard let saved = objc_getAssociatedObject(self, &Self.nnwSavedToolbarAppearanceKey) as? [UIToolbarAppearance?] else {
				return
			}
			toolbar.standardAppearance = saved[0] ?? UIToolbarAppearance()
			toolbar.compactAppearance = saved[1]
			toolbar.scrollEdgeAppearance = saved[2]
			objc_setAssociatedObject(self, &Self.nnwSavedToolbarAppearanceKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
		}
	}
}

#endif
