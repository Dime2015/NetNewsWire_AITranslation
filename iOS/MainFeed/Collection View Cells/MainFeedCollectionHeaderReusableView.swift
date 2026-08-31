//
//  MainFeedCollectionHeaderReusableView.swift
//  NetNewsWire-iOS
//
//  Created by Stuart Breckenridge on 12/07/2025.
//  Copyright © 2025 Ranchero Software. All rights reserved.
//

import UIKit
import Account

@MainActor protocol MainFeedCollectionHeaderReusableViewDelegate: AnyObject {
	func mainFeedCollectionHeaderReusableViewDidTapDisclosureIndicator(_ view: MainFeedCollectionHeaderReusableView)
}

enum SectionHeaderType {
	case smartFeeds
	case account(String) // accountID
}

final class MainFeedCollectionHeaderReusableView: UICollectionReusableView {
	var delegate: MainFeedCollectionHeaderReusableViewDelegate?
	var sectionHeaderType: SectionHeaderType?

	@IBOutlet var headerTitle: UILabel!
	@IBOutlet var disclosureIndicator: UIImageView!
	@IBOutlet var unreadCountLabel: UILabel!

	private var unreadLabelWidthConstraint: NSLayoutConstraint?

	override var accessibilityLabel: String? {
		get {
			if unreadCount > 0 {
				let unreadLabel = NSLocalizedString("unread", comment: "Unread label for accessibility")
				return "\(headerTitle.text ?? "") \(unreadCount) \(unreadLabel) \(expandedStateMessage) "
			} else {
				return "\(headerTitle.text ?? "") \(expandedStateMessage) "
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

	private var _unreadCount: Int = 0

	var unreadCount: Int {
		get {
			return _unreadCount
		}
		set {
			_unreadCount = newValue
			updateUnreadCount()
			unreadCountLabel.text = newValue.formatted()
		}
	}

	/// [外观] 展开三角跟着主题色走。
	///
	/// ⚠️ **不能写在 IBOutlet 的 `didSet` 里**(2026-08-05 用户报"换了主题色三角还是橙的"):
	/// 那个 didSet 只在 **nib 加载时跑一次**,而分组头是**复用**的 ——
	/// 换色后没有人再去走它,颜色就永远停在旧值。
	/// 挪到每次配装都会跑的地方(`disclosureExpanded` 的 didSet)才跟得上。
	var disclosureExpanded = true {
		didSet {
			disclosureIndicator?.tintColor = .secondaryLabel
			updateExpandedState(animate: true)
			updateUnreadCount()
		}
	}

	override func awakeFromNib() {
		MainActor.assumeIsolated {
			super.awakeFromNib()
			isAccessibilityElement = true
			headerTitle.isAccessibilityElement = false
			unreadCountLabel.isAccessibilityElement = false
			disclosureIndicator.isAccessibilityElement = false
			unreadLabelWidthConstraint = unreadCountLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 80)
			unreadLabelWidthConstraint?.isActive = true
			configureUI()
			addTapGesture()
		}
	}

	override func prepareForReuse() {
		super.prepareForReuse()

		sectionHeaderType = nil

		let contextMenuInteractions = interactions.compactMap { $0 as? UIContextMenuInteraction }
		for interaction in contextMenuInteractions {
			removeInteraction(interaction)
		}
	}

	func configureUI() {
		headerTitle.textColor = traitCollection.userInterfaceIdiom == .pad ? .tertiaryLabel : .label
		backgroundColor = AppAppearance.paperBackground	// [外观] 分组头也用暖纸底,别露出系统灰
	}

	private func addTapGesture() {
		let tapGesture = UITapGestureRecognizer(target: self, action: #selector(containerHeaderTapped))
		self.addGestureRecognizer(tapGesture)
		self.isUserInteractionEnabled = true
	}

	@objc private func containerHeaderTapped() {
		delegate?.mainFeedCollectionHeaderReusableViewDidTapDisclosureIndicator(self)
	}

	func configureContainer(withTitle title: String) {
		headerTitle.text = title
		disclosureIndicator.transform = .identity
	}

	func updateExpandedState(animate: Bool) {

		if disclosureExpanded == false {
			unreadLabelWidthConstraint = unreadCountLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 80)
		} else {
			unreadLabelWidthConstraint = unreadCountLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 0)
			unreadLabelWidthConstraint?.isActive = false
		}

		let angle: CGFloat = disclosureExpanded ? 0 : -.pi / 2
		let transform = CGAffineTransform(rotationAngle: angle)
		let animations = {
			self.disclosureIndicator.transform = transform
		}
		if animate {
			UIView.animate(withDuration: 0.3, animations: animations)
		} else {
			animations()
		}
	}

	func updateUnreadCount() {
		if !disclosureExpanded && unreadCount > 0 {
			UIView.animate(withDuration: 0.3) {
				self.unreadCountLabel.alpha = 1
			}
		} else {
			UIView.animate(withDuration: 0.3) {
				self.unreadCountLabel.alpha = 0
			}
		}
	}

}
