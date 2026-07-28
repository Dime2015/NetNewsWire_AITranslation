//
//  FeedListMetrics.swift
//  NetNewsWire — AI 翻译 fork
//
//  [外观] 本 fork 新增,上游没有这个文件。
//
//  ## 这个文件解决什么问题
//
//  订阅列表(首页)的行显得「松垮」。2026-07-28 逐像素量过两边:
//
//  | | 我们(改前) | Reeder |
//  |---|---|---|
//  | 源名字高 | 16.0pt | 15.3pt |
//  | **行距** | **50.3pt**(49.0~51.7 波动) | **44.0pt**(分毫不差) |
//  | **图标** | **24pt** | **28pt** |
//
//  结论:**字号没问题,问题是"元素偏小 + 间距偏大"** ——
//  图标占行高的比例我们是 0.48、Reeder 是 0.64,所以我们的行是「空」的,它的是「满」的。
//  → 这里做两件方向相反的事:**行高收紧(50→44)、图标放大(24→28)**。
//
//  ## 为什么这些值住在代码里,而不是直接改 storyboard
//
//  这些约束原本全在 `Main.storyboard` 里。按 CLAUDE.md,storyboard 是 D 级
//  (XML,merge 冲突风险高,L6「能不碰就不碰」)。所以这里的做法是:
//  **storyboard 一个字节都不改**,在 cell 的 `awakeFromNib` 里把相关约束
//  停用 / 改常量,用本文件的值重建。上游以后改 storyboard 也不会和我们冲突。
//
//  ## ⚠️ 这里依赖 storyboard 里的约束「长什么样」
//
//  识别靠的是特征(常量 15 的上下内边距、常量 24 的图标宽高),不是靠 id。
//  万一上游哪天改了那几个数,这里会**静默失效**(界面退回原样,不崩)。
//  所以每个改动点都会 `assert` + 打一条 `[外观]` 日志说明改了几条 ——
//  合并上游后如果日志里的条数变了,就是这里需要跟着调(L69:日志的价值在于能排除什么)。
//

#if os(iOS)

import UIKit

enum FeedListMetrics {

	// MARK: - 可调的值(想再紧一点/松一点,只改这里)

	/// 行的目标高度。44pt 是 iOS 列表行的标准值,也是 Reeder 实测值。
	static let rowHeight: CGFloat = 44

	/// 文字上下的内边距。行高 = 文字行高 + 这个值×2。
	/// 改前是 15(撑出 50pt),改成 12 得到 44pt。
	static let verticalPadding: CGFloat = 12

	/// 订阅源 / 文件夹图标的边长。改前 24,放大到 28(Reeder 实测值)。
	static let iconSize: CGFloat = 28

	/// 展开三角距离行左边缘。三角挪到左边之后当层级的锚点。
	static let disclosureLeading: CGFloat = 2

	/// 文件夹图标距离行左边缘。
	///
	/// ⚠️ **这个值是三次实测调出来的,别凭"应该对齐"改回 16**:
	/// - 串在三角后面排 → 图标被推到 48pt,比自己内部的源(48pt)还靠右,层级颠倒;
	/// - 严格对齐顶层源的 16pt → 三角和图标**贴在一起甚至叠上**(用户实测反馈);
	/// - 28pt:三角按钮占 2~22,图标占 28~56,中间留出 6pt 净空;
	///   而顶层源图标在 32pt,只差 4pt —— 肉眼基本齐平,
	///   且文件夹略微靠左反而更像"容器"(Reeder 的文件夹行同样比源行靠左)。
	static let iconLeading: CGFloat = 28

	/// 展开三角按钮的边长。
	///
	/// ⚠️ **storyboard 里原本是 39pt,必须缩小**:三角要挤进图标左边那 16pt 的空当里。
	/// 22pt 的按钮里,chevron 图形居中约占中间 11pt(即 5.5~16.5pt),
	/// 图标从 16pt 起 —— 两者几乎不重叠,视觉上是"三角在图标左前方"。
	///
	/// **取舍**:点击区域从 39×39 缩到 20×20,比 iOS 建议的 44pt 小。
	/// 但这个按钮只管"展开/收起",点错的代价极低(再点一次即可),
	/// 而层级读错的代价是每次扫列表都要重新理解一遍。
	static let disclosureSize: CGFloat = 20

	private static let originalDisclosureSize: CGFloat = 39

	/// 图标与标题之间的间隙(和 storyboard 原值一致,保持观感不变)。
	static let iconToTitle: CGFloat = 8

	/// 未读数距离行右边缘 —— **必须和普通 cell 保持一致**,
	/// 否则文件夹的数字和智能组的数字对不齐(用户 2026-07-28 明确要求对齐)。
	static let trailingInset: CGFloat = 16

	// MARK: - 改前的原值(用来在约束堆里认人)

	private static let originalVerticalPadding: CGFloat = 15
	private static let originalIconSize: CGFloat = 24

	// MARK: - 应用到 cell

