//
//  AppAppearance.swift
//  NetNewsWire — AI 翻译 fork
//
//  [外观] 本 fork 新增,上游没有这个文件。
//
//  全 app 原生界面(UIKit)的「外观中心 / 调色板」。
//
//  为什么要有这个文件:NetNewsWire 的颜色**没有统一来源**,散落在各个
//  view controller / cell / storyboard 里(有的写 .systemGroupedBackground、
//  有的干脆不设走系统白)。想成体系地换配色,必须先有一个集中的来源,
//  再让各处指到这里(和 TimelineStyle.swift 是同一个思路)。
//
//  ## 结构(两层)—— 目标:换色只动一个地方
//
//  1. `Palette`(调色板层,色号的**唯一真源**):每个颜色的浅色/深色**原始色值**都在这里。
//     想整体换个色系,只改这一层的几个 0xRRGGBB 数字。
//  2. 语义色层(`paperBackground` 等):界面代码只认语义名,不直接碰色号。
//     想单独调某种语义色,改这一层一行。
//
//  以后各页需要新颜色(正文字色、次要文字、强调色…),就往这两层各加一条,
//  边做边长,不空建一个用不上的大调色板。
//
//  注意:文章正文阅读页虽然是 WKWebView,但它的**纸色底也归这里管**(2026-07-23 改)——
//  网页设成透明,底由 `WebViewController` 的 view 铺 `paperBackground`。
//  这么做是为了让顶栏能安全地做透明:透出来的必须是 UIKit 的动态色(系统自适应),
//  而不是网页自己画的底(深浅色和 app 不同步,浅色模式下顶栏会变黑,见 L60)。
//  网页那边只剩文字和图的颜色,仍由主题 CSS / nnw_appearance.js 管。
//
//  ⚠️ 别用全局 UINavigationBarAppearance 去铺色 —— 会把大标题和 iOS 26 副标题
//  一起冲掉(见 NOTES-lessons L45)。正路:各列表设自己的 config.backgroundColor
//  (见 L44),导航栏保持系统默认透明,自然透出下面已变暖的背景。
//

#if os(iOS)

import UIKit
import SwiftUI

enum AppAppearance {

	// MARK: - 调色板(色号的唯一真源 —— 换色只改这一层的数字)

	private enum Palette {
		/// 暖纸背景。取色为命令行从用户提供的 Reeder / 深色截图取样(不是肉眼)。
		///
		/// ⚠️ **深色值 2026-07-28 修正过,原因值得记下来**:
		/// 原本是 `0x1E1E1E` —— 色相 0°、饱和度 **0.000**,是一块**纯中性灰**。
		/// 而本调色板深色一族的其它四个颜色(selectionDark / menuCardDark /
		/// menuSeparatorDark / inkDark)色相都在 **34~40°**、饱和度 0.06~0.13,
		/// 全是暖的 —— **只有这一个掉了队**。
		/// 后果:浅色模式下 app 是暖纸调,一切到深色模式,整片底色就变成通用的黑白,
		/// 「纸」的身份没了,而顶上的浮世绘头图仍是暖褐调,上下割裂。
		///
		/// 新值 `0x1E1C19`:色相 36°(与 menuCardDark 一致)、
		/// **明度 0.118 与旧值分毫不差** —— 只变暖,不变亮也不变暗。
		/// (调深浅要锁色相走明度轴,别在 RGB 里朝黑白混合,见 L54。)
		static let paperLight = rgb(0xF3F0EB)
		static let paperDark  = rgb(0x1E1C19)

		/// 选中高亮(淡暖色):比纸略深/浅一档,给点按反馈又不抢眼。
		static let selectionLight = rgb(0xE8E3DB)
		static let selectionDark  = rgb(0x2E2C28)

		/// 自绘选单(NNWMenu)卡片底:比纸面再亮/浮一档,营造"卡片浮在纸上"的层次。
		static let menuCardLight = rgb(0xFBF8F3)
		static let menuCardDark  = rgb(0x2A2825)

		/// 自绘选单的分隔线与卡片描边(极淡;深色下还兼任把卡片从暗背景里衬出来的描边)。
		static let menuSeparatorLight = rgb(0xE4DFD6)
		static let menuSeparatorDark  = rgb(0x3A3733)

