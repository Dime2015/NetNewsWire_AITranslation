import UIKit

/// 文章列表页顶部大图（ADR-027 第 2 步，样式 E「整幅清晰铺满」，用户 2026-09-25 从 A 改选）。
///
/// - 订阅源高清图不虚化、完全不透明，从屏幕最顶端（状态栏 / 灵动岛下面）铺到安全区下方 169pt
/// - 只在最下面约 45% 渐隐成纸色（深色模式即深色底），与下面的列表无缝相接
///   （A 版「虚化 + 半透明 + 大面积渐隐」遮得太重、几乎看不出图，被否决）
/// - 标题用正文墨色、27pt 半粗（ADR-067），落在已接近纸色的底部；下面一行「N 篇」
/// - 有大图时不放圆形小图标（用户 2026-09-25）；返回按钮在上层的窄栏里，全程不动
/// - 没有高清图（跨源列表、没有高清图标的源）：标题上方多一行小字「眉题」（ADR-067）；
///   「微光点阵」不在这里画，而是列表页垫在列表下面的一层（天幕，ADR-068：纹路不随滑动离开）。
///   有大图时眉题不显示——会落在图上看不清；状态栏渐变也只在有图时才需要。
/// - 底色透明（ADR-068）：没有图时露出下面的纹路；有图时图本身不透明。
/// - 大标题（ADR-068）：看得见的那个标题住在窄栏里，从这里的位置缩放归位到窄栏；
///   这里的 titleLabel 只占位（量出静止时标题在哪），不显示。
///
/// 第 3 步：随列表滚动整体上移、图与眉题 / 篇数淡出（`apply(progress:)`，只改平移与透明度）。
/// 不接收点按——手指从大图上开始拖，照样能滚动下面的列表。
final class Babel2FeedHeroView: UIView {
	/// 安全区以下的高度（Figma 03A「Feed Hero / Expanded」169pt）。
	static let expandedHeight: CGFloat = 169

	let titleLabel = UILabel()
	private let countLabel: UILabel
	private let eyebrowLabel = UILabel()
	private let artView = UIImageView()
	private let fadeLayer = CAGradientLayer()
	/// 状态栏那一条从顶端往下的淡纸色渐变：深色图上时间、信号也看得清（2026-09-25 用户截图）。只盖状态栏高度。
	private let statusScrimLayer = CAGradientLayer()
	private var artTask: Task<Void, Never>?
	/// 当前收缩进度（0 展开 … 1 收缩），决定图与大标题的透明度。
	private var progress: CGFloat = 0
	/// 仅供自动化测试观察：是否已经铺上了订阅源的图。
	var hasArtForTesting: Bool { artView.image != nil }
	/// 有没有大图（不含正在淡出的）变了：列表页据此在「天幕」与「大图收起」两种顶栏之间切换（ADR-068）。
	var onArtShownChanged: ((Bool) -> Void)?
	/// 排好版之后（占位标题的位置定了）：窄栏据此重算标题的缩放归位起点。
	var onLayout: (() -> Void)?
	private var lastReportedShowsArt = false

