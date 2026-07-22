//
//  TimelineFeedHeader.swift
//  NetNewsWire — AI 翻译 fork
//
//  [外观] 单一订阅源的文章列表页,顶部约 1/4 屏的「源头部区」:
//
//  ┌────────────────────────────┐
//  │   (氛围背景:logo 放大铺满 + 重度模糊       │
//  │    + 纸色蒙层,底部渐变融入列表背景)        │
//  │        ┌────────┐          │
//  │        │ 清晰 logo │  ← 偏上,居中     │
//  │        └────────┘          │
//  │     Essays - Benedict Evans   ← 偏下,居中 │
//  ├────────────────────────────┤
//  │  文章行从这里开始……                │
//  └────────────────────────────┘
//
//  这是水印方案(2026-07-22 上午)被用户否掉后的第二版:
//  「太浅、太糊」→ 改为专属头部区 + 清晰小 logo + 高清抓取(FeedHeroIconLoader)。
//  背景氛围层反而**要**重度模糊 —— 模糊是手法而不是缺陷,低分辨率在这层无所谓。
//
//  交互(和用户确认的设计一致):
//  - 只有「单一订阅源」页显示;文件夹 / 今天 / 未读 / 星标完全不变(保留系统大标题)
//  - 单源页隐藏系统大标题(标题改由头部区自己画);往下滚动时头部渐隐,
//    滚过一段后导航栏顶部淡入小标题(和 Apple Music 的行为一致)
//  - 列表内容整体下移,从头部区底边开始 —— 这是「让出来」而不是「垫在下面」
//
//  工程要点:
//  - 头部装在 collectionView.backgroundView 上;内容下移靠 contentInset.top,
//    装卸都记账(appliedInset),不会越叠越高
//  - 系统大标题的显隐用 navigationItem.largeTitleDisplayMode 切换(.never / .automatic),
//    这是标准 API,在我们自己的代码里做,上游零改动
//  - 上游唯一钩子仍是 updateNavigationBarTitle 里那一行(切源必经之地)
//  - 深浅色都支持:氛围背景是烘焙位图,颜色外观变化时重新烘焙一次
//
//  这个文件不属于上游 NetNewsWire,是本 fork 新增的。
//

import UIKit
import os
import Account
import Images
import HTMLMetadata

// MARK: - 装到时间线控制器上的入口

extension MainTimelineModernViewController {

	private static var nnwHeaderKey: UInt8 = 0

	/// 每次时间线切换订阅源时调用(挂在 updateNavigationBarTitle 里 —— 那是切源的必经之地)。
	/// 单一订阅源 → 装/换头部区;文件夹、智能源、搜索等 → 摘掉头部区、恢复系统大标题。
	func nnwUpdateFeedHeader() {
		guard TimelineStyle.headerEnabled, let collectionView else { return }

		let controller: TimelineFeedHeaderController
		if let existing = objc_getAssociatedObject(self, &Self.nnwHeaderKey) as? TimelineFeedHeaderController {
			controller = existing
		} else {
			controller = TimelineFeedHeaderController()
			objc_setAssociatedObject(self, &Self.nnwHeaderKey, controller, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
		}

		let feed = coordinator?.timelineFeed as? Feed
		controller.update(feed: feed, collectionView: collectionView, navigationItem: navigationItem)
	}
}

// MARK: - 头部区管理器

@MainActor final class TimelineFeedHeaderController: NSObject {

	private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "TimelineFeedHeader")

	private weak var collectionView: UICollectionView?
	private weak var navigationItem: UINavigationItem?
	private weak var currentFeed: Feed?

	private let headerView = TimelineFeedHeaderView()

	/// 已渲染的内容标识(feedID + 明暗),避免重复渲染
	private var renderedKey: String?
	/// 我们往 contentInset.top 里加过多少,卸载/调整时按这个数还,绝不越叠越高
	private var appliedInset: CGFloat = 0
	/// 上一次装好的 feedID —— 用来判断「换了源」(要滚回顶部)还是「同源重进」(保持滚动位置)
	private var installedFeedID: String?
	/// 导航栏小标题当前是否显示着(滚动联动用,避免每帧都写 navigationItem)
	private var navTitleShown = false

