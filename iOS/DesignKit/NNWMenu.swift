//
//  NNWMenu.swift
//  NetNewsWire — AI 翻译 fork
//
//  [外观] 本 fork 新增,上游没有这个文件(iOS/DesignKit/ 整个目录都是新的)。
//
//  自绘的「品牌选单」—— 用来取代系统 UIAlertController 动作单。
//
//  ## 为什么要自己画
//
//  系统动作单(从屏幕底部滑出的那种大白条)样式不可定制,和本 app 的
//  暖纸设计完全不搭。参考 Reeder 的做法:菜单是一张**圆角小卡片**,
//  从触发按钮旁边弹出来,图标 + 文字一行一项,点卡片外面任意处收起。
//
//  ## 怎么用(调用方只需要这几行)
//
//      NNWMenu.show(in: self, anchor: .bottomTrailing, sections: [[
//          NNWMenu.Item(title: "文件夹管理", icon: "folder") { ... },
//          NNWMenu.Item(title: "搜索订阅源", icon: "magnifyingglass") { ... }
//      ]])
//
//  - sections 里每个数组是一组,组与组之间画一条细分隔线(参考截图里 Reeder 的分组)。
//  - title / message 可选:确认类弹窗(删除、重翻)用它们在卡片顶部说明处境。
//  - 不需要「取消」项 —— 点卡片外面任意处就是取消。
//    (破坏性确认可以自己加一行「取消」,给用户一个明确的退路,见删除文件夹那处。)
//  - 危险操作(删除类)把 isDestructive 设 true,会显示成红色。
//  - 选项太多一屏放不下时(选文件夹这类),卡片高度封顶、**内部自己滚动**,标题区钉着不动。
//
//  ## 设计上的几个定数(想调样式改这里,一处改处处一致)
//
//  - 卡片宽度**写死 250**,高度由内容自己长、封顶到安全区。为什么写死:L78 的教训 ——
//    放进浮层的东西尺寸要一次算死,"自适应宽度"会把静态问题变成时序问题。
//  - 颜色全部走 AppAppearance(卡片底 menuCardBackground / 分隔线 menuSeparator /
//    文字 inkPrimary / 说明文字 inkSecondary),深浅色自动跟随,这个文件里不出现任何色号。
//  - 弹出动画:从靠近触发点的那个角弹开(和系统长按菜单同款观感);
//    系统开了「减弱动态效果」时退化成纯淡入。
//
//  ## 结构:为什么卡片外面还套了一层 shadowHost
//
//  列表能滚动之后,滚动内容会从卡片的直角裁切框里"穿出"圆角 —— 卡片必须
//  clipsToBounds 裁圆角;可是裁切的层画不了阴影(阴影在边界外)。
//  所以拆两层:外层 shadowHost 只负责投影和动画(不裁切),内层 card 负责圆角裁切。
//
//  ## 几条前人教训在这里的落点
//
//  - L78:宽度写死、高度只在弹出前量一次(量和排用同一套 Auto Layout,不会对不上)。
//  - L73:卡片位置是我们自己算的,所以**转屏/分屏时不追着重算,直接收起**
//    (viewWillTransition 里 dismiss),下次再点重新算,永远不存在"两套坐标对不上"。
//  - L62/L83:动画只用一次性的 UIView.animate,不留活的 animator,销毁无雷。
//

#if os(iOS)

import UIKit
import os

/// [外观] 选单的尺寸定数。**全部来自对参考图 IMG_2442 的逐像素测量**
/// (比例尺 4.94 px/pt,定法见 NNWSoftMaterial.rimWidth)。
enum NNWMenuMetrics {
	/// 文字左边距 / 图标右边距 / 分隔线内缩:实测 167px ÷ 4.94 = **33.8pt**。
	/// ⚠️ 原来是 18pt —— **不到实测的一半**,卡片因此显得挤。
	/// 用户 2026-08-05 的原话:「为什么和这个效果看起来还是差了不少」,差的主要就是这个。
	static let sidePadding: CGFloat = 34
	/// 顶部图标行两端的内缩:实测三个图标横跨 862…1669,卡片 635…1890 → ≈46pt
	static let quickRowInset: CGFloat = 46
}

/// [外观] 自绘品牌选单的对外入口(菜单项、锚点、show 方法都在这个命名空间下)。
enum NNWMenu {

