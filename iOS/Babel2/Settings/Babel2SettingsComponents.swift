import UIKit

// 设置页的可复用组件，逐一对应 Figma 组件（Slice 6）：
// 导航栏（Root / Back / Editor）、分组标题、Disclosure 行、Value 行、Select 行、Toggle 行、Action 行、
// Choice 行、文本框、开关、弹出单选菜单。行与行之间没有分隔线。

// MARK: - 导航栏

/// Figma「Navigation Bar / Settings Root · Back · Editor」：58pt，左侧 24pt 图标（中心 x=32），
/// 标题 24pt 半粗从 x=58 开始，编辑页右侧保存勾（中心 x=370），底部 0.5pt 细线。
final class Babel2SettingsNavigationBar: UIView {
	enum Kind {
		/// 设置首页：左侧 ×（关闭）
		case root
		/// 类别页 / 二级页：左侧 ‹（返回）
		case back
		/// 点保存才生效的编辑页：左 ×（取消）、右 ✓（保存）
		case editor
	}

	let leadingButton = UIButton(type: .system)
	let saveButton = UIButton(type: .system)
	let titleLabel = UILabel()

	init(kind: Kind, title: String) {
		super.init(frame: .zero)
		backgroundColor = Babel2SettingsStyle.background

		let leadingImage = kind == .back ? "Babel2SettingsBack" : "Babel2SettingsClose"
		leadingButton.setImage(UIImage(named: leadingImage), for: .normal)
		leadingButton.tintColor = Babel2SettingsStyle.secondaryText
		leadingButton.accessibilityLabel = Babel2SettingsText.t(kind == .back ? "Back" : (kind == .root ? "Close" : "Cancel"))
		leadingButton.accessibilityIdentifier = kind == .editor ? "babel2.settings.cancel" : "babel2.settings.back"

		saveButton.setImage(UIImage(named: "Babel2SettingsSave"), for: .normal)
		saveButton.tintColor = Babel2SettingsStyle.secondaryText
		saveButton.accessibilityLabel = Babel2SettingsText.t("Save")
		saveButton.accessibilityIdentifier = "babel2.settings.save"
		saveButton.isHidden = kind != .editor

		titleLabel.text = title
		titleLabel.font = Babel2SettingsStyle.navigationTitleFont
		titleLabel.textColor = Babel2SettingsStyle.primaryText
		titleLabel.accessibilityTraits = .header
		titleLabel.accessibilityIdentifier = "babel2.settings.title"
		titleLabel.lineBreakMode = .byTruncatingTail

		let hairline = UIView()
		hairline.backgroundColor = Babel2SettingsStyle.hairline

		for view in [leadingButton, saveButton, titleLabel, hairline] {
			view.translatesAutoresizingMaskIntoConstraints = false
			addSubview(view)
		}
		NSLayoutConstraint.activate([
			heightAnchor.constraint(equalToConstant: Babel2SettingsStyle.navigationHeight),
			leadingButton.centerXAnchor.constraint(equalTo: leadingAnchor, constant: 32),
			leadingButton.centerYAnchor.constraint(equalTo: topAnchor, constant: 22),
			leadingButton.widthAnchor.constraint(equalToConstant: 44),
			leadingButton.heightAnchor.constraint(equalToConstant: 44),
			saveButton.centerXAnchor.constraint(equalTo: trailingAnchor, constant: -32),
			saveButton.centerYAnchor.constraint(equalTo: topAnchor, constant: 22),
			saveButton.widthAnchor.constraint(equalToConstant: 44),
			saveButton.heightAnchor.constraint(equalToConstant: 44),
			titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 58),
			titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: kind == .editor ? -58 : -20),
			titleLabel.centerYAnchor.constraint(equalTo: topAnchor, constant: 22.5),
			hairline.leadingAnchor.constraint(equalTo: leadingAnchor),
			hairline.trailingAnchor.constraint(equalTo: trailingAnchor),
			hairline.bottomAnchor.constraint(equalTo: bottomAnchor),
			hairline.heightAnchor.constraint(equalToConstant: 0.5)
		])
	}

	required init?(coder: NSCoder) { nil }
}