	/// 收紧「上下内边距」:把 storyboard 里那两条常量 15 的约束改成我们的值。
	///
	/// 返回改动的条数 —— 调用方拿它做自检(正常是 2 条:一条 top、一条 bottom)。
	@discardableResult
	@MainActor
	static func tightenVerticalPadding(in contentView: UIView) -> Int {
		var changed = 0
		for c in contentView.constraints {
			guard abs(c.constant - originalVerticalPadding) < 0.5 else { continue }
			guard c.firstAttribute == .top || c.firstAttribute == .bottom else { continue }
			c.constant = verticalPadding
			changed += 1
		}
		return changed
	}

	/// 把图标的宽高约束从 24 放大到我们的值。返回改动条数(正常是 2 条:宽 + 高)。
	@discardableResult
	@MainActor
	static func enlargeIcon(_ icon: UIView) -> Int {
		var changed = 0
		for c in icon.constraints {
			guard abs(c.constant - originalIconSize) < 0.5 else { continue }
			guard c.firstAttribute == .width || c.firstAttribute == .height else { continue }
			c.constant = iconSize
			changed += 1
		}
		return changed
	}

	/// **文件夹行专用**:把展开三角从最右边挪到最左边,让未读数顶到右边缘。
	///
	/// storyboard 里原本的水平链条是:
	/// `图标(左16) → 标题 → 未读数 → 三角 → 右边缘(3)`
	/// —— 于是文件夹的数字被三角挤得离右边缘很远,和智能组那几个数字对不齐。
	///
	/// 改成:
	/// `三角(左10) → 图标 → 标题 → 未读数 → 右边缘(16)`
	/// 数字于是和普通 cell 用同一个右边距,视觉上连成一条线;
	/// 三角挪到左边还顺带成了层级的锚点(Reeder 就是这么排的)。
	/// ⚠️ **重建时必须把被停用的每一条都补回来。**
	/// 第一版只补了 3 条,而停用的是 5 条 —— 漏掉的
	/// 「标题.leading = 图标.trailing」和「未读数.leading = 标题.trailing」
	/// 让标题失去横向定位、图标直接压在文字中间,文件夹行整个错乱。
	/// (停用了几条就该建回几条,数字要对上账 —— L74。)
	@MainActor
	static func moveDisclosureToLeading(contentView: UIView,
										disclosure: UIView,
										icon: UIView,
										title: UIView,
										unreadCount: UIView) -> Int {

		// ① 停用所有"横向"上牵扯到三角或图标的旧约束 ——
		//    只挑 leading/trailing,不碰 centerY / 宽高,免得把垂直居中一起拆了。
		var killed = 0
		for c in contentView.constraints {
			let first = c.firstItem as? UIView
			let second = c.secondItem as? UIView
			let touchesOurs = first === disclosure || second === disclosure
				|| first === icon || second === icon
				|| first === title || second === title
				|| first === unreadCount || second === unreadCount
			guard touchesOurs else { continue }
			let isHorizontal = [c.firstAttribute, c.secondAttribute].contains { attr in
				attr == .leading || attr == .trailing
			}
			guard isHorizontal else { continue }
			c.isActive = false
			killed += 1
		}

		// ② 把三角按钮缩小(理由见 disclosureSize 的注释:不缩小会导致层级颠倒)。
		for c in disclosure.constraints {
			guard abs(c.constant - originalDisclosureSize) < 0.5 else { continue }
			guard c.firstAttribute == .width || c.firstAttribute == .height else { continue }
			c.constant = disclosureSize
		}

		// ③ 重建**整条**横向链条:三角 → 图标 → 标题 → 未读数 → 右边缘。
		//    上一步停用了 5 条,这里就要建回 5 条,一条都不能少。
		for v in [disclosure, icon, title, unreadCount] {
			v.translatesAutoresizingMaskIntoConstraints = false
		}

		let titleToCount = unreadCount.leadingAnchor.constraint(
			greaterThanOrEqualTo: title.trailingAnchor, constant: 8)

		NSLayoutConstraint.activate([
			disclosure.leadingAnchor.constraint(equalTo: contentView.leadingAnchor,
												constant: disclosureLeading),
			// 图标独立定位在 16pt(和顶层源同一条竖线),不串在三角后面 —— 理由见 iconLeading
			icon.leadingAnchor.constraint(equalTo: contentView.leadingAnchor,
										  constant: iconLeading),
			title.leadingAnchor.constraint(equalTo: icon.trailingAnchor,
										   constant: iconToTitle),
			titleToCount,
			contentView.trailingAnchor.constraint(equalTo: unreadCount.trailingAnchor,
												  constant: trailingInset)
		])

		// 未读数不许被标题挤扁 —— 标题长了应该截断标题,而不是把数字压没。
		unreadCount.setContentCompressionResistancePriority(.required, for: .horizontal)
		unreadCount.setContentHuggingPriority(.required, for: .horizontal)

		return killed
	}
}

#endif
