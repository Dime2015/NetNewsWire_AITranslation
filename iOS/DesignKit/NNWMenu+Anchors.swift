//
//  NNWMenu+Anchors.swift
//  NetNewsWire — AI 翻译 fork
//
//  [外观] 本 fork 新增。长按某一行时,自绘选单该从哪儿弹出来。
//
//  单独一个文件的原因:`NNWMenu+SystemBridge.swift` 是**通用**桥接
//  (只认 UIMenu,不认识这个 app 的任何页面);而"锚点在哪"必然要认识具体页面。
//  两件事分开放,通用的那份才能一直保持通用。
//

#if os(iOS)

import UIKit

extension UIViewController {

	/// 以某个列表行为锚点。行还在屏幕上就贴着它弹,否则退回屏幕正中。
	@MainActor
	func nnwMenuAnchor(in collectionView: UICollectionView?, at indexPath: IndexPath) -> NNWMenu.Anchor {
		guard let collectionView,
			  let cell = collectionView.cellForItem(at: indexPath) else { return .center }
		return .rect(cell.frame, within: collectionView)
	}

	/// 以某个点为锚点(正文页长按、账户分组头长按这类:没有"行",只有手指位置)。
	@MainActor
	func nnwMenuAnchor(atPoint point: CGPoint, in container: UIView?) -> NNWMenu.Anchor {
		guard let container else { return .center }
		return .rect(CGRect(origin: point, size: .zero), within: container)
	}
}

extension MainFeedCollectionViewController {

	/// 订阅列表页:长按某一行时的锚点。
	@MainActor
	func nnwMenuAnchor(for indexPath: IndexPath) -> NNWMenu.Anchor {
		nnwMenuAnchor(in: collectionView, at: indexPath)
	}
}

extension MainTimelineModernViewController {

	/// 文章列表页:长按某一行时的锚点。
	@MainActor
	func nnwMenuAnchor(for indexPath: IndexPath) -> NNWMenu.Anchor {
		nnwMenuAnchor(in: collectionView, at: indexPath)
	}
}

#endif
