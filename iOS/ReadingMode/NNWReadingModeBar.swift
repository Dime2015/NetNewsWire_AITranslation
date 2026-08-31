//
//  NNWReadingModeBar.swift
//  NetNewsWire — AI 翻译 fork
//
//  [阅读档] 底部工具栏正中那个三档控件。本 fork 新增,上游没有。
//
//  ## 长什么样(照 Reeder 的做法)
//
//  ```
//   ★   ( ◉ 未读 )   ≡
//  ```
//  **当前档展开成一颗药丸(图标 + 文字),另外两档只留图标。**
//
//  ## ⚠️ 尺寸:每一格都钉死,而且**总宽恒定**(2026-07-23 连修两次才对)
//
//  **第一版**:让控件按内容自适应宽度。换档时药丸变宽、而工具栏拿到的还是旧宽度 →
//  展开的那颗被压扁,**图标和文字叠在一起**。
//
//  **第二版**:开局量一次尺寸钉死。**还是会挤** —— 因为"量"用的是
//  `systemLayoutSizeFitting`,而 UIKit 给按钮排版时用的是另一套,量出来偏小。
//  **又一次 L73**:我算一套坐标、系统算一套,两套对不上。
//
//  **现在这一版:不量了。** 三格各给一个写死的宽度 ——
//  展开那格 `expandedWidth`、收起两格 `collapsedWidth`。
//  关键在于:**任何时刻都恰好是「一个展开 + 两个收起」**,所以
//  **总宽是个常数**;换档只是把宽度在三格之间挪一挪,外层永远不需要重新问尺寸。
//
//  于是三件事同时不可能发生:量歪、被压缩、整条控件忽宽忽窄地跳。
//  代价是宽度写死 —— 但三个档都是**两个汉字**(星标 / 未读 / 全部)、字号也写死 13pt
//  (刻意不跟随动态字号,工具栏这一格本来就没有伸缩余地)。
//  ⚠️ **以后要是把档位文字改长,记得同步调大 `expandedWidth`。**
//

#if os(iOS)

import UIKit

@MainActor final class NNWReadingModeBar: UIView {

	/// 用户点了某一档。**只在真的换档时调**(点当前档不会触发)。
	var onSelect: ((NNWReadingMode) -> Void)?

	// MARK: - 写死的尺寸(改这里就能调控件大小)

	/// 当前档那一格的宽度。内容 = 图标 16 + 间隔 5 + 两个汉字约 26 ≈ 47,留足余量。
	private static let expandedWidth: CGFloat = 84
	/// 收起的那两格(只有一个图标)
	private static let collapsedWidth: CGFloat = 44
	/// 三档图标的字号。
	///
	/// [外观] 2026-08-09:13 → **15**(用户报「各控件质感不一致」)。
	/// 全 app 别处的控件图标统一走 `NNWSoftMaterial.iconPointSize`(18pt),
	/// **这一格是唯一的例外**:展开那格里图标要和「未读」两个汉字并排,
	/// 拉到 18 会挤,而且 `expandedWidth` 是写死的(见文件头),改大要连带调宽。
	/// 15 是"明显不再是全屏最小的那个图标"和"不挤"之间的折中。
	/// ⚠️ 字重保持 `.semibold`:SF Symbol 的笔画随字号走,15pt semibold 的**绝对笔画**
	/// 才和别处 18pt medium 接近 —— 统一的是**看起来的粗细**,不是那个枚举值。
	private static let iconPointSize: CGFloat = 15
	/// 高度 —— **读全 app 的唯一真源**,别在这里写死(用户 2026-08-05:「以后都一直保持一样」)。
	///
	/// ⚠️ **量圆的直径要横扫取最宽处,别竖扫**:竖扫如果没扫在圆心上,
	/// 量到的是**弦**不是直径,会低估(L109 —— 当天就是这个错让我一路改反了方向)。
	private static var barHeight: CGFloat { NNWSoftMaterial.controlDiameter }
	private static let buttonSpacing: CGFloat = 2
	/// 选中胶囊比它那一格四周各收多少(实测参考图 ≈3.2pt,取 3.5 让"小一点"更明确)
	private static let capsuleInset: CGFloat = 3.5

