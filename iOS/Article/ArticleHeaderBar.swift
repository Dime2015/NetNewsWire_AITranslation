//
//  ArticleHeaderBar.swift
//  NetNewsWire — AI 翻译 fork
//
//  [外观] 文章内容页顶部的「阅读栏」。本 fork 新增文件,上游没有。
//
//  ## 它长什么样
//
//  停在顶部时(正文还没滚动):
//
//  ┌──────────────────────────────┐
//  │  (icon 48)                    │  ← 源图标,左上
//  │                               │
//  │  这里是文章标题,大字衬线,      │  ← UIKit 画的标题(网页里那个已被藏掉)
//  │  最多三行                      │
//  ├──────────────────────────────┤
//  │  正文从这里开始……              │
//  └──────────────────────────────┘
//
//  往下滚之后(**系统的栏全藏起来,只留我们这条**):
//
//  ┌──────────────────────────────┐
//  │ (◜ic◝) Daring Fireball · Gruber │  ← 12pt 次要色
//  │  ╰环   Spotlight: Not Right     │  ← 15pt 半粗,单行截断
//  ├──────────────────────────────┤
//  │  正文……                       │
//
//  上滑时导航栏、底部工具条全都回来。
//
//  ⚠️ **两次设计弯路,别再走回去**:
//  1. 第一版冻结在**导航栏那一条**里,和返回键、上/下一篇按钮叠住了(用户截图)。
//     量过才知道:那条栏的标题区是个写死 150×44 的占位视图,左右两组按钮占去大半 ——
//     "图标 + 源名作者 + 标题 + 进度环"根本塞不下。→ 改成**另起一条**。
//  2. 我一开始判断「滑动藏栏」和「冻结阅读栏」**互斥**,让用户二选一。
//     用户提出了更好的安排:**那不是互斥,是分工** ——
//     系统的栏是"导航"(返回、上/下一篇、工具条),读文章时该让路;
//     我们这条是"阅读上下文",该常驻。于是下滑全藏、只留这条,上滑全回来。
//
//  ## 三个设计决定(用户 2026-07-23 拍板,别改回去)
//
//  1. **下滑时系统的栏全藏,只留这条阅读栏;上滑全都回来。**
//     用户已确认接受"返回按钮会暂时消失"(往回滑一点就回来)。
//     设置里那个**已有的**「全屏阅读」开关现在只决定**有没有这条阅读栏**:
//     - 关(默认)→ 有这条(图标 + 源名作者 + 标题 + 进度环)
//     - 开 → 纯沉浸,连这条也没有,网页里的标题和头像自动回来
//  2. **进度做成绕着图标的一圈环**,不是图标下方的小条。
//     理由:**毛玻璃在 2–3pt 高的条上根本显不出模糊**,那时它和一条半透明色线没区别;
//     环形不占额外高度,而且"读完一圈"这个隐喻很直观。
//  3. **网页里的大标题和右上角 48×48 头像被注入 CSS 藏掉**,改由本文件画。
//     DOM 元素搬不进 UIKit 顶栏,只有自己画才能做出"线性跟随着飞上去"。
//     正文里的「源名 / 作者 / 日期」那一行**保留** —— 那是正文该有的信息。
//
//  ## ⚠️ 一条硬约束(来自 L63,别越界)
//
//  文章页在滚动回调里改布局,曾经炸出 **28000 层递归**的栈溢出:
//  藏栏 → 安全区变 → 系统调整滚动位置 → 又回调滚动 → 再藏栏 → ……
//  所以本文件的飞行动画**只允许改 `transform` 和 `alpha`**,
//  **绝不在滚动回调里碰 `contentInset` / `safeArea`**。
//  内容下移那一下(`contentInset.top`)只在**绑定文章时**做一次,不在每帧做。
//

#if os(iOS)

import UIKit
import Account
import Articles
import Images

@MainActor final class ArticleHeaderBarController: NSObject {

	// MARK: - 可调的数(要调样式改这里)

