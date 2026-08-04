//
//  MainFeedCollectionViewFolderCell.swift
//  NetNewsWire-iOS
//
//  Created by Stuart Breckenridge on 14/07/2025.
//  Copyright © 2025 Ranchero Software. All rights reserved.
//

import UIKit
import Images

@MainActor protocol MainFeedCollectionViewFolderCellDelegate: AnyObject {
	func mainFeedCollectionFolderViewCellDisclosureDidToggle(_ sender: MainFeedCollectionViewFolderCell, expanding: Bool)
}

class MainFeedCollectionViewFolderCell: UICollectionViewCell {
	@IBOutlet var folderTitle: UILabel!
	@IBOutlet var faviconView: IconView!
	@IBOutlet var unreadCountLabel: UILabel!
	@IBOutlet var disclosureButton: UIButton!

	var delegate: MainFeedCollectionViewFolderCellDelegate?

	private var _unreadCount: Int = 0
	var unreadCount: Int {
		get {
			return _unreadCount
		}
		set {
			_unreadCount = newValue
			if newValue == 0 {
				unreadCountLabel.isHidden = true
			} else {
				unreadCountLabel.isHidden = false
				updateUnreadCountVisibility()
			}
			unreadCountLabel.text = newValue.formatted()
		}
	}

	var iconImage: IconImage? {
		didSet {
			// [外观] 与订阅源 cell 保持同一条处理链路(见 NNWFeedIconStyle)。
			// 文件夹目前用的是 SF Symbol 图标,会被那边直接原样放行 ——
			// 这里加上是为了两个 cell 的写法一致,免得以后有人以为只处理了一半。
			faviconView.iconImage = NNWFeedIconStyle.styled(iconImage)
			faviconView.tintColor = iconImage?.preferredColor ?? Assets.Colors.secondaryAccent
		}
	}

	var disclosureExpanded = true {
		didSet {
			updateExpandedState(animate: true)
			updateUnreadCountVisibility()
		}
	}

	override func awakeFromNib() {
		MainActor.assumeIsolated {
			super.awakeFromNib()
			isAccessibilityElement = true
			folderTitle.isAccessibilityElement = false
			unreadCountLabel.isAccessibilityElement = false
			faviconView.isAccessibilityElement = false
			disclosureButton.isAccessibilityElement = false
			disclosureButton.addInteraction(UIPointerInteraction())
			disclosureButton.tintColor = NNWSoftMaterial.accent	// [外观] 2026-08-04:三角跟着这一页的橙色走

			// [外观] 收紧行高、放大图标,并把展开三角从最右挪到最左
			//(让未读数顶到右边缘,和智能组那几个数字对齐)。实现见 FeedListMetrics。
			let padded = FeedListMetrics.tightenVerticalPadding(in: contentView)
			let sized = FeedListMetrics.enlargeIcon(faviconView)
			let moved = FeedListMetrics.moveDisclosureToLeading(contentView: contentView,
															   disclosure: disclosureButton,
															   icon: faviconView,
															   title: folderTitle,
															   unreadCount: unreadCountLabel)
			// 认约束靠的是"特征"而不是 id,上游改了 storyboard 这里会静默失效 ——
			// 所以把条数打出来,合并上游后一眼能看出还灵不灵(见文件头的警告)。
			NSLog("[外观] 文件夹行:收紧内边距 \(padded) 条、图标放大 \(sized) 条、横向约束重排 \(moved) 条")
		}
	}

	func updateExpandedState(animate: Bool) {
		let angle: CGFloat = disclosureExpanded ? 0 : -.pi / 2
		let transform = CGAffineTransform(rotationAngle: angle)
		let animations = {
			self.disclosureButton.transform = transform
		}
		if animate {
			UIView.animate(withDuration: 0.3, animations: animations)
		} else {
			animations()
		}
	}

