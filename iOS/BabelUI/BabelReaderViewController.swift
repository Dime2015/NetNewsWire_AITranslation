//
//  BabelReaderViewController.swift
//  NetNewsWire
//

import UIKit
import WebKit
import Articles

final class BabelReaderViewController: UIViewController, UIScrollViewDelegate {

	private let article: Article
	var nextArticle: (() -> Article?)?
    private let webView = WKWebView(frame: .zero)
    private let progressView = UIProgressView(progressViewStyle: .bar)
	private let bottomToolbar = UIStackView()
	private let readerHeader = UIView()
	private weak var readButton: UIButton?
	private weak var starButton: UIButton?
	private var readerMode = false
	private var didApplyDebugReaderMode = false
	private var pendingScrollOffset: CGPoint?
	private var lastScrollOffsetY: CGFloat = 0
	private var hasEstablishedScrollBaseline = false
	private var webViewToolbarBottomConstraint: NSLayoutConstraint!
	private var webViewFullBottomConstraint: NSLayoutConstraint!
	private var webViewHeaderTopConstraint: NSLayoutConstraint!
	private var webViewFullTopConstraint: NSLayoutConstraint!
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
		NotificationCenter.default.addObserver(self, selector: #selector(translationDidUpdate), name: .nnwTitleTranslationDidUpdate, object: nil)
	}