	enum Style {
		/// 停在顶部时,图标多大
		static let restIconSize: CGFloat = 48
		/// 冻结在顶栏里时,图标多大
		static let dockedIconSize: CGFloat = 34
		/// 图标左边距。**停靠前后一样** —— 图标是竖直飞上去的,横向不动,看起来更稳。
		static let iconLeading: CGFloat = 20
		/// 头区上下留白
		static let topPadding: CGFloat = 12
		static let bottomPadding: CGFloat = 16
		/// 图标底部到标题的距离
		static let iconTitleGap: CGFloat = 14
		/// 标题最多几行(停在顶部时)
		static let restTitleMaxLines = 4
		/// 冻结后的标题字号。**字体本身和大标题同一套**(见 applyContent),这里只管大小。
		static let dockedTitleFontSize: CGFloat = 16
		/// 图标和冻结标题之间的距离
		static let dockedTitleGap: CGFloat = 10
		/// 「源名 · 作者」到大标题的距离
		static let sourceTitleGap: CGFloat = 6
		/// 冻结条内部的上下留白
		static let dockedInnerPadding: CGFloat = 7
		/// 内容总高变化超过这个比例才算"大幅变化",才冻结进度。
		/// ⚠️ **别设成 0**:WKWebView 在图片陆续到货、排版沉降时会**反复**微调内容高度,
		/// 每次都冻结的话,进度看起来就是一跳一跳的(2026-07-23 用户报的正是这个)。
		static let significantContentChange: CGFloat = 0.05
		/// 冻结后那条独立窄条的高度。
		/// ⚠️ **不要停靠到导航栏那一条里** —— 那里被返回键和上/下一篇按钮占去大半,
		/// 只剩约 150pt(标题区是个写死 150×44 的占位视图),三样东西塞不下(用户实测撞车)。
		static let dockedStripHeight: CGFloat = 52

		/// 飞完这么长的距离(pt)就算完全冻结。越小越"跟手",越大越舒缓。
		static let flightDistance: CGFloat = 120
		/// 交接:飞到这个进度之后,大标题淡出、冻结标题淡入
		static let swapStart: CGFloat = 0.45
		/// 毛玻璃底从这个进度开始现
		static let scrimFadeStart: CGFloat = 0.3
		/// 毛玻璃浓度上限(1 = 系统满浓度)。和文章列表页那条口径一致。
		static let scrimStrength: CGFloat = 0.72

		/// 进度环的线宽。
		/// ⚠️ **环紧贴着图标边缘走**(圆心距 = 图标半径 + 线宽的一半),
		/// 于是图标正好填满环的内部、环成了它的描边 —— 用户 2026-07-23 要的就是这个效果。
		/// 所以图标必须是**正圆**(见 `applyGeometry` 里的 cornerRadius),
		/// 圆角方形配圆环会露出四个角的空当。
		static let ringWidth: CGFloat = 3

		/// 内容高度变化后,进度条冻结多久(秒)。
		/// **翻译是逐块替换的**,替换时内容总高会跳变,进度跟着往回跳很难看;
		/// 图片异步加载同理。冻一下等它稳定。
		static let progressFreezeSeconds: TimeInterval = 0.6
	}

	// MARK: - 部件

	private let container = NNWPassThroughView()
	private let scrimView = UIVisualEffectView(effect: nil)
	private let iconView = UIImageView()
	private let ringLayer = CAShapeLayer()
	/// 停在顶部时的大标题(多行、衬线)
	private let restTitleLabel = UILabel()
	/// 冻结在顶栏里的小标题(单行)
	private let dockedTitleLabel = UILabel()
	/// 「源名 · 作者」那一行。**两个状态共用同一个**(都是单行,直接平移过去就行)
	private let sourceLabel = UILabel()

	/// 毛玻璃的浓度滑杆。
	/// ⚠️ **不能用 `scrimView.alpha` 调浓淡**(L62):alpha 会让模糊失真,
	/// 而且调出来的"薄"是清晰内容和模糊内容叠加的重影。
	/// 正确做法是把"从无到毛玻璃"交给动画器,再用 `fractionComplete` 停在任意档位。
	/// ⚠️ 它停在"暂停中"被释放会**直接崩溃**,所以离开窗口时必须停掉(见 `detach`)。
	private var scrimAnimator: UIViewPropertyAnimator?

	private weak var host: UIViewController?
	private weak var scrollView: UIScrollView?
	private var offsetObservation: NSKeyValueObservation?
	private var sizeObservation: NSKeyValueObservation?

