//
//  MainTimelineCellLayout.swift
//  NetNewsWire-iOS
//
//  Created by Maurice Parker on 4/29/19.
//  Copyright © 2019 Ranchero Software. All rights reserved.
//

import UIKit
import RSCore
import Images

@MainActor protocol MainTimelineCellLayout {
	var height: CGFloat { get }
	var unreadIndicatorRect: CGRect { get }
	var starRect: CGRect { get }
	var iconImageRect: CGRect { get }
	var titleRect: CGRect { get }
	var summaryRect: CGRect { get }
	var feedNameRect: CGRect { get }
	var dateRect: CGRect { get }
	var separatorRect: CGRect { get }
	var thumbnailRect: CGRect { get } // [界面] 右侧缩略图;没有图时为 .zero
}

extension MainTimelineCellLayout {

	static func rectForUnreadIndicator(_ point: CGPoint) -> CGRect {
		var r = CGRect.zero
		r.size = CGSize(width: MainTimelineDefaultCellLayout.unreadCircleDimension, height: MainTimelineDefaultCellLayout.unreadCircleDimension)
		r.origin.x = point.x
		r.origin.y = point.y + TimelineStyle.unreadCircleTopOffset // [界面]
		return r
	}

	static func rectForStar(_ point: CGPoint) -> CGRect {
		var r = CGRect.zero
		r.size.width = MainTimelineDefaultCellLayout.starDimension
		r.size.height = MainTimelineDefaultCellLayout.starDimension
		r.origin.x = floor(point.x - ((MainTimelineDefaultCellLayout.starDimension - MainTimelineDefaultCellLayout.unreadCircleDimension) / 2.0))
		r.origin.y = point.y + TimelineStyle.starTopOffset // [界面]
		return r
	}

	static func rectForIconView(_ point: CGPoint, iconSize: IconSize) -> CGRect {
		var r = CGRect.zero
		r.size = iconSize.size
		r.origin.x = point.x
		r.origin.y = point.y + TimelineStyle.iconTopOffset // [界面]
		return r
	}

	static func rectForTitle(_ cellData: MainTimelineCellData, _ point: CGPoint, _ textAreaWidth: CGFloat) -> (CGRect, Int) {
		var r = CGRect.zero
		if cellData.title.isEmpty {
			return (r, 0)
		}
		r.origin = point
		let sizeInfo = MultilineUILabelSizer.size(for: cellData.title, font: MainTimelineDefaultCellLayout.titleFont, numberOfLines: cellData.numberOfLines, width: Int(textAreaWidth))
		r.size.width = textAreaWidth
		r.size.height = sizeInfo.size.height
		if sizeInfo.numberOfLinesUsed < 1 {
			r.size.height = 0
		}
		return (r, sizeInfo.numberOfLinesUsed)
	}

	static func rectForSummary(_ cellData: MainTimelineCellData, _ point: CGPoint, _ textAreaWidth: CGFloat, _ linesUsed: Int) -> CGRect {
		let linesLeft = cellData.numberOfLines - linesUsed
		var r = CGRect.zero
		if cellData.summary.isEmpty || linesLeft < 1 {
			return r
		}
		r.origin = point
		let sizeInfo = MultilineUILabelSizer.size(for: cellData.summary, font: MainTimelineDefaultCellLayout.summaryFont, numberOfLines: linesLeft, width: Int(textAreaWidth))
		r.size.width = textAreaWidth
		r.size.height = sizeInfo.size.height
		if sizeInfo.numberOfLinesUsed < 1 {
			r.size.height = 0
		}
		return r
	}

	// MARK: - [界面] Reeder 式布局用的测量方法
	//
	// 新布局的一行:
	//   [favicon] [ 源名 …… 时间 ★ ]
	//             [ 标题(粗,≤3 行) ]
	//             [ 正文(补足共 4 行) ]
	//   最右边可能还有一张缩略图。

	/// 量标题:限制在 `maxTitleLines` 行内,同时告诉调用方实际用了几行
	/// (正文要靠这个数字决定自己能占几行)。
	static func nnwRectForHeadline(_ cellData: MainTimelineCellData, _ point: CGPoint, _ textAreaWidth: CGFloat) -> (CGRect, Int) {
		var r = CGRect.zero
		if cellData.title.isEmpty {
			return (r, 0)
		}
		r.origin = point
		let sizeInfo = MultilineUILabelSizer.size(for: cellData.title,
												  font: TimelineStyle.headlineFont,
												  numberOfLines: TimelineStyle.maxTitleLines,
												  width: Int(textAreaWidth))
		r.size.width = textAreaWidth
		r.size.height = sizeInfo.size.height
		if sizeInfo.numberOfLinesUsed < 1 {
			r.size.height = 0
			return (r, 0)
		}
		return (r, sizeInfo.numberOfLinesUsed)
	}

