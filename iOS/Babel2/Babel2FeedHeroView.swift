import UIKit

/// 文章列表页顶部大图（ADR-027 第 2 步，样式 E「整幅清晰铺满」，用户 2026-09-25 从 A 改选）。
///
/// - 订阅源高清图不虚化、完全不透明，从屏幕最顶端（状态栏 / 灵动岛下面）铺到安全区下方 169pt
/// - 只在最下面约 45% 渐隐成纸色（深色模式即深色底），与下面的列表无缝相接
///   （A 版「虚化 + 半透明 + 大面积渐隐」遮得太重、几乎看不出图，被否决）
/// - 标题用正文墨色、28pt 粗体，落在已接近纸色的底部；下面一行「N 篇」
/// - 只放返回按钮；有大图时不放圆形小图标（用户 2026-09-25）
/// - 没有高清图标：同样版式、纯纸色底（不另做一套样子）
///
/// 这一步大图固定高度，不随滚动收缩（第 3 步再做）。
final class Babel2FeedHeroView: UIView {
	/// 安全区以下的高度（Figma 03A「Feed Hero / Expanded」169pt）。
	static let expandedHeight: CGFloat = 169

	let backButton = UIButton(type: .system)
	let titleLabel = UILabel()
	private let countLabel: UILabel
	private let artView = UIImageView()
	private let fadeLayer = CAGradientLayer()
	private var artTask: Task<Void, Never>?
	/// 仅供自动化测试观察：是否已经铺上了订阅源的图。
	var hasArtForTesting: Bool { artView.image != nil }

	init(title: String, countLabel: UILabel) {
		self.countLabel = countLabel
		super.init(frame: .zero)
		backgroundColor = BabelPalette.background
		clipsToBounds = true

		artView.contentMode = .scaleAspectFill
		artView.clipsToBounds = true
		artView.alpha = 0
		artView.translatesAutoresizingMaskIntoConstraints = false
		addSubview(artView)
		layer.addSublayer(fadeLayer)
		updateFadeColors()

		backButton.setImage(UIImage(systemName: "chevron.left", withConfiguration: UIImage.SymbolConfiguration(pointSize: 19, weight: .semibold)), for: .normal)
		backButton.tintColor = BabelPalette.ink
		backButton.accessibilityLabel = "Back"
		backButton.accessibilityIdentifier = "babel2.feed.back"
		backButton.translatesAutoresizingMaskIntoConstraints = false

		titleLabel.text = title
		titleLabel.font = .systemFont(ofSize: 28, weight: .bold)
		titleLabel.textColor = BabelPalette.ink
		titleLabel.numberOfLines = 1
		titleLabel.lineBreakMode = .byTruncatingTail
		titleLabel.adjustsFontSizeToFitWidth = true
		titleLabel.minimumScaleFactor = 0.75
		titleLabel.accessibilityIdentifier = "babel2.feed.title"
		titleLabel.accessibilityTraits = .header
		titleLabel.translatesAutoresizingMaskIntoConstraints = false

		countLabel.font = .systemFont(ofSize: 13, weight: .medium)
		countLabel.textColor = BabelPalette.tertiaryInk
		countLabel.accessibilityIdentifier = "babel2.feed.count"
		countLabel.translatesAutoresizingMaskIntoConstraints = false

		[backButton, titleLabel, countLabel].forEach(addSubview)

		NSLayoutConstraint.activate([
			artView.leadingAnchor.constraint(equalTo: leadingAnchor),
			artView.trailingAnchor.constraint(equalTo: trailingAnchor),
			artView.topAnchor.constraint(equalTo: topAnchor),
			artView.bottomAnchor.constraint(equalTo: bottomAnchor),

			backButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
			backButton.centerYAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 22),
			backButton.widthAnchor.constraint(equalToConstant: 44),
			backButton.heightAnchor.constraint(equalToConstant: 44),

			titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
			titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -20),
			titleLabel.bottomAnchor.constraint(equalTo: countLabel.topAnchor, constant: -2),
			countLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
			countLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -20),
			countLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14)
		])

		registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: Babel2FeedHeroView, _) in
			view.updateFadeColors()
		}
	}

	required init?(coder: NSCoder) { nil }

	deinit {
		artTask?.cancel()
	}

	override func layoutSubviews() {
		super.layoutSubviews()
		CATransaction.begin()
		CATransaction.setDisableActions(true)
		fadeLayer.frame = bounds
		CATransaction.commit()
		// 渐隐层压在底图之上、文字与按钮之下
		layer.insertSublayer(fadeLayer, above: artView.layer)
	}

	/// 铺上订阅源的图：后台先解码好（不在主线程上解码大图），再淡入。
	/// 同一张图重复调用无害；晚到的更好的图会替换掉之前的。
	func setArt(_ image: UIImage?, animated: Bool) {
		artTask?.cancel()
		guard let image else { return }
		artTask = Task { @MainActor [weak self] in
			let prepared = await image.byPreparingForDisplay() ?? image
			guard let self, !Task.isCancelled else { return }
			self.artView.image = prepared
			let show = { self.artView.alpha = Self.artAlpha }
			if animated {
				UIView.animate(withDuration: 0.25, animations: show)
			} else {
				show()
			}
		}
	}

	/// 图完全不透明：要让人看清订阅源的图。
	private static let artAlpha: CGFloat = 1

	/// 渐隐：上半部分完全是原图；约 55% 处开始、80% 处基本变成纸色（标题落在这里），底边完全是纸色（与列表无缝）。
	private func updateFadeColors() {
		let paper = BabelPalette.background.resolvedColor(with: traitCollection)
		fadeLayer.colors = [0, 0, 0.85, 1].map { paper.withAlphaComponent($0).cgColor }
		fadeLayer.locations = [0, 0.55, 0.8, 1]
	}
}
