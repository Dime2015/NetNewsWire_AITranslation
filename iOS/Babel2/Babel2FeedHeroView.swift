import UIKit

/// 文章列表页顶部大图（ADR-027 第 2 步，样式 E「整幅清晰铺满」，用户 2026-09-25 从 A 改选）。
///
/// - 订阅源高清图不虚化、完全不透明，从屏幕最顶端（状态栏 / 灵动岛下面）铺到安全区下方 169pt
/// - 只在最下面约 45% 渐隐成纸色（深色模式即深色底），与下面的列表无缝相接
///   （A 版「虚化 + 半透明 + 大面积渐隐」遮得太重、几乎看不出图，被否决）
/// - 标题用正文墨色、28pt 粗体，落在已接近纸色的底部；下面一行「N 篇」
/// - 有大图时不放圆形小图标（用户 2026-09-25）；返回按钮在上层的窄栏里，全程不动
/// - 没有高清图标：同样版式、纯纸色底（不另做一套样子）
///
/// 第 3 步：随列表滚动整体上移、图与大标题淡出（`apply(progress:)`，只改平移与透明度）。
/// 不接收点按——手指从大图上开始拖，照样能滚动下面的列表。
final class Babel2FeedHeroView: UIView {
	/// 安全区以下的高度（Figma 03A「Feed Hero / Expanded」169pt）。
	static let expandedHeight: CGFloat = 169

	let titleLabel = UILabel()
	private let countLabel: UILabel
	private let artView = UIImageView()
	private let fadeLayer = CAGradientLayer()
	private var artTask: Task<Void, Never>?
	/// 当前收缩进度（0 展开 … 1 收缩），决定图与大标题的透明度。
	private var progress: CGFloat = 0
	/// 仅供自动化测试观察：是否已经铺上了订阅源的图。
	var hasArtForTesting: Bool { artView.image != nil }

