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
		controller.update(feed: feed, host: self, collectionView: collectionView)
	}
}

// MARK: - 头图区管理器

@MainActor final class TimelineFeedHeaderController: NSObject {

	private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "TimelineFeedHeader")

	private weak var collectionView: UICollectionView?
	private weak var navigationItem: UINavigationItem?
	private weak var currentFeed: Feed?

	private let headerView = TimelineFeedHeaderView()
	/// 标题所在的浮层。**必须挂在控制器的 view 上、盖在列表之上** ——
	/// 原来标题住在 collectionView.backgroundView 里,那是在**所有文章行的下面**,
	/// 标题往上飞会从文章文字底下穿过去。
	private let overlay = TimelineHeaderOverlayView()
	private weak var host: UIViewController?

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

	func update(feed: Feed?, host: UIViewController, collectionView: UICollectionView) {
		self.collectionView = collectionView
		self.navigationItem = host.navigationItem
		self.host = host
		self.currentFeed = feed

		guard let feed else {
			remove()
			return
		}
		let navigationItem: UINavigationItem = host.navigationItem

		// —— 单一订阅源:接管顶部 ——

		// 1. 让上游那个导航栏标题让位:标题从头到尾由我们自己画(要能一路飞过去)。
		//    ⚠️ **只把 titleView 藏起来,不要把 navigationItem.title 清空** ——
		//    title 还兼任下一页返回按钮的文字,清了会连带影响文章页的返回按钮。
		//    titleView 存在时会盖过 title,所以藏了它就什么都不显示了,两不耽误。
		navigationItem.largeTitleDisplayMode = .never
		navigationItem.titleView?.alpha = 0

		// 2. 停靠时导航栏要有一层底,否则文章正文会从标题背后穿过去(用户截图证实)。
		//    用 **navigationItem 上的** appearance,不是全局 appearance 代理 ——
		//    后者会把大标题和副标题一起冲掉(教训 L45);上游自己在文章页也是这么做的。
		applyNavigationBarAppearance(to: navigationItem, host: host)

		// 3. 装容器
		if collectionView.backgroundView !== headerView {
			collectionView.backgroundView = headerView
		}
		installOverlayIfNeeded(in: host)
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
		// 恢复上游的导航栏标题与外观(文件夹 / 智能源页面要跟原来一模一样)
		navigationItem?.titleView?.alpha = 1
		navigationItem?.standardAppearance = nil
		navigationItem?.scrollEdgeAppearance = nil
		navigationItem?.largeTitleDisplayMode = .automatic
		overlay.removeFromSuperview()
		renderedKey = nil
		installedFeedID = nil
	}

	/// 供通知/明暗变化后重新渲染(源和列表都不变时)
	private func refresh() {
		guard let feed = currentFeed, let collectionView, let host else { return }
		update(feed: feed, host: host, collectionView: collectionView)
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

		overlay.titleLabel.text = feed.nameForDisplay

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
			// 主色渐变这一路:先保证这个颜色**在纸色上看得见**,
			// 否则近白的主色(如 Six Colors 的 #E6E6E6)会让整片头图消失。
			let rawColor: UIColor = analysis?.dominantColor ?? .systemGray
			let color: UIColor = FeedIconColorAnalyzer.visibleGradientColor(
				brand: rawColor,
				paper: AppAppearance.paperBackground.resolvedColor(with: headerView.traitCollection),
				minContrast: TimelineStyle.headerMinGradientContrast
			)
			layer = Self.makeSolidFill(color: color, size: size)
		}

		let paper: UIColor = AppAppearance.paperBackground.resolvedColor(with: headerView.traitCollection)

		// 标题染成「这个源的主题色,但保证读得清」。
		// 规则和方向说明见 FeedIconColorAnalyzer.readableTitleColor ——
		// 简单说:浅色模式往深里压、深色模式往亮里提,压到对比度达标为止。
		if let brand = analysis?.dominantColor {
			overlay.titleLabel.textColor = FeedIconColorAnalyzer.readableTitleColor(
				brand: brand,
				paper: paper,
				tint: TimelineStyle.headerTitleTintStrength,
				minContrast: TimelineStyle.headerTitleMinContrast
			)
		} else {
			overlay.titleLabel.textColor = .label
		}

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

	/// 有大图这一路:**aspectFill 铺满整条**,默认保持清晰。
	///
	/// ⚠️ 2026-07-22 这里来回改过两轮,别再走回头路:
	/// - 最早无条件把图缩到 40px 宽再放大当"氛围层" → 用户:「好模糊,一看就是小图强行拉大」。
	///   改为**按放大倍数自适应**:只有放大超过 headerBlurAboveUpscale 倍才轻微柔化。
	/// - 然后试过「方案 A:完整显示 + 模糊填边」(底层铺满模糊 + 上层完整不裁),
	///   解决了 furbo.org 的 `f` 被裁成白十字的问题 —— 但**用户看完选择退回铺满**,
	///   理由是「还是原来铺满好看」:完整显示会把画面从"整片浓烈"变成
	///   "中间一块清晰 + 两侧色晕",气势弱了。
	///   **这是明知代价的取舍:方形 logo 上下各被裁掉 22%,单字母 logo 会认不出。**
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
		return softBlurred(filled, downsampleWidth: TimelineStyle.headerImageDownsampleWidth)
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
	private static func softBlurred(_ input: UIImage, downsampleWidth: CGFloat) -> UIImage {
		let tinyWidth: CGFloat = max(downsampleWidth, 2)
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
		guard let collectionView, let host, currentFeed != nil else { return }
		let restY: CGFloat = -collectionView.adjustedContentInset.top
		let raw: CGFloat = (collectionView.contentOffset.y - restY) / TimelineStyle.headerScrollFadeDistance
		let progress: CGFloat = min(max(raw, 0), 1)

		// 头图(图片本身)照旧渐隐
		headerView.contentAlpha = 1 - progress

		// 标题沿一条直线飞向导航栏,同时线性缩小;纸色底在后半段淡入
		overlay.apply(
			progress: progress,
			headerHeight: headerView.headerHeight,
			dockBand: dockedTitleBand(in: host),
			safeAreaTop: host.view.safeAreaInsets.top
		)
	}

	/// 标题停靠区:**状态栏下沿 到 安全区顶部** 之间那一条(也就是两个圆钮所在的那条)。
	///
	/// ⚠️ **不要用 `navigationBar.bounds` 去算中点**(2026-07-22 实测踩过,见 L57):
	/// iOS 26 的导航栏 bounds 是**从屏幕最顶端算起、把状态栏一起包进去的**(约 114pt 高),
	/// 它的"正中"在 57pt —— 而两个圆钮实际在 85pt。照它对齐,标题会比按钮高出 28pt,
	/// 再滑一点就飞出画面。用户的原话:「标题跟着线性动画要飞到画面外了」。
	///
	/// 状态栏高度 + 安全区顶 这两个值都是可靠的:安全区顶 = 状态栏 + 导航栏,
	/// 两者的中点正好落在导航栏那一条的正中。
	private func dockedTitleBand(in host: UIViewController) -> CGRect {
		let width: CGFloat = host.view.bounds.width
		let safeTop: CGFloat = host.view.safeAreaInsets.top
		let statusBarHeight: CGFloat = host.view.window?.windowScene?.statusBarManager?.statusBarFrame.height ?? 0

		// 兜底:拿不到状态栏高度(极少见)就按"安全区顶往上 44pt"当作导航栏那一条
		let bandTop: CGFloat = statusBarHeight > 0 ? statusBarHeight : max(safeTop - 44, 0)
		let bandHeight: CGFloat = max(safeTop - bandTop, 20)
		return CGRect(x: 0, y: bandTop, width: width, height: bandHeight)
	}

	/// 把浮层装到宿主控制器的 view 上(盖在列表之上、导航栏之下)。
	private func installOverlayIfNeeded(in host: UIViewController) {
		guard overlay.superview !== host.view else { return }
		overlay.removeFromSuperview()
		host.view.addSubview(overlay)
		overlay.frame = host.view.bounds
		overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
	}

	/// 让导航栏**始终透明**(只作用于本页面,不是全局 appearance 代理)。
	///
	/// ⚠️ **第一版在这里犯了错,别再犯**(2026-07-22 用户截图指出):
	/// 当时给滚动后的 standardAppearance 铺了一层不透明纸色,想给停靠的标题当底。
	/// 但**导航栏画在我们那层浮层的上面** —— 结果标题飞上去就钻到它背后不见了,
	/// 而那条不透明的带子还把头图和正文一起挡住。用户的原话:
	/// 「顶栏没有变透明,把后面遮挡起来了,标题在往顶栏的遮挡后面跑」。
	///
	/// 正确的分工:**导航栏自始至终透明,底由浮层自己那条 scrim 提供**。
	/// 这样层级是「正文 → scrim → 标题 → 导航栏按钮」,标题稳稳停在自己的底上面,
	/// 而两个圆钮仍然压在最上面。
	///
	/// 仍然要显式设成透明(而不是不管)的原因:iOS 默认的 standardAppearance
	/// 在内容滚上去之后会自己画一层毛玻璃 —— 那正是要避免的那层遮挡。
	private func applyNavigationBarAppearance(to navigationItem: UINavigationItem, host: UIViewController) {
		let transparent = UINavigationBarAppearance()
		transparent.configureWithTransparentBackground()
		transparent.shadowColor = .clear	// 不要那条分隔线,和无边界风格一致
		transparent.titleTextAttributes = [.foregroundColor: UIColor.clear]	// 标题由我们自己画

		navigationItem.scrollEdgeAppearance = transparent
		navigationItem.standardAppearance = transparent
		navigationItem.compactAppearance = transparent
	}

	// MARK: 图标迟到的补装

	@objc private func iconMightBeAvailable(_ note: Notification) {
		guard let feed = currentFeed else { return }

		// ① 新信息(尤其是**网页元数据**)到货,可能让之前失败的高清抓取变得可行。
		//    apple-touch-icon 和 og:image 两类候选都来自元数据,而元数据是内存缓存、
		//    启动时为空 —— 第一次抓图时它们根本不存在。所以这里要再捅一次。
		//    抓取器自己有「已有高清 / 正在抓 / 失败次数超限」三道闸门,不会重复干活。
		if FeedHeroIconLoader.shared.cachedHero(for: feed) == nil {
			FeedHeroIconLoader.shared.fetchHeroIfNeeded(for: feed) { [weak self] _ in
				guard let self, self.currentFeed?.feedID == feed.feedID else { return }
				self.renderedKey = nil
				self.refresh()
			}
		}

		// ② 还没画出过东西时才补画。
		//    (别改成"每次通知都刷新":图标通知在启动时会密集地来几十条,那样会把
		//     同一个源反复重渲染 —— 实测一次进页面渲染了 4 遍。)
		guard renderedKey == nil else { return }
		refresh()
	}
}

