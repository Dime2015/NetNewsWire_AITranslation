import UIKit

// 全 app 统一的毛玻璃弹出菜单（2026-09-25，用户要求「所有弹出的菜单都改成设置页选单那种毛玻璃」）。
// 外观与设置页弹出选单同源（Figma「Babel/Popover/Thick Glass」）：圆角 22、0.5pt 细线、投影、背景模糊。
// 用于：阅读页「•••」、文章列表大图「•••」、「全部标为已读」确认。屏幕中间的确认 / 输入对话框保留系统样式（用户同意）。

/// 毛玻璃卡片：背景模糊 + 半透明底色 + 细线描边 + 投影。设置页选单与通用菜单共用。
final class Babel2GlassCard: UIView {
	let contentView = UIView()

	override init(frame: CGRect) {
		super.init(frame: frame)
		layer.cornerRadius = 22
		layer.cornerCurve = .continuous
		layer.borderWidth = 0.5
		layer.shadowColor = UIColor.black.cgColor
		layer.shadowOpacity = 0.15
		layer.shadowRadius = 14
		layer.shadowOffset = CGSize(width: 0, height: 10)
		let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemThickMaterial))
		blur.layer.cornerRadius = 22
		blur.layer.cornerCurve = .continuous
		blur.clipsToBounds = true
		blur.translatesAutoresizingMaskIntoConstraints = false
		let tint = UIView()
		tint.backgroundColor = Babel2SettingsStyle.elevatedBackground
		tint.translatesAutoresizingMaskIntoConstraints = false
		blur.contentView.addSubview(tint)
		addSubview(blur)
		contentView.translatesAutoresizingMaskIntoConstraints = false
		addSubview(contentView)
		NSLayoutConstraint.activate([
			blur.leadingAnchor.constraint(equalTo: leadingAnchor),
			blur.trailingAnchor.constraint(equalTo: trailingAnchor),
			blur.topAnchor.constraint(equalTo: topAnchor),
			blur.bottomAnchor.constraint(equalTo: bottomAnchor),
			tint.leadingAnchor.constraint(equalTo: blur.contentView.leadingAnchor),
			tint.trailingAnchor.constraint(equalTo: blur.contentView.trailingAnchor),
			tint.topAnchor.constraint(equalTo: blur.contentView.topAnchor),
			tint.bottomAnchor.constraint(equalTo: blur.contentView.bottomAnchor),
			contentView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
			contentView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
			contentView.topAnchor.constraint(equalTo: topAnchor, constant: 6),
			contentView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6)
		])
		updateBorder()
		registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: Babel2GlassCard, _) in
			view.updateBorder()
		}
	}

	required init?(coder: NSCoder) { nil }

	private func updateBorder() {
		layer.borderColor = Babel2SettingsStyle.hairline.resolvedColor(with: traitCollection).cgColor
	}
}

/// 菜单里的一项。isOn 为 nil 表示普通动作；为 true / false 表示开关（开时右侧显示勾）。
struct Babel2MenuItem {
	let title: String
	var image: UIImage?
	let identifier: String
	var isOn: Bool?
	var isDestructive = false
	var isEnabled = true
	let handler: () -> Void
}

/// 通用毛玻璃菜单：可选顶部说明文字；各组之间细线分隔；每项 44pt（左 18pt 图标、文字 15、右侧勾；ADR-033 收小一档），危险项红色，不可用项变灰。
/// 锚定在触发按钮下方（放不下时在上方），水平方向尽量对齐按钮、不出屏；点空白处关闭，选中后关闭并执行。
final class Babel2GlassMenu: UIView {
	private let card = Babel2GlassCard()
	private var items = [Babel2MenuItem]()
	/// 卡片上最靠近触发按钮的点（展开 / 收起的中心）
	private var growOrigin: CGPoint = .zero
	/// 仅供自动化测试：各项的控件（按顺序）。
	private(set) var itemControlsForTesting = [UIControl]()

	@discardableResult
	static func present(sections: [[Babel2MenuItem]], title: String? = nil, from anchor: UIView, in host: UIView) -> Babel2GlassMenu {
		let menu = Babel2GlassMenu(sections: sections.filter { !$0.isEmpty }, title: title)
		menu.frame = host.bounds
		menu.autoresizingMask = [.flexibleWidth, .flexibleHeight]
		host.addSubview(menu)
		menu.place(anchoredTo: anchor)
		// 从触发按钮那一侧展开（ADR-034）：以卡片上最靠近按钮的点为中心，由 92% 放大到原大并淡入
		menu.card.alpha = 0
		menu.card.transform = menu.growTransform(scale: 0.92)
		Babel2Motion.animate(Babel2Motion.standard) {
			menu.card.alpha = 1
			menu.card.transform = .identity
		}
		UIAccessibility.post(notification: .screenChanged, argument: menu.itemControlsForTesting.first)
		return menu
	}