	private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "app", category: "NNW选单")


	/// 一行菜单项:图标 + 文字 + 点了做什么。
	struct Item {
		let title: String
		/// SF Symbol 图标名;nil = 这行不带图标
		let icon: String?
		/// 直接给一张图(从系统 `UIAction` 桥接过来时走这条 —— `UIAction.image` 是
		/// `UIImage` 而不是符号名)。和 `icon` 二选一,两个都有时以 `image` 为准。
		let image: UIImage?
		/// 危险项(删除类),红色显示
		let isDestructive: Bool
		/// 置灰不可点(系统菜单里 `.disabled` 的项桥接过来是这个)
		let isEnabled: Bool
		let handler: () -> Void

		init(title: String, icon: String?, isDestructive: Bool = false, handler: @escaping () -> Void) {
			self.init(title: title, icon: icon, image: nil,
					  isDestructive: isDestructive, isEnabled: true, handler: handler)
		}

		init(title: String, icon: String? = nil, image: UIImage?,
			 isDestructive: Bool = false, isEnabled: Bool = true, handler: @escaping () -> Void) {
			self.title = title
			self.icon = icon
			self.image = image
			self.isDestructive = isDestructive
			self.isEnabled = isEnabled
			self.handler = handler
		}

		/// 这一项最终显示哪张图(符号名和现成的图统一到这里,行控件只认它)。
		///
		/// [外观] 2026-08-05:统一加粗到 **17pt / semibold**。
		/// 实测参考图 IMG_2442 的行图标是 85×85px、笔画 10px ——
		/// 换算成 **17.2pt 见方、笔画 2.0pt**,笔画占比 11.5%。
		/// SF Symbols 在 `.regular` 下只有约 6%、`.medium` 约 7%,摆在那张卡里明显"太秀气";
		/// `.semibold` 约 8.5%、`.bold` 约 10.5% —— **用 bold**,是系统符号能给到的最接近值。
		///(真要 11.5% 得整套手绘,那是另一件事,已记进 NOTES-todo。)
		@MainActor var resolvedImage: UIImage? {
			let config = UIImage.SymbolConfiguration(pointSize: 17, weight: .bold)
			if let image { return image.applyingSymbolConfiguration(config) ?? image }
			guard let icon else { return nil }
			return UIImage(systemName: icon, withConfiguration: config)
		}
	}

	/// 选单从哪里弹出。
	enum Anchor {
		/// 从某个具体控件旁弹出(在它上方还是下方、靠左还是靠右,按控件在屏幕的位置自动选)
		case view(UIView)
		/// 从某个矩形区域旁弹出(rect 用 within 那个视图的坐标系;设置页这类只有
		/// 「view + sourceRect」组合的老调用点用它,不用先找到具体的 cell)
		case rect(CGRect, within: UIView)
		/// 底部工具栏右侧的上方(订阅列表页右下角 `+`、编辑模式的「删除」这类;
		/// 系统工具栏按钮拿不到它的视图,所以按"工具栏上缘靠右"定位,视觉上正好在按钮头顶)
		case bottomTrailing
		/// 底部工具栏左侧的上方(编辑模式的「移动到…」这类)
		case bottomLeading
		/// 导航栏右侧按钮的下方(文件夹管理页「新建文件夹」这类)
		case topTrailing
		/// 屏幕正中(错误提示、和具体位置无关的确认框 —— 传统 alert 的位置)
		case center
	}

	/// 弹出选单。host = 当前页面(选单以全屏浮层盖在它上面)。
	/// title / message 可选:填了就在卡片顶部显示一块钉住的说明区(列表滚动时它不动)。
	/// onCancel:用户**没选任何项**就关掉选单时(点外面 / VoiceOver 退出 / 转屏)回调 ——
	/// 有些调用方要在"用户放弃了"时收尾(比如把滑开的行收回去),没有就不传。
	/// - Parameter quickActions: 顶部那一排**只有图标**的快捷键(照参考图 IMG_2442:
	///   一排图标 → 分隔线 → 下面才是文字行)。空数组 = 不显示这一排。
	@MainActor
	static func show(in host: UIViewController, anchor: Anchor,
					 title: String? = nil, message: String? = nil,
					 quickActions: [Item] = [],
					 sections: [[Item]], onCancel: (() -> Void)? = nil) {
		guard !quickActions.isEmpty || sections.contains(where: { !$0.isEmpty }) else { return }

		// ⚠️ **从最顶上那一层弹,不能直接用 host**(2026-07-28 用户报"发现页选不了文件夹")。
		//
		// 这里原来的写法是 `guard host.presentedViewController == nil else { return }`,
		// 本意是"已经有东西弹着就别再弹,防连点"。但那个判断太宽了 ——
		// **激活着的搜索框本身就是一次真实的 presentation**:
		// 页面只要设了 `definesPresentationContext`(发现页正是如此),
		// 用户一在搜索框里搜过东西,`host.presentedViewController` 就是那个搜索控制器,
		// 于是这条守卫直接 return,点「文件夹」**静默什么都不发生**。
		//
		// 而且 UIKit 也不允许对一个"已经在弹别人"的控制器再 present ——
		// 所以正确做法是顺着 presented 链走到最顶上那一层,从那儿弹。
		//(同一族的坑今天已经在 modal 搜索页踩过一次,见 NOTES-lessons L93。)
		var presenter: UIViewController = host
		var depth = 0
		while let presented = presenter.presentedViewController {
			// 防连点:顶上已经是一张选单了就不再弹(这才是那条守卫本来的意思)
			if presented is NNWMenuViewController { return }
			presenter = presented
			depth += 1
		}

		// 📋 排查用(2026-07-29):用户报过"搜索出结果后选单弹不出来"。
		// 这一行记下"从第几层弹的、那一层是谁" —— 万一还弹不出来,看这行就知道
		// 是被挡在了哪儿,不用再靠猜。(问题定性之后可以删。)
		Self.logger.notice("NNW选单 · 从第\(depth, privacy: .public)层弹出,弹出者=\(String(describing: type(of: presenter)), privacy: .public)")

		let menu = NNWMenuViewController(sections: sections, quickActions: quickActions, anchor: anchor,
										 headerTitle: title, headerMessage: message,
										 hostView: host.view, onCancel: onCancel)
		menu.modalPresentationStyle = .overFullScreen
		presenter.present(menu, animated: false)	// 动画自己做(系统的模态动画是"从底部推上来",不是我们要的)
	}
}