// MARK: - 头图视图(布局 + 明暗监听)

@MainActor final class TimelineFeedHeaderView: UIView {

	let backgroundImageView = UIImageView()

	/// 头图区总高(从屏幕顶算),由控制器设置
	var headerHeight: CGFloat = 0 {
		didSet { setNeedsLayout() }
	}

	var onAppearanceChange: (() -> Void)?
	var onLayout: (() -> Void)?

	/// 滚动渐隐只作用于头图内容,不影响容器本身
	var contentAlpha: CGFloat = 1 {
		didSet { backgroundImageView.alpha = contentAlpha }
	}

	override init(frame: CGRect) {
		super.init(frame: frame)
		backgroundColor = .clear
		isUserInteractionEnabled = false	// 纯装饰,不挡点按
		clipsToBounds = true

		backgroundImageView.contentMode = .scaleToFill
		addSubview(backgroundImageView)

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
		onLayout?()
	}
}

// MARK: - 标题浮层(会飞的那个标题 + 停靠时的纸色底)

/// 挂在**控制器的 view 上**、盖在文章列表之上的一层浮层。
///
/// ⚠️ 为什么标题非要住在这里、不能留在头图里(2026-07-22):
/// 头图是 `collectionView.backgroundView`,那一层在**所有文章行的下面**。
/// 标题要往上飞到导航栏,一路上会从文章文字**底下**穿过去 —— 看起来像鬼影。
/// 放到这一层才是"浮在内容之上",也才是 Apple Music 那种观感。
///
/// 层级关系(从下往上):文章列表 → 本浮层 → 导航栏(返回/筛选两个圆钮)。
/// 所以两个圆钮永远盖在标题上面,这是对的;而标题永远盖在正文上面,也是对的。
@MainActor final class TimelineHeaderOverlayView: UIView {

