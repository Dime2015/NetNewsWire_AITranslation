//
//  TimelineFeedWatermark.swift
//  NetNewsWire — AI 翻译 fork
//
//  [外观] 单一订阅源的文章列表页,顶部大标题区的「钢印水印」:
//  把这个源的图标放大、灰度化、以极低浓度"印"在暖纸背景上,右侧一部分出血到屏幕外。
//  灵感来自 Apple Music 艺人页的头图,但转译成本 app 的纸张审美 —— 是水印,不是海报。
//
//  设计要点(和用户确认过的):
//  - 只对「单一订阅源」的列表页显示;文件夹、今天/未读/星标这些没有单一 logo,不显示
//  - 只做浅色模式;深色模式下整个隐藏(用户说先看浅色效果,不好就回退)
//  - 图案约 80% 留在屏内、右侧约 20% 出血出去(出血比例可调,见 TimelineStyle)
//  - 所有可调数值都在 TimelineStyle.swift 的「水印」段,改样式不用碰这个文件
//
//  工程要点(为什么这么做,都是查过代码的):
//  1. 素材上限 144px(IconImage.maxIconPixelSize = 48pt × 3x,下载器落盘前就缩了)。
//     放大 7 倍必然糊 —— 所以刻意走"软水印"路线:灰度 + 低浓度 + 高质量插值的柔化,
//     糊就成了晕染感的一部分,而不是缺陷。
//  2. 用「正片叠底(multiply)」把灰度图印在纸色上:白色像素 × 纸色 = 纸色,
//     白底 favicon 的底自动消失,只留图案 —— 否则大量白底方图标会变成一块浅灰"贴纸"。
//     混合不靠图层滤镜,而是**预先烘焙**进一张图(背景色是已知的纯色,数学上等价),
//     行为确定、可逐像素验证。
//  3. 时间线 cell 的正常态背景是 .clear(MainTimelineCell 里写的),纸色是列表底层透上来的,
//     所以文章行滚动时不会"盖住"水印,而是从淡印上滑过 —— 因此**滚动渐隐是必须的**:
//     监听 contentOffset,滚过一小段就把水印淡出,避免正文长期压着图案。
//  4. 水印装在 collectionView.backgroundView 上(在所有 cell 后面),
//     大标题是导航栏画的、天然在水印上层,两不相干。
//  5. 首次进某个源时图标可能还没下载好 —— 监听几个「图标就绪」通知,到货后补装。
//
//  这个文件不属于上游 NetNewsWire,是本 fork 新增的。
//

import UIKit
import Account
import Images
import HTMLMetadata	// .htmlMetadataAvailable 通知定义在这个模块

// MARK: - 装到时间线控制器上的入口

extension MainTimelineModernViewController {

	private static var nnwWatermarkKey: UInt8 = 0

	/// 每次时间线切换订阅源时调用(挂在 updateNavigationBarTitle 里 —— 那是切源的必经之地)。
	/// 单一订阅源 → 装/换水印;文件夹、智能源、搜索等 → 摘掉水印。
	func nnwUpdateFeedWatermark() {
		guard TimelineStyle.watermarkEnabled, let collectionView else { return }

		// 惰性建一个水印管理器,挂在本控制器身上(扩展不能加存储属性,用关联对象)
		let controller: TimelineFeedWatermarkController
		if let existing = objc_getAssociatedObject(self, &Self.nnwWatermarkKey) as? TimelineFeedWatermarkController {
			controller = existing
		} else {
			controller = TimelineFeedWatermarkController()
			objc_setAssociatedObject(self, &Self.nnwWatermarkKey, controller, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
		}

		// 只有「单一订阅源」才有唯一的 logo;文件夹/智能源(今天、未读、星标)都不算
		let feed = coordinator?.timelineFeed as? Feed
		controller.update(feed: feed, collectionView: collectionView)
	}
}

// MARK: - 水印管理器

@MainActor final class TimelineFeedWatermarkController: NSObject {

	private weak var collectionView: UICollectionView?
	private weak var currentFeed: Feed?

	/// 真正显示水印的容器(作为 collectionView.backgroundView)
	private let container = TimelineWatermarkContainerView()

	/// 已经渲染出印章的源(feedID),避免同一个源反复渲染
	private var renderedFeedID: String?

	private var offsetObservation: NSKeyValueObservation?

	override init() {
		super.init()
		// 图标可能晚于页面到货:到货后如果水印还空着,补装一次。
		// 通知名的选择照抄时间线自己刷新 favicon 的那一组(MainTimelineModernViewController)。
		let names: [Notification.Name] = [
			.feedIconDidBecomeAvailable,
			.FaviconDidBecomeAvailable,
			.imageDidBecomeAvailable,
			.htmlMetadataAvailable
		]
		for name in names {
			NotificationCenter.default.addObserver(self, selector: #selector(iconMightBeAvailable(_:)), name: name, object: nil)
		}
	}

	func update(feed: Feed?, collectionView: UICollectionView) {
		self.collectionView = collectionView
		self.currentFeed = feed

		guard let feed else {
			removeWatermark()
			return
		}

		// 装容器(只装一次;backgroundView 会自动跟随 collectionView 的大小)
		if collectionView.backgroundView !== container {
			collectionView.backgroundView = container
		}
		observeScrollIfNeeded(collectionView)

		guard let icon = IconImageCache.shared.imageForFeed(feed) else {
			// 图标还没到 —— 先摘干净,等「图标就绪」通知来补装
			container.stampImageView.image = nil
			renderedFeedID = nil
			return
		}

		let feedID = feed.feedID
		if renderedFeedID == feedID, container.stampImageView.image != nil {
			return	// 同一个源、已渲染过,不重复干活
		}

		container.stampImageView.image = Self.makeStampImage(icon: icon.image, screenWidth: collectionView.bounds.width)
		container.setNeedsLayout()
		renderedFeedID = feedID
		applyScrollFade()
	}

	private func removeWatermark() {
		container.stampImageView.image = nil
		renderedFeedID = nil
		if collectionView?.backgroundView === container {
			collectionView?.backgroundView = nil
		}
		offsetObservation = nil
	}

	// MARK: 滚动渐隐

	private func observeScrollIfNeeded(_ collectionView: UICollectionView) {
		guard offsetObservation == nil else { return }
		offsetObservation = collectionView.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in
			// contentOffset 只会在主线程变,这里安全地断言回主 actor
			MainActor.assumeIsolated {
				self?.applyScrollFade()
			}
		}
	}