	/// 我们往 contentInset.top 里加过多少 —— 卸载时按这个数还,绝不越叠越高
	private var appliedInset: CGFloat = 0
	/// 当前这篇的标识,用来判断"换文章了"
	private var installedArticleID: String?
	/// 上次量出来的头区高度(内容宽度变化时要重算)
	private var measuredHeight: CGFloat = 0

	/// 内容总高上次变化的时刻 —— 进度条据此冻结(见 Style.progressFreezeSeconds)
	private var lastContentSizeChange: Date?
	private var lastProgress: CGFloat = 0
	/// 上次看到的内容总高 —— 用来判断这次变化是"大幅"还是"排版沉降"
	private var lastContentHeight: CGFloat = 0
	/// 源站主页 —— 点「源名 · 作者」那行时打开
	private var feedHomePageURL: URL?

	// MARK: - 装 / 卸

	override init() {
		super.init()
		configureViews()
	}

	private func configureViews() {
		// ⚠️ 容器本身**必须让点击穿过去**,否则整条头区会盖住下面的网页,
		// 正文里的链接、图片全点不动。只有"源名那一行"例外(见 NNWPassThroughView)。
		container.backgroundColor = .clear
		container.passThroughExcept = { [weak self] in self?.sourceLabel }

		scrimView.frame = .zero
		container.addSubview(scrimView)

		iconView.contentMode = .scaleAspectFill
		iconView.clipsToBounds = true
		iconView.layer.cornerCurve = .continuous
		container.addSubview(iconView)

		// 进度环:画在图标外面一圈
		ringLayer.fillColor = UIColor.clear.cgColor
		ringLayer.lineCap = .round
		ringLayer.strokeEnd = 0
		ringLayer.opacity = 0
		container.layer.addSublayer(ringLayer)

		restTitleLabel.numberOfLines = Style.restTitleMaxLines
		restTitleLabel.textColor = .label
		container.addSubview(restTitleLabel)

		dockedTitleLabel.numberOfLines = 1
		dockedTitleLabel.textColor = .label
		dockedTitleLabel.alpha = 0
		dockedTitleLabel.lineBreakMode = .byTruncatingTail
		container.addSubview(dockedTitleLabel)

		sourceLabel.numberOfLines = 1
		sourceLabel.font = .systemFont(ofSize: 12, weight: .medium)
		sourceLabel.textColor = .secondaryLabel
		sourceLabel.lineBreakMode = .byTruncatingTail
		// 点它打开源站 —— 网页里那行原本是个超链接,藏掉之后这份可点击性由我们接回来
		sourceLabel.isUserInteractionEnabled = true
		sourceLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(openFeedHomePage)))
		container.addSubview(sourceLabel)
	}

	/// 绑定 / 更新当前这篇文章。
	///
	/// 调用时机跟着 `nnwTrackCurrentArticleScrolling()` 走 —— 那是**已有的**方法,
	/// 网页加载完、翻页结束时都会调到,正是我们需要的两处。**不用往上游加新钩子。**
	func update(article: Article?, host: UIViewController, scrollView: UIScrollView?) {

		self.host = host

		guard let article, let scrollView else {
			detach()
			return
		}

		// 装容器(盖在网页之上、导航栏之下)
		if container.superview !== host.view {
			container.removeFromSuperview()
			host.view.addSubview(container)
		}
		host.view.bringSubviewToFront(container)

		// 换文章 → 换内容、重量高度、重置进度
		if installedArticleID != article.articleID {
			installedArticleID = article.articleID
			applyContent(for: article)
			measuredHeight = 0
			lastProgress = 0
			lastContentSizeChange = nil
			lastContentHeight = 0
		}

		bind(to: scrollView)
		layoutAndApply()
	}

	/// 把这篇文章的图标和标题装上
	private func applyContent(for article: Article) {
		let title = article.title ?? article.rawLink ?? ""
		restTitleLabel.text = title
		// 和其它页的标题同一套字体规则(西文 New York 衬线、中文思源宋体)
		let titleFont = TimelineStyle.headerTitleFont(for: title)
		restTitleLabel.font = titleFont
		dockedTitleLabel.text = title
		// ⚠️ 飘上去之后**必须还是同一个字体**,只是小一号(用户 2026-07-23 指出)。
		// 原来这里写死了系统黑体 —— 于是大标题是衬线、飞上去却变成黑体,
		// 看起来像"换了个标题",而不是"同一个标题飞上去了"。
		// `withSize` 会保住字族与字重,只改字号,正是要的。
		dockedTitleLabel.font = titleFont.withSize(Style.dockedTitleFontSize)

		// 「源名 · 作者」—— 作者可能没有,那就只显示源名(不留一个孤零零的分隔点)
		let feedName = article.feed?.nameForDisplay ?? ""
		let author = article.authors?.first?.name ?? ""
		sourceLabel.text = [feedName, author].filter { !$0.isEmpty }.joined(separator: " · ")

		feedHomePageURL = (article.feed?.homePageURL).flatMap { URL(string: $0) }

		iconView.image = IconImageCache.shared.imageForArticle(article)?.image
		iconView.isHidden = (iconView.image == nil)
	}

	private func bind(to scrollView: UIScrollView) {
		guard self.scrollView !== scrollView else { return }
		self.scrollView = scrollView
		offsetObservation = scrollView.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in
			MainActor.assumeIsolated { self?.layoutAndApply() }
		}
		sizeObservation = scrollView.observe(\.contentSize, options: [.new]) { [weak self] view, _ in
			MainActor.assumeIsolated {
				guard let self else { return }
				// ⚠️ **只有大幅变化才冻结进度**(翻译逐块替换那种)。
				// WKWebView 在图片陆续到货、排版沉降时会**反复**微调内容高度 ——
				// 每次都冻的话,进度看起来就是一跳一跳的(用户 2026-07-23 报的正是这个)。
				let newHeight = view.contentSize.height
				let ratio = self.lastContentHeight > 0
					? abs(newHeight - self.lastContentHeight) / self.lastContentHeight : 1
				if ratio > Style.significantContentChange {
					self.lastContentSizeChange = Date()
				}
				self.lastContentHeight = newHeight
				self.layoutAndApply()
			}
		}
	}

	/// 摘掉阅读栏,把 contentInset 还回去。
	func detach() {
		offsetObservation = nil
		sizeObservation = nil
		if let scrollView, appliedInset != 0 {
			scrollView.contentInset.top -= appliedInset
		}
		appliedInset = 0
		scrollView = nil
		installedArticleID = nil
		container.removeFromSuperview()
		stopScrimAnimator()
	}

	// MARK: - 毛玻璃浓度滑杆

	private func scrimAnimatorIfNeeded() -> UIViewPropertyAnimator {
		if let existing = scrimAnimator { return existing }
		let animator = UIViewPropertyAnimator(duration: 1, curve: .linear) { [weak self] in
			self?.scrimView.effect = UIBlurEffect(style: .systemThinMaterial)
		}
		// 到头也不自动结束 —— 结束后这根滑杆就作废了,之后喂进度没有任何反应
		animator.pausesOnCompletion = true
		scrimAnimator = animator
		return animator
	}

	private func stopScrimAnimator() {
		scrimAnimator?.stopAnimation(true)
		scrimAnimator = nil
		scrimView.effect = nil
	}

	// MARK: - 每帧:量 + 摆

	private func layoutAndApply() {

		guard let host, let scrollView, container.superview != nil else { return }

		let width = host.view.bounds.width
		guard width > 0 else { return }

		let safeTop = host.view.safeAreaInsets.top
		// 停靠区 = **导航栏下面**新起的一条。
		// 不再用导航栏那一条(它被返回键和上/下一篇占着,见 dockedStripHeight 的说明)。
		let dockBand = CGRect(x: 0, y: safeTop, width: width, height: Style.dockedStripHeight)

		// —— 头区高度(只在需要时重量)——
		if measuredHeight == 0 {
			let textWidth = width - Style.iconLeading * 2
			let sourceSize = sourceLabel.sizeThatFits(CGSize(width: textWidth, height: .greatestFiniteMagnitude))
			let titleSize = restTitleLabel.sizeThatFits(CGSize(width: textWidth, height: .greatestFiniteMagnitude))
			measuredHeight = Style.topPadding + Style.restIconSize + Style.iconTitleGap
				+ titleSize.height + Style.sourceTitleGap + sourceSize.height + Style.bottomPadding
			syncInset()
		}

		container.frame = CGRect(x: 0, y: 0, width: width, height: safeTop + measuredHeight)

		// —— 飞行进度(0 = 停在顶部,1 = 完全冻结)——
		let restY = -scrollView.adjustedContentInset.top
		let travelled = scrollView.contentOffset.y - restY
		let flight = min(max(travelled / Style.flightDistance, 0), 1)

		applyGeometry(flight: flight, width: width, dockBand: dockBand, safeTop: safeTop)
		applyProgressRing(scrollView: scrollView, flight: flight)
	}

	/// 内容往下让出头区的高度。**只在高度变了时做一次,绝不在每帧做**(L63)。
	private func syncInset() {
		guard let scrollView else { return }
		let target = measuredHeight
		guard abs(target - appliedInset) > 0.5 else { return }
		scrollView.contentInset.top += (target - appliedInset)
		appliedInset = target
	}

	private func applyGeometry(flight: CGFloat, width: CGFloat, dockBand: CGRect, safeTop: CGFloat) {

		// —— 图标:从头区里的大图标,竖直飞到停靠区,同时缩小 ——
		let iconSize = Style.restIconSize + (Style.dockedIconSize - Style.restIconSize) * flight
		let restIconCenterY = safeTop + Style.topPadding + Style.restIconSize / 2
		let iconCenterY = restIconCenterY + (dockBand.midY - restIconCenterY) * flight
		let iconCenterX = Style.iconLeading + iconSize / 2

		iconView.bounds = CGRect(x: 0, y: 0, width: iconSize, height: iconSize)
		iconView.center = CGPoint(x: iconCenterX, y: iconCenterY)
		iconView.layer.cornerRadius = iconSize / 2	// 正圆 —— 环要紧贴它当描边(见 ringWidth 的说明)

		// —— 两个标题的交接 ——
		let swap = min(max((flight - Style.swapStart) / max(1 - Style.swapStart, 0.01), 0), 1)

		let textWidth = width - Style.iconLeading * 2
		let sourceSize = sourceLabel.sizeThatFits(CGSize(width: textWidth, height: .greatestFiniteMagnitude))

		// 大标题:跟着往上走一截并轻微缩小,同时淡出。
		// (不试图把多行标题"变形"成单行 —— 那是做不到的,只能交接。)
		let restTitleTop = safeTop + Style.topPadding + Style.restIconSize + Style.iconTitleGap
		restTitleLabel.transform = .identity
		let titleSize = restTitleLabel.sizeThatFits(CGSize(width: textWidth, height: .greatestFiniteMagnitude))
		restTitleLabel.frame = CGRect(x: Style.iconLeading, y: restTitleTop,
									  width: textWidth, height: titleSize.height)
		let rise = (restTitleTop - dockBand.midY) * flight * 0.5	// 往上走一半路,剩下的交给淡出
		let shrink = 1 - 0.15 * flight
		restTitleLabel.transform = CGAffineTransform(translationX: 0, y: -rise)
			.scaledBy(x: shrink, y: shrink)
		restTitleLabel.alpha = 1 - swap

		// —— 「源名 · 作者」那一行 ——
		//
		// 停在顶部时它在**标题下方**(也就是网页原本那行表头的位置);
		// 往下滑就飞到小图标右边的上面一行。两端都是单行,所以**直接位移**,不用交接;
		// 也刻意让两端**字号相同** —— 一行小小的次要文字,缩放的收益微乎其微,
		// 而做缩放就得处理 transform 和 frame 打架、文字发虚。
		let restSourceY = restTitleTop + titleSize.height + Style.sourceTitleGap
		let dockedTextX = Style.iconLeading + Style.dockedIconSize + Style.dockedTitleGap
		let dockedSourceY = dockBand.minY + Style.dockedInnerPadding
		let sourceX = Style.iconLeading + (dockedTextX - Style.iconLeading) * flight
		let sourceY = restSourceY + (dockedSourceY - restSourceY) * flight
		sourceLabel.frame = CGRect(x: sourceX, y: sourceY,
								   width: max(width - sourceX - Style.iconLeading, 1),
								   height: sourceSize.height)

		// 冻结标题:排在小图标右边的**下面一行**,单行截断
		let dockedTitleY = dockedSourceY + sourceSize.height + 2
		dockedTitleLabel.frame = CGRect(x: dockedTextX, y: dockedTitleY,
										width: max(width - dockedTextX - Style.iconLeading, 1),
										height: dockBand.maxY - dockedTitleY - Style.dockedInnerPadding)
		dockedTitleLabel.alpha = swap

		// —— 毛玻璃底:后半段才现。高度要盖住**导航栏 + 我们这条窄条** ——
		// 正文会从它们背后滚过去,少盖一段就会看到文字从半空冒出来。
		scrimView.frame = CGRect(x: 0, y: 0, width: width, height: safeTop + Style.dockedStripHeight)
		scrimView.alpha = 1	// 恒为 1,浓度由滑杆调(L62)
		let scrimProgress = flight <= Style.scrimFadeStart ? 0
			: (flight - Style.scrimFadeStart) / max(1 - Style.scrimFadeStart, 0.01)
		let strength = min(max(scrimProgress, 0), 1) * Style.scrimStrength
		if strength > 0 {
			scrimAnimatorIfNeeded().fractionComplete = strength
		} else if scrimAnimator != nil {
			stopScrimAnimator()	// 回到顶部就停掉:它活着的时间越短越安全
		}
	}

	// MARK: - 进度环

	private func applyProgressRing(scrollView: UIScrollView, flight: CGFloat) {

		// 环画在图标外面一圈,跟着图标一起飞
		let iconSize = Style.restIconSize + (Style.dockedIconSize - Style.restIconSize) * flight
		// 圆心距 = 图标半径 + 线宽的一半 → 描边正好压在图标边缘上,图标填满环的内部
		let radius = iconSize / 2 + Style.ringWidth / 2
		let center = iconView.center
		let path = UIBezierPath(arcCenter: center, radius: radius,
								startAngle: -.pi / 2, endAngle: .pi * 1.5, clockwise: true)

		// ⚠️ 关掉 CALayer 的隐式动画 —— 否则每帧的 path/strokeEnd 变化都会被排成
		// 一段 0.25 秒的动画,环就跟不上手指了。
		CATransaction.begin()
		CATransaction.setDisableActions(true)
		ringLayer.path = path.cgPath
		ringLayer.lineWidth = Style.ringWidth
		ringLayer.strokeColor = Assets.Colors.primaryAccent.cgColor
		ringLayer.opacity = Float(flight)	// 和冻结同步现身:停在顶部时不需要它
		ringLayer.strokeEnd = readingProgress(in: scrollView)
		CATransaction.commit()
	}

	@objc private func openFeedHomePage() {
		guard let feedHomePageURL else { return }
		UIApplication.shared.open(feedHomePageURL)
	}

	/// 读到哪了 = 滚动位置 ÷ 可滚动总长。
	///
	/// **不需要区分阅读模式 / 译文**:阅读模式换了正文、翻译替换了段落,
	/// 网页的**内容总高自己就变了**,这个比值天然对应"当前渲染出来的东西"。
	/// 比按文本长度算更准,也不用去接翻译状态。
	///
	/// ⚠️ 但内容总高**跳变**时要冻一下:翻译是逐块替换的,图片也是异步到货的,
	/// 不冻的话进度会来回蹦。
	private func readingProgress(in scrollView: UIScrollView) -> CGFloat {

		if let changed = lastContentSizeChange, Date().timeIntervalSince(changed) < Style.progressFreezeSeconds {
			return lastProgress
		}

		let inset = scrollView.adjustedContentInset
		let visible = scrollView.bounds.height - inset.top - inset.bottom
		let scrollable = scrollView.contentSize.height - visible
		guard scrollable > 1 else { return 0 }

		let scrolled = scrollView.contentOffset.y + inset.top
		lastProgress = min(max(scrolled / scrollable, 0), 1)
		return lastProgress
	}
}

/// 一个「只有指定子视图吃点击、其余一律放行」的容器。
///
/// 为什么需要它:阅读栏是盖在网页**之上**的一层。若它整片都吃点击,
/// 正文里的链接、图片就全点不动了。而我们又确实需要其中**一行**可点(源名 → 打开源站)。
/// → `hitTest` 里只认那一个子视图,其余返回 nil,点击直接落到下面的网页上。
@MainActor final class NNWPassThroughView: UIView {

	/// 唯一允许接收点击的子视图(用闭包取,免得循环引用)
	var passThroughExcept: (() -> UIView?)?

	override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
		guard let target = passThroughExcept?(), !target.isHidden, target.alpha > 0.01 else { return nil }
		let inTarget = target.convert(point, from: self)
		return target.point(inside: inTarget, with: event) ? target : nil
	}
}

#endif
