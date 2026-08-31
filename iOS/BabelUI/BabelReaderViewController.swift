//
//  BabelReaderViewController.swift
//  NetNewsWire
//

import UIKit
import WebKit
import Articles
import Images

/// Reuse the app's already-warmed WebKit instances. The legacy reader does
/// this too; creating a new WKWebView for every Babel article is what made a
/// cached article still spend seconds in WebKit's cold-start blank state.
@MainActor enum BabelReaderWebViewPool {
	static var provider: WebViewProvider?
}

final class BabelReaderViewController: UIViewController, UIScrollViewDelegate, WKNavigationDelegate, UIGestureRecognizerDelegate {
	private static let readerDateFormatter: DateFormatter = {
		let formatter = DateFormatter()
		formatter.locale = Locale(identifier: "en_US_POSIX")
		formatter.dateFormat = "EEEE, MMMM d, yyyy 'AT' H:mm"
		return formatter
	}()

	private let article: Article
	private let preparedWebView: PreloadedWebView?
	var nextArticle: (() -> Article?)?
	var takePreparedWebView: (() -> PreloadedWebView?)?
	private var webView: WKWebView!
	private let loadErrorLabel = UILabel()
	private let bottomToolbar = UIView()
	private let readerHeader = UIView()
	private let compactHeader = BabelReaderCompactHeaderView()
	private let initialIdentityView = BabelReaderInitialIdentityView()
	private let translationButton = BabelTranslationToggleControl()
	private lazy var translationController = TranslationController { [weak self] in self }
	private weak var readButton: UIButton?
	private weak var starButton: UIButton?
	private weak var readerModeButton: UIButton?
	private var articleExtractor: ReaderViewExtractor?
	private var extractedArticle: ExtractedArticle?
	private var isShowingExtractedArticle = false
	private var pendingScrollOffset: CGPoint?
	private var compactTitleOverride: String?
	private var lastScrollOffsetY: CGFloat = 0
	private var hasEstablishedScrollBaseline = false
	private var compactHeaderThreshold: CGFloat = 190
	private var isCompactHeaderVisible = false
	private var isScrollableArticle = false
	private var controlsVisible = true
	private var accumulatedDirectionTravel: CGFloat = 0
	private var lastDirection: CGFloat = 0
	private var debugReadingProgressOverride: CGFloat?
	private var didApplyDebugScrollState = false
	private var hasCommittedInitialDocument = false
	private var webViewToolbarBottomConstraint: NSLayoutConstraint!
	private var webViewFullBottomConstraint: NSLayoutConstraint!
	private var webViewHeaderTopConstraint: NSLayoutConstraint!
	private var webViewCompactTopConstraint: NSLayoutConstraint!
	private var compactHeaderTopConstraint: NSLayoutConstraint!
	private lazy var openOriginalPanGestureRecognizer: UIPanGestureRecognizer = {
		let gesture = UIPanGestureRecognizer(target: self, action: #selector(handleOpenOriginalPan(_:)))
		gesture.delegate = self
		gesture.maximumNumberOfTouches = 1
		gesture.cancelsTouchesInView = false
		gesture.delaysTouchesBegan = false
		return gesture
	}()

	init(article: Article, preparedWebView: PreloadedWebView? = nil) {
		self.article = article
		self.preparedWebView = preparedWebView
		super.init(nibName: nil, bundle: nil)
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		configureView()
		translationController.stateDidChange = { [weak self] state in
			self?.updateTranslationControl(for: state)
		}
		updateTranslationControl(for: translationController.state)
		NotificationCenter.default.addObserver(self, selector: #selector(translationDidUpdate), name: .nnwTitleTranslationDidUpdate, object: nil)
	}

	deinit {
		NotificationCenter.default.removeObserver(self)
	}

	override func willMove(toParent parent: UIViewController?) {
		super.willMove(toParent: parent)
		if parent == nil {
			articleExtractor?.cancel()
			articleExtractor = nil
		}
	}

	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)
		if !article.status.read { updateStatus(.read, flag: true) }
	}