	private var offsetObservation: NSKeyValueObservation?

	override init() {
		super.init()
		// 图标可能晚于页面到货:到货后如果头部还空着,补装一次(照抄时间线自己刷新图标的那组通知)
		let names: [Notification.Name] = [
			.feedIconDidBecomeAvailable,
			.FaviconDidBecomeAvailable,
			.imageDidBecomeAvailable,
			.htmlMetadataAvailable
		]
		for name in names {
			NotificationCenter.default.addObserver(self, selector: #selector(iconMightBeAvailable(_:)), name: name, object: nil)
		}
		// 明暗切换 → 氛围背景要按新纸色重新烘焙
		headerView.onAppearanceChange = { [weak self] in
			self?.renderedKey = nil
			self?.refresh()
		}
		// 头部尺寸/安全区变化(转屏等)→ 重新对 contentInset
		headerView.onLayout = { [weak self] in
			self?.syncInset()
		}
	}

	// MARK: 装 / 卸

	func update(feed: Feed?, collectionView: UICollectionView, navigationItem: UINavigationItem) {
		self.collectionView = collectionView
		self.navigationItem = navigationItem
		self.currentFeed = feed

		guard let feed else {
			remove()
			return
		}

		// —— 单一订阅源:接管顶部 ——

		// 1. 隐藏系统大标题(标题改由头部区画);滚动后的小标题由 applyScrollLinkage 控制
		navigationItem.largeTitleDisplayMode = .never
		navigationItem.title = nil
		navTitleShown = false

		// 2. 装容器
		if collectionView.backgroundView !== headerView {
			collectionView.backgroundView = headerView
		}
		observeScrollIfNeeded(collectionView)

		// 3. 头部高度 = 屏高 × 比例(装完由 syncInset 把内容推下去)
		headerView.headerHeight = (collectionView.window?.bounds.height ?? UIScreen.main.bounds.height) * TimelineStyle.headerHeightFraction
		syncInset()

		// 4. 换源时滚回顶部,让头部完整亮相;同源重进(返回)保持原位
		let switched = (installedFeedID != feed.feedID)
		installedFeedID = feed.feedID
		if switched {
			collectionView.setContentOffset(CGPoint(x: 0, y: -collectionView.adjustedContentInset.top), animated: false)
		}

		render(feed: feed)
		applyScrollLinkage()
	}

	private func remove() {
		guard let collectionView else { return }
		if collectionView.backgroundView === headerView {
			collectionView.backgroundView = nil
		}
		if appliedInset != 0 {
			collectionView.contentInset.top -= appliedInset
			appliedInset = 0
		}
		// 恢复系统大标题(上游 updateNavigationBarTitle 刚设过 title,别动它)
		navigationItem?.largeTitleDisplayMode = .automatic
		renderedKey = nil
		installedFeedID = nil
		navTitleShown = false
	}

	/// 供通知/明暗变化后重新渲染(源和列表都不变时)
	private func refresh() {
		guard let feed = currentFeed, let collectionView, let navigationItem else { return }
		update(feed: feed, collectionView: collectionView, navigationItem: navigationItem)
	}

	// MARK: 内容下移(contentInset 记账)

	private func syncInset() {
		guard let collectionView else { return }
		// 目标:列表内容从头部区底边开始。safe area(状态栏+导航条)本身就占掉一段,
		// 只需要补齐差额。带记账,重复调用不会越加越多。
		let safeTop = collectionView.safeAreaInsets.top
		let target = max(0, headerView.headerHeight - safeTop)
		guard abs(target - appliedInset) > 0.5 else { return }
		collectionView.contentInset.top += (target - appliedInset)
		appliedInset = target
	}

	// MARK: 渲染

	private func render(feed: Feed) {
		let style: String = headerView.traitCollection.userInterfaceStyle == .dark ? "dark" : "light"
		let key = feed.feedID + "|" + style
		if renderedKey == key { return }

		headerView.titleLabel.text = feed.nameForDisplay

		// logo:优先高清(FeedHeroIconLoader),暂时没有就先用上游 144px 的顶着,
		// 同时发起高清抓取,到货后重渲染换上
		let smallIcon = IconImageCache.shared.imageForFeed(feed)?.image
		let hero = FeedHeroIconLoader.shared.cachedHero(for: feed)
		let logo = hero ?? smallIcon

		if hero == nil {
			FeedHeroIconLoader.shared.fetchHeroIfNeeded(for: feed) { [weak self] _ in
				guard let self, self.currentFeed?.feedID == feed.feedID else { return }
				self.renderedKey = nil
				self.refresh()
			}
		}

		guard let logo else {
			// 连小图都还没有:先画个只有标题的头部,等「图标就绪」通知来补
			Self.logger.info("[头图] 源「\(feed.nameForDisplay, privacy: .public)」暂时没有任何图标,先只显示标题")
			headerView.logoImageView.image = nil
			headerView.backgroundImageView.image = nil
			renderedKey = nil
			return
		}

		headerView.logoImageView.image = logo
		headerView.backgroundImageView.image = Self.makeAmbientBackground(
			from: logo,
			size: CGSize(width: headerView.bounds.width > 0 ? headerView.bounds.width : UIScreen.main.bounds.width,
						 height: max(headerView.headerHeight, 1)),
			traits: headerView.traitCollection
		)
		headerView.setNeedsLayout()
		renderedKey = key

		let pxW = Int(logo.size.width * logo.scale)
		Self.logger.info("""
			[头图] 已装:源「\(feed.nameForDisplay, privacy: .public)」\
			logo 素材 \(pxW)px(\(hero != nil ? "高清" : "144 兜底", privacy: .public));\
			头部高 \(Int(self.headerView.headerHeight))pt,inset \(Int(self.appliedInset))pt
			""")
	}

	/// 氛围背景:logo 放大铺满 → 重度高斯模糊 → 纸色蒙层压淡 → 底部渐变到纯纸色(与列表无缝)。
	/// 一次性烘焙成位图。模糊层不在乎素材分辨率 —— 反正要糊,糊就是这一层的本分。
	/// (拆成三个小函数是给 Swift 类型检查器减负 —— 整段写在一起会超时,编译器直接报错。)
	static func makeAmbientBackground(from source: UIImage, size: CGSize, traits: UITraitCollection) -> UIImage? {
		guard size.width > 1, size.height > 1 else { return nil }
		let paper: UIColor = AppAppearance.paperBackground.resolvedColor(with: traits)
		let filled: UIImage = drawAspectFilled(source: source, size: size, paper: paper)
		let blurred: UIImage = softBlurred(filled)
		return compositeVeilAndFade(over: blurred, size: size, paper: paper)
	}

	/// 第一步:aspectFill 缩放进头部尺寸,先落成位图
	private static func drawAspectFilled(source: UIImage, size: CGSize, paper: UIColor) -> UIImage {
		let sourceW: CGFloat = max(source.size.width, 1)
		let sourceH: CGFloat = max(source.size.height, 1)
		let fillScale: CGFloat = max(size.width / sourceW, size.height / sourceH)
		let drawW: CGFloat = sourceW * fillScale
		let drawH: CGFloat = sourceH * fillScale
		let drawX: CGFloat = (size.width - drawW) / 2.0
		let drawY: CGFloat = (size.height - drawH) / 2.0

		let format = UIGraphicsImageRendererFormat()
		format.opaque = true
		let renderer = UIGraphicsImageRenderer(size: size, format: format)
		return renderer.image { (ctx: UIGraphicsImageRendererContext) in
			paper.setFill()
			ctx.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height))
			source.draw(in: CGRect(x: drawX, y: drawY, width: drawW, height: drawH))
		}
	}

	/// 第二步:模糊。手法是「缩到十几个像素再放大」—— 细节被压缩掉,
	/// 放大时的高质量插值把残留信息抹成一片柔和色晕,效果上等价于重度高斯模糊。
	/// ⚠️ 刻意**不用 CoreImage**:本工程开着「警告当错误 + 表达式类型检查限时 1 秒」,
	/// 而 CIImage/CIFilter 的初始化器重载多到让类型检查直接超时报错,实测连换三种写法都过不去。
	private static func softBlurred(_ input: UIImage) -> UIImage {
		let tinyWidth: CGFloat = max(TimelineStyle.headerAmbientDownsampleWidth, 2)
		guard input.size.width > tinyWidth else { return input }
		let aspect: CGFloat = input.size.height / max(input.size.width, 1)
		let tinySize = CGSize(width: tinyWidth, height: max(tinyWidth * aspect, 2))

		let tinyFormat = UIGraphicsImageRendererFormat()
		tinyFormat.scale = 1
		tinyFormat.opaque = true
		let tinyRenderer = UIGraphicsImageRenderer(size: tinySize, format: tinyFormat)
		let tiny = tinyRenderer.image { (ctx: UIGraphicsImageRendererContext) in
			ctx.cgContext.interpolationQuality = .high
			input.draw(in: CGRect(x: 0, y: 0, width: tinySize.width, height: tinySize.height))
		}

		let bigFormat = UIGraphicsImageRendererFormat()
		bigFormat.opaque = true
		let bigRenderer = UIGraphicsImageRenderer(size: input.size, format: bigFormat)
		return bigRenderer.image { (ctx: UIGraphicsImageRendererContext) in
			ctx.cgContext.interpolationQuality = .high
			tiny.draw(in: CGRect(x: 0, y: 0, width: input.size.width, height: input.size.height))
		}
	}

	/// 第三步:纸色蒙层 + 底部渐变融入列表
	private static func compositeVeilAndFade(over blurred: UIImage, size: CGSize, paper: UIColor) -> UIImage {
		let veil: UIColor = paper.withAlphaComponent(TimelineStyle.headerAmbientVeilAlpha)
		let clearPaper: CGColor = paper.withAlphaComponent(0).cgColor
		let solidPaper: CGColor = paper.cgColor
		let colors: CFArray = [clearPaper, solidPaper] as CFArray
		let locations: [CGFloat] = [0, 1]
		let fadeStartY: CGFloat = size.height * TimelineStyle.headerAmbientFadeStart

		let format = UIGraphicsImageRendererFormat()
		format.opaque = true
		let renderer = UIGraphicsImageRenderer(size: size, format: format)
		return renderer.image { (ctx: UIGraphicsImageRendererContext) in
			blurred.draw(in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
			veil.setFill()
			ctx.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height))
			if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: locations) {
				ctx.cgContext.drawLinearGradient(
					gradient,
					start: CGPoint(x: 0, y: fadeStartY),
					end: CGPoint(x: 0, y: size.height),
					options: [.drawsAfterEndLocation]
				)
			}
		}
	}

	// MARK: 滚动联动(头部渐隐 + 导航栏小标题淡入)

	private func observeScrollIfNeeded(_ collectionView: UICollectionView) {
		guard offsetObservation == nil else { return }
		offsetObservation = collectionView.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in
			MainActor.assumeIsolated {
				self?.applyScrollLinkage()
			}
		}
	}

	private func applyScrollLinkage() {
		guard let collectionView, currentFeed != nil else { return }
		let restY = -collectionView.adjustedContentInset.top
		let progress = (collectionView.contentOffset.y - restY) / TimelineStyle.headerScrollFadeDistance
		let clamped = min(max(progress, 0), 1)
		headerView.contentAlpha = 1 - clamped

		// 滚过大半后,导航栏顶部淡入源名(Apple Music 的行为);滚回来再收掉
		let shouldShowNavTitle = clamped > 0.85
		if shouldShowNavTitle != navTitleShown {
			navTitleShown = shouldShowNavTitle
			navigationItem?.title = shouldShowNavTitle ? currentFeed?.nameForDisplay : nil
		}
	}

	// MARK: 图标迟到的补装

	@objc private func iconMightBeAvailable(_ note: Notification) {
		guard renderedKey == nil, currentFeed != nil else { return }
		refresh()
	}
}

