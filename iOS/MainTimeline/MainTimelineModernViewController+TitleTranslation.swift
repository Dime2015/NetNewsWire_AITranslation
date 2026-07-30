//
//  MainTimelineModernViewController+TitleTranslation.swift
//  NetNewsWire — AI 翻译 fork
//
//  [翻译] 本 fork 新增,上游没有这个文件。
//
//  标题翻译在时间线这头的唯一挂点:译文入库(或简介页里拨了开关)时刷新可见行。
//  刷新走上游自己的 `queueReloadAvailableCells()` —— 和 favicon/缩略图迟到后
//  重刷可见行是同一套机制,不另起炉灶。
//  (显示替换那半句在上游 configure(article:) 里,带 [翻译] 标记的一行。)
//

import UIKit

extension MainTimelineModernViewController {

	@objc func nnwTitleTranslationDidUpdate(_ note: Notification) {
		queueReloadAvailableCells()
	}
}