	private func configureView() {
		view.backgroundColor = BabelPalette.background
		// The safe-area region behind the system status items is part of the
		// Reader surface, not Liquid Glass. Keep this root surface fully opaque
		// even though the WKWebView above it intentionally renders transparent.
		view.isOpaque = true
		title = article.feed?.nameForDisplay
        navigationItem.largeTitleDisplayMode = .never
		configureReaderHeader()
		bottomToolbar.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(bottomToolbar)

		configureCompactHeader()
		configureInitialIdentityView()

        bottomToolbar.backgroundColor = BabelPalette.background
		let toolbarItems: [(String, String)] = [
			("circle", "已读"),
			("star", "星标"),
			("chevron.down", "下一篇"),
			("doc.text", "阅读模式"),
			("photo.badge.plus", "生成长图")
		]
		var controls = [UIButton]()
		for (index, item) in toolbarItems.enumerated() {
			let button = UIButton(type: .custom)
			button.accessibilityIdentifier = "babel.reader.toolbar.\(item.1)"
			button.setImage(BabelChromeMetrics.bottomSymbol(item.0), for: .normal)
			button.tintColor = BabelPalette.ink
			button.accessibilityLabel = item.1
			button.translatesAutoresizingMaskIntoConstraints = false
            if index == 0 { button.addTarget(self, action: #selector(toggleRead), for: .touchUpInside) }
            if index == 1 { button.addTarget(self, action: #selector(toggleStar), for: .touchUpInside) }
            if index == 2 { button.addTarget(self, action: #selector(showNextArticle), for: .touchUpInside) }
			if index == 3 { button.addTarget(self, action: #selector(toggleReaderMode), for: .touchUpInside) }
			if index == 4 { button.addTarget(self, action: #selector(shareLongImage), for: .touchUpInside) }
			if index == 0 { readButton = button }
			if index == 1 { starButton = button }
			if index == 3 { readerModeButton = button }
			controls.append(button)
		}
		translationButton.accessibilityIdentifier = "babel.reader.toolbar.translation"
		translationButton.addTarget(self, action: #selector(requestTranslation), for: .touchUpInside)
		translationButton.translatesAutoresizingMaskIntoConstraints = false
		let toolbarStack = UIStackView(arrangedSubviews: controls + [translationButton])
		toolbarStack.axis = .horizontal
		toolbarStack.alignment = .fill
		toolbarStack.distribution = .fillEqually
		toolbarStack.translatesAutoresizingMaskIntoConstraints = false
		bottomToolbar.addSubview(toolbarStack)
		let toolbarSeparator = UIView()
		toolbarSeparator.backgroundColor = BabelPalette.hairline
		toolbarSeparator.translatesAutoresizingMaskIntoConstraints = false
		bottomToolbar.addSubview(toolbarSeparator)
		updateToolbarState()
        NSLayoutConstraint.activate([
            bottomToolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomToolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            // Reeder's reader toolbar extends through the home-indicator inset;
            // anchoring to the view bottom keeps its icons at the reference
            // baseline instead of lifting them by the safe-area height.
            bottomToolbar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
			bottomToolbar.heightAnchor.constraint(equalToConstant: BabelChromeMetrics.bottomToolbarHeight),
			toolbarSeparator.leadingAnchor.constraint(equalTo: bottomToolbar.leadingAnchor),
			toolbarSeparator.trailingAnchor.constraint(equalTo: bottomToolbar.trailingAnchor),
			toolbarSeparator.topAnchor.constraint(equalTo: bottomToolbar.topAnchor),
			toolbarSeparator.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),
			toolbarStack.leadingAnchor.constraint(equalTo: bottomToolbar.leadingAnchor),
			toolbarStack.trailingAnchor.constraint(equalTo: bottomToolbar.trailingAnchor),
			toolbarStack.topAnchor.constraint(equalTo: bottomToolbar.topAnchor, constant: 2),
			toolbarStack.heightAnchor.constraint(equalToConstant: 44)
		])
		view.bringSubviewToFront(bottomToolbar)
		NotificationCenter.default.addObserver(self, selector: #selector(feedIconDidUpdate), name: .feedIconDidBecomeAvailable, object: nil)
		installInitialWebView()
	}

	private func installInitialWebView() {
		if let preparedWebView {
			installWebView(preparedWebView)
			return
		}
		guard let provider = BabelReaderWebViewPool.provider else {
			installWebView(WKWebView(frame: .zero))
			return
		}
		provider.dequeueWebView { [weak self] preloadedWebView in
			preloadedWebView.ready { [weak self] in
				self?.installWebView(preloadedWebView)
			}
		}
	}

	private func installWebView(_ webView: WKWebView) {
		guard self.webView == nil else { return }
		self.webView = webView
		installBabelHeaderVisibilityScript(in: webView)
		webView.isOpaque = false
		webView.accessibilityIdentifier = "babel.reader.content"
		webView.backgroundColor = .clear
		webView.scrollView.backgroundColor = BabelPalette.background
		webView.allowsBackForwardNavigationGestures = false
		webView.navigationDelegate = self
		webView.scrollView.delegate = self
		webView.addGestureRecognizer(openOriginalPanGestureRecognizer)
		let chromeTap = UITapGestureRecognizer(target: self, action: #selector(toggleChrome))
		chromeTap.cancelsTouchesInView = false
		webView.addGestureRecognizer(chromeTap)
		webView.translatesAutoresizingMaskIntoConstraints = false
		view.insertSubview(webView, belowSubview: readerHeader)

		webViewHeaderTopConstraint = webView.topAnchor.constraint(equalTo: readerHeader.bottomAnchor)
		webViewCompactTopConstraint = webView.topAnchor.constraint(equalTo: compactHeader.bottomAnchor)
		webViewToolbarBottomConstraint = webView.bottomAnchor.constraint(equalTo: bottomToolbar.topAnchor)
		webViewFullBottomConstraint = webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
		NSLayoutConstraint.activate([
			webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			webViewHeaderTopConstraint,
			webViewToolbarBottomConstraint
		])

		loadErrorLabel.textColor = BabelPalette.mutedInk
		loadErrorLabel.accessibilityIdentifier = "babel.reader.load-error"
		loadErrorLabel.font = UIFont.systemFont(ofSize: 15)
		loadErrorLabel.textAlignment = .center
		loadErrorLabel.numberOfLines = 0
		loadErrorLabel.isHidden = true
		loadErrorLabel.isUserInteractionEnabled = true
		loadErrorLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(retryRender)))
		loadErrorLabel.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(loadErrorLabel)
		NSLayoutConstraint.activate([
			loadErrorLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
			loadErrorLabel.centerYAnchor.constraint(equalTo: webView.centerYAnchor),
			loadErrorLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
			loadErrorLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32)
		])
		view.bringSubviewToFront(initialIdentityView)
		view.bringSubviewToFront(readerHeader)
		view.bringSubviewToFront(compactHeader)
		view.bringSubviewToFront(bottomToolbar)
		// The expanded article header is the entry state. The compact identity
		// bar belongs only to the scrolled state, after the document's own
		// author/title block has moved past the top chrome.
		setCompactHeaderVisible(false, animated: false)
		renderArticle()
	}

	/// The shared WebView pool also carries Genesis v2's `nnw_appearance.js`.
	/// That script adds `nnw-reading-bar` and hides the document title/byline,
	/// because the legacy reader redraws them in `ArticleHeaderBar`. Babel keeps
	/// those nodes in the document at entry, so remove the legacy marker at both
	/// points where the shared script can add it.
	private func installBabelHeaderVisibilityScript(in webView: WKWebView) {
		let source = """
		(function() {
			document.documentElement.classList.remove("nnw-reading-bar");
			document.addEventListener("DOMContentLoaded", function() {
				document.documentElement.classList.remove("nnw-reading-bar");
			});
		})();
		"""
		webView.configuration.userContentController.addUserScript(
			WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true)
		)
	}

	@objc private func toggleChrome() {
		guard isCompactHeaderVisible else { return }
		setControlsVisible(!controlsVisible, animated: true)
	}

	private func setCompactHeaderVisible(_ visible: Bool, animated: Bool) {
		guard isCompactHeaderVisible != visible else { return }
		isCompactHeaderVisible = visible
		if visible {
			controlsVisible = false
			readerHeader.isUserInteractionEnabled = false
			compactHeaderTopConstraint.constant = 0
			webViewHeaderTopConstraint.isActive = false
			webViewCompactTopConstraint.isActive = true
			webViewToolbarBottomConstraint.isActive = false
			webViewFullBottomConstraint.isActive = true
			// Text travels upward on a straight, non-spring path; the icon starts
			// transparent and appears as a secondary fade-in detail.
			compactHeader.transform = CGAffineTransform(translationX: 0, y: 38)
			compactHeader.setProgressIconVisible(false)
		} else {
			controlsVisible = true
			readerHeader.isUserInteractionEnabled = true
			compactHeaderTopConstraint.constant = 0
			webViewCompactTopConstraint.isActive = false
			webViewHeaderTopConstraint.isActive = true
			webViewFullBottomConstraint.isActive = false
			webViewToolbarBottomConstraint.isActive = true
		}
		let changes = {
			self.readerHeader.alpha = visible ? 0 : 1
			self.readerHeader.transform = .identity
			self.compactHeader.alpha = visible ? 1 : 0
			self.compactHeader.transform = .identity
			self.compactHeader.setProgressIconVisible(visible)
			self.bottomToolbar.alpha = visible ? 0 : 1
			self.bottomToolbar.transform = .identity
			self.view.layoutIfNeeded()
		}
		if animated {
			UIView.animate(withDuration: 0.26, delay: 0, options: [.curveLinear, .beginFromCurrentState, .allowUserInteraction], animations: changes)
		} else {
			changes()
		}
	}

	private func setControlsVisible(_ visible: Bool, animated: Bool) {
		guard isCompactHeaderVisible, controlsVisible != visible else { return }
		controlsVisible = visible
		if visible {
			readerHeader.isUserInteractionEnabled = true
			compactHeaderTopConstraint.constant = 44
			webViewToolbarBottomConstraint.isActive = true
			webViewFullBottomConstraint.isActive = false
			readerHeader.transform = CGAffineTransform(translationX: 0, y: -10)
			bottomToolbar.transform = CGAffineTransform(translationX: 0, y: 14)
		} else {
			compactHeaderTopConstraint.constant = 0
			webViewToolbarBottomConstraint.isActive = false
			webViewFullBottomConstraint.isActive = true
		}
		let changes = {
			self.readerHeader.alpha = visible ? 1 : 0
			self.readerHeader.transform = visible ? .identity : CGAffineTransform(translationX: 0, y: -10)
			self.bottomToolbar.alpha = visible ? 1 : 0
			self.bottomToolbar.transform = visible ? .identity : CGAffineTransform(translationX: 0, y: 14)
			self.view.layoutIfNeeded()
		}
		let completion: (Bool) -> Void = { [weak self] _ in
			if !visible { self?.readerHeader.isUserInteractionEnabled = false }
		}
		if animated {
			UIView.animate(withDuration: BabelChromeMetrics.selectionDuration, delay: 0, options: [.curveLinear, .beginFromCurrentState, .allowUserInteraction], animations: changes, completion: completion)
		} else {
			changes()
			completion(true)
		}
	}

	func scrollViewDidScroll(_ scrollView: UIScrollView) {
		let offsetY = scrollView.contentOffset.y
		refreshScrollableState(in: scrollView)
		updateReadingProgress(in: scrollView)
		guard isScrollableArticle else {
			setCompactHeaderVisible(false, animated: false)
			return
		}
		// Let the article's real byline and title own the entry state. The compact
		// bar takes over only after that block has physically crossed the chrome.
		let shouldShowCompactHeader = offsetY >= compactHeaderThreshold
		setCompactHeaderVisible(shouldShowCompactHeader, animated: hasEstablishedScrollBaseline)
		guard hasEstablishedScrollBaseline else {
			lastScrollOffsetY = offsetY
			hasEstablishedScrollBaseline = true
			return
		}
		let delta = offsetY - lastScrollOffsetY
		lastScrollOffsetY = offsetY
		guard shouldShowCompactHeader, abs(delta) > 0.5 else { return }
		let maxOffset = max(scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom, -scrollView.adjustedContentInset.top)
		guard offsetY >= -scrollView.adjustedContentInset.top, offsetY <= maxOffset else { return }
		let direction: CGFloat = delta > 0 ? 1 : -1
		if direction == lastDirection {
			accumulatedDirectionTravel += abs(delta)
		} else {
			lastDirection = direction
			accumulatedDirectionTravel = abs(delta)
		}
		guard accumulatedDirectionTravel >= 12 else { return }
		setControlsVisible(direction < 0, animated: true)
		accumulatedDirectionTravel = 0
	}

	func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
		if !decelerate, !isCompactHeaderVisible { setCompactHeaderVisible(false, animated: false) }
	}

	func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
		if !isCompactHeaderVisible { setCompactHeaderVisible(false, animated: false) }
	}

	private func updateReadingProgress(in scrollView: UIScrollView) {
		if let debugReadingProgressOverride {
			compactHeader.readingProgress = debugReadingProgressOverride
			return
		}
		guard isScrollableArticle else {
			compactHeader.readingProgress = 0
			return
		}
		let maxScrollableOffset = scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom
		let distance = max(maxScrollableOffset - compactHeaderThreshold, 1)
		let value = min(max((scrollView.contentOffset.y - compactHeaderThreshold) / distance, 0), 1)
		compactHeader.readingProgress = value
	}

	private func refreshScrollableState(in scrollView: UIScrollView) {
		let maximumOffset = scrollView.contentSize.height
			- scrollView.bounds.height
			+ scrollView.adjustedContentInset.bottom
		let minimumOffset = -scrollView.adjustedContentInset.top
		isScrollableArticle = maximumOffset > minimumOffset + 1
	}

	private func configureCompactHeader() {
		compactHeader.translatesAutoresizingMaskIntoConstraints = false
		compactHeader.alpha = 0
		compactHeader.isAccessibilityElement = true
		compactHeader.accessibilityIdentifier = "babel.reader.compact-header"
		view.addSubview(compactHeader)
		compactHeaderTopConstraint = compactHeader.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor)
		NSLayoutConstraint.activate([
			compactHeader.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			compactHeader.trailingAnchor.constraint(equalTo: view.trailingAnchor),
		compactHeaderTopConstraint,
			compactHeader.heightAnchor.constraint(equalToConstant: 86)
		])
		updateCompactHeaderContent()
	}

	private func configureInitialIdentityView() {
		let feedName = article.feed?.nameForDisplay ?? "ARTICLE"
		let author = article.authors?.first?.name ?? ""
		let source = [feedName, author]
			.filter { !$0.isEmpty }
			.joined(separator: " · ")
		initialIdentityView.configure(
			date: Self.readerDateFormatter.string(from: article.logicalDatePublished).uppercased(),
			title: BabelLibrary.displayTitle(for: article),
			source: source.uppercased()
		)
		initialIdentityView.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(initialIdentityView)
		NSLayoutConstraint.activate([
			initialIdentityView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			initialIdentityView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			initialIdentityView.topAnchor.constraint(equalTo: readerHeader.bottomAnchor)
		])
	}

	private func updateCompactHeaderContent() {
		let feedName = article.feed?.nameForDisplay ?? "ARTICLE"
		let author = article.authors?.first?.name ?? ""
		var sourceText = [feedName, author].filter { !$0.isEmpty }.joined(separator: " · ")
		if article.preferredURL != nil { sourceText += "  ↗" }
		compactHeader.configure(
			source: sourceText.uppercased(),
			title: compactTitleOverride ?? BabelLibrary.displayTitle(for: article),
			icon: IconImageCache.shared.imageForArticle(article)?.image,
			fallback: String(feedName.prefix(1)).uppercased()
		)
	}

	@objc private func feedIconDidUpdate() {
		updateCompactHeaderContent()
	}

	private func configureReaderHeader() {
		readerHeader.translatesAutoresizingMaskIntoConstraints = false
		readerHeader.backgroundColor = BabelPalette.background
		view.addSubview(readerHeader)
		let back = UIButton(type: .custom)
		back.setImage(UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)), for: .normal)
		back.tintColor = BabelPalette.ink
		back.accessibilityLabel = "关闭文章"
		back.accessibilityIdentifier = "babel.reader.header.close"
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
		actions.accessibilityLabel = "文章操作"
		actions.accessibilityIdentifier = "babel.reader.header.actions"
		actions.addTarget(self, action: #selector(showActions), for: .touchUpInside)
		actions.translatesAutoresizingMaskIntoConstraints = false
		readerHeader.addSubview(actions)
		let tag = UIButton(type: .custom)
		tag.setImage(UIImage(systemName: "tag", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)), for: .normal)
		tag.tintColor = BabelPalette.ink
		tag.accessibilityLabel = "文章标签"
		tag.accessibilityIdentifier = "babel.reader.header.tag"
		tag.addTarget(self, action: #selector(showActions), for: .touchUpInside)
		tag.translatesAutoresizingMaskIntoConstraints = false
		readerHeader.addSubview(tag)
		let share = UIButton(type: .custom)
		share.setImage(UIImage(systemName: "square.and.arrow.up", withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .regular)), for: .normal)
		share.tintColor = BabelPalette.ink
		share.accessibilityLabel = "分享文章"
		share.accessibilityIdentifier = "babel.reader.header.share"
		share.addTarget(self, action: #selector(shareButtonTapped(_:)), for: .touchUpInside)
		share.translatesAutoresizingMaskIntoConstraints = false
		readerHeader.addSubview(share)
		NSLayoutConstraint.activate([
			readerHeader.leadingAnchor.constraint(equalTo: view.leadingAnchor), readerHeader.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			readerHeader.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor), readerHeader.heightAnchor.constraint(equalToConstant: 58),
			back.centerXAnchor.constraint(equalTo: readerHeader.leadingAnchor, constant: BabelChromeMetrics.topSlots[0]), back.centerYAnchor.constraint(equalTo: readerHeader.topAnchor, constant: BabelChromeMetrics.topControlCenterY),
			back.widthAnchor.constraint(equalToConstant: 44), back.heightAnchor.constraint(equalToConstant: 44),
			label.centerXAnchor.constraint(equalTo: readerHeader.centerXAnchor), label.centerYAnchor.constraint(equalTo: readerHeader.centerYAnchor),
			actions.centerXAnchor.constraint(equalTo: readerHeader.leadingAnchor, constant: BabelChromeMetrics.topSlots[1]), actions.centerYAnchor.constraint(equalTo: readerHeader.topAnchor, constant: BabelChromeMetrics.topControlCenterY),
			actions.widthAnchor.constraint(equalToConstant: 44), actions.heightAnchor.constraint(equalToConstant: 44),
			tag.centerXAnchor.constraint(equalTo: readerHeader.leadingAnchor, constant: BabelChromeMetrics.topSlots[2]), tag.centerYAnchor.constraint(equalTo: readerHeader.topAnchor, constant: BabelChromeMetrics.topControlCenterY),
			tag.widthAnchor.constraint(equalToConstant: 44), tag.heightAnchor.constraint(equalToConstant: 44),
			share.centerXAnchor.constraint(equalTo: readerHeader.leadingAnchor, constant: BabelChromeMetrics.topSlots[4]), share.centerYAnchor.constraint(equalTo: readerHeader.topAnchor, constant: BabelChromeMetrics.topControlCenterY),
			share.widthAnchor.constraint(equalToConstant: 44), share.heightAnchor.constraint(equalToConstant: 44)
		])
	}

	@objc private func shareLongImage() {
		let progress = NNWProgressCard.present(in: self, text: "正在生成长图…")
		Task { [weak self] in
			guard let self else { return }
			do {
				let image = try await ArticleLongImageExporter.export(from: self)
				progress.finish {
					let preview = UINavigationController(rootViewController: LongImagePreviewViewController(image: image))
					preview.modalPresentationStyle = .fullScreen
					self.present(preview, animated: true)
				}
			} catch {
				progress.finish {
					self.presentError(title: "生成长图失败", message: error.localizedDescription)
				}
			}
		}
	}

	@objc private func shareButtonTapped(_ sender: UIButton) {
		shareNormally(sourceView: sender)
	}

	private func shareNormally(sourceView: UIView? = nil) {
		var items: [Any] = [BabelLibrary.displayTitle(for: article)]
		if let url = article.preferredURL { items.append(url) }
		let activityViewController = UIActivityViewController(activityItems: items, applicationActivities: nil)
		if traitCollection.userInterfaceIdiom == .pad, let popover = activityViewController.popoverPresentationController {
			guard let anchor = sourceView ?? viewIfLoaded else { return }
			popover.sourceView = anchor
			popover.sourceRect = anchor.bounds
		}
		present(activityViewController, animated: true)
	}

	private func renderArticle() {
		guard webView != nil else { return }
		let displayArticle = NNWTitleTranslationController.shared.cachedDisplayArticle(for: article)
		let rendering: ArticleRenderer.Rendering
		if isShowingExtractedArticle, let extractedArticle {
			rendering = ArticleRenderer.articleHTML(article: displayArticle, extractedArticle: extractedArticle, theme: ArticleThemesManager.shared.currentTheme)
		} else {
			rendering = ArticleRenderer.articleHTML(article: displayArticle, theme: ArticleThemesManager.shared.currentTheme)
		}
		let fallbackTitle = BabelLibrary.displayTitle(for: article)
			.replacingOccurrences(of: "\\", with: "\\\\")
			.replacingOccurrences(of: "&", with: "&amp;")
			.replacingOccurrences(of: "<", with: "&lt;")
			.replacingOccurrences(of: ">", with: "&gt;")
			.replacingOccurrences(of: "'", with: "\\'")
		let readerDate = Self.readerDateFormatter.string(from: article.logicalDatePublished).uppercased()
		let isDark = traitCollection.userInterfaceStyle == .dark
		let readerBodyColor = isDark ? "#d8d8d8" : "#787878"
		let readerTitleColor = isDark ? "#d8d8d8" : "#3a3a3a"
		let readerMetadataColor = isDark ? "#9c988e" : "#a3a0a1"
		let readerQuoteColor = isDark ? "#6c6c6c" : "#b0aeaf"
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
				color: \(readerBodyColor);
				font-family: -apple-system, BlinkMacSystemFont, sans-serif;
				font-size: 19px;
				font-weight: 400;
				line-height: 30px;
				margin: 0 auto;
				max-width: 680px;
				/* Figma Reader Original starts the dateline 26pt below the web
				   content frame; the native reader chrome already owns the space
				   above this frame. */
				padding: 26px 20px 80px;
			}
			.headerContainer, .header-container { margin-bottom: 30px; }
			.headerTable { width: 100%; }
			.header, .articleDateline, .articleDatelineTitle, .externalLink {
				color: \(readerMetadataColor) !important;
				font-family: -apple-system, BlinkMacSystemFont, sans-serif;
				font-size: 11px !important;
				line-height: 15px !important;
			}
			.articleTitle h1, article .articleTitle h1,
			.article-title h1, article .article-title h1 {
				color: \(readerTitleColor) !important;
				font-family: -apple-system, BlinkMacSystemFont, sans-serif !important;
				font-size: 34px !important;
				font-weight: 700 !important;
				line-height: 38px !important;
				letter-spacing: -0.02em;
				margin: 12px 0 14px !important;
				text-align: left !important;
				width: 100% !important;
			}
			.articleTitle, article .articleTitle,
			.article-title, article .article-title {
				margin: 0 !important;
				padding: 0 !important;
				text-align: left !important;
				width: 100% !important;
			}
			.articleTitle a, article .articleTitle a,
			.article-title a, article .article-title a {
				display: inline !important;
				margin: 0 !important;
				padding: 0 !important;
			}
			/* Reeder's reading hierarchy is date, title, then source/byline. */
			article { display: flex; flex-direction: column; }
			.articleDateline, .articleDatelineTitle { order: 1; }
			.articleTitle, .article-title { order: 2; }
			.headerContainer, .header-container { order: 3; margin: 0 0 34px !important; border: 0 !important; border-bottom: 0 !important; }
			body .headerTable { border-bottom: 0 !important; }
			.externalLink { order: 4; }
			/* Reeder keeps the raw URL out of the article header; it remains
			   available through the actions menu and the share control. */
			.externalLink { display: none !important; }
			.articleBody, .article-body { order: 5; }
			.headerContainer .avatar { display: none !important; }
			.headerContainer, .headerContainer table, .headerContainer tr, .headerContainer td,
			.header-container, .header-container table, .header-container tr, .header-container td {
				min-height: 0 !important;
				height: auto !important;
			}
			.headerContainer .headerTable { width: 100%; }
			.headerContainer .leftAlign { text-align: left; }
			.headerContainer, .headerContainer * {
				font-weight: 400 !important;
				text-transform: uppercase;
			}
			.articleDateline, .articleDatelineTitle { margin: 0 0 10px !important; }
			.articleTitle h1, article .articleTitle h1,
			.article-title h1, article .article-title h1 { margin: 0 0 16px !important; }
			.externalLink { margin: 0 0 28px !important; }
			/* Reader links deliberately carry no colour or underline. Feed HTML often
			   applies its own link decoration to nested spans, so reset the whole
			   article link subtree rather than only the anchor element. */
			.articleBody a, .articleBody a *,
			.article-body a, .article-body a * {
				color: inherit !important;
				font-weight: 600 !important;
				text-decoration: none !important;
				text-decoration-line: none !important;
				text-decoration-color: transparent !important;
			}
			.articleBody, .article-body { margin-top: 34px !important; }
			.articleBody p, .article-body p { margin: 0 0 1.25em; }
			/* Article media uses a hard rectangular edge. Theme styles and linked
			   image wrappers may add their own radius, so reset every clipping layer. */
			.articleBody img, .articleBody video,
			.article-body img, .article-body video {
				border-radius: 0 !important;
				clip-path: none !important;
				height: auto;
				max-width: 100%;
			}
			.articleBody figure, .articleBody picture, .articleBody a:has(img),
			.article-body figure, .article-body picture, .article-body a:has(img) {
				border-radius: 0 !important;
				clip-path: none !important;
				overflow: visible !important;
			}
			/* Landscape editorial images break out of the reading column and meet
			   both viewport edges. Text, captions, portrait images and small inline
			   artwork keep the normal 20pt reading margin. */
			.articleBody img.babel-landscape-fullbleed,
			.article-body img.babel-landscape-fullbleed {
				border-radius: 0 !important;
				display: block;
				height: auto !important;
				left: 50%;
				margin-left: -50vw !important;
				margin-right: -50vw !important;
				max-width: none !important;
				position: relative;
				width: 100vw !important;
			}
			.articleBody figure:has(img.babel-landscape-fullbleed),
			.article-body figure:has(img.babel-landscape-fullbleed) {
				margin-left: 0;
				margin-right: 0;
			}
			(article.rawImageLink == nil ? ".headerTable img, .headerImage, .articleImage { display: none !important; }" : "")
			blockquote {
				border-left: 2px solid \(readerQuoteColor);
				color: \(readerBodyColor);
				margin-left: 0;
				padding-left: 20px;
			}
			@media (prefers-color-scheme: dark) {
				body { color: #d8d8d8; }
				.header, .articleDateline, .articleDatelineTitle, .externalLink { color: #9c988e !important; }
				blockquote { border-left-color: #6c6c6c; color: #b5b0a5; }
			}
			</style>
		</head>
		<body>
			\(renderedHTML)
			<script>
			// Match Reeder's reading order: date, title, source/byline, then body.
			(function () {
				const article = document.querySelector('article');
				const header = document.querySelector('.headerContainer, .header-container');
				if (!article) return;
				let title = article.querySelector('.articleTitle, .article-title')
					|| document.querySelector('.articleTitle, .article-title');
				const dateline = article.querySelector('.articleDateline, .articleDatelineTitle');
				const body = article.querySelector('.articleBody, .article-body');
				if (dateline) dateline.textContent = '\(readerDate)';
				if (!title && body) {
					const fallback = document.createElement('div');
					fallback.className = 'articleTitle';
					fallback.innerHTML = '<h1>\(fallbackTitle)</h1>';
					article.insertBefore(fallback, body);
					title = fallback;
				}
				if (title && dateline && title.parentElement === article) article.insertBefore(dateline, title);
				if (header && body) article.insertBefore(header, body);
			})();
			// Reeder does not reserve a blank frame when a remote thumbnail fails.
			// Landscape editorial images become full-bleed only after WebKit knows
			// their intrinsic size. Translation can replace body nodes, so observe
			// the article body and apply the same rule to newly inserted images.
			(function () {
				const body = document.querySelector('.articleBody, .article-body');
				if (!body) return;

				function updateImageLayout(image) {
					if (!(image instanceof HTMLImageElement)) return;
					const isEditorialLandscape = image.naturalWidth >= 240
						&& image.naturalHeight >= 120
						&& image.naturalWidth / image.naturalHeight >= 1.08;
					image.classList.toggle('babel-landscape-fullbleed', isEditorialLandscape);
				}

				function prepareImage(image) {
					if (!(image instanceof HTMLImageElement)) return;
					if (!image.dataset.babelLayoutPrepared) {
						image.dataset.babelLayoutPrepared = 'true';
						image.addEventListener('load', function () { updateImageLayout(image); });
						image.addEventListener('error', function () { image.style.display = 'none'; });
					}
					if (image.complete && image.naturalWidth > 0) updateImageLayout(image);
				}

				body.querySelectorAll('img').forEach(prepareImage);
				new MutationObserver(function (mutations) {
					mutations.forEach(function (mutation) {
						if (mutation.type === 'attributes') {
							prepareImage(mutation.target);
							return;
						}
						mutation.addedNodes.forEach(function (node) {
							if (!(node instanceof Element)) return;
							if (node.matches('img')) prepareImage(node);
							node.querySelectorAll('img').forEach(prepareImage);
						});
					});
				}).observe(body, {
					attributes: true,
					attributeFilter: ['src', 'srcset'],
					childList: true,
					subtree: true
				});
			})();
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

	func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
		let thresholdScript = """
		(() => {
			const title = document.querySelector('.articleTitle, .article-title');
			const header = document.querySelector('.headerContainer, .header-container');
			const elements = [title, header].filter(Boolean);
			if (!elements.length) return 190;
			return Math.max(...elements.map(element => element.getBoundingClientRect().bottom + window.scrollY));
		})()
		"""
		webView.evaluateJavaScript(thresholdScript) { [weak self] result, _ in
			guard let self else { return }
			if let value = result as? NSNumber {
				self.compactHeaderThreshold = max(CGFloat(truncating: value) - 12, 96)
			}
			// WebKit finalizes its content size on the next run-loop turn. A
			// compact reader identity is valid only when there is actual travel
			// below the readable viewport, not merely because a header exists.
			DispatchQueue.main.async {
				let scrollView = webView.scrollView
				self.refreshScrollableState(in: scrollView)
				if !self.isScrollableArticle {
					// Short articles still need their source and title on entry.
					self.compactHeader.readingProgress = 0
				}
				self.updateReadingProgress(in: scrollView)
				#if DEBUG
				if !self.didApplyDebugScrollState {
					let arguments = ProcessInfo.processInfo.arguments
					if arguments.contains("-BabelReaderScrolled") {
						self.didApplyDebugScrollState = true
						self.hideChromeForDebug()
					} else if arguments.contains("-BabelReaderPinnedUp") {
						self.didApplyDebugScrollState = true
						self.showPinnedChromeForDebug()
					}
				}
				#endif
			}
		}
	}

	func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
		guard !hasCommittedInitialDocument else { return }
		hasCommittedInitialDocument = true
		UIView.animate(
			withDuration: 0.16,
			delay: 0.05,
			options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction]
		) {
			self.initialIdentityView.alpha = 0
		} completion: { _ in
			self.initialIdentityView.isHidden = true
		}
	}

	func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
		initialIdentityView.isHidden = true
		loadErrorLabel.text = "无法加载文章\n点击重试"
		loadErrorLabel.isHidden = false
	}

	func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
		self.webView(webView, didFail: navigation, withError: error)
	}

	@objc private func retryRender() {
		loadErrorLabel.isHidden = true
		renderArticle()
	}

	@objc private func openOriginal() {
		guard let url = article.preferredURL,
			  let scheme = url.scheme?.lowercased(),
			  scheme == "http" || scheme == "https" else { return }
		let browser = BabelBrowserViewController(
			url: url,
			articleTitle: BabelLibrary.displayTitle(for: article)
		)
		navigationController?.pushViewController(browser, animated: true)
	}

	@objc private func handleOpenOriginalPan(_ gesture: UIPanGestureRecognizer) {
		guard gesture.state == .ended else { return }
		let translationX = gesture.translation(in: webView).x
		let velocityX = gesture.velocity(in: webView).x
		if BabelOriginalLinkSwipePolicy.shouldOpen(translationX: translationX, velocityX: velocityX) {
			openOriginal()
		}
	}

	func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
		guard gestureRecognizer === openOriginalPanGestureRecognizer,
			  let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
		let originalScheme = article.preferredURL?.scheme?.lowercased()
		return BabelOriginalLinkSwipePolicy.shouldBegin(
			hasOriginalURL: originalScheme == "http" || originalScheme == "https",
			transitionInFlight: navigationController?.transitionCoordinator != nil,
			translation: pan.translation(in: webView),
			velocity: pan.velocity(in: webView)
		)
	}