		/// 暖墨文字色(取代纯黑/纯白的 .label,和暖纸底更搭)。目前选单在用;
		/// 以后别的自绘控件要文字色也用这条,别再开新色。
		static let inkLight = rgb(0x2C2823)
		static let inkDark  = rgb(0xE8E3DA)

		/// 次要暖墨(说明文字、注释性小字):比正文墨色淡两档。
		static let inkSecondaryLight = rgb(0x877F73)
		static let inkSecondaryDark  = rgb(0x9C958A)

		// ⚠️ 强调色(陶土红)**不在这里** —— 它的真源是
		// `iOS/Resources/Assets.xcassets/primaryAccentColor.colorset`(+ secondaryAccentColor)。
		// 原因:5 个 storyboard 按名字直接引这个 colorset,storyboard 读不了代码里的颜色,
		// 所以强调色只能放 colorset 里才能"一处改、全 app(含 storyboard)一起变"。
		// 想调强调色的深浅,改那个 colorset 的 RGB。
		//
		// 之后随各页需要往这里加:inkPrimary(正文字色)、inkSecondary(次要文字)…… 每条写浅+深。

		/// 0xRRGGBB → 不透明 UIColor。
		static func rgb(_ value: UInt32) -> UIColor {
			UIColor(red:   CGFloat((value >> 16) & 0xFF) / 255.0,
					green: CGFloat((value >> 8) & 0xFF) / 255.0,
					blue:  CGFloat(value & 0xFF) / 255.0,
					alpha: 1)
		}
	}

	// MARK: - ⚗️ 中性玻璃画布(2026-08-05 试验,一处开关)

	/// **把 app 的基底材质从「暖纸」换成「中性玻璃」。`false` = 完全回到暖纸。**
	///
	/// ## 为什么会有这一档(量出来的,不是审美主张)
	///
	/// 用户连着三轮说"玻璃感不够"。逐像素量完参考图才找到病根:
	///
	/// | | 参考图 | 暖纸档 |
	/// |---|---|---|
	/// | app 自身表面 | **#EAEAEA(234,精确中性 R=G=B)** | #F3F0EB(243,偏暖 8 级) |
	/// | 亮边 vs 画布 | 255−234 = **Δ21** | 253−243 = **Δ10** |
	/// | 面板 vs 画布 | 232−234 = **Δ−2** | 235−243 = **Δ−8** |
	///
	/// **白色是亮度的天花板**:画布越亮,那道纯白亮边越"发不出光"。
	/// 我们只有参考图一半的边缘对比度 —— 这才是"边缘没有反光"的真因,
	/// 不是亮边画细了(那个上一轮已经改对)。
	/// 而且参考图的面板与背景几乎同色(Δ2),层次**全靠那道边**撑;
	/// 我们反而把面板压暗 8 级去做层次,方向是反的(L101 那条只走了一半)。
	///
	/// 结论:**「暖纸」和「中性玻璃」是两种互斥的材质**,在纸上打磨不出玻璃。
	///
	/// ⚠️ 这一档等于「全局换肤」—— 用户 2026-08-04 明确否过一次。
	/// 现在重新提出来,是因为量化之后确认它是玻璃质感的**唯一**入口,
	/// 且做成了一行开关,不满意改回 `false` 即可。
	///
	/// 🔴 2026-08-11:用户反馈浅色模式下这套中性玻璃色"有点灰",要求改回暖纸——关掉。
	static let isGlassCanvas = false

	private enum Glass {
		/// 精确取自参考图三张图的 app 表面:**#EAEAEA**
		static let paperLight = rgb(0xEAEAEA)
		/// 深色:同样去掉暖味,明度沿用暖纸档的 0.118
		static let paperDark  = rgb(0x1E1E1E)
		static let selectionLight = rgb(0xDEDEDE)
		static let selectionDark  = rgb(0x2E2E2E)
		static let menuCardLight = rgb(0xF0F0F0)
		static let menuCardDark  = rgb(0x2A2A2A)
		static let menuSeparatorLight = rgb(0xD6D6D6)
		static let menuSeparatorDark  = rgb(0x3A3A3A)
		/// 参考图的文字实测 #0A0A0A —— 近纯黑,不是暖墨
		static let inkLight = rgb(0x0E0E0E)
		static let inkDark  = rgb(0xEDEDED)
		static let inkSecondaryLight = rgb(0x8A8A8A)
		static let inkSecondaryDark  = rgb(0x9A9A9A)