	init(title: String, countLabel: UILabel, eyebrow: String? = nil) {
		self.countLabel = countLabel
		super.init(frame: .zero)
		backgroundColor = .clear
		clipsToBounds = true
		isUserInteractionEnabled = false

		artView.contentMode = .scaleAspectFill
		artView.clipsToBounds = true
		artView.alpha = 0
		artView.translatesAutoresizingMaskIntoConstraints = false
		addSubview(artView)
		layer.addSublayer(fadeLayer)
		layer.addSublayer(statusScrimLayer)
		statusScrimLayer.isHidden = true
		// 渐隐成纸色只为大图收尾：没有图时这层会盖在天幕纹路上、并在大图区下沿切出一道硬边（2026-09-29 真机截图）
		fadeLayer.opacity = 0
		updateFadeColors()

		eyebrowLabel.attributedText = eyebrow.map { Babel2HeroEyebrow.attributed($0) }
		eyebrowLabel.isHidden = eyebrow == nil
		eyebrowLabel.numberOfLines = 1
		eyebrowLabel.lineBreakMode = .byTruncatingTail
		eyebrowLabel.accessibilityIdentifier = "babel2.feed.eyebrow"
		eyebrowLabel.translatesAutoresizingMaskIntoConstraints = false

		titleLabel.text = title
		titleLabel.font = Babel2Type.heroTitle
		titleLabel.textColor = BabelPalette.ink
		titleLabel.numberOfLines = 1
		titleLabel.lineBreakMode = .byTruncatingTail
		titleLabel.adjustsFontSizeToFitWidth = true
		titleLabel.minimumScaleFactor = 0.75
		// 只占位：看得见、读屏读到的是窄栏里那个会缩放归位的标题
		titleLabel.alpha = 0
		titleLabel.isAccessibilityElement = false
		titleLabel.translatesAutoresizingMaskIntoConstraints = false

		countLabel.font = .systemFont(ofSize: 13, weight: .medium)
		countLabel.textColor = BabelPalette.tertiaryInk
		countLabel.accessibilityIdentifier = "babel2.feed.count"
		countLabel.translatesAutoresizingMaskIntoConstraints = false

		[eyebrowLabel, titleLabel, countLabel].forEach(addSubview)

		NSLayoutConstraint.activate([
			artView.leadingAnchor.constraint(equalTo: leadingAnchor),
			artView.trailingAnchor.constraint(equalTo: trailingAnchor),
			artView.topAnchor.constraint(equalTo: topAnchor),
			artView.bottomAnchor.constraint(equalTo: bottomAnchor),

			titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
			titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -20),
			titleLabel.bottomAnchor.constraint(equalTo: countLabel.topAnchor, constant: -2),
			eyebrowLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
			eyebrowLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -20),
			eyebrowLabel.bottomAnchor.constraint(equalTo: titleLabel.topAnchor, constant: -3),
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
		statusScrimLayer.frame = CGRect(x: 0, y: 0, width: bounds.width, height: safeAreaInsets.top + 12)
		CATransaction.commit()
		// 渐隐层压在底图之上、文字与按钮之下
		layer.insertSublayer(fadeLayer, above: artView.layer)
		layer.insertSublayer(statusScrimLayer, above: fadeLayer)
		onLayout?()
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
			self.statusScrimLayer.isHidden = false
			let show = {
				self.artView.alpha = Self.artAlpha * Babel2FeedHeroMotion.heroContentAlpha(self.progress)
				self.updateArtDependentAlpha()
			}
			if animated {
				Babel2Motion.animate(Babel2Motion.page, show)
			} else {
				show()
			}
		}
	}

	/// 恢复默认图标后没有高清图可用：图淡出，回到纯纸色底（ADR-046）。
	func clearArt(animated: Bool) {
		artTask?.cancel()
		guard artView.image != nil else { return }
		guard animated else {
			artView.alpha = 0
			artView.image = nil
			statusScrimLayer.isHidden = true
			updateArtDependentAlpha()
			return
		}
		// 先按「没有图」算纹路与眉题的透明度，与图的淡出一起过渡
		isClearingArt = true
		Babel2Motion.animate(Babel2Motion.standard, {
			self.artView.alpha = 0
			self.updateArtDependentAlpha()
		}, completion: { _ in
			self.isClearingArt = false
			if self.artView.alpha == 0 {
				self.artView.image = nil
				self.statusScrimLayer.isHidden = true
			}
		})
	}

	/// 按收缩进度更新：整体上移 70pt × 进度，图淡出、大标题更快淡出。只改平移与透明度，不重新排版。
	func apply(progress newProgress: CGFloat) {
		progress = newProgress
		transform = CGAffineTransform(translationX: 0, y: -Babel2FeedHeroMotion.collapseDistance * newProgress)
		if artView.image != nil {
			artView.alpha = Self.artAlpha * Babel2FeedHeroMotion.heroContentAlpha(newProgress)
		}
		countLabel.alpha = Babel2FeedHeroMotion.heroTitleAlpha(newProgress)
		updateArtDependentAlpha()
	}

	/// 正在淡出大图（恢复默认图标）：这期间按「没有图」处理纹路与眉题。
	private var isClearingArt = false
	private var showsArt: Bool { artView.image != nil && !isClearingArt }

	/// 眉题与篇数同进退；有大图时眉题不显示。有没有图变了就告诉列表页。
	private func updateArtDependentAlpha() {
		eyebrowLabel.alpha = showsArt ? 0 : Babel2FeedHeroMotion.heroTitleAlpha(progress)
		fadeLayer.opacity = showsArt ? 1 : 0
		if showsArt != lastReportedShowsArt {
			lastReportedShowsArt = showsArt
			onArtShownChanged?(showsArt)
		}
	}

	/// 现在有没有大图（正在淡出的不算）。
	var isShowingArt: Bool { showsArt }

	/// 仅供自动化测试。
	var eyebrowTextForTesting: String? { eyebrowLabel.isHidden ? nil : eyebrowLabel.attributedText?.string }
	var eyebrowAlphaForTesting: CGFloat { eyebrowLabel.alpha }

	/// 图完全不透明：要让人看清订阅源的图。
	private static let artAlpha: CGFloat = 1

	/// 渐隐：上半部分完全是原图；约 55% 处开始、80% 处基本变成纸色（标题落在这里），底边完全是纸色（与列表无缝）。
	private func updateFadeColors() {
		let paper = BabelPalette.background.resolvedColor(with: traitCollection)
		fadeLayer.colors = [0, 0, 0.85, 1].map { paper.withAlphaComponent($0).cgColor }
		fadeLayer.locations = [0, 0.55, 0.8, 1]
		statusScrimLayer.colors = [0.72, 0.4, 0].map { paper.withAlphaComponent($0).cgColor }
		statusScrimLayer.locations = [0, 0.6, 1]
	}
}