	func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
						   shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
		gestureRecognizer === openOriginalPanGestureRecognizer || otherGestureRecognizer === openOriginalPanGestureRecognizer
	}

    @objc private func closeReader() {
        navigationController?.popViewController(animated: true)
    }

	@objc private func showActions() {
		let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
		alert.addAction(UIAlertAction(title: article.status.read ? "Mark as Unread" : "Mark as Read", style: .default) { [weak self] _ in
			self?.updateStatus(.read, flag: !(self?.article.status.read ?? false))
		})
		alert.addAction(UIAlertAction(title: article.status.starred ? "Unstar" : "Star", style: .default) { [weak self] _ in
			self?.updateStatus(.starred, flag: !(self?.article.status.starred ?? false))
		})
		if article.preferredURL != nil {
			alert.addAction(UIAlertAction(title: "打开原文", style: .default) { [weak self] _ in self?.openOriginal() })
		}
		alert.addAction(UIAlertAction(title: "Share", style: .default) { [weak self] _ in self?.shareNormally() })
		alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
		if traitCollection.userInterfaceIdiom == .pad, let popover = alert.popoverPresentationController {
			popover.sourceView = view
			popover.sourceRect = CGRect(x: view.bounds.midX, y: view.safeAreaInsets.top + 24, width: 1, height: 1)
		}
        present(alert, animated: true)
    }

	private func updateStatus(_ key: ArticleStatus.Key, flag: Bool) {
		if key == .read { setReaderSymbol(readButton, name: flag ? "circle" : "circle.fill") }
		if key == .starred { setReaderSymbol(starButton, name: flag ? "star.fill" : "star") }
		if key == .starred { starButton?.tintColor = BabelPalette.ink }
		// Update the shared in-memory status immediately so repeated taps and
		// subsequent reader transitions use the new state before sync completes.
		article.status.setBoolStatus(flag, forKey: key)
		guard let account = article.account else { return }
		Task { try? await account.markArticles(articleIDs: [article.articleID], statusKey: key, flag: flag) }
	}

	/// Simulator-only hook used by the visual comparison workflow.
	func presentActionsForDebug() {
		guard presentedViewController == nil else { return }
		showActions()
	}

	func hideChromeForDebug() {
		debugReadingProgressOverride = 0.42
		isScrollableArticle = true
		setCompactHeaderVisible(true, animated: false)
		setControlsVisible(false, animated: false)
		let maximumOffset = max(webView.scrollView.contentSize.height - webView.scrollView.bounds.height, 0)
		let targetOffset = min(max(compactHeaderThreshold + 120, 310), maximumOffset)
		webView.scrollView.setContentOffset(CGPoint(x: 0, y: targetOffset), animated: false)
		compactHeader.readingProgress = 0.42
	}

	func showPinnedChromeForDebug() {
		debugReadingProgressOverride = 0.42
		isScrollableArticle = true
		let maximumOffset = max(webView.scrollView.contentSize.height - webView.scrollView.bounds.height, 0)
		let targetOffset = min(max(compactHeaderThreshold + 120, 310), maximumOffset)
		webView.scrollView.setContentOffset(CGPoint(x: 0, y: targetOffset), animated: false)
		// WebKit can issue a final layout-driven scroll callback after this method
		// returns. Apply the verification state on the following run-loop turn.
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
			guard let self else { return }
			self.setCompactHeaderVisible(true, animated: false)
			self.setControlsVisible(true, animated: false)
			self.compactHeader.readingProgress = 0.42
		}
	}

	private func updateToolbarState() {
		setReaderSymbol(readButton, name: article.status.read ? "circle" : "circle.fill")
		setReaderSymbol(starButton, name: article.status.starred ? "star.fill" : "star")
		starButton?.tintColor = BabelPalette.ink
	}

	private func setReaderSymbol(_ button: UIButton?, name: String) {
		button?.setImage(BabelChromeMetrics.bottomSymbol(name), for: .normal)
	}

	@objc private func toggleRead() { updateStatus(.read, flag: !article.status.read) }
	@objc private func toggleStar() { updateStatus(.starred, flag: !article.status.starred) }
    @objc private func showNextArticle() {
		guard let next = nextArticle?() else { return }
		let reader = BabelReaderViewController(
			article: next,
			preparedWebView: takePreparedWebView?()
		)
		reader.nextArticle = nextArticle
		reader.takePreparedWebView = takePreparedWebView
		navigationController?.pushViewController(reader, animated: true)
	}

	@objc private func requestTranslation() {
		translationController.toggle()
	}

	@objc private func toggleReaderMode() {
		if isShowingExtractedArticle {
			isShowingExtractedArticle = false
			updateReaderModeButton(isProcessing: false)
			pendingScrollOffset = .zero
			renderArticle()
			return
		}
		if extractedArticle != nil {
			isShowingExtractedArticle = true
			updateReaderModeButton(isProcessing: false)
			pendingScrollOffset = .zero
			renderArticle()
			return
		}
		guard let link = article.preferredLink,
			  let extractor = ReaderViewExtractor(link, delegate: self, hostView: view) else {
			presentError(title: "阅读模式", message: "这篇文章没有可提取的原文链接。")
			return
		}
		articleExtractor = extractor
		updateReaderModeButton(isProcessing: true)
		extractor.process()
	}

	private func updateReaderModeButton(isProcessing: Bool) {
		guard let readerModeButton else { return }
		readerModeButton.isEnabled = !isProcessing
		readerModeButton.alpha = isProcessing ? 0.35 : 1
		readerModeButton.setImage(
			BabelChromeMetrics.bottomSymbol(isShowingExtractedArticle ? "doc.text.fill" : "doc.text"),
			for: .normal
		)
		// Reading mode is a weight change, not an accent-color state: regular ink
		// when off, the same ink with a heavier vector when on.
		readerModeButton.tintColor = BabelPalette.ink
		readerModeButton.isSelected = isShowingExtractedArticle
		readerModeButton.accessibilityValue = isProcessing ? "正在提取" : (isShowingExtractedArticle ? "已开启" : "已关闭")
	}

	@objc private func translationDidUpdate() {
		updateCompactHeaderContent()
	}

	private func updateTranslationControl(for state: TranslationButtonState) {
		switch state {
		case .working:
			translationButton.display = .translating
		case .translated:
			translationButton.display = .translation
		default:
			translationButton.display = .original
		}
	}
}

