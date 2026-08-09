//
//  NNWSoftGlassButton.swift
//  NetNewsWire — AI 翻译 fork
//
//  [外观] 本 fork 新增。一颗「软面板圆钮」,和底栏中间那条三档是同一套材质。
//
//  ## 📌 2026-08-09 起,全 app 的圆钮**都是这一颗**
//
//  在这之前分成两种实现,而且底不一样:
//
//  | 用在哪 | 当时的底 | 当时的实现 |
//  |---|---|---|
//  | 底部工具栏(齿轮/加号、标记已读/下一篇未读) | 不透明 | 面板**烘焙进图片**(`NNWSoftMaterial.roundButtonImage`) |
//  | 导航栏(搜索 / 编辑) | 真磨砂 | 本文件 |
//
//  当时的理由是「工具栏那两颗只能换 image」(加号是 storyboard 的 IBOutlet,
//  上游还往它身上挂 `menu`,换成 customView 会把菜单弄丢)。
//  **那个理由只对"换掉整个 UIBarButtonItem 对象"成立** —— 现在改成
//  「对象不换、只设 customView、把 menu/isEnabled 转发过去」,四颗全部换成了本类。
//  完整来龙去脉见 `NNWSoftGlassBarButton.swift`。
//
//  **换的原因**:用户 2026-08-09 报「各控件的玻璃透明度、层次、质感不一致,深色下尤其明显」。
//  病根就是这张表 —— 同一屏上一半是真玻璃、一半是不透明图片。浅色下两者亮度接近还混得过去,
//  深色下玻璃只补 3–6% 的白、亮度跟着背后内容浮动,而图片是恒定实心,**当场分家**。
//
//  ## 尺寸
//
//  可见圆盘 = `NNWSoftMaterial.controlDiameter`(40pt,全 app 唯一真源);
//  控件本体 44pt = 苹果的最小点按标准,圆盘居中,多出来的一圈只吃点按不画东西。
//  ⚠️ 实测(2026-08-09,读真 frame 不是截图反推):放进工具栏后圆盘落在
//  **上802 / 下842 / 中心822**,和首页那条三档浮层**四项完全相同**。
//

#if os(iOS)

import UIKit

/// ## ⚠️ 为什么基类是 `UIButton` 而不是 `UIControl`(2026-08-09 改)
///
/// 这一颗原来只当导航栏的圆钮用,`UIControl` 就够。现在**底部工具栏那四颗也改用它**
/// (首页齿轮/加号、文章列表页标记已读/下一篇未读),而那四颗身上带着两样
/// `UIControl` 给不了的东西:
///
/// - **点击弹菜单**:首页的加号上,上游挂着一个 `UIMenu`
///   (`MainFeedCollectionViewController.configureContextMenu`)。`UIButton` 自带
///   `menu` + `showsMenuAsPrimaryAction`,`UIControl` 没有。
/// - **禁用态**:上游会写 `isEnabled`(没有账户时加号禁用、没有下一篇未读时那颗禁用)。
///
/// `UIButton` 是 `UIControl` 的子类,`addTarget(_:action:for:)` 一字不变,
/// 唯一原来的用法(导航栏放大镜)不受影响。
@MainActor final class NNWSoftGlassButton: UIButton {

	/// 可见圆盘直径 —— **读全 app 的唯一真源**,别在这里写死。
	/// 用户 2026-08-05:「以后都一直保持一样」。见 `NNWSoftMaterial.controlDiameter`。
	static var discSize: CGFloat { NNWSoftMaterial.controlDiameter }
	/// 点按区边长(苹果最小标准 44pt)。
	///
	/// 🔴 **2026-08-09:从 `discSize + 4` 改成 `max(44, discSize)`** ——
	/// 直径抬到 44 之后,前者算出 48,而**导航栏给 bar item 的高度上限就是 44**,
	/// 于是真机日志里刷了一整屏:
	/// ```
	/// NNWSoftGlassButton.height == 48 (active)
	/// NavigationBarPlatterRepresentable.height == 44 (active)
	/// Will attempt to recover by breaking constraint ... height == 48
	/// ```
	/// 系统每次都得打断我们一条约束才能排下去 —— 不崩,但那是"我们的约束正在被系统悄悄丢掉",
	/// 属于随时会变成真 bug 的那种脏状态。
	///
	/// 直径已经是 44(= 苹果的最小点按标准)本身,不必再外扩:**盘子多大,点按区就多大**。
	static var hitSize: CGFloat { max(44, discSize) }

