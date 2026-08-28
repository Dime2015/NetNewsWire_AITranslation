//
//  BabelReaderViewController.swift
//  NetNewsWire
//

import UIKit
import WebKit
import Articles

final class BabelReaderViewController: UIViewController {

	private let article: Article
	private let webView = WKWebView(frame: .zero)
	private let progressView = UIProgressView(progressViewStyle: .bar)
	private var progressObservation: NSKeyValueObservation?

	init(article: Article) {
		self.article = article
		super.init(nibName: nil, bundle: nil)
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		configureView()
		renderArticle()
	}

	private func configureView() {
		view.backgroundColor = BabelPalette.background
		title = article.feed?.nameForDisplay
		navigationItem.largeTitleDisplayMode = .never

		if article.preferredURL != nil {
			navigationItem.rightBarButtonItem = UIBarButtonItem(
				image: UIImage(systemName: "safari"),
				style: .plain,
				target: self,
				action: #selector(openOriginal)
			)
		}

		webView.isOpaque = false
		webView.backgroundColor = .clear
		webView.scrollView.backgroundColor = BabelPalette.background
		webView.allowsBackForwardNavigationGestures = false
		view.addSubview(webView)
		webView.babelPinToEdges(of: view)

		progressView.tintColor = BabelPalette.accent
		progressView.trackTintColor = .clear
		progressView.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(progressView)
		NSLayoutConstraint.activate([
			progressView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			progressView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			progressView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor)
		])

		progressObservation = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] webView, _ in
			Task { @MainActor in
				self?.progressView.setProgress(Float(webView.estimatedProgress), animated: true)
				self?.progressView.isHidden = webView.estimatedProgress >= 1
			}
		}
	}

	private func renderArticle() {
		let displayArticle = NNWTitleTranslationController.shared.cachedDisplayArticle(for: article)
		let rendering = ArticleRenderer.articleHTML(
			article: displayArticle,
			theme: ArticleThemesManager.shared.currentTheme
		)
		let html = """
		<!doctype html>
		<html>
		<head>
			<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
			<meta name="color-scheme" content="light dark">
			<style>
			\(rendering.style)
			:root { color-scheme: light dark; }
			html { background: transparent !important; }
			body {
				background: transparent !important;
				color: #1a1916;
				font-family: ui-serif, Georgia, serif;
				font-size: 19px;
				line-height: 1.68;
				margin: 0 auto;
				max-width: 680px;
				padding: 34px 25px 80px;
			}
			.headerContainer { margin-bottom: 30px; }
			.headerTable { width: 100%; }
			.header, .articleDateline, .articleDatelineTitle, .externalLink {
				color: #6a665e !important;
				font-family: -apple-system, BlinkMacSystemFont, sans-serif;
				font-size: 12px !important;
			}
			.articleTitle h1 {
				font-family: ui-serif, Georgia, serif !important;
				font-size: 36px !important;
				font-weight: 650 !important;
				line-height: 1.08 !important;
				letter-spacing: -0.02em;
				margin: 12px 0 14px !important;
			}
			a { color: inherit !important; text-decoration-color: #c14a28 !important; }
			.articleBody { margin-top: 34px !important; }
			.articleBody p { margin: 0 0 1.25em; }
			.articleBody img, .articleBody video { border-radius: 10px; height: auto; max-width: 100%; }
			blockquote {
				border-left: 2px solid #c14a28;
				color: #5d594f;
				margin-left: 0;
				padding-left: 20px;
			}
			@media (prefers-color-scheme: dark) {
				body { color: #efede5; }
				.header, .articleDateline, .articleDatelineTitle, .externalLink { color: #9c988e !important; }
				blockquote { color: #b5b0a5; }
			}
			</style>
		</head>
		<body>
			\(rendering.html)
		</body>
		</html>
		"""
		let baseURL = URL(string: rendering.baseURL)
		webView.loadHTMLString(html, baseURL: baseURL)
	}

	@objc private func openOriginal() {
		guard let url = article.preferredURL else { return }
		UIApplication.shared.open(url)
	}
}
