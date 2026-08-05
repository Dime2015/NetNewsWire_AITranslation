//
//  NNWSoftGlassButton.swift
//  NetNewsWire — AI 翻译 fork
//
//  [外观] 本 fork 新增。一颗「软面板圆钮」,和底栏中间那条三档是同一套材质。
//
//  ## 为什么它和工具栏那两颗(齿轮/加号)不是同一种实现
//
//  两者**长得一样,底不一样**:
//
//  | 用在哪 | 底是什么 | 实现 |
//  |---|---|---|
//  | 底部工具栏(齿轮 / 加号) | 纯色暖纸 | 面板**烘焙进图片**(`NNWSoftMaterial.roundButtonImage`) |
//  | 导航栏(搜索 / 编辑) | **首页头图,是张照片** | 本文件:磨砂玻璃 + 同一圈亮边 |
//
//  分开的两个原因,都是硬的:
//
//  1. **工具栏那两颗只能换 image**。加号是 storyboard 的 IBOutlet,上游还往它身上挂
//     `menu`(`MainFeedCollectionViewController.swift:897`),换成 customView 会把长按菜单
//     整个弄丢。所以那两颗只能烘焙成图片 —— 而图片里装不下"磨砂"。
//  2. **导航栏那两颗压在照片上**。2026-08-04 先按工具栏的做法上了不透明圆盘,
//     截图一看是两张**贴纸**:圆盘和背后的画毫无关系。压在图上就必须真透。
//
//  在各自的底上,两者观感一致(磨砂盖在纯色上 ≈ 那个纯色),所以"统一"没有破。
//
//  ## 尺寸
//
//  可见圆盘 34pt = 三档控件的高度(并排时一样高);
//  控件本体 44pt = 苹果的最小点按标准,圆盘居中,多出来的一圈只吃点按不画东西。
//

#if os(iOS)

import UIKit

@MainActor final class NNWSoftGlassButton: UIControl {

	/// 可见圆盘直径 —— **读全 app 的唯一真源**,别在这里写死。
	/// 用户 2026-08-05:「以后都一直保持一样」。见 `NNWSoftMaterial.controlDiameter`。
	static var discSize: CGFloat { NNWSoftMaterial.controlDiameter }
	/// 点按区边长(苹果最小标准)。圆盘在中间,四周 5pt 只吃点按。
	static var hitSize: CGFloat { max(44, discSize + 4) }

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
		softPanel.install(in: material)

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
		softPanel.layout(in: material, cornerRadius: Self.discSize / 2)
		iconView.frame = bounds
	}

	/// 按下去整颗轻微变暗,和板上其他键的手感一致。
	override var isHighlighted: Bool {
		didSet { alpha = isHighlighted ? 0.55 : 1 }
	}
}

#endif