	deinit { NotificationCenter.default.removeObserver(self) }

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		navigationController?.setNavigationBarHidden(true, animated: animated)
	}

	override func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)
		navigationController?.setNavigationBarHidden(false, animated: animated)
	}

	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)
		if !article.status.read { updateStatus(.read, flag: true) }
		if !didApplyDebugReaderMode && ProcessInfo.processInfo.arguments.contains("-BabelReaderBR") {
			didApplyDebugReaderMode = true
			toggleReaderMode()
		}
	}

	private func configureView() {
		view.backgroundColor = BabelPalette.background
		title = article.feed?.nameForDisplay
        navigationItem.largeTitleDisplayMode = .never
		configureReaderHeader()
		bottomToolbar.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(bottomToolbar)

		webView.isOpaque = false
		webView.backgroundColor = .clear
		webView.scrollView.backgroundColor = BabelPalette.background
		webView.allowsBackForwardNavigationGestures = false
		webView.scrollView.delegate = self
		let chromeTap = UITapGestureRecognizer(target: self, action: #selector(toggleChrome))
		chromeTap.cancelsTouchesInView = false
		webView.addGestureRecognizer(chromeTap)
        view.addSubview(webView)
        webView.translatesAutoresizingMaskIntoConstraints = false

		progressView.tintColor = BabelPalette.accent
		progressView.trackTintColor = .clear
		progressView.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(progressView)
		webViewHeaderTopConstraint = webView.topAnchor.constraint(equalTo: readerHeader.bottomAnchor)
		webViewFullTopConstraint = webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor)
		webViewToolbarBottomConstraint = webView.bottomAnchor.constraint(equalTo: bottomToolbar.topAnchor)
		webViewFullBottomConstraint = webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
		NSLayoutConstraint.activate([
			webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			webViewHeaderTopConstraint,
			webViewToolbarBottomConstraint,
            progressView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			progressView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			progressView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor)
		])

        bottomToolbar.axis = .horizontal
		bottomToolbar.distribution = .equalSpacing
        bottomToolbar.alignment = .center
		bottomToolbar.layoutMargins = UIEdgeInsets(top: 6, left: 24, bottom: 8, right: 24)
        bottomToolbar.isLayoutMarginsRelativeArrangement = true
        bottomToolbar.backgroundColor = BabelPalette.background
		for (index, item) in [("circle", "已读", CGFloat(12)), ("star", "星标", CGFloat(15)), ("chevron.down", "下一篇", CGFloat(16)),
								("text.alignleft", "翻译", CGFloat(16)), ("character.book.closed", "Bionic Reading", CGFloat(16))].enumerated() {
			let button = UIButton(type: .custom)
			let symbol = UIImage.SymbolConfiguration(pointSize: item.2, weight: .regular)
			if index == 4 {
				button.setTitle("BR", for: .normal)
				button.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .bold)
				button.setTitleColor(BabelPalette.ink, for: .normal)
			} else {
				button.setImage(UIImage(systemName: item.0, withConfiguration: symbol), for: .normal)
			}
			button.tintColor = BabelPalette.ink
			button.accessibilityLabel = item.1
			button.translatesAutoresizingMaskIntoConstraints = false
			button.widthAnchor.constraint(equalToConstant: 44).isActive = true
			button.heightAnchor.constraint(equalToConstant: 36).isActive = true
            if index == 0 { button.addTarget(self, action: #selector(toggleRead), for: .touchUpInside) }
            if index == 1 { button.addTarget(self, action: #selector(toggleStar), for: .touchUpInside) }
            if index == 2 { button.addTarget(self, action: #selector(showNextArticle), for: .touchUpInside) }
			if index == 3 { button.addTarget(self, action: #selector(requestTranslation), for: .touchUpInside) }
			if index == 4 { button.addTarget(self, action: #selector(toggleReaderMode), for: .touchUpInside) }
			if index == 0 { readButton = button }
			if index == 1 { starButton = button }
			bottomToolbar.addArrangedSubview(button)
		}
		updateToolbarState()
        NSLayoutConstraint.activate([
            bottomToolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomToolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            // Reeder's reader toolbar extends through the home-indicator inset;
            // anchoring to the view bottom keeps its icons at the reference
            // baseline instead of lifting them by the safe-area height.
            bottomToolbar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            bottomToolbar.heightAnchor.constraint(equalToConstant: 58)
        ])

		progressObservation = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] webView, _ in
			Task { @MainActor in
				self?.progressView.setProgress(Float(webView.estimatedProgress), animated: true)
				self?.progressView.isHidden = webView.estimatedProgress >= 1
			}
		}
	}

	@objc private func toggleChrome() {
		let hidden = readerHeader.alpha > 0.5
		setChromeHidden(!hidden, animated: true)
	}

	private func setChromeHidden(_ hidden: Bool, animated: Bool) {
		let changes = {
			self.readerHeader.alpha = hidden ? 0 : 1
			self.bottomToolbar.alpha = hidden ? 0 : 1
			self.progressView.alpha = hidden ? 0 : 1
			self.webViewHeaderTopConstraint.isActive = !hidden
			self.webViewFullTopConstraint.isActive = hidden
			self.webViewToolbarBottomConstraint.isActive = !hidden
			self.webViewFullBottomConstraint.isActive = hidden
			self.view.layoutIfNeeded()
		}
		if animated {
			UIView.animate(withDuration: 0.2, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction], animations: changes)
		} else {
			changes()
		}
	}

	func scrollViewDidScroll(_ scrollView: UIScrollView) {
		let offsetY = scrollView.contentOffset.y
		guard hasEstablishedScrollBaseline else {
			lastScrollOffsetY = offsetY
			hasEstablishedScrollBaseline = true
			return
		}
		let delta = offsetY - lastScrollOffsetY
		lastScrollOffsetY = offsetY
		guard abs(delta) > 1 else { return }
		if delta > 0, offsetY > -scrollView.adjustedContentInset.top + 12 {
			setChromeHidden(true, animated: true)
		} else if delta < 0 {
			setChromeHidden(false, animated: true)
		}
	}

	private func configureReaderHeader() {
		readerHeader.translatesAutoresizingMaskIntoConstraints = false
		readerHeader.backgroundColor = BabelPalette.background
		view.addSubview(readerHeader)
		let back = UIButton(type: .custom)
		back.setImage(UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)), for: .normal)
		back.tintColor = BabelPalette.ink
		back.addTarget(self, action: #selector(closeReader), for: .touchUpInside)
		back.translatesAutoresizingMaskIntoConstraints = false
		readerHeader.addSubview(back)
		let label = UILabel()
		label.text = nil
		label.font = .systemFont(ofSize: 18, weight: .semibold)
		label.textColor = BabelPalette.ink
		label.translatesAutoresizingMaskIntoConstraints = false
		readerHeader.addSubview(label)
		let actions = UIButton(type: .custom)
		actions.setImage(UIImage(systemName: "ellipsis", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)), for: .normal)
		actions.tintColor = BabelPalette.ink
		actions.addTarget(self, action: #selector(showActions), for: .touchUpInside)
		actions.translatesAutoresizingMaskIntoConstraints = false
		readerHeader.addSubview(actions)
		let tag = UIButton(type: .custom)
		tag.setImage(UIImage(systemName: "tag", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)), for: .normal)
		tag.tintColor = BabelPalette.ink
		tag.addTarget(self, action: #selector(showActions), for: .touchUpInside)
		tag.translatesAutoresizingMaskIntoConstraints = false
		readerHeader.addSubview(tag)
		let share = UIButton(type: .custom)
		share.setImage(UIImage(systemName: "square.and.arrow.up", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)), for: .normal)
		share.tintColor = BabelPalette.ink
		share.addTarget(self, action: #selector(shareArticle), for: .touchUpInside)
		share.translatesAutoresizingMaskIntoConstraints = false
		readerHeader.addSubview(share)
		NSLayoutConstraint.activate([
			readerHeader.leadingAnchor.constraint(equalTo: view.leadingAnchor), readerHeader.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			readerHeader.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor), readerHeader.heightAnchor.constraint(equalToConstant: 58),
			back.leadingAnchor.constraint(equalTo: readerHeader.leadingAnchor), back.centerYAnchor.constraint(equalTo: readerHeader.topAnchor, constant: 24),
			back.widthAnchor.constraint(equalToConstant: 44), back.heightAnchor.constraint(equalToConstant: 44),
			label.centerXAnchor.constraint(equalTo: readerHeader.centerXAnchor), label.centerYAnchor.constraint(equalTo: readerHeader.centerYAnchor),
			actions.centerXAnchor.constraint(equalTo: readerHeader.centerXAnchor), actions.centerYAnchor.constraint(equalTo: readerHeader.topAnchor, constant: 24),
			actions.widthAnchor.constraint(equalToConstant: 44), actions.heightAnchor.constraint(equalToConstant: 44),
			tag.trailingAnchor.constraint(equalTo: share.leadingAnchor, constant: -31), tag.centerYAnchor.constraint(equalTo: readerHeader.topAnchor, constant: 24),
			tag.widthAnchor.constraint(equalToConstant: 44), tag.heightAnchor.constraint(equalToConstant: 44),
			share.trailingAnchor.constraint(equalTo: readerHeader.trailingAnchor, constant: -16), share.centerYAnchor.constraint(equalTo: readerHeader.topAnchor, constant: 24),
			share.widthAnchor.constraint(equalToConstant: 44), share.heightAnchor.constraint(equalToConstant: 44)
		])
	}

	@objc private func shareArticle() {
		var items: [Any] = [BabelLibrary.displayTitle(for: article)]
		if let url = article.preferredURL { items.append(url) }
		present(UIActivityViewController(activityItems: items, applicationActivities: nil), animated: true)
	}

	private func renderArticle() {
		let displayArticle = NNWTitleTranslationController.shared.cachedDisplayArticle(for: article)
		let rendering = ArticleRenderer.articleHTML(
			article: displayArticle,
			theme: ArticleThemesManager.shared.currentTheme
		)
		let fallbackTitle = BabelLibrary.displayTitle(for: article)
			.replacingOccurrences(of: "\\", with: "\\\\")
			.replacingOccurrences(of: "&", with: "&amp;")
			.replacingOccurrences(of: "<", with: "&lt;")
			.replacingOccurrences(of: ">", with: "&gt;")
			.replacingOccurrences(of: "'", with: "\\'")
		let readerDateFormatter = DateFormatter()
		readerDateFormatter.locale = Locale(identifier: "en_US_POSIX")
		readerDateFormatter.dateFormat = "EEEE, MMMM d, yyyy 'AT' H:mm"
		let readerDate = readerDateFormatter.string(from: article.logicalDatePublished).uppercased()
		var renderedHTML = rendering.html
		let needsFallbackTitle = article.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
		if needsFallbackTitle, let articleTag = renderedHTML.range(of: "<article"),
		   let articleEnd = renderedHTML.range(of: ">", range: articleTag.upperBound..<renderedHTML.endIndex) {
			let titleHTML = "<div class=\"articleTitle\"><h1>\(fallbackTitle)</h1></div>"
			renderedHTML.insert(contentsOf: titleHTML, at: renderedHTML.index(after: articleEnd.lowerBound))
		}
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
				color: #423f40;
				font-family: -apple-system, BlinkMacSystemFont, sans-serif;
				font-size: \(readerMode ? 19 : 17)px;
				font-weight: \(readerMode ? 500 : 400);
				line-height: \(readerMode ? 1.72 : 1.55);
				margin: 0 auto;
				max-width: \(readerMode ? 560 : 680)px;
				padding: 90px 20px 80px;
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
				text-align: left !important;
			}
			.articleTitle { text-align: left !important; }
			/* Reeder's reading hierarchy is date, title, then source/byline. */
			article { display: flex; flex-direction: column; }
			.articleDateline, .articleDatelineTitle { order: 1; }
			.articleTitle { order: 2; }
			.headerContainer { order: 3; margin: 0 0 34px !important; border: 0 !important; border-bottom: 0 !important; }
			body .headerTable { border-bottom: 0 !important; }
			.externalLink { order: 4; }
			/* Reeder keeps the raw URL out of the article header; it remains
			   available through the actions menu and the share control. */
			.externalLink { display: none !important; }
			.articleBody { order: 5; }
			.headerContainer .avatar { display: none !important; }
			.headerContainer .headerTable { width: 100%; }
			.headerContainer .leftAlign { text-align: left; }
			.headerContainer, .headerContainer * {
				font-weight: 400 !important;
				text-transform: uppercase;
			}
			.articleDateline, .articleDatelineTitle { margin: 0 0 10px !important; }
			.articleTitle h1 { margin: 0 0 16px !important; }
			.externalLink { margin: 0 0 28px !important; }
			a { color: inherit !important; text-decoration-color: #44be9c !important; }
			.articleBody { margin-top: 34px !important; }
			.articleBody p { margin: 0 0 1.25em; }
			.articleBody img, .articleBody video { border-radius: 10px; height: auto; max-width: 100%; }
			(article.rawImageLink == nil ? ".headerTable img, .headerImage, .articleImage { display: none !important; }" : "")
			blockquote {
				border-left: 2px solid #44be9c;
				color: #6f6b6c;
				margin-left: 0;
				padding-left: 20px;
			}
			@media (prefers-color-scheme: dark) {
				body { color: #d8d8d8; }
				.header, .articleDateline, .articleDatelineTitle, .externalLink { color: #9c988e !important; }
				a { text-decoration-color: #d64c46 !important; }
				blockquote { border-left-color: #d64c46; color: #b5b0a5; }
			}
			</style>
		</head>
		<body>
			\(renderedHTML)
			<script>
			// Match Reeder's reading order: date, title, source/byline, then body.
			(function () {
				const article = document.querySelector('article');
				const header = document.querySelector('.headerContainer');
				if (!article || !header) return;
				let title = article.querySelector('.articleTitle');
				const dateline = article.querySelector('.articleDateline, .articleDatelineTitle');
				const body = article.querySelector('.articleBody');
				if (dateline) dateline.textContent = '\(readerDate)';
				if (!title && body) {
					const fallback = document.createElement('div');
					fallback.className = 'articleTitle';
					fallback.innerHTML = '<h1>\(fallbackTitle)</h1>';
					article.insertBefore(fallback, body);
					title = fallback;
				}
				if (title && dateline) article.insertBefore(dateline, title);
				if (body) article.insertBefore(header, body);
			})();
			// Reeder does not reserve a blank frame when a remote thumbnail fails.
			document.querySelectorAll('img').forEach(function (image) {
				image.addEventListener('error', function () { image.style.display = 'none'; });
			});
			</script>
		</body>
		</html>
		"""
		let baseURL = URL(string: rendering.baseURL)
		webView.loadHTMLString(html, baseURL: baseURL)
		if let offset = pendingScrollOffset {
			pendingScrollOffset = nil
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
				self?.webView.scrollView.setContentOffset(offset, animated: false)
			}
		}
	}

    @objc private func openOriginal() {
        guard let url = article.preferredURL else { return }
        UIApplication.shared.open(url)
    }

    @objc private func closeReader() {
        navigationController?.popViewController(animated: true)
    }

    @objc private func showActions() {
		let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
		alert.addAction(UIAlertAction(title: article.status.read ? "Mark as Unread" : "Mark as Read", style: .default) { [weak self] _ in
			self?.updateStatus(.read, flag: !(self?.article.status.read ?? false))
		})
		if article.preferredURL != nil {
			alert.addAction(UIAlertAction(title: "Open in Safari", style: .default) { [weak self] _ in self?.openOriginal() })
		}
		alert.addAction(UIAlertAction(title: "Share", style: .default) { [weak self] _ in
			guard let self else { return }
			var items: [Any] = [BabelLibrary.displayTitle(for: article)]
			if let url = article.preferredURL { items.append(url) }
			let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
			self.present(controller, animated: true)
		})
		alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

	private func updateStatus(_ key: ArticleStatus.Key, flag: Bool) {
		if key == .read { setReaderSymbol(readButton, name: flag ? "circle" : "circle.fill", pointSize: 12) }
		if key == .starred { setReaderSymbol(starButton, name: flag ? "star.fill" : "star", pointSize: 15) }
		if key == .starred { starButton?.tintColor = flag ? BabelPalette.accent : BabelPalette.ink }
		// Update the shared in-memory status immediately so repeated taps and
		// subsequent reader transitions use the new state before sync completes.
		article.status.setBoolStatus(flag, forKey: key)
		guard let account = article.account else { return }
		Task { try? await account.markArticles(articleIDs: [article.articleID], statusKey: key, flag: flag) }
	}

	private func updateToolbarState() {
		setReaderSymbol(readButton, name: article.status.read ? "circle" : "circle.fill", pointSize: 12)
		setReaderSymbol(starButton, name: article.status.starred ? "star.fill" : "star", pointSize: 15)
		starButton?.tintColor = article.status.starred ? BabelPalette.accent : BabelPalette.ink
	}

	private func setReaderSymbol(_ button: UIButton?, name: String, pointSize: CGFloat) {
		let config = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
		button?.setImage(UIImage(systemName: name, withConfiguration: config), for: .normal)
	}

	@objc private func toggleRead() { updateStatus(.read, flag: !article.status.read) }
	@objc private func toggleStar() { updateStatus(.starred, flag: !article.status.starred) }
    @objc private func showNextArticle() {
		guard let next = nextArticle?() else { return }
		let reader = BabelReaderViewController(article: next)
		reader.readerMode = readerMode
		reader.nextArticle = nextArticle
		navigationController?.pushViewController(reader, animated: true)
	}

	@objc private func toggleReaderMode() {
		pendingScrollOffset = webView.scrollView.contentOffset
		readerMode.toggle()
		if let brButton = bottomToolbar.arrangedSubviews.last as? UIButton {
			brButton.setTitleColor(readerMode ? BabelPalette.accent : BabelPalette.mutedInk, for: .normal)
		}
		renderArticle()
	}

	@objc private func requestTranslation() {
		_ = NNWTitleTranslationController.shared.displayArticle(for: article)
	}

	@objc private func translationDidUpdate() { renderArticle() }
}