// MARK: - 分组标题

/// Figma「Settings Section Header」：28pt，11pt 半粗次要灰，文字顶部 8pt。
final class Babel2SettingsSectionHeader: UIView {
	init(title: String) {
		super.init(frame: .zero)
		let label = UILabel()
		label.text = title
		label.font = Babel2SettingsStyle.sectionHeaderFont
		label.textColor = Babel2SettingsStyle.secondaryText
		label.accessibilityTraits = .header
		label.translatesAutoresizingMaskIntoConstraints = false
		addSubview(label)
		NSLayoutConstraint.activate([
			heightAnchor.constraint(equalToConstant: Babel2SettingsStyle.sectionHeaderHeight),
			label.leadingAnchor.constraint(equalTo: leadingAnchor),
			label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
			label.topAnchor.constraint(equalTo: topAnchor, constant: 8)
		])
	}

	required init?(coder: NSCoder) { nil }
}

// MARK: - 行

/// 所有可点的设置行的基类：整行可点，按下时稍微变暗。
class Babel2SettingsRowControl: UIControl {
	var onTap: (() -> Void)?

	override init(frame: CGRect) {
		super.init(frame: frame)
		isAccessibilityElement = true
		accessibilityTraits = .button
		addTarget(self, action: #selector(tapped), for: .touchUpInside)
	}

	required init?(coder: NSCoder) { nil }

	@objc private func tapped() { onTap?() }

	override var isHighlighted: Bool {
		didSet { alpha = isHighlighted ? 0.55 : 1 }
	}
}

/// 右侧的小图标（箭头 / 下箭头 / 勾），统一次要灰。
private func settingsGlyph(_ name: String, side: CGFloat) -> UIImageView {
	let view = UIImageView(image: UIImage(named: name))
	view.tintColor = Babel2SettingsStyle.secondaryText
	view.contentMode = .scaleAspectFit
	view.translatesAutoresizingMaskIntoConstraints = false
	NSLayoutConstraint.activate([
		view.widthAnchor.constraint(equalToConstant: side),
		view.heightAnchor.constraint(equalToConstant: side)
	])
	return view
}

/// Figma「Settings Row / Disclosure」：56pt 两行（标题 16 半粗 + 说明 11 常规），右侧 18pt 箭头，点击进入下一页。
/// 设置首页的类别行在左侧另有 38pt 宽的图标位（图标与文字间距 6）。
final class Babel2SettingsDisclosureRow: Babel2SettingsRowControl {
	let titleLabel = UILabel()
	let detailLabel = UILabel()

	init(title: String, detail: String?, icon: UIImage? = nil, iconSide: CGFloat = 24) {
		super.init(frame: .zero)
		titleLabel.text = title
		titleLabel.font = Babel2SettingsStyle.disclosureTitleFont
		titleLabel.textColor = Babel2SettingsStyle.primaryText
		detailLabel.text = detail
		detailLabel.font = Babel2SettingsStyle.disclosureDetailFont
		detailLabel.textColor = Babel2SettingsStyle.secondaryText
		detailLabel.isHidden = (detail ?? "").isEmpty
		let labels = UIStackView(arrangedSubviews: [titleLabel, detailLabel])
		labels.axis = .vertical
		labels.spacing = 2
		labels.isUserInteractionEnabled = false
		labels.translatesAutoresizingMaskIntoConstraints = false
		let chevron = settingsGlyph("Babel2SettingsChevron", side: 18)
		addSubview(labels)
		addSubview(chevron)

		var textLeading: CGFloat = 0
		if let icon {
			let iconView = UIImageView(image: icon)
			iconView.tintColor = Babel2SettingsStyle.secondaryText
			iconView.contentMode = .scaleAspectFit
			iconView.translatesAutoresizingMaskIntoConstraints = false
			addSubview(iconView)
			NSLayoutConstraint.activate([
				iconView.centerXAnchor.constraint(equalTo: leadingAnchor, constant: 19),
				iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
				iconView.widthAnchor.constraint(equalToConstant: iconSide),
				iconView.heightAnchor.constraint(equalToConstant: iconSide)
			])
			textLeading = 44
		}
		NSLayoutConstraint.activate([
			heightAnchor.constraint(equalToConstant: Babel2SettingsStyle.disclosureRowHeight),
			labels.leadingAnchor.constraint(equalTo: leadingAnchor, constant: textLeading),
			labels.trailingAnchor.constraint(lessThanOrEqualTo: chevron.leadingAnchor, constant: -8),
			labels.centerYAnchor.constraint(equalTo: centerYAnchor),
			chevron.trailingAnchor.constraint(equalTo: trailingAnchor),
			chevron.centerYAnchor.constraint(equalTo: centerYAnchor)
		])
		accessibilityLabel = [title, detail].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
	}

