//
//  WebViewProvider.swift
//  NetNewsWire-iOS
//
//  Created by Maurice Parker on 9/21/19.
//  Copyright © 2019 Ranchero Software. All rights reserved.
//

import Foundation
import RSCore
import WebKit

/// WKWebView has an awful behavior of a flash to white on first load when in dark mode.
/// Keep a queue of WebViews where we've already done a trivial load so that by the time we need them in the UI, they're past the flash-to-white part of their lifecycle.
struct WebViewProviderTeardownAudit: Equatable {
	let cancellationRequested: Bool
	let operationsCompleted: Bool
	let preloadedViewsDetached: Bool
}

@MainActor final class WebViewProvider: NSObject {
	private let articleIconSchemeHandler: ArticleIconSchemeHandler
	private let operationQueue = MainThreadOperationQueue()
	private var queue = NSMutableArray()
	private(set) var isTornDown = false
	private(set) var teardownAudit: WebViewProviderTeardownAudit?

	init(coordinator: SceneCoordinator) {
		appDelegate?.recordLegacyWebViewBootstrap(
			source: "WebViewProvider.init",
			detail: "legacy startup WebView/blank bootstrap boundary"
		)
		articleIconSchemeHandler = ArticleIconSchemeHandler(coordinator: coordinator)
		super.init()
		replenishQueueIfNeeded()
	}

	func replenishQueueIfNeeded() {
		guard !isTornDown else { return }
		operationQueue.add(WebViewProviderReplenishQueueOperation(queue: queue, articleIconSchemeHandler: articleIconSchemeHandler))
	}

	func dequeueWebView(completion: @escaping (PreloadedWebView) -> Void) {
		guard !isTornDown else { return }
		operationQueue.add(WebViewProviderDequeueOperation(queue: queue, articleIconSchemeHandler: articleIconSchemeHandler, completion: completion))
		operationQueue.add(WebViewProviderReplenishQueueOperation(queue: queue, articleIconSchemeHandler: articleIconSchemeHandler))
	}

	/// Stop scene-owned preloading work before the coordinator releases its
	/// controllers. MainThreadOperationQueue cancellation is explicit here;
	/// dropping the provider reference alone does not cancel a current operation.
	@discardableResult
	func tearDown() -> WebViewProviderTeardownAudit {
		if let teardownAudit {
			return teardownAudit
		}
		isTornDown = true
		let activeOperationsBeforeCancellation = operationQueue.activeOperationsCount
		operationQueue.cancelAll()
		let queuedWebViews = queue.compactMap { $0 as? PreloadedWebView }
		queuedWebViews.forEach { $0.tearDown() }
		queue.removeAllObjects()
		articleIconSchemeHandler.coordinator = nil
		let audit = WebViewProviderTeardownAudit(
			cancellationRequested: activeOperationsBeforeCancellation > 0,
			operationsCompleted: operationQueue.activeOperationsCount == 0,
			preloadedViewsDetached: queue.count == 0
		)
		teardownAudit = audit
		return audit
	}
}

final class WebViewProviderReplenishQueueOperation: MainThreadOperation, @unchecked Sendable {
	private let minimumQueueDepth = 3

	private var queue: NSMutableArray
	private var articleIconSchemeHandler: ArticleIconSchemeHandler

	init(queue: NSMutableArray, articleIconSchemeHandler: ArticleIconSchemeHandler) {
		self.queue = queue
		self.articleIconSchemeHandler = articleIconSchemeHandler
		super.init(name: "WebViewProviderReplenishQueueOperation")
	}

	override func run() {
		while queue.count < minimumQueueDepth && !isCanceled {
			let webView = PreloadedWebView(articleIconSchemeHandler: articleIconSchemeHandler)
			webView.preload()
			queue.insert(webView, at: 0)
		}
		didComplete()
	}
}

final class WebViewProviderDequeueOperation: MainThreadOperation, @unchecked Sendable {
	private var queue: NSMutableArray
	private var articleIconSchemeHandler: ArticleIconSchemeHandler
	private var completion: (PreloadedWebView) -> Void

	init(queue: NSMutableArray, articleIconSchemeHandler: ArticleIconSchemeHandler, completion: @escaping (PreloadedWebView) -> Void) {
		self.queue = queue
		self.articleIconSchemeHandler = articleIconSchemeHandler
		self.completion = completion
		super.init(name: "WebViewProviderFlushQueueOperation")
	}

	override func run() {
		guard !isCanceled else {
			didComplete()
			return
		}
		if let webView = queue.lastObject as? PreloadedWebView {
			self.completion(webView)
			self.queue.remove(webView)
			didComplete()
			return
		}

		assertionFailure("Creating PreloadedWebView in \(#function); queue has run dry.")

		let webView = PreloadedWebView(articleIconSchemeHandler: articleIconSchemeHandler)
		webView.preload()
		self.completion(webView)
		didComplete()
	}
}