	/// 总宽恒定 —— 这是整个设计的地基,别改成"按内容算"
	private static var totalWidth: CGFloat {
		expandedWidth + collapsedWidth * 2 + buttonSpacing * 2
	}

	/// **外圈那条轨道归谁画。**
	///
	/// - `false`(默认,住在系统工具栏里):跟着 `NNWSoftMaterial.systemDrawsBarCapsule` 走 ——
	///   那个开关**现在恒为 `false`**(2026-08-05 晚已把版本分叉去掉),所以实际上也是我们画。
	///   ⚠️ 保留这条判断的意义:万一哪天把那个开关翻回 `true`(重新让系统画栏里的胶囊),
	///   栏里这条要跟着跳过,否则就是套娃。
	/// - `true`(已搬出工具栏,浮在页面上):**不管那个开关怎么设,浮层永远得自己画** ——
	///   系统不给浮层垫任何东西。
	///
	/// 📌 用户 2026-08-05 报过的「真机上内圈比外圈小很多」曾经就是这里的病根:
	/// 那时 27 上外圈是**系统**画的(实测 48pt、自带内边距)、内圈是**我们**按自己的高度算的(40pt),
	/// 两把尺子不是同一把。**现在外圈内圈都归我们,这个差从根上没有了**(判据见 L121)。
	let drawsOwnTrack: Bool

	/// 外圈到底画不画。
	private var showsOwnPanel: Bool { drawsOwnTrack || !NNWSoftMaterial.systemDrawsBarCapsule }

	private let stack = UIStackView()

	/// [外观] 2026-08-04:整条做成软面板,当前档是一颗浮起的胶囊(参考图里的 Chat|History)
	// [外观] 2026-08-05:改成**真磨砂** —— 这一条浮在文章列表上方,
	// 底下是滚动的文章。不透明的话等于把唯一有内容可透的地方盖死了。
	private let softPanel = NNWSoftPanel(kind: .panel, translucent: true)
	private let capsule = UIView()
	// [外观] 2026-08-09:选中那一格也改成**半透明**(`translucent: true`)。
	// 原来是实心色,坐在一条真磨砂的轨道上 —— 一实一虚,深色下最扎眼。
	// ⚠️ 半透明的 `.capsule` 档**不会**再垫一块自己的磨砂(否则玻璃套玻璃),
	// 它只是在轨道那块玻璃上压一层更浓的白。见 `NNWSoftPanel.needsOwnBlur`。
	private let capsuleMaterial = NNWSoftPanel(kind: .capsule, translucent: true)
	private var buttons: [NNWReadingMode: UIButton] = [:]
	/// 每一格的宽度约束,换档时只改这三条的常数(总和不变)
	private var widthConstraints: [NNWReadingMode: NSLayoutConstraint] = [:]
	/// [外观] 当前档 —— 胶囊要对准它(layoutSubviews 用)
	private var currentMode: NNWReadingMode = NNWReadingModeStore.shared.mode

