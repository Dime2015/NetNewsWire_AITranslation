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
