//
//  NNWFeedListEditDecor.swift
//  NetNewsWire — AI 翻译 fork
//
//  [编辑] 首页原地编辑模式的**行装饰**:勾选圈 + 轻微抖动 + 内容右移让位。
//  本 fork 新增文件,上游没有。
//
//  ## ⚠️ 这个文件存在的全部理由:一行约束都不碰
//
//  首页的行是**故事板里的自定义 cell**(不是系统的列表行),所以拿不到系统多选
//  自带的勾选圈。照常规做法要给两个 cell 加勾选圈 + 把内容往右推,
//  就得动它们的横向约束 —— 而那正是这一页最脆的地方:
//  `FeedListMetrics` 已经对那批约束做过一次手术(停用 5 条、重建 5 条),
//  文件夹行的横向链条整个是在函数里现建的,**外面根本拿不到那几根约束**。
//  再往上叠一层"编辑时改约束",几乎必然把行高、图标、三角的位置一起弄坏。
//
//  所以这里换一条完全不同的路,三件事各走各的层,互不干扰:
//
//  | 要什么 | 挂在哪 | 为什么不会打架 |
//  |---|---|---|
//  | 勾选圈 | **cell 本身**的子视图(和 contentView 平级) | 不进 contentView,就不参与它那套约束 |
//  | 内容右移让位 | `contentView.transform` 平移 | 变换和约束是两套东西,约束一根没动 |
//  | 抖动 | **cell.layer** 的旋转动画 | 和上面那个平移不在同一层,不会互相覆盖 |
//
//  最后一条尤其重要:如果把抖动也加在 contentView 上,它的 `transform.rotation`
//  动画会**顶掉**我们设的平移(两者写的是同一个 transform)。分层就没这个问题。
//
//  文件夹行的展开三角自己也用着 `transform`(旋转),而它住在 contentView **里面**,
//  contentView 整体平移不影响它自己的变换 —— 这也是选择平移 contentView 而不是
//  平移各个子视图的原因。
//

#if os(iOS)

import UIKit

/// 能进入编辑模式的行。用来告诉装饰层"这一行右边那个数字是谁"(编辑时要把它藏起来)。
///
/// 为什么要藏:内容整体右移之后,右边的未读数会被挤出可视区、只露半个,很难看。
/// 而编辑模式下未读数本来也没有意义。
@MainActor protocol NNWEditableFeedCell: UICollectionViewCell {
	/// 行右侧的未读数标签(没有就返回 nil)。
	var nnwTrailingBadge: UIView? { get }
	/// 这一行的标题标签 —— 编辑模式下要让它**早一点换行**,别顶到行尾那支铅笔上。
	var nnwTitleLabel: UILabel? { get }
}

// 两个 cell 的实现写在这里,**上游那两个文件一行都不用改**。
extension MainFeedCollectionViewCell: NNWEditableFeedCell {
	var nnwTrailingBadge: UIView? { unreadCountLabel }
	var nnwTitleLabel: UILabel? { feedTitle }
}

extension MainFeedCollectionViewFolderCell: NNWEditableFeedCell {
	var nnwTrailingBadge: UIView? { unreadCountLabel }
	var nnwTitleLabel: UILabel? { folderTitle }
}

// MARK: - 装饰

extension UICollectionViewCell {

	private static var nnwSelectionCircleKey: UInt8 = 0
	private static var nnwRowPencilKey: UInt8 = 0
	private static var nnwTitleClampKey: UInt8 = 0
	private static var nnwHiddenForEditingKey: UInt8 = 0

	/// 编辑模式下内容往右让出多少 —— 正好够放一个勾选圈。
	private static let nnwEditContentShift: CGFloat = 36

