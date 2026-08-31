//
//  MainFeedCollectionViewCell.swift
//  NetNewsWire-iOS
//
//  Created by Stuart Breckenridge on 23/06/2025.
//  Copyright © 2025 Ranchero Software. All rights reserved.
//

import UIKit
import RSCore
import Account
import RSTree
import Images

final class MainFeedCollectionViewCell: UICollectionViewCell {
	@IBOutlet var feedTitle: UILabel!
	@IBOutlet var faviconView: IconView!
	@IBOutlet var unreadCountLabel: UILabel!
	private var faviconLeadingConstraint: NSLayoutConstraint?

	var iconImage: IconImage? {
		didSet {
			// [外观] 订阅源图标统一风格(彩色 → 灰度;透明背景的图形补一层方块底),
			// 实现全在本 fork 新增的 NNWFeedIconStyle 里,这里只加一层包装。
			faviconView.iconImage = NNWFeedIconStyle.styled(iconImage)
			faviconView.tintColor = Self.nnwIconTint(for: iconImage)
		}
	}

	/// [外观] 侧栏图标的着色。
	///
	/// 默认**走调色板**(`NNWSoftMaterial.accent`)—— 换主题色时全 app 一起跟上;
	/// 不能吃上游的 `preferredColor`,那是 xcassets 静态色板,换色跟不动(T40 追加六的判据)。
	///
	/// **唯一的例外是「今天」那颗太阳**(用户 2026-08-05:
	/// 「希望在全部统一的主题色里加一抹亮色,但是用克制的方式」)。
	/// ⚠️ 那抹亮色**直接用它上游自带的 `preferredColor`(systemOrange),不另立色号** ——
	/// 这样它天然跟随深浅色,而且以后上游改了这颗图标的颜色我们自动跟上。
	///
	/// ⚠️ 判据用 `===`:`IconImage` 是 final class,`Assets.Images.todayFeed` 是唯一实例。
	/// 别改成比字符串(标题会被本地化)或比颜色(那是循环论证)。
	static func nnwIconTint(for icon: IconImage?) -> UIColor {
		if let icon, icon === Assets.Images.todayFeed, let preferred = icon.preferredColor {
			return preferred
		}
		return .secondaryLabel
	}

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
			}
			unreadCountLabel.text = newValue.formatted()
		}
	}

	/// If the feed is contained in a folder, the indentation level is 1
	/// and the cell's favicon leading constrain is increased. Otherwise,
	/// it has the standard leading constraint.
	///
	/// On the storyboard, no leading constraint is set.
	var indentationLevel: Int = 0 {
		didSet {
			if indentationLevel == 1 {
				faviconLeadingConstraint?.constant = 32
			} else {
				faviconLeadingConstraint?.constant = 16
			}
		}
	}

	override var accessibilityLabel: String? {
		get {
			let name = feedTitle.text ?? ""
			if unreadCount > 0 {
				let unreadLabel = NSLocalizedString("unread", comment: "Unread label for accessibility")
				return "\(name) \(unreadCount) \(unreadLabel)"
			} else {
				return name
			}
		}
		set {}
	}

    override func awakeFromNib() {
		MainActor.assumeIsolated {
			super.awakeFromNib()
			isAccessibilityElement = true
			feedTitle.isAccessibilityElement = false
			unreadCountLabel.isAccessibilityElement = false
			faviconView.isAccessibilityElement = false
			faviconLeadingConstraint = faviconView.leadingAnchor.constraint(equalTo: contentView.safeAreaLayoutGuide.leadingAnchor)
			faviconLeadingConstraint?.isActive = true

			// [外观] 收紧行高(50→44)+ 放大图标(24→28),值见 FeedListMetrics。
			// 这一页的未读数原本就顶到右边缘(trailing+16),不用动。
			let padded = FeedListMetrics.tightenVerticalPadding(in: contentView)
			let sized = FeedListMetrics.enlargeIcon(faviconView)
			NSLog("[外观] 订阅源行:收紧内边距 \(padded) 条、图标放大 \(sized) 条")
		}
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
			feedTitle.textColor = .label
			feedTitle.font = UIFont.systemFont(ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize,
											   weight: .semibold)
			unreadCountLabel.textColor = .label
			unreadCountLabel.font = UIFont.systemFont(ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize, weight: .semibold)
		default:
			feedTitle.textColor = .label
			feedTitle.font = UIFont.preferredFont(forTextStyle: .body)
			unreadCountLabel.font = UIFont.preferredFont(forTextStyle: .body)
			unreadCountLabel.textColor = .secondaryLabel
			if traitCollection.userInterfaceIdiom == .phone {
				if feedTitle.text == "All Unread" {
					faviconView.tintColor = .secondaryLabel
				}
			}
		}
		// [外观] iPhone 上把非选中态的卡片底色也抹成暖纸色,让订阅列表整片是暖背景
		// (选中/高亮态保留系统反馈,不动)。
		if traitCollection.userInterfaceIdiom == .phone,
		   !(state.isHighlighted || state.isSelected || state.isFocused) {
			backgroundConfig.backgroundColor = AppAppearance.paperBackground
		}
		self.backgroundConfiguration = backgroundConfig
	}
}
