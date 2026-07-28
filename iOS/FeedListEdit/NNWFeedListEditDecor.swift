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
}

// 两个 cell 的实现写在这里,**上游那两个文件一行都不用改**。
extension MainFeedCollectionViewCell: NNWEditableFeedCell {
	var nnwTrailingBadge: UIView? { unreadCountLabel }
}

extension MainFeedCollectionViewFolderCell: NNWEditableFeedCell {
	var nnwTrailingBadge: UIView? { unreadCountLabel }
}

// MARK: - 装饰

extension UICollectionViewCell {

	private static var nnwSelectionCircleKey: UInt8 = 0

	/// 编辑模式下内容往右让出多少 —— 正好够放一个勾选圈。
	private static let nnwEditContentShift: CGFloat = 36

	private var nnwSelectionCircle: UIImageView? {
		get { objc_getAssociatedObject(self, &Self.nnwSelectionCircleKey) as? UIImageView }
		set { objc_setAssociatedObject(self, &Self.nnwSelectionCircleKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
	}

	/// 给这一行套上 / 摘掉编辑模式的装饰。
	///
	/// **幂等**:cell 会被反复复用,这个方法每次配置行时都会被调一遍,重复调用无害。
	///
	/// - Parameters:
	///   - editing: 是否处于编辑模式
	///   - selected: 是否已被勾选
	///   - animated: 进出编辑模式那一下要动画;滚动中复用出来的新行不要(否则会看到它"滑进来")
	func nnwApplyEditDecor(editing: Bool, selected: Bool, animated: Bool) {

		let circle = nnwEnsureSelectionCircle()

		// ① 勾选圈:编辑时才有
		circle.isHidden = !editing
		if editing {
			circle.image = UIImage(systemName: selected ? "checkmark.circle.fill" : "circle")
			circle.tintColor = selected ? Assets.Colors.primaryAccent : .tertiaryLabel
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
		(self as? NNWEditableFeedCell)?.nnwTrailingBadge?.alpha = editing ? 0 : 1

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