	/// 量正文:行数 = 总行数 − 标题实际用掉的行数,但至少留 1 行给正文。
	static func nnwRectForBody(_ cellData: MainTimelineCellData, _ point: CGPoint, _ textAreaWidth: CGFloat, headlineLinesUsed: Int) -> CGRect {
		var r = CGRect.zero
		if cellData.summary.isEmpty {
			return r
		}
		let linesForBody = max(TimelineStyle.minSummaryLines, TimelineStyle.totalTextLines - headlineLinesUsed)
		r.origin = point
		let sizeInfo = MultilineUILabelSizer.size(for: cellData.summary,
												  font: TimelineStyle.bodyFont,
												  numberOfLines: linesForBody,
												  width: Int(textAreaWidth))
		r.size.width = textAreaWidth
		r.size.height = sizeInfo.size.height
		if sizeInfo.numberOfLinesUsed < 1 {
			r.size.height = 0
		}
		return r
	}

	/// 量顶行:源名在左,时间在右,星标(如果有)紧挨在时间左边。
	/// 返回三个矩形 + 这一行的高度。
	static func nnwRectsForFeedLine(_ cellData: MainTimelineCellData, _ point: CGPoint, _ textAreaWidth: CGFloat) -> (feedName: CGRect, date: CGRect, star: CGRect, height: CGFloat) {

		let dateSize = SingleLineUILabelSizer.size(for: cellData.dateString, font: TimelineStyle.timeFont)
		let feedNameSize = SingleLineUILabelSizer.size(for: cellData.feedName, font: TimelineStyle.feedLineFont)
		let lineHeight = max(dateSize.height, feedNameSize.height)

		// 时间靠右贴齐文字区右边缘
		var dateRect = CGRect.zero
		dateRect.size = dateSize
		dateRect.origin.x = (point.x + textAreaWidth) - dateSize.width
		dateRect.origin.y = point.y + ((lineHeight - dateSize.height) / 2.0)

		// 星标紧挨在时间左边
		var starRect = CGRect.zero
		if cellData.starred {
			starRect.size = CGSize(width: TimelineStyle.starDimensionInFeedLine, height: TimelineStyle.starDimensionInFeedLine)
			starRect.origin.x = dateRect.minX - TimelineStyle.starMarginLeft - starRect.width
			starRect.origin.y = point.y + ((lineHeight - starRect.height) / 2.0)
		}

		// 源名占掉剩下的宽度
		let occupiedOnRight = (textAreaWidth - ((cellData.starred ? starRect.minX : dateRect.minX) - point.x))
		var feedNameRect = CGRect.zero
		feedNameRect.origin.x = point.x
		feedNameRect.origin.y = point.y + ((lineHeight - feedNameSize.height) / 2.0)
		feedNameRect.size.height = feedNameSize.height
		feedNameRect.size.width = max(0, min(feedNameSize.width, textAreaWidth - occupiedOnRight - TimelineStyle.timeMarginLeft))

		return (feedNameRect, dateRect, starRect, lineHeight)
	}

	static func rectForFeedName(_ cellData: MainTimelineCellData, _ point: CGPoint, _ textAreaWidth: CGFloat) -> CGRect {
		var r = CGRect.zero
		r.origin = point
		let feedName = cellData.showFeedName == .feed ? cellData.feedName : cellData.byline
		let size = SingleLineUILabelSizer.size(for: feedName, font: MainTimelineDefaultCellLayout.feedNameFont)
		r.size = size
		if r.size.width > textAreaWidth {
			r.size.width = textAreaWidth
		}
		return r
	}
}

// MARK: - Default

struct MainTimelineDefaultCellLayout: MainTimelineCellLayout {

	// [界面] 以下常量的值全部改为引用 TimelineStyle,要调外观请改那个文件,不要改这里。
	static let cellPadding = TimelineStyle.cellPadding

	static let unreadCircleMarginLeft = TimelineStyle.unreadCircleMarginLeft
	static let unreadCircleDimension = TimelineStyle.unreadCircleDimension
	static let unreadCircleMarginRight = TimelineStyle.unreadCircleMarginRight

	static let starDimension = TimelineStyle.starDimension

	static let iconMarginRight = TimelineStyle.iconMarginRight
	static let iconCornerRadius = CGFloat(4)

	static var titleFont: UIFont { TimelineStyle.titleFont }
	static let titleBottomMargin = TimelineStyle.titleBottomMargin