	/// 磨砂底。⚠️ 它必须在最下面,而且要自己裁圆角。
	/// [外观] 2026-08-05:和 NNWSoftPanel 一样,优先用系统原生的液态玻璃。
	/// 理由见那边的注释(用户在 iOS 27 真机上报"变成遮罩",而我复现不了 → 换系统机制)。
	private let blur: UIVisualEffectView = {
		if #available(iOS 26, *) {
			return UIVisualEffectView(effect: UIGlassEffect(style: .regular))
		}
		return UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
	}()
	/// 材质层(半透明染色 + 整圈亮边 + 极淡阴影)的宿主。
	///
	/// 为什么单独开一个视图而不是画在 self 上:`NNWSoftPanel` 把渐变塞的是**图层**,
	/// 而 `blur` 是**子视图** —— 子视图的图层永远在裸图层上面,直接混着放会被磨砂盖住。
	/// 让材质住在一个独立的、排在磨砂之后的子视图里,层级就不用较劲了。
	private let material = UIView()
	private let softPanel = NNWSoftPanel(kind: .panel, translucent: true)
	private let iconView = UIImageView()

	/// - Parameter icon: 24×24 的模板图(`NNWDockIcons` 那一套)
	init(icon: UIImage, tint: UIColor? = nil) {
		super.init(frame: .zero)

		blur.isUserInteractionEnabled = false
		blur.layer.masksToBounds = true
		blur.layer.cornerCurve = .continuous
		addSubview(blur)

		material.isUserInteractionEnabled = false
		addSubview(material)
		// [外观] iOS 27+:导航栏里这颗的底由系统的液态玻璃画,我们不画磨砂圆盘也不画亮边,
		// 否则就是"系统胶囊里再套一颗圆钮"(用户 2026-08-05 真机截图指出)。
		// 见 NNWSoftMaterial.systemDrawsBarCapsule
		if !NNWSoftMaterial.systemDrawsBarCapsule {
			softPanel.install(in: material)
		} else {
			blur.isHidden = true
			material.isHidden = true
		}

		iconView.image = icon.withRenderingMode(.alwaysTemplate)
		iconView.tintColor = tint ?? NNWSoftMaterial.accent
		iconView.contentMode = .center
		iconView.isUserInteractionEnabled = false
		addSubview(iconView)

		// ⚠️ **必须显式钉死尺寸**,光有 intrinsicContentSize 不够。
		// 2026-08-04 实测:只给 intrinsicContentSize 时,两颗按钮**画得出来但点不动** ——
		// 导航栏没给它算宽高,bounds 是零,子视图照样画(没开 clipsToBounds),
		// 但命中测试按 bounds 走,于是所有触摸都落空。
		// 这是 L73「我算一套坐标、系统算一套」的又一次:**画得对 ≠ 点得到**。
		// 写法照抄工具栏里已验证可用的 NNWReadingModeBar。
		NSLayoutConstraint.activate([
			widthAnchor.constraint(equalToConstant: Self.hitSize),
			heightAnchor.constraint(equalToConstant: Self.hitSize)
		])

		isAccessibilityElement = true
		accessibilityTraits = .button
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { fatalError("不从故事板加载") }

	override var intrinsicContentSize: CGSize {
		CGSize(width: Self.hitSize, height: Self.hitSize)
	}

	override func layoutSubviews() {
		super.layoutSubviews()

		let disc = CGRect(x: (bounds.width - Self.discSize) / 2,
						  y: (bounds.height - Self.discSize) / 2,
						  width: Self.discSize, height: Self.discSize)
		blur.frame = disc
		blur.layer.cornerRadius = Self.discSize / 2
		material.frame = disc
		// iOS 27+ 不画我们这层底(系统画),只摆图标
		if !NNWSoftMaterial.systemDrawsBarCapsule {
			softPanel.layout(in: material, cornerRadius: Self.discSize / 2)
		}
		iconView.frame = bounds
	}

	/// 按下去整颗轻微变暗,和板上其他键的手感一致。
	override var isHighlighted: Bool {
		didSet { nnwUpdateVisualState() }
	}

	/// 禁用时整颗变淡。
	///
	/// ⚠️ **必须和上面那条走同一个出口**:两处都直接写 `alpha` 的话会互相盖掉 ——
	/// 「按下(0.55)后松手(1)」会把「本来就是禁用(0.35)」一并抹成正常态。
	/// 这是本项目反复吃过的那类账:**同一个属性有两个写入点,就要先合并成一个**(L74)。
	override var isEnabled: Bool {
		didSet { nnwUpdateVisualState() }
	}

	private func nnwUpdateVisualState() {
		if !isEnabled {
			alpha = 0.35
		} else {
			alpha = isHighlighted ? 0.55 : 1
		}
	}

	/// 换图标(换强调色 / 换页面状态时用)。
	func nnwSetIcon(_ icon: UIImage, tint: UIColor? = nil) {
		iconView.image = icon.withRenderingMode(.alwaysTemplate)
		iconView.tintColor = tint ?? NNWSoftMaterial.accent
	}
}

#endif