	private init(sections: [[Babel2MenuItem]], title: String?) {
		super.init(frame: .zero)
		backgroundColor = .clear
		accessibilityIdentifier = "babel2.menu"
		accessibilityViewIsModal = true
		let dismissTap = UITapGestureRecognizer(target: self, action: #selector(backgroundTapped(_:)))
		dismissTap.cancelsTouchesInView = false
		addGestureRecognizer(dismissTap)

		let stack = UIStackView()
		stack.axis = .vertical
		stack.translatesAutoresizingMaskIntoConstraints = false
		card.contentView.addSubview(stack)
		NSLayoutConstraint.activate([
			stack.leadingAnchor.constraint(equalTo: card.contentView.leadingAnchor),
			stack.trailingAnchor.constraint(equalTo: card.contentView.trailingAnchor),
			stack.topAnchor.constraint(equalTo: card.contentView.topAnchor),
			stack.bottomAnchor.constraint(equalTo: card.contentView.bottomAnchor)
		])
		if let title, !title.isEmpty {
			let label = UILabel()
			label.text = title
			label.font = Babel2Type.menuHeader
			label.textColor = Babel2SettingsStyle.secondaryText
			label.numberOfLines = 0
			label.textAlignment = .center
			label.accessibilityIdentifier = "babel2.menu.title"
			let wrapper = UIView()
			label.translatesAutoresizingMaskIntoConstraints = false
			wrapper.addSubview(label)
			NSLayoutConstraint.activate([
				label.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 14),
				label.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -14),
				label.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: 10),
				label.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: -10)
			])
			stack.addArrangedSubview(wrapper)
			stack.addArrangedSubview(Self.divider())
		}
		for (sectionIndex, section) in sections.enumerated() {
			if sectionIndex > 0 { stack.addArrangedSubview(Self.divider()) }
			for item in section {
				let row = Babel2GlassMenuRow(item: item)
				row.tag = items.count
				row.addTarget(self, action: #selector(itemTapped(_:)), for: .touchUpInside)
				stack.addArrangedSubview(row)
				items.append(item)
				itemControlsForTesting.append(row)
			}
		}
		addSubview(card)
	}

	required init?(coder: NSCoder) { nil }

	private static func divider() -> UIView {
		let wrapper = UIView()
		let line = UIView()
		line.backgroundColor = Babel2SettingsStyle.hairline
		line.translatesAutoresizingMaskIntoConstraints = false
		wrapper.addSubview(line)
		NSLayoutConstraint.activate([
			wrapper.heightAnchor.constraint(equalToConstant: 9),
			line.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 14),
			line.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -14),
			line.centerYAnchor.constraint(equalTo: wrapper.centerYAnchor),
			line.heightAnchor.constraint(equalToConstant: 0.5)
		])
		return wrapper
	}

	/// 宽度 272（Figma 选单宽度）、最多屏宽 − 40；按内容算高度。放在按钮下方 6pt，放不下就放到上方。
	private func place(anchoredTo anchor: UIView) {
		let width = min(272, bounds.width - 40)
		card.frame = CGRect(x: 0, y: 0, width: width, height: 10)
		let height = card.systemLayoutSizeFitting(CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
			withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height
		let anchorFrame = anchor.convert(anchor.bounds, to: self)
		let x = min(max(20, anchorFrame.midX - width / 2), bounds.width - 20 - width)
		var y = anchorFrame.maxY + 6
		if y + height > bounds.height - safeAreaInsets.bottom - 8 {
			y = max(safeAreaInsets.top + 8, anchorFrame.minY - 6 - height)
		}
		card.frame = CGRect(x: x, y: y, width: width, height: height)
		let below = y >= anchorFrame.maxY
		growOrigin = CGPoint(x: min(max(anchorFrame.midX, card.frame.minX + 22), card.frame.maxX - 22),
			y: below ? card.frame.minY : card.frame.maxY)
	}

	/// 以 growOrigin 为中心缩放的变换（transform 默认以卡片中心为原点，所以要补一个平移）。
	/// 减弱动态效果时不缩放，只淡入淡出。
	private func growTransform(scale: CGFloat) -> CGAffineTransform {
		guard !Babel2Motion.reduceMotion else { return .identity }
		let center = CGPoint(x: card.frame.midX, y: card.frame.midY)
		let dx = (growOrigin.x - center.x) * (1 - scale)
		let dy = (growOrigin.y - center.y) * (1 - scale)
		return CGAffineTransform(translationX: dx, y: dy).scaledBy(x: scale, y: scale)
	}

	/// 仅供自动化测试。
	var cardFrameForTesting: CGRect { card.frame }
	var growOriginForTesting: CGPoint { growOrigin }
	func growTransformForTesting(scale: CGFloat) -> CGAffineTransform { growTransform(scale: scale) }

	@objc private func itemTapped(_ sender: UIControl) {
		let item = items[sender.tag]
		guard item.isEnabled else { return }
		dismiss()
		item.handler()
	}

	/// 仅供自动化测试：选中某一项（与点按同一路径，不等动画）。
	func selectForTesting(_ identifier: String) {
		guard let item = items.first(where: { $0.identifier == identifier }), item.isEnabled else { return }
		removeFromSuperview()
		item.handler()
	}

	@objc private func backgroundTapped(_ gesture: UITapGestureRecognizer) {
		guard !card.frame.contains(gesture.location(in: self)) else { return }
		dismiss()
	}

	func dismiss() {
		Babel2Motion.animate(Babel2Motion.quick, {
			self.card.alpha = 0
			self.card.transform = self.growTransform(scale: 0.96)
		}, completion: { _ in
			self.removeFromSuperview()
		})
	}
}

