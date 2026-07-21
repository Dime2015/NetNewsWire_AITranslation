//
//  MainTimelineCell.swift
//  NetNewsWire-iOS
//
//  Created by Brent Simmons on 6/22/26.
//

import UIKit
import RSCore
import Images

///  Manual-layout timeline cell modeled on the Mac timeline
///  and the pre-7.0 iOS table view cell.
final class MainTimelineCell: UICollectionViewCell {

	static let reuseIdentifier = "MainTimelineCell"

	var isPreview = false

	private let titleView = MainTimelineCell.multiLineLabel()
	private let summaryView = MainTimelineCell.multiLineLabel()
	private let dateView = MainTimelineCell.singleLineLabel()
	private let feedNameView = MainTimelineCell.singleLineLabel()
	private lazy var iconView = IconView()
	private lazy var indicatorView = IconView()
	private let topSeparator = UIView()
	/// [界面] 右侧的正文首图缩略图。没有图时隐藏,文字会铺满整宽。
	private let thumbnailView = MainTimelineCell.thumbnailImageView()

	var cellData: MainTimelineCellData! {
		didSet {
			updateSubviews()
		}
	}

	override init(frame: CGRect) {
		super.init(frame: frame)
		commonInit()
	}

	required init?(coder: NSCoder) {
		super.init(coder: coder)
		commonInit()
	}

	override func prepareForReuse() {
		super.prepareForReuse()
		indicatorView.isHidden = true
		// [界面] 复用前复位,否则上一篇文章的缩略图/浓淡会串到下一篇上
		thumbnailView.image = nil
		thumbnailView.isHidden = true
		contentView.alpha = TimelineStyle.unreadAlpha
	}

	override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
		let layout = updatedLayout(width: layoutAttributes.frame.width)
		layoutAttributes.frame.size.height = layout.height
		return layoutAttributes
	}

	override func layoutSubviews() {
		super.layoutSubviews()

		let layout = updatedLayout(width: contentView.bounds.width)

		setFrame(for: titleView, rect: layout.titleRect)
		setFrame(for: summaryView, rect: layout.summaryRect)
		feedNameView.setFrameIfNotEqual(layout.feedNameRect)
		dateView.setFrameIfNotEqual(layout.dateRect)
		iconView.setFrameIfNotEqual(layout.iconImageRect)
		// [界面] 星标现在在顶行时间旁边;未读圆点已弃用(改为整行浓淡)
		indicatorView.setFrameIfNotEqual(layout.starRect)
		thumbnailView.setFrameIfNotEqual(layout.thumbnailRect) // [界面]
		topSeparator.frame = CGRect(x: layout.separatorRect.minX, y: 0, width: layout.separatorRect.width, height: 1.0 / traitCollection.displayScale)
	}

	override func updateConfiguration(using state: UICellConfigurationState) {
		super.updateConfiguration(using: state)

		var backgroundConfig: UIBackgroundConfiguration
		if #available(iOS 18, *) {
			backgroundConfig = UIBackgroundConfiguration.listCell().updated(for: state)
		} else {
			backgroundConfig = UIBackgroundConfiguration.listGroupedCell().updated(for: state)
		}
		if state.traitCollection.horizontalSizeClass == .compact {
			// Full-bleed rectangle selection in compact width; iPad (regular width) keeps the
			// rounded, inset selection below.
			backgroundConfig.cornerRadius = 0
			backgroundConfig.backgroundInsets = .zero
			backgroundConfig.edgesAddingLayoutMarginsToBackgroundInsets = []
		} else if #available(iOS 26, *) {
			backgroundConfig.cornerRadius = 20
			backgroundConfig.edgesAddingLayoutMarginsToBackgroundInsets = [.leading, .trailing]
			if UIDevice.current.userInterfaceIdiom == .pad {
				backgroundConfig.backgroundInsets = NSDirectionalEdgeInsets(top: 0, leading: -8, bottom: 0, trailing: -8)
			} else if isPreview {
				backgroundConfig.backgroundInsets = NSDirectionalEdgeInsets(top: 0, leading: -16, bottom: 0, trailing: -16)
			} else {
				backgroundConfig.backgroundInsets = NSDirectionalEdgeInsets(top: 0, leading: -12, bottom: 0, trailing: -12)
			}
		} else {
			backgroundConfig.cornerRadius = 0
		}

		// Selected cells keep the standard system selection color from updated(for: state).
		if state.isSwiped {
			backgroundConfig.backgroundColor = .secondarySystemFill
		} else if !state.isSelected {
			backgroundConfig.backgroundColor = .clear
		}

		let isActive = state.isSwiped || state.isSelected

		if isPreview {
			backgroundConfig.backgroundColor = traitCollection.userInterfaceStyle == .dark ? .secondarySystemBackground : .white
		}
		backgroundConfiguration = backgroundConfig

		topSeparator.alpha = (isActive || isPreview) ? 0.0 : 1.0

		updateColors()
		updateIndicatorView()
	}

	func setIconImage(_ image: IconImage) {
		iconView.iconImage = image
	}
}

// MARK: - Private

private extension MainTimelineCell {

	static func singleLineLabel() -> UILabel {
		let label = NonIntrinsicLabel()
		label.lineBreakMode = .byTruncatingTail
		label.allowsDefaultTighteningForTruncation = false
		label.adjustsFontForContentSizeCategory = true
		return label
	}