// MARK: - 浮层本体(私有,外面只通过 NNWMenu.show 使用)

private final class NNWMenuViewController: UIViewController {

	// 样式定数(想调样式改这里)
	// [外观] 2026-08-05 第三轮:**按参考图 IMG_2442 逐像素量出来的值**,不再是估的。
	// 比例尺 4.94 px/pt 的定法见 NNWSoftMaterial.rimWidth 的注释(用 17pt 正文当锚点)。
	//   卡片宽  1255px ÷ 4.94 = 254pt(前一版 268 偏宽,把行显得松)
	//   圆角    实测左上角曲线解出 ≈167px ÷ 4.94 = 34pt(前一版 26 偏方)
	private static let cardWidth: CGFloat = 254
	private static let cardCornerRadius: CGFloat = 34
	private static let screenMargin: CGFloat = 12		// 卡片距屏幕安全区的最小边距
	private static let anchorGap: CGFloat = 10			// 卡片和触发点之间留的缝
	private static let dimAlpha: CGFloat = 0.2			// 背景压暗程度

	private let sections: [[NNWMenu.Item]]
	/// [外观] 顶部那一排只有图标的快捷键(参考图 IMG_2442 的结构)
	private let quickActions: [NNWMenu.Item]
	private let anchor: NNWMenu.Anchor
	private let headerTitle: String?
	private let headerMessage: String?
	private weak var hostView: UIView?					// 用来算工具栏/导航栏锚点位置
	private let onCancel: (() -> Void)?					// 没选任何项就关掉时的回调

	private let dim = UIView()
	private let shadowHost = UIView()					// 只负责投影 + 弹出动画(不裁切)
	private let card = UIView()							// 负责圆角裁切(裁切层画不了阴影,见文件头)
	/// [外观] 卡片的软面板材质(和 dock / 三档同一套)
	/// [外观] 2026-08-05:**真磨砂** —— 选单压在整页内容上,这是最能体现玻璃的位置
	private let softPanel = NNWSoftPanel(kind: .panel, translucent: true)
	private let scrollView = UIScrollView()				// 选项列表;超高时在这里面滚
	private var placed = false							// 位置只算一次(见文件头 L73 那条)
	private var isClosing = false

	/// 居中弹出(错误提示这类)时动画柔一点:不从角上弹,轻轻放大浮现即可
	private var isCentered: Bool {
		if case .center = anchor { return true }
		return false
	}

	init(sections: [[NNWMenu.Item]], quickActions: [NNWMenu.Item], anchor: NNWMenu.Anchor,
		 headerTitle: String?, headerMessage: String?, hostView: UIView?,
		 onCancel: (() -> Void)?) {
		self.sections = sections
		self.quickActions = quickActions
		self.anchor = anchor
		self.headerTitle = headerTitle
		self.headerMessage = headerMessage
		self.hostView = hostView
		self.onCancel = onCancel
		super.init(nibName: nil, bundle: nil)
	}

	required init?(coder: NSCoder) { fatalError("不走 storyboard") }

	// MARK: 搭界面