/// 收缩后的窄栏（Figma 03C「Feed Hero / Compact Sticky」，ADR-027 保留「小图标 + 名字」）：
/// 从屏幕最顶端到安全区下方 99pt；纸色底随收缩进度变为完全不透明；
/// 第二行 26pt 圆形小图标（x=20）+ 订阅源名 16pt 半粗（x=56）在后半程淡入。
/// ADR-067（用户 2026-09-28 选「去圆圈，细线换阴影」）：没有真实图标时（跨源列表、图标还没到的源）
/// 不再画「首字母圆圈」，名字左移到 x=20。
/// ADR-068（用户 2026-09-28 选「天幕」+ 22pt）：
/// - 标题住在这里、全程可见：静止时摆在大图标题的位置（27pt），随收缩缩放归位到第二行（22pt）。
/// - 天幕（没有大图时，usesSky）：窄栏没有底色、没有下沿，右侧显示列表当前滑到的日期（「今天 / 昨天」）。
/// - 有大图时：纸色底照旧随收缩变不透明，下沿是一道纸色渐隐（Babel2SoftEdgeView，取代黑色阴影）。
/// 返回按钮与右上角放大镜（Figma 搜索位 x=330）在这一层、全程不动。除这些控件外不拦截触摸（拖动照样滚动列表）。
/// 搜索时第二行换成搜索框 +「取消」，纸色底完全不透明。
final class Babel2FeedCompactBar: UIView {
	let backButton = UIButton(type: .system)
	let searchButton = UIButton(type: .system)
	/// 刷新（Figma 刷新位 x=201）：浅色圆盘 + 逆时针箭头，同步时旋转（复用首页同步图标）。ADR-031。
	let refreshButton = UIButton(type: .system)
	/// 外面已经有毛玻璃圆底：图形自带的灰色圆底关掉（2026-09-27 用户：圈外套圈，重复；收起后毛玻璃圆底淡出，
	/// 自带的灰圆却还在，四个按钮里只有它有底色）
	private let refreshGlyph = Babel2SyncSpinner(showsBackground: false)
	/// 更多（Figma 更多位 x=370）：点按弹出本订阅源的操作菜单。ADR-031。
	let moreButton = UIButton(type: .system)
	let searchField: Babel2FeedSearchField
	private(set) var isSearching = false
	/// 返回 / 刷新 / 放大镜 / 更多下面的毛玻璃圆底（直径 36pt）：大图上按钮不会被深色图吞掉（2026-09-25 用户截图）。
	/// 随收缩进度淡出——收起后窄栏本身是不透明纸色，不需要圆底。
	private var glassDiscs = [UIView]()
	/// 仅供自动化测试。
	var glassDiscAlphaForTesting: CGFloat { glassDiscs.first?.alpha ?? 0 }
	let titleLabel = UILabel()
	/// 天幕时右侧的日期（列表当前滑到哪一天）
	private let dayLabel = UILabel()
	/// 大图区里那个只占位的标题：静止时这里的标题要摆到它的位置（缩放归位的起点）。
	weak var restTitleLabel: UILabel?
	/// 没有大图 = 天幕（ADR-068）。由列表页随大图有无切换。
	var usesSky = true {
		didSet { if usesSky != oldValue { apply(progress: lastProgress) } }
	}
	private var lastProgress: CGFloat = 0
	private let backdrop = UIView()
	private let iconView = UIImageView()
	/// 下沿的纸色渐隐（只在有大图时）；日期段标题吸顶时挪到段标题下沿（edgeOffset）。
	private let edge = Babel2SoftEdgeView()
	private var edgeTop: NSLayoutConstraint!
	/// 名字的左边：有图标时让出图标（56），没有时贴左（20）。
	private var titleLeadingWithIcon: NSLayoutConstraint!
	private var titleLeadingPlain: NSLayoutConstraint!
	/// 仅供自动化测试观察：纸色底的不透明度（1 = 完全不透明）。
	var backdropAlphaForTesting: CGFloat { backdrop.alpha }
	var edgeAlphaForTesting: CGFloat { edge.alpha }
	var edgeOffsetForTesting: CGFloat { edgeTop.constant }
	/// 第二行（收起后）标题的左边：按排版位置，不含缩放归位的 transform。
	var titleMinXForTesting: CGFloat { titleLabel.center.x - titleLabel.bounds.width / 2 }
	/// 标题此刻在屏幕上的外框（含 transform）。
	var visibleTitleFrameForTesting: CGRect { titleLabel.frame }
	var dayTextForTesting: String? { dayLabel.alpha > 0.01 ? dayLabel.text : nil }
	/// 标题此刻看起来的字号（缩放后）。
	var visibleTitlePointSizeForTesting: CGFloat { titleLabel.font.pointSize * titleLabel.transform.a }

