//
//  TimelineFeedHeader.swift
//  NetNewsWire — AI 翻译 fork
//
//  [外观] 单一订阅源的文章列表页,顶部约 1/4 屏的「源头图区」(v3):
//
//  ┌────────────────────────────┐
//  │▓▓▓▓▓▓ 图铺满全宽,越往上越浓 ▓▓▓▓▓▓│  ← 出血到屏幕边,盖住状态栏那一片
//  │▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒│  ← 整体压一层纸色蒙版,防止和页面底色撞色
//  │░░░░ Essays - Benedict Evans ░░░│  ← 标题在最下方、最淡的位置
//  ├────────────────────────────┤
//  │  文章行从这里开始……                │
//  └────────────────────────────┘
//
//  三版演进(每一版都是用户看了实物之后否掉的,记下来免得后人走回头路):
//  - v1「钢印水印」:灰度、10% 浓度、右侧出血 → 用户:「太浅、太糊,效果很差」
//  - v2「小 logo + 标题」:清晰小方图居中偏上 → 用户:「还行,但是挺丑的」
//    (病根:一个小方块孤零零摆着,像设置页的图标,没有氛围)
//  - v3(本版,用户提的方案):图拉满全宽、上浓下淡、蒙版压色、标题压在最淡处。
//    这是成熟范式(Apple Music / Spotify 艺人页),视觉重心从"一个图标"变成"一片氛围"。
//
//  两类源、一套观感(关键设计):
//  - **有合格大图**(尺寸够 且 非白底像素占比够)→ 图 aspectFill 铺满 + 适度模糊
//  - **没有合格大图**(抓不到 / 抓到的是白底 logo)→ 取 favicon 主色做纯色渐变
//    判据与主色提取见 FeedIconColorAnalyzer(白底 logo 的主色恰好是那个字的颜色,
//    所以两类源摆在一起是统一的,这正是用户要的"匹配上其他的源")
//  两条路**共用同一套合成管线**(上浓下淡 + 纸色蒙版),所以浓淡、蒙版口径天然一致。
//
//  交互:
//  - 只有「单一订阅源」页有;文件夹 / 今天 / 未读 / 星标完全不变(保留系统大标题)
//  - 单源页隐藏系统大标题(标题由头图区自己画);往下滚头图渐隐,
//    滚过一段后导航栏淡入小标题(Apple Music 行为)
//  - 列表内容从头图区底边开始(contentInset 记账,不会越叠越高)
//
//  ⚠️ 模糊**不用 CoreImage** —— 本工程开着「表达式类型检查限时 1 秒 + 警告当错误」,
//  CIImage/CIFilter 的重载会让编译直接失败(教训 L50)。用缩放法,纯 CoreGraphics。
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
	/// 单一订阅源 → 装/换头图区;文件夹、智能源、搜索等 → 摘掉头图区、恢复系统大标题。
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

// MARK: - 头图区管理器

@MainActor final class TimelineFeedHeaderController: NSObject {

