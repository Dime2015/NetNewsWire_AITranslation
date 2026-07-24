//
//  NNWControlBoard.swift
//  NetNewsWire — AI 翻译 fork
//
//  [外观] 本 fork 新增,上游没有这个文件。
//
//  文章详情页底部的「控件板」—— 用一块自绘的板子取代 iOS 26 把 6 个系统按钮
//  切成的两坨玻璃胶囊(用户 2026-07-25 拍板重做)。
//
//  ## 布局(用户拍板,2026-07-25 二版:去掉分隔线、平均间隔,顺序别自行调)
//
//      已读 ○ · 星标 ★ · 下一篇未读 ▾ · 分享 · 长图 · 阅读视图 · 翻译
//
//  ## 分工(核心设计,接手前必须看懂)
//
//  - 「阅读视图」「翻译」两个按钮**不是这里造的**:它们是上游/翻译层的原有按钮实例,
//    自带完整状态机(转圈/出错/角标……),从外面**整个注入**进来。所有原来往这两个
//    实例上写状态的代码一行不用改 —— 写的还是同一个对象,只是它换了个地方住。
//  - 其余 5 个键是本文件自己的按钮。它们的状态**只有一个入口**:`apply(_ state:)`。
//    调用方(ArticleViewController.updateUI 末尾的一行钩子)把状态整包送进来。
//    ⚠️ 这是把 L74「一个显示值有 N 个写入点」的病根从结构上锁死 —— 板子上
//    **不允许**出现第二条改状态的路。要加状态就往 State 里加字段。
//
//  ## 尺寸(L78:一次算死,不自适应)
//
//  每键 44×44(苹果的最小点按标准),分区隔线占 11,总宽 = 7×44 + 2×11 = 330,定死。
//  330 在最窄的机型(375pt)上也放得下。字号跟随系统时图标不缩放 —— 故意的,
//  控件板是"仪表盘"不是"正文",尺寸恒定才不会挤成一团(和三档控件同一个理)。
//
//  ## 点击区的一个坑(为什么每个键都套在"格子"里)
//
//  上游的阅读视图按钮为了盖住玻璃胶囊的缝,把自己的点击区向四周扩了 20pt
//  (point(inside:) 重写)。在拥挤的板子里这会**吞掉邻居的点击**。
//  把每个键装进一个固定 44×44 的"格子"容器后,命中测试先按格子算,
//  扩张的点击区只在自己格子里说话 —— 不改上游一行,坑就拆了。
//

#if os(iOS)

import UIKit

/// [外观] 文章页底部控件板。
final class NNWArticleControlBoard: UIView {

	// MARK: 尺寸定数(想调整改这里)

	private static let slotSize: CGFloat = 44		// 每键的格子边长
	/// 总宽定死(L78)。7 键共 308,余下的宽度由 equalSpacing 平均分给 6 个间隔。
	private static let boardWidth: CGFloat = 330

	// MARK: 状态(唯一入口,见文件头)

	/// 5 个自有键的全部状态。字段与 ArticleViewController.updateUI 的判断一一对应。
	struct State {
		var hasArticle: Bool				// 没有文章时全部置灰
		var isRead: Bool					// 已读(圆圈空心)/未读(实心)
		var canMarkUnread: Bool				// 已读状态下还允不允许标回未读
		var isStarred: Bool					// 星标点亮(星色)
		var isNextUnreadAvailable: Bool		// 还有下一篇未读吗
		var hasLink: Bool					// 有原文链接吗(分享/长图都要靠它)
	}

	// MARK: 动作回调(由 ArticleViewController 接线)

	var onToggleRead: (() -> Void)?
	var onToggleStar: (() -> Void)?
	var onNextUnread: (() -> Void)?
	var onShareLongImage: (() -> Void)?
	/// 分享要弹系统分享单,iPad 上需要一个锚点视图 —— 把分享键自己传出去
	var onShare: ((UIView) -> Void)?

	// MARK: 自有的 5 个键

	private let readButton = NNWBoardButton()
	private let starButton = NNWBoardButton()
	private let nextUnreadButton = NNWBoardButton()
	private let longImageButton = NNWBoardButton()
	private let shareButton = NNWBoardButton()

	/// 分享键的视图,给外面当 iPad 气泡锚点用(比如键盘快捷键触发的分享,也该锚在这)。
	var shareAnchorView: UIView { shareButton }

