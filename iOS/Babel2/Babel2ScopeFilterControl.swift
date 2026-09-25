import UIKit
import Babel2Core

/// 星标 / 未读 / 全部 三档切换条（Figma「Feed Toolbar」22:35 与 Filter Pill 28:44）。
///
/// 外观与首页底栏完全一致（图标、胶囊宽度 90 / 78 / 68、选中文字 10pt 半粗、0.18 秒胶囊滑动），
/// 首页与订阅源文章列表页共用本组件（2026-09-25 起；首页原先的手写实现在真机上切回「未读」
/// 时胶囊会错位，用户选择统一到本组件）。
///
/// 它铺满整条底栏宽度，三个按钮中心按 402pt 画布的 x = 104 / 201 / 290.5 比例定位。
@MainActor
final class Babel2ScopeFilterControl: UIView {
	static let displayOrder: [Babel2FeedScope] = [.starred, .unread, .all]
	private static let referenceCenters: [CGFloat] = [104, 201, 290.5]
	private static let referenceWidth: CGFloat = 402

	private let selectionPill = UIView()
	private(set) var buttons = [Babel2FeedScope: UIButton]()
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
			let button = UIButton(type: .system)
			button.configuration = .plain()
			button.configuration?.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
				var transformed = attributes
				transformed.font = .systemFont(ofSize: 10, weight: .semibold)
				transformed.foregroundColor = BabelPalette.mutedInk
				return transformed
			}
			button.tintColor = BabelPalette.mutedInk
			button.accessibilityIdentifier = "\(identifierPrefix).\(scope.rawValue)"
			button.accessibilityLabel = Babel2Localization.text(scope.localizationKey, bundle: localizationBundle)
			button.addAction(UIAction { [weak self] _ in self?.tapped(scope) }, for: .touchUpInside)
			button.translatesAutoresizingMaskIntoConstraints = false
			addSubview(button)
			buttons[scope] = button
			let width: CGFloat = scope == .starred ? 90 : (scope == .unread ? 78 : 68)
			NSLayoutConstraint.activate([
				button.widthAnchor.constraint(equalToConstant: width),
				button.heightAnchor.constraint(equalToConstant: 44),
				button.centerYAnchor.constraint(equalTo: topAnchor, constant: 24),
				NSLayoutConstraint(
					item: button, attribute: .centerX, relatedBy: .equal,
					toItem: self, attribute: .trailing,
					multiplier: Self.referenceCenters[index] / Self.referenceWidth, constant: 0
				)
			])
		}
		updateButtons()
	}

	required init?(coder: NSCoder) { nil }

	override func layoutSubviews() {
		super.layoutSubviews()
		if animator == nil, let button = buttons[selectedScope] {
			selectionPill.frame = button.frame.insetBy(dx: 0, dy: 9)
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
		let target = button.frame.insetBy(dx: 0, dy: 9)
		guard animated, window != nil else {
			selectionPill.frame = target
			return
		}
		let animator = UIViewPropertyAnimator(duration: 0.18, curve: .linear) { [weak self] in
			self?.selectionPill.frame = target
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
			button.contentHorizontalAlignment = isSelected ? .leading : .center
			var configuration = button.configuration ?? .plain()
			configuration.image = Self.image(for: scope, selected: isSelected)
			configuration.title = isSelected ? scope.localizationKey.rawValue.uppercased() : nil
			configuration.imagePlacement = .leading
			configuration.imagePadding = scope == .unread ? 7 : 6
			configuration.contentInsets = NSDirectionalEdgeInsets(
				top: 0,
				leading: isSelected ? (scope == .starred ? 10 : (scope == .unread ? 8 : 9)) : 0,
				bottom: 0,
				trailing: 0
			)
			button.configuration = configuration
		}
	}

	/// 与首页同一套图标：星标（选中为实心小星）、未读（8pt 圆点）、全部（三条横线，选中缩到 15pt）。
	private static func image(for scope: Babel2FeedScope, selected: Bool) -> UIImage? {
		switch scope {
		case .starred:
			return UIImage(named: selected ? "BabelFilterSelectedStar" : "BabelHomeStar")?.withRenderingMode(.alwaysTemplate)
		case .unread:
			return UIImage(systemName: "circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 8, weight: .regular))
		case .all:
			guard let image = UIImage(named: "BabelHomeAll")?.withRenderingMode(.alwaysTemplate) else { return nil }
			guard selected else { return image }
			let size = CGSize(width: 15, height: 15)
			return UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
				.withRenderingMode(.alwaysTemplate)
		}
	}
}