extension BabelReaderViewController: ArticleExtractorDelegate {
	func articleExtractionDidFail(with error: Error) {
		articleExtractor = nil
		updateReaderModeButton(isProcessing: false)
		presentError(title: "阅读模式提取失败", message: error.localizedDescription)
	}

	func articleExtractionDidComplete(extractedArticle: ExtractedArticle) {
		let wasCancelled = articleExtractor?.state == .cancelled
		articleExtractor = nil
		guard !wasCancelled else { return }
		self.extractedArticle = extractedArticle
		isShowingExtractedArticle = true
		updateReaderModeButton(isProcessing: false)
		pendingScrollOffset = .zero
		renderArticle()
	}
}

extension BabelReaderViewController: NNWArticlePageHost {
	var nnwHostArticle: Article? { article }
	var nnwHostWebView: WKWebView? { webView }

	func nnwTranslationTitleDidChange(_ text: String?) {
		compactTitleOverride = text
		updateCompactHeaderContent()
	}
}

/// Shows the article's real identity synchronously while the already-local HTML
/// is being committed to WebKit. This is not a loading screen: it is the same
/// date/title/byline block that becomes the first content in the document.
private final class BabelReaderInitialIdentityView: UIView {
	private let dateLabel = UILabel()
	private let titleLabel = UILabel()
	private let sourceLabel = UILabel()