	required init?(coder: NSCoder) { nil }
}

/// Figma「Settings Row / Value」：48pt，标题 16 常规，右侧当前值（13 次要灰）+ 18pt 箭头，点击进入下一页。
final class Babel2SettingsValueRow: Babel2SettingsRowControl {
	let titleLabel = UILabel()
	let valueLabel = UILabel()

	init(title: String, value: String?) {
		super.init(frame: .zero)
		titleLabel.text = title
		titleLabel.font = Babel2SettingsStyle.rowTitleFont
		titleLabel.textColor = Babel2SettingsStyle.primaryText
		valueLabel.font = Babel2SettingsStyle.valueFont
		valueLabel.textColor = Babel2SettingsStyle.secondaryText
		valueLabel.textAlignment = .right
		valueLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
		let chevron = settingsGlyph("Babel2SettingsChevron", side: 18)
		for view in [titleLabel, valueLabel] as [UIView] {
			view.translatesAutoresizingMaskIntoConstraints = false
			addSubview(view)
		}
		addSubview(chevron)
		NSLayoutConstraint.activate([
			heightAnchor.constraint(equalToConstant: Babel2SettingsStyle.rowHeight),
			titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
			titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
			valueLabel.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 12),
			valueLabel.trailingAnchor.constraint(equalTo: chevron.leadingAnchor, constant: -6),
			valueLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
			chevron.trailingAnchor.constraint(equalTo: trailingAnchor),
			chevron.centerYAnchor.constraint(equalTo: centerYAnchor)
		])
		setValue(value)
	}

	required init?(coder: NSCoder) { nil }

	func setValue(_ value: String?) {
		valueLabel.text = value
		accessibilityLabel = titleLabel.text
		accessibilityValue = value
	}
}

/// Figma「Settings Select Row」：48pt，标题 16 常规，右侧当前值（15 次要灰）+ 16pt 下箭头。
/// 点击在本页弹出单选菜单，选完立即生效、菜单关闭；绝不进入子页面。
final class Babel2SettingsSelectRow: Babel2SettingsRowControl {
	let titleLabel = UILabel()
	let valueLabel = UILabel()

	init(title: String, value: String?) {
		super.init(frame: .zero)
		titleLabel.text = title
		titleLabel.font = Babel2SettingsStyle.rowTitleFont
		titleLabel.textColor = Babel2SettingsStyle.primaryText
		valueLabel.font = Babel2SettingsStyle.selectValueFont
		valueLabel.textColor = Babel2SettingsStyle.secondaryText
		valueLabel.textAlignment = .right
		valueLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
		let chevron = settingsGlyph("Babel2SettingsChevronDown", side: 16)
		for view in [titleLabel, valueLabel] as [UIView] {
			view.translatesAutoresizingMaskIntoConstraints = false
			addSubview(view)
		}
		addSubview(chevron)
		NSLayoutConstraint.activate([
			heightAnchor.constraint(equalToConstant: Babel2SettingsStyle.rowHeight),
			titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
			titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
			valueLabel.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 8),
			valueLabel.trailingAnchor.constraint(equalTo: chevron.leadingAnchor, constant: -4),
			valueLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
			chevron.trailingAnchor.constraint(equalTo: trailingAnchor),
			chevron.centerYAnchor.constraint(equalTo: centerYAnchor)
		])
		setValue(value)
	}

	required init?(coder: NSCoder) { nil }

	func setValue(_ value: String?) {
		valueLabel.text = value
		accessibilityLabel = titleLabel.text
		accessibilityValue = value
	}
}

