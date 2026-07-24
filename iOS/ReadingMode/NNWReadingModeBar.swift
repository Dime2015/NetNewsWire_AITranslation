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
	private static let barHeight: CGFloat = 34
	private static let buttonSpacing: CGFloat = 2

	/// 总宽恒定 —— 这是整个设计的地基,别改成"按内容算"
	private static var totalWidth: CGFloat {
		expandedWidth + collapsedWidth * 2 + buttonSpacing * 2
	}

	private let stack = UIStackView()
	private var buttons: [NNWReadingMode: UIButton] = [:]
	/// 每一格的宽度约束,换档时只改这三条的常数(总和不变)
	private var widthConstraints: [NNWReadingMode: NSLayoutConstraint] = [:]

	override init(frame: CGRect) {
		super.init(frame: frame)

		stack.axis = .horizontal
		stack.alignment = .center
		stack.distribution = .fill
		stack.spacing = Self.buttonSpacing
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

		apply(mode: NNWReadingModeStore.shared.mode)
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { fatalError("不从故事板加载") }

	@objc private func modeDidChange() {
		apply(mode: NNWReadingModeStore.shared.mode)
	}

	/// 把外观切到某一档。**三格宽度的总和永远不变**,所以外层不用重新排版。
	func apply(mode current: NNWReadingMode) {
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
							   withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold))
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
			config.baseForegroundColor = Assets.Colors.primaryAccent
			config.background.backgroundColor = pillBackground
			config.background.cornerRadius = barHeight / 2
		} else {
			config.attributedTitle = nil
			config.background.backgroundColor = .clear
			// 还没做好的档画得更淡,并且点不动
			config.baseForegroundColor = mode.isAvailable ? .secondaryLabel : .tertiaryLabel
		}
		return config
	}

	/// 当前档那颗药丸的底色:用强调色化开一点点。
	///
	/// ⚠️ iOS 26 上整个控件外面**还有一层系统自己的玻璃胶囊**(工具栏给自定义视图套的),
	/// 所以这一层只要"看得出被选中"就够,不能太重 —— 两层药丸叠起来会很脏。
	private static let pillBackground = Assets.Colors.primaryAccent.withAlphaComponent(0.14)

	override var intrinsicContentSize: CGSize {
		CGSize(width: Self.totalWidth, height: Self.barHeight)
	}
}

#endif
