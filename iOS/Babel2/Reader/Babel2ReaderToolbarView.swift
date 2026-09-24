import UIKit

/// 阅读页底栏：72pt 高、贴屏幕最底（含 Home 指示条区域），顶上一条细分隔线。
///
/// 5 个按钮按 Figma「Reader Toolbar」：已读 / 星标 / 下一篇 / 阅读模式 / 翻译，
/// 中心位置对应 402pt 画布的 x = 32 / 104 / 201 / 290.5 / 362，垂直中心距底栏顶 24pt。
/// 第 3 步只接通「已读」「星标」；其余三个是 Slice 5 的占位，显示为灰色且不可点。
/// （「生成长图」放在哪，用户 2026-09-24 决定到 Slice 5 再定。）
@MainActor
final class Babel2ReaderToolbarView: UIView {
	static let height: CGFloat = 72
	private static let slotCenters: [CGFloat] = [32, 104, 201, 290.5, 362]
	private static let referenceWidth: CGFloat = 402

	let readButton: UIButton
	let starButton: UIButton
	let placeholderButtons: [UIButton]
	var onToggleRead: (() -> Void)?
	var onToggleStar: (() -> Void)?

	private(set) var isRead = false
	private(set) var isStarred = false

	override init(frame: CGRect) {
		readButton = Self.makeButton(identifier: "babel2.article.toolbar.read")
		starButton = Self.makeButton(identifier: "babel2.article.toolbar.star")
		let next = Self.makeButton(identifier: "babel2.article.toolbar.next")
		let readingMode = Self.makeButton(identifier: "babel2.article.toolbar.reading-mode")
		let translate = Self.makeButton(identifier: "babel2.article.toolbar.translate")
		placeholderButtons = [next, readingMode, translate]
		super.init(frame: frame)
		backgroundColor = BabelPalette.background
		accessibilityIdentifier = "babel2.article.toolbar"

		Self.setSymbol("chevron.down", on: next)
		next.accessibilityLabel = Babel2Localization.text(.nextArticle)
		Self.setSymbol("doc.text", on: readingMode)
		readingMode.accessibilityLabel = Babel2Localization.text(.readingMode)
		Self.setSymbol("translate", on: translate)
		translate.accessibilityLabel = Babel2Localization.text(.translate)
		placeholderButtons.forEach { $0.isEnabled = false }

		readButton.addTarget(self, action: #selector(readTapped), for: .touchUpInside)
		starButton.addTarget(self, action: #selector(starTapped), for: .touchUpInside)

		let separator = UIView()
		separator.backgroundColor = BabelPalette.hairline
		separator.translatesAutoresizingMaskIntoConstraints = false
		addSubview(separator)
		NSLayoutConstraint.activate([
			separator.leadingAnchor.constraint(equalTo: leadingAnchor),
			separator.trailingAnchor.constraint(equalTo: trailingAnchor),
			separator.topAnchor.constraint(equalTo: topAnchor),
			separator.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale)
		])

		// 按参考画布比例定位，屏幕宽度不同也保持相对位置
		for (button, center) in zip([readButton, starButton] + placeholderButtons, Self.slotCenters) {
			addSubview(button)
			NSLayoutConstraint.activate([
				NSLayoutConstraint(
					item: button, attribute: .centerX, relatedBy: .equal,
					toItem: self, attribute: .trailing,
					multiplier: center / Self.referenceWidth, constant: 0
				),
				button.centerYAnchor.constraint(equalTo: topAnchor, constant: 24),
				button.widthAnchor.constraint(equalToConstant: 44),
				button.heightAnchor.constraint(equalToConstant: 44)
			])
		}
		setRead(false)
		setStarred(false)
	}

	required init?(coder: NSCoder) { nil }

	/// 已读 = 空心圆，未读 = 实心圆点；按钮文字说明的是「点了会怎样」。
	func setRead(_ read: Bool) {
		isRead = read
		Self.setSymbol(read ? "circle" : "circle.fill", on: readButton)
		readButton.accessibilityLabel = Babel2Localization.text(read ? .markUnread : .markRead)
		readButton.accessibilityValue = read ? "read" : "unread"
	}

	func setStarred(_ starred: Bool) {
		isStarred = starred
		Self.setSymbol(starred ? "star.fill" : "star", on: starButton)
		starButton.accessibilityLabel = Babel2Localization.text(starred ? .unstar : .star)
		starButton.accessibilityValue = starred ? "starred" : "unstarred"
	}

	@objc private func readTapped() { onToggleRead?() }
	@objc private func starTapped() { onToggleStar?() }

	private static func makeButton(identifier: String) -> UIButton {
		let button = UIButton(type: .system)
		button.tintColor = BabelPalette.ink
		button.accessibilityIdentifier = identifier
		button.translatesAutoresizingMaskIntoConstraints = false
		return button
	}

	private static func setSymbol(_ name: String, on button: UIButton) {
		let configuration = UIImage.SymbolConfiguration(pointSize: 20, weight: .regular)
		let image = UIImage(systemName: name, withConfiguration: configuration)
		button.setImage(image, for: .normal)
		// 占位按钮的灰色：用中性浅灰，不用主题色
		button.setImage(image?.withTintColor(BabelPalette.tertiaryInk, renderingMode: .alwaysOriginal), for: .disabled)
	}
}
