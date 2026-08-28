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
	private let bottomToolbar = UIStackView()
	private var readerMode = false
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

	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)
		if !article.status.read { updateStatus(.read, flag: true) }
	}

	private func configureView() {
		view.backgroundColor = BabelPalette.background
		title = article.feed?.nameForDisplay
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "chevron.left"), style: .plain,
            target: self, action: #selector(closeReader)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "ellipsis"), style: .plain,
            target: self, action: #selector(showActions)
        )

		webView.isOpaque = false
		webView.backgroundColor = .clear
		webView.scrollView.backgroundColor = BabelPalette.background
		webView.allowsBackForwardNavigationGestures = false
        view.addSubview(webView)
        webView.translatesAutoresizingMaskIntoConstraints = false

		progressView.tintColor = BabelPalette.accent
		progressView.trackTintColor = .clear
		progressView.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(progressView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomToolbar.topAnchor),
            progressView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			progressView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			progressView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor)
        ])

        bottomToolbar.axis = .horizontal
        bottomToolbar.distribution = .equalCentering
        bottomToolbar.alignment = .center
        bottomToolbar.layoutMargins = UIEdgeInsets(top: 6, left: 20, bottom: 8, right: 20)
        bottomToolbar.isLayoutMarginsRelativeArrangement = true
        bottomToolbar.backgroundColor = BabelPalette.background
        bottomToolbar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bottomToolbar)
        for (index, item) in [("circle", "已读"), ("star", "星标"), ("chevron.down", "下一篇"),
                                ("text.alignleft", "阅读模式"), ("character.book.closed", "翻译")].enumerated() {
            var config = UIButton.Configuration.plain()
            config.image = UIImage(systemName: item.0)
            config.baseForegroundColor = BabelPalette.mutedInk
            let button = UIButton(configuration: config)
            button.accessibilityLabel = item.1
            button.configuration?.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12)
            if index == 0 { button.addTarget(self, action: #selector(toggleRead), for: .touchUpInside) }
            if index == 1 { button.addTarget(self, action: #selector(toggleStar), for: .touchUpInside) }
            if index == 2 { button.addTarget(self, action: #selector(showNextArticle), for: .touchUpInside) }
            if index == 3 { button.addTarget(self, action: #selector(toggleReaderMode), for: .touchUpInside) }
            bottomToolbar.addArrangedSubview(button)
        }
        NSLayoutConstraint.activate([
            bottomToolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomToolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomToolbar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            bottomToolbar.heightAnchor.constraint(equalToConstant: 58)
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
				font-family: -apple-system, BlinkMacSystemFont, sans-serif;
				font-size: \(readerMode ? 19 : 17)px;
				line-height: \(readerMode ? 1.72 : 1.55);
				margin: 0 auto;
				max-width: \(readerMode ? 560 : 680)px;
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
				font-family: -apple-system, BlinkMacSystemFont, sans-serif !important;
				font-size: 28px !important;
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

    @objc private func closeReader() {
        navigationController?.popViewController(animated: true)
    }

    @objc private func showActions() {
        let alert = UIAlertController(title: "文章操作", message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: article.status.read ? "标记未读" : "标记已读", style: .default) { [weak self] _ in
			self?.updateStatus(.read, flag: !(self?.article.status.read ?? false))
		})
		if article.preferredURL != nil {
			alert.addAction(UIAlertAction(title: "在浏览器中打开", style: .default) { [weak self] _ in self?.openOriginal() })
		}
        alert.addAction(UIAlertAction(title: "分享", style: .default) { [weak self] _ in
			guard let self else { return }
			let items: [Any] = [BabelLibrary.displayTitle(for: article), article.preferredURL as Any].compactMap { $0 }
			let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
			self.present(controller, animated: true)
		})
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(alert, animated: true)
    }

	private func updateStatus(_ key: ArticleStatus.Key, flag: Bool) {
		guard let account = article.account else { return }
		Task { try? await account.markArticles(articleIDs: [article.articleID], statusKey: key, flag: flag) }
	}

	@objc private func toggleRead() { updateStatus(.read, flag: !article.status.read) }
	@objc private func toggleStar() { updateStatus(.starred, flag: !article.status.starred) }
    @objc private func showNextArticle() { navigationController?.popViewController(animated: true) }

	@objc private func toggleReaderMode() {
		readerMode.toggle()
		renderArticle()
	}
}
