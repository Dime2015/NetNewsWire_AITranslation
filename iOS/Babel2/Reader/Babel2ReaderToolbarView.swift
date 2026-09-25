import UIKit

/// 阅读页底栏：按 Figma「Reader Toolbar」(21:5) 对齐（ADR-018）。
///
/// - 72pt 高、贴屏幕最底（含 Home 指示条区域），顶部 0.5pt 分隔线
/// - 四个 24pt 设计稿图标：已读 / 星标 / 下一篇 / 阅读模式，中心 x = 32 / 104 / 201 / 290.5，中心 y = 24
/// - 右侧 58×44 的「原 / 译」文字开关（Babel2TranslationToggle），中心 x = 362
/// - 图标颜色为设计稿的次要灰（BabelPalette.mutedInk = #787878）
/// 已接通：已读、星标、翻译；「下一篇」「阅读模式」仍是占位（灰色不可点）。
/// （按 ADR-016，后续第 4 格改为「长图」，阅读模式移入顶栏「更多」菜单。）
@MainActor
final class Babel2ReaderToolbarView: UIView {
	static let height: CGFloat = 72
	private static let slotCenters: [CGFloat] = [32, 104, 201, 290.5, 362]
	private static let referenceWidth: CGFloat = 402

	let readButton: UIButton
	let starButton: UIButton
	let translationToggle = Babel2TranslationToggle()
	let placeholderButtons: [UIButton]
	var onToggleRead: (() -> Void)?
	var onToggleStar: (() -> Void)?
	var onTranslate: (() -> Void)?

	private(set) var isRead = false
	private(set) var isStarred = false
	/// 仅供自动化测试：当前已读 / 星标按钮用的资源名。
	private(set) var readIconName = ""
	private(set) var starIconName = ""
	var translationState: TranslationButtonState { translationToggle.translationState }

	override init(frame: CGRect) {
		readButton = Self.makeButton(identifier: "babel2.article.toolbar.read")
		starButton = Self.makeButton(identifier: "babel2.article.toolbar.star")
		let next = Self.makeButton(identifier: "babel2.article.toolbar.next")
		let readingMode = Self.makeButton(identifier: "babel2.article.toolbar.reading-mode")
		placeholderButtons = [next, readingMode]
		super.init(frame: frame)
		backgroundColor = BabelPalette.background
		accessibilityIdentifier = "babel2.article.toolbar"

		Self.setIcon("Babel2ReaderNext", on: next)
		next.accessibilityLabel = Babel2Localization.text(.nextArticle)
		Self.setIcon("BabelReaderReadingMode", on: readingMode)
		readingMode.accessibilityLabel = Babel2Localization.text(.readingMode)
		placeholderButtons.forEach { $0.isEnabled = false }

		readButton.addTarget(self, action: #selector(readTapped), for: .touchUpInside)
		starButton.addTarget(self, action: #selector(starTapped), for: .touchUpInside)
		translationToggle.addTarget(self, action: #selector(translateTapped), for: .touchUpInside)
		translationToggle.translatesAutoresizingMaskIntoConstraints = false

		let separator = UIView()
		separator.backgroundColor = BabelPalette.hairline
		separator.translatesAutoresizingMaskIntoConstraints = false
		addSubview(separator)
		NSLayoutConstraint.activate([
			separator.leadingAnchor.constraint(equalTo: leadingAnchor),
			separator.trailingAnchor.constraint(equalTo: trailingAnchor),
			separator.topAnchor.constraint(equalTo: topAnchor),
			separator.heightAnchor.constraint(equalToConstant: 0.5)
		])

		// 按参考画布比例定位，屏幕宽度不同也保持相对位置
		let controls: [UIView] = [readButton, starButton] + placeholderButtons + [translationToggle]
		for (control, center) in zip(controls, Self.slotCenters) {
			addSubview(control)
			let size = control === translationToggle ? Babel2TranslationToggle.size : CGSize(width: 44, height: 44)
			NSLayoutConstraint.activate([
				NSLayoutConstraint(
					item: control, attribute: .centerX, relatedBy: .equal,
					toItem: self, attribute: .trailing,
					multiplier: center / Self.referenceWidth, constant: 0
				),
				control.centerYAnchor.constraint(equalTo: topAnchor, constant: 24),
				control.widthAnchor.constraint(equalToConstant: size.width),
				control.heightAnchor.constraint(equalToConstant: size.height)
			])
		}
		setRead(false)
		setStarred(false)
		setTranslationState(.original)
		setTranslationAvailable(false)
	}

	required init?(coder: NSCoder) { nil }

	/// 已读 = 实心圆，未读 = 空心圈（用户 2026-09-25 决定）；无障碍说明描述「点了会怎样」。
	func setRead(_ read: Bool) {
		isRead = read
		readIconName = read ? "Babel2ReaderReadStateFilled" : "Babel2ReaderReadState"
		Self.setIcon(readIconName, on: readButton)
		readButton.accessibilityLabel = Babel2Localization.text(read ? .markUnread : .markRead)
		readButton.accessibilityValue = read ? "read" : "unread"
	}

	func setStarred(_ starred: Bool) {
		isStarred = starred
		starIconName = starred ? "Babel2ReaderStarFilled" : "Babel2ReaderStar"
		Self.setIcon(starIconName, on: starButton)
		starButton.accessibilityLabel = Babel2Localization.text(starred ? .unstar : .star)
		starButton.accessibilityValue = starred ? "starred" : "unstarred"
	}

	/// 页面还没准备好（正文未排版、文章对象未取回）时翻译开关不可点。
	func setTranslationAvailable(_ available: Bool) {
		translationToggle.isEnabled = available
	}

	func setTranslationState(_ state: TranslationButtonState) {
		translationToggle.setState(state)
	}

	@objc private func readTapped() { onToggleRead?() }
	@objc private func starTapped() { onToggleStar?() }
	@objc private func translateTapped() { onTranslate?() }

	private static func makeButton(identifier: String) -> UIButton {
		let button = UIButton(type: .system)
		button.tintColor = BabelPalette.mutedInk
		button.accessibilityIdentifier = identifier
		button.translatesAutoresizingMaskIntoConstraints = false
		return button
	}

	/// 设计稿图标（24pt 模板图），正常态为次要灰；不可点时用更浅的中性灰，不用主题色。
	private static func setIcon(_ name: String, on button: UIButton) {
		let image = UIImage(named: name)?.withRenderingMode(.alwaysTemplate)
		assert(image != nil, "missing reader icon asset \(name)")
		button.setImage(image, for: .normal)
		button.setImage(image?.withTintColor(BabelPalette.tertiaryInk, renderingMode: .alwaysOriginal), for: .disabled)
	}
}