	private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "TimelineFeedHeader")

	private weak var collectionView: UICollectionView?
	private weak var navigationItem: UINavigationItem?
	private weak var currentFeed: Feed?

	private let headerView = TimelineFeedHeaderView()

	/// 已渲染的内容标识(feedID + 明暗 + 宽度),避免重复渲染
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
		// 图标可能晚于页面到货:到货后如果头图还空着,补装一次(照抄时间线自己刷新图标的那组通知)
		let names: [Notification.Name] = [
			.feedIconDidBecomeAvailable,
			.FaviconDidBecomeAvailable,
			.imageDidBecomeAvailable,
			.htmlMetadataAvailable
		]
		for name in names {
			NotificationCenter.default.addObserver(self, selector: #selector(iconMightBeAvailable(_:)), name: name, object: nil)
		}
		// 明暗切换 → 头图要按新纸色重新烘焙
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

		// 1. 隐藏系统大标题(标题改由头图区画);滚动后的小标题由 applyScrollLinkage 控制
		navigationItem.largeTitleDisplayMode = .never
		navigationItem.title = nil
		navTitleShown = false

		// 2. 装容器
		if collectionView.backgroundView !== headerView {
			collectionView.backgroundView = headerView
		}
		observeScrollIfNeeded(collectionView)

		// 3. 头图高度 = 屏高 × 比例(装完由 syncInset 把内容推下去)
		let screenHeight: CGFloat = collectionView.window?.bounds.height ?? UIScreen.main.bounds.height
		headerView.headerHeight = screenHeight * TimelineStyle.headerHeightFraction
		syncInset()

		// 4. 换源时滚回顶部,让头图完整亮相;同源重进(返回)保持原位
		let switched: Bool = (installedFeedID != feed.feedID)
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
		// 目标:列表内容从头图区底边开始。safe area(状态栏+导航条)本身就占掉一段,
		// 只需要补齐差额。带记账,重复调用不会越加越多。
		let safeTop: CGFloat = collectionView.safeAreaInsets.top
		let target: CGFloat = max(0, headerView.headerHeight - safeTop)
		guard abs(target - appliedInset) > 0.5 else { return }
		collectionView.contentInset.top += (target - appliedInset)
		appliedInset = target
	}

	// MARK: 渲染

	private func render(feed: Feed) {
		let isDark: Bool = headerView.traitCollection.userInterfaceStyle == .dark
		let width: CGFloat = headerView.bounds.width > 0 ? headerView.bounds.width : UIScreen.main.bounds.width
		let key: String = feed.feedID + "|" + (isDark ? "dark" : "light") + "|" + String(Int(width))
		if renderedKey == key { return }

		headerView.titleLabel.text = feed.nameForDisplay

		// 素材:高清优先,其次是**真**图标。
		// ⚠️ 千万别用 IconImageCache.imageForFeed —— 真图标还没下载好时,它会退回
		// FaviconGenerator 合成的「地球仪占位图」,而那个图的颜色是**按网址哈希**染的,
		// 和站点品牌毫无关系(Lawfare 的墨绿被算成紫色,就是踩了这个,见 L52)。
		// 这里直接问两个下载器要真图标:它们没有缓存时会**顺带发起下载**,
		// 到货后走 iconMightBeAvailable 通知补装。
		let hero: UIImage? = FeedHeroIconLoader.shared.cachedHero(for: feed)
		let realIcon: UIImage? = hero
			?? FeedIconDownloader.shared.icon(for: feed)?.image
			?? FaviconDownloader.shared.favicon(for: feed)?.image

		if hero == nil {
			FeedHeroIconLoader.shared.fetchHeroIfNeeded(for: feed) { [weak self] _ in
				guard let self, self.currentFeed?.feedID == feed.feedID else { return }
				self.renderedKey = nil
				self.refresh()
			}
		}

		guard let source: UIImage = realIcon else {
			// 真图标还没到:这一帧先什么都不画(纸色底),等通知补装。
			// **不设 renderedKey** —— 否则这次"空渲染"会被当成最终结果,再也不刷新。
			Self.logger.info("[头图] 源「\(feed.nameForDisplay, privacy: .public)」真图标还没到,等下载完再画")
			headerView.backgroundImageView.image = nil
			renderedKey = nil
			return
		}

		let size = CGSize(width: width, height: max(headerView.headerHeight, 1))
		let analysis: FeedIconAnalysis? = FeedIconColorAnalyzer.analyze(source)
		let coverage: CGFloat = analysis?.coverage ?? 0

		// 够不够格当整片头图:①素材够大 ②非白底像素占比够(白底 logo 拉满会是一片白)
		let sourcePixels: CGFloat = max(source.size.width, source.size.height) * source.scale
		let bigEnough: Bool = sourcePixels >= TimelineStyle.headerMinHeroPixels
		let richEnough: Bool = coverage >= TimelineStyle.headerMinCoverage
		let useImage: Bool = bigEnough && richEnough

		let layer: UIImage
		if useImage {
			layer = Self.makeBlurredFill(source: source, size: size)
		} else {
			let color: UIColor = analysis?.dominantColor ?? .systemGray
			layer = Self.makeSolidFill(color: color, size: size)
		}

		let paper: UIColor = AppAppearance.paperBackground.resolvedColor(with: headerView.traitCollection)
		headerView.backgroundImageView.image = Self.composite(layer: layer, size: size, paper: paper)
		headerView.setNeedsLayout()
		renderedKey = key

		let mode: String = useImage ? "大图" : "主色渐变"
		let coveragePercent: Int = Int(coverage * 100)
		let dominantHex: String = Self.hexString(analysis?.dominantColor)
		Self.logger.info("""
			[头图] 已装:源「\(feed.nameForDisplay, privacy: .public)」用\(mode, privacy: .public);\
			素材 \(Int(sourcePixels))px(\(hero != nil ? "高清" : "144 兜底", privacy: .public)),\
			非白像素 \(coveragePercent)%,主色 \(dominantHex, privacy: .public);\
			头图高 \(Int(self.headerView.headerHeight))pt,inset \(Int(self.appliedInset))pt
			""")
	}

	/// 把颜色转成 #RRGGBB,只用于日志排查(肉眼看颜色不可靠,得有数)。
	private static func hexString(_ color: UIColor?) -> String {
		guard let color else { return "无" }
		var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
		guard color.getRed(&r, green: &g, blue: &b, alpha: &a) else { return "读不出" }
		return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
	}

	/// 有大图这一路:aspectFill 铺满,**默认保持清晰**。
	///
	/// ⚠️ 2026-07-22 用户反馈「好模糊,一看就是小图强行拉大」后改的:
	/// 之前无条件把图缩到 40 像素宽再放大当"氛围层" —— 那是**我亲手把高清图糊掉**,
	/// 抓来的 314px 大图完全白费。现在改为**按放大倍数自适应**:
	/// 只有当素材实在不够(放大超过 headerBlurAboveUpscale 倍)才轻微柔化,
	/// 目的是掩盖插值锯齿,而不是制造氛围。素材够大时一点都不糊。
	private static func makeBlurredFill(source: UIImage, size: CGSize) -> UIImage {
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
		let filled: UIImage = renderer.image { (ctx: UIGraphicsImageRendererContext) in
			ctx.cgContext.interpolationQuality = .high
			source.draw(in: CGRect(x: drawX, y: drawY, width: drawW, height: drawH))
		}

		// 放大倍数 = 目标像素宽 / 素材像素宽。够清晰就原样返回,不做任何柔化。
		let sourcePixels: CGFloat = max(sourceW, sourceH) * source.scale
		let targetPixels: CGFloat = size.width * UIScreen.main.scale
		let upscale: CGFloat = targetPixels / max(sourcePixels, 1)
		guard upscale > TimelineStyle.headerBlurAboveUpscale else { return filled }
		return softBlurred(filled)
	}

	/// 没有合格大图这一路:纯主色铺满(后续合成会给它上浓下淡的渐变)。
	private static func makeSolidFill(color: UIColor, size: CGSize) -> UIImage {
		let format = UIGraphicsImageRendererFormat()
		format.opaque = true
		let renderer = UIGraphicsImageRenderer(size: size, format: format)
		return renderer.image { (ctx: UIGraphicsImageRendererContext) in
			color.setFill()
			ctx.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height))
		}
	}

	/// 模糊:缩到几十像素宽再高质量放大。细节被压掉,放大时插值把残留抹成柔和色晕。
	/// ⚠️ 刻意不用 CoreImage,原因见文件头与教训 L50。
	private static func softBlurred(_ input: UIImage) -> UIImage {
		let tinyWidth: CGFloat = max(TimelineStyle.headerImageDownsampleWidth, 2)
		guard input.size.width > tinyWidth else { return input }
		let aspect: CGFloat = input.size.height / max(input.size.width, 1)
		let tinySize = CGSize(width: tinyWidth, height: max(tinyWidth * aspect, 2))

		let tinyFormat = UIGraphicsImageRendererFormat()
		tinyFormat.scale = 1
		tinyFormat.opaque = true
		let tinyRenderer = UIGraphicsImageRenderer(size: tinySize, format: tinyFormat)
		let tiny: UIImage = tinyRenderer.image { (ctx: UIGraphicsImageRendererContext) in
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

	/// 合成(两条路共用,所以浓淡与蒙版口径天然一致):
	/// 纸色打底 → 以 headerImageStrength 的强度画素材层 → 素材层上浓下淡地被挖空 →
	/// 底部完全透出纸色,与文章列表无缝衔接。
	///
	/// 「整体蒙版」就是 headerImageStrength:小于 1 的全局不透明度,等价于盖一层纸色 ——
	/// 强度越低,图的颜色越被纸色拉回来,越不会和页面底色撞。
	private static func composite(layer: UIImage, size: CGSize, paper: UIColor) -> UIImage {
		let strength: CGFloat = TimelineStyle.headerImageStrength
		let fadeStartY: CGFloat = size.height * TimelineStyle.headerImageFadeStart
		let clearMask: CGColor = UIColor.clear.cgColor
		let solidMask: CGColor = UIColor.black.cgColor
		let maskColors: CFArray = [clearMask, solidMask] as CFArray
		let locations: [CGFloat] = [0, 1]

		let format = UIGraphicsImageRendererFormat()
		format.opaque = true
		let renderer = UIGraphicsImageRenderer(size: size, format: format)
		return renderer.image { (ctx: UIGraphicsImageRendererContext) in
			let cg: CGContext = ctx.cgContext
			let full = CGRect(x: 0, y: 0, width: size.width, height: size.height)

			paper.setFill()
			ctx.fill(full)

			cg.saveGState()
			cg.setAlpha(strength)
			cg.beginTransparencyLayer(auxiliaryInfo: nil)
			layer.draw(in: full)
			// destinationOut + (透明→黑)的竖直渐变 = 从 fadeStart 往下逐渐把素材层擦掉,
			// 擦掉的地方露出下面的纸色 → 正是「越往上越浓、越往下越淡」。
			cg.setBlendMode(.destinationOut)
			if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: maskColors, locations: locations) {
				cg.drawLinearGradient(
					gradient,
					start: CGPoint(x: 0, y: fadeStartY),
					end: CGPoint(x: 0, y: size.height),
					options: [.drawsAfterEndLocation]
				)
			}
			cg.setBlendMode(.normal)
			cg.endTransparencyLayer()
			cg.restoreGState()
		}
	}

	// MARK: 滚动联动(头图渐隐 + 导航栏小标题淡入)

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
		let restY: CGFloat = -collectionView.adjustedContentInset.top
		let progress: CGFloat = (collectionView.contentOffset.y - restY) / TimelineStyle.headerScrollFadeDistance
		let clamped: CGFloat = min(max(progress, 0), 1)
		headerView.contentAlpha = 1 - clamped

		// 滚过大半后,导航栏顶部淡入源名(Apple Music 的行为);滚回来再收掉
		let shouldShowNavTitle: Bool = clamped > 0.85
		if shouldShowNavTitle != navTitleShown {
			navTitleShown = shouldShowNavTitle
			navigationItem?.title = shouldShowNavTitle ? currentFeed?.nameForDisplay : nil
		}
	}

	// MARK: 图标迟到的补装

	@objc private func iconMightBeAvailable(_ note: Notification) {
		// 只在「还没画出过东西」时补装。
		// 这个判断之所以够用,是因为拿不到真图标时我们**故意不设 renderedKey**;
		// 而高清素材到货有 fetchHeroIfNeeded 的回调专门负责刷新,不归这里管。
		// (别改成"每次通知都刷新":图标通知在启动时会密集地来几十条,那样会把
		//  同一个源反复重渲染 —— 实测一次进页面渲染了 4 遍。)
		guard renderedKey == nil, currentFeed != nil else { return }
		refresh()
	}
}