	/// 天幕右侧的日期：nil = 不显示。
	func setDay(_ text: String?, alpha: CGFloat) {
		if dayLabel.text != text { dayLabel.text = text }
		dayLabel.alpha = text == nil || isSearching ? 0 : alpha
	}

	/// 图标晚到时补上（ADR-039）；没有图标时不占位（ADR-067）。
	func setIcon(_ icon: UIImage?) {
		iconView.image = icon
		iconView.isHidden = icon == nil || isSearching
		titleLeadingWithIcon.isActive = icon != nil
		titleLeadingPlain.isActive = icon == nil
	}

	/// 阴影挂在哪：0 = 窄栏下沿；日期段标题吸在窄栏下面时挂到段标题下沿，整块顶栏只有一道阴影。
	func setEdgeOffset(_ offset: CGFloat) {
		guard edgeTop.constant != offset else { return }
		edgeTop.constant = offset
	}

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

		backButton.setImage(Babel2Icon.back.image(size: Babel2Icon.Size.top), for: .normal)
		backButton.tintColor = BabelPalette.ink
		backButton.accessibilityLabel = "Back"
		backButton.accessibilityIdentifier = "babel2.feed.back"
		backButton.translatesAutoresizingMaskIntoConstraints = false

		iconView.image = icon
		iconView.isHidden = icon == nil
		iconView.contentMode = .scaleAspectFill
		iconView.clipsToBounds = true
		iconView.layer.cornerRadius = 13
		iconView.layer.borderWidth = 0.75
		iconView.layer.borderColor = UIColor(red: 209 / 255, green: 209 / 255, blue: 204 / 255, alpha: 0.42).cgColor
		iconView.alpha = 0
		iconView.translatesAutoresizingMaskIntoConstraints = false

