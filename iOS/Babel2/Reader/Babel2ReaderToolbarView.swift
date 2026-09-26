import UIKit

/// 阅读页底栏：按 Figma「Reader Toolbar」(21:5) 对齐（ADR-018）。
///
/// - 72pt 高、贴屏幕最底（含 Home 指示条区域），顶部 0.5pt 分隔线
/// - 四个设计稿图标（ADR-033 起 21pt）：已读 / 星标 / 下一篇 / 阅读模式，中心 x = 32 / 116.5 / 201 / 285.5，中心 y = 24
///   （ADR-020：第 4 格回到 Figma 原样的「阅读模式」，长图移入顶栏 ••• 菜单）
/// - 右侧 58×44 的「原 / 译」文字开关（Babel2TranslationToggle），中心 x = 370
/// - 图标颜色为设计稿的次要灰（BabelPalette.mutedInk = #787878）
/// 全部接通：已读、星标、下一篇（没有下一篇时变灰）、阅读模式、翻译。
@MainActor
final class Babel2ReaderToolbarView: UIView {
	static let height: CGFloat = 72
	private static let slotCenters = Babel2BarLayout.slots

	let readButton: UIButton
	let starButton: UIButton
	let readingModeButton: UIButton
	let nextButton: UIButton
	let translationToggle = Babel2TranslationToggle()
	let placeholderButtons: [UIButton]
	var onToggleRead: (() -> Void)?
	var onToggleStar: (() -> Void)?
	var onTranslate: (() -> Void)?
	var onToggleReaderMode: (() -> Void)?
	var onNext: (() -> Void)?

	private(set) var isRead = false
	private(set) var isStarred = false
	/// 仅供自动化测试：当前已读 / 星标按钮用的资源名。
	private(set) var readIconName = ""
	private(set) var starIconName = ""
	/// 每个按钮当前显示的图标名（换图标时才做交叉淡入）
	private var iconNames = [ObjectIdentifier: String]()
	var translationState: TranslationButtonState { translationToggle.translationState }

	override init(frame: CGRect) {
		readButton = Self.makeButton(identifier: "babel2.article.toolbar.read")
		starButton = Self.makeButton(identifier: "babel2.article.toolbar.star")
		let next = Self.makeButton(identifier: "babel2.article.toolbar.next")
		nextButton = next
		readingModeButton = Self.makeButton(identifier: "babel2.article.toolbar.reading-mode")
		placeholderButtons = []
		super.init(frame: frame)
		backgroundColor = BabelPalette.background
		accessibilityIdentifier = "babel2.article.toolbar"

		setIcon("Babel2ReaderNext", on: next)
		next.accessibilityLabel = Babel2Localization.text(.nextArticle)
		readingModeButton.accessibilityLabel = Babel2Localization.text(.readingMode)
		readingModeButton.addTarget(self, action: #selector(readingModeTapped), for: .touchUpInside)
		next.isEnabled = false
		next.addTarget(self, action: #selector(nextTapped), for: .touchUpInside)

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
		let controls: [UIView] = [readButton, starButton, next, readingModeButton, translationToggle]
		for (control, center) in zip(controls, Self.slotCenters) {
			addSubview(control)
			let size = control === translationToggle ? Babel2TranslationToggle.size : CGSize(width: 44, height: 44)
			NSLayoutConstraint.activate([
				Babel2BarLayout.centerX(control, in: self, slot: center),
				control.centerYAnchor.constraint(equalTo: topAnchor, constant: Babel2BarLayout.centerY),
				control.widthAnchor.constraint(equalToConstant: size.width),
				control.heightAnchor.constraint(equalToConstant: size.height)
			])
		}
		// 按压反馈（ADR-034）
		controls.compactMap { $0 as? UIControl }.forEach(Babel2Motion.addPressFeedback)
		setRead(false)
		setStarred(false)
		setTranslationState(.original)
		setTranslationAvailable(false)
		setReaderMode(false, available: true)
	}

	/// 阅读模式按钮：关 = 设计稿图标（次要灰）；开 = 既有的加粗版图标（主墨色）。没有原文地址时不可点。
	func setReaderMode(_ on: Bool, available: Bool) {
		setIcon(on ? "BabelReaderReadingModeActive" : "BabelReaderReadingMode", on: readingModeButton)
		readingModeButton.tintColor = on ? BabelPalette.ink : BabelPalette.mutedInk
		readingModeButton.isEnabled = available
		readingModeButton.accessibilityValue = on ? "on" : "off"
	}

	required init?(coder: NSCoder) { nil }

	/// 已读 = 实心圆，未读 = 空心圈（用户 2026-09-25 决定）；无障碍说明描述「点了会怎样」。
	func setRead(_ read: Bool) {
		isRead = read
		readIconName = read ? "Babel2ReaderReadStateFilled" : "Babel2ReaderReadState"
		setIcon(readIconName, on: readButton)
		readButton.accessibilityLabel = Babel2Localization.text(read ? .markUnread : .markRead)
		readButton.accessibilityValue = read ? "read" : "unread"
	}

	func setStarred(_ starred: Bool) {
		let lightsUp = starred && !isStarred
		isStarred = starred
		starIconName = starred ? "Babel2ReaderStarFilled" : "Babel2ReaderStar"
		setIcon(starIconName, on: starButton)
		starButton.accessibilityLabel = Babel2Localization.text(starred ? .unstar : .star)
		starButton.accessibilityValue = starred ? "starred" : "unstarred"
		// 星标点亮时轻轻放大再回原（1.12 → 1，不回弹）；减弱动态效果时只有交叉淡入
		if lightsUp, starButton.window != nil, !Babel2Motion.reduceMotion, let imageView = starButton.imageView {
			imageView.transform = CGAffineTransform(scaleX: 1.12, y: 1.12)
			Babel2Motion.animate(Babel2Motion.standard) { imageView.transform = .identity }
		}
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
	@objc private func readingModeTapped() { onToggleReaderMode?() }
	@objc private func nextTapped() { onNext?() }

	/// 有下一篇才可点（没有时变灰，ADR-022）。
	func setNextAvailable(_ available: Bool) {
		nextButton.isEnabled = available
	}

	private static func makeButton(identifier: String) -> UIButton {
		let button = UIButton(type: .system)
		button.tintColor = BabelPalette.mutedInk
		button.accessibilityIdentifier = identifier
		button.translatesAutoresizingMaskIntoConstraints = false
		return button
	}

	/// 设计稿图标（模板图，按 Babel2Type.toolbarIcon 重画），正常态为次要灰；不可点时用更浅的中性灰，不用主题色。
	/// 换图标时交叉淡入（ADR-034，0.22 秒），不再瞬间跳变；同一个图标不重设。
	private func setIcon(_ name: String, on button: UIButton) {
		let key = ObjectIdentifier(button)
		guard iconNames[key] != name else { return }
		let image = Babel2Type.icon(UIImage(named: name), side: Babel2Type.toolbarIcon)?.withRenderingMode(.alwaysTemplate)
		assert(image != nil, "missing reader icon asset \(name)")
		let isFirstIcon = iconNames[key] == nil
		iconNames[key] = name
		let change = {
			button.setImage(image, for: .normal)
			button.setImage(image?.withTintColor(BabelPalette.tertiaryInk, renderingMode: .alwaysOriginal), for: .disabled)
		}
		if isFirstIcon {
			change()
		} else {
			Babel2Motion.crossfade(button, change)
		}
	}
}