	static func multiLineLabel() -> UILabel {
		let label = NonIntrinsicLabel()
		label.numberOfLines = 0
		label.lineBreakMode = .byTruncatingTail
		label.allowsDefaultTighteningForTruncation = false
		label.adjustsFontForContentSizeCategory = true
		return label
	}

	/// [界面] 缩略图控件。
	/// ⚠️ 尺寸完全由 layoutSubviews 里的 frame 决定,**绝不依赖图片撑出来的固有尺寸** ——
	/// 图还没下载好时它是空的,靠固有尺寸会被算成 0 宽而永久塌陷(见 NOTES-lessons L19)。
	static func thumbnailImageView() -> UIImageView {
		let imageView = UIImageView()
		imageView.contentMode = .scaleAspectFill
		imageView.clipsToBounds = true
		imageView.layer.cornerRadius = TimelineStyle.thumbnailCornerRadius
		imageView.layer.cornerCurve = .continuous
		imageView.backgroundColor = .clear
		return imageView
	}

	func commonInit() {
		isAccessibilityElement = true
		topSeparator.backgroundColor = TimelineStyle.separatorColor // [界面]
		// [界面] favicon 加圆角
		iconView.layer.cornerRadius = TimelineStyle.faviconCornerRadius
		iconView.layer.cornerCurve = .continuous
		iconView.clipsToBounds = true
		for view in [titleView, summaryView, dateView, feedNameView, iconView, indicatorView, topSeparator, thumbnailView] {
			contentView.addSubview(view)
			view.isAccessibilityElement = false
		}
		indicatorView.isHidden = true
	}

	func updatedLayout(width: CGFloat) -> MainTimelineCellLayout {
		guard cellData != nil else {
			return MainTimelineDefaultCellLayout(width: width, insets: .zero, cellData: MainTimelineCellData())
		}
		if traitCollection.preferredContentSizeCategory.isAccessibilityCategory {
			return MainTimelineAccessibilityCellLayout(width: width, insets: .zero, cellData: cellData)
		}
		return MainTimelineDefaultCellLayout(width: width, insets: .zero, cellData: cellData)
	}

	func setFrame(for label: UILabel, rect: CGRect) {
		if Int(floor(rect.height)) == 0 || Int(floor(rect.width)) == 0 {
			label.isHidden = true
		} else {
			label.isHidden = false
			label.setFrameIfNotEqual(rect)
		}
	}

	// [界面] 2026-07-21 改为 Reeder 式布局:
	// 顶行源名(所有列表都显示)、中间加粗标题、下面正文摘要、右侧缩略图。
	func updateSubviews() {
		titleView.font = TimelineStyle.headlineFont
		titleView.attributedText = cellData.attributedTitle.applyingBaseFont(TimelineStyle.headlineFont)

		summaryView.font = TimelineStyle.bodyFont
		summaryView.text = cellData.summary

		dateView.font = TimelineStyle.timeFont
		dateView.text = cellData.dateString

		// [界面] 源名恒显 —— 用户要求"所有地方格式统一",不再看 showFeedName。
		feedNameView.font = TimelineStyle.feedLineFont
		feedNameView.text = cellData.feedName
		feedNameView.isHidden = cellData.feedName.isEmpty

		// [界面] 位置永远留着(布局里已占位),只是没图时不画。
		if let iconImage = cellData.iconImage {
			iconView.iconImage = iconImage
			iconView.isHidden = false
		} else {
			iconView.iconImage = nil
			iconView.isHidden = true
		}

		// [界面] 缩略图:没有就藏起来,布局那边宽度会按 0 算,文字自动铺满。
		if let thumbnail = cellData.thumbnail {
			thumbnailView.image = thumbnail
			thumbnailView.isHidden = false
		} else {
			thumbnailView.image = nil
			thumbnailView.isHidden = true
		}

		updateColors()
		updateIndicatorView()
		updateAccessibilityLabel()
		setNeedsLayout()
	}

	func updateColors() {
		// [界面] 颜色改为引用 TimelineStyle,要调请改那个文件。
		titleView.textColor = TimelineStyle.headlineColor
		summaryView.textColor = TimelineStyle.bodyColor
		dateView.textColor = TimelineStyle.timeColor
		feedNameView.textColor = TimelineStyle.feedLineColor
		updateReadAppearance()
	}

	/// [界面] 已读 / 未读的区分方式:**整行浓淡**(用户 2026-07-21 确认)。
	/// 浓 = 未读,淡 = 已读。原来的未读小蓝点已不再使用。
	func updateReadAppearance() {
		guard cellData != nil else {
			contentView.alpha = TimelineStyle.unreadAlpha
			return
		}
		contentView.alpha = cellData.read ? TimelineStyle.readAlpha : TimelineStyle.unreadAlpha
	}

	func updateIndicatorView() {
		// [界面] 这个控件现在只用来显示星标(在顶行时间旁边)。
		// 未读状态改由整行浓淡表示,不再画小圆点。
		guard cellData != nil, cellData.starred else {
			indicatorView.isHidden = true
			return
		}
		indicatorView.iconImage = Assets.Images.starredFeed
		indicatorView.tintColor = Assets.Colors.star
		indicatorView.isHidden = false
	}

	func updateAccessibilityLabel() {
		let starredStatus = cellData.starred ? "\(NSLocalizedString("Starred", comment: "Starred")), " : ""
		let unreadStatus = cellData.read ? "" : "\(NSLocalizedString("Unread", comment: "Unread")), "
		accessibilityLabel = starredStatus + unreadStatus + "\(cellData.feedName), \(cellData.title), \(cellData.summary), \(cellData.dateString)"
	}
}