	init(title: String, countLabel: UILabel) {
		self.countLabel = countLabel
		super.init(frame: .zero)
		backgroundColor = BabelPalette.background
		clipsToBounds = true
		isUserInteractionEnabled = false

		artView.contentMode = .scaleAspectFill
		artView.clipsToBounds = true
		artView.alpha = 0
		artView.translatesAutoresizingMaskIntoConstraints = false
		addSubview(artView)
		layer.addSublayer(fadeLayer)
		updateFadeColors()

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

		[titleLabel, countLabel].forEach(addSubview)

		NSLayoutConstraint.activate([
			artView.leadingAnchor.constraint(equalTo: leadingAnchor),
			artView.trailingAnchor.constraint(equalTo: trailingAnchor),
			artView.topAnchor.constraint(equalTo: topAnchor),
			artView.bottomAnchor.constraint(equalTo: bottomAnchor),

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
			let show = { self.artView.alpha = Self.artAlpha * Babel2FeedHeroMotion.heroContentAlpha(self.progress) }
			if animated {
				UIView.animate(withDuration: 0.25, animations: show)
			} else {
				show()
			}
		}
	}

	/// 按收缩进度更新：整体上移 70pt × 进度，图淡出、大标题更快淡出。只改平移与透明度，不重新排版。
	func apply(progress newProgress: CGFloat) {
		progress = newProgress
		transform = CGAffineTransform(translationX: 0, y: -Babel2FeedHeroMotion.collapseDistance * newProgress)
		if artView.image != nil {
			artView.alpha = Self.artAlpha * Babel2FeedHeroMotion.heroContentAlpha(newProgress)
		}
		let titleAlpha = Babel2FeedHeroMotion.heroTitleAlpha(newProgress)
		titleLabel.alpha = titleAlpha
		countLabel.alpha = titleAlpha
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

/// 收缩后的窄栏（Figma 03C「Feed Hero / Compact Sticky」，ADR-027 保留「小图标 + 名字」）：
/// 从屏幕最顶端到安全区下方 99pt；纸色底随收缩进度变为完全不透明；
/// 第二行 26pt 圆形小图标（x=20）+ 订阅源名 17pt 半粗（x=56）在后半程淡入；底部细线。
/// 返回按钮与右上角放大镜（Figma 搜索位 x=330）在这一层、全程不动。除这些控件外不拦截触摸（拖动照样滚动列表）。
/// 搜索时第二行换成搜索框 +「取消」，纸色底完全不透明。
final class Babel2FeedCompactBar: UIView {
	let backButton = UIButton(type: .system)
	let searchButton = UIButton(type: .system)
	/// 刷新（Figma 刷新位 x=201）：浅色圆盘 + 逆时针箭头，同步时旋转（复用首页同步图标）。ADR-031。
	let refreshButton = UIButton(type: .system)
	private let refreshGlyph = BabelSyncGlyphView()
	/// 更多（Figma 更多位 x=370）：点按弹出本订阅源的操作菜单。ADR-031。
	let moreButton = UIButton(type: .system)
	let searchField: Babel2FeedSearchField
	private(set) var isSearching = false
	let titleLabel = UILabel()
	private let backdrop = UIView()
	private let iconView = UIImageView()
	private let initialLabel = UILabel()
	private let hairline = UIView()
	/// 仅供自动化测试观察：纸色底的不透明度（1 = 完全不透明）。
	var backdropAlphaForTesting: CGFloat { backdrop.alpha }

	init(title: String, icon: UIImage?) {
		searchField = Babel2FeedSearchField(
			placeholder: String(format: Babel2Localization.text(.searchFeedPlaceholder), title),
			cancelTitle: Babel2Localization.text(.cancel)
		)
		super.init(frame: .zero)
		backgroundColor = .clear

		backdrop.backgroundColor = BabelPalette.background
		backdrop.alpha = 0
		backdrop.translatesAutoresizingMaskIntoConstraints = false
		addSubview(backdrop)

		backButton.setImage(UIImage(systemName: "chevron.left", withConfiguration: UIImage.SymbolConfiguration(pointSize: 19, weight: .semibold)), for: .normal)
		backButton.tintColor = BabelPalette.ink
		backButton.accessibilityLabel = "Back"
		backButton.accessibilityIdentifier = "babel2.feed.back"
		backButton.translatesAutoresizingMaskIntoConstraints = false

		iconView.image = icon
		iconView.contentMode = .scaleAspectFill
		iconView.clipsToBounds = true
		iconView.layer.cornerRadius = 13
		iconView.layer.borderWidth = 0.75
		iconView.layer.borderColor = UIColor(red: 209 / 255, green: 209 / 255, blue: 204 / 255, alpha: 0.42).cgColor
		iconView.backgroundColor = icon == nil ? BabelPalette.hairline : .clear
		iconView.alpha = 0
		iconView.translatesAutoresizingMaskIntoConstraints = false
		initialLabel.text = icon == nil ? title.first.map { String($0).uppercased() } : nil
		initialLabel.font = .systemFont(ofSize: 13, weight: .semibold)
		initialLabel.textColor = BabelPalette.mutedInk
		initialLabel.translatesAutoresizingMaskIntoConstraints = false
		iconView.addSubview(initialLabel)

		titleLabel.text = title
		titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
		titleLabel.textColor = BabelPalette.ink
		titleLabel.lineBreakMode = .byTruncatingTail
		titleLabel.alpha = 0
		titleLabel.accessibilityIdentifier = "babel2.feed.compact-title"
		titleLabel.translatesAutoresizingMaskIntoConstraints = false

		hairline.backgroundColor = BabelPalette.hairline
		hairline.alpha = 0
		hairline.translatesAutoresizingMaskIntoConstraints = false

		searchButton.setImage(UIImage(systemName: "magnifyingglass", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)), for: .normal)
		searchButton.tintColor = BabelPalette.ink
		searchButton.accessibilityLabel = Babel2Localization.text(.search)
		searchButton.accessibilityIdentifier = "babel2.feed.search"
		searchButton.translatesAutoresizingMaskIntoConstraints = false
		searchField.isHidden = true
		searchField.translatesAutoresizingMaskIntoConstraints = false

		refreshButton.accessibilityLabel = Babel2Localization.text(.refresh)
		refreshButton.accessibilityIdentifier = "babel2.feed.refresh"
		refreshButton.translatesAutoresizingMaskIntoConstraints = false
		refreshGlyph.translatesAutoresizingMaskIntoConstraints = false
		refreshButton.addSubview(refreshGlyph)
		setSyncing(false)
		moreButton.setImage(UIImage(named: "Babel2ReaderMore"), for: .normal)
		moreButton.tintColor = BabelPalette.ink
		moreButton.showsMenuAsPrimaryAction = true
		moreButton.accessibilityLabel = Babel2Localization.text(.more)
		moreButton.accessibilityIdentifier = "babel2.feed.more"
		moreButton.translatesAutoresizingMaskIntoConstraints = false

		[backButton, searchButton, refreshButton, moreButton, iconView, titleLabel, hairline, searchField].forEach(addSubview)
		let safeTop = safeAreaLayoutGuide.topAnchor
		NSLayoutConstraint.activate([
			backdrop.leadingAnchor.constraint(equalTo: leadingAnchor),
			backdrop.trailingAnchor.constraint(equalTo: trailingAnchor),
			backdrop.topAnchor.constraint(equalTo: topAnchor),
			backdrop.bottomAnchor.constraint(equalTo: bottomAnchor),

			backButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
			backButton.centerYAnchor.constraint(equalTo: safeTop, constant: 22),
			backButton.widthAnchor.constraint(equalToConstant: 44),
			backButton.heightAnchor.constraint(equalToConstant: 44),
			refreshButton.centerXAnchor.constraint(equalTo: centerXAnchor),
			refreshButton.centerYAnchor.constraint(equalTo: safeTop, constant: 22),
			refreshButton.widthAnchor.constraint(equalToConstant: 44),
			refreshButton.heightAnchor.constraint(equalToConstant: 44),
			refreshGlyph.centerXAnchor.constraint(equalTo: refreshButton.centerXAnchor),
			refreshGlyph.centerYAnchor.constraint(equalTo: refreshButton.centerYAnchor),
			refreshGlyph.widthAnchor.constraint(equalToConstant: 24),
			refreshGlyph.heightAnchor.constraint(equalToConstant: 24),
			moreButton.centerXAnchor.constraint(equalTo: trailingAnchor, constant: -32),
			moreButton.centerYAnchor.constraint(equalTo: safeTop, constant: 22),
			moreButton.widthAnchor.constraint(equalToConstant: 44),
			moreButton.heightAnchor.constraint(equalToConstant: 44),
			searchButton.centerXAnchor.constraint(equalTo: trailingAnchor, constant: -72),
			searchButton.centerYAnchor.constraint(equalTo: safeTop, constant: 22),
			searchButton.widthAnchor.constraint(equalToConstant: 44),
			searchButton.heightAnchor.constraint(equalToConstant: 44),
			searchField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
			searchField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
			searchField.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),
			searchField.heightAnchor.constraint(equalToConstant: 44),

			iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
			iconView.topAnchor.constraint(equalTo: safeTop, constant: 54),
			iconView.widthAnchor.constraint(equalToConstant: 26),
			iconView.heightAnchor.constraint(equalToConstant: 26),
			initialLabel.centerXAnchor.constraint(equalTo: iconView.centerXAnchor),
			initialLabel.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),

			titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 56),
			titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -20),
			titleLabel.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),

