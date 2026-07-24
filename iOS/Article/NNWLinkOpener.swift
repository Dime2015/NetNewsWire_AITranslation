//
//  NNWLinkOpener.swift
//  NetNewsWire — AI 翻译 fork
//
//  [链接] 打开外部链接的**唯一入口**。本 fork 新增,上游没有。
//
//  ## 为什么要有它(2026-07-24 用户要求「app 里点的链接一律不跳出去」)
//
//  上游其实早有「Open Links in NetNewsWire」开关(`useSystemBrowser`,默认就是 app 内打开),
//  但实际有**三类漏网**,即使开关开着也会把人甩出 app:
//
//  1. **万能链接**:正文里点 YouTube / Reddit 链接,上游会先问系统"有没有对应的 app",
//     有就直接跳进那个 app(`universalLinksOnly: true` 那句)。用户拍板:**一律 app 内网页**。
//  2. 上游三个 `showBrowserFor…`(长按菜单「打开主页」等):无条件 `UIApplication.open`,根本不看开关。
//  3. 本 fork 自己的阅读栏点击:当初照抄了上游,也直接跳。
//
//  现在三类全部走这里:开关关(默认)→ app 内 Safari 页;开 → 系统浏览器。
//  以后再加"点了要开网页"的功能,**都调这里,别再直接 UIApplication.open**。
//

#if os(iOS)

import UIKit
import SafariServices

@MainActor enum NNWLinkOpener {

	/// 打开一个链接。`presenter` = 从哪个页面往外弹(app 内模式要用它 present)。
	static func open(_ url: URL, from presenter: UIViewController?) {

		// 非网页链接(mailto、播客的 podcast:// 等)只能交给系统 —— app 内浏览器打不开它们
		guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
			UIApplication.shared.open(url, options: [:])
			return
		}

		// 用户开了「用系统浏览器」→ 尊重选择,照旧跳出去
		guard !AppDefaults.shared.useSystemBrowser else {
			UIApplication.shared.open(url, options: [:])
			return
		}

		// app 内:Safari 浏览器页。造不出来(极少数畸形 URL,见上游 #4857)就兜底跳系统。
		guard let presenter, let safari = SFSafariViewController.safeSafariViewController(url) else {
			UIApplication.shared.open(url, options: [:])
			return
		}

		// 从**最上层**弹出 —— presenter 自己可能正被别的弹层(分享单、设置)盖着,
		// 从被盖住的页面 present 会静默失败(不报错,就是不出来)。
		var top: UIViewController = presenter
		while let presented = top.presentedViewController { top = presented }
		top.present(safari, animated: true)
	}
}

#endif