	override init(frame: CGRect) {
		super.init(frame: frame)
		backgroundColor = BabelPalette.background
		isUserInteractionEnabled = false

		dateLabel.font = UIFont.systemFont(ofSize: 11, weight: .regular)
		dateLabel.textColor = BabelPalette.mutedInk
		dateLabel.numberOfLines = 1

		titleLabel.font = UIFont.systemFont(ofSize: 34, weight: .bold)
		titleLabel.textColor = BabelPalette.ink
		titleLabel.numberOfLines = 0
		titleLabel.lineBreakMode = .byWordWrapping

		sourceLabel.font = UIFont.systemFont(ofSize: 11, weight: .regular)
		sourceLabel.textColor = BabelPalette.mutedInk
		sourceLabel.numberOfLines = 2

		for label in [dateLabel, titleLabel, sourceLabel] {
			label.translatesAutoresizingMaskIntoConstraints = false
			addSubview(label)
		}

		NSLayoutConstraint.activate([
			dateLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
			dateLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
			dateLabel.topAnchor.constraint(equalTo: topAnchor, constant: 26),
			titleLabel.leadingAnchor.constraint(equalTo: dateLabel.leadingAnchor),
			titleLabel.trailingAnchor.constraint(equalTo: dateLabel.trailingAnchor),
			titleLabel.topAnchor.constraint(equalTo: dateLabel.bottomAnchor, constant: 10),
			sourceLabel.leadingAnchor.constraint(equalTo: dateLabel.leadingAnchor),
			sourceLabel.trailingAnchor.constraint(equalTo: dateLabel.trailingAnchor),
			sourceLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
			sourceLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -24)
		])
	}

	required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

	func configure(date: String, title: String, source: String) {
		dateLabel.text = date
		titleLabel.text = title
		sourceLabel.text = source
		accessibilityLabel = [date, title, source].filter { !$0.isEmpty }.joined(separator: ", ")
	}
}