// MARK: - 头部视图(布局 + 明暗监听)

@MainActor final class TimelineFeedHeaderView: UIView {

	let backgroundImageView = UIImageView()
	let logoImageView = UIImageView()
	let titleLabel = UILabel()

	/// 头部区总高(从屏幕顶算),由控制器设置
	var headerHeight: CGFloat = 0 {
		didSet { setNeedsLayout() }
	}

	var onAppearanceChange: (() -> Void)?
	var onLayout: (() -> Void)?

	/// 滚动渐隐只作用于头部内容,不影响容器本身
	var contentAlpha: CGFloat = 1 {
		didSet {
			backgroundImageView.alpha = contentAlpha
			logoImageView.alpha = contentAlpha
			titleLabel.alpha = contentAlpha
		}
	}

	override init(frame: CGRect) {
		super.init(frame: frame)
		backgroundColor = .clear
		isUserInteractionEnabled = false	// 纯装饰,不挡点按
		clipsToBounds = true

		backgroundImageView.contentMode = .scaleToFill
		addSubview(backgroundImageView)

		logoImageView.contentMode = .scaleAspectFill
		logoImageView.clipsToBounds = true
		logoImageView.layer.cornerCurve = .continuous
		// 细描边:白底 logo 不至于融进背景里没有边界
		logoImageView.layer.borderWidth = 0.5
		addSubview(logoImageView)

		titleLabel.font = .preferredFont(forTextStyle: .title1).bold()
		titleLabel.adjustsFontSizeToFitWidth = true
		titleLabel.minimumScaleFactor = 0.7
		titleLabel.textAlignment = .center
		titleLabel.numberOfLines = 1
		titleLabel.textColor = .label
		addSubview(titleLabel)

		updateBorderColor()
		registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: TimelineFeedHeaderView, _) in
			view.updateBorderColor()
			view.onAppearanceChange?()
		}
	}

	required init?(coder: NSCoder) {
		fatalError("不从 storyboard 创建")
	}

	private func updateBorderColor() {
		logoImageView.layer.borderColor = UIColor.label.withAlphaComponent(0.12).cgColor
	}

	override func layoutSubviews() {
		super.layoutSubviews()

		backgroundImageView.frame = CGRect(x: 0, y: 0, width: bounds.width, height: headerHeight)

		// 可用区:状态栏/灵动岛以下、头部底边以上。
		// ⚠️ 这里要用 window 的安全区,不能用自己的 —— 本视图是 collectionView 的
		// backgroundView,系统不给它传正确的 safeAreaInsets(实测拿到 0,
		// logo 会顶到灵动岛底下)。window 的安全区顶 = 状态栏/灵动岛,正是想要的基准:
		// 返回/筛选两个圆钮浮在左右两角,中央这条竖线是空的,logo 居中不会撞上它们。
		// logo 偏上、标题偏下(用户点名的布局),具体比例见 TimelineStyle。
		let topInset: CGFloat = window?.safeAreaInsets.top ?? safeAreaInsets.top
		let usableHeight = max(headerHeight - topInset, 1)

		let logoSize = TimelineStyle.headerLogoSize
		logoImageView.frame = CGRect(
			x: (bounds.width - logoSize) / 2,
			y: topInset + usableHeight * TimelineStyle.headerLogoTopRatio,
			width: logoSize,
			height: logoSize
		)
		logoImageView.layer.cornerRadius = logoSize * TimelineStyle.headerLogoCornerRadiusRatio

		let titleY = logoImageView.frame.maxY + TimelineStyle.headerTitleSpacing
		titleLabel.frame = CGRect(
			x: 24,
			y: titleY,
			width: bounds.width - 48,
			height: titleLabel.font.lineHeight + 4
		)

		onLayout?()
	}
}
