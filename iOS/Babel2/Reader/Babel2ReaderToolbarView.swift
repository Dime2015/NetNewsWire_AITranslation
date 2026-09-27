import UIKit

/// 阅读页底栏：按 Figma「Reader Toolbar」(21:5) 对齐（ADR-018）。
///
/// - 72pt 高、贴屏幕最底（含 Home 指示条区域），顶部 0.5pt 分隔线
/// - 四个设计稿图标（ADR-033 起 21pt）：已读 / 星标 / 下一篇 / 阅读模式，中心 x = 32 / 116.5 / 201 / 285.5，中心 y = 24
///   （ADR-020：第 4 格回到 Figma 原样的「阅读模式」，长图移入顶栏 ••• 菜单）
/// - 第 4 格「阅读模式」、第 5 格「翻译」是状态图标（ADR-043，2026-09-27 取代原来的线条图标与「原 / 译」文字开关）：
///   平时线条、进行中图标本身在动、成功墨色方块底、失败轻晃（Babel2StatusIcons.swift）
/// - 图标颜色为设计稿的次要灰（BabelPalette.mutedInk = #787878）
/// 全部接通：已读、星标、下一篇（没有下一篇时变灰）、阅读模式、翻译。
@MainActor
final class Babel2ReaderToolbarView: UIView {
	static let height: CGFloat = 72
	private static let slotCenters = Babel2BarLayout.slots

	let readButton: UIButton
	let starButton: UIButton
	let readingModeButton = Babel2ReaderModeIconButton()
	let nextButton: UIButton
	let translationToggle = Babel2TranslateIconButton()
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
		placeholderButtons = []
		super.init(frame: frame)
		backgroundColor = BabelPalette.background
		accessibilityIdentifier = "babel2.article.toolbar"

		setIcon("Babel2ReaderNext", on: next)
		next.accessibilityLabel = Babel2Localization.text(.nextArticle)
		readingModeButton.addTarget(self, action: #selector(readingModeTapped), for: .touchUpInside)
		next.isEnabled = false
		next.addTarget(self, action: #selector(nextTapped), for: .touchUpInside)

		readButton.addTarget(self, action: #selector(readTapped), for: .touchUpInside)
		starButton.addTarget(self, action: #selector(starTapped), for: .touchUpInside)
		translationToggle.addTarget(self, action: #selector(translateTapped), for: .touchUpInside)
		translationToggle.translatesAutoresizingMaskIntoConstraints = false
		readingModeButton.translatesAutoresizingMaskIntoConstraints = false

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
			let size = CGSize(width: 44, height: 44)
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

	/// 阅读模式按钮（ADR-043）：关 = 线条纸页；开 = 墨色方块底、纸页反白。没有原文地址时不可点。
	func setReaderMode(_ on: Bool, available: Bool) {
		isReaderModeLoading = false
		readingModeButton.isEnabled = available
		readingModeButton.setPhase(on ? .on : .idle)
		readingModeButton.accessibilityValue = on ? "on" : "off"
	}

	/// 正在取全文：纸页的三行字依次明灭（取代标题下的「正在获取全文…」）。
	private(set) var isReaderModeLoading = false
	func setReaderModeLoading() {
		isReaderModeLoading = true
		readingModeButton.setPhase(.working)
		readingModeButton.accessibilityValue = "loading"
	}

	/// 取全文失败：图标轻晃一下（提示文字由阅读页用小胶囊给）。
	func readerModeFailed() {
		readingModeButton.shake()
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