/// Figma「Settings Row / Toggle」：48pt，标题 16 常规，右侧 38×22 开关（点击区 44pt）。改了立即生效。
final class Babel2SettingsToggleRow: UIView {
	let titleLabel = UILabel()
	let toggle = Babel2SettingsSwitch()

	init(title: String, isOn: Bool, onChange: @escaping (Bool) -> Void) {
		super.init(frame: .zero)
		titleLabel.text = title
		titleLabel.font = Babel2SettingsStyle.rowTitleFont
		titleLabel.textColor = Babel2SettingsStyle.primaryText
		titleLabel.numberOfLines = 1
		titleLabel.adjustsFontSizeToFitWidth = true
		titleLabel.minimumScaleFactor = 0.8
		toggle.isOn = isOn
		toggle.accessibilityLabel = title
		toggle.onChange = onChange
		for view in [titleLabel, toggle] as [UIView] {
			view.translatesAutoresizingMaskIntoConstraints = false
			addSubview(view)
		}
		NSLayoutConstraint.activate([
			heightAnchor.constraint(equalToConstant: Babel2SettingsStyle.rowHeight),
			titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
			titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: toggle.leadingAnchor, constant: -12),
			titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
			toggle.trailingAnchor.constraint(equalTo: trailingAnchor, constant: 3),
			toggle.centerYAnchor.constraint(equalTo: centerYAnchor)
		])
	}

	required init?(coder: NSCoder) { nil }
}

/// Figma「Settings Row / Action」：48pt，只有一行标题（16 常规），一点就执行，不进新页面；危险操作用红色。
final class Babel2SettingsActionRow: Babel2SettingsRowControl {
	let titleLabel = UILabel()

	init(title: String, destructive: Bool = false) {
		super.init(frame: .zero)
		titleLabel.text = title
		titleLabel.font = Babel2SettingsStyle.rowTitleFont
		titleLabel.textColor = destructive ? Babel2SettingsStyle.destructive : Babel2SettingsStyle.primaryText
		titleLabel.translatesAutoresizingMaskIntoConstraints = false
		addSubview(titleLabel)
		NSLayoutConstraint.activate([
			heightAnchor.constraint(equalToConstant: Babel2SettingsStyle.rowHeight),
			titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
			titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
			titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
		])
		accessibilityLabel = title
	}

	required init?(coder: NSCoder) { nil }
}

/// Figma「Settings Choice Row」：48pt，标题 16 常规，选中时右侧 20pt 勾（未选中也占位、透明）。
/// 翻译模型页的行左侧可再放 20pt 服务商 logo（文字从 x=28 开始）。
final class Babel2SettingsChoiceRow: Babel2SettingsRowControl {
	let titleLabel = UILabel()
	private let check = settingsGlyph("Babel2SettingsCheck", side: 20)