	func updateUnreadCountVisibility() {
		// [编辑] 加一行:编辑模式下这个数字是藏着的(内容右移后它会和行尾的铅笔叠在一起)。
		// 这个方法在**折叠文件夹**时会被调到,不挡的话数字会自己动画回来(2026-07-28 审查抓到)。
		if nnwIsHiddenForEditing { return }

		if !disclosureExpanded && unreadCount > 0 {
			UIView.animate {
				self.unreadCountLabel.alpha = 1
			}
		} else {
			UIView.animate {
				self.unreadCountLabel.alpha = 0
			}
		}
	}

	@IBAction
	func toggleDisclosure() {
		setDisclosure(isExpanded: !disclosureExpanded, animated: true)
		delegate?.mainFeedCollectionFolderViewCellDisclosureDidToggle(self, expanding: disclosureExpanded)
	}

	func setDisclosure(isExpanded: Bool, animated: Bool) {
		disclosureExpanded = isExpanded
	}

	override var accessibilityLabel: String? {
		get {
			let name = folderTitle.text ?? ""
			if unreadCount > 0 {
				let unreadLabel = NSLocalizedString("unread", comment: "Unread label for accessibility")
				return "\(name) \(unreadCount) \(unreadLabel) \(expandedStateMessage)"
			} else {
				return "\(name) \(expandedStateMessage)"
			}
		}
		set {}
	}

	private var expandedStateMessage: String {
		if disclosureExpanded {
			return NSLocalizedString("Expanded", comment: "Expanded")
		}
		return NSLocalizedString("Collapsed", comment: "Collapsed")
	}

	override var accessibilityCustomActions: [UIAccessibilityCustomAction]? {
		get {
			let name: String
			if disclosureExpanded {
				name = NSLocalizedString("Collapse", comment: "Collapse")
			} else {
				name = NSLocalizedString("Expand", comment: "Expand")
			}
			let toggleAction = UIAccessibilityCustomAction(name: name) { [weak self] _ in
				self?.toggleDisclosure()
				return true
			}
			return [toggleAction]
		}
		set {}
	}

	override func updateConfiguration(using state: UICellConfigurationState) {
		var backgroundConfig: UIBackgroundConfiguration
		if #available(iOS 18, *) {
			backgroundConfig = UIBackgroundConfiguration.listCell().updated(for: state)
		} else if traitCollection.userInterfaceIdiom == .pad {
			backgroundConfig = UIBackgroundConfiguration.listSidebarCell().updated(for: state)
		} else {
			backgroundConfig = UIBackgroundConfiguration.listGroupedCell().updated(for: state)
		}

		switch (state.isHighlighted || state.isSelected || state.isFocused, traitCollection.userInterfaceIdiom) {
		case (true, .pad):
			backgroundConfig.backgroundColor = .tertiarySystemFill
			folderTitle.textColor = Assets.Colors.primaryAccent
			folderTitle.font = UIFont.systemFont(ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize, weight: .semibold)
			unreadCountLabel.textColor = Assets.Colors.primaryAccent
			unreadCountLabel.font = UIFont.systemFont(ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize, weight: .semibold)
		default:
			folderTitle.textColor = .label
			faviconView.tintColor = Assets.Colors.primaryAccent
			folderTitle.font = UIFont.preferredFont(forTextStyle: .body)
			unreadCountLabel.textColor = .secondaryLabel
			unreadCountLabel.font = UIFont.preferredFont(forTextStyle: .body)
		}

		// [外观] 同订阅源 cell:iPhone 非选中态卡片抹成暖纸色(选中态和下面的拖放目标态不动)
		if traitCollection.userInterfaceIdiom == .phone,
		   !(state.isHighlighted || state.isSelected || state.isFocused) {
			backgroundConfig.backgroundColor = AppAppearance.paperBackground
		}

		if state.cellDropState == .targeted {
			backgroundConfig.backgroundColor = .tertiarySystemFill
		}

		self.backgroundConfiguration = backgroundConfig
	}
}
