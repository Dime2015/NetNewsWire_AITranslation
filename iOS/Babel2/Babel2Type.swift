import UIKit

/// 全 App 字号与图标尺寸的唯一出处（ADR-033，2026-09-25 用户确认「高级感 / 克制」整体缩小一档）。
///
/// 原先的数字来自 Figma / Reeder 截图，整体偏大；这次按用户看过的对比预览统一收小约 12–15%，
/// 阅读正文定为 17pt。设置页不在这次调整范围内（它有自己的 Figma 规格），不用这里的数字。
/// 以后要再调，只改这个文件。
enum Babel2Type {
	// MARK: 首页

	/// 大标题「订阅」：36 → 28 半粗
	static var homeTitle: UIFont { .systemFont(ofSize: 28, weight: .semibold) }
	/// 「全部未读 / 文件夹」分组标题：20 → 16 半粗；旁边的数字同字号常规
	static var homeSection: UIFont { .systemFont(ofSize: 16, weight: .semibold) }
	static var homeSectionCount: UIFont { .systemFont(ofSize: 16, weight: .regular) }
	/// 文件夹行：18 半粗 → 16 中等
	static var homeFolder: UIFont { .systemFont(ofSize: 16, weight: .medium) }
	/// 订阅源行：17 中等 → 16 常规
	static var homeFeed: UIFont { .systemFont(ofSize: 16, weight: .regular) }
	/// 行尾未读数：17 / 18 → 14
	static var homeCount: UIFont { .systemFont(ofSize: 14, weight: .regular) }
	/// 订阅源图标：24 → 20
	static let homeFeedIcon: CGFloat = 20
	/// 首页左上设置齿轮：20 → 18
	static let homeSettingsSymbol: CGFloat = 18

	// MARK: 文章列表

	/// 顶部大图上的订阅源名：28 粗体 → 24 半粗
	static var heroTitle: UIFont { .systemFont(ofSize: 24, weight: .semibold) }
	/// 收起后顶栏的订阅源名：17 → 16
	static var compactTitle: UIFont { .systemFont(ofSize: 16, weight: .semibold) }
	/// 日期分段：14 中等 → 12 半粗（配合大写与字距）
	static var dayHeader: UIFont { .systemFont(ofSize: 12, weight: .semibold) }
	/// 来源名 12 → 11；时间 13 → 12
	static var rowSource: UIFont { .systemFont(ofSize: 11, weight: .regular) }
	static var rowTime: UIFont { .monospacedDigitSystemFont(ofSize: 12, weight: .regular) }
	/// 文章标题 17 → 15.5（未读半粗 / 已读常规），行高 22 → 20
	static func rowTitle(read: Bool) -> UIFont { .systemFont(ofSize: 15.5, weight: read ? .regular : .semibold) }
	static let rowTitleLineHeight: CGFloat = 20
	/// 摘要 17 → 14.5，与标题同行高
	static var rowSummary: UIFont { .systemFont(ofSize: 14.5, weight: .regular) }
	/// 标题 + 摘要一共几行（2026-09-27 用户选定）：标题一行时摘要两行，标题两行时摘要一行。
	/// 有缩略图的行正好填满缩略图旁边的空白、行高不变；没有缩略图的行高度统一。
	static let rowTextLines = 3
	static let rowTitleMaxLines = 2
	/// 来源图标 24 → 20；缩略图 70 → 64；行上下留白 14 → 16（字小了，留白多一点更透气）
	static let rowIcon: CGFloat = 20
	static let rowThumbnail: CGFloat = 64
	static let rowPadding: CGFloat = 16
	/// 顶栏系统符号：返回 19 → 17，放大镜 18 → 16
	static let compactBackSymbol: CGFloat = 17
	static let compactSearchSymbol: CGFloat = 16

	// MARK: 阅读页

	/// 大标题 34 粗体 → 27 半粗，行高 38 → 33，字距 -1 → -0.4
	static var readerTitle: UIFont { .systemFont(ofSize: 27, weight: .semibold) }
	static let readerTitleLineHeight: CGFloat = 33
	static let readerTitleKern: CGFloat = -0.4
	/// 正文 19 → 17，行高 30 → 28，段距 20 → 18（网页里的 CSS 用这几个数）
	static let readerBody: CGFloat = 17
	static let readerBodyLineHeight: CGFloat = 28
	static let readerParagraphSpacing: CGFloat = 18
	/// 顶栏图标 22 → 19（系统分享符号 19 → 17，视觉上与设计稿图标一样大）
	static let readerTopIcon: CGFloat = 19
	static let readerTopSymbol: CGFloat = 17
	/// 收起后的小标题栏：来源 13 → 12，标题 16 → 15
	static var readerCompactSource: UIFont { .systemFont(ofSize: 12, weight: .regular) }
	static var readerCompactTitle: UIFont { .systemFont(ofSize: 15, weight: .semibold) }

	// MARK: 底栏（首页 / 文章列表 / 阅读页 / 网页）

	/// 底栏图标 24 → 21；网页底栏的系统符号 19 → 17
	static let toolbarIcon: CGFloat = 21
	static let toolbarSymbol: CGFloat = 17

	// MARK: 网页浏览、添加订阅、菜单、搜索框