	init(title: String, isSelected: Bool, logo: UIImage? = nil) {
		super.init(frame: .zero)
		titleLabel.text = title
		titleLabel.font = Babel2SettingsStyle.rowTitleFont
		titleLabel.textColor = Babel2SettingsStyle.primaryText
		titleLabel.lineBreakMode = .byTruncatingTail
		titleLabel.translatesAutoresizingMaskIntoConstraints = false
		addSubview(titleLabel)
		addSubview(check)
		var textLeading: CGFloat = 0
		if let logo {
			let logoView = UIImageView(image: logo)
			logoView.contentMode = .scaleAspectFit
			logoView.layer.cornerRadius = 4
			logoView.clipsToBounds = true
			logoView.translatesAutoresizingMaskIntoConstraints = false
			addSubview(logoView)
			NSLayoutConstraint.activate([
				logoView.leadingAnchor.constraint(equalTo: leadingAnchor),
				logoView.centerYAnchor.constraint(equalTo: centerYAnchor),
				logoView.widthAnchor.constraint(equalToConstant: 20),
				logoView.heightAnchor.constraint(equalToConstant: 20)
			])
			textLeading = 28
		}
		NSLayoutConstraint.activate([
			heightAnchor.constraint(equalToConstant: Babel2SettingsStyle.rowHeight),
			titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: textLeading),
			titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: check.leadingAnchor, constant: -8),
			titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
			check.trailingAnchor.constraint(equalTo: trailingAnchor),
			check.centerYAnchor.constraint(equalTo: centerYAnchor)
		])
		accessibilityLabel = title
		setSelected(isSelected)
	}

	required init?(coder: NSCoder) { nil }

	func setSelected(_ selected: Bool) {
		isSelected = selected
		check.alpha = selected ? 1 : 0
		accessibilityTraits = selected ? [.button, .selected] : .button
	}
}

/// 说明文字（Figma 通知页 / 翻译 API 页的灰色小字）。
final class Babel2SettingsNoteLabel: UILabel {
	init(text: String, size: CGFloat = 13) {
		super.init(frame: .zero)
		self.text = text
		font = .systemFont(ofSize: size, weight: .regular)
		textColor = Babel2SettingsStyle.secondaryText
		numberOfLines = 0
	}

	required init?(coder: NSCoder) { nil }
}

// MARK: - 文本框

/// Figma「Settings Text Field」：68pt，输入底色、0.5pt 细线描边、圆角 8；
/// 上方小标签 11 半粗次要灰（11.5, 8.5），下方输入 15 常规主色（11.5, 33.5）。Secure 模式遮住内容。
final class Babel2SettingsTextField: UIView, UITextFieldDelegate {
	let textField = UITextField()

	init(label: String, text: String?, placeholder: String? = nil, secure: Bool, keyboard: UIKeyboardType = .default, identifier: String) {
		super.init(frame: .zero)
		backgroundColor = Babel2SettingsStyle.inputBackground
		layer.cornerRadius = 8
		layer.cornerCurve = .continuous
		layer.borderWidth = 0.5
		layer.borderColor = Babel2SettingsStyle.hairline.resolvedColor(with: traitCollection).cgColor

		let caption = UILabel()
		caption.text = label
		caption.font = Babel2SettingsStyle.sectionHeaderFont
		caption.textColor = Babel2SettingsStyle.secondaryText
		textField.text = text
		textField.placeholder = placeholder
		textField.font = .systemFont(ofSize: 15, weight: .regular)
		textField.textColor = Babel2SettingsStyle.primaryText
		textField.isSecureTextEntry = secure
		textField.keyboardType = keyboard
		textField.autocapitalizationType = .none
		textField.autocorrectionType = .no
		textField.spellCheckingType = .no
		textField.clearButtonMode = .whileEditing
		textField.returnKeyType = .done
		textField.accessibilityLabel = label
		textField.accessibilityIdentifier = identifier
		textField.delegate = self
		for view in [caption, textField] as [UIView] {
			view.translatesAutoresizingMaskIntoConstraints = false
			addSubview(view)
		}
		NSLayoutConstraint.activate([
			heightAnchor.constraint(equalToConstant: Babel2SettingsStyle.textFieldHeight),
			caption.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 11.5),
			caption.topAnchor.constraint(equalTo: topAnchor, constant: 8.5),
			textField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 11.5),
			textField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
			textField.topAnchor.constraint(equalTo: topAnchor, constant: 30),
			textField.heightAnchor.constraint(equalToConstant: 26)
		])
		registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: Babel2SettingsTextField, _) in
			view.layer.borderColor = Babel2SettingsStyle.hairline.resolvedColor(with: view.traitCollection).cgColor
		}
	}

	required init?(coder: NSCoder) { nil }

	var text: String { (textField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }

	func textFieldShouldReturn(_ textField: UITextField) -> Bool {
		textField.resignFirstResponder()
		return true
	}
}