private final class BabelReaderCompactHeaderView: UIView {
	private let progressIcon = BabelReaderProgressIconView()
	private let sourceLabel = UILabel()
	private let titleLabel = UILabel()
	private let separator = UIView()

	var readingProgress: CGFloat = 0 {
		didSet {
			progressIcon.progress = readingProgress
			accessibilityValue = "阅读进度 \(Int((readingProgress * 100).rounded()))%"
		}
	}

	override init(frame: CGRect) {
		super.init(frame: frame)
		backgroundColor = BabelPalette.background
		progressIcon.translatesAutoresizingMaskIntoConstraints = false
		addSubview(progressIcon)

		sourceLabel.font = UIFont.systemFont(ofSize: 13, weight: .regular)
		sourceLabel.textColor = BabelPalette.mutedInk
		sourceLabel.numberOfLines = 1
		sourceLabel.lineBreakMode = .byTruncatingTail
		sourceLabel.translatesAutoresizingMaskIntoConstraints = false
		addSubview(sourceLabel)

		titleLabel.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
		titleLabel.textColor = BabelPalette.ink
		titleLabel.numberOfLines = 1
		titleLabel.lineBreakMode = .byTruncatingTail
		titleLabel.translatesAutoresizingMaskIntoConstraints = false
		addSubview(titleLabel)

		separator.backgroundColor = BabelPalette.hairline
		separator.translatesAutoresizingMaskIntoConstraints = false
		addSubview(separator)

		NSLayoutConstraint.activate([
			progressIcon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
			progressIcon.centerYAnchor.constraint(equalTo: centerYAnchor),
			progressIcon.widthAnchor.constraint(equalToConstant: 48),
			progressIcon.heightAnchor.constraint(equalToConstant: 48),
			sourceLabel.leadingAnchor.constraint(equalTo: progressIcon.trailingAnchor, constant: 12),
			sourceLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
			sourceLabel.topAnchor.constraint(equalTo: topAnchor, constant: 19),
			titleLabel.leadingAnchor.constraint(equalTo: sourceLabel.leadingAnchor),
			titleLabel.trailingAnchor.constraint(equalTo: sourceLabel.trailingAnchor),
			titleLabel.topAnchor.constraint(equalTo: sourceLabel.bottomAnchor, constant: 5),
			separator.leadingAnchor.constraint(equalTo: leadingAnchor),
			separator.trailingAnchor.constraint(equalTo: trailingAnchor),
			separator.bottomAnchor.constraint(equalTo: bottomAnchor),
			separator.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale)
		])
	}

	required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

	func configure(source: String, title: String, icon: UIImage?, fallback: String) {
		sourceLabel.text = source
		titleLabel.text = title
		progressIcon.configure(image: icon, fallback: fallback)
		accessibilityLabel = [source, title].filter { !$0.isEmpty }.joined(separator: ", ")
	}

	func setProgressIconVisible(_ visible: Bool) {
		progressIcon.alpha = visible ? 1 : 0
	}
}

