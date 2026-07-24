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

/// [外观] 自绘品牌选单的对外入口(菜单项、锚点、show 方法都在这个命名空间下)。
enum NNWMenu {

	/// 一行菜单项:图标 + 文字 + 点了做什么。
	struct Item {
		let title: String
		/// SF Symbol 图标名;nil = 这行不带图标
		let icon: String?
		/// 危险项(删除类),红色显示
		let isDestructive: Bool
		let handler: () -> Void

		init(title: String, icon: String?, isDestructive: Bool = false, handler: @escaping () -> Void) {
			self.title = title
			self.icon = icon
			self.isDestructive = isDestructive
			self.handler = handler
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
	@MainActor
	static func show(in host: UIViewController, anchor: Anchor,
					 title: String? = nil, message: String? = nil,
					 sections: [[Item]], onCancel: (() -> Void)? = nil) {
		// 已经有东西弹着(包括另一张选单)就不再弹,防连点
		guard host.presentedViewController == nil else { return }
		guard sections.contains(where: { !$0.isEmpty }) else { return }
		let menu = NNWMenuViewController(sections: sections, anchor: anchor,
										 headerTitle: title, headerMessage: message,
										 hostView: host.view, onCancel: onCancel)
		menu.modalPresentationStyle = .overFullScreen
		host.present(menu, animated: false)		// 动画自己做(系统的模态动画是"从底部推上来",不是我们要的)
	}
}

// MARK: - 浮层本体(私有,外面只通过 NNWMenu.show 使用)

private final class NNWMenuViewController: UIViewController {

	// 样式定数(想调样式改这里)
	private static let cardWidth: CGFloat = 250
	private static let cardCornerRadius: CGFloat = 22
	private static let screenMargin: CGFloat = 12		// 卡片距屏幕安全区的最小边距
	private static let anchorGap: CGFloat = 10			// 卡片和触发点之间留的缝
	private static let dimAlpha: CGFloat = 0.2			// 背景压暗程度

	private let sections: [[NNWMenu.Item]]
	private let anchor: NNWMenu.Anchor
	private let headerTitle: String?
	private let headerMessage: String?
	private weak var hostView: UIView?					// 用来算工具栏/导航栏锚点位置
	private let onCancel: (() -> Void)?					// 没选任何项就关掉时的回调

	private let dim = UIView()
	private let shadowHost = UIView()					// 只负责投影 + 弹出动画(不裁切)
	private let card = UIView()							// 负责圆角裁切(裁切层画不了阴影,见文件头)
	private let scrollView = UIScrollView()				// 选项列表;超高时在这里面滚
	private var placed = false							// 位置只算一次(见文件头 L73 那条)
	private var isClosing = false

	/// 居中弹出(错误提示这类)时动画柔一点:不从角上弹,轻轻放大浮现即可
	private var isCentered: Bool {
		if case .center = anchor { return true }
		return false
	}

	init(sections: [[NNWMenu.Item]], anchor: NNWMenu.Anchor,
		 headerTitle: String?, headerMessage: String?, hostView: UIView?,
		 onCancel: (() -> Void)?) {
		self.sections = sections
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
		shadowHost.layer.shadowColor = UIColor.black.cgColor
		shadowHost.layer.shadowOpacity = 0.22
		shadowHost.layer.shadowRadius = 24
		shadowHost.layer.shadowOffset = CGSize(width: 0, height: 8)
		view.addSubview(shadowHost)

		// 卡片
		card.backgroundColor = AppAppearance.menuCardBackground
		card.layer.cornerRadius = Self.cardCornerRadius
		card.layer.cornerCurve = .continuous
		card.clipsToBounds = true		// 列表滚动时内容不能穿出圆角
		// 极淡描边:浅色下几乎看不见,深色下把卡片从压暗的背景里衬出来(阴影在深色里不管用)
		card.layer.borderWidth = 1.0 / max(view.traitCollection.displayScale, 1)
		card.layer.borderColor = AppAppearance.menuSeparator.cgColor
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

		let groups = sections.filter { !$0.isEmpty }
		for (index, group) in groups.enumerated() {
			if index > 0 { stack.addArrangedSubview(makeSeparator()) }
			for item in group {
				let row = NNWMenuRowControl(item: item)
				row.addTarget(self, action: #selector(rowTapped(_:)), for: .touchUpInside)
				stack.addArrangedSubview(row)
			}
		}
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
		line.backgroundColor = AppAppearance.menuSeparator
		line.translatesAutoresizingMaskIntoConstraints = false
		container.addSubview(line)
		let hairline = 1.0 / max(view.traitCollection.displayScale, 1)
		NSLayoutConstraint.activate([
			container.heightAnchor.constraint(equalToConstant: 12),
			line.heightAnchor.constraint(equalToConstant: hairline),
			line.centerYAnchor.constraint(equalTo: container.centerYAnchor),
			line.leadingAnchor.constraint(equalTo: container.leadingAnchor),
			line.trailingAnchor.constraint(equalTo: container.trailingAnchor)
		])
		return container
	}

	// MARK: 摆位置(只算一次)

	override func viewDidLayoutSubviews() {
		super.viewDidLayoutSubviews()
		guard !placed else { return }
		placed = true
		placeCard()
		// 摆好后先藏起来,等 viewDidAppear 里做弹出动画
		shadowHost.alpha = 0
		dim.alpha = 0
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

	init(item: NNWMenu.Item) {
		self.item = item
		super.init(frame: .zero)

		// 高亮垫(默认藏着,按下才显示)
		pill.backgroundColor = AppAppearance.selectionHighlight
		pill.layer.cornerRadius = 10
		pill.layer.cornerCurve = .continuous
		pill.isHidden = true
		pill.isUserInteractionEnabled = false
		addSubview(pill)

		let tint: UIColor = item.isDestructive ? .systemRed : AppAppearance.inkPrimary

		// 图标列固定 26pt 宽,有无图标文字都对得齐
		var labelLeading: CGFloat = 18
		if let iconName = item.icon {
			let config = UIImage.SymbolConfiguration(textStyle: .body)
				.applying(UIImage.SymbolConfiguration(weight: .medium))
			let iconView = UIImageView(image: UIImage(systemName: iconName, withConfiguration: config))
			iconView.tintColor = tint
			iconView.contentMode = .center
			iconView.translatesAutoresizingMaskIntoConstraints = false
			iconView.isUserInteractionEnabled = false
			addSubview(iconView)
			NSLayoutConstraint.activate([
				iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
				iconView.widthAnchor.constraint(equalToConstant: 26),
				iconView.centerYAnchor.constraint(equalTo: centerYAnchor)
			])
			labelLeading = 18 + 26 + 10
		}

		let label = UILabel()
		label.text = item.title
		label.font = .preferredFont(forTextStyle: .body)
		label.adjustsFontForContentSizeCategory = true		// 跟随系统字号
		label.textColor = tint
		label.numberOfLines = 1
		label.translatesAutoresizingMaskIntoConstraints = false
		label.isUserInteractionEnabled = false
		addSubview(label)
		NSLayoutConstraint.activate([
			label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: labelLeading),
			label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -18),
			// 行高由文字撑:上下各 13pt,系统字号变大行自动变高
			label.topAnchor.constraint(equalTo: topAnchor, constant: 13),
			label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -13)
		])

		isAccessibilityElement = true
		accessibilityLabel = item.title
		accessibilityTraits = .button
	}

	required init?(coder: NSCoder) { fatalError("不走 storyboard") }

	override func layoutSubviews() {
		super.layoutSubviews()
		pill.frame = bounds.insetBy(dx: 8, dy: 3)
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