		// 以大标题的字号排版，收起时按比例缩到 22pt（缩小比放大清楚）
		titleLabel.text = title
		titleLabel.font = Babel2Type.heroTitle
		titleLabel.textColor = BabelPalette.ink
		titleLabel.lineBreakMode = .byTruncatingTail
		titleLabel.accessibilityIdentifier = "babel2.feed.title"
		titleLabel.accessibilityTraits = .header
		titleLabel.translatesAutoresizingMaskIntoConstraints = false

		dayLabel.font = Babel2Type.dayHeader
		dayLabel.textColor = BabelPalette.tertiaryInk
		dayLabel.textAlignment = .right
		dayLabel.alpha = 0
		dayLabel.accessibilityIdentifier = "babel2.feed.compact-day"
		dayLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
		dayLabel.translatesAutoresizingMaskIntoConstraints = false

		edge.alpha = 0
		edge.translatesAutoresizingMaskIntoConstraints = false

		searchButton.setImage(Babel2Icon.search.image(size: Babel2Icon.Size.top), for: .normal)
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
		moreButton.setImage(Babel2Icon.more.image(size: Babel2Icon.Size.top), for: .normal)
		moreButton.tintColor = BabelPalette.ink
		moreButton.accessibilityLabel = Babel2Localization.text(.more)
		moreButton.accessibilityIdentifier = "babel2.feed.more"
		moreButton.translatesAutoresizingMaskIntoConstraints = false
		// 按压反馈（ADR-034）：图标在毛玻璃圆底里轻轻缩一下
		[backButton, refreshButton, searchButton, moreButton].forEach(Babel2Motion.addPressFeedback)

		// 圆底先加（在按钮下面）
		for _ in 0..<4 {
			let disc = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
			disc.isUserInteractionEnabled = false
			disc.layer.cornerRadius = 18
			disc.clipsToBounds = true
			disc.translatesAutoresizingMaskIntoConstraints = false
			addSubview(disc)
			glassDiscs.append(disc)
		}
		[backButton, searchButton, refreshButton, moreButton, iconView, titleLabel, dayLabel, edge, searchField].forEach(addSubview)
		for (disc, button) in zip(glassDiscs, [backButton, refreshButton, searchButton, moreButton]) {
			NSLayoutConstraint.activate([
				disc.centerXAnchor.constraint(equalTo: button.centerXAnchor),
				disc.centerYAnchor.constraint(equalTo: button.centerYAnchor),
				disc.widthAnchor.constraint(equalToConstant: 36),
				disc.heightAnchor.constraint(equalToConstant: 36)
			])
		}
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

			titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: dayLabel.leadingAnchor, constant: -12),
			titleLabel.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),
			dayLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
			dayLabel.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),

			// 渐隐挂在窄栏外、往下（窄栏不裁切子视图；不接收触摸）
			edge.leadingAnchor.constraint(equalTo: leadingAnchor),
			edge.trailingAnchor.constraint(equalTo: trailingAnchor),
			edge.heightAnchor.constraint(equalToConstant: Babel2SoftEdgeView.height)
		])
		edgeTop = edge.topAnchor.constraint(equalTo: bottomAnchor)
		edgeTop.isActive = true
		titleLeadingWithIcon = titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 56)
		titleLeadingPlain = titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20)
		titleLeadingWithIcon.isActive = icon != nil
		titleLeadingPlain.isActive = icon == nil
	}

	required init?(coder: NSCoder) { nil }

	/// 进入 / 退出搜索：第二行在「小图标 + 名字」与搜索框之间切换；搜索时放大镜隐藏。
	func setSearching(_ searching: Bool) {
		isSearching = searching
		searchField.isHidden = !searching
		searchButton.isHidden = searching
		refreshButton.isHidden = searching
		moreButton.isHidden = searching
		updateDiscVisibility()
		iconView.isHidden = searching || iconView.image == nil
		titleLabel.isHidden = searching
		dayLabel.isHidden = searching
		if searching {
			apply(progress: 1)
		} else {
			searchField.clear()
			searchField.textField.resignFirstResponder()
		}
	}

	private var discProgress: CGFloat = 0

	/// 圆底跟着各自的按钮显示 / 隐藏，并随收缩进度淡出。
	func updateDiscVisibility() {
		for (disc, button) in zip(glassDiscs, [backButton, refreshButton, searchButton, moreButton]) {
			disc.isHidden = button.isHidden
			disc.alpha = 1 - discProgress
		}
	}

	/// 同步中：刷新箭头旋转；不同步时静止显示（首页的同一图标不同步时会自己隐藏，这里要一直可见）。
	func setSyncing(_ syncing: Bool) {
		refreshGlyph.setSpinning(syncing)
		refreshButton.accessibilityValue = syncing ? Babel2Localization.text(.syncing) : nil
	}

	/// 仅供自动化测试。
	var isShowingSyncingForTesting: Bool { refreshButton.accessibilityValue != nil }
	var refreshGlyphForTesting: Babel2SyncSpinner { refreshGlyph }

	/// 按收缩进度更新透明度与标题的位置 / 大小（只改 transform，不重新排版）。
	func apply(progress: CGFloat) {
		lastProgress = progress
		discProgress = progress
		updateDiscVisibility()
		// 天幕：没有底色、没有下沿；有大图或正在搜索：纸色底 + 纸色渐隐
		let solid = !usesSky || isSearching
		backdrop.alpha = solid ? Babel2FeedHeroMotion.compactBackgroundAlpha(progress) : 0
		edge.alpha = solid ? progress : 0
		iconView.alpha = Babel2FeedHeroMotion.compactContentAlpha(progress)
		titleLabel.transform = titleTransform(progress: progress)
	}

	/// 缩放归位：进度 0 时摆在大图标题的位置、原大（27pt）；进度 1 时回到第二行、缩到 22pt。
	/// 以左边缘为准缩放（缩放绕中心，所以再往左补回宽度缩掉的一半）。
	private func titleTransform(progress: CGFloat) -> CGAffineTransform {
		let finalScale = Babel2Type.compactTitle.pointSize / Babel2Type.heroTitle.pointSize
		let scale = 1 + (finalScale - 1) * progress
		let offset = restTitleOffset()
		let x = offset.x * (1 - progress) - titleLabel.bounds.width * (1 - scale) / 2
		let y = offset.y * (1 - progress)
		return CGAffineTransform(translationX: x, y: y).scaledBy(x: scale, y: scale)
	}

	/// 大图标题静止时相对第二行标题的位移（两边都按不含 transform 的位置算）。
	private func restTitleOffset() -> CGPoint {
		guard let rest = restTitleLabel, let host = rest.superview else { return .zero }
		let hostOrigin = CGPoint(x: host.center.x - host.bounds.width / 2, y: host.center.y - host.bounds.height / 2)
		let selfOrigin = CGPoint(x: center.x - bounds.width / 2, y: center.y - bounds.height / 2)
		let restFrame = rest.frame.offsetBy(dx: hostOrigin.x, dy: hostOrigin.y)
		// 标题自己带着 transform，frame 是变形后的外框，用 center + bounds 取排版位置
		let mine = CGRect(x: titleLabel.center.x - titleLabel.bounds.width / 2 + selfOrigin.x,
			y: titleLabel.center.y - titleLabel.bounds.height / 2 + selfOrigin.y,
			width: titleLabel.bounds.width, height: titleLabel.bounds.height)
		return CGPoint(x: restFrame.minX - mine.minX, y: restFrame.midY - mine.midY)
	}

	override func layoutSubviews() {
		super.layoutSubviews()
		refreshTitlePosition()
	}

	/// 名字变了、图标到了、屏幕尺寸变了、大图区排好了：按新的排版重算标题位置。
	func refreshTitlePosition() {
		titleLabel.transform = titleTransform(progress: lastProgress)
	}

	/// 只有返回、放大镜、搜索框接收触摸；其余位置交给下面的列表（从顶部开始拖也能滚动）。
	/// 搜索时整条窄栏都接收（它是完全不透明的顶栏）。
	override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
		if isSearching { return bounds.contains(point) }
		return [backButton, searchButton, refreshButton, moreButton].contains { !$0.isHidden && $0.frame.insetBy(dx: -4, dy: -4).contains(point) }
	}
}