private final class BabelReaderProgressIconView: UIView {
	private let trackLayer = CAShapeLayer()
	private let progressLayer = CAShapeLayer()
	private let imageView = UIImageView()
	private let fallbackLabel = UILabel()

	var progress: CGFloat = 0 {
		didSet {
			CATransaction.begin()
			CATransaction.setDisableActions(true)
			progressLayer.strokeEnd = min(max(progress, 0), 1)
			CATransaction.commit()
		}
	}

	override init(frame: CGRect) {
		super.init(frame: frame)
		isUserInteractionEnabled = false
		trackLayer.fillColor = UIColor.clear.cgColor
		trackLayer.lineWidth = 2
		progressLayer.fillColor = UIColor.clear.cgColor
		progressLayer.lineWidth = 3
		progressLayer.lineCap = .round
		progressLayer.strokeEnd = 0
		trackLayer.zPosition = 1
		progressLayer.zPosition = 2
		layer.addSublayer(trackLayer)
		layer.addSublayer(progressLayer)

		imageView.contentMode = .scaleAspectFill
		imageView.clipsToBounds = true
		imageView.layer.cornerRadius = 21
		imageView.translatesAutoresizingMaskIntoConstraints = false
		addSubview(imageView)

		fallbackLabel.font = UIFont.systemFont(ofSize: 22, weight: .semibold)
		fallbackLabel.textAlignment = .center
		fallbackLabel.textColor = BabelPalette.mutedInk
		fallbackLabel.backgroundColor = BabelPalette.raisedBackground
		fallbackLabel.clipsToBounds = true
		fallbackLabel.layer.cornerRadius = 21
		fallbackLabel.translatesAutoresizingMaskIntoConstraints = false
		addSubview(fallbackLabel)

		NSLayoutConstraint.activate([
			imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
			imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
			imageView.widthAnchor.constraint(equalToConstant: 42),
			imageView.heightAnchor.constraint(equalToConstant: 42),
			fallbackLabel.centerXAnchor.constraint(equalTo: imageView.centerXAnchor),
			fallbackLabel.centerYAnchor.constraint(equalTo: imageView.centerYAnchor),
			fallbackLabel.widthAnchor.constraint(equalTo: imageView.widthAnchor),
			fallbackLabel.heightAnchor.constraint(equalTo: imageView.heightAnchor)
		])
		updateLayerColors()
		NotificationCenter.default.addObserver(
			self,
			selector: #selector(accentDidChange),
			name: NNWAccentPalette.didChangeNotification,
			object: nil
		)
		registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: BabelReaderProgressIconView, _) in
			view.updateLayerColors()
		}
	}

	required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

	@objc private func accentDidChange() {
		updateLayerColors()
	}

	override func layoutSubviews() {
		super.layoutSubviews()
		let center = CGPoint(x: bounds.midX, y: bounds.midY)
		let path = UIBezierPath(
			arcCenter: center,
			radius: 22.5,
			startAngle: -.pi / 2,
			endAngle: .pi * 1.5,
			clockwise: true
		).cgPath
		trackLayer.frame = bounds
		progressLayer.frame = bounds
		trackLayer.path = path
		progressLayer.path = path
	}

	func configure(image: UIImage?, fallback: String) {
		imageView.image = image
		imageView.isHidden = image == nil
		fallbackLabel.text = fallback
		fallbackLabel.isHidden = image != nil
	}

	private func updateLayerColors() {
		trackLayer.strokeColor = BabelPalette.hairline.resolvedColor(with: traitCollection).cgColor
		progressLayer.strokeColor = BabelPalette.themeAccent.resolvedColor(with: traitCollection).cgColor
	}
}
