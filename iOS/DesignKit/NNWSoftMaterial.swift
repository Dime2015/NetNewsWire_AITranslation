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

	// MARK: - 采样得到的色号

	/// 面板(dock 本体)。实测 #E5E5E5 → #E7E7E7,由上向下变亮。
	static var panelTop: UIColor { dynamic(light: 0xE5E5E5, dark: 0x1E2021) }
	static var panelBottom: UIColor { dynamic(light: 0xE7E7E7, dark: 0x212324) }

	/// 选中胶囊。实测 #E9E9E9 → #EDEDED,比面板亮 4 级。
	static var capsuleTop: UIColor { dynamic(light: 0xE9E9E9, dark: 0x26292A) }
	static var capsuleBottom: UIColor { dynamic(light: 0xEDEDED, dark: 0x2A2D2E) }

	/// 图标/文字。实测参考图的文字是 #262626,**不是纯黑**。
	static var ink: UIColor { dynamic(light: 0x262626, dark: 0xF0F1F1) }
	static var inkMuted: UIColor { dynamic(light: 0x8A8F91, dark: 0x8E9395) }

	/// 强调橙。实测精确命中 #FF5A1F。
	static var accent: UIColor { dynamic(light: 0xFF5A1F, dark: 0xFF6A2F) }

	// MARK: - 形状与光影(单位:pt)

	/// 上缘高光的线宽。实测 3.5px @ 6.4px/pt ≈ 0.55pt —— 是一条 hairline,
	/// 不是"描边"。⚠️ 别加粗,一加粗立刻变塑料。
	static let rimWidth: CGFloat = 0.55

	/// 阴影:极淡、极宽。实测贴边仅比背景暗 7 级,扩散约 5pt。
	static let shadowRadius: CGFloat = 5
	static let shadowOffsetY: CGFloat = 2
	static var shadowOpacity: Float { NNWSoftMaterial.isDarkNow ? 0.55 : 0.16 }

	private static var isDarkNow: Bool {
		UITraitCollection.current.userInterfaceStyle == .dark
	}

	private static func dynamic(light: UInt32, dark: UInt32) -> UIColor {
		UIColor { $0.userInterfaceStyle == .dark ? rgb(dark) : rgb(light) }
	}

	private static func rgb(_ v: UInt32) -> UIColor {
		UIColor(red: CGFloat((v >> 16) & 0xFF) / 255,
				green: CGFloat((v >> 8) & 0xFF) / 255,
				blue: CGFloat(v & 0xFF) / 255,
				alpha: 1)
	}
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
		let top = kind == .panel ? NNWSoftMaterial.panelTop : NNWSoftMaterial.capsuleTop
		let bottom = kind == .panel ? NNWSoftMaterial.panelBottom : NNWSoftMaterial.capsuleBottom
		fill.frame = bounds
		fill.cornerRadius = cornerRadius
		fill.cornerCurve = .continuous
		fill.colors = [top.resolvedColor(with: traits).cgColor,
					   bottom.resolvedColor(with: traits).cgColor]

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
