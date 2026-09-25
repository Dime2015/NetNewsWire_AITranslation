import UIKit

/// 阅读页的「紧凑标题栏」，按 Figma「Reader Compact Header」(143:73)：86pt 高，
/// 左 20pt 起 48pt 进度圆环（内含 42pt 圆形订阅源图标），间隔 12pt 后是两行文字：
/// 「订阅源 · 作者」13pt 常规次要灰 + 一行标题 16pt 半粗主墨色，行间 2pt；底部 0.5pt 分隔线。
///
/// 它不自己做动画，只接收两个进度值并立刻画出来：
/// - `pCollapse`（0→1）：底色、图标、圆环、文字一起从透明变清楚，文字从下方 12pt 滑到位
/// - `pReading`（0→1）：圆环上主题色弧的长度
/// 手指停在哪、画面就停在哪，往回滑就倒着走（方案 A，用户 2026-09-24 选定）。
@MainActor
final class Babel2ReaderCompactHeaderView: UIView {
	/// 文字滑入的起始下移距离；合同未规定具体值，属可调项。
	private static let textRiseDistance: CGFloat = 12

	private let backgroundView = UIView()
	private let separator = UIView()
	private let ringView = Babel2ReaderProgressRingView()
	private let sourceLabel = UILabel()
	private let titleLabel = UILabel()
	private(set) var pCollapse: CGFloat = 0
	private(set) var pReading: CGFloat = 0

	/// 点副标题末尾「↗」：在内置浏览器打开原文（ADR-021）。
	var onSourceLinkTapped: (() -> Void)?
	private let showsSourceLink: Bool

	init(feedTitle: String?, author: String? = nil, articleTitle: String, iconData: Data?, showsSourceLink: Bool = false) {
		self.showsSourceLink = showsSourceLink
		super.init(frame: .zero)
		accessibilityIdentifier = "babel2.article.compact-header"
		isAccessibilityElement = true
		accessibilityLabel = [feedTitle, author, articleTitle].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
		isUserInteractionEnabled = false
		addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))

		backgroundView.backgroundColor = BabelPalette.background
		separator.backgroundColor = BabelPalette.hairline
		[backgroundView, separator].forEach { view in
			view.translatesAutoresizingMaskIntoConstraints = false
			addSubview(view)
		}

		ringView.configure(iconData: iconData, fallbackTitle: feedTitle ?? articleTitle)
		ringView.translatesAutoresizingMaskIntoConstraints = false
		addSubview(ringView)

		// 设计稿这一行末尾有「↗」（打开来源）：能在内置浏览器打开原文时才显示
		var subtitle = [feedTitle, author]
			.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
			.filter { !$0.isEmpty }
			.joined(separator: " · ")
			.uppercased()
		if showsSourceLink { subtitle += subtitle.isEmpty ? "↗" : " ↗" }
		sourceLabel.text = subtitle
		sourceLabel.font = .systemFont(ofSize: 13, weight: .regular)
		sourceLabel.textColor = BabelPalette.mutedInk
		sourceLabel.lineBreakMode = .byTruncatingTail
		titleLabel.text = articleTitle
		titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
		titleLabel.textColor = BabelPalette.ink
		titleLabel.lineBreakMode = .byTruncatingTail
		titleLabel.accessibilityIdentifier = "babel2.article.compact-title"
		let textStack = UIStackView(arrangedSubviews: [sourceLabel, titleLabel])
		textStack.axis = .vertical
		textStack.spacing = 2
		textStack.translatesAutoresizingMaskIntoConstraints = false
		addSubview(textStack)
		sourceLabel.isHidden = subtitle.isEmpty
		sourceLabel.accessibilityIdentifier = "babel2.article.compact-subtitle"

		// 内容在 85.5pt 内容区里垂直居中（上下各 15pt 内边距）；栏显示时顶部 14pt 与顶栏重叠
		NSLayoutConstraint.activate([
			backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
			backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
			backgroundView.topAnchor.constraint(equalTo: topAnchor),
			backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),
			separator.leadingAnchor.constraint(equalTo: leadingAnchor),
			separator.trailingAnchor.constraint(equalTo: trailingAnchor),
			separator.bottomAnchor.constraint(equalTo: bottomAnchor),
			separator.heightAnchor.constraint(equalToConstant: 0.5),
			ringView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
			ringView.centerYAnchor.constraint(equalTo: topAnchor, constant: 42.75),
			ringView.widthAnchor.constraint(equalToConstant: 48),
			ringView.heightAnchor.constraint(equalToConstant: 48),
			textStack.leadingAnchor.constraint(equalTo: ringView.trailingAnchor, constant: 12),
			textStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
			textStack.centerYAnchor.constraint(equalTo: ringView.centerYAnchor)
		])
		apply(pCollapse: 0, pReading: 0)
	}

	required init?(coder: NSCoder) { nil }

	var textLayer: UIView { titleLabel.superview ?? titleLabel }

	/// 标题译文就位 / 切回原文时同步紧凑栏标题。
	func setArticleTitle(_ title: String) {
		titleLabel.text = title
	}

	/// 按进度立刻重画，不带任何隐式动画。
	func apply(pCollapse: CGFloat, pReading: CGFloat) {
		self.pCollapse = pCollapse
		self.pReading = pReading
		isHidden = pCollapse <= 0
		let rise = CGAffineTransform(translationX: 0, y: (1 - pCollapse) * Self.textRiseDistance)
		UIView.performWithoutAnimation {
			backgroundView.alpha = pCollapse
			separator.alpha = pCollapse
			ringView.alpha = pCollapse
			textLayer.alpha = pCollapse
			textLayer.transform = rise
		}
		ringView.progress = pReading
		accessibilityValue = "\(Int((pReading * 100).rounded()))%"
		// 基本出现后才接收点击（打开原文）；其余时候点击穿透到正文
		isUserInteractionEnabled = showsSourceLink && pCollapse >= 0.5
	}

	@objc private func tapped() { onSourceLinkTapped?() }

	/// 仅供自动化测试。
	var subtitleText: String? { sourceLabel.text }
}