	/// 停靠时铺在导航栏那条上的底。没有它,正文会直接从标题背后穿过去。
	///
	/// 效果目标(2026-07-23 用户要求):和订阅列表页 / 文章内容页一样的"渐变透明毛玻璃" ——
	/// 顶部还在头图区时完全没有它、一点不挡头图;往下滚才渐渐现出一层**薄**毛玻璃。
	///
	/// ⚠️ **effect 初始是 nil,浓度由下面的 `scrimAnimator` 驱动,别在这里直接给它 effect。**
	private let scrimView = UIVisualEffectView(effect: nil)

	/// 给毛玻璃底边做羽化的遮罩:上面那段全实,最后 `headerDockedScrimFeather` 点渐隐到透明。
	/// 没有它,毛玻璃的下沿是一条切齐的硬边,整条看起来像块挡板而不是一层雾。
	private let scrimMask = CAGradientLayer()

	/// 驱动**毛玻璃浓度**的动画器 —— 它不播放,只是被当成一根"浓度滑杆"用。
	///
	/// ⚠️ **为什么不用 `scrimView.alpha`**(2026-07-23 改,这是本轮的关键修正):
	/// 苹果明确说毛玻璃视图的 alpha 小于 1 会让模糊失真;而且拿 alpha 调出来的"薄",
	/// 本质是**清晰内容和模糊内容叠加**的重影,不是真的薄。
	/// 官方做法是把"从无到毛玻璃"这个变化交给 `UIViewPropertyAnimator`,再用
	/// `fractionComplete` 把它**停在任意档位** —— 那是系统插值出来的真毛玻璃
	/// (模糊半径和着色一起按比例减弱)。于是"厚度"变成一个可调的旋钮
	/// (`TimelineStyle.headerDockedScrimStrength`),而 alpha 全程保持 1。
	///
	/// ⚠️ **这个动画器停在"暂停中"状态时被释放会直接崩溃**(UIKit 的硬性要求)。
	/// 本类是主线程隔离的,Swift 6 不允许在 `deinit` 里访问它,所以收尾改在
	/// `willMove(toWindow:)`:离开窗口就停掉,回来时按需重建。**别把这段挪进 deinit。**
	private var scrimAnimator: UIViewPropertyAnimator?

