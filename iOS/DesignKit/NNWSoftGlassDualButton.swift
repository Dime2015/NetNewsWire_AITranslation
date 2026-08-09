//
//  NNWSoftGlassDualButton.swift
//  NetNewsWire — AI 翻译 fork
//
//  [外观] 本 fork 新增。**一颗胶囊里放两个图标**,左右各自可点。
//  用户 2026-08-08 第 10 件:文章列表页右上角的齿轮压住了长源名的标题,
//  他要求「把设置和搜索放进同一个控件里」。
//
//  ## ⚠️ 为什么是自己画,而不是让系统把两颗合并
//
//  系统确实会把相邻的 bar item 合并成一颗胶囊 —— 但那是**系统材质**,
//  它在 iOS 26 和 27 上是两副样子(26 靠 `hidesSharedBackground` 拆、
//  27 会把相邻项自动归进隐式组从而忽略那句,详见 `nnwHideSystemGlassCapsule` 与 T50)。
//  2026-08-05 整整绕了一轮才把两个系统上的观感统一,**不能再退回去交给系统**。
//  判据是 L121:**要么全归系统,要么全归我们,半分最贵。**
//  这颗胶囊的材质和圆钮(`NNWSoftGlassButton`)、dock、三档控件同源,天然一致。
//
//  ## 左右半区怎么分
//
//  **不做手工的命中测试**(那是 L120 那一族最容易出事的地方)——
//  两个半区各是一个真的 `UIControl` 子视图,并排铺满胶囊。
//  于是「谁被点到」由 UIKit 自己按 frame 判定,顺带白拿两件事:
//  各自的按下高亮、各自是一个独立的无障碍元素(VoiceOver 能分别念出来)。
//
//  ## 尺寸
//
//  高 = `NNWSoftMaterial.controlDiameter`(和全 app 的圆钮同高,并排不打架);
//  宽 = 高 × 1.7 —— 比两颗独立圆钮(2×44 + 间距 ≈ 96pt)省下 ≈ 28pt,
//  这就是还给标题的净空。上下各留出 hit 余量,总高仍是 44pt 的点按标准。
//

#if os(iOS)

import UIKit

@MainActor final class NNWSoftGlassDualButton: UIView {

	/// 可见胶囊的高 —— 读全 app 的唯一真源,别在这里写死。
	static var capsuleHeight: CGFloat { NNWSoftMaterial.controlDiameter }
	/// 可见胶囊的宽。1.7 倍是"两个图标各自够宽、又明显比两颗圆钮省地方"的折中。
	static var capsuleWidth: CGFloat { (capsuleHeight * 1.7).rounded() }
	/// 控件本体的高(苹果最小点按标准),胶囊在中间。
	/// 🔴 2026-08-09:同 `NNWSoftGlassButton.hitSize`,从 `+4` 改成不外扩 ——
	/// 导航栏给 bar item 的高度上限就是 44,要 48 会被系统打断一条约束(真机日志里刷屏)。
	static var hitHeight: CGFloat { max(44, capsuleHeight) }

