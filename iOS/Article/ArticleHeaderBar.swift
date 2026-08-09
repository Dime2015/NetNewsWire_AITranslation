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
import os

@MainActor final class ArticleHeaderBarController: NSObject {

	private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "app", category: "ReadingBar")

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

		/// 网页还在装载时,滚动偏移要**超过静止位这么多**才算"用户真的在滑"。
		///
		/// WebKit 装载中会自己把滚动位置重置回静止位附近,那种抖动不该让头区跟着飞;
		/// 而用户真的用手指滑动时,一下就远超这个值。取小一点,让头区跟手不迟钝。
		/// 详见 `layoutAndApply` 里 `contentSettled == false` 那一段。
		static let settleGrace: CGFloat = 8
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

		/// 🔴 **翻页时"安全区还没到"的那段,要不要用 transform 把正文垫住**(2026-08-09 第十九轮)。
		///
		/// ⚠️ **出问题就把它改成 `false`,一行就能关掉整套补偿** ——
		/// 上一轮我把 app 弄成白屏假死过,这次留个闸(L137)。
		static let compensatesLateSafeArea = true
		/// 垫付的上限。安全区最多也就 116pt 上下;超过这个数说明我算错了,宁可不垫。
		static let maxSafeDebt: CGFloat = 200

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

	/// 安全区自愈请求是否已在路上(T24,防止每帧都发一次)
	private var pendingSafeAreaNudge = false

	/// ⚠️ 临时探针(2026-08-09 第五轮,查完就删):上一次打出来的「让路」状态。
	///
	/// 排版每帧都跑,所以**只在状态翻转时打一行**,不刷屏。
	/// 用途是补上 L124/L132 定死的那条硬规矩 ——
	/// **带条件的钩子,交付前必须有一次"它被走到了"的证据**,而不是读代码推断。
	/// 下面那个「拽的时候让路」的口子已经被我写错过两次(`host as?` 恒为 nil),
	/// 这一次要有正面证据才算数。
	private var nnwLoggedPullProbe: String?

	/// ⚠️ 临时探针(2026-08-09 第七轮,查完就删):一次翻页动画期间,
	/// 排版被叫了多少次,以及**它读到的每一个会变的量各自扫过多大范围**。翻完打一行。
	///
	/// 第六轮只量了安全区,结果是 `116→116`(一动不动)—— 假设被推翻,
	/// 可 `排版=51 次` 说明**高频重排本身是真的**,只是驱动它的是别的量。
	/// 📌 判据:**推翻一个假设之后,别急着换一个假设去改代码 ——
	/// 先把"这个函数里所有会变的量"一次全量出来,让数字自己指认。**
	/// 最近一次**在可信几何下**算出来的飞行进度。翻页动画期间拿它顶着,不再跟着中间态跳。
	/// 新页从来没记过 → 0 → 大标题态,正是它该有的样子。见 `layoutAndApply` 里的说明。
	private var nnwLastGoodFlight: CGFloat = 0

	/// ⚠️ 临时探针(2026-08-09 第十三轮,查完就删):盯住这一页的 `contentInset` 被谁改。
	/// 装卸和另外两条观察一样(`bind` 里装、`detach` 里摘),只读不写。
	private var insetObservation: NSKeyValueObservation?
	/// 上一次记过的 `inset上`,用来只打"真的变了"的那些(KVO 会因别的字段变动重复响)。
	private var nnwLastLoggedInsetTop: CGFloat = .greatestFiniteMagnitude
	/// 这一页已经抓过几次调用栈(抓栈不便宜,每页封顶 8 次,别让探针自己拖慢现场)。
	private var nnwInsetStackDumps = 0

	private var nnwTurnLayoutCount = 0
	private var nnwTurnFlight = (min: CGFloat.greatestFiniteMagnitude, max: -CGFloat.greatestFiniteMagnitude)
	private var nnwTurnOffset = (min: CGFloat.greatestFiniteMagnitude, max: -CGFloat.greatestFiniteMagnitude)
	private var nnwTurnInset = (min: CGFloat.greatestFiniteMagnitude, max: -CGFloat.greatestFiniteMagnitude)
	private var nnwTurnContentH = (min: CGFloat.greatestFiniteMagnitude, max: -CGFloat.greatestFiniteMagnitude)
	/// 第十三轮补量:翻页期间**阅读栏自己的几何**动没动(安全区、头区容器高)。
	private var nnwTurnSafeTop = (min: CGFloat.greatestFiniteMagnitude, max: -CGFloat.greatestFiniteMagnitude)
	private var nnwTurnContainerH = (min: CGFloat.greatestFiniteMagnitude, max: -CGFloat.greatestFiniteMagnitude)

	/// ⚠️ 临时探针(2026-08-09 第十五轮,查完就删):记一个量在**一次翻页里**的
	/// 「首帧 / 末帧 / 最小 / 最大」。
	///
	/// 🔴 **必须有首末,不能只有 min→max**:上一轮打的 `安全区 62→116` 是范围,
	/// **看不出方向** —— 而"从 62 涨到 116"(新页还没接上导航栏)和
	/// "从 116 掉到 62"(它被摘掉了)是完全不同的两件事,修法也完全相反。
	/// 📌 判据:**一个"范围"回答不了"先后",而先后往往就是因果。**
	private struct NNWTurnTrace {
		var first: CGFloat = .nan
		var last: CGFloat = .nan
		var low: CGFloat = .greatestFiniteMagnitude
		var high: CGFloat = -.greatestFiniteMagnitude
		mutating func add(_ value: CGFloat) {
			if first.isNaN { first = value }
			last = value
			low = Swift.min(low, value)
			high = Swift.max(high, value)
		}
		var text: String { String(format: "首%.0f→末%.0f(%.0f~%.0f)", first, last, low, high) }
	}

	/// 翻页期间三个"安全区候选来源"各自的走势 —— 下一轮要挑一个**稳定**的当基准。
	private var nnwTurnHostSafe = NNWTurnTrace()			// 宿主(WebViewController)的
	private var nnwTurnPageSafe = NNWTurnTrace()			// 文章页(ArticleViewController)的
	private var nnwTurnWindowSafe = NNWTurnTrace()			// 窗口的

	/// 🔴 **滚动视图自己的安全区** —— 用户 2026-08-09「翻成了就一定抖」那句话之后锁定的头号嫌疑。
	/// 它和 `offset` 一起看:安全区涨了 116 而 offset 没跟着走,正文就真的跳了 116pt。
	private var nnwTurnScrollSafe = NNWTurnTrace()
	/// offset 的**首末**(上面那个 `nnwTurnOffset` 只有 min/max,看不出它有没有跟着安全区走)。
	private var nnwTurnOffsetTrace = NNWTurnTrace()
	/// 🎯 第十七轮的验收量:**夹后的顶部总量**(我们写的 + 系统的安全区)。
	/// 修好之后它必须全程恒定 —— 这是"正文不再跳"的数字版说法。
	private var nnwTurnAdjustedTrace = NNWTurnTrace()

	// MARK: - 安全区垫付(第十九轮,治"翻页时正文掉 116pt")

	/// 此刻替系统垫着多少安全区(用 `transform` 画上去的位移,**不碰滚动状态**)。
	private var nnwSafeDebt: CGFloat = 0
	/// 这一页"欠多少"是否已经**定过了**。
	///
	/// 🔴 **这个标志是防振荡的核心。** 垫付量算自 `safeAreaInsets`,
	/// 而本项目早有实测(T24/第七轮):**平移一个视图会真的改变它的安全区**。
	/// 也就是说"垫付"和"依据"互为因果 —— 天然是个反馈环。
	/// 所以设计成**单向**:一页只在第一次排版时定一次,之后**只会归零,永不再抬高**。
	/// 单向 ⇒ 状态机没有回路 ⇒ **数学上不可能振荡**,最坏情况也只是回到"不垫"的现状。
	private var nnwSafeDebtLatched = false
	/// 探针用:定下垫付时的滚动视图安全区,和撤销时的。查完就删。
	private var nnwSafeDebtAtLatch: CGFloat = 0

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
		// [翻译] 列表那套「标题翻译」已经翻过这条的话,进文章页直接显示中文标题
		// (2026-07-29 用户要求)。只查缓存不发请求;正文翻译如果稍后给出自己的译文,
		// 会通过 titleOverride 盖在上面,互不打架。
		baseTitle = NNWTitleTranslationController.shared.cachedTranslatedTitle(for: article)
			?? article.title ?? article.rawLink ?? ""
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
		// ⚠️ 换页之前**先把垫付撤回给旧那一页** —— 位移是画在旧网页上的,
		// 指针一换就再也够不着它了,会永久留下一个歪掉的页面(和 `releaseInset` 同一个道理)。
		nnwApplySafeDebt(0)
		releaseInset()
		self.scrollView = scrollView
		// 新的一页重新开始:允许再定一次垫付量(见 `nnwSafeDebtLatched` 的说明)。
		nnwSafeDebtLatched = false
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

		// ⚠️ 临时探针(2026-08-09 第十三轮,查完就删):**任何人**改这一页的 contentInset 都记一行。
		//
		// 为什么不能只盯着我们自己那两处:上游 `WebViewController.loadWebView()` 里有一行
		// `webView.scrollView.contentInset = UIEdgeInsets(top: 0, left: -1, bottom: 0, right: 0)`
		// (修 iPad 横向橡皮筋的老 hack),而**网页是从池子里复用的** ——
		// 它会把整条 inset 连同我们加的那一段**一起抹平**,而 `appliedInset` 还记着旧数,
		// 之后的加减法就全错了。这条 KVO 谁写都拦得到,不用去改上游那一行。
		//
		// ⚠️ **只观察、不改任何东西**,所以不会引起递归重排(L63 那条硬约束的射程内)。
		// 📌 沉默要有含义:下面装完先无条件打一行"探针已装" ——
		// 万一 UIEdgeInsets 这种非对象类型 KVO 不响,日志里一行都没有时才分得清
		// 是"没人改过"还是"仪器根本没通电"(第五轮那条探针纪律)。
		nnwInsetStackDumps = 0
		nnwLastLoggedInsetTop = scrollView.contentInset.top
		insetObservation = scrollView.observe(\.contentInset, options: []) { [weak self] view, _ in
			MainActor.assumeIsolated { self?.nnwLogInsetChanged(view) }
		}
		let bindTag = UInt(bitPattern: ObjectIdentifier(scrollView).hashValue) % 9973
		NNWArticlePagingLog.logger.info("""
			[拽] 内边距探针已装 页=\(bindTag, privacy: .public) \
			| 此刻 inset上=\(scrollView.contentInset.top, privacy: .public) \
			| 我们共加过=\(self.appliedInset, privacy: .public)
			""")
	}

	/// ⚠️ 临时探针(第十三轮,查完就删):这一页的 contentInset 被**任何人**改了。
	///
	/// 翻页动画期间还会顺带抓一小段调用栈 —— 「谁改的」这个问题,读代码是猜,栈是答案。
	/// ⚠️ 抓栈本身不便宜,所以**只在翻页期间、且改动超过 1pt 时抓,每次翻页最多 8 条**:
	/// 探针把机器拖慢,量到的就不是原来那个现场了。
	private func nnwLogInsetChanged(_ scrollView: UIScrollView) {
		let top = scrollView.contentInset.top
		guard abs(top - nnwLastLoggedInsetTop) > 0.5 else { return }
		let previous = nnwLastLoggedInsetTop
		nnwLastLoggedInsetTop = top

		let articleHost = nnwArticleHost
		let turning = articleHost?.nnwIsTurningPage ?? false
		let stage = turning ? "翻页中" : ((articleHost?.nnwIsPullingToTurnPage ?? false) ? "拽中" : "平时")
		let pageTag = UInt(bitPattern: ObjectIdentifier(scrollView).hashValue) % 9973
		NNWArticlePagingLog.logger.info("""
			[拽] inset被改 \(stage, privacy: .public) \
			| \(previous, privacy: .public)→\(top, privacy: .public) \
			| 我们共加过=\(self.appliedInset, privacy: .public) \
			| offset=\(scrollView.contentOffset.y, privacy: .public) | 页=\(pageTag, privacy: .public)
			""")

		if turning, abs(top - previous) > 1, nnwInsetStackDumps < 8 {
			nnwInsetStackDumps += 1
			let frames = Thread.callStackSymbols.dropFirst(1).prefix(7).joined(separator: "\n")
			NNWArticlePagingLog.logger.info("[拽] inset被改 · 谁改的:\n\(frames, privacy: .public)")
		}
	}

	/// 把当前这一页的 contentInset 还回去(换页、卸载都要做)。
	private func releaseInset() {
		if let scrollView, appliedInset != 0 {
			let offsetBefore = scrollView.contentOffset.y
			scrollView.contentInset.top -= appliedInset
			scrollView.contentOffset.y = offsetBefore + appliedInset	// 理由同 syncInset
			nnwLogInsetWrite("还旧页", delta: -appliedInset, scrollView: scrollView,
							 offsetBefore: offsetBefore, offsetAfter: scrollView.contentOffset.y)
		}
		appliedInset = 0
	}

	/// 摘掉阅读栏,把 contentInset 还回去。
	func detach() {
		offsetObservation = nil
		sizeObservation = nil
		insetObservation = nil		// ⚠️ 第十三轮的临时探针,和上面两条同生共死
		nnwApplySafeDebt(0)			// 卸载前一定把垫付撤掉,别留下歪掉的网页
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

		// ⚠️ 安全区兜底(T24,2026-07-25 真机偶发):快速滑动撞上页面装载时,
		// 这一页视图的 safeAreaInsets 可能**没被系统灌进来**(读出来是 0),而屏幕上
		// 状态栏、返回键明明都在 —— 用 0 排版,标题顶进状态栏、压住返回键;
		// 且每帧都读到同一个错值,滚动永远不会自己好(用户实测:只有换文章才恢复)。
		// 两道处理:
		// ① 这一帧先用「窗口的安全区」兜底 —— 那是系统此刻真实的状态栏高度,
		//    不经过宿主视图传播,不会跟着一起坏(正常时宿主值 ≥ 窗口值,max 不改变任何行为);
		// ② 差值出现时**另起一拍**请求父级重排(不在滚动回调里同步改布局 —— L63):
		//    系统把安全区补灌进来后,safeAreaInsetsDidChange 会拉我们重排,
		//    网页内容的 adjustedContentInset 也随之复位,整体自愈。
		let hostSafeTop = host.view.safeAreaInsets.top
		let windowSafeTop = container.window?.safeAreaInsets.top ?? 0
		// 🔴 **正在"拽过头翻页"时,这条自愈必须让路**(2026-08-09,用户报"标题和正文一直抖动")。
		//
		// 那个手势会给翻页容器加一个 `transform` 平移(把正文推开、给箭头让位),
		// 而**平移一个视图会真的改变它的安全区** —— 视图往下挪了,压在状态栏底下的部分就少了,
		// `safeAreaInsets.top` 从 62 掉到 44。
		// 这条自愈的前提是"host < window 一定是系统没传播",而现在**多了一个合法原因**,
		// 于是它每帧请求一次重排、重排又触发下一帧 —— 真机日志里刷了 150 多条,那就是抖动本身。
		//
		// 📌 判据(L122 的又一次):**一条"异常检测"要连着它的适用范围一起记。**
		// T24 当初若写成「**在没人主动位移这一层的前提下**,host < window 就是没传播」,
		// 这次加位移时就会立刻想到要给它开个口子。
		//
		// ⚠️ 让路是安全的:上面 `safeTop` 取的是 `max(host, window)`,拽的过程中它恒等于
		// window 那个值(稳定、正确),**排版不受影响**,只是不再徒劳地请求重排。
		// 🔴 **必须往上找,`host` 不是 `ArticleViewController`**(2026-08-09,第二次才修对):
		// 这条栏的 `host` 是 `WebViewController`(见 `WebViewController+ReadingBar.swift` 的调用),
		// 上一版写成 `host as? ArticleViewController` —— **恒为 nil,这个口子从来没打开过**,
		// 用户报的抖动一次都没被治到。又一次 L124:**钩子挂在了一个不成立的分支上。**
		// 判据:**写 `as?` 之前,先去调用方确认那个参数到底是什么类型。**
		//(这段"往上找"已抽成 `nnwArticleHost` —— 第十三轮那两条内边距探针要用同一份,
		// 抄第二份迟早会和这份走岔。行为与原来逐字相同。)
		let articleHost = nnwArticleHost
		let isPullingToTurnPage = articleHost?.nnwIsPullingToTurnPage ?? false
		let isTurningPage = articleHost?.nnwIsTurningPage ?? false

		// 🔴🔴 **2026-08-09 第七轮:这里曾经改成"翻页期间用窗口的安全区",那是错的,已回退。**
		//
		// 当时的假设:滑进来的那一页有一截在窗口顶边外,它自己的安全区每帧都不一样。
		// **探针一量就推翻了**:`宿主安全区 从=116 到=116`,整个动画期间**一动不动**。
		//
		// 而且那一改**当场制造了一个新 bug**:`host=116`(状态栏 62 + 导航栏 54),
		// `window=62` —— 改成用窗口值等于**凭空砍掉导航栏那 54pt**,
		// 标题直接顶到导航栏底下,用户报的"标题和顶部控件重叠"就是这么来的。
		//
		// 📌 两条判据(都是老账的新一遍):
		// 1. **`max(host, window)` 里 host 更大是常态,不是异常** ——
		//    宿主视图在导航控制器里,它的安全区本来就含导航栏。
		//    动它之前先问"这两个值平时到底谁大"(L123:我量到了 ≠ 我量的是它)。
		// 2. **猜到病根就动刀,是把"假设"当成"结论"。** 这一轮的正确顺序是
		//    先埋探针跑一次、看见 116→116,再决定改什么。**探针救了这一刀,但它本不该挨这一刀。**
		let safeTop = max(hostSafeTop, windowSafeTop)

		// ⚠️ 临时探针(2026-08-09 第五轮,查完就删):证明上面那条 `articleHost` **真的被走到了**。
		//
		// ⚠️ **必须连"有没有找到宿主"一起打** —— 只打让路状态是不够的:
		// 万一 parent 链断了,`articleHost` 恒为 nil、这个值恒为 false、**一次都不会翻转**,
		// 于是日志一片空白 —— 而"没有日志"根本分不清是**口子没生效**还是**用户没拽**。
		// 📌 判据(L132 那三次栽跟头的形状):**探针的"沉默"必须是有含义的,
		// 否则它证明不了任何事。** 所以第一次排版就先把"找没找到宿主"打出来。
		let pullProbe = (articleHost == nil ? "🔴没找到ArticleViewController" : "找到宿主")
			+ (isPullingToTurnPage ? " / 让路中" : " / 不让路")
			+ (isTurningPage ? " / 翻页中" : "")
		if pullProbe != nnwLoggedPullProbe {
			nnwLoggedPullProbe = pullProbe
			NNWArticlePagingLog.logger.info("[拽] 让路探针:\(pullProbe, privacy: .public)")
		}

		// ⚠️ 翻页动画期间这条自愈也要让路:此刻 host 比 window **大**(不是小),
		// 条件本来就不成立;但万一滑到某一帧反过来了,重排只会给动画添乱。
		if hostSafeTop + 0.5 < windowSafeTop, !pendingSafeAreaNudge, !isPullingToTurnPage, !isTurningPage {
			pendingSafeAreaNudge = true
			Self.logger.info("[外观] 阅读栏:宿主安全区疑似未传播(host=\(hostSafeTop, privacy: .public), window=\(windowSafeTop, privacy: .public)),已请求重排自愈(T24)")
			DispatchQueue.main.async { [weak self] in
				guard let self else { return }
				self.pendingSafeAreaNudge = false
				self.host?.view.superview?.setNeedsLayout()
				self.host?.view.setNeedsLayout()
			}
		}
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

		// [外观] 第十九轮:翻页时替系统垫上它还没送到的安全区(用 transform,不碰滚动状态)。
		// ⚠️ 这里**每帧都调是安全的** —— 它只读、只画 transform,
		// 而且是**单向状态机**(定一次 → 归零),不写任何滚动状态,不会形成 L137 那个环。
		nnwUpdateSafeDebt(expectedSafeTop: safeTop, scrollView: scrollView, isTurningPage: isTurningPage)

		// 🔴🔴 **2026-08-09 第十七轮:这里曾经改成"每次排版都问一次 syncInset(带安全区补偿)",
		// 结果真机白屏假死,已全部回退。** 来龙去脉见 NOTES-todo「第十八轮」和 **L137**。
		// ⚠️ 本文件开头那条硬约束("绝不在滚动回调里碰 contentInset / safeArea",L63 的
		// 28000 层递归)**就是在说这件事** —— 我加了「不足 0.5pt 不落笔」的守卫就以为安全了,
		// 但那个守卫只在"目标值稳定"时才成立;补偿量本身依赖 `safeAreaInsets`,
		// 而 `safeAreaInsets` 会被 inset 的写入反过来影响 → 目标值来回跳 → 每帧都写 → 卡死。
		// **别再把 `syncInset` 挪进每帧的路径。**

		container.frame = CGRect(x: 0, y: 0, width: width, height: safeTop + measuredHeight)

		// —— 飞行进度(0 = 停在顶部,1 = 完全冻结)——
		// ⚠️ 网页还没装载完时偏移不可信(WebKit 装载中会自己重置滚动位置),
		// 一律按"停在顶部"画;didFinish 之后才用真实偏移(见 contentSettled 的说明)。
		let restY = -scrollView.adjustedContentInset.top
		let travelled = scrollView.contentOffset.y - restY
		let measuredFlight = min(max(travelled / Style.flightDistance, 0), 1)

		// ⚠️ 临时探针(第十三轮):**解冻那一下跳了多大**,必须在下面这段把它覆盖掉之前抓住。
		let frozenFlightBefore = nnwLastGoodFlight

		let flight: CGFloat
		if isTurningPage {
			// 🔴 **翻页动画期间,把飞行进度冻住**(2026-08-09 第八轮,探针指认的病根)。
			//
			// 实测五次翻页,**每一次 `飞行进度` 都扫遍 0→1 的全程**:
			// ```
			// 排版=49 次 | 飞行进度 0→1 | offset -291.33→0 | inset上 175.33→291.33 | contentH 271.33→874
			// ```
			// 飞行进度 0 = 大标题在头图上,1 = 完全冻结成顶栏小标题 ——
			// **一次翻页的 45~61 帧里,标题在这两个极端之间来回跑。那就是抖动本身。**
			//
			// 为什么会乱跳:飞行进度 = `(contentOffset − 静止位) / 飞行距离`,
			// 而静止位来自 `adjustedContentInset.top`。新页刚建出来时**内边距还没装好**
			// (探针实测一次翻页里 `inset上` 变了 116pt、`offset` 变了 291pt,
			// 网页还在长:`contentH 0→874`)。
			// 📌 判据:**一个比值,分子和分母都还在装的时候,它算出来的不是"进度",是噪声。**
			//
			// 冻成"上一个可信值"而不是一律归 0:
			// - **新页**从来没记过 → 默认 0 → 大标题态 ✅ 它本来就是停在顶部
			// - **旧页**保持翻页开始前的样子 → 滑出去的过程里纹丝不动 ✅
			//   (一律归 0 的话,读到一半、已经是小标题的那一页会在滑走时**突然变回大标题**,
			//   那是把一种抖动换成另一种。)
			//
			// ⚠️ 动画结束后 `nnwTurnPage` 的 completion 会主动叫一次排版,用真实几何重算。
			flight = nnwLastGoodFlight
		} else if contentSettled {
			flight = measuredFlight
			nnwLastGoodFlight = flight
		} else {
			// ⚠️ **装载期间不能一律钉死 0**(2026-08-08 修,用户报的第二个现象)。
			//
			// 原来这里无条件 `flight = 0`,理由是"WebKit 装载中会自己重置滚动位置,偏移不可信"。
			// 那条防护本身没错,但它有个没考虑到的副作用:**用户此时其实已经能滚了**。
			// 一滚,内容跟着手指上移、头区却纹丝不动 —— 屏幕上就是
			// **大标题压在正文上、和正文叠在一起**(用户 2026-08-08 的截图 2);
			// 直到 `didFinish` 把 contentSettled 翻成 true,下一帧才突然算出真值 ——
			// 也就是用户说的"等一会会**突然**变成正常的毛玻璃和大小,还有位置"。
			//
			// 折中:WebKit 的自动重置总是把偏移放回**静止位附近**,不会明显超过它;
			// 而用户真的在滑时会明显超过。所以只认"明显超过"的那一部分。
			flight = travelled > Style.settleGrace ? measuredFlight : 0
			nnwLastGoodFlight = flight
		}

		// ⚠️ 临时探针(2026-08-09 第七轮,查完就删):翻页动画期间,
		// **这个函数读到的每一个会变的量,各自扫过多大范围。**
		// 第六轮量了安全区 → 116→116,假设被推翻;可 `排版=51 次` 说明高频重排是真的。
		// 所以这次把候选一次全摆上,让数字自己指认是谁在抖:
		// `flight`(飞行进度,标题从大变小那条)、`offset`/`inset上`(它俩算出 flight)、
		// `contentH`(网页装载中会一直长,长一次就重排一次)。
		if isTurningPage {
			nnwTurnLayoutCount += 1
			nnwTurnFlight = (min(nnwTurnFlight.min, flight), max(nnwTurnFlight.max, flight))
			nnwTurnOffset = (min(nnwTurnOffset.min, scrollView.contentOffset.y),
							 max(nnwTurnOffset.max, scrollView.contentOffset.y))
			nnwTurnInset = (min(nnwTurnInset.min, scrollView.adjustedContentInset.top),
							max(nnwTurnInset.max, scrollView.adjustedContentInset.top))
			nnwTurnContentH = (min(nnwTurnContentH.min, scrollView.contentSize.height),
							   max(nnwTurnContentH.max, scrollView.contentSize.height))
			// 第十三轮补两个:阅读栏**自己的几何**在翻页期间动没动。
			// 上一轮把 `inset上` 当成了嫌疑人,结果那读的是"夹后"的值(含安全区),
			// 我们写进去的原始 inset 一次都没变过 —— 所以这次直接量"决定标题块位置的那两个量"。
			nnwTurnSafeTop = (min(nnwTurnSafeTop.min, safeTop), max(nnwTurnSafeTop.max, safeTop))
			nnwTurnContainerH = (min(nnwTurnContainerH.min, safeTop + measuredHeight),
								 max(nnwTurnContainerH.max, safeTop + measuredHeight))
			// 第十五轮:三个候选来源分开记,并且**带首末**(方向就是因果,见 NNWTurnTrace)。
			nnwTurnHostSafe.add(hostSafeTop)
			nnwTurnPageSafe.add(articleHost?.view.safeAreaInsets.top ?? -1)
			nnwTurnWindowSafe.add(windowSafeTop)
			nnwTurnScrollSafe.add(scrollView.safeAreaInsets.top)
			nnwTurnOffsetTrace.add(scrollView.contentOffset.y)
			nnwTurnAdjustedTrace.add(scrollView.adjustedContentInset.top)
		} else if nnwTurnLayoutCount > 0 {
			NNWArticlePagingLog.logger.info("""
				[拽] 翻页期间 排版=\(self.nnwTurnLayoutCount, privacy: .public) 次 \
				| 飞行进度 \(self.nnwTurnFlight.min, privacy: .public)→\(self.nnwTurnFlight.max, privacy: .public) \
				| offset \(self.nnwTurnOffset.min, privacy: .public)→\(self.nnwTurnOffset.max, privacy: .public) \
				| inset上 \(self.nnwTurnInset.min, privacy: .public)→\(self.nnwTurnInset.max, privacy: .public) \
				| contentH \(self.nnwTurnContentH.min, privacy: .public)→\(self.nnwTurnContentH.max, privacy: .public) \
				| 装载完=\(self.contentSettled, privacy: .public) \
				| 文章=\(self.installedArticleID.map { String($0.prefix(8)) } ?? "无", privacy: .public)
				""")
			nnwTurnLayoutCount = 0
			nnwTurnFlight = (.greatestFiniteMagnitude, -.greatestFiniteMagnitude)
			nnwTurnOffset = (.greatestFiniteMagnitude, -.greatestFiniteMagnitude)
			nnwTurnInset = (.greatestFiniteMagnitude, -.greatestFiniteMagnitude)
			nnwTurnContentH = (.greatestFiniteMagnitude, -.greatestFiniteMagnitude)

			// 🔴 **第十三轮真正要量的那一下:解冻的瞬间,标题跳了多大。**
			//
			// 上一轮的结论是「冻结飞行进度」没治好抖动(`飞行进度 0→0` 全程稳定,用户说照旧抖)。
			// 但那一行只证明了**冻结期间不抖** —— 它**量不到冻结解除的那一帧**。
			// 而恰恰在那一帧,标题要从"冻住的旧值"一步跳到"真实值":
			// 新页冻的是 0(大标题态),而真实值可能已经是 1(完全停靠)——
			// 那就是一次**满量程的突变**,发生在动画刚停、用户眼睛正盯着的时候。
			//
			// ⚠️ 走"超时兜底"那几次更糟:冻结要多持续将近 0.9 秒
			//(上一份真机日志 6 次翻页里**有 3 次走的兜底**),
			// 期间用户已经能滚了(其中一次 offset 在冻结窗口内走了 800pt),
			// 标题却纹丝不动,直到兜底触发才猛地归位。
			//
			// 📌 **这一轮仍然只量不改。** 判读:
			// - `跳变` 接近 0 → 解冻很平顺,抖动另有来源,继续量别乱改
			// - `跳变` 到 0.5~1 → 病根就是它,下一轮改的是**"怎么解冻"**(而不是要不要冻)
			// - `安全区` / `头区容器高` 有摆动 → 阅读栏自己的几何在动,那是另一条线索
			NNWArticlePagingLog.logger.info("""
				[拽] 解冻 冻结值=\(frozenFlightBefore, privacy: .public) \
				→ 真实值=\(flight, privacy: .public) \
				| 跳变=\(abs(flight - frozenFlightBefore), privacy: .public) \
				| 安全区 \(self.nnwTurnSafeTop.min, privacy: .public)→\(self.nnwTurnSafeTop.max, privacy: .public) \
				| 头区容器高 \(self.nnwTurnContainerH.min, privacy: .public)→\(self.nnwTurnContainerH.max, privacy: .public)
				""")
			// 🔴 **第十五轮要回答的最后一个问题:哪个来源在翻页期间是稳的。**
			//
			// 上一轮的数据把病灶指到了这里:9 次翻页里有 3 次 `安全区 62→116`,
			// 而 116 − 62 = 54 = **导航栏的高度**;`头区容器高` 跟着摆同样的 54pt。
			// 也就是说**新页的宿主视图一开始还没拿到导航栏那一段安全区**,
			// 我们就拿这个偏小的值排了几十帧的版,等它补上再跳回去 ——
			// 标题块整体上下窜 54pt,正文的静止位也跟着变。**那就是抖动。**
			//
            // ⚠️ 但**不要急着改成"用文章页的安全区"** —— 第八轮就是这么栽的:
			// 当时假设"滑进来的页安全区每帧在变",直接改用窗口值,结果凭空砍掉导航栏 54pt,
			// 制造了"标题压住正文"。这一次先把三个候选一起量出来再挑。
			//
			// 判读:**谁的 `首→末` 不变、而且等于 116,谁就是那个稳定基准。**
			// - 文章页(ArticleViewController)稳定 116 → 下一轮用它兜底,一行的事
			// - 三个都在动 → 没有稳定来源,得改成"翻页期间冻住上一次的好值"
			NNWArticlePagingLog.logger.info("""
				[拽] 安全区来源 宿主 \(self.nnwTurnHostSafe.text, privacy: .public) \
				| 文章页 \(self.nnwTurnPageSafe.text, privacy: .public) \
				| 窗口 \(self.nnwTurnWindowSafe.text, privacy: .public)
				""")

			// 🔴🔴 **这一行是第十六轮真正要看的**(用户 2026-08-09:「翻成了就一定抖,不抖就是没翻成」)。
			//
			// 那句话把范围一下子收死了:**抖动和"翻页成功"是同一件事**,
			// 所以病因必须是**每一次成功翻页都发生**的东西 —— 上一轮那个「安全区 62→116」
			// 只在 20 次里出现 5 次,**不符合**,不能是它(至少不只是它)。
			//
			// 而日志里真正每次都成立的不变量是这个(从减法推出来的):
			// 写 inset 的那一刻 `夹后 == 原始`(滚动视图的安全区**还是 0**),
			// 翻页结束时 `夹后 = 原始 + 116`。也就是说
			// **新页的滚动视图在动画期间才拿到那 116pt 安全区**,
			// 于是"滚到顶"的基准位置中途挪了 116pt —— 正文就是在这时候跳的。
			//
			// 📌 判据:**"每次都抖"这种全称说法,只能由"每次都发生"的量来解释。
			// 一个只在 1/4 的情况里出现的现象,再显眼也不是它。**
			//
			// ✅ **答案已经拿到(2026-08-09 第十六轮真机,12 次翻页 11 次同一形状)**:
			// ```
			// 滚动视图安全区 首0→末116 | offset 首-175→末-291
			// ```
			// 安全区 +116,offset 正好 −116。
			// ⚠️ **这不是"系统替我们补偿了"** —— 我原来在这里写反了。
			// offset 跟着走 −116,意思是"滚动位置仍然是顶",
			// 但**"顶"这个位置本身往下移了 116pt**(内容原点的屏幕位置 = −offset)。
			// 所以**正文确实在动画中途整体掉下去 116pt**,病根坐实。
			// 📌 判据:**`offset` 和"内容看起来在哪"不是一回事;
			// 判断有没有视觉位移,要看 `−offset`,不是看 offset 有没有变。**
			//
			// ⬇️ 第十七轮加的验收行:总量 = 我们写的 + 系统的安全区。
			// 修好之后它必须**全程恒定**(首 == 末);还在变就说明补偿没接上。
			NNWArticlePagingLog.logger.info("""
				[拽] 滚动视图安全区 \(self.nnwTurnScrollSafe.text, privacy: .public) \
				| offset \(self.nnwTurnOffsetTrace.text, privacy: .public) \
				| 🎯夹后总量 \(self.nnwTurnAdjustedTrace.text, privacy: .public)
				""")

			nnwTurnSafeTop = (.greatestFiniteMagnitude, -.greatestFiniteMagnitude)
			nnwTurnContainerH = (.greatestFiniteMagnitude, -.greatestFiniteMagnitude)
			nnwTurnHostSafe = NNWTurnTrace()
			nnwTurnPageSafe = NNWTurnTrace()
			nnwTurnWindowSafe = NNWTurnTrace()
			nnwTurnScrollSafe = NNWTurnTrace()
			nnwTurnOffsetTrace = NNWTurnTrace()
			nnwTurnAdjustedTrace = NNWTurnTrace()
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
	/// 🔴🔴 **2026-08-09 第十七轮在这里加过一项"安全区补偿",真机白屏假死,已回退。**
	///
	/// 那次的诊断本身是对的(真机 12 次翻页 11 次 `滚动视图安全区 首0→末116`,
	/// 正文在动画中途整体掉 116pt),**错的是修法**:
	/// 补偿量 = `expectedSafeTop − scrollView.safeAreaInsets.top`,
	/// 它**依赖一个会被自己的写入反过来影响的量**,于是目标值来回跳、每帧都落笔 → 卡死。
	/// 详见 NOTES-todo「第十八轮」与 **L137**。**下次要治这个,不能再往每帧路径上加写操作。**
	private func syncInset() {
		guard let scrollView else { return }
		let delta = measuredHeight - appliedInset
		guard abs(delta) > 0.5 else {
			// ⚠️ **"没改"也要打一行**:这一轮要回答的是"翻页期间这里被叫了几次、各改了多少",
			// 只打改成功的那些,就分不清"没被调用"和"调用了但判定无需改"(第五轮那条探针纪律)。
			nnwLogInsetWrite("推新页(delta 太小,跳过)", delta: delta, scrollView: scrollView,
							 offsetBefore: scrollView.contentOffset.y, offsetAfter: scrollView.contentOffset.y)
			return
		}
		let offsetBefore = scrollView.contentOffset.y
		scrollView.contentInset.top += delta
		scrollView.contentOffset.y = offsetBefore - delta
		appliedInset = measuredHeight
		nnwLogInsetWrite("推新页", delta: delta, scrollView: scrollView,
						 offsetBefore: offsetBefore, offsetAfter: scrollView.contentOffset.y)
	}

	// MARK: - ⚠️ 临时探针(2026-08-09 第十三轮,查完就删)

	/// 沿 `parent` 链往上找 `ArticleViewController`(**`host` 是 `WebViewController`,不是它**)。
	/// 详细来龙去脉见 `layoutAndApply` 里那段注释(L124/L132:钩子挂在不成立的分支上,栽过三次)。
	private var nnwArticleHost: ArticleViewController? {
		var current: UIViewController? = host
		while let vc = current {
			if let article = vc as? ArticleViewController { return article }
			current = vc.parent
		}
		return nil
	}

	/// [外观] 翻页时替系统**垫上**它还没送到的那份安全区 —— 用 `transform`,**不碰滚动状态**。
	///
	/// ## 为什么需要(真机 12 次翻页 11 次同一形状,`[拽] 滚动视图安全区` 实测)
	///
	/// ```
	/// 滚动视图安全区 首0→末116 | offset 首-175→末-291
	/// ```
	/// 新页的滚动视图在我们写内边距的那一刻安全区**还是 0**,那 116pt 是在
	/// **翻页动画进行当中**才到的。到货时"滚到顶"这个基准位置下移 116pt,
	/// 屏幕上就是**正文在动画中途整体掉一截**。
	/// 只有真的新建了一页才会有这种"安全区还没到"的滚动视图 ——
	/// 所以和用户那句「翻成了就一定抖,不抖就是没翻成」完全对得上(L135)。
	///
	/// ## 为什么用 transform 而不是改内边距
	///
	/// 上一轮我就是去改内边距的,结果**白屏假死**(L137):
	/// 补偿量依赖 `safeAreaInsets`,而写内边距会反过来影响它 → 目标值来回跳 → 每帧落笔。
	/// 本文件开头那条硬约束早就写着:**只允许改 `transform` 和 `alpha`,
	/// 绝不在滚动回调里碰 `contentInset` / `safeArea`。**
	/// `transform` 是画上去的位移,**滚动状态一个字节都不变**,不参与那个环。
	///
	/// ## 为什么它不会变成第二个反馈环
	///
	/// ⚠️ 平移一个视图**确实会改变它的安全区**(本项目 T24/第七轮实测过)——
	/// 所以"垫付量算自安全区"本身仍然是有回路的。
	/// **靠单向状态机切断**:一页只在第一次排版时定一次垫付量,之后**只会归零,永不再抬高**。
	/// 没有回路 ⇒ 不可能振荡;最坏情况是"撤早了/撤晚了",退化成今天的那一跳,**不会更糟**。
	private func nnwUpdateSafeDebt(expectedSafeTop: CGFloat, scrollView: UIScrollView, isTurningPage: Bool) {

		guard Style.compensatesLateSafeArea else { return }

		// ① 只定一次:这一页第一次排版时,看系统欠多少。
		if !nnwSafeDebtLatched {
			nnwSafeDebtLatched = true
			let debt = expectedSafeTop - scrollView.safeAreaInsets.top
			// ⚠️ 只在**翻页动画期间**垫 —— 平时打开文章时安全区本来就已经到位(模拟器实测 116),
			// 不该无缘无故给正文加位移。
			guard isTurningPage, debt > 0.5, debt <= Style.maxSafeDebt else { return }
			nnwSafeDebtAtLatch = scrollView.safeAreaInsets.top
			nnwApplySafeDebt(debt)
			NNWArticlePagingLog.logger.info("""
				[拽] 安全区垫付 垫上=\(debt, privacy: .public) \
				| 此刻滚动视图安全区=\(scrollView.safeAreaInsets.top, privacy: .public) \
				| 期望=\(expectedSafeTop, privacy: .public)
				""")
			return
		}

		// ② 单向归零:安全区到货了(或者这一页已经不在翻页里了)就撤掉。
		// **只读,不重算垫付量** —— 撤了就不会再垫回去,所以没有回路。
		guard nnwSafeDebt > 0 else { return }
		let arrived = scrollView.safeAreaInsets.top >= expectedSafeTop - 0.5
		guard arrived || !isTurningPage else { return }
		NNWArticlePagingLog.logger.info("""
			[拽] 安全区垫付 撤销 原因=\(arrived ? "安全区到货" : "翻页结束", privacy: .public) \
			| 垫过=\(self.nnwSafeDebt, privacy: .public) \
			| 定时安全区=\(self.nnwSafeDebtAtLatch, privacy: .public) \
			→ 现在=\(scrollView.safeAreaInsets.top, privacy: .public)
			""")
		nnwApplySafeDebt(0)
	}

	/// 真正把位移画上去 / 撤下来。垫的是**网页那一层**(滚动视图的宿主 = `WKWebView`)。
	///
	/// ⚠️ 只在**我们自己垫过**的前提下才写 `.identity`(靠 `nnwSafeDebt != debt` 保证),
	/// 免得把别人设的 transform 抹掉。现有代码里动 transform 的只有
	/// `nnwSetContentPushBack`,它动的是**翻页容器**那一层,和这里不是同一个视图。
	private func nnwApplySafeDebt(_ debt: CGFloat) {
		guard nnwSafeDebt != debt else { return }
		nnwSafeDebt = debt
		scrollView?.superview?.transform = debt > 0.5 ? CGAffineTransform(translationX: 0, y: debt) : .identity
	}

	/// 记一行「我们自己动了正文的内边距和偏移」。
	///
	/// **为什么这一轮要量这个**:第十二轮的数据把嫌疑指到这里 ——
	/// 一次翻页里 `inset上` 摆动整整 116pt(= 一个安全区)、`offset` 摆动 300+pt。
	/// 而全项目只有两处会**同时**写 `contentInset.top` 和 `contentOffset.y`:
	/// `syncInset()`(推新页)和 `releaseInset()`(还旧页)—— 那正是"正文在动"的直接嫌疑人。
	///
	/// 📌 **这一轮只量不改。** 第十二轮我两次"数据指认 → 直接动刀",两次都把事情弄得更糟
	/// (一次制造了标题压正文,一次把隐藏缺陷升级成永久锁死翻页)。
	/// 要回答三个问题:①翻页动画期间被调用了几次(预期各一次,若是几十次则病根坐实);
	/// ②每次改了多少(delta 是不是那 116);③改的是哪一页(`页=` 那个短号区分新旧两页)。
	private func nnwLogInsetWrite(_ what: String, delta: CGFloat, scrollView: UIScrollView,
								  offsetBefore: CGFloat, offsetAfter: CGFloat) {
		let articleHost = nnwArticleHost
		let stage = (articleHost?.nnwIsTurningPage ?? false) ? "翻页中"
			: ((articleHost?.nnwIsPullingToTurnPage ?? false) ? "拽中" : "平时")
		let pageTag = UInt(bitPattern: ObjectIdentifier(scrollView).hashValue) % 9973
		let articleTag = installedArticleID.map { String($0.prefix(8)) } ?? "无"
		NNWArticlePagingLog.logger.info("""
			[拽] 改内边距 \(what, privacy: .public) \(stage, privacy: .public) \
			| delta=\(delta, privacy: .public) | 我们共加过=\(self.appliedInset, privacy: .public) \
			| offset \(offsetBefore, privacy: .public)→\(offsetAfter, privacy: .public) \
			| inset上=\(scrollView.contentInset.top, privacy: .public) \
			| 夹后inset上=\(scrollView.adjustedContentInset.top, privacy: .public) \
			| 页=\(pageTag, privacy: .public) | 文章=\(articleTag, privacy: .public)
			""")
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
		// [外观] 2026-08-05:一行换一行 —— 走调色板,不走 xcassets 的静态色板。
		// 原来写死 `Assets.Colors.primaryAccent`,所以在设置里换强调色时**这圈进度环跟不上**。
		// ⚠️ `CGColor` 不会自己跟随深浅色,所以必须**按当前 traits 解析一次**再取 cgColor
		// (这个方法每次滚动都跑,深浅色变了下一帧就会带上新值)。
		ringLayer.strokeColor = NNWSoftMaterial.accent.resolvedColor(with: iconView.traitCollection).cgColor
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

	/// [翻译] 点头像 → 进"这个源的文章列表"(2026-07-30 用户要求)。
	/// 由装配方(WebViewController+ReadingBar)接上;没接上时保持老行为(开源主页)。
	var onIconTapped: (() -> Void)?

	@objc private func openFeedHomePage() {
		// [翻译] 2026-07-30 起头像的正职是"进这个源的文章列表"(上面的闭包);
		// 闭包没接上(只有 article.feed 为 nil 的理论边角)才退回老行为:开源主页。
		if let onIconTapped {
			onIconTapped()
			return
		}
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

	/// 安全区变了也要重排(T24 自愈的接收端):宿主视图的安全区**迟到**时,
	/// 系统补灌进来的那一刻从这里拉一次排版,标题从状态栏里落回正位。
	override func safeAreaInsetsDidChange() {
		super.safeAreaInsetsDidChange()
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