	let titleLabel = UILabel()

	override init(frame: CGRect) {
		super.init(frame: frame)
		backgroundColor = .clear
		isUserInteractionEnabled = false	// 纯装饰,一点也不挡下面列表的点按

		// 羽化遮罩:自上而下「实 → 实 → 透」,拐点位置在 apply() 里按实际高度算。
		scrimMask.startPoint = CGPoint(x: 0.5, y: 0)
		scrimMask.endPoint = CGPoint(x: 0.5, y: 1)
		scrimMask.colors = [UIColor.black.cgColor, UIColor.black.cgColor, UIColor.clear.cgColor]
		scrimView.layer.mask = scrimMask
		addSubview(scrimView)

		// 切深浅色时把浓度滑杆重建一次 —— 毛玻璃材质的深浅两套颜色是在
		// 动画器建立时插值固化的,不重建的话切换后会停在旧的那套(L59 的同类问题)。
		registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: TimelineHeaderOverlayView, _) in
			view.rebuildScrimForAppearanceChange()
		}

		titleLabel.font = TimelineStyle.headerTitleFont
		titleLabel.textAlignment = TimelineStyle.headerTitleAlignment
		// 单行:要一路缩放着飞过去,多行会让运动看起来很乱;超长源名自动压字号
		titleLabel.numberOfLines = 1
		titleLabel.adjustsFontSizeToFitWidth = true
		titleLabel.minimumScaleFactor = 0.5
		titleLabel.isAccessibilityElement = true
		addSubview(titleLabel)

		// 毛玻璃自带深浅色自适应,不需要手动跟随明暗重设颜色(只需切换时重建浓度滑杆,见上)。
	}

	required init?(coder: NSCoder) {
		fatalError("不从 storyboard 创建")
	}

	// MARK: 毛玻璃浓度滑杆的生命周期

	/// 拿到浓度滑杆,没有就现建一根(建好就停在起点,等人喂进度)。
	private func scrimAnimatorIfNeeded() -> UIViewPropertyAnimator {
		if let existing = scrimAnimator { return existing }
		let animator = UIViewPropertyAnimator(duration: 1, curve: .linear) { [weak self] in
			guard let self else { return }
			self.scrimView.effect = UIBlurEffect(style: TimelineStyle.headerDockedScrimMaterial)
		}
		// 到头了也不要自动"结束" —— 结束后这根滑杆就作废了,之后再喂进度不会有任何反应。
		animator.pausesOnCompletion = true
		scrimAnimator = animator
		return animator
	}

	/// 停掉并丢弃浓度滑杆,顺便把毛玻璃清空。
	private func stopScrimAnimator() {
		scrimAnimator?.stopAnimation(true)
		scrimAnimator = nil
		scrimView.effect = nil
	}

	/// 深浅色切换时重建滑杆,并把浓度接回原来的位置(观感上没有跳变)。
	private func rebuildScrimForAppearanceChange() {
		let fraction = scrimAnimator?.fractionComplete ?? 0
		stopScrimAnimator()
		guard fraction > 0 else { return }
		scrimAnimatorIfNeeded().fractionComplete = fraction
	}

	/// ⚠️ 页面离开窗口时必须停掉滑杆 —— 它停在"暂停中"状态时被释放会**直接崩溃**。
	/// 这里是 deinit 的替身(本类主线程隔离,Swift 6 不让在 deinit 里碰它)。
	override func willMove(toWindow newWindow: UIWindow?) {
		super.willMove(toWindow: newWindow)
		if newWindow == nil {
			stopScrimAnimator()
		}
	}

	/// 按滚动进度摆放标题(0 = 停在头图下方靠右,1 = 停靠在导航栏正中)。
	///
	/// 缩放用 `transform` 而不是换字号:换字号是跳变的,做不出连续动画。
	/// 方向上**刻意是"大字缩小"而不是"小字放大"** —— 缩小的插值损失小得多,
	/// 停靠时看起来仍然干净。
	func apply(progress: CGFloat, headerHeight: CGFloat, dockBand: CGRect, safeAreaTop: CGFloat) {
		let width: CGFloat = bounds.width
		guard width > 0, headerHeight > 0 else { return }

		// —— 毛玻璃底:后半段才现,免得刚一动就压上一片 ——
		let scrimStart: CGFloat = TimelineStyle.headerDockedScrimFadeStart
		let scrimProgress: CGFloat = progress <= scrimStart ? 0 : (progress - scrimStart) / max(1 - scrimStart, 0.01)

		// 高度 = 「实的那段」(盖住状态栏+导航栏)+「羽化那段」(在导航栏下方渐渐散掉)
		let solidHeight: CGFloat = max(safeAreaTop, dockBand.maxY)
		let feather: CGFloat = TimelineStyle.headerDockedScrimFeather
		scrimView.frame = CGRect(x: 0, y: 0, width: width, height: solidHeight + feather)
		scrimView.alpha = 1	// ⚠️ 恒为 1,浓度由滑杆调(理由见 scrimAnimator 的说明)

		// 遮罩跟着尺寸走。⚠️ 必须关掉 CALayer 的隐式动画 —— 否则每帧的 frame/locations 变化
		// 都会被排成一段 0.25 秒的动画,羽化就跟不上手指了。
		CATransaction.begin()
		CATransaction.setDisableActions(true)
		scrimMask.frame = scrimView.bounds
		let solidRatio = solidHeight / max(scrimView.bounds.height, 1)
		scrimMask.locations = [0, NSNumber(value: Double(solidRatio)), 1]
		CATransaction.commit()

		// 浓度:0 → 上限。
		// 回到顶部(不需要毛玻璃)时**顺手把滑杆停掉**:一来省得白留一根,
		// 二来它停在"暂停中"状态时被释放会崩,活着的时间越短越安全。
		let strength: CGFloat = min(max(scrimProgress, 0), 1) * TimelineStyle.headerDockedScrimStrength
		if strength > 0 {
			scrimAnimatorIfNeeded().fractionComplete = strength
		} else if scrimAnimator != nil {
			stopScrimAnimator()
		}

		// —— 两个端点 ——
		let sideMargin: CGFloat = TimelineStyle.headerTitleSideMargin
		let available: CGFloat = max(width - sideMargin * 2, 1)

		// 先把 transform 清掉再量尺寸,否则量到的是被缩放过的
		titleLabel.transform = .identity
		var fitted: CGSize = titleLabel.sizeThatFits(CGSize(width: available, height: CGFloat(10000)))
		fitted.width = min(fitted.width, available)
		titleLabel.bounds = CGRect(origin: .zero, size: fitted)

		// 起点:右缘对齐文章行的右边距,**基线**落在头图底边(渐变消失的那条线)上
		let descender: CGFloat = abs(titleLabel.font.descender)
		let restBottom: CGFloat = headerHeight - TimelineStyle.headerTitleBaselineInset + descender
		let restCenter = CGPoint(x: width - sideMargin - fitted.width / 2,
								 y: restBottom - fitted.height / 2)

		// 终点:停靠区正中(两个圆钮所在的那一条)
		let dockedCenter = CGPoint(x: width / 2, y: dockBand.midY)

		// 线性插值(位置 + 缩放同步进行)
		let scale: CGFloat = 1 + (TimelineStyle.headerDockedTitleFontSize / TimelineStyle.headerTitleFontSize - 1) * progress
		let interpolatedY: CGFloat = restCenter.y + (dockedCenter.y - restCenter.y) * progress
		// 保险:无论几何怎么算,都不许飞到停靠区上沿以上(否则会滑出画面)
		let minCenterY: CGFloat = dockBand.minY + fitted.height * scale / 2
		titleLabel.center = CGPoint(x: restCenter.x + (dockedCenter.x - restCenter.x) * progress,
									y: max(interpolatedY, minCenterY))
		titleLabel.transform = CGAffineTransform(scaleX: scale, y: scale)
	}
}