		/// `Palette.rgb` 是 Palette 私有的,兄弟类型看不见 —— 这里自带一份,
		/// 免得为了共用去放宽 Palette 的访问级别(那是改上游风格的既有代码)。
		private static func rgb(_ hex: UInt32) -> UIColor {
			UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
					green: CGFloat((hex >> 8) & 0xFF) / 255,
					blue: CGFloat(hex & 0xFF) / 255,
					alpha: 1)
		}
	}

	// MARK: - 语义色(界面代码用这些,不直接碰色号)

	/// 背景,自动跟随系统浅色 / 深色。玻璃档 = 中性,暖纸档 = 暖。
	static let paperBackground = isGlassCanvas
		? dynamic(light: Glass.paperLight, dark: Glass.paperDark)
		: dynamic(light: Palette.paperLight, dark: Palette.paperDark)

	/// 表格 cell 选中时的淡色高亮(取代系统蓝)。
	static let selectionHighlight = isGlassCanvas
		? dynamic(light: Glass.selectionLight, dark: Glass.selectionDark)
		: dynamic(light: Palette.selectionLight, dark: Palette.selectionDark)

	/// 自绘选单(NNWMenu)的卡片底色。
	static let menuCardBackground = isGlassCanvas
		? dynamic(light: Glass.menuCardLight, dark: Glass.menuCardDark)
		: dynamic(light: Palette.menuCardLight, dark: Palette.menuCardDark)

	/// 自绘选单的分隔线 / 描边色。
	static let menuSeparator = isGlassCanvas
		? dynamic(light: Glass.menuSeparatorLight, dark: Glass.menuSeparatorDark)
		: dynamic(light: Palette.menuSeparatorLight, dark: Palette.menuSeparatorDark)

	/// 主文字色(自绘控件的文字与图标用,别直接用 .label)。
	static let inkPrimary = isGlassCanvas
		? dynamic(light: Glass.inkLight, dark: Glass.inkDark)
		: dynamic(light: Palette.inkLight, dark: Palette.inkDark)

	/// 次要文字(自绘控件里的说明文字用,别直接用 .secondaryLabel)。
	static let inkSecondary = isGlassCanvas
		? dynamic(light: Glass.inkSecondaryLight, dark: Glass.inkSecondaryDark)
		: dynamic(light: Palette.inkSecondaryLight, dark: Palette.inkSecondaryDark)

	// MARK: - 复用:把「分组表格」类页面(设置等)刷成暖纸风

	/// 把一个 UITableView(设置这类 insetGrouped 分组表格)刷成暖纸底、无分隔线。
	/// ⚠️ cell 的卡片底色要在各 VC 的 `willDisplay` 里配合调 `applyPaperStyle(to: cell)` ——
	/// 表格没有"统一设每个 cell 背景"的入口,只能逐 cell 来。
	@MainActor
	static func applyPaperStyle(to tableView: UITableView) {
		tableView.backgroundColor = paperBackground
		tableView.separatorStyle = .none
	}

	/// 把一个 cell 刷成暖纸风:卡片底色 = 暖纸色 + 统一的"药丸"选中高亮(在 `willDisplay` 里调)。
	/// 普通 UITableViewCell 默认没有药丸高亮,这里一并补上;VibrantTableViewCell 已自带同样的,
	/// 被这里覆盖成一模一样的,无害。
	@MainActor
	static func applyPaperStyle(to cell: UITableViewCell) {
		cell.backgroundColor = paperBackground
		cell.selectedBackgroundView = makePillSelectionBackgroundView()
	}

	// MARK: - 工具

	/// 按当前浅 / 深色返回对应的颜色。系统切换深浅色时 UIKit 会自动重解析。
	private static func dynamic(light: UIColor, dark: UIColor) -> UIColor {
		UIColor { traits in traits.userInterfaceStyle == .dark ? dark : light }
	}

	/// 造一个"药丸高亮"选中视图(见 PillSelectionBackgroundView)。
	/// 给 UITableViewCell 当 selectedBackgroundView 用。
	@MainActor
	static func makePillSelectionBackgroundView() -> UIView {
		PillSelectionBackgroundView()
	}
}