// MARK: - 开关

/// Figma 开关：可见 38×22、圆角 11，圆钮半径 9；点击区 44pt。
/// 开 = 强调色（ADR-008），关 = color/background/selection；圆钮为纸色。改了立即回调。
final class Babel2SettingsSwitch: UIControl {
	var onChange: ((Bool) -> Void)?
	var isOn = false {
		didSet { updateAppearance(animated: window != nil) }
	}

	private let track = UIView()
	private let knob = UIView()
	private var knobCenter: NSLayoutConstraint!

	override init(frame: CGRect) {
		super.init(frame: frame)
		isAccessibilityElement = true
		accessibilityTraits = .button
		track.isUserInteractionEnabled = false
		track.layer.cornerRadius = 11
		knob.isUserInteractionEnabled = false
		knob.layer.cornerRadius = 9
		knob.backgroundColor = BabelPalette.background
		for view in [track, knob] {
			view.translatesAutoresizingMaskIntoConstraints = false
		}
		addSubview(track)
		track.addSubview(knob)
		knobCenter = knob.centerXAnchor.constraint(equalTo: track.leadingAnchor, constant: 11)
		NSLayoutConstraint.activate([
			widthAnchor.constraint(equalToConstant: 44),
			heightAnchor.constraint(equalToConstant: 44),
			track.centerXAnchor.constraint(equalTo: centerXAnchor),
			track.centerYAnchor.constraint(equalTo: centerYAnchor),
			track.widthAnchor.constraint(equalToConstant: 38),
			track.heightAnchor.constraint(equalToConstant: 22),
			knob.centerYAnchor.constraint(equalTo: track.centerYAnchor),
			knob.widthAnchor.constraint(equalToConstant: 18),
			knob.heightAnchor.constraint(equalToConstant: 18),
			knobCenter
		])
		addTarget(self, action: #selector(tapped), for: .touchUpInside)
		updateAppearance(animated: false)
	}

	required init?(coder: NSCoder) { nil }

	@objc private func tapped() {
		isOn.toggle()
		onChange?(isOn)
		sendActions(for: .valueChanged)
	}

	/// 仅供自动化测试：模拟一次点按。
	func toggleForTesting() { tapped() }

	private func updateAppearance(animated: Bool) {
		knobCenter.constant = isOn ? 27 : 11
		accessibilityValue = isOn ? "1" : "0"
		let apply = {
			self.track.backgroundColor = self.isOn ? Babel2SettingsStyle.switchOnTrack : Babel2SettingsStyle.switchOffTrack
			self.layoutIfNeeded()
		}
		if animated {
			UIView.animate(withDuration: 0.18, delay: 0, options: [.curveEaseOut, .beginFromCurrentState], animations: apply)
		} else {
			apply()
		}
	}
}

// MARK: - 弹出单选菜单

/// Figma「Babel/Popover/Thick Glass」：宽 272、内边距 6、圆角 22、0.5pt 细线，两层投影 + 背景模糊；
/// 每个选项 48pt（左右 14，18pt 勾位与文字间距 10，文字 16 常规）；未选中的勾位透明占位。
/// 右边与内容区右边对齐；顶边在触发行下沿往下 39pt（Figma），放不下时改到上方。选中立即生效并关闭；点空白处关闭。
final class Babel2SettingsPopover: UIView {
	struct Option {
		let title: String
		let isSelected: Bool
		/// 强调色菜单的 10pt 圆形色块（勾位与文字之间，间距 8）。
		var swatch: UIColor?
	}

	static let width: CGFloat = 272
	private let onSelect: (Int) -> Void
	private let card = UIView()
	/// 仅供自动化测试：选项行（按顺序）。
	private(set) var optionControlsForTesting = [UIControl]()