/// 菜单的一行：左 14，18pt 图标位 → 10 → 文字（最多 2 行）→ 右侧勾（开关开时）。
private final class Babel2GlassMenuRow: UIControl {
	init(item: Babel2MenuItem) {
		super.init(frame: .zero)
		isEnabled = item.isEnabled
		isAccessibilityElement = true
		accessibilityLabel = item.title
		accessibilityIdentifier = item.identifier
		var traits: UIAccessibilityTraits = .button
		if item.isOn == true { traits.insert(.selected) }
		if !item.isEnabled { traits.insert(.notEnabled) }
		accessibilityTraits = traits
		let color = item.isDestructive ? Babel2SettingsStyle.destructive : Babel2SettingsStyle.primaryText
		let icon = UIImageView(image: item.image?.withRenderingMode(.alwaysTemplate))
		icon.tintColor = item.isDestructive ? Babel2SettingsStyle.destructive : Babel2SettingsStyle.secondaryText
		icon.contentMode = .scaleAspectFit
		let label = UILabel()
		label.text = item.title
		label.font = Babel2Type.menuRow
		label.textColor = color
		label.numberOfLines = 2
		let check = UIImageView(image: UIImage(named: "Babel2SettingsCheck"))
		check.tintColor = Babel2SettingsStyle.secondaryText
		check.isHidden = item.isOn != true
		for view in [icon, label, check] as [UIView] {
			view.isUserInteractionEnabled = false
			view.translatesAutoresizingMaskIntoConstraints = false
			addSubview(view)
		}
		alpha = item.isEnabled ? 1 : 0.4
		NSLayoutConstraint.activate([
			heightAnchor.constraint(greaterThanOrEqualToConstant: Babel2Type.menuRowHeight),
			icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
			icon.centerYAnchor.constraint(equalTo: centerYAnchor),
			icon.widthAnchor.constraint(equalToConstant: 18),
			icon.heightAnchor.constraint(equalToConstant: 18),
			label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
			label.trailingAnchor.constraint(lessThanOrEqualTo: check.leadingAnchor, constant: -8),
			label.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 12),
			label.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -12),
			label.centerYAnchor.constraint(equalTo: centerYAnchor),
			check.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
			check.centerYAnchor.constraint(equalTo: centerYAnchor),
			check.widthAnchor.constraint(equalToConstant: 18),
			check.heightAnchor.constraint(equalToConstant: 18)
		])
	}

	required init?(coder: NSCoder) { nil }

	override var isHighlighted: Bool {
		// 按下时底色淡入、松开淡出（ADR-034）
		didSet {
			let color = isHighlighted ? Babel2SettingsStyle.hairline.withAlphaComponent(0.5) : .clear
			Babel2Motion.animate(Babel2Motion.quick) { self.backgroundColor = color }
		}
	}
}