	/// - Parameter drawsOwnTrack: 外圈归不归我们画,见该属性的说明。
	init(drawsOwnTrack: Bool = false) {
		self.drawsOwnTrack = drawsOwnTrack
		super.init(frame: .zero)

		stack.axis = .horizontal
		stack.alignment = .center
		stack.distribution = .fill
		stack.spacing = Self.buttonSpacing
		// [外观] 面板 + 胶囊要垫在按钮**下面**,先加它们。
		// ⚠️ iOS 27+ 跳过**外面这层面板**(那里由系统的液态玻璃画,再画就是套娃),
		// 但下面那个 `capsuleMaterial` **要留着** —— 它是"当前选中哪一档"的指示器,
		// 不是栏的背景,系统不会替我们画。见 NNWSoftMaterial.systemDrawsBarCapsule
		if showsOwnPanel {
			softPanel.install(in: self)
		}
		capsule.isUserInteractionEnabled = false
		addSubview(capsule)
		capsuleMaterial.install(in: capsule)

		stack.translatesAutoresizingMaskIntoConstraints = false
		addSubview(stack)
		NSLayoutConstraint.activate([
			stack.centerXAnchor.constraint(equalTo: centerXAnchor),
			stack.centerYAnchor.constraint(equalTo: centerYAnchor)
		])

		for mode in NNWReadingMode.allCases {
			let button = UIButton(type: .system)
			button.addAction(UIAction { [weak self] _ in self?.onSelect?(mode) }, for: .touchUpInside)
			button.accessibilityLabel = mode.title
			button.translatesAutoresizingMaskIntoConstraints = false

			let width = button.widthAnchor.constraint(equalToConstant: Self.collapsedWidth)
			width.isActive = true
			widthConstraints[mode] = width
			button.heightAnchor.constraint(equalToConstant: Self.barHeight).isActive = true

			buttons[mode] = button
			stack.addArrangedSubview(button)
		}

		NSLayoutConstraint.activate([
			widthAnchor.constraint(equalToConstant: Self.totalWidth),
			heightAnchor.constraint(equalToConstant: Self.barHeight)
		])

		// 档位可能在**另一个页面**被改(订阅列表页和文章列表页各有一条),
		// 所以每条都自己盯着通知,不用谁去挨个通知谁。
		NotificationCenter.default.addObserver(self, selector: #selector(modeDidChange),
											   name: NNWReadingModeStore.didChangeNotification, object: nil)
		// [外观] 换强调色之后当前档的字色要跟着变 —— 颜色是在 makeConfiguration 里
		// 一次性写进 UIButton.Configuration 的,不会自己刷新,必须重跑一遍。
		NotificationCenter.default.addObserver(self, selector: #selector(modeDidChange),
											   name: NNWAccentPalette.didChangeNotification, object: nil)

		apply(mode: NNWReadingModeStore.shared.mode)
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { fatalError("不从故事板加载") }

	@objc private func modeDidChange() {
		apply(mode: NNWReadingModeStore.shared.mode)
	}

	/// 把外观切到某一档。**三格宽度的总和永远不变**,所以外层不用重新排版。
	func apply(mode current: NNWReadingMode) {
		currentMode = current
		setNeedsLayout()			// [外观] 胶囊要跟着换位置
		for mode in NNWReadingMode.allCases {
			guard let button = buttons[mode] else { continue }
			let isCurrent = mode == current
			widthConstraints[mode]?.constant = isCurrent ? Self.expandedWidth : Self.collapsedWidth
			button.configuration = Self.makeConfiguration(for: mode, isCurrent: isCurrent)
			button.isEnabled = mode.isAvailable || isCurrent
		}
	}

	// MARK: - 外观配方

	private static func makeConfiguration(for mode: NNWReadingMode, isCurrent: Bool) -> UIButton.Configuration {

		var config = UIButton.Configuration.plain()
		config.image = UIImage(systemName: mode.symbolName,
							   withConfiguration: UIImage.SymbolConfiguration(pointSize: iconPointSize, weight: .semibold))
		config.imagePadding = 5
		// ⚠️ 内边距一律给 0:每一格的宽度已经由约束钉死,再叠内边距只会把内容往里挤
		//(第二版就是内边距 + 自适应宽度一起作用,才把文字挤没的)。内容自己会居中。
		config.contentInsets = .zero

		// ⚠️ 用了 `UIButton.Configuration` 之后,前景色必须走 `baseForegroundColor` ——
		// 设 `button.tintColor` **不起作用**(L75:第一版就是这么写的,装机一看图标文字全是黑的)。
		if isCurrent {
			var title = AttributedString(mode.title)
			title.font = .systemFont(ofSize: 13, weight: .semibold)
			config.attributedTitle = title
			// [外观] 2026-07-28:当前档从「强调色字 + 强调色药丸」改成「暖墨字 + 中性药丸」。
			// 原因:改之前这颗药丸的文字是饱和度 0.49 的橙、底是 0.26 的暖褐,
			// **是整屏饱和度最高的东西** —— 视觉重心被拽到了底部的导航控件上,
			// 而那里并不是内容。参考物 Reeder 的当前档也是「浅灰底 + 深色字」,
			// 高饱和的红只留给「开关」这类真正表达状态的控件。
			// [外观] 2026-08-04:当前档改为「橙字 + 浮起的胶囊」(参考图的做法)。
			// 胶囊由 capsule 视图画(软材质),这里的 background 一律留空,免得两层叠。
			config.baseForegroundColor = NNWSoftMaterial.ink
			config.background.backgroundColor = .clear
		} else {
			config.attributedTitle = nil
			config.background.backgroundColor = .clear
			// 还没做好的档画得更淡,并且点不动
			config.baseForegroundColor = mode.isAvailable ? .secondaryLabel : .tertiaryLabel
		}
		return config
	}

	/// 当前档那颗药丸的底色:统一的「选中高亮」暖中性色。
	///
	/// ⚠️ iOS 26 上整个控件外面**还有一层系统自己的玻璃胶囊**(工具栏给自定义视图套的),
	/// 所以这一层只要"看得出被选中"就够,不能太重 —— 两层药丸叠起来会很脏。
	///
	/// [外观] 2026-07-28 从 `primaryAccent.withAlphaComponent(0.14)` 换成这里 ——
	/// 复用全 app 统一的选中高亮色(语义完全对口:当前档就是"选中"),
	/// 顺带让这颗药丸退出「全屏最跳的颜色」这个位置。
	private static let pillBackground = AppAppearance.selectionHighlight

	override var intrinsicContentSize: CGSize {
		CGSize(width: Self.totalWidth, height: Self.barHeight)
	}

	/// [外观] 面板与胶囊按当前档重画。胶囊对准当前那一格。
	override func layoutSubviews() {
		super.layoutSubviews()
		// 还住在栏里时,iOS 27+ 的外层面板由系统画,这里跳过;搬出来之后永远自己画。
		// 不管画不画,下面的选中胶囊照旧要排版。
		if showsOwnPanel {
			softPanel.layout(in: self, cornerRadius: bounds.height / 2)
		}

		// ⚠️ **必须先让 stack 排完版再读按钮的 frame**(2026-08-04 用户报"遮罩错位"):
		// 换档时改的是每格的宽度约束,而 super.layoutSubviews() 只排到 stack 这一层,
		// stack 内部给三个按钮定位是**之后**才发生的 —— 这时读到的还是上一档的旧宽度,
		// 胶囊就画到了错的位置。layoutIfNeeded 把内层排版提前逼出来。
		stack.layoutIfNeeded()

		guard let currentButton = buttons[currentMode], currentButton.bounds.width > 0 else {
			capsule.isHidden = true
			return
		}
		capsule.isHidden = false
		// 胶囊比它那一格四周都收一圈 —— 参考图里胶囊是"嵌在槽里"的,四边都留缝。
		//
		// ⚠️ **左右也要收**(2026-08-05,用户报"在框体边缘时看不出内外的区别")。
		// 原来写的是 `dx: 0` —— 只收了上下。选中格在**最左或最右**时,
		// 胶囊的边就直接贴上轨道的亮边,两层叠在一起,间隔完全消失。
		// 实测参考图 IMG_2440:胶囊左缘 x=680、轨道左缘 x=664 → 缝 16px ÷ 4.94 = **3.2pt**。
		capsule.frame = convert(currentButton.bounds, from: currentButton)
			.insetBy(dx: Self.capsuleInset, dy: Self.capsuleInset)
		capsuleMaterial.layout(in: capsule, cornerRadius: capsule.bounds.height / 2)
	}
}

#endif