	/// 在 host 的整个 view 上盖一层透明遮罩，把菜单锚定在 anchor 旁边。
	@discardableResult
	static func present(options: [Option], from anchor: UIView, in host: UIView, onSelect: @escaping (Int) -> Void) -> Babel2SettingsPopover {
		let popover = Babel2SettingsPopover(options: options, onSelect: onSelect)
		popover.frame = host.bounds
		popover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
		host.addSubview(popover)
		popover.place(anchoredTo: anchor)
		popover.card.alpha = 0
		popover.card.transform = CGAffineTransform(scaleX: 0.96, y: 0.96)
		UIView.animate(withDuration: 0.18, delay: 0, options: [.curveEaseOut]) {
			popover.card.alpha = 1
			popover.card.transform = .identity
		}
		UIAccessibility.post(notification: .screenChanged, argument: popover.optionControlsForTesting.first)
		return popover
	}

	private init(options: [Option], onSelect: @escaping (Int) -> Void) {
		self.onSelect = onSelect
		super.init(frame: .zero)
		backgroundColor = .clear
		accessibilityIdentifier = "babel2.settings.popover"
		accessibilityViewIsModal = true

		let dismissTap = UITapGestureRecognizer(target: self, action: #selector(dismissTapped))
		dismissTap.cancelsTouchesInView = false
		addGestureRecognizer(dismissTap)

		card.layer.cornerRadius = 22
		card.layer.cornerCurve = .continuous
		card.layer.borderWidth = 0.5
		card.layer.shadowColor = UIColor.black.cgColor
		card.layer.shadowOpacity = 0.15
		card.layer.shadowRadius = 14
		card.layer.shadowOffset = CGSize(width: 0, height: 10)
		let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemThickMaterial))
		blur.layer.cornerRadius = 22
		blur.layer.cornerCurve = .continuous
		blur.clipsToBounds = true
		blur.translatesAutoresizingMaskIntoConstraints = false
		let tint = UIView()
		tint.backgroundColor = Babel2SettingsStyle.elevatedBackground
		tint.translatesAutoresizingMaskIntoConstraints = false
		blur.contentView.addSubview(tint)
		card.addSubview(blur)