			hairline.leadingAnchor.constraint(equalTo: leadingAnchor),
			hairline.trailingAnchor.constraint(equalTo: trailingAnchor),
			hairline.bottomAnchor.constraint(equalTo: bottomAnchor),
			hairline.heightAnchor.constraint(equalToConstant: 0.5)
		])
	}

	required init?(coder: NSCoder) { nil }

	/// 进入 / 退出搜索：第二行在「小图标 + 名字」与搜索框之间切换；搜索时放大镜隐藏。
	func setSearching(_ searching: Bool) {
		isSearching = searching
		searchField.isHidden = !searching
		searchButton.isHidden = searching
		refreshButton.isHidden = searching
		moreButton.isHidden = searching
		iconView.isHidden = searching
		titleLabel.isHidden = searching
		if searching {
			apply(progress: 1)
		} else {
			searchField.clear()
			searchField.textField.resignFirstResponder()
		}
	}

	/// 同步中：刷新箭头旋转；不同步时静止显示（首页的同一图标不同步时会自己隐藏，这里要一直可见）。
	func setSyncing(_ syncing: Bool) {
		refreshGlyph.setSyncing(syncing)
		refreshGlyph.isHidden = false
		refreshButton.accessibilityValue = syncing ? Babel2Localization.text(.syncing) : nil
	}

	/// 仅供自动化测试。
	var isShowingSyncingForTesting: Bool { refreshButton.accessibilityValue != nil }

	/// 按收缩进度更新透明度（不重新排版）。
	func apply(progress: CGFloat) {
		backdrop.alpha = Babel2FeedHeroMotion.compactBackgroundAlpha(progress)
		hairline.alpha = progress
		let contentAlpha = Babel2FeedHeroMotion.compactContentAlpha(progress)
		iconView.alpha = contentAlpha
		titleLabel.alpha = contentAlpha
	}

	/// 只有返回、放大镜、搜索框接收触摸；其余位置交给下面的列表（从顶部开始拖也能滚动）。
	/// 搜索时整条窄栏都接收（它是完全不透明的顶栏）。
	override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
		if isSearching { return bounds.contains(point) }
		return [backButton, searchButton, refreshButton, moreButton].contains { !$0.isHidden && $0.frame.insetBy(dx: -4, dy: -4).contains(point) }
	}
}