	/// [保命] 上游的旧工具栏按钮,板子上线后**收养在这里,永不使用**。
	///
	/// ⚠️ 为什么必须有(L85,2026-07-25 启动闪退的根因):上游 updateUI 仍会往
	/// 旧按钮(已读/星标/下一篇未读…)身上写状态 —— 我们故意不改那段(最小 diff)。
	/// 但那些按钮的 IBOutlet 全是 **weak**:以前靠待在 toolbarItems 数组里活着,
	/// 板子把数组换掉的一瞬间它们就被释放、弱引用变空,上游一写(隐式解包)当场崩。
	/// 所以换数组**之前**要把旧按钮原样存进来"续命"。删这个属性 = app 秒崩。
	var legacyItemsKeptAlive: [UIBarButtonItem] = []

	/// - Parameters:
	///   - readerButton: 上游的「阅读视图」按钮实例(状态机自理,整个注入)
	///   - translationButton: 翻译层的「翻译」按钮实例(同上)
	init(readerButton: UIView, translationButton: UIView) {
		super.init(frame: .zero)

		// 图标统一暖墨色(星标点亮时单独换色,在 apply 里)
		tintColor = AppAppearance.inkPrimary

		// [外观] 统一图标尺寸(2026-07-25 用户指出:最后两键看着偏大 —— 不是错觉):
		// 注入的两个按钮用的是系统默认符号尺寸,比板上其他键的 17pt 大一圈。
		// 给它们设同一份符号配置;这个配置属于按钮本身,它们内部状态机之后
		// setImage 换图标(转圈/出错/角标态)也依然生效。
		let unifiedIcon = UIImage.SymbolConfiguration(pointSize: 17, weight: .medium)
		(readerButton as? UIButton)?.setPreferredSymbolConfiguration(unifiedIcon, forImageIn: .normal)
		(translationButton as? UIButton)?.setPreferredSymbolConfiguration(unifiedIcon, forImageIn: .normal)

		readButton.addTarget(self, action: #selector(readTapped), for: .touchUpInside)
		starButton.addTarget(self, action: #selector(starTapped), for: .touchUpInside)
		nextUnreadButton.addTarget(self, action: #selector(nextUnreadTapped), for: .touchUpInside)
		longImageButton.addTarget(self, action: #selector(longImageTapped), for: .touchUpInside)
		shareButton.addTarget(self, action: #selector(shareTapped), for: .touchUpInside)

		nextUnreadButton.setSymbol("chevron.down.circle")	// 和上游故事板同一个图标
		nextUnreadButton.accessibilityLabel = NSLocalizedString("Next Unread Article", comment: "Next Unread Article")
		longImageButton.setImage(NNWIcons.longImageShare())	// 自绘图标(竖长卡片 + 分享箭头)
		longImageButton.accessibilityLabel = "分享长图"
		shareButton.setSymbol("square.and.arrow.up")
		shareButton.accessibilityLabel = NSLocalizedString("Share", comment: "Share")

		// 7 键平均间隔,顺序即用户拍板的布局(2026-07-25 二版:去分隔线)
		let stack = UIStackView(arrangedSubviews: [
			slot(readButton), slot(starButton), slot(nextUnreadButton),
			slot(shareButton), slot(longImageButton),
			slot(readerButton), slot(translationButton)
		])
		stack.axis = .horizontal
		stack.distribution = .equalSpacing		// 总宽定死,富余宽度平均分给 6 个间隔
		stack.translatesAutoresizingMaskIntoConstraints = false
		addSubview(stack)
		NSLayoutConstraint.activate([
			stack.topAnchor.constraint(equalTo: topAnchor),
			stack.bottomAnchor.constraint(equalTo: bottomAnchor),
			stack.leadingAnchor.constraint(equalTo: leadingAnchor),
			stack.trailingAnchor.constraint(equalTo: trailingAnchor)
		])
	}

	required init?(coder: NSCoder) { fatalError("不走 storyboard") }

	/// 定死的整体尺寸(工具栏按这个摆它,永远不需要重新问 —— L78)
	override var intrinsicContentSize: CGSize {
		CGSize(width: Self.boardWidth, height: Self.slotSize)
	}

	/// 刷新 5 个自有键。**这是板子唯一的状态入口**(见文件头)。
	func apply(_ state: State) {

		// 已读:空心圈 = 已读(点了标回未读),实心圈 = 未读(点了标已读)。图标与上游一致。
		readButton.setSymbol(state.isRead ? "circle" : "largecircle.fill.circle")
		readButton.isEnabled = state.hasArticle && (state.isRead ? state.canMarkUnread : true)
		readButton.accessibilityLabel = state.isRead
			? NSLocalizedString("Mark Article Unread", comment: "Mark Article Unread")
			: NSLocalizedString("Selected - Mark Article Unread", comment: "Selected - Mark Article Unread")

		// 星标:点亮时用 app 的星色,平时和别的键一样是暖墨
		starButton.setSymbol(state.isStarred ? "star.fill" : "star")
		starButton.iconTint = state.isStarred ? Assets.Colors.star : nil
		starButton.isEnabled = state.hasArticle
		starButton.accessibilityLabel = state.isStarred
			? NSLocalizedString("Selected - Star Article", comment: "Selected - Star Article")
			: NSLocalizedString("Star Article", comment: "Star Article")

		nextUnreadButton.isEnabled = state.hasArticle && state.isNextUnreadAvailable
		longImageButton.isEnabled = state.hasArticle && state.hasLink
		shareButton.isEnabled = state.hasArticle && state.hasLink
	}

	// MARK: 内部

	@objc private func readTapped() { onToggleRead?() }
	@objc private func starTapped() { onToggleStar?() }
	@objc private func nextUnreadTapped() { onNextUnread?() }
	@objc private func longImageTapped() { onShareLongImage?() }
	@objc private func shareTapped() { onShare?(shareButton) }

	/// 把一个键装进固定 44×44 的"格子"(作用见文件头「点击区的坑」)。
	private func slot(_ button: UIView) -> UIView {
		let container = UIView()
		button.translatesAutoresizingMaskIntoConstraints = false
		container.addSubview(button)
		NSLayoutConstraint.activate([
			container.widthAnchor.constraint(equalToConstant: Self.slotSize),
			container.heightAnchor.constraint(equalToConstant: Self.slotSize),
			button.centerXAnchor.constraint(equalTo: container.centerXAnchor),
			button.centerYAnchor.constraint(equalTo: container.centerYAnchor)
		])
		// 自有键没有自己的尺寸约束,给足整格;注入的两个按钮自带 44×44 约束,不重复给
		if button is NNWBoardButton {
			NSLayoutConstraint.activate([
				button.widthAnchor.constraint(equalToConstant: Self.slotSize),
				button.heightAnchor.constraint(equalToConstant: Self.slotSize)
			])
		}
		return container
	}

	// (2026-07-25 二版:分区隔线已按用户要求去掉,改为 7 键平均间隔)
}

// MARK: - 板上的单个键(图标 + 按下药丸高亮,和选单行同一套观感)

private final class NNWBoardButton: UIControl {

	private let pill = UIView()
	private let iconView = UIImageView()

	/// 单独指定图标颜色(星标点亮用星色);nil = 跟板子的暖墨 tint 走
	var iconTint: UIColor? {
		didSet { iconView.tintColor = iconTint }		// 设回 nil 即恢复继承 tintColor
	}

	init() {
		super.init(frame: .zero)

		pill.backgroundColor = AppAppearance.selectionHighlight
		pill.layer.cornerRadius = 10
		pill.layer.cornerCurve = .continuous
		pill.isHidden = true
		pill.isUserInteractionEnabled = false
		addSubview(pill)

		iconView.contentMode = .center
		iconView.translatesAutoresizingMaskIntoConstraints = false
		iconView.isUserInteractionEnabled = false
		addSubview(iconView)
		NSLayoutConstraint.activate([
			iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
			iconView.centerYAnchor.constraint(equalTo: centerYAnchor)
		])

		isAccessibilityElement = true
		accessibilityTraits = .button
	}

	required init?(coder: NSCoder) { fatalError("不走 storyboard") }

	func setSymbol(_ name: String) {
		let config = UIImage.SymbolConfiguration(pointSize: 17, weight: .medium)
		iconView.image = UIImage(systemName: name, withConfiguration: config)
	}

	func setImage(_ image: UIImage?) {
		iconView.image = image
	}

	override func layoutSubviews() {
		super.layoutSubviews()
		pill.frame = bounds.insetBy(dx: 4, dy: 4)
	}

	override var isHighlighted: Bool {
		didSet { pill.isHidden = !isHighlighted }
	}

	override var isEnabled: Bool {
		didSet {
			iconView.alpha = isEnabled ? 1 : 0.3
			accessibilityTraits = isEnabled ? .button : [.button, .notEnabled]
		}
	}
}

// MARK: - 自绘图标

/// [外观] 自绘的矢量图标(SF Symbols 里没有合适的才自己画,目前只有长图分享一个)。
enum NNWIcons {

	/// 「文章长图」(2026-07-25 四版,按用户第二张参考图重画):
	/// **虚线选取框 + 相机** —— 截图工具的通用语法,一眼读出"截取"。
	/// 选取框画成竖长的,保住"长图"的意思;相机坐在左下角,
	/// 压住的那段虚线镂空断开(和参考图一样,不让虚线从相机身上穿过去)。
	/// 三版那个"箭头穿卡片"被用户点名不明所以,已废弃。
	/// 画成模板图(template),颜色跟随 tintColor,深浅色自动对。
	static func longImageShare() -> UIImage {
		let canvas = CGSize(width: 22, height: 22)
		let renderer = UIGraphicsImageRenderer(size: canvas)
		let image = renderer.image { _ in
			let stroke: CGFloat = 1.6

			// 虚线选取框(竖长 13×17):圆头短划,像系统截图选区
			let frame = UIBezierPath(roundedRect: CGRect(x: 4.5, y: 2.5, width: 13, height: 17),
									 cornerRadius: 2.5)
			frame.lineWidth = stroke
			frame.lineCapStyle = .round
			frame.setLineDash([3.4, 2.8], count: 2, phase: 1.2)
			frame.stroke()

			// 把相机要坐的地方擦干净(镂空):虚线不许从相机身上穿过
			let knockout = UIBezierPath(roundedRect: CGRect(x: 3.6, y: 9.4, width: 12.8, height: 11),
										cornerRadius: 3)
			knockout.fill(with: .clear, alpha: 1)

			// 相机:机身 + 顶部取景器凸起,一笔连着画
			let x0: CGFloat = 4.8, x1: CGFloat = 15.2		// 机身左右
			let top: CGFloat = 12.4, bottom: CGFloat = 19.2	// 机身上下
			let r: CGFloat = 2								// 机身圆角
			let hx0: CGFloat = 8.2, hx1: CGFloat = 11.8		// 凸起左右
			let hy: CGFloat = 10.6, hr: CGFloat = 1			// 凸起顶 / 圆角

			let camera = UIBezierPath()
			camera.move(to: CGPoint(x: x0 + r, y: top))
			camera.addLine(to: CGPoint(x: hx0, y: top))
			camera.addLine(to: CGPoint(x: hx0, y: hy + hr))
			camera.addArc(withCenter: CGPoint(x: hx0 + hr, y: hy + hr), radius: hr,
						  startAngle: .pi, endAngle: -.pi / 2, clockwise: true)
			camera.addLine(to: CGPoint(x: hx1 - hr, y: hy))
			camera.addArc(withCenter: CGPoint(x: hx1 - hr, y: hy + hr), radius: hr,
						  startAngle: -.pi / 2, endAngle: 0, clockwise: true)
			camera.addLine(to: CGPoint(x: hx1, y: top))
			camera.addLine(to: CGPoint(x: x1 - r, y: top))
			camera.addArc(withCenter: CGPoint(x: x1 - r, y: top + r), radius: r,
						  startAngle: -.pi / 2, endAngle: 0, clockwise: true)
			camera.addLine(to: CGPoint(x: x1, y: bottom - r))
			camera.addArc(withCenter: CGPoint(x: x1 - r, y: bottom - r), radius: r,
						  startAngle: 0, endAngle: .pi / 2, clockwise: true)
			camera.addLine(to: CGPoint(x: x0 + r, y: bottom))
			camera.addArc(withCenter: CGPoint(x: x0 + r, y: bottom - r), radius: r,
						  startAngle: .pi / 2, endAngle: .pi, clockwise: true)
			camera.addLine(to: CGPoint(x: x0, y: top + r))
			camera.addArc(withCenter: CGPoint(x: x0 + r, y: top + r), radius: r,
						  startAngle: .pi, endAngle: -.pi / 2, clockwise: true)
			camera.close()
			camera.lineWidth = stroke
			camera.lineJoinStyle = .round
			camera.stroke()

			// 镜头
			let lens = UIBezierPath(ovalIn: CGRect(x: 7.8, y: 13.6, width: 4.4, height: 4.4))
			lens.lineWidth = stroke
			lens.stroke()
		}
		return image.withRenderingMode(.alwaysTemplate)
	}
}

#endif