	static var feedNameFont: UIFont { TimelineStyle.feedNameFont }
	static let feedRightMargin = TimelineStyle.feedRightMargin

	static var dateFont: UIFont { TimelineStyle.dateFont }
	static let dateMarginBottom = CGFloat(1)

	static var summaryFont: UIFont { TimelineStyle.summaryFont }

	let height: CGFloat
	let unreadIndicatorRect: CGRect
	let starRect: CGRect
	let iconImageRect: CGRect
	let titleRect: CGRect
	let summaryRect: CGRect
	let feedNameRect: CGRect
	let dateRect: CGRect
	let separatorRect: CGRect
	let thumbnailRect: CGRect

	// [界面] 2026-07-21 整个 init 改成 Reeder 式布局:
	//
	//   [favicon] [ 源名 ……………… 时间 ★ ]  [缩略图]
	//             [ 标题(粗,≤3 行)     ]
	//             [ 正文(补足到共 4 行) ]
	//
	// 与上游原版的区别:①favicon 移到最左(原来最左是未读圆点);
	// ②源名和时间从底部移到顶行;③新增右侧缩略图;④未读圆点不再使用
	// (改为整行浓淡,见 MainTimelineCell.updateColors)。
	// 所有数值都在 TimelineStyle.swift 里,不要在这里写死数字。
	init(width: CGFloat, insets: UIEdgeInsets, cellData: MainTimelineCellData) {

		// 未读圆点已弃用:改用整行浓淡表示已读/未读。
		self.unreadIndicatorRect = CGRect.zero

		var currentPoint = CGPoint.zero
		currentPoint.x = Self.cellPadding.left + insets.left
		currentPoint.y = Self.cellPadding.top

		// ① 最左边:favicon。
		// **这一列永远占位**,哪怕这个源没有 favicon —— 否则有图标的行和没图标的行
		// 文字起点不一样,混合列表(全部未读)里会参差不齐。
		// 没有图时 MainTimelineCell 会把 iconView 藏起来,位置照样留着。
		self.iconImageRect = CGRect(x: currentPoint.x,
									y: currentPoint.y + TimelineStyle.faviconTopOffset,
									width: TimelineStyle.faviconDimension,
									height: TimelineStyle.faviconDimension)
		currentPoint.x = self.iconImageRect.maxX + TimelineStyle.faviconMarginRight

		// ③ 最右边:缩略图。**没有图时宽度按 0 算,文字自然铺满到最右边。**
		let rightEdge = width - (Self.cellPadding.right + insets.right)
		let thumbnailBlockWidth: CGFloat
		if cellData.thumbnail != nil {
			thumbnailBlockWidth = TimelineStyle.thumbnailDimension + TimelineStyle.thumbnailMarginLeft
			self.thumbnailRect = CGRect(x: rightEdge - TimelineStyle.thumbnailDimension,
										y: currentPoint.y,
										width: TimelineStyle.thumbnailDimension,
										height: TimelineStyle.thumbnailDimension)
		} else {
			thumbnailBlockWidth = 0
			self.thumbnailRect = CGRect.zero
		}

		let textAreaWidth = max(0, rightEdge - currentPoint.x - thumbnailBlockWidth)
		self.separatorRect = CGRect(x: currentPoint.x, y: 0, width: rightEdge - currentPoint.x, height: 0)

		// ② 顶行:源名 + 时间 + 星标
		let feedLine = Self.nnwRectsForFeedLine(cellData, currentPoint, textAreaWidth)
		self.feedNameRect = feedLine.feedName
		self.dateRect = feedLine.date
		self.starRect = feedLine.star
		currentPoint.y += feedLine.height + TimelineStyle.feedLineBottomMargin

		// 标题(最多 3 行)
		let (headlineRect, headlineLinesUsed) = Self.nnwRectForHeadline(cellData, currentPoint, textAreaWidth)
		self.titleRect = headlineRect
		if headlineRect.height > 0 {
			currentPoint.y = headlineRect.maxY + TimelineStyle.headlineBottomMargin
		}

		// 正文(补足到总共 4 行,至少 1 行)
		self.summaryRect = Self.nnwRectForBody(cellData, currentPoint, textAreaWidth, headlineLinesUsed: headlineLinesUsed)

		// 整行高度取「文字块」「favicon」「缩略图」里最靠下的那个
		let contentBottom = [self.titleRect, self.summaryRect, self.dateRect, self.feedNameRect,
							 self.iconImageRect, self.thumbnailRect].maxY()
		self.height = contentBottom + Self.cellPadding.bottom
	}

