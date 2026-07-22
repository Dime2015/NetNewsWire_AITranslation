//
//  VibrantTableViewCell.swift
//  NetNewsWire-iOS
//
//  Created by Jim Correia on 9/2/19.
//  Copyright © 2019 Ranchero Software. All rights reserved.
//

import UIKit

class VibrantTableViewCell: UITableViewCell {

	static let duration: TimeInterval = 0.6

	// [外观] 选中态不再把文字翻白 —— 新设计的选中高亮是淡暖色(见 applyThemeProperties),
	// 淡底上必须保持深色文字才看得清。原来翻白是为了配蓝色实心高亮。
	var labelColor: UIColor {
		return UIColor.label
	}

	var secondaryLabelColor: UIColor {
		return UIColor.secondaryLabel
	}

	override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
		super.init(style: style, reuseIdentifier: reuseIdentifier)
		commonInit()
	}

	required init?(coder: NSCoder) {
		super.init(coder: coder)
		commonInit()
	}

	private func commonInit() {
		applyThemeProperties()
	}

	override func setHighlighted(_ highlighted: Bool, animated: Bool) {
		super.setHighlighted(highlighted, animated: animated)
		updateVibrancy(animated: animated)
	}

	override func setSelected(_ selected: Bool, animated: Bool) {
		super.setSelected(selected, animated: animated)
		updateVibrancy(animated: animated)
	}

	/// Subclass overrides should call super
	func applyThemeProperties() {
		// [外观] 淡暖色"药丸"选中高亮:统一四角圆角、略内缩,取代 insetGrouped 那种
		// 随行位置变的卡片形状(原来是一整块 secondaryAccent 蓝)。
		self.selectedBackgroundView = AppAppearance.makePillSelectionBackgroundView()
	}

	/// Subclass overrides should call super
	func updateVibrancy(animated: Bool) {
		updateLabelVibrancy(textLabel, color: labelColor, animated: animated)
		updateLabelVibrancy(detailTextLabel, color: labelColor, animated: animated)
	}

	func updateLabelVibrancy(_ label: UILabel?, color: UIColor, animated: Bool) {
		guard let label = label else { return }
		if animated {
			UIView.transition(with: label, duration: Self.duration, options: .transitionCrossDissolve, animations: {
				label.textColor = color
			}, completion: nil)
		} else {
			label.textColor = color
		}
	}

}

class VibrantBasicTableViewCell: VibrantTableViewCell {

	@IBOutlet private var label: UILabel!
	@IBOutlet private var detail: UILabel!
	@IBOutlet private var icon: UIImageView!

	@IBInspectable var imageNormal: UIImage?
	@IBInspectable var imageSelected: UIImage?

	var iconTint: UIColor {
		return isHighlighted || isSelected ? labelColor : Assets.Colors.primaryAccent
	}

	var iconImage: UIImage? {
		return isHighlighted || isSelected ? imageSelected : imageNormal
	}

	override func updateVibrancy(animated: Bool) {
		super.updateVibrancy(animated: animated)
		updateIconVibrancy(icon, color: iconTint, image: iconImage, animated: animated)
		updateLabelVibrancy(label, color: labelColor, animated: animated)
		updateLabelVibrancy(detail, color: secondaryLabelColor, animated: animated)
	}

	private func updateIconVibrancy(_ icon: UIImageView?, color: UIColor, image: UIImage?, animated: Bool) {
		guard let icon = icon else { return }
		if animated {
			UIView.transition(with: icon, duration: Self.duration, options: .transitionCrossDissolve, animations: {
				icon.tintColor = color
				icon.image = image
			}, completion: nil)
		} else {
			icon.tintColor = color
			icon.image = image
		}
	}

}