/// 48pt 的进度圆环，中间是 42pt 圆形订阅源图标（没有图标显示首字母）。
/// 浅灰底圈 + 一段从 12 点方向顺时针增长的主题色弧（整页唯一使用主题色的地方）。
@MainActor
final class Babel2ReaderProgressRingView: UIView {
	private let trackLayer = CAShapeLayer()
	private let progressLayer = CAShapeLayer()
	private let imageView = UIImageView()
	private let fallbackLabel = UILabel()

	var progress: CGFloat = 0 {
		didSet {
			CATransaction.begin()
			CATransaction.setDisableActions(true)
			progressLayer.strokeEnd = min(max(progress, 0), 1)
			CATransaction.commit()
		}
	}

	/// 仅供自动化测试：当前主题色弧的长度（0…1）。
	var renderedProgress: CGFloat { progressLayer.strokeEnd }

	override init(frame: CGRect) {
		super.init(frame: frame)
		isUserInteractionEnabled = false
		for shape in [trackLayer, progressLayer] {
			shape.fillColor = UIColor.clear.cgColor
			layer.addSublayer(shape)
		}
		// Figma Progress Ring：底圈 2pt、进度弧 2.5pt 圆头，半径 22
		trackLayer.lineWidth = 2
		progressLayer.lineWidth = 2.5
		progressLayer.lineCap = .round
		progressLayer.strokeEnd = 0

		imageView.contentMode = .scaleAspectFill
		imageView.clipsToBounds = true
		imageView.layer.cornerRadius = 21
		// 无图标时：浅灰占位底（设计稿 placeholder = 分隔线同色）+ 24pt 半粗首字母
		fallbackLabel.font = .systemFont(ofSize: 24, weight: .semibold)
		fallbackLabel.textAlignment = .center
		fallbackLabel.textColor = BabelPalette.mutedInk
		fallbackLabel.backgroundColor = BabelPalette.hairline
		fallbackLabel.clipsToBounds = true
		fallbackLabel.layer.cornerRadius = 21
		for view in [imageView, fallbackLabel] {
			view.translatesAutoresizingMaskIntoConstraints = false
			addSubview(view)
			NSLayoutConstraint.activate([
				view.centerXAnchor.constraint(equalTo: centerXAnchor),
				view.centerYAnchor.constraint(equalTo: centerYAnchor),
				view.widthAnchor.constraint(equalToConstant: 42),
				view.heightAnchor.constraint(equalToConstant: 42)
			])
		}
		updateColors()
		NotificationCenter.default.addObserver(self, selector: #selector(accentDidChange), name: NNWAccentPalette.didChangeNotification, object: nil)
		registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: Babel2ReaderProgressRingView, _) in
			view.updateColors()
		}
	}

	required init?(coder: NSCoder) { nil }

	func configure(iconData: Data?, fallbackTitle: String) {
		let image = iconData.flatMap(UIImage.init(data:))
		imageView.image = image
		imageView.isHidden = image == nil
		fallbackLabel.text = fallbackTitle.trimmingCharacters(in: .whitespacesAndNewlines).first.map { String($0).uppercased() }
		fallbackLabel.isHidden = image != nil
	}

	override func layoutSubviews() {
		super.layoutSubviews()
		// 从 12 点方向（-90°）开始顺时针一整圈
		let path = UIBezierPath(
			arcCenter: CGPoint(x: bounds.midX, y: bounds.midY),
			radius: 22,
			startAngle: -.pi / 2,
			endAngle: .pi * 1.5,
			clockwise: true
		).cgPath
		for shape in [trackLayer, progressLayer] {
			shape.frame = bounds
			shape.path = path
		}
	}

	@objc private func accentDidChange() { updateColors() }

	private func updateColors() {
		trackLayer.strokeColor = BabelPalette.hairline.resolvedColor(with: traitCollection).cgColor
		progressLayer.strokeColor = BabelPalette.themeAccent.resolvedColor(with: traitCollection).cgColor
	}
}
