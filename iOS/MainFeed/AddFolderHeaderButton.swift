//
//  AddFolderHeaderButton.swift
//  NetNewsWire-iOS
//
//  [界面] 本 fork 新增,上游没有这个文件。
//
//  作用:在订阅列表的账户分组头(「我的 iPhone」那一行)右侧,
//       放一个「新建文件夹」按钮。
//
//  ## 为什么不改 storyboard
//
//  这个分组头的布局定义在 `iOS/Base.lproj/Main.storyboard` 里,横向是一条约束链:
//
//      [标题] →+8→ [未读数] →+8→ [箭头] →+3→ 容器右边
//
//  想把按钮插进去,得打断「箭头.leading = 未读数.trailing + 8」这条约束。
//  但 Main.storyboard 是 932 行 XML,是本项目 merge 风险最高的文件之一(见 L6)。
//
//  所以改成:**运行时**按「两端分别是谁」把那条约束精确找出来、停用,
//  再用代码把按钮接进链条。storyboard 一个字节都不用改。
//
//  ## 找不到约束怎么办
//
//  如果上游哪天改了这条约束,我们就找不到它 —— 这时**什么都不做**,
//  按钮不出现。宁可少一个按钮,也不要让分组头的布局错乱。
//  (对应 L12 的原则:永远不要静默地把事情做坏。)
//

import UIKit
import Account

extension MainFeedCollectionHeaderReusableView {

	/// 我们这个按钮的 tag。用 tag 而不是存储属性,是因为上游的类不能加存储属性。
	static let nnwAddFolderButtonTag = 987_101

	/// 在账户分组头上装「新建文件夹」按钮。
	///
	/// - Parameters:
	///   - accountID: 账户 id。传 nil 表示这不是账户分组(例如「智能订阅」),按钮会被藏起来。
	///   - target/action: 点按钮时通知谁。
	///
	/// 这个方法每次分组头被复用时都会被调用,所以必须能反复调用而不出错:
	/// 按钮只创建一次,之后只更新显示/隐藏。
	func nnwInstallAddFolderButton(accountID: String?, target: Any, action: Selector) {

		// 这个账户支不支持文件夹?不支持就别给按钮。
		// 判断方式抄的是上游 add(_:) 里的同款写法,保持行为一致。
		var shouldShow = false
		if let accountID,
		   let account = AccountManager.shared.existingAccount(accountID: accountID),
		   !account.behaviors.contains(.disallowFolderManagement) {
			shouldShow = true
		}

		if let existing = viewWithTag(Self.nnwAddFolderButtonTag) {
			// 已经装过了,只更新显示与否。
			// ⚠️ 必须更新 —— 分组头是复用的,账户的头可能被拿去当「智能订阅」的头。
			existing.isHidden = !shouldShow
			return
		}

		guard shouldShow else {
			return // 还没装过,而且这次也不该显示,那就先不装
		}

		// 把「未读数.leading = 标题.trailing」这条约束找出来。
		// 按两端是谁来匹配,不靠 storyboard 里的 id —— id 是会变的,对象关系不会。
		//
		// 为什么断这一条(而不是「箭头↔未读数」那条):
		// 按钮要**紧跟在账户名右边**,并且随名字长短自动挪位置。
		// 断这一条,把按钮接在标题和未读数之间,未读数就仍然保持原来
		// 「贴着右边箭头」的位置不变。
		let linkConstraint = constraints.first { constraint in
			(constraint.firstItem === unreadCountLabel
				&& constraint.firstAttribute == .leading
				&& constraint.secondItem === headerTitle)
			|| (constraint.firstItem === headerTitle
				&& constraint.firstAttribute == .trailing
				&& constraint.secondItem === unreadCountLabel)
		}

		guard let linkConstraint else {
			// 上游改了布局。什么都不做,别把分组头搞乱。
			return
		}

		// 图标本身不大,用 configuration 给个宽松的内边距,免得难按。
		// (iOS 15 起 contentEdgeInsets 被 UIButton.Configuration 取代)
		var configuration = UIButton.Configuration.plain()
		configuration.image = UIImage(systemName: "folder.badge.plus")
		configuration.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8)

		let button = UIButton(configuration: configuration)
		button.tag = Self.nnwAddFolderButtonTag
		button.translatesAutoresizingMaskIntoConstraints = false
		button.accessibilityLabel = "新建文件夹"
		button.addTarget(target, action: action, for: .touchUpInside)
		// ⚠️ 颜色必须显式设定。
		// 第一版没设,按钮用的是继承来的 tintColor —— 在白底上等于隐形,
		// 只有弹出操作单把背景压暗时才显出一点灰色轮廓,看着像「时有时无」。
		// 实际上按钮一直都在、也一直能点(用户实测:看不见时点那个位置反而管用)。
		button.tintColor = .secondaryLabel
		addSubview(button)

		// 标题默认会**拉伸**去占满剩余空间(label 的水平 hugging 优先级只有 251),
		// 所以原来「未读数贴着右边」才是那个样子。
		// 现在要让按钮紧跟名字,就得先让标题只占自己文字的宽度。
		headerTitle.setContentHuggingPriority(.defaultHigh, for: .horizontal)

		// 断开「标题 ↔ 未读数」那一节,改接成:标题 → 按钮 →(可伸缩)→ 未读数
		linkConstraint.isActive = false
		let flexibleGap = unreadCountLabel.leadingAnchor.constraint(
			greaterThanOrEqualTo: button.trailingAnchor, constant: 8)
		NSLayoutConstraint.activate([
			button.leadingAnchor.constraint(equalTo: headerTitle.trailingAnchor, constant: 6),
			button.centerYAnchor.constraint(equalTo: headerTitle.centerYAnchor),
			flexibleGap
		])

		// 约束是在「分组头即将显示」这个时机改的,不主动要求重新布局的话,
		// 要等到下一次外力触发(例如弹个操作单)才会生效 —— 表现就是「按钮时有时无」。
		setNeedsLayout()

		// 整个分组头上挂着一个点击手势(上游用它折叠/展开分组)。
		// 不做处理的话,点按钮会**顺带把分组折叠掉**。
		// 这里给那个手势装一个仲裁者:触点落在我们按钮上时,手势不接管。
		for gesture in gestureRecognizers ?? [] where gesture is UITapGestureRecognizer {
			gesture.delegate = NNWHeaderTapArbiter.shared
		}
	}
}

/// 让「点按钮」和「点分组头折叠」两件事不打架。
///
/// 无状态,所以全 app 共用一个实例就够。
@MainActor final class NNWHeaderTapArbiter: NSObject, UIGestureRecognizerDelegate {

	static let shared = NNWHeaderTapArbiter()

	nonisolated func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
									   shouldReceive touch: UITouch) -> Bool {
		MainActor.assumeIsolated {
			// 触点落在我们的按钮上(或按钮的子视图上)时,折叠手势让路
			var view: UIView? = touch.view
			while let current = view {
				if current.tag == MainFeedCollectionHeaderReusableView.nnwAddFolderButtonTag {
					return false
				}
				view = current.superview
			}
			return true
		}
	}
}