	private let blur: UIVisualEffectView = {
		if #available(iOS 26, *) {
			return UIVisualEffectView(effect: UIGlassEffect(style: .regular))
		}
		return UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
	}()
	private let material = UIView()
	private let softPanel = NNWSoftPanel(kind: .panel, translucent: true)
	/// 中间那条极淡的分隔线 —— 告诉用户"这是两个键",但不要抢眼。
	private let divider = UIView()

	private let leftHalf: Half
	private let rightHalf: Half

	/// - Parameters:
	///   - leftIcon / rightIcon: 24×24 的模板图(`NNWDockIcons` 那一套)
	init(leftIcon: UIImage, leftLabel: String, rightIcon: UIImage, rightLabel: String) {

		leftHalf = Half(icon: leftIcon, label: leftLabel)
		rightHalf = Half(icon: rightIcon, label: rightLabel)

		super.init(frame: .zero)

		blur.isUserInteractionEnabled = false
		blur.layer.masksToBounds = true
		blur.layer.cornerCurve = .continuous
		addSubview(blur)

		material.isUserInteractionEnabled = false
		addSubview(material)
		softPanel.install(in: material)

		divider.isUserInteractionEnabled = false
		divider.backgroundColor = UIColor.label.withAlphaComponent(0.12)
		addSubview(divider)

		addSubview(leftHalf)
		addSubview(rightHalf)

		// ⚠️ 必须显式钉死尺寸,光有 intrinsicContentSize 不够 ——
		// 导航栏不给它算宽高时 bounds 是零,子视图照画但命中测试全落空
		// (`NNWSoftGlassButton` 里逐字记过这个坑,别重蹈)。
		NSLayoutConstraint.activate([
			widthAnchor.constraint(equalToConstant: Self.capsuleWidth),
			heightAnchor.constraint(equalToConstant: Self.hitHeight)
		])
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { fatalError("不从故事板加载") }

	override var intrinsicContentSize: CGSize {
		CGSize(width: Self.capsuleWidth, height: Self.hitHeight)
	}

	func addLeftTarget(_ target: Any?, action: Selector) {
		leftHalf.addTarget(target, action: action, for: .touchUpInside)
	}

	func addRightTarget(_ target: Any?, action: Selector) {
		rightHalf.addTarget(target, action: action, for: .touchUpInside)
	}

	override func layoutSubviews() {
		super.layoutSubviews()

		let capsule = CGRect(x: 0,
							 y: (bounds.height - Self.capsuleHeight) / 2,
							 width: bounds.width,
							 height: Self.capsuleHeight)
		let radius = Self.capsuleHeight / 2

		blur.frame = capsule
		blur.layer.cornerRadius = radius
		material.frame = capsule
		softPanel.layout(in: material, cornerRadius: radius)

		// 分隔线只占中间六成高 —— 顶到边会让胶囊看起来像被切成两块
		let dividerHeight = (Self.capsuleHeight * 0.6).rounded()
		divider.frame = CGRect(x: (bounds.width / 2).rounded() - 0.5,
							   y: capsule.midY - dividerHeight / 2,
							   width: 1 / (window?.screen.scale ?? 3),
							   height: dividerHeight)

		// 两个半区铺满整个点按高度(上下那点余量也要能点)
		let halfWidth = bounds.width / 2
		leftHalf.frame = CGRect(x: 0, y: 0, width: halfWidth, height: bounds.height)
		rightHalf.frame = CGRect(x: halfWidth, y: 0, width: halfWidth, height: bounds.height)
	}

	// MARK: - 半区

	/// 胶囊的一半:一个透明的按钮,只画图标。底(磨砂 + 亮边)由外面那层统一提供。
	private final class Half: UIControl {

		private let iconView = UIImageView()

		init(icon: UIImage, label: String) {
			super.init(frame: .zero)
			iconView.image = icon.withRenderingMode(.alwaysTemplate)
			iconView.tintColor = NNWSoftMaterial.accent
			iconView.contentMode = .center
			iconView.isUserInteractionEnabled = false
			addSubview(iconView)

			isAccessibilityElement = true
			accessibilityTraits = .button
			accessibilityLabel = label
		}

		@available(*, unavailable)
		required init?(coder: NSCoder) { fatalError("不从故事板加载") }

		override func layoutSubviews() {
			super.layoutSubviews()
			iconView.frame = bounds
		}

		/// 按下去这一半变淡,和板上其他键的手感一致(只淡图标,底不动 ——
		/// 底是两半共用的,整块变淡会让人以为两个键一起按下去了)。
		override var isHighlighted: Bool {
			didSet { iconView.alpha = isHighlighted ? 0.45 : 1 }
		}
	}
}

#endif
