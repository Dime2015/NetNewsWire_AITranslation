import UIKit

/// 阅读页底栏：72pt 高、贴屏幕最底（含 Home 指示条区域），顶上一条细分隔线。
///
/// 5 个按钮按 Figma「Reader Toolbar」：已读 / 星标 / 下一篇 / 阅读模式 / 翻译，
/// 中心位置对应 402pt 画布的 x = 32 / 104 / 201 / 290.5 / 362，垂直中心距底栏顶 24pt。
/// 已接通「已读」「星标」「翻译」（Slice 5 第 1 步）；「下一篇」「阅读模式」仍是占位，灰色不可点。
/// （按 ADR-016，之后第 4 格会改成「长图」，阅读模式移入顶栏「更多」菜单。）
@MainActor
final class Babel2ReaderToolbarView: UIView {
	static let height: CGFloat = 72
	private static let slotCenters: [CGFloat] = [32, 104, 201, 290.5, 362]
	private static let referenceWidth: CGFloat = 402

	let readButton: UIButton
	let starButton: UIButton
	let translateButton: UIButton
	let placeholderButtons: [UIButton]
	var onToggleRead: (() -> Void)?
	var onToggleStar: (() -> Void)?
	var onTranslate: (() -> Void)?
	/// 翻译按钮右下角的状态角标（实心点 / 空心圈 / 小勾），颜色为中性墨色。
	private let translateBadge = UIImageView()
	private(set) var translationState: TranslationButtonState = .original
	/// 仅供自动化测试：当前角标用的符号名（nil = 无角标）。
	private(set) var translateBadgeSymbol: String?

	private(set) var isRead = false
	private(set) var isStarred = false

	override init(frame: CGRect) {
		readButton = Self.makeButton(identifier: "babel2.article.toolbar.read")
		starButton = Self.makeButton(identifier: "babel2.article.toolbar.star")
		let next = Self.makeButton(identifier: "babel2.article.toolbar.next")
		let readingMode = Self.makeButton(identifier: "babel2.article.toolbar.reading-mode")
		translateButton = Self.makeButton(identifier: "babel2.article.toolbar.translate")
		placeholderButtons = [next, readingMode]
		super.init(frame: frame)
		backgroundColor = BabelPalette.background
		accessibilityIdentifier = "babel2.article.toolbar"

		Self.setSymbol("chevron.down", on: next)
		next.accessibilityLabel = Babel2Localization.text(.nextArticle)
		Self.setSymbol("doc.text", on: readingMode)
		readingMode.accessibilityLabel = Babel2Localization.text(.readingMode)
		placeholderButtons.forEach { $0.isEnabled = false }
		translateButton.addTarget(self, action: #selector(translateTapped), for: .touchUpInside)
		translateBadge.tintColor = BabelPalette.ink
		translateBadge.contentMode = .center
		// 晕圈：角标脚下垫一圈背景色，和翻译图标的笔画隔开（同旧版定稿设计）
		translateBadge.backgroundColor = BabelPalette.background
		translateBadge.layer.cornerRadius = 6
		translateBadge.isUserInteractionEnabled = false
		translateBadge.translatesAutoresizingMaskIntoConstraints = false
		translateButton.addSubview(translateBadge)
		NSLayoutConstraint.activate([
			translateBadge.centerXAnchor.constraint(equalTo: translateButton.centerXAnchor, constant: 11),
			translateBadge.centerYAnchor.constraint(equalTo: translateButton.centerYAnchor, constant: 10),
			translateBadge.widthAnchor.constraint(equalToConstant: 12),
			translateBadge.heightAnchor.constraint(equalToConstant: 12)
		])

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
		for (button, center) in zip([readButton, starButton] + placeholderButtons + [translateButton], Self.slotCenters) {
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
		setTranslationState(.original)
		setTranslationAvailable(false)
	}

	/// 页面还没准备好（正文未排版、文章对象未取回）时翻译按钮不可点。
	func setTranslationAvailable(_ available: Bool) {
		translateButton.isEnabled = available
		translateBadge.isHidden = !available || translateBadge.image == nil
	}

	/// 翻译按钮的六种状态（沿用 2026-07-30 定稿的「翻译符号 + 右下角角标」设计，按本底栏 20pt 重画）：
	/// 原文 = 无角标；有完整缓存 = 实心点；有未完成缓存 = 空心圈；已显示译文 = 小勾；
	/// 翻译中 = 图标变淡（合同禁止系统转圈，进度由正文骨架色条表示），仍可点 = 取消；失败 = 感叹号气泡。
	func setTranslationState(_ state: TranslationButtonState) {
		translationState = state
		var symbol = "translate"
		var badge: String?
		var alpha: CGFloat = 1
		let label: Babel2LocalizationKey
		let value: String
		switch state {
		case .original:
			label = .translate; value = "original"
		case .cachedAvailable:
			badge = "circle.fill"; label = .translate; value = "cached"
		case .partialCacheAvailable:
			badge = "circle"; label = .translate; value = "partial"
		case .working:
			alpha = 0.35; label = .cancelTranslation; value = "working"
		case .translated:
			// 单独的小勾（不带圆底）：带圆底的勾在这个尺寸下看起来就是实心点，会和「有缓存」混淆
			badge = "checkmark"; label = .showOriginal; value = "translated"
		case .failed:
			symbol = "exclamationmark.bubble"; label = .translate; value = "failed"
		}
		Self.setSymbol(symbol, on: translateButton)
		translateButton.imageView?.alpha = alpha
		// 勾比圆点略大略粗（笔画细，同尺寸显小）——沿用旧版设计稿要点
		let badgeConfiguration = badge == "checkmark"
			? UIImage.SymbolConfiguration(pointSize: 10, weight: .heavy)
			: UIImage.SymbolConfiguration(pointSize: 7, weight: .bold)
		translateBadge.image = badge.flatMap { UIImage(systemName: $0, withConfiguration: badgeConfiguration) }
		translateBadgeSymbol = badge
		translateBadge.isHidden = translateBadge.image == nil || !translateButton.isEnabled
		translateButton.accessibilityLabel = Babel2Localization.text(label)
		translateButton.accessibilityValue = value
	}

	required init?(coder: NSCoder) { nil }

	/// 已读 = 实心圆，未读 = 空心圈（用户 2026-09-25 决定，与 Reeder/旧版相反）；
	/// 按钮的无障碍说明描述的是「点了会怎样」。
	func setRead(_ read: Bool) {
		isRead = read
		Self.setSymbol(read ? "circle.fill" : "circle", on: readButton)
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
	@objc private func translateTapped() { onTranslate?() }

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
