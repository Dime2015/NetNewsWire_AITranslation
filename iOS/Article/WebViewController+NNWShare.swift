//
//  WebViewController+NNWShare.swift
//  NetNewsWire — AI 翻译 fork
//
//  [外观] 本 fork 新增,上游没有这个文件。
//
//  控件板上的「分享」键要弹系统分享单。上游现成的 showActivityDialog 只收
//  UIBarButtonItem 当 iPad 气泡锚点,而板上的键是普通视图 —— 所以照着上游那 4 行
//  镜像一个"视图锚点"版。内容(链接、标题、两个自定义活动)与上游完全一致。
//
//  ⚠️ 镜像自 WebViewController.showActivityDialog(popOverBarButtonItem:) ——
//  上游若改那边(比如加新的自定义活动),这里要跟着对一遍。
//

#if os(iOS)

import UIKit

extension WebViewController {

	/// 弹系统分享单,iPad 气泡锚在 sourceView 上(iPhone 上锚点没作用,但传了不碍事)。
	func nnwShowActivityDialog(sourceView: UIView) {
		guard let url = article?.preferredURL else { return }
		let activityViewController = UIActivityViewController(url: url, title: article?.title,
															  applicationActivities: [FindInArticleActivity(), OpenInBrowserActivity()])
		activityViewController.popoverPresentationController?.sourceView = sourceView
		activityViewController.popoverPresentationController?.sourceRect = sourceView.bounds
		present(activityViewController, animated: true)
	}
}

#endif
