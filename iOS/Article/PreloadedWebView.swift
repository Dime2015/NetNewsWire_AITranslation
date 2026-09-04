//
//  PreloadedWebView.swift
//  NetNewsWire-iOS
//
//  Created by Maurice Parker on 2/25/20.
//  Copyright © 2020 Ranchero Software. All rights reserved.
//

import Foundation
import WebKit

private final class PreloadedWebViewObserverBox: @unchecked Sendable {
	let token: NSObjectProtocol

	init(token: NSObjectProtocol) {
		self.token = token
	}
}

final class PreloadedWebView: WKWebView {

	private var isReady: Bool = false
	private var readyCompletion: (() -> Void)?
	private var userDefaultsObserver: PreloadedWebViewObserverBox?
	private(set) var isTornDown = false

	init(articleIconSchemeHandler: ArticleIconSchemeHandler) {
		let configuration = WebViewConfiguration.configuration(with: articleIconSchemeHandler)
		super.init(frame: .zero, configuration: configuration)
		let observer = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
			MainActor.assumeIsolated {
				self?.userDefaultsDidChange()
			}
		}
		userDefaultsObserver = PreloadedWebViewObserverBox(token: observer)
	}

	required init?(coder: NSCoder) {
		super.init(coder: coder)

	}

	deinit {
		if let userDefaultsObserver {
			NotificationCenter.default.removeObserver(userDefaultsObserver.token)
		}
	}

	func preload() {
		guard !isTornDown else { return }
		// WebViewProvider owns the provider-construction count; this separate
		// bootstrap event records the concrete blank-page load without counting the
		// same startup boundary twice as a WebViewProvider creation.
		appDelegate?.recordLegacyBlankWebViewBootstrap(
			source: "PreloadedWebView.preload",
			detail: "legacy blank-page WebView bootstrap"
		)
		navigationDelegate = self
		loadFileURL(ArticleRenderer.blank.url, allowingReadAccessTo: ArticleRenderer.blank.baseURL)
	}

	func ready(completion: @escaping () -> Void) {
		guard !isTornDown else { return }
		if isReady {
			completeRequest(completion: completion)
		} else {
			readyCompletion = completion
		}
	}

	func userDefaultsDidChange() {
		guard !isTornDown else { return }
		if configuration.defaultWebpagePreferences.allowsContentJavaScript != AppDefaults.shared.isArticleContentJavascriptEnabled {
			configuration.defaultWebpagePreferences.allowsContentJavaScript = AppDefaults.shared.isArticleContentJavascriptEnabled
			reload()
		}
	}

	/// Stop the web view before its provider and icon scheme handler are
	/// released. The observer token is explicitly removed because a block
	/// observer is retained by NotificationCenter independently of this view.
	func tearDown() {
		guard !isTornDown else { return }
		isTornDown = true
		if let userDefaultsObserver {
			NotificationCenter.default.removeObserver(userDefaultsObserver.token)
			self.userDefaultsObserver = nil
		}
		readyCompletion = nil
		navigationDelegate = nil
		stopLoading()
	}
}

// MARK: WKScriptMessageHandler

extension PreloadedWebView: WKNavigationDelegate {

	func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
		guard !isTornDown else { return }
		isReady = true
		if let completion = readyCompletion {
			completeRequest(completion: completion)
			readyCompletion = nil
		}
	}
}

// MARK: Private

private extension PreloadedWebView {

	func completeRequest(completion: @escaping () -> Void) {
		isReady = false
		navigationDelegate = nil
		completion()
	}
}