	static var browserTitle: UIFont { .systemFont(ofSize: 14, weight: .semibold) }
	/// 输入框文字与「取消」：16 → 15
	static var searchField: UIFont { .systemFont(ofSize: 15, weight: .regular) }
	/// 添加订阅页标题 24 → 20（设置页仍是 24）
	static let addSubscriptionTitle: CGFloat = 20
	static var resultTitle: UIFont { .systemFont(ofSize: 15, weight: .semibold) }
	static var resultSubtitle: UIFont { .systemFont(ofSize: 12, weight: .regular) }
	/// 毛玻璃菜单：选项 16 → 15、行高 48 → 44；顶部说明 13 → 12
	static var menuRow: UIFont { .systemFont(ofSize: 15, weight: .regular) }
	static let menuRowHeight: CGFloat = 44
	static var menuHeader: UIFont { .systemFont(ofSize: 12, weight: .regular) }

	// MARK: 底栏图标的统一画法与视觉修正（ADR-052）

	/// 2026-09-27 用户：「圆看起来就比星视觉上大一些」「列表页和阅读页底栏，一样的控件位置大小一样，不一样的控件视觉上大小相近」。
	/// 设计稿图标都画在 24×24 网格里：首页、列表、阅读页底栏一律按同一比例画进 21pt 画布
	/// （以前首页 / 列表页的档位图标按 24pt 画，同一颗星大了 14%），再按形状做视觉修正——
	/// 实心 / 空心的圆会把框占满，比同宽的星看起来大一圈；向下箭头又宽又粗。
	enum BarOptical {
		static let circle: CGFloat = 0.86
		static let chevron: CGFloat = 0.85
		static let star: CGFloat = 1
		static let lines: CGFloat = 1
		/// 翻译符号（A / 文 双气泡）：1.x 的 14.5pt 放在这里比邻居大一圈，按同样的视觉大小取 11.5pt（角标等比例缩小）
		static let translatePointSize: CGFloat = 11.5
	}

	/// 底栏图标：画布固定 21pt（位置、点按区都不变），图形在里面居中画成 21 × optical 大小。模板渲染，随 tintColor 变色。
	static func barIcon(_ image: UIImage?, optical: CGFloat = 1) -> UIImage? {
		guard let image, image.size.width > 0, image.size.height > 0 else { return image }
		let canvas = CGSize(width: toolbarIcon, height: toolbarIcon)
		let scale = toolbarIcon * optical / max(image.size.width, image.size.height)
		let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
		let rect = CGRect(x: (canvas.width - size.width) / 2, y: (canvas.height - size.height) / 2, width: size.width, height: size.height)
		return UIGraphicsImageRenderer(size: canvas, format: .preferred()).image { _ in
			image.draw(in: rect)
		}.withRenderingMode(.alwaysTemplate)
	}

	/// 「全部标为已读」：实心圆里挖出一个勾。设计稿里勾和圆同色，按模板上色后勾就消失了、只剩一个实心圆，
	/// 和阅读页的「已读」实心圆一模一样；这里按设计稿同样的坐标自己画，勾是镂空的。
	static func readAllIcon(side: CGFloat = toolbarIcon, optical: CGFloat = BarOptical.circle) -> UIImage {
		UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: .preferred()).image { context in
			let unit = side * optical / 24
			let origin = (side - 24 * unit) / 2
			func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: origin + x * unit, y: origin + y * unit) }
			UIColor.black.setFill()
			context.cgContext.fillEllipse(in: CGRect(x: origin + 4 * unit, y: origin + 4 * unit, width: 16 * unit, height: 16 * unit))
			let check = UIBezierPath()
			check.move(to: point(7.6, 12.64))
			check.addLine(to: point(10.16, 15.2))
			check.addLine(to: point(16.4, 8.8))
			check.lineWidth = 2.2 * unit
			check.lineCapStyle = .round
			check.lineJoinStyle = .round
			check.stroke(with: .clear, alpha: 1)
		}.withRenderingMode(.alwaysTemplate)
	}

	/// 设计稿图标（SVG 矢量）按比例重画，使较长的一边等于 side（「•••」这种扁图标也不变形）；
	/// 模板渲染方式保留，照样随 tintColor 变色。
	static func icon(_ image: UIImage?, side: CGFloat) -> UIImage? {
		guard let image, image.size.width > 0, image.size.height > 0 else { return image }
		let scale = side / max(image.size.width, image.size.height)
		let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
		let format = UIGraphicsImageRendererFormat.preferred()
		let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
			image.draw(in: CGRect(origin: .zero, size: size))
		}
		return resized.withRenderingMode(image.renderingMode == .automatic ? .alwaysTemplate : image.renderingMode)
	}
}

/// 底栏五个位置（ADR-033）：402pt 画布上 x = 32 / 116.5 / 201 / 285.5 / 370，中心 y = 24。
///
/// 原先照搬 Figma 的 32 / 104 / 201 / 290.5 / 362，相邻间距是 72 / 97 / 89.5 / 71.5，
/// 用户觉得「没有平均散开」。现在两端贴边 32、中间三格等距 84.5，左右完全对称。
/// 首页只有中间三档（116.5 / 201 / 285.5），与其它页的中间三格对齐。
enum Babel2BarLayout {
	static let referenceWidth: CGFloat = 402
	static let slots: [CGFloat] = [32, 116.5, 201, 285.5, 370]
	static var scopeSlots: [CGFloat] { Array(slots[1...3]) }
	static let centerY: CGFloat = 24

	/// 按参考画布比例定位的横向约束（屏幕宽度不同也保持相对位置）。
	static func centerX(_ view: UIView, in bar: UIView, slot: CGFloat) -> NSLayoutConstraint {
		NSLayoutConstraint(item: view, attribute: .centerX, relatedBy: .equal, toItem: bar, attribute: .trailing,
			multiplier: slot / referenceWidth, constant: 0)
	}
}