	/// 从"停在顶部"往下滚 watermarkScrollFadeDistance 点的过程中,水印线性淡出。
	/// 往下拉(刷新那个方向)不加深也不隐藏,保持满值。
	private func applyScrollFade() {
		guard let collectionView else { return }
		let restY = -collectionView.adjustedContentInset.top
		let progress = (collectionView.contentOffset.y - restY) / TimelineStyle.watermarkScrollFadeDistance
		container.stampImageView.alpha = 1 - min(max(progress, 0), 1)
	}

	// MARK: 图标迟到的补装

	@objc private func iconMightBeAvailable(_ note: Notification) {
		guard renderedFeedID == nil, let feed = currentFeed, let collectionView else { return }
		update(feed: feed, collectionView: collectionView)
	}

	// MARK: 印章渲染(一次性,按源缓存于 renderedFeedID 判断)

	/// 把(最大 144px 的)图标做成一张「印在纸上」的水印图:
	/// 灰度 → 以 watermarkAlpha 的浓度正片叠底到纸色上 → 底部纵向渐隐。
	/// 产出的图自带纸色底,和列表背景同色,所以边界看不出来。
	static func makeStampImage(icon: UIImage, screenWidth: CGFloat) -> UIImage {
		let width = screenWidth * TimelineStyle.watermarkWidthRatio
		// 图标都是正方形(下载管线里就是按方形缓存的);非方形按原比例
		let aspect = icon.size.height > 0 ? icon.size.height / icon.size.width : 1
		let size = CGSize(width: width, height: width * aspect)

		let format = UIGraphicsImageRendererFormat()
		format.opaque = false
		let renderer = UIGraphicsImageRenderer(size: size, format: format)

		// 第一步:灰度。白底上以 luminosity 混合画原图 —— 白底没有饱和度,
		// 结果就是"只保留明度"的灰度图;图标的透明区域保持白色(下一步会被 multiply 抹掉)。
		let gray = renderer.image { ctx in
			ctx.cgContext.interpolationQuality = .high	// 144px 放大到这个尺寸,靠高质量插值柔化
			UIColor.white.setFill()
			ctx.fill(CGRect(origin: .zero, size: size))
			icon.draw(in: CGRect(origin: .zero, size: size), blendMode: .luminosity, alpha: 1)
		}

		// 纸色固定按浅色模式解析(深色模式下整个水印是隐藏的,烘焙进图里的必须是浅色纸)
		let paper = AppAppearance.paperBackground.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))

		// 第二步:印章 = 纸色打底 + multiply 低浓度盖灰度图 + 底部渐隐
		return renderer.image { ctx in
			paper.setFill()
			ctx.fill(CGRect(origin: .zero, size: size))
			gray.draw(in: CGRect(origin: .zero, size: size), blendMode: .multiply, alpha: TimelineStyle.watermarkAlpha)

			// 纵向渐隐:从 fadeStart 高度处开始,到底部完全消失。
			// 用 destinationOut 把已画内容的不透明度渐进"挖掉",露出来的就是同色的列表背景。
			let colors = [UIColor.clear.cgColor, UIColor.black.cgColor] as CFArray
			if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
				ctx.cgContext.setBlendMode(.destinationOut)
				ctx.cgContext.drawLinearGradient(
					gradient,
					start: CGPoint(x: 0, y: size.height * TimelineStyle.watermarkFadeStart),
					end: CGPoint(x: 0, y: size.height),
					options: [.drawsAfterEndLocation]
				)
			}
		}
	}
}

// MARK: - 容器视图(负责摆位置 + 深色模式隐藏)

@MainActor final class TimelineWatermarkContainerView: UIView {

	let stampImageView = UIImageView()

	override init(frame: CGRect) {
		super.init(frame: frame)
		backgroundColor = .clear
		isUserInteractionEnabled = false	// 纯装饰,不挡任何点按
		clipsToBounds = true				// 出血的部分裁掉,不越界
		stampImageView.contentMode = .scaleAspectFit
		addSubview(stampImageView)

		// 只做浅色模式(用户确认):深色下整个隐藏。iOS 17+ 的注册式监听,不用已废弃的回调。
		updateForAppearance()
		registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: TimelineWatermarkContainerView, _) in
			view.updateForAppearance()
		}
	}

	required init?(coder: NSCoder) {
		fatalError("不从 storyboard 创建")
	}

	private func updateForAppearance() {
		stampImageView.isHidden = (traitCollection.userInterfaceStyle == .dark)
	}

	override func layoutSubviews() {
		super.layoutSubviews()
		guard let image = stampImageView.image else { return }
		// 水平:让图的右侧出血 —— 屏内只留 visibleFraction,其余伸出右边界(被裁掉)
		let x = bounds.width - image.size.width * TimelineStyle.watermarkVisibleFraction
		stampImageView.frame = CGRect(
			x: x,
			y: TimelineStyle.watermarkTopOffset,
			width: image.size.width,
			height: image.size.height
		)
	}
}