		let stack = UIStackView()
		stack.axis = .vertical
		stack.translatesAutoresizingMaskIntoConstraints = false
		card.addSubview(stack)
		for (index, option) in options.enumerated() {
			let row = Babel2SettingsPopoverOptionRow(option: option)
			row.tag = index
			row.accessibilityIdentifier = "babel2.settings.popover.option.\(index)"
			row.addTarget(self, action: #selector(optionTapped(_:)), for: .touchUpInside)
			stack.addArrangedSubview(row)
			optionControlsForTesting.append(row)
		}
		addSubview(card)
		NSLayoutConstraint.activate([
			blur.leadingAnchor.constraint(equalTo: card.leadingAnchor),
			blur.trailingAnchor.constraint(equalTo: card.trailingAnchor),
			blur.topAnchor.constraint(equalTo: card.topAnchor),
			blur.bottomAnchor.constraint(equalTo: card.bottomAnchor),
			tint.leadingAnchor.constraint(equalTo: blur.contentView.leadingAnchor),
			tint.trailingAnchor.constraint(equalTo: blur.contentView.trailingAnchor),
			tint.topAnchor.constraint(equalTo: blur.contentView.topAnchor),
			tint.bottomAnchor.constraint(equalTo: blur.contentView.bottomAnchor),
			stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 6),
			stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -6),
			stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 6),
			stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -6)
		])
		updateBorder()
		registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: Babel2SettingsPopover, _) in
			view.updateBorder()
		}
	}

	required init?(coder: NSCoder) { nil }

	private func updateBorder() {
		card.layer.borderColor = Babel2SettingsStyle.hairline.resolvedColor(with: traitCollection).cgColor
	}

	/// 右边对齐内容区右边（屏宽 − 20）；按 Figma 03A/03B/06A–C 一致的画法，顶边在触发行下沿再往下 39pt；
	/// 放不下时放到触发行上方。
	private func place(anchoredTo anchor: UIView) {
		let height = 12 + 48 * CGFloat(optionControlsForTesting.count)
		let anchorFrame = anchor.convert(anchor.bounds, to: self)
		let x = bounds.width - Babel2SettingsStyle.sideInset - Self.width
		var y = anchorFrame.maxY + 39
		let bottomLimit = bounds.height - safeAreaInsets.bottom - 12
		if y + height > bottomLimit {
			y = max(safeAreaInsets.top + 12, anchorFrame.minY - 8 - height)
		}
		card.frame = CGRect(x: x, y: y, width: Self.width, height: height)
	}

	/// 仅供自动化测试：菜单卡片在遮罩里的位置。
	var cardFrameForTesting: CGRect { card.frame }

	@objc private func optionTapped(_ sender: UIControl) {
		let index = sender.tag
		dismiss { self.onSelect(index) }
	}

	@objc private func dismissTapped(_ gesture: UITapGestureRecognizer) {
		guard !card.frame.contains(gesture.location(in: self)) else { return }
		dismiss(completion: nil)
	}

	/// 仅供自动化测试：选中第 index 项（与点按同一路径，但不等动画）。
	func selectForTesting(_ index: Int) {
		removeFromSuperview()
		onSelect(index)
	}

	func dismiss(completion: (() -> Void)?) {
		// 先生效、再淡出：值立刻更新，菜单随后消失
		completion?()
		UIView.animate(withDuration: 0.14, animations: {
			self.card.alpha = 0
		}, completion: { _ in
			self.removeFromSuperview()
		})
	}
}

/// 弹出菜单里的一个选项：48pt，左右 14，18pt 勾位（未选中透明占位）→（可选 10pt 色块）→ 文字 16 常规。
private final class Babel2SettingsPopoverOptionRow: UIControl {
	init(option: Babel2SettingsPopover.Option) {
		super.init(frame: .zero)
		isAccessibilityElement = true
		accessibilityLabel = option.title
		accessibilityTraits = option.isSelected ? [.button, .selected] : .button
		let check = settingsGlyph("Babel2SettingsCheck", side: 18)
		check.alpha = option.isSelected ? 1 : 0
		let label = UILabel()
		label.text = option.title
		label.font = .systemFont(ofSize: 16, weight: .regular)
		label.textColor = Babel2SettingsStyle.primaryText
		label.translatesAutoresizingMaskIntoConstraints = false
		addSubview(check)
		addSubview(label)
		var constraints = [
			heightAnchor.constraint(equalToConstant: 48),
			check.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
			check.centerYAnchor.constraint(equalTo: centerYAnchor),
			label.centerYAnchor.constraint(equalTo: centerYAnchor),
			label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -14)
		]
		if let swatch = option.swatch {
			let dot = UIView()
			dot.backgroundColor = swatch
			dot.layer.cornerRadius = 5
			dot.isUserInteractionEnabled = false
			dot.translatesAutoresizingMaskIntoConstraints = false
			addSubview(dot)
			constraints += [
				dot.leadingAnchor.constraint(equalTo: check.trailingAnchor, constant: 8),
				dot.centerYAnchor.constraint(equalTo: centerYAnchor),
				dot.widthAnchor.constraint(equalToConstant: 10),
				dot.heightAnchor.constraint(equalToConstant: 10),
				label.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 8)
			]
		} else {
			constraints.append(label.leadingAnchor.constraint(equalTo: check.trailingAnchor, constant: 10))
		}
		NSLayoutConstraint.activate(constraints)
	}

	required init?(coder: NSCoder) { nil }

	override var isHighlighted: Bool {
		didSet { backgroundColor = isHighlighted ? Babel2SettingsStyle.hairline.withAlphaComponent(0.5) : .clear }
	}
}
