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
	// 可点的部件用「按下有反馈」的子类(2026-07-24,让用户知道这里能点,见文件末尾两个小类)
	private let iconView = NNWTappableImageView()
	private let ringLayer = CAShapeLayer()
	/// 停在顶部时的大标题(多行、衬线)。点 = 开原文
	private let restTitleLabel = NNWTappableLabel()
	/// 冻结在顶栏里的小标题(单行)。点 = 开原文
	private let dockedTitleLabel = NNWTappableLabel()
	/// 「源名 · 作者」那一行。**两个状态共用同一个**(都是单行,直接平移过去就行)。点 = 开原文
	private let sourceLabel = NNWTappableLabel()

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
	/// 上次量高度时用的宽度 —— 宽度一变就得重量
	private var measuredWidth: CGFloat = 0

	/// 内容总高上次变化的时刻 —— 进度条据此冻结(见 Style.progressFreezeSeconds)
	private var lastContentSizeChange: Date?
	private var lastProgress: CGFloat = 0
	/// 上次看到的内容总高 —— 用来判断这次变化是"大幅"还是"排版沉降"
	private var lastContentHeight: CGFloat = 0
	/// 源站主页 —— 点**图标**时打开(2026-07-24 用户定的分工,见「点击」那节)
	private var feedHomePageURL: URL?
	/// 文章原文地址 —— 点标题 / 源名那行时打开
	private var articleURL: URL?
	/// 文章原标题(applyContent 时存下)
	private var baseTitle: String = ""
	/// [翻译] 标题的译文覆盖。非 nil 时标签显示它而不是原标题(见 setTitleOverride)
	private var titleOverride: String?

	/// 网页装载完了没(false = 还在装)。
	///
	/// ⚠️ **装载期间 WebKit 会自己重置滚动位置**,那一瞬的 contentOffset 不可信 ——
	/// 拿它算飞行进度会得出"半冻结"的鬼样子(2026-07-23 用户截图:翻页中途
	/// 大标题、冻结小标题、正文三层叠在一起)。所以**没装载完一律按"停在顶部"画**,
	/// didFinish 之后才信真实偏移。这是把挂载提前到 renderPage(治"表头闪现")的必要配套。
	private var contentSettled = true

	// MARK: - 装 / 卸

	override init() {
		super.init()
		configureViews()
	}

	private func configureViews() {
		// ⚠️ 容器本身**必须让点击穿过去**,否则整条头区会盖住下面的网页,
		// 正文里的链接、图片全点不动。只放行几个明确可点的部件(见 NNWPassThroughView):
		// 两个标题 + 源名那行(开原文)、图标(开主页)。
		container.backgroundColor = .clear
		container.passThroughTargets = { [weak self] in
			guard let self else { return [] }
			return [self.restTitleLabel, self.dockedTitleLabel, self.sourceLabel, self.iconView]
		}
		// 宽度变了就重新量、重新摆(转屏;也兜住"第一次布局时宽度还不对"的情况)
		container.onLayout = { [weak self] in self?.layoutAndApply() }
		// [方案 C] 页面被销毁 / 移出层级时,把毛玻璃动画器停掉,免得它在"活动中"被释放而崩溃(L62)
		container.onWillLeaveWindow = { [weak self] in self?.stopScrimAnimator() }

		scrimView.frame = .zero
		container.addSubview(scrimView)

		iconView.contentMode = .scaleAspectFill
		iconView.clipsToBounds = true
		iconView.layer.cornerCurve = .continuous
		// 点图标开源站主页(2026-07-24 用户定的分工:图标目标大、离标题远,主页归它)
		iconView.isUserInteractionEnabled = true
		iconView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(openFeedHomePage)))
		container.addSubview(iconView)

		// 进度环:画在图标外面一圈
		ringLayer.fillColor = UIColor.clear.cgColor
		ringLayer.lineCap = .round
		ringLayer.strokeEnd = 0
		ringLayer.opacity = 0
		container.layer.addSublayer(ringLayer)

		restTitleLabel.numberOfLines = Style.restTitleMaxLines
		restTitleLabel.textColor = .label
		restTitleLabel.highlightedTextColor = .secondaryLabel	// 按下变浅一档 = "能点"的反馈
		// 点标题开**原文**(2026-07-24 用户要求,分工见「点击」那节)
		restTitleLabel.isUserInteractionEnabled = true
		restTitleLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(openArticleURL)))
		container.addSubview(restTitleLabel)

		dockedTitleLabel.numberOfLines = 1
		dockedTitleLabel.textColor = .label
		dockedTitleLabel.highlightedTextColor = .secondaryLabel
		dockedTitleLabel.alpha = 0
		dockedTitleLabel.lineBreakMode = .byTruncatingTail
		dockedTitleLabel.isUserInteractionEnabled = true
		dockedTitleLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(openArticleURL)))
		container.addSubview(dockedTitleLabel)

		sourceLabel.numberOfLines = 1
		sourceLabel.font = .systemFont(ofSize: 12, weight: .medium)
		sourceLabel.textColor = .secondaryLabel
		sourceLabel.highlightedTextColor = .tertiaryLabel
		sourceLabel.lineBreakMode = .byTruncatingTail
		// 源名那行也开**原文**(不再开主页):字太小、冻结态又和标题挨得近,
		// 分两种行为必点错 → 和标题统一。主页改由图标负责。
		sourceLabel.isUserInteractionEnabled = true
		sourceLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(openArticleURL)))
		container.addSubview(sourceLabel)
	}

	/// 绑定 / 更新当前这篇文章。
	///
	/// 调用时机跟着 `nnwTrackCurrentArticleScrolling()` 走 —— 那是**已有的**方法,
	/// 网页加载完、翻页结束时都会调到,正是我们需要的两处。**不用往上游加新钩子。**
	/// `contentSettled`:true = 网页装载完(didFinish)、偏移可信;false = 刚开始装载;
	/// nil = 只是布局变化(转屏等),装载状态不变。
	func update(article: Article?, host: UIViewController, scrollView: UIScrollView?, contentSettled: Bool? = nil) {

		self.host = host
		if let contentSettled { self.contentSettled = contentSettled }

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
			titleOverride = nil		// [翻译] 标题覆盖只属于上一篇,换文章必须清掉
			applyContent(for: article)
			measuredHeight = 0
			measuredWidth = 0
			lastProgress = 0
			lastContentSizeChange = nil
			lastContentHeight = 0
		}

		// ⚠️ 换了滚动视图就必须重量一次高度并重新下推内容 ——
		// 否则 `measuredHeight` 还是上一页算的,新页的 inset 就补不上。
		let switchedScrollView = (self.scrollView !== scrollView)
		bind(to: scrollView)
		if switchedScrollView { measuredHeight = 0; measuredWidth = 0 }
		layoutAndApply()
	}

	/// 把这篇文章的图标和标题装上
	private func applyContent(for article: Article) {
		baseTitle = article.title ?? article.rawLink ?? ""
		applyTitleText()

		feedHomePageURL = (article.feed?.homePageURL).flatMap { URL(string: $0) }
		articleURL = article.preferredURL	// 点标题开原文用(2026-07-24)

		// 「源名 · 作者」—— 作者可能没有,那就只显示源名(不留一个孤零零的分隔点)。
		// 行尾的小 ↗ 是**常驻的"能点"提示**(2026-07-24 用户要求):这一行静止态贴着大标题、
		// 冻结态是第一行,两种状态都看得见 —— 一个符号覆盖整块"点了开原文"的区域。
		// 只在真有原文地址时加,免得挂一个点了没反应的箭头。
		let feedName = article.feed?.nameForDisplay ?? ""
		let author = article.authors?.first?.name ?? ""
		var sourceText = [feedName, author].filter { !$0.isEmpty }.joined(separator: " · ")
		if articleURL != nil, !sourceText.isEmpty {
			sourceText += "  ↗"
		}
		sourceLabel.text = sourceText

		iconView.image = IconImageCache.shared.imageForArticle(article)?.image
		iconView.isHidden = (iconView.image == nil)
	}

	/// 把「当前该显示的标题」写进两个标签(覆盖优先,没有覆盖用文章原标题)。
	///
	/// 字体每次都重挑 —— 覆盖成中文译文时要换到思源宋体,还原成英文时换回 New York
	/// (`headerTitleFont(for:)` 按文字内容选字体,正是干这个的)。
	private func applyTitleText() {
		let title = titleOverride ?? baseTitle
		restTitleLabel.text = title
		let titleFont = TimelineStyle.headerTitleFont(for: title)
		restTitleLabel.font = titleFont
		dockedTitleLabel.text = title
		// ⚠️ 飘上去之后**必须还是同一个字体**,只是小一号(用户 2026-07-23 指出):
		// `withSize` 保住字族与字重,只改字号。
		dockedTitleLabel.font = titleFont.withSize(Style.dockedTitleFontSize)
	}

	/// [翻译] 用译文覆盖标题(nil = 撤销覆盖,回到文章原标题)。
	///
	/// 为什么需要:阅读栏把网页标题藏掉、由 UIKit 重画,而翻译只改了网页里那份 ——
	/// 不喂给这里,用户看到的标题永远是原文(2026-07-24 用户报的)。
	/// 换标题后**必须重量高度**:中文标题通常比英文短,行数可能从 3 行变 2 行,
	/// 不重量的话正文上方会留一段空白(measuredHeight 归零,layoutAndApply 会重量并同步 inset)。
	func setTitleOverride(_ text: String?) {
		guard titleOverride != text else { return }
		titleOverride = text
		applyTitleText()
		measuredHeight = 0
		layoutAndApply()
	}

	private func bind(to scrollView: UIScrollView) {
		guard self.scrollView !== scrollView else { return }

		// ⚠️ **换页之前,先把上一页的 contentInset 还回去**(2026-07-23 真机实测的 bug):
		// 一条阅读栏要伺候好几个网页(UIPageViewController 会预载前后页)。
		// 原来换页时只是把 `scrollView` 指过去,却没有还旧那一页的 inset ——
		// 于是 ①旧页永远多出一段顶部空白;②`appliedInset` 记着的是旧页的数,
		// 新页 syncInset 时算出的差值接近 0 → **新页根本没被下推**,
		// 正文顶到阅读栏底下,而"停在顶部"的基准位置也就错了 ——
		// 表现就是用户报的「拉到最上面还是显示冻结后的样子」。
		releaseInset()
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

	/// 把当前这一页的 contentInset 还回去(换页、卸载都要做)。
	private func releaseInset() {
		if let scrollView, appliedInset != 0 {
			let offsetBefore = scrollView.contentOffset.y
			scrollView.contentInset.top -= appliedInset
			scrollView.contentOffset.y = offsetBefore + appliedInset	// 理由同 syncInset
		}
		appliedInset = 0
	}

	/// 摘掉阅读栏,把 contentInset 还回去。
	func detach() {
		offsetObservation = nil
		sizeObservation = nil
		releaseInset()
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

		// ⚠️ **不在窗口上就什么都不做**(2026-07-23 修一个必崩:页面被滑走销毁时,
		// 惯性滚动还在每帧触发 KVO 回调 —— 这里若继续跑,会把刚被 willMove(toWindow:)
		// 停掉的毛玻璃动画器**又重新建出来**,随后页面释放,动画器在"活动中"被释放 → 崩(L62)。
		// 崩溃栈里 _smoothScrollWithUpdateTime + UIViewPropertyAnimator dealloc 就是这条路。)
		// 页面被滑回来时 layoutSubviews 会再触发 onLayout,一切自动恢复。
		guard container.window != nil else { return }

		let width = host.view.bounds.width
		guard width > 0 else { return }

		let safeTop = host.view.safeAreaInsets.top
		// 停靠区 = **导航栏下面**新起的一条。
		// 不再用导航栏那一条(它被返回键和上/下一篇占着,见 dockedStripHeight 的说明)。
		let dockBand = CGRect(x: 0, y: safeTop, width: width, height: Style.dockedStripHeight)

		// —— 头区高度 ——
		// ⚠️ **宽度变了也要重量**(转屏、分屏):原来只在"高度为 0"时算一次,
		// 于是换了宽度之后标题行数变了,内容却还按旧高度下推,正文要么被压住要么空一截。
		let textWidth = width - Style.iconLeading * 2
		if measuredHeight == 0 || abs(measuredWidth - width) > 0.5 {
			measuredWidth = width
			let sourceSize = sourceLabel.sizeThatFits(CGSize(width: textWidth, height: .greatestFiniteMagnitude))
			measuredHeight = Style.topPadding + Style.restIconSize + Style.iconTitleGap
				+ titleHeight(width: textWidth) + Style.sourceTitleGap + sourceSize.height + Style.bottomPadding
			syncInset()
		}

		container.frame = CGRect(x: 0, y: 0, width: width, height: safeTop + measuredHeight)

		// —— 飞行进度(0 = 停在顶部,1 = 完全冻结)——
		// ⚠️ 网页还没装载完时偏移不可信(WebKit 装载中会自己重置滚动位置),
		// 一律按"停在顶部"画;didFinish 之后才用真实偏移(见 contentSettled 的说明)。
		let flight: CGFloat
		if contentSettled {
			let restY = -scrollView.adjustedContentInset.top
			let travelled = scrollView.contentOffset.y - restY
			flight = min(max(travelled / Style.flightDistance, 0), 1)
		} else {
			flight = 0
		}

		applyGeometry(flight: flight, width: width, dockBand: dockBand, safeTop: safeTop)
		applyProgressRing(scrollView: scrollView, flight: flight)
	}

	/// 内容往下让出头区的高度。**只在高度变了时做一次,绝不在每帧做**(L63)。
	///
	/// ⚠️⚠️ **改 inset 的同时必须把 contentOffset 挪同样的距离**
	/// (2026-07-23 真机上一连三个症状,都是漏了这一步):
	///
	/// 顶部内边距一加,"滚到顶"这个基准就从 0 变成了 −250 —— 可内容还停在 0,
	/// 于是**一进文章就等于「已经往下滚了 250pt」**。后果按对齐程度依次是:
	///   · 完全没对上 → 飞行进度直接算成 1:一进来就是冻结态,正文被压在栏底下
	///   · 对上一半   → 进度停在中间:两套元素(大标题 + 冻结小标题)同时画,叠成一团
	///   · 换页残留   → 「拉到最上面还是冻结的样子」
	/// 三个看起来完全不同的现象,其实是同一处漏掉。
	///
	/// 补上这一行之后,视觉位置在改 inset 前后**完全不动**,"顶"仍然是"顶"。
	/// (先记下改之前的偏移再算,而不是相信系统会不会自己调 —— 那个行为随场景而变,不可靠。)
	private func syncInset() {
		guard let scrollView else { return }
		let delta = measuredHeight - appliedInset
		guard abs(delta) > 0.5 else { return }
		let offsetBefore = scrollView.contentOffset.y
		scrollView.contentInset.top += delta
		scrollView.contentOffset.y = offsetBefore - delta
		appliedInset = measuredHeight
	}

	/// 量标题真正要占多高。
	///
	/// ⚠️ **必须用 `textRect(forBounds:limitedToNumberOfLines:)`,不能用 `sizeThatFits`**
	/// (2026-07-23 用户报「文字错乱」才发现):
	/// 那两个在多行 + 自定义字体的情况下会给出**不一样的**结果,而 UILabel 画字时用的是前者。
	/// 一旦算矮了,UILabel **不会裁剪**,多出来的行会溢出框外、压在下面那行上 ——
	/// 表现就是源名和标题叠在一起。
	private func titleHeight(width: CGFloat) -> CGFloat {
		let bounds = CGRect(x: 0, y: 0, width: width, height: .greatestFiniteMagnitude)
		return ceil(restTitleLabel.textRect(forBounds: bounds,
											limitedToNumberOfLines: Style.restTitleMaxLines).height)
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
		let titleH = titleHeight(width: textWidth)
		restTitleLabel.frame = CGRect(x: Style.iconLeading, y: restTitleTop,
									  width: textWidth, height: titleH)
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
		let restSourceY = restTitleLabel.frame.maxY + Style.sourceTitleGap
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

	// MARK: - 点击(2026-07-24 用户定的分工)
	//
	// | 点哪 | 开什么 | 为什么 |
	// |---|---|---|
	// | 大标题 / 冻结小标题 / 「源名·作者」 | **文章原文** | 源名那行字太小,冻结态又和标题挨得近,分成两种行为必点错 → 统一开原文 |
	// | 图标(带进度环那个) | **源站主页** | 离标题远、目标独立,不会误触 |
	//
	// 打开一律走 NNWLinkOpener:跟着设置里「app 内打开链接」的开关走,默认 app 内。

	@objc private func openArticleURL() {
		guard let articleURL else { return }
		NNWLinkOpener.open(articleURL, from: host)
	}

	@objc private func openFeedHomePage() {
		guard let feedHomePageURL else { return }
		NNWLinkOpener.open(feedHomePageURL, from: host)
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

	/// 允许接收点击的子视图们(用闭包取,免得循环引用)。
	/// 2026-07-24 从"只有源名一行"扩成一组:标题×2 + 源名(开原文)、图标(开主页)。
	var passThroughTargets: (() -> [UIView])?

	/// 容器尺寸变了(转屏、分屏、首次布局)时叫一声 —— 头区要按新宽度重量。
	var onLayout: (() -> Void)?

	/// **即将离开窗口**(所属页面被销毁 / 移出层级)时叫一声。
	/// ⚠️ 这是**方案 C 之后必须补的一环**(L62):每页一份之后,滑走一页 = 那一页连同它的
	/// 阅读栏一起销毁,而毛玻璃动画器若正停在"活动中"被释放会**直接崩溃**。
	/// 所以离开窗口时先把它停掉。整页共享那版几乎不销毁,才一直没暴露这个坑。
	var onWillLeaveWindow: (() -> Void)?

	override func layoutSubviews() {
		super.layoutSubviews()
		onLayout?()
	}

	override func willMove(toWindow newWindow: UIWindow?) {
		super.willMove(toWindow: newWindow)
		if newWindow == nil {
			onWillLeaveWindow?()
		}
	}

	override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
		for target in passThroughTargets?() ?? [] {
			guard !target.isHidden, target.alpha > 0.01 else { continue }	// 藏着/淡出的不吃点击(冻结态的大标题已透明,点那里应该落到网页上)
			let inTarget = target.convert(point, from: self)
			if target.point(inside: inTarget, with: event) { return target }
		}
		return nil		// 其余一律穿透给下面的网页 —— 正文的链接、图片还要能点
	}
}

// MARK: - 按下有反馈的小部件(2026-07-24,"能点"的通用信号)
//
// 用户想让标题/图标看起来"可能能点"。没用浮雕 —— 那是拟物时代的手法,
// 压在暖纸+衬线的安静排版上很突兀。改用 iOS 通用的两件套:
// **按下瞬间变浅/变淡**(下面这两个小类)+ 源名行尾常驻一个小 ↗(见 applyContent)。
//
// ⚠️ 反馈刻意不用 alpha/transform 做在标题上 —— 那两个属性被飞行动画每帧驱动着
// (applyGeometry),再叠一层按下动画必打架。标签用 `isHighlighted`(纯换色,
// 谁也不碰),图标用 alpha(它的 alpha 没人驱动)。

/// 按下时文字变浅一档的标签(颜色在创建处用 highlightedTextColor 配)
@MainActor final class NNWTappableLabel: UILabel {

	override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
		super.touchesBegan(touches, with: event)
		isHighlighted = true
	}

	override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
		super.touchesEnded(touches, with: event)
		isHighlighted = false
	}

	/// 点按手势识别成功时系统会取消触摸 —— 这条也要还原,否则高亮态卡住
	override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
		super.touchesCancelled(touches, with: event)
		isHighlighted = false
	}
}

/// 按下时变淡的图片(给图标用)
@MainActor final class NNWTappableImageView: UIImageView {

	override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
		super.touchesBegan(touches, with: event)
		alpha = 0.55
	}

	override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
		super.touchesEnded(touches, with: event)
		UIView.animate(withDuration: 0.15) { self.alpha = 1 }
	}

	override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
		super.touchesCancelled(touches, with: event)
		UIView.animate(withDuration: 0.15) { self.alpha = 1 }
	}
}

#endif
