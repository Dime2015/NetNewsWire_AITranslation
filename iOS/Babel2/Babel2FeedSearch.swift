import UIKit

/// 文章列表搜索框（2026-09-25，交互合同「Feed Search：在当前源原地进入搜索、取消恢复原列表与滚动位置」）。
/// Figma 只有搜索按钮、没有搜索界面的设计稿：样式按设置页输入框近似（输入底色、圆角、放大镜），用户已同意。
/// 放在收缩后窄栏的第二行（原「小图标 + 名字」的位置）：搜索框 + 右侧「取消」。
final class Babel2FeedSearchField: UIView, UITextFieldDelegate {
	let textField = UITextField()
	let cancelButton = UIButton(type: .system)
	/// 文字变了（每次按键）；由列表页做防抖。
	var onChange: ((String) -> Void)?
	var onCancel: (() -> Void)?

	init(placeholder: String, cancelTitle: String) {
		super.init(frame: .zero)
		let box = UIView()
		box.backgroundColor = Babel2SettingsStyle.inputBackground
		box.layer.cornerRadius = 10
		box.layer.cornerCurve = .continuous
		box.translatesAutoresizingMaskIntoConstraints = false

		let glass = UIImageView(image: UIImage(systemName: "magnifyingglass", withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)))
		glass.tintColor = BabelPalette.mutedInk
		// 固定 16×16、按原比例显示（2026-09-25 用户截图：未定尺寸时被输入框横向拉长变形）
		glass.contentMode = .scaleAspectFit
		glass.setContentHuggingPriority(.required, for: .horizontal)
		glass.setContentCompressionResistancePriority(.required, for: .horizontal)
		glass.translatesAutoresizingMaskIntoConstraints = false

		textField.placeholder = placeholder
		textField.font = .systemFont(ofSize: 16, weight: .regular)
		textField.textColor = BabelPalette.ink
		textField.returnKeyType = .search
		// 框里有字时 × 一直显示（不只在输入时），收起键盘后也能一键清空
		textField.clearButtonMode = .always
		textField.autocorrectionType = .no
		textField.autocapitalizationType = .none
		textField.enablesReturnKeyAutomatically = false
		textField.accessibilityIdentifier = "babel2.feed.search.field"
		textField.delegate = self
		textField.addTarget(self, action: #selector(textChanged), for: .editingChanged)
		textField.translatesAutoresizingMaskIntoConstraints = false

		cancelButton.setTitle(cancelTitle, for: .normal)
		cancelButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .regular)
		cancelButton.tintColor = BabelPalette.ink
		cancelButton.accessibilityIdentifier = "babel2.feed.search.cancel"
		cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
		cancelButton.setContentHuggingPriority(.required, for: .horizontal)
		cancelButton.setContentCompressionResistancePriority(.required, for: .horizontal)
		cancelButton.translatesAutoresizingMaskIntoConstraints = false

		addSubview(box)
		box.addSubview(glass)
		box.addSubview(textField)
		addSubview(cancelButton)
		NSLayoutConstraint.activate([
			box.leadingAnchor.constraint(equalTo: leadingAnchor),
			box.centerYAnchor.constraint(equalTo: centerYAnchor),
			box.heightAnchor.constraint(equalToConstant: 36),
			box.trailingAnchor.constraint(equalTo: cancelButton.leadingAnchor, constant: -12),
			glass.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 10),
			glass.centerYAnchor.constraint(equalTo: box.centerYAnchor),
			glass.widthAnchor.constraint(equalToConstant: 16),
			glass.heightAnchor.constraint(equalToConstant: 16),
			textField.leadingAnchor.constraint(equalTo: glass.trailingAnchor, constant: 6),
			textField.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -6),
			textField.topAnchor.constraint(equalTo: box.topAnchor),
			textField.bottomAnchor.constraint(equalTo: box.bottomAnchor),
			cancelButton.trailingAnchor.constraint(equalTo: trailingAnchor),
			cancelButton.centerYAnchor.constraint(equalTo: centerYAnchor),
			cancelButton.heightAnchor.constraint(equalToConstant: 44)
		])
	}

	required init?(coder: NSCoder) { nil }

	var query: String { textField.text ?? "" }

	func clear() {
		textField.text = nil
	}

	@objc private func textChanged() { onChange?(query) }

	@objc private func cancelTapped() { onCancel?() }

	/// 按键盘上的「搜索」：收起键盘，保留结果。
	func textFieldShouldReturn(_ textField: UITextField) -> Bool {
		textField.resignFirstResponder()
		return true
	}
}
