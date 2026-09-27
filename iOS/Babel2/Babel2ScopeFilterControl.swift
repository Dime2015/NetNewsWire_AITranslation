import UIKit
import Babel2Core

/// 星标 / 未读 / 全部 三档切换条（Figma「Feed Toolbar」22:35 与 Filter Pill 28:44）。
///
/// 外观与首页底栏完全一致（图标、胶囊宽度 90 / 78 / 68、选中文字 10pt 半粗、0.22 秒先快后缓的胶囊滑动，ADR-034），
/// 首页与订阅源文章列表页共用本组件（2026-09-25 起；首页原先的手写实现在真机上切回「未读」
/// 时胶囊会错位，用户选择统一到本组件）。
///
/// 它铺满整条底栏宽度，三个按钮中心按 402pt 画布的 x = 116.5 / 201 / 285.5 比例定位（ADR-033 等距底栏）。
@MainActor
final class Babel2ScopeFilterControl: UIView {
	static let displayOrder: [Babel2FeedScope] = [.starred, .unread, .all]
	private static let referenceCenters = Babel2BarLayout.scopeSlots

	private let selectionPill = UIView()
	private(set) var buttons = [Babel2FeedScope: Babel2ScopeButton]()
	private(set) var selectedScope: Babel2FeedScope
	var onSelect: ((Babel2FeedScope) -> Void)?
	private var animator: UIViewPropertyAnimator?

	/// - identifierPrefix: 按钮无障碍标识前缀（首页沿用原来的 "babel2.scope"，测试与 UI 驱动不用改）
	init(
		selectedScope: Babel2FeedScope,
		identifierPrefix: String = "babel2.feed.scope",
		controlIdentifier: String = "babel2.feed.scope.controls",
		localizationBundle: Bundle = .main
	) {
		self.selectedScope = selectedScope
		super.init(frame: .zero)
		accessibilityIdentifier = controlIdentifier
		selectionPill.backgroundColor = BabelPalette.raisedBackground.withAlphaComponent(0.62)
		selectionPill.layer.cornerRadius = 13
		selectionPill.isUserInteractionEnabled = false
		selectionPill.accessibilityElementsHidden = true
		addSubview(selectionPill)
		for (index, scope) in Self.displayOrder.enumerated() {
			let button = Babel2ScopeButton()
			button.titleText = scope.localizationKey.rawValue.uppercased()
			button.accessibilityIdentifier = "\(identifierPrefix).\(scope.rawValue)"
			button.accessibilityLabel = Babel2Localization.text(scope.localizationKey, bundle: localizationBundle)
			button.addAction(UIAction { [weak self] _ in self?.tapped(scope) }, for: .touchUpInside)
			button.translatesAutoresizingMaskIntoConstraints = false
			addSubview(button)
			Babel2Motion.addPressFeedback(to: button)
			buttons[scope] = button
			let width: CGFloat = scope == .starred ? 90 : (scope == .unread ? 78 : 68)
			NSLayoutConstraint.activate([
				button.widthAnchor.constraint(equalToConstant: width),
				button.heightAnchor.constraint(equalToConstant: 44),
				button.centerYAnchor.constraint(equalTo: topAnchor, constant: Babel2BarLayout.centerY),
				Babel2BarLayout.centerX(button, in: self, slot: Self.referenceCenters[index])
			])
		}
		updateButtons()
	}

	required init?(coder: NSCoder) { nil }

	/// 仅供自动化测试：选中胶囊的（目标）位置。
	var selectionPillFrameForTesting: CGRect { selectionPill.frame }

	/// 胶囊按按钮的「原始」大小定位：按下时按钮会缩到 94%（ADR-034 按压反馈），frame 会跟着变小，
	/// 所以用 center + bounds（不受缩放影响），胶囊始终是原来的大小。
	private static func pillFrame(for button: UIButton) -> CGRect {
		let size = button.bounds.size
		return CGRect(x: button.center.x - size.width / 2, y: button.center.y - size.height / 2,
			width: size.width, height: size.height).insetBy(dx: 0, dy: 9)
	}

	override func layoutSubviews() {
		super.layoutSubviews()
		if animator == nil, let button = buttons[selectedScope] {
			selectionPill.frame = Self.pillFrame(for: button)
		}
	}

	/// 外部改档位（例如同步首页）：不触发 onSelect，直接更新显示。
	func setSelectedScope(_ scope: Babel2FeedScope, animated: Bool) {
		guard scope != selectedScope else { return }
		selectedScope = scope
		updateButtons()
		movePill(animated: animated)
	}

	private func tapped(_ scope: Babel2FeedScope) {
		guard scope != selectedScope else { return }
		setSelectedScope(scope, animated: true)
		onSelect?(scope)
	}

	private func movePill(animated: Bool) {
		animator?.stopAnimation(true)
		animator = nil
		guard let button = buttons[selectedScope] else { return }
		layoutIfNeeded()
		let target = Self.pillFrame(for: button)
		guard animated, window != nil else {
			selectionPill.frame = target
			return
		}
		// 减弱动态效果：胶囊不滑动，直接到位后淡入
		if Babel2Motion.reduceMotion {
			selectionPill.frame = target
			selectionPill.alpha = 0
		}
		// 统一动效（ADR-034）：0.22 秒、先快后缓
		let animator = UIViewPropertyAnimator(duration: Babel2Motion.standard, curve: .easeOut) { [weak self] in
			self?.selectionPill.frame = target
			self?.selectionPill.alpha = 1
		}
		animator.addCompletion { [weak self] _ in self?.animator = nil }
		self.animator = animator
		animator.startAnimation()
	}