// MARK: - 头图视图(布局 + 明暗监听)

@MainActor final class TimelineFeedHeaderView: UIView {

	let backgroundImageView = UIImageView()
	let titleLabel = UILabel()

	/// 头图区总高(从屏幕顶算),由控制器设置
	var headerHeight: CGFloat = 0 {
		didSet { setNeedsLayout() }
	}

	var onAppearanceChange: (() -> Void)?
	var onLayout: (() -> Void)?

	/// 滚动渐隐只作用于头图内容,不影响容器本身
	var contentAlpha: CGFloat = 1 {
		didSet {
			backgroundImageView.alpha = contentAlpha
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

		titleLabel.font = .preferredFont(forTextStyle: .largeTitle).bold()
		titleLabel.adjustsFontSizeToFitWidth = true
		titleLabel.minimumScaleFactor = 0.6
		titleLabel.textAlignment = .center
		titleLabel.numberOfLines = 2
		titleLabel.textColor = .label
		addSubview(titleLabel)

		registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: TimelineFeedHeaderView, _) in
			view.onAppearanceChange?()
		}
	}

	required init?(coder: NSCoder) {
		fatalError("不从 storyboard 创建")
	}

	override func layoutSubviews() {
		super.layoutSubviews()

		backgroundImageView.frame = CGRect(x: 0, y: 0, width: bounds.width, height: headerHeight)

		// 标题贴在头图区底部(最淡的位置),两侧留白给长源名折行
		let sideMargin: CGFloat = 24
		let maxWidth: CGFloat = max(bounds.width - sideMargin * 2, 1)
		let fitted: CGSize = titleLabel.sizeThatFits(CGSize(width: maxWidth, height: CGFloat(10000)))
		let titleHeight: CGFloat = min(fitted.height, headerHeight)
		let titleY: CGFloat = headerHeight - titleHeight - TimelineStyle.headerTitleBottomInset

		titleLabel.frame = CGRect(x: sideMargin, y: titleY, width: maxWidth, height: titleHeight)

		onLayout?()
	}
}