	override func viewDidLoad() {
		super.viewDidLoad()
		view.backgroundColor = .clear

		// 压暗层:点它任意处 = 取消
		dim.backgroundColor = UIColor.black.withAlphaComponent(Self.dimAlpha)
		dim.frame = view.bounds
		dim.autoresizingMask = [.flexibleWidth, .flexibleHeight]
		dim.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(dimTapped)))
		// VoiceOver 用户也要有"取消"的路:压暗层本身读作一个关闭按钮
		dim.isAccessibilityElement = true
		dim.accessibilityLabel = "关闭选单"
		dim.accessibilityTraits = .button
		view.addSubview(dim)

		// 投影层(阴影画在这层;圆角裁切在里面的 card 上,两者不能是同一层)
		//
		// [外观] 2026-08-04:阴影从「0.22 / 24 / 8」收到参考图 IMG_2442 的量级。
		// 原来那组是"要把卡片从页面上狠狠抬起来"的思路,和这一轮定下的软面板语言冲突
		//(dock 那边贴边只暗 6–7 级)。选单浮在压暗层上,比 dock 略重一点点即可。
		shadowHost.layer.shadowColor = UIColor.black.cgColor
		shadowHost.layer.shadowOpacity = 0.14
		shadowHost.layer.shadowRadius = 14
		shadowHost.layer.shadowOffset = CGSize(width: 0, height: 4)
		view.addSubview(shadowHost)

		// 卡片
		// [外观] 2026-08-04:底改成和 dock / 三档**同一套软面板材质**
		//(上暗下亮的极淡渐变 + 整圈纯白亮边)。参考图 IMG_2442 实测:
		// 卡片填充比背景暗 2 级、上缘亮边 5px 纯白 —— 和那条 dock 轨道是同一种东西。
		// ⚠️ 材质装在 card 上,阴影仍归外面的 shadowHost —— card 要 clipsToBounds
		//(列表滚动时内容不能穿出圆角),而裁切的层画不了阴影(见文件头)。
		card.layer.cornerRadius = Self.cardCornerRadius
		card.layer.cornerCurve = .continuous
		card.clipsToBounds = true		// 列表滚动时内容不能穿出圆角
		if NNWSoftMaterial.isEnabled {
			softPanel.install(in: card)
		} else {
			card.backgroundColor = AppAppearance.menuCardBackground
			card.layer.borderWidth = 1.0 / max(view.traitCollection.displayScale, 1)
			card.layer.borderColor = AppAppearance.menuSeparator.cgColor
		}
		shadowHost.addSubview(card)

		// 顶部说明区(可选,钉在卡片顶上,列表滚动时不动)
		var headerView: UIView?
		if headerTitle != nil || headerMessage != nil {
			headerView = makeHeader()
			card.addSubview(headerView!)
			NSLayoutConstraint.activate([
				headerView!.topAnchor.constraint(equalTo: card.topAnchor),
				headerView!.leadingAnchor.constraint(equalTo: card.leadingAnchor),
				headerView!.trailingAnchor.constraint(equalTo: card.trailingAnchor)
			])
		}

		// 选项列表放进滚动容器:内容不高时它就是静止的,超过封顶高度才滚
		scrollView.translatesAutoresizingMaskIntoConstraints = false
		scrollView.alwaysBounceVertical = false
		scrollView.contentInsetAdjustmentBehavior = .never		// 卡片不贴屏幕边,系统别自作主张加内边距
		card.addSubview(scrollView)
		NSLayoutConstraint.activate([
			scrollView.topAnchor.constraint(equalTo: headerView?.bottomAnchor ?? card.topAnchor),
			scrollView.leadingAnchor.constraint(equalTo: card.leadingAnchor),
			scrollView.trailingAnchor.constraint(equalTo: card.trailingAnchor),
			scrollView.bottomAnchor.constraint(equalTo: card.bottomAnchor)
		])
		// 「滚动区高度 = 内容高度」但优先级只有 750:量尺寸时它成立(算出自然高度),
		// 卡片被封顶压矮时它让步(内容比框高 → 开始滚动)。这是滚动容器自适应高度的标准写法。
		let fitContent = scrollView.frameLayoutGuide.heightAnchor
			.constraint(equalTo: scrollView.contentLayoutGuide.heightAnchor)
		fitContent.priority = .defaultHigh
		fitContent.isActive = true

		let stack = UIStackView()
		stack.axis = .vertical
		stack.translatesAutoresizingMaskIntoConstraints = false
		scrollView.addSubview(stack)
		NSLayoutConstraint.activate([
			stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 8),
			stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -8),
			stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
			stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
			stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
		])

		// [外观] 顶部那一排只有图标的快捷键(参考图 IMG_2442 的结构:一排图标 → 分隔线 → 文字行)
		let groups = sections.filter { !$0.isEmpty }
		if !quickActions.isEmpty {
			stack.addArrangedSubview(makeQuickRow(quickActions))
			if !groups.isEmpty { stack.addArrangedSubview(makeSeparator()) }
		}

		for (index, group) in groups.enumerated() {
			if index > 0 { stack.addArrangedSubview(makeSeparator()) }
			for item in group {
				let row = NNWMenuRowControl(item: item)
				row.addTarget(self, action: #selector(rowTapped(_:)), for: .touchUpInside)
				stack.addArrangedSubview(row)
			}
		}
	}

	/// 顶部快捷图标行:几个图标等分排开,没有文字(参考图里的 ⊕ / ♡ / 👥 那一排)。
	private func makeQuickRow(_ items: [NNWMenu.Item]) -> UIView {
		let row = UIStackView()
		row.axis = .horizontal
		row.distribution = .fillEqually
		row.alignment = .fill
		row.isLayoutMarginsRelativeArrangement = true
		// 实测参考图:三个图标横跨 862…1669,卡片 635…1890 → 两端各内缩 ≈46pt
		row.layoutMargins = UIEdgeInsets(top: 6, left: NNWMenuMetrics.quickRowInset,
										 bottom: 6, right: NNWMenuMetrics.quickRowInset)
		for item in items {
			let button = NNWMenuRowControl(item: item, iconOnly: true)
			button.addTarget(self, action: #selector(rowTapped(_:)), for: .touchUpInside)
			row.addArrangedSubview(button)
		}
		row.heightAnchor.constraint(equalToConstant: 52).isActive = true
		return row
	}

	/// 顶部说明区:标题(粗一点的墨色)+ 可选的说明句(小一号的浅墨),底下一条细线。
	private func makeHeader() -> UIView {
		let header = UIView()
		header.translatesAutoresizingMaskIntoConstraints = false

		var lastBottom = header.topAnchor
		var lastGap: CGFloat = 14

		if let headerTitle {
			let title = UILabel()
			title.text = headerTitle
			title.font = UIFont.preferredFont(forTextStyle: .subheadline).nnwSemibold()
			title.adjustsFontForContentSizeCategory = true
			title.textColor = AppAppearance.inkPrimary
			title.numberOfLines = 0
			title.translatesAutoresizingMaskIntoConstraints = false
			header.addSubview(title)
			NSLayoutConstraint.activate([
				title.topAnchor.constraint(equalTo: lastBottom, constant: lastGap),
				title.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 18),
				title.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -18)
			])
			lastBottom = title.bottomAnchor
			lastGap = 4
		}

		if let headerMessage {
			let message = UILabel()
			message.text = headerMessage
			message.font = .preferredFont(forTextStyle: .footnote)
			message.adjustsFontForContentSizeCategory = true
			message.textColor = AppAppearance.inkSecondary
			message.numberOfLines = 0
			message.translatesAutoresizingMaskIntoConstraints = false
			header.addSubview(message)
			NSLayoutConstraint.activate([
				message.topAnchor.constraint(equalTo: lastBottom, constant: lastGap),
				message.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 18),
				message.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -18)
			])
			lastBottom = message.bottomAnchor
		}

		// 说明区和列表之间的细线
		let line = UIView()
		line.backgroundColor = AppAppearance.menuSeparator
		line.translatesAutoresizingMaskIntoConstraints = false
		header.addSubview(line)
		NSLayoutConstraint.activate([
			line.topAnchor.constraint(equalTo: lastBottom, constant: 12),
			line.heightAnchor.constraint(equalToConstant: 1.0 / max(view.traitCollection.displayScale, 1)),
			line.leadingAnchor.constraint(equalTo: header.leadingAnchor),
			line.trailingAnchor.constraint(equalTo: header.trailingAnchor),
			line.bottomAnchor.constraint(equalTo: header.bottomAnchor)
		])
		return header
	}

	/// 组间分隔线:一条细线,上下各留 6pt 呼吸(参考截图里 Reeder 的分组线)。
	private func makeSeparator() -> UIView {
		let container = UIView()
		let line = UIView()
		// [外观] 2026-08-05:实测参考图的分隔线是 **6px(=1.2pt)、比卡片底暗 21 级**,
		// 不是一根发丝线。原来那根 1 像素的极淡线在暖纸上基本看不见,
		// 卡片因此显得"平"—— 这是用户说"没有质感"的原因之一。
		let useSoft = NNWSoftMaterial.isEnabled
		line.backgroundColor = useSoft
			? NNWSoftMaterial.menuSeparatorColor(for: view.traitCollection)
			: AppAppearance.menuSeparator
		line.translatesAutoresizingMaskIntoConstraints = false
		container.addSubview(line)
		let hairline = useSoft
			? NNWSoftMaterial.menuSeparatorWidth
			: 1.0 / max(view.traitCollection.displayScale, 1)
		NSLayoutConstraint.activate([
			container.heightAnchor.constraint(equalToConstant: 12),
			line.heightAnchor.constraint(equalToConstant: hairline),
			line.centerYAnchor.constraint(equalTo: container.centerYAnchor),
			// [外观] 2026-08-05:分隔线**左右内缩**,不通栏。
			// 实测参考图 IMG_2442:线从 x=799 到 1727,而卡片是 635…1890 ——
			// 两端各内缩 164px ÷ 4.94 = 33pt,和文字的左边距对齐。
			line.leadingAnchor.constraint(equalTo: container.leadingAnchor,
										  constant: NNWMenuMetrics.sidePadding),
			line.trailingAnchor.constraint(equalTo: container.trailingAnchor,
										   constant: -NNWMenuMetrics.sidePadding)
		])
		return container
	}

	// MARK: 摆位置(只算一次)

	override func viewDidLayoutSubviews() {
		super.viewDidLayoutSubviews()
		if !placed {
			placed = true
			placeCard()
			// 摆好后先藏起来,等 viewDidAppear 里做弹出动画
			shadowHost.alpha = 0
			dim.alpha = 0
		}
		// [外观] 材质要按 card 的**实际**尺寸重画 —— 摆完位置才知道它多大
		//(L103 第 2 条的同一个道理:读尺寸之前要先让它被算出来)
		if NNWSoftMaterial.isEnabled {
			softPanel.layout(in: card, cornerRadius: Self.cardCornerRadius)
		}
	}

	private func placeCard() {
		let safe = view.safeAreaLayoutGuide.layoutFrame

		// 高度按内容量一次(量和排用的是同一套 Auto Layout —— L73:别用两套各算各的)
		let natural = card.systemLayoutSizeFitting(
			CGSize(width: Self.cardWidth, height: UIView.layoutFittingCompressedSize.height),
			withHorizontalFittingPriority: .required,
			verticalFittingPriority: .fittingSizeLevel)
		// 封顶到安全区:超出的部分由 scrollView 内部滚动消化(那条 750 约束此时让步)
		let size = CGSize(width: Self.cardWidth,
						  height: min(natural.height, safe.height - 2 * Self.screenMargin))

		// 居中(错误提示这类):不看触发点,直接摆安全区正中
		if isCentered {
			shadowHost.frame = CGRect(x: safe.midX - size.width / 2,
									  y: safe.midY - size.height / 2,
									  width: size.width, height: size.height)
			card.frame = shadowHost.bounds
			shadowHost.layer.shadowPath = UIBezierPath(roundedRect: shadowHost.bounds,
													   cornerRadius: Self.cardCornerRadius).cgPath
			return		// 缩放锚点保持默认的正中,浮现动画从中心轻轻放大
		}

		// 触发点的位置(换算到本浮层的坐标系;浮层铺满整个窗口)
		let anchorRect: CGRect
		let alignTrailing: Bool		// 卡片右边对齐触发点(true)还是左边对齐(false)
		let above: Bool				// 卡片在触发点上方(true)还是下方(false)
		switch anchor {
		case .view(let v):
			anchorRect = v.convert(v.bounds, to: view)
			alignTrailing = anchorRect.midX > view.bounds.midX
			above = anchorRect.midY > view.bounds.midY
		case .rect(let r, let container):
			anchorRect = container.convert(r, to: view)
			alignTrailing = anchorRect.midX > view.bounds.midX
			above = anchorRect.midY > view.bounds.midY
		case .center:
			// 上面已经 return,走不到这里;补全 switch 而已
			anchorRect = view.bounds; alignTrailing = false; above = false
		case .bottomTrailing, .bottomLeading, .topTrailing:
			// host 页面安全区:底缘 = 工具栏顶,顶缘 = 导航栏底
			let hostSafe: CGRect
			if let hostView {
				hostSafe = hostView.convert(hostView.safeAreaLayoutGuide.layoutFrame, to: view)
			} else {
				hostSafe = safe
			}
			switch anchor {
			case .bottomTrailing:
				anchorRect = CGRect(x: hostSafe.maxX - 44, y: hostSafe.maxY, width: 44, height: 0)
				alignTrailing = true; above = true
			case .bottomLeading:
				anchorRect = CGRect(x: hostSafe.minX, y: hostSafe.maxY, width: 44, height: 0)
				alignTrailing = false; above = true
			default: // .topTrailing
				anchorRect = CGRect(x: hostSafe.maxX - 44, y: hostSafe.minY, width: 44, height: 0)
				alignTrailing = true; above = false
			}
		}

		// 先按对齐规则摆,再整体夹回安全区内(不管触发点多贴边,卡片都不出屏)
		var frame = CGRect(origin: .zero, size: size)
		frame.origin.x = alignTrailing ? (anchorRect.maxX - size.width) : anchorRect.minX
		frame.origin.x = max(safe.minX + Self.screenMargin,
							 min(frame.origin.x, safe.maxX - Self.screenMargin - size.width))
		frame.origin.y = above ? (anchorRect.minY - Self.anchorGap - size.height)
							   : (anchorRect.maxY + Self.anchorGap)
		frame.origin.y = max(safe.minY + Self.screenMargin,
							 min(frame.origin.y, safe.maxY - Self.screenMargin - size.height))
		shadowHost.frame = frame
		card.frame = shadowHost.bounds
		shadowHost.layer.shadowPath = UIBezierPath(roundedRect: shadowHost.bounds,
												   cornerRadius: Self.cardCornerRadius).cgPath

		// 缩放动画的锚点 = 靠近触发点的那个角(观感和系统长按菜单一致)
		setScaleAnchor(CGPoint(x: alignTrailing ? 1 : 0, y: above ? 1 : 0))
	}

	/// 改 layer.anchorPoint 而不让视图跑位(标准补偿写法)。
	private func setScaleAnchor(_ p: CGPoint) {
		let old = shadowHost.layer.anchorPoint
		shadowHost.layer.anchorPoint = p
		shadowHost.layer.position.x += (p.x - old.x) * shadowHost.bounds.width
		shadowHost.layer.position.y += (p.y - old.y) * shadowHost.bounds.height
	}

	// MARK: 弹出 / 收起动画

	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)
		UIImpactFeedbackGenerator(style: .light).impactOccurred()
		if UIAccessibility.isReduceMotionEnabled {
			// 用户关掉了动态效果:只淡入
			UIView.animate(withDuration: 0.2) { self.shadowHost.alpha = 1; self.dim.alpha = 1 }
		} else {
			// 角上弹出的从小弹开;居中的(错误提示)轻轻放大浮现,别太跳
			let startScale: CGFloat = isCentered ? 0.9 : 0.25
			shadowHost.transform = CGAffineTransform(scaleX: startScale, y: startScale)
			UIView.animate(withDuration: 0.32, delay: 0,
						   usingSpringWithDamping: 0.82, initialSpringVelocity: 0.4) {
				self.shadowHost.transform = .identity
				self.shadowHost.alpha = 1
				self.dim.alpha = 1
			}
		}
	}

	/// 收起(动画完了再执行选中项的动作,不让菜单收起和页面跳转互相打架)。
	/// cancelled = 用户没选任何项就关掉(点外面 / VoiceOver 退出) → 走 onCancel 回调。
	private func close(cancelled: Bool = false, then handler: (() -> Void)? = nil) {
		guard !isClosing else { return }
		isClosing = true
		UIView.animate(withDuration: 0.16, delay: 0, options: [.curveEaseIn]) {
			self.shadowHost.alpha = 0
			self.dim.alpha = 0
			if !UIAccessibility.isReduceMotionEnabled {
				let endScale: CGFloat = self.isCentered ? 0.95 : 0.5
				self.shadowHost.transform = CGAffineTransform(scaleX: endScale, y: endScale)
			}
		} completion: { _ in
			self.dismiss(animated: false) {
				if cancelled { self.onCancel?() }
				handler?()
			}
		}
	}

	@objc private func dimTapped() { close(cancelled: true) }

	@objc private func rowTapped(_ row: NNWMenuRowControl) {
		close(then: row.item.handler)
	}

	// VoiceOver 的"两指 Z"退出手势
	override func accessibilityPerformEscape() -> Bool {
		close(cancelled: true)
		return true
	}

	// 转屏/分屏:不追着重算位置,直接收起(位置是按旧尺寸算的,重算容易两套坐标打架 —— L73)。
	// 这也算"没选任何项就关掉",onCancel 要补上,否则等着收尾的调用方会永远等不到。
	override func viewWillTransition(to size: CGSize, with coordinator: any UIViewControllerTransitionCoordinator) {
		super.viewWillTransition(to: size, with: coordinator)
		guard !isClosing else { return }
		isClosing = true
		dismiss(animated: false) { self.onCancel?() }
	}
}

