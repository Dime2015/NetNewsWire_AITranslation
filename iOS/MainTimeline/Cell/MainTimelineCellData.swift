//
//  MainTimelineCellData.swift
//  NetNewsWire
//
//  Created by Brent Simmons on 2/6/16.
//  Copyright © 2016 Ranchero Software, LLC. All rights reserved.
//

import UIKit
import Articles
import Images

@MainActor struct MainTimelineCellData {

	private static let noText = NSLocalizedString("(No Text)", comment: "No Text")

	let accountID: String
	let articleID: String
	let title: String
	let attributedTitle: NSAttributedString
	let summary: String
	let dateString: String
	let feedName: String
	let byline: String
	let showFeedName: ShowFeedName
	let iconImage: IconImage? // feed icon, user avatar, or favicon
	let showIcon: Bool // Make space even when icon is nil
	let read: Bool
	let starred: Bool
	let numberOfLines: Int
	let iconSize: IconSize
	/// [界面] 正文首图的缩略图位图。图还没下载好时为 nil ——
	/// **布局占不占位不看这个字段**,看下面的 `hasThumbnail`(2026-08-11 改)。
	let thumbnail: UIImage?
	/// [界面] 这篇文章有没有图,只看正文 HTML 里扫不扫得到图片地址,不看下没下载好。
	/// 布局(`MainTimelineCellLayout`)用这个字段决定要不要留出缩略图的位置 ——
	/// 图片下载完成前先用灰色占位块占住,避免下载完才让文字重新排版跳动。
	let hasThumbnail: Bool

	init(article: Article, showFeedName: ShowFeedName, feedName: String?, byline: String?, iconImage: IconImage?, showIcon: Bool, numberOfLines: Int, iconSize: IconSize, hasThumbnail: Bool = false, thumbnail: UIImage? = nil) {

		self.thumbnail = thumbnail // [界面]
		self.hasThumbnail = hasThumbnail // [界面]

		self.accountID = article.accountID
		self.articleID = article.articleID
		self.title = ArticleStringFormatter.shared.truncatedTitle(article)
		self.attributedTitle = ArticleStringFormatter.shared.attributedTruncatedTitle(article)

		let truncatedSummary = ArticleStringFormatter.shared.truncatedSummary(article)
		if self.title.isEmpty && truncatedSummary.isEmpty {
			self.summary = Self.noText
		} else {
			self.summary = truncatedSummary
		}

		self.dateString = ArticleStringFormatter.shared.dateString(article.logicalDatePublished)

		if let feedName = feedName {
			self.feedName = ArticleStringFormatter.shared.truncatedFeedName(feedName)
		} else {
			self.feedName = ""
		}

		if let byline = byline {
			self.byline = byline
		} else {
			self.byline = ""
		}

		self.showFeedName = showFeedName

		self.showIcon = showIcon
		self.iconImage = iconImage

		self.read = article.status.read
		self.starred = article.status.starred
		self.numberOfLines = numberOfLines
		self.iconSize = iconSize

	}

	init() { // Empty
		self.accountID = ""
		self.articleID = ""
		self.title = ""
		self.attributedTitle = NSAttributedString()
		self.summary = ""
		self.dateString = ""
		self.feedName = ""
		self.byline = ""
		self.showFeedName = .none
		self.showIcon = false
		self.iconImage = nil
		self.read = true
		self.starred = false
		self.numberOfLines = 0
		self.iconSize = .medium
		self.thumbnail = nil // [界面]
		self.hasThumbnail = false // [界面]
	}

}