	private func updateButtons() {
		for (scope, button) in buttons {
			let isSelected = scope == selectedScope
			button.accessibilityValue = isSelected ? "Selected" : "Not selected"
			button.accessibilityTraits = isSelected ? [.button, .selected] : [.button]
			button.icon = Self.image(for: scope, selected: isSelected)
			button.showsTitle = isSelected
			button.leadingInset = scope == .starred ? 10 : (scope == .unread ? 8 : 9)
			button.iconSpacing = scope == .unread ? 7 : 6
		}
	}

	/// 与首页同一套图标：星标（选中为实心小星）、未读（8pt 圆点）、全部（横线，选中缩到 15pt）。
	/// 没选中的星标 / 横线按底栏统一画法（21pt 画布，ADR-052），与阅读页底栏同一位置的星、横线一样大。
	private static func image(for scope: Babel2FeedScope, selected: Bool) -> UIImage? {
		switch scope {
		case .starred:
			if selected { return UIImage(named: "BabelFilterSelectedStar")?.withRenderingMode(.alwaysTemplate) }
			return Babel2Type.barIcon(UIImage(named: "BabelHomeStar"), optical: Babel2Type.BarOptical.star)
		case .unread:
			return UIImage(systemName: "circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 8, weight: .regular))
		case .all:
			guard let image = UIImage(named: "BabelHomeAll")?.withRenderingMode(.alwaysTemplate) else { return nil }
			guard selected else { return Babel2Type.barIcon(image, optical: Babel2Type.BarOptical.lines) }
			let size = CGSize(width: 15, height: 15)
			return UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
				.withRenderingMode(.alwaysTemplate)
		}
	}
}

/// 档位按钮（2026-09-27 修「● UNREAD」圆点和文字叠在一起）。
///
/// 以前用系统按钮的「配置」自动排图标和文字，在 78pt 宽的固定格子里偶尔会排错（首页 9-25 出过一次，
/// 当时改用本组件绕开；这次文章列表第一次打开某个源时又出现）。模拟器里复现不了，具体时机没查实（推测是页面滑入动画中第一次排版）。
/// 现在不交给系统排：图标、文字的位置每次排版都按按钮自己的大小直接算出来——
/// 选中：图标从左边 leadingInset 起，文字紧跟在图标右边 iconSpacing 处；没选中：只有图标，居中。
/// 文字的起点永远在图标右边，任何时机都不可能压在图标上。
/// 按钮大小用 bounds（不受按压缩放影响），按下时整体跟着缩放，相对位置不变。
@MainActor
final class Babel2ScopeButton: UIButton {
	private let iconView = UIImageView()
	private let textLabel = UILabel()

	var icon: UIImage? {
		didSet { iconView.image = icon; setNeedsLayout() }
	}
	var titleText = "" {
		didSet { textLabel.text = titleText; setNeedsLayout() }
	}
	var showsTitle = false {
		didSet { setNeedsLayout() }
	}
	var leadingInset: CGFloat = 0 {
		didSet { setNeedsLayout() }
	}
	var iconSpacing: CGFloat = 6 {
		didSet { setNeedsLayout() }
	}

	init() {
		super.init(frame: .zero)
		iconView.tintColor = BabelPalette.mutedInk
		iconView.contentMode = .center
		iconView.isUserInteractionEnabled = false
		textLabel.font = .systemFont(ofSize: 10, weight: .semibold)
		textLabel.textColor = BabelPalette.mutedInk
		textLabel.isUserInteractionEnabled = false
		addSubview(iconView)
		addSubview(textLabel)
	}

	required init?(coder: NSCoder) { nil }

	override func layoutSubviews() {
		super.layoutSubviews()
		let frames = Self.contentFrames(in: bounds.size, iconSize: icon?.size ?? .zero,
			textSize: textLabel.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: bounds.height)),
			showsTitle: showsTitle, leadingInset: leadingInset, iconSpacing: iconSpacing,
			scale: max(traitCollection.displayScale, 1))
		iconView.frame = frames.icon
		textLabel.frame = frames.text ?? .zero
		textLabel.isHidden = frames.text == nil
	}

	/// 图标、文字在按钮里的位置（纯计算，测试直接核对）。
	static func contentFrames(in size: CGSize, iconSize: CGSize, textSize: CGSize, showsTitle: Bool,
		leadingInset: CGFloat, iconSpacing: CGFloat, scale: CGFloat) -> (icon: CGRect, text: CGRect?) {
		func pixel(_ value: CGFloat) -> CGFloat { (value * scale).rounded() / scale }
		guard showsTitle else {
			return (CGRect(x: pixel((size.width - iconSize.width) / 2), y: pixel((size.height - iconSize.height) / 2),
				width: iconSize.width, height: iconSize.height), nil)
		}
		let icon = CGRect(x: pixel(leadingInset), y: pixel((size.height - iconSize.height) / 2),
			width: iconSize.width, height: iconSize.height)
		let textX = icon.maxX + iconSpacing
		let text = CGRect(x: pixel(textX), y: pixel((size.height - textSize.height) / 2),
			width: max(0, min(textSize.width, size.width - textX)), height: textSize.height)
		return (icon, text)
	}

	/// 仅供自动化测试：屏幕上真正画出来的图标、文字（不是系统按钮的内部副本，见 LESSONS 36）。
	var iconViewForTesting: UIImageView { iconView }
	var textLabelForTesting: UILabel { textLabel }
}
