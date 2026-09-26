import UIKit

/// Figma「Translation Toggle」(43:19)：底栏右侧安静的文字开关，58×44。
///
/// 一个粗体大字 + 一个小字说明（设计稿原样，中文字形是设计的一部分）：
/// - 显示原文：「原」+「翻译」
/// - 翻译进行中：「译」+「生成中」（仍可点 = 取消并回到原文）
/// - 显示译文：「译」+「原文」
/// - 失败：「原」+「重试」（设计稿无此态，按同一版式补）
/// 有缓存 / 翻了一半 这两种状态设计稿没有提示，和「原文」显示相同（ADR-018）。
@MainActor
final class Babel2TranslationToggle: UIControl {
	static let size = CGSize(width: 58, height: 44)

	private let mainLabel = UILabel()
	private let captionLabel = UILabel()
	private(set) var translationState: TranslationButtonState = .original

	override init(frame: CGRect) {
		super.init(frame: frame)
		isAccessibilityElement = true
		accessibilityTraits = .button
		accessibilityIdentifier = "babel2.article.toolbar.translate"

		// 大字：13pt 半粗、次要灰，中心在 x=16，顶 14.5，高 17
		// （ADR-033：整体下移 1pt，汉字的视觉中心与左边几个图标的中线对齐）
		mainLabel.font = .systemFont(ofSize: 13, weight: .semibold)
		mainLabel.textColor = BabelPalette.mutedInk
		mainLabel.textAlignment = .center
		mainLabel.frame = CGRect(x: 16 - 9, y: 14.5, width: 18, height: 17)
		// 小字：7pt 常规、浅灰，左 25，顶 18.5，高 9
		captionLabel.font = .systemFont(ofSize: 7, weight: .regular)
		captionLabel.textColor = BabelPalette.tertiaryInk
		captionLabel.frame = CGRect(x: 25, y: 18.5, width: 27, height: 9)
		[mainLabel, captionLabel].forEach {
			$0.isUserInteractionEnabled = false
			addSubview($0)
		}
		setState(.original)
	}

	required init?(coder: NSCoder) { nil }

	override var intrinsicContentSize: CGSize { Self.size }

	override var isEnabled: Bool {
		didSet { alpha = isEnabled ? 1 : 0.4 }
	}

	func setState(_ newState: TranslationButtonState) {
		translationState = newState
		let main: String
		let caption: String
		let label: Babel2LocalizationKey
		let value: String
		switch newState {
		case .original, .cachedAvailable, .partialCacheAvailable:
			main = "原"; caption = "翻译"; label = .translate
			value = newState == .original ? "original" : (newState == .cachedAvailable ? "cached" : "partial")
		case .working:
			main = "译"; caption = "生成中"; label = .cancelTranslation; value = "working"
		case .translated:
			main = "译"; caption = "原文"; label = .showOriginal; value = "translated"
		case .failed:
			main = "原"; caption = "重试"; label = .translate; value = "failed"
		}
		// 字变了才交叉淡入（ADR-034）；首次设置与不在屏幕上时直接换
		if mainLabel.text != nil, mainLabel.text != main || captionLabel.text != caption {
			Babel2Motion.crossfade(self) {
				self.mainLabel.text = main
				self.captionLabel.text = caption
			}
		} else {
			mainLabel.text = main
			captionLabel.text = caption
		}
		accessibilityLabel = Babel2Localization.text(label)
		accessibilityValue = value
	}

	/// 仅供自动化测试：当前显示的大字与小字。
	var displayedText: (main: String?, caption: String?) { (mainLabel.text, captionLabel.text) }
}