// MARK: - 单行菜单项(图标 + 文字,按下时垫暖色药丸高亮)

private final class NNWMenuRowControl: UIControl {

	let item: NNWMenu.Item
	private let pill = UIView()		// 按下时的高亮垫(和全 app 的药丸选中态同款观感)
	/// true = 顶部快捷行那种"只有图标、居中"的样子
	private let iconOnly: Bool

	init(item: NNWMenu.Item, iconOnly: Bool = false) {
		self.item = item
		self.iconOnly = iconOnly
		super.init(frame: .zero)

		// 高亮垫(默认藏着,按下才显示)
		pill.backgroundColor = AppAppearance.selectionHighlight
		pill.layer.cornerRadius = 10
		pill.layer.cornerCurve = .continuous
		pill.isHidden = true
		pill.isUserInteractionEnabled = false
		addSubview(pill)

		// [外观] 2026-08-05:字色改用 **近纯黑**(实测参考图 #0A0A0A,亮度 10)。
		// 原来用的 AppAppearance.inkPrimary 是 #2C2823、亮度 40 —— 浅了四倍,
		// 正是用户说的「黑色不够深不够通透」。
		let ink = NNWSoftMaterial.isEnabled ? NNWSoftMaterial.menuInk : AppAppearance.inkPrimary
		let tint: UIColor = item.isDestructive ? .systemRed : ink

		// —— 顶部快捷行:只有一个居中的图标,没有文字 ——
		if iconOnly {
			let iconView = UIImageView(image: item.resolvedImage)
			// [外观] 2026-08-05:顶部这排是**主要动作**,用强调色。
			// 参考图 IMG_2442 里也正是用橙色标出那一项最想让人点的
			//(那张图是「More like this」那行的图标是橙的)。
			// 颜色走 NNWAccentPalette,设置里换色这里跟着变。
			iconView.tintColor = item.isDestructive ? .systemRed
				: (NNWSoftMaterial.isEnabled ? NNWSoftMaterial.accent : tint)
			iconView.contentMode = .center
			iconView.translatesAutoresizingMaskIntoConstraints = false
			iconView.isUserInteractionEnabled = false
			addSubview(iconView)
			NSLayoutConstraint.activate([
				iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
				iconView.centerYAnchor.constraint(equalTo: centerYAnchor)
			])
			isEnabled = item.isEnabled
			alpha = item.isEnabled ? 1 : 0.35
			isAccessibilityElement = true
			accessibilityLabel = item.title
			accessibilityTraits = item.isEnabled ? .button : [.button, .notEnabled]
			return
		}

		// [外观] 2026-08-04:改成**文字在左、图标在右**(照参考图 IMG_2442)。
		// 原来是"图标在左、文字在右"的系统菜单排法;参考图那套把图标推到行尾,
		// 于是一列文字左对齐、一列图标右对齐,两条竖直的视觉线,比系统菜单更整齐。
		var labelTrailing: CGFloat = 18
		if let icon = item.resolvedImage {
			let iconView = UIImageView(image: icon)
			iconView.tintColor = tint
			iconView.contentMode = .center
			iconView.translatesAutoresizingMaskIntoConstraints = false
			iconView.isUserInteractionEnabled = false
			addSubview(iconView)
			NSLayoutConstraint.activate([
				iconView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -NNWMenuMetrics.sidePadding),
				iconView.widthAnchor.constraint(equalToConstant: 26),
				iconView.centerYAnchor.constraint(equalTo: centerYAnchor)
			])
			labelTrailing = NNWMenuMetrics.sidePadding + 26 + 10
		}

