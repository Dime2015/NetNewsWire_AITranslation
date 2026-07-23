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
//  好处是横向占位小 —— 底部两端已经被「设置」和「+」占着,中间只剩 250pt 上下,
//  三个都带文字会挤成一团。
//
//  ## 为什么不用 UISegmentedControl
//
//  系统分段控件三格等宽、自带灰底,和这一版暖纸风格格不入,
//  而且没法做到"只有当前档有文字"。这里就是三个按钮 + 一个横向 stack,几十行的事。
//

#if os(iOS)

import UIKit

@MainActor final class NNWReadingModeBar: UIView {

	/// 用户点了某一档。**只在真的换档时调**(点当前档不会触发)。
	var onSelect: ((NNWReadingMode) -> Void)?

	private let stack = UIStackView()
	private var buttons: [NNWReadingMode: UIButton] = [:]

	override init(frame: CGRect) {
		super.init(frame: frame)

		stack.axis = .horizontal
		stack.alignment = .center
		stack.spacing = 2
		stack.translatesAutoresizingMaskIntoConstraints = false
		addSubview(stack)
		NSLayoutConstraint.activate([
			stack.topAnchor.constraint(equalTo: topAnchor),
			stack.bottomAnchor.constraint(equalTo: bottomAnchor),
			stack.leadingAnchor.constraint(equalTo: leadingAnchor),
			stack.trailingAnchor.constraint(equalTo: trailingAnchor)
		])

		for mode in NNWReadingMode.allCases {
			let button = UIButton(type: .system)
			button.addAction(UIAction { [weak self] _ in self?.onSelect?(mode) }, for: .touchUpInside)
			button.accessibilityLabel = mode.title
			buttons[mode] = button
			stack.addArrangedSubview(button)
		}

		// 档位可能在**另一个页面**被改(订阅列表页和文章列表页各有一条),
		// 所以每条都自己盯着通知,不用谁去挨个通知谁。
		NotificationCenter.default.addObserver(self, selector: #selector(modeDidChange),
											   name: NNWReadingModeStore.didChangeNotification, object: nil)

		apply(mode: NNWReadingModeStore.shared.mode)
	}

	@objc private func modeDidChange() {
		apply(mode: NNWReadingModeStore.shared.mode)
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { fatalError("不从故事板加载") }

	/// 把外观切到某一档。**换档动画只动这一层,不碰列表**(L63:滚动/布局回调里别连锁改东西)。
	func apply(mode current: NNWReadingMode) {
		for mode in NNWReadingMode.allCases {
			guard let button = buttons[mode] else { continue }
			let isCurrent = mode == current

			var config = UIButton.Configuration.plain()
			config.image = UIImage(systemName: mode.symbolName,
								   withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold))
			config.imagePadding = 5
			config.contentInsets = isCurrent
				? NSDirectionalEdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 13)
				: NSDirectionalEdgeInsets(top: 6, leading: 9, bottom: 6, trailing: 9)

			// ⚠️ 用了 `UIButton.Configuration` 之后,前景色必须走 `baseForegroundColor` ——
			// 设 `button.tintColor` **不起作用**(第一版就是这么写的,装机一看图标文字全是黑的)。
			if isCurrent {
				var title = AttributedString(mode.title)
				title.font = .systemFont(ofSize: 13, weight: .semibold)
				config.attributedTitle = title
				config.baseForegroundColor = Assets.Colors.primaryAccent
				config.background.backgroundColor = Self.pillBackground
				config.background.cornerRadius = 15
			} else {
				config.attributedTitle = nil
				config.background.backgroundColor = .clear
				// 还没做好的档(Phase 1 的★)画得更淡,并且点不动
				config.baseForegroundColor = mode.isAvailable ? .secondaryLabel : .tertiaryLabel
			}

			button.isEnabled = mode.isAvailable || isCurrent
			button.configuration = config
		}

		// 换档时宽度会变(药丸从一格跳到另一格),让工具栏重新排一次
		invalidateIntrinsicContentSize()
		superview?.setNeedsLayout()
	}

	/// 当前档那颗药丸的底色:用强调色化开一点点。
	///
	/// ⚠️ iOS 26 上整个控件外面**还有一层系统自己的玻璃胶囊**(工具栏给自定义视图套的),
	/// 所以这一层只要"看得出被选中"就够,不能太重 —— 两层药丸叠起来会很脏。
	private static let pillBackground = Assets.Colors.primaryAccent.withAlphaComponent(0.14)

	override var intrinsicContentSize: CGSize {
		stack.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
	}
}

#endif