// MARK: - [交互] 统一的"取消 / 勾保存"导航按钮

extension UIViewController {

	/// 给一个"填 / 选东西"的设置子页装上统一的两个导航按钮:
	/// **左上角「取消」= 不保存退回;右上角「勾」= 保存并返回**(iOS 惯例)。
	///
	/// 各页自己实现 saveAction(保存并 pop)和 cancelAction(直接 pop),
	/// 并把"改动"做成"待定"—— 只有 saveAction 里才真正落库。
	func nnwInstallCancelSaveItems(saveAction: Selector, cancelAction: Selector) {
		navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel,
														   target: self, action: cancelAction)
		let save = UIBarButtonItem(image: UIImage(systemName: "checkmark"),
								   style: .done, target: self, action: saveAction)
		save.accessibilityLabel = "保存"
		navigationItem.rightBarButtonItem = save
	}
}

// MARK: - SwiftUI 侧(信息页那批是 SwiftUI,不是 UIKit 表格)

extension AppAppearance {
	/// 暖纸背景的 SwiftUI 版。
	static var paperBackgroundColor: Color { Color(uiColor: paperBackground) }
}

extension View {

	/// [外观] 给 SwiftUI 页(VStack / ScrollView 这类)铺暖纸底(铺满整屏,含安全区外)。
	func nnwPaperBackground() -> some View {
		background(AppAppearance.paperBackgroundColor.ignoresSafeArea())
	}

	/// [外观] 给 SwiftUI List 铺暖纸底 + 隐藏系统灰底。
	/// ⚠️ 行/Section 还要各自加 `.nnwPaperRow()`,否则行仍是白卡片浮在暖底上。
	func nnwPaperList() -> some View {
		scrollContentBackground(.hidden)
			.background(AppAppearance.paperBackgroundColor.ignoresSafeArea())
	}

	/// [外观] 把 List 里的行 / Section 刷成暖纸底 + 去掉分隔线(配合 nnwPaperList 用)。
	func nnwPaperRow() -> some View {
		listRowBackground(AppAppearance.paperBackgroundColor)
			.listRowSeparator(.hidden)
	}
}

/// [外观] "药丸"选中高亮:统一四角圆角 + 略微内缩的暖色块。
///
/// 用来取代 iOS `insetGrouped` 那种"首行顶部圆角、末行底部圆角、中间不圆、还随位置变"
/// 的选中形状 —— 那个形状在颜色统一后一点按就冒出来,显得割裂、突兀。
/// 这里改成:**不管第几行,都高亮成同一个四角一致的小圆角块**,像现代菜单项。
///
/// 做法:自己背景透明,里面放一个内缩的圆角块。因为圆角块严格缩在 cell 卡片内部、
/// 碰不到卡片边缘,所以不受 insetGrouped 卡片圆角遮罩的影响,四角圆角总是完整、一致。
final class PillSelectionBackgroundView: UIView {

	// 可调项(想调高亮的圆角 / 内缩,改这三个值即可,一处改全 app 一致)。
	private static let horizontalInset: CGFloat = 6
	private static let verticalInset: CGFloat = 4
	private static let cornerRadius: CGFloat = 10

	private let pill = UIView()

	override init(frame: CGRect) {
		super.init(frame: frame)
		setUp()
	}

	required init?(coder: NSCoder) {
		super.init(coder: coder)
		setUp()
	}

	private func setUp() {
		backgroundColor = .clear
		pill.backgroundColor = AppAppearance.selectionHighlight
		pill.layer.cornerRadius = Self.cornerRadius
		pill.layer.cornerCurve = .continuous
		addSubview(pill)
	}

	override func layoutSubviews() {
		super.layoutSubviews()
		pill.frame = bounds.insetBy(dx: Self.horizontalInset, dy: Self.verticalInset)
	}
}

#endif