		let label = UILabel()
		label.text = item.title
		label.font = .preferredFont(forTextStyle: .body)
		label.adjustsFontForContentSizeCategory = true		// 跟随系统字号
		label.textColor = tint
		// [外观] 2026-08-04:允许折到两行。系统菜单本来就会折,而我们原来钉死一行 ——
		// 「将"Marginal Revolution"标记为已读」这种长标题会被截成「将"Marginal Revolu…」,
		// 读不出是什么操作。这是换掉系统菜单**必须补上**的一课(不是可选的美化)。
		label.numberOfLines = 2
		// 文字长了先压缩自己,别把右边的图标顶出去
		label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
		label.translatesAutoresizingMaskIntoConstraints = false
		label.isUserInteractionEnabled = false
		addSubview(label)
		NSLayoutConstraint.activate([
			label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: NNWMenuMetrics.sidePadding),
			label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -labelTrailing),
			// 行高由文字撑:上下各 13pt,系统字号变大行自动变高
			// [外观] 2026-08-05:上下内边距 13 → 10.5。
			// 实测参考图的行距是 204.7px ÷ 4.94 = **41.4pt**;
			// 17pt 正文的行高约 20.3pt,余下 21.1pt 上下各分一半。
			label.topAnchor.constraint(equalTo: topAnchor, constant: 10.5),
			label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10.5)
		])

		// 置灰项:整行变淡且点不动(系统菜单里 .disabled 的项桥接过来就是它)
		isEnabled = item.isEnabled
		alpha = item.isEnabled ? 1 : 0.35

		isAccessibilityElement = true
		accessibilityLabel = item.title
		accessibilityTraits = item.isEnabled ? .button : [.button, .notEnabled]
	}

	required init?(coder: NSCoder) { fatalError("不走 storyboard") }

	override func layoutSubviews() {
		super.layoutSubviews()
		pill.frame = iconOnly ? bounds.insetBy(dx: 4, dy: 4) : bounds.insetBy(dx: 8, dy: 3)
	}

	// 手指按上去 → 显示药丸;抬起/划出 → 收掉。isHighlighted 是 UIControl 自己维护的
	override var isHighlighted: Bool {
		didSet { pill.isHidden = !isHighlighted }
	}
}

// MARK: - 小工具

private extension UIFont {
	/// 同字号的半粗版(给说明区标题用;动态字号照常生效)。
	func nnwSemibold() -> UIFont {
		guard let descriptor = fontDescriptor.withSymbolicTraits(.traitBold) else { return self }
		return UIFont(descriptor: descriptor, size: 0)		// size 0 = 沿用原字号
	}
}

#endif