	private var nnwSelectionCircle: UIImageView? {
		get { objc_getAssociatedObject(self, &Self.nnwSelectionCircleKey) as? UIImageView }
		set { objc_setAssociatedObject(self, &Self.nnwSelectionCircleKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
	}

	private var nnwRowPencil: UIButton? {
		get { objc_getAssociatedObject(self, &Self.nnwRowPencilKey) as? UIButton }
		set { objc_setAssociatedObject(self, &Self.nnwRowPencilKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
	}

	/// 编辑期间限制标题右边界的那根约束(只在编辑时启用)。
	private var nnwTitleClamp: NSLayoutConstraint? {
		get { objc_getAssociatedObject(self, &Self.nnwTitleClampKey) as? NSLayoutConstraint }
		set { objc_setAssociatedObject(self, &Self.nnwTitleClampKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
	}

	/// 「这一行的未读数此刻因为编辑模式而藏着」。
	/// 文件夹 cell 在折叠时会自己把未读数的 alpha 动画回 1 —— 它靠这个标记知道该不该动。
	var nnwIsHiddenForEditing: Bool {
		get { (objc_getAssociatedObject(self, &Self.nnwHiddenForEditingKey) as? Bool) ?? false }
		set { objc_setAssociatedObject(self, &Self.nnwHiddenForEditingKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
	}

	/// 编辑模式下标题要给行尾让出多少。
	///
	/// 算法:内容整体右移了 `nnwEditContentShift`(36),所以标题的右边界在**屏幕上**
	/// 也跟着右移了 36;行尾的铅笔占掉 12(边距)+ 34(按钮)= 46;再留 8 的呼吸缝。
	/// 合计 36 + 46 + 8 = 90。
	private static let nnwEditTitleTrailingReserve: CGFloat = 90

	/// 给这一行套上 / 摘掉编辑模式的装饰。
	///
	/// **幂等**:cell 会被反复复用,这个方法每次配置行时都会被调一遍,重复调用无害。
	///
	/// - Parameters:
	///   - editing: 是否处于编辑模式
	///   - selected: 是否已被勾选
	///   - animated: 进出编辑模式那一下要动画;滚动中复用出来的新行不要(否则会看到它"滑进来")
	func nnwApplyEditDecor(editing: Bool, selected: Bool, animated: Bool,
						   pencilTarget: Any? = nil, pencilAction: Selector? = nil) {

		let circle = nnwEnsureSelectionCircle()

		// ⓪ 行尾那支铅笔:点它拿到这一行自己的操作(重命名 / 删除 / 设置)。
		//
		// 为什么放**行尾**而不是行首:行首已经被勾选圈占着,再挤一个按钮进去,
		// 两个小圆点紧挨着、动作却完全不同(一个选中、一个开菜单),最容易误触。
		// 而编辑模式下未读数是隐藏的,**行尾本来就空着**;
		// 这也是 iOS 的老位置(设置里 Wi-Fi 那个 ⓘ 就在行尾),手上有肌肉记忆。
		if let pencilTarget, let pencilAction {
			let pencil = nnwEnsureRowPencil(target: pencilTarget, action: pencilAction)
			pencil.isHidden = !editing
		} else {
			nnwRowPencil?.isHidden = true
		}

		// ① 勾选圈:编辑时才有
		circle.isHidden = !editing
		if editing {
			circle.image = UIImage(systemName: selected ? "checkmark.circle.fill" : "circle")
			circle.tintColor = selected ? Assets.Colors.primaryAccent : .tertiaryLabel
		}

		// ①b 标题早一点换行,别顶到行尾那支铅笔上(2026-07-28 用户反馈)。
		//
		// ⚠️ 这里**新加一根自己的约束**,不去改任何现有约束 ——
		// 这一页的横向约束是最脆的地方(见文件头)。新加的是一条 `<=`,
		// 只会把标题的可用宽度**further 收窄**,不和既有约束抢;不编辑时停用即可复原。
		if let title = (self as? NNWEditableFeedCell)?.nnwTitleLabel {
			if nnwTitleClamp == nil {
				let clamp = title.trailingAnchor.constraint(
					lessThanOrEqualTo: contentView.trailingAnchor,
					constant: -Self.nnwEditTitleTrailingReserve)
				clamp.priority = UILayoutPriority(999)		// 别用 required,免得和既有约束冲突时整条崩掉
				nnwTitleClamp = clamp
			}
			nnwTitleClamp?.isActive = editing
		}

		// ② 右侧未读数:编辑时让它淡出(内容右移后它会被挤出可视区,只露半个很难看)。
		//
		// ⚠️ **用 alpha,绝对不要用 isHidden**(2026-07-28 交付前审查抓到的严重回归):
		// `isHidden` 是上游 cell 自己在管的 —— 未读数为 0 时它会把标签藏起来。
		// 我们若也去写 `isHidden`,就必须"记住原状再还原",而 cell 是**复用**的、
		// `prepareForReuse` 又不归我们管,那个"原状"必然会记成上一个源的状态。
		// 第一版正是这么写的,结果**不进编辑模式也会坏**:每次配置行都把标签强行显示出来,
		// 「全部」档下整页每行右边都挂一个 "0"。
		// 换成 alpha 之后这里是**幂等**的:只表达"编辑时不显示",
		// 该不该藏仍然完全由上游的 isHidden 决定,两者互不干扰。
		nnwIsHiddenForEditing = editing
		(self as? NNWEditableFeedCell)?.nnwTrailingBadge?.alpha = editing ? 0 : 1

		// ②b 落点高亮不属于常态外观 —— 每次配置行都撤掉,
		// 否则拖动时被高亮的行一旦滚出屏幕就没人给它复位,复用到别的行会带着蓝底(审查抓到)。
		if !editing { nnwSetDropTargetHighlighted(false) }

		// ③ 内容右移让位
		let target: CGAffineTransform = editing
			? CGAffineTransform(translationX: Self.nnwEditContentShift, y: 0)
			: .identity

		guard contentView.transform != target else { return }

		if animated {
			UIView.animate(withDuration: 0.25, delay: 0, options: [.beginFromCurrentState]) {
				self.contentView.transform = target
			}
		} else {
			contentView.transform = target
		}
	}

	/// 抖动:iOS 主屏那种整行轻微左右摇摆。
	///
	/// ⚠️ **加在 `cell.layer` 上,不能加在 contentView 上** ——
	/// contentView 的 transform 被"内容右移让位"占着,而
	/// `transform.rotation` 动画写的是同一个 transform,会把平移顶掉。
	///
	/// 每一行的相位错开一点点,整片看起来才像"活的",而不是所有行齐步走。
	/// 相位用行自己的地址取模算出来 —— 同一行每次复用都稳定,不会跳。
	func nnwStartJiggle() {
		guard layer.animation(forKey: Self.jiggleKey) == nil else { return }

		let angle: CGFloat = 0.016		// 弧度,约 0.9°。再大就吵了
		let animation = CAKeyframeAnimation(keyPath: "transform.rotation.z")
		animation.values = [0, -angle, 0, angle, 0]
		animation.keyTimes = [0, 0.25, 0.5, 0.75, 1]
		animation.duration = 0.28
		animation.repeatCount = .infinity
		animation.isRemovedOnCompletion = false

		// 相位错开:0 ~ 0.28 秒之间挑一个稳定的偏移
		let phase = Double(UInt(bitPattern: ObjectIdentifier(self).hashValue) % 100) / 100.0
		animation.timeOffset = phase * animation.duration

		layer.add(animation, forKey: Self.jiggleKey)
	}

	func nnwStopJiggle() {
		layer.removeAnimation(forKey: Self.jiggleKey)
	}

	private static let jiggleKey = "nnwJiggle"

	private func nnwEnsureRowPencil(target: Any, action: Selector) -> UIButton {
		if let existing = nnwRowPencil { return existing }

		let pencil = UIButton(type: .system)
		pencil.translatesAutoresizingMaskIntoConstraints = false
		pencil.setImage(UIImage(systemName: "ellipsis.circle"), for: .normal)
		pencil.tintColor = .secondaryLabel
		pencil.accessibilityLabel = "更多操作"
		pencil.addTarget(target, action: action, for: .touchUpInside)
		// 和勾选圈一样挂在 **cell 上**,不进 contentView —— 不参与那套约束,
		// 也不会跟着"内容右移"一起走。
		addSubview(pencil)
		NSLayoutConstraint.activate([
			pencil.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
			pencil.centerYAnchor.constraint(equalTo: centerYAnchor),
			pencil.widthAnchor.constraint(equalToConstant: 34),		// 比图标大一圈,好点
			pencil.heightAnchor.constraint(equalToConstant: 34),
		])
		nnwRowPencil = pencil
		return pencil
	}

	private func nnwEnsureSelectionCircle() -> UIImageView {
		if let existing = nnwSelectionCircle { return existing }

		let circle = UIImageView()
		circle.translatesAutoresizingMaskIntoConstraints = false
		circle.contentMode = .scaleAspectFit
		circle.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 20, weight: .regular)
		// 装在 **cell 上**,不是 contentView —— 这样它既不参与 contentView 那套约束,
		// 也不会跟着"内容右移"一起走(它得待在让出来的那块地方)。
		addSubview(circle)
		NSLayoutConstraint.activate([
			circle.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
			circle.centerYAnchor.constraint(equalTo: centerYAnchor),
			circle.widthAnchor.constraint(equalToConstant: 22),
			circle.heightAnchor.constraint(equalToConstant: 22),
		])
		nnwSelectionCircle = circle
		return circle
	}
}

#endif