	static func rectForDate(_ cellData: MainTimelineCellData, _ point: CGPoint, _ textAreaWidth: CGFloat) -> CGRect {
		var r = CGRect.zero
		let size = SingleLineUILabelSizer.size(for: cellData.dateString, font: Self.dateFont)
		r.size = size
		r.origin.x = (point.x + textAreaWidth) - size.width
		r.origin.y = point.y
		return r
	}
}

// MARK: - Accessibility

struct MainTimelineAccessibilityCellLayout: MainTimelineCellLayout {

	let height: CGFloat
	let unreadIndicatorRect: CGRect
	let starRect: CGRect
	let iconImageRect: CGRect
	let titleRect: CGRect
	let summaryRect: CGRect
	let feedNameRect: CGRect
	let dateRect: CGRect
	let separatorRect: CGRect
	let thumbnailRect: CGRect

	// [界面] 2026-07-21 与默认布局同步改成 Reeder 式,但**竖着堆**:
	//
	//   [favicon]
	//   源名
	//   标题
	//   正文
	//   时间 ★
	//
	// 为什么不横排:系统字号开到「辅助功能」档位时字非常大,
	// 横着放源名+时间会挤成一团;缩略图同理,在这个档位下直接不显示,
	// 把整个宽度让给文字(这一点记在 NOTES-todo T7)。
	init(width: CGFloat, insets: UIEdgeInsets, cellData: MainTimelineCellData) {

		// 未读圆点已弃用:改用整行浓淡表示已读/未读。
		self.unreadIndicatorRect = CGRect.zero
		// 大字号下不显示缩略图,文字铺满整宽。
		self.thumbnailRect = CGRect.zero

		var currentPoint = CGPoint.zero
		currentPoint.x = MainTimelineDefaultCellLayout.cellPadding.left + insets.left
		currentPoint.y = MainTimelineDefaultCellLayout.cellPadding.top

		// favicon 同样永远占位(理由同默认布局)
		self.iconImageRect = CGRect(x: currentPoint.x,
									y: currentPoint.y,
									width: TimelineStyle.faviconDimension,
									height: TimelineStyle.faviconDimension)
		currentPoint.y = self.iconImageRect.maxY + TimelineStyle.feedLineBottomMargin

		let textAreaWidth = width - (currentPoint.x + MainTimelineDefaultCellLayout.cellPadding.right + insets.right)
		self.separatorRect = CGRect(x: currentPoint.x, y: 0, width: textAreaWidth, height: 0)

		// 源名单独一行
		let feedNameSize = SingleLineUILabelSizer.size(for: cellData.feedName, font: TimelineStyle.feedLineFont)
		self.feedNameRect = CGRect(x: currentPoint.x, y: currentPoint.y,
								   width: min(feedNameSize.width, textAreaWidth), height: feedNameSize.height)
		currentPoint.y = self.feedNameRect.maxY + TimelineStyle.feedLineBottomMargin

		// 标题
		let (headlineRect, headlineLinesUsed) = Self.nnwRectForHeadline(cellData, currentPoint, textAreaWidth)
		self.titleRect = headlineRect
		if headlineRect.height > 0 {
			currentPoint.y = headlineRect.maxY + TimelineStyle.headlineBottomMargin
		}

		// 正文
		self.summaryRect = Self.nnwRectForBody(cellData, currentPoint, textAreaWidth, headlineLinesUsed: headlineLinesUsed)
		if self.summaryRect.height > 0 {
			currentPoint.y = self.summaryRect.maxY + TimelineStyle.headlineBottomMargin
		}

		// 时间单独一行,星标跟在右边
		let dateSize = SingleLineUILabelSizer.size(for: cellData.dateString, font: TimelineStyle.timeFont)
		self.dateRect = CGRect(x: currentPoint.x, y: currentPoint.y, width: dateSize.width, height: dateSize.height)

		if cellData.starred {
			let side = TimelineStyle.starDimensionInFeedLine
			self.starRect = CGRect(x: self.dateRect.maxX + TimelineStyle.starMarginLeft,
								   y: currentPoint.y + ((dateSize.height - side) / 2.0),
								   width: side, height: side)
		} else {
			self.starRect = CGRect.zero
		}

		self.height = [self.dateRect, self.starRect].maxY() + MainTimelineDefaultCellLayout.cellPadding.bottom
	}

	static func rectForDate(_ cellData: MainTimelineCellData, _ point: CGPoint, _ textAreaWidth: CGFloat) -> CGRect {
		var r = CGRect.zero
		let size = SingleLineUILabelSizer.size(for: cellData.dateString, font: MainTimelineDefaultCellLayout.dateFont)
		r.size = size
		r.origin = point
		return r
	}
}
