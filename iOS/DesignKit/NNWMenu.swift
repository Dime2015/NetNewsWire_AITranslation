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
//  - 不需要「取消」项 —— 点卡片外面任意地方就是取消。
//  - 危险操作(删除类)把 isDestructive 设 true,会显示成红色。
//
//  ## 设计上的几个定数(想调样式改这里,一处改处处一致)
//
//  - 卡片宽度**写死 250**,高度由内容自己长。为什么写死:L78 的教训 ——
//    放进浮层的东西尺寸要一次算死,"自适应宽度"会把静态问题变成时序问题。
//  - 颜色全部走 AppAppearance(卡片底 menuCardBackground / 分隔线 menuSeparator /
//    文字 inkPrimary),深浅色自动跟随,这个文件里不出现任何色号。
//  - 弹出动画:从靠近触发点的那个角弹开(和系统长按菜单同款观感);
//    系统开了「减弱动态效果」时退化成纯淡入。
//
//  ## 几条前人教训在这里的落点
//
//  - L78:宽度写死、不 systemLayoutSizeFitting 反复量 —— 高度只在弹出前量一次。
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
		/// 底部工具栏右侧的上方(订阅列表页右下角 `+` 这类;系统工具栏按钮拿不到
		/// 它的视图,所以按"工具栏上缘靠右"定位,视觉上正好在按钮头顶)
		case bottomTrailing
		/// 底部工具栏左侧的上方
		case bottomLeading
	}

	/// 弹出选单。host = 当前页面(选单以全屏浮层盖在它上面)。
	@MainActor
	static func show(in host: UIViewController, anchor: Anchor, sections: [[Item]]) {
		// 已经有东西弹着(包括另一张选单)就不再弹,防连点
		guard host.presentedViewController == nil else { return }
		guard sections.contains(where: { !$0.isEmpty }) else { return }
		let menu = NNWMenuViewController(sections: sections, anchor: anchor, hostView: host.view)
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
	private weak var hostView: UIView?					// 用来算 bottomTrailing/Leading 的工具栏位置

	private let dim = UIView()
	private let card = UIView()
	private var placed = false							// 位置只算一次(见文件头 L73 那条)
	private var isClosing = false

	init(sections: [[NNWMenu.Item]], anchor: NNWMenu.Anchor, hostView: UIView?) {
		self.sections = sections
		self.anchor = anchor
		self.hostView = hostView
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

		// 卡片
		card.backgroundColor = AppAppearance.menuCardBackground
		card.layer.cornerRadius = Self.cardCornerRadius
		card.layer.cornerCurve = .continuous
		// 极淡描边:浅色下几乎看不见,深色下把卡片从压暗的背景里衬出来(阴影在深色里不管用)
		card.layer.borderWidth = 1.0 / max(view.traitCollection.displayScale, 1)
		card.layer.borderColor = AppAppearance.menuSeparator.cgColor
		card.layer.shadowColor = UIColor.black.cgColor
		card.layer.shadowOpacity = 0.22
		card.layer.shadowRadius = 24
		card.layer.shadowOffset = CGSize(width: 0, height: 8)
		view.addSubview(card)

		// 菜单行竖着叠;组与组之间插分隔线
		let stack = UIStackView()
		stack.axis = .vertical
		stack.translatesAutoresizingMaskIntoConstraints = false
		card.addSubview(stack)
		NSLayoutConstraint.activate([
			stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 8),
			stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -8),
			stack.leadingAnchor.constraint(equalTo: card.leadingAnchor),
			stack.trailingAnchor.constraint(equalTo: card.trailingAnchor)
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
		card.alpha = 0
		dim.alpha = 0
	}

	private func placeCard() {
		let safe = view.safeAreaLayoutGuide.layoutFrame

		// 高度按内容量一次(宽度写死,理由见文件头 L78 那条)
		let size = card.systemLayoutSizeFitting(
			CGSize(width: Self.cardWidth, height: UIView.layoutFittingCompressedSize.height),
			withHorizontalFittingPriority: .required,
			verticalFittingPriority: .fittingSizeLevel)

		// 触发点的位置(换算到本浮层的坐标系;浮层铺满整个窗口)
		let anchorRect: CGRect
		let alignTrailing: Bool		// 卡片右边对齐触发点(true)还是左边对齐(false)
		let above: Bool				// 卡片在触发点上方(true)还是下方(false)
		switch anchor {
		case .view(let v):
			anchorRect = v.convert(v.bounds, to: view)
			alignTrailing = anchorRect.midX > view.bounds.midX
			above = anchorRect.midY > view.bounds.midY
		case .bottomTrailing, .bottomLeading:
			// host 页面底部安全区的上缘 = 工具栏顶。在它上方弹,左右贴着安全区边
			let hostSafe: CGRect
			if let hostView {
				hostSafe = hostView.convert(hostView.safeAreaLayoutGuide.layoutFrame, to: view)
			} else {
				hostSafe = safe
			}
			if case .bottomTrailing = anchor {
				anchorRect = CGRect(x: hostSafe.maxX - 44, y: hostSafe.maxY, width: 44, height: 0)
				alignTrailing = true
			} else {
				anchorRect = CGRect(x: hostSafe.minX, y: hostSafe.maxY, width: 44, height: 0)
				alignTrailing = false
			}
			above = true
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
		card.frame = frame
		card.layer.shadowPath = UIBezierPath(roundedRect: card.bounds,
											 cornerRadius: Self.cardCornerRadius).cgPath

		// 缩放动画的锚点 = 靠近触发点的那个角(观感和系统长按菜单一致)
		setScaleAnchor(CGPoint(x: alignTrailing ? 1 : 0, y: above ? 1 : 0))
	}

	/// 改 layer.anchorPoint 而不让视图跑位(标准补偿写法)。
	private func setScaleAnchor(_ p: CGPoint) {
		let old = card.layer.anchorPoint
		card.layer.anchorPoint = p
		card.layer.position.x += (p.x - old.x) * card.bounds.width
		card.layer.position.y += (p.y - old.y) * card.bounds.height
	}

	// MARK: 弹出 / 收起动画

	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)
		UIImpactFeedbackGenerator(style: .light).impactOccurred()
		if UIAccessibility.isReduceMotionEnabled {
			// 用户关掉了动态效果:只淡入
			UIView.animate(withDuration: 0.2) { self.card.alpha = 1; self.dim.alpha = 1 }
		} else {
			card.transform = CGAffineTransform(scaleX: 0.25, y: 0.25)
			UIView.animate(withDuration: 0.32, delay: 0,
						   usingSpringWithDamping: 0.82, initialSpringVelocity: 0.4) {
				self.card.transform = .identity
				self.card.alpha = 1
				self.dim.alpha = 1
			}
		}
	}

	/// 收起(动画完了再执行选中项的动作,不让菜单收起和页面跳转互相打架)。
	private func close(then handler: (() -> Void)? = nil) {
		guard !isClosing else { return }
		isClosing = true
		UIView.animate(withDuration: 0.16, delay: 0, options: [.curveEaseIn]) {
			self.card.alpha = 0
			self.dim.alpha = 0
			if !UIAccessibility.isReduceMotionEnabled {
				self.card.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
			}
		} completion: { _ in
			self.dismiss(animated: false) { handler?() }
		}
	}

	@objc private func dimTapped() { close() }

	@objc private func rowTapped(_ row: NNWMenuRowControl) {
		close(then: row.item.handler)
	}

	// VoiceOver 的"两指 Z"退出手势
	override func accessibilityPerformEscape() -> Bool {
		close()
		return true
	}

	// 转屏/分屏:不追着重算位置,直接收起(位置是按旧尺寸算的,重算容易两套坐标打架 —— L73)
	override func viewWillTransition(to size: CGSize, with coordinator: any UIViewControllerTransitionCoordinator) {
		super.viewWillTransition(to: size, with: coordinator)
		dismiss(animated: false)
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

#endif
