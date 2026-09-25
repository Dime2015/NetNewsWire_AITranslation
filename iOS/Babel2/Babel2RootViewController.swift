import UIKit
import Babel2Core
import Babel2UI
import QuartzCore

@MainActor
final class Babel2RootViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
	private enum SurfaceState: String {
		case loading
		case loaded
		case empty
		case error
	}

	private enum SurfaceUpdate {
		case snapshot(LibrarySnapshot)
		case error
	}

	private enum LibraryRow {
		case folder(FolderSnapshot, expanded: Bool)
		case feed(FeedSnapshot, nested: Bool)
	}

	private static let filterDisplayOrder: [Babel2FeedScope] = [.starred, .unread, .all]

	@MainActor
	private final class ScopeSurface: UIView {
		private static let listHeaderHeight: CGFloat = 150
		let scope: Babel2FeedScope
		let tableView = UITableView(frame: .zero, style: .plain)
		let stateLabel = UILabel()
		let retryButton = UIButton(type: .system)
		private let listHeader = UIView()
		private let shortRule = UIView()
		private let summaryTitleLabel = UILabel()
		private let summaryCountLabel = UILabel()
		private let foldersTitleLabel = UILabel()
		var rows = [LibraryRow]()
		var snapshot: LibrarySnapshot?
		var state: SurfaceState = .loading
		var hasLoaded = false
		var isSyncing = false
		var requestID = UUID()
		var pendingUpdate: (UUID, SurfaceUpdate)?
		var onRetry: (() -> Void)?

		init(scope: Babel2FeedScope, localizationBundle: Bundle) {
			self.scope = scope
			super.init(frame: .zero)
			backgroundColor = BabelPalette.background
			isOpaque = true
			accessibilityIdentifier = "babel2.feeds.surface.\(scope.rawValue)"

			listHeader.backgroundColor = BabelPalette.background
			listHeader.frame = CGRect(x: 0, y: 0, width: 0, height: Self.listHeaderHeight)
			shortRule.backgroundColor = BabelPalette.hairline
			shortRule.translatesAutoresizingMaskIntoConstraints = false
			listHeader.addSubview(shortRule)

			summaryTitleLabel.text = Babel2Localization.text(scope.localizationKey, bundle: localizationBundle)
			summaryTitleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
			summaryTitleLabel.textColor = BabelPalette.ink
			summaryTitleLabel.translatesAutoresizingMaskIntoConstraints = false
			listHeader.addSubview(summaryTitleLabel)

			summaryCountLabel.font = .systemFont(ofSize: 20, weight: .regular)
			summaryCountLabel.textColor = BabelPalette.tertiaryInk
			summaryCountLabel.textAlignment = .right
			summaryCountLabel.isHidden = true
			summaryCountLabel.translatesAutoresizingMaskIntoConstraints = false
			listHeader.addSubview(summaryCountLabel)

			foldersTitleLabel.text = Babel2Localization.text(.folders, bundle: localizationBundle)
			foldersTitleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
			foldersTitleLabel.textColor = BabelPalette.ink
			foldersTitleLabel.translatesAutoresizingMaskIntoConstraints = false
			listHeader.addSubview(foldersTitleLabel)

			NSLayoutConstraint.activate([
				shortRule.leadingAnchor.constraint(equalTo: listHeader.leadingAnchor, constant: 111),
				shortRule.topAnchor.constraint(equalTo: listHeader.topAnchor, constant: 2),
				shortRule.widthAnchor.constraint(equalToConstant: 180),
				shortRule.heightAnchor.constraint(equalToConstant: 0.5),
				summaryTitleLabel.leadingAnchor.constraint(equalTo: listHeader.leadingAnchor, constant: 20),
				summaryTitleLabel.topAnchor.constraint(equalTo: listHeader.topAnchor, constant: 31),
				summaryTitleLabel.heightAnchor.constraint(equalToConstant: 28),
				summaryTitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: summaryCountLabel.leadingAnchor, constant: -12),
				summaryCountLabel.trailingAnchor.constraint(equalTo: listHeader.trailingAnchor, constant: -20),
				summaryCountLabel.topAnchor.constraint(equalTo: summaryTitleLabel.topAnchor),
				summaryCountLabel.heightAnchor.constraint(equalToConstant: 28),
				summaryCountLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 92),
				foldersTitleLabel.leadingAnchor.constraint(equalTo: listHeader.leadingAnchor, constant: 20),
				foldersTitleLabel.topAnchor.constraint(equalTo: listHeader.topAnchor, constant: 99),
				foldersTitleLabel.heightAnchor.constraint(equalToConstant: 28)
			])

			tableView.backgroundColor = BabelPalette.background
			tableView.backgroundView = nil
			tableView.separatorStyle = .none
			tableView.rowHeight = 44
			tableView.estimatedRowHeight = 44
			tableView.contentInsetAdjustmentBehavior = .never
			tableView.accessibilityIdentifier = "babel2.feeds.table.\(scope.rawValue)"
			tableView.accessibilityValue = SurfaceState.loading.rawValue
			tableView.translatesAutoresizingMaskIntoConstraints = false
			tableView.tableHeaderView = listHeader
			addSubview(tableView)

			stateLabel.text = Babel2Localization.text(.loading, bundle: localizationBundle)
			stateLabel.accessibilityIdentifier = scope == .all ? "babel2.feeds.state" : "babel2.feeds.state.\(scope.rawValue)"
			stateLabel.accessibilityValue = SurfaceState.loading.rawValue
			stateLabel.font = .preferredFont(forTextStyle: .body)
			stateLabel.adjustsFontForContentSizeCategory = true
			stateLabel.textColor = BabelPalette.mutedInk
			stateLabel.textAlignment = .center
			stateLabel.isHidden = false
			stateLabel.translatesAutoresizingMaskIntoConstraints = false
			addSubview(stateLabel)

			retryButton.configuration = .plain()
			retryButton.setTitle(Babel2Localization.text(.retry, bundle: localizationBundle), for: .normal)
			retryButton.tintColor = BabelPalette.ink
			retryButton.accessibilityIdentifier = "babel2.feeds.retry.\(scope.rawValue)"
			retryButton.isHidden = true
			retryButton.translatesAutoresizingMaskIntoConstraints = false
			retryButton.addAction(UIAction { [weak self] _ in self?.onRetry?() }, for: .touchUpInside)
			addSubview(retryButton)

			NSLayoutConstraint.activate([
				tableView.leadingAnchor.constraint(equalTo: leadingAnchor),
				tableView.trailingAnchor.constraint(equalTo: trailingAnchor),
				tableView.topAnchor.constraint(equalTo: topAnchor),
				tableView.bottomAnchor.constraint(equalTo: bottomAnchor),
				stateLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
				stateLabel.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -20),
				stateLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
				stateLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24),
				retryButton.topAnchor.constraint(equalTo: stateLabel.bottomAnchor, constant: 8),
				retryButton.centerXAnchor.constraint(equalTo: centerXAnchor),
				retryButton.heightAnchor.constraint(equalToConstant: 44),
				retryButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 44)
			])
		}

		required init?(coder: NSCoder) { nil }

		override func layoutSubviews() {
			super.layoutSubviews()
			guard tableView.bounds.width > 0 else { return }
			let frame = CGRect(x: 0, y: 0, width: tableView.bounds.width, height: Self.listHeaderHeight)
			guard listHeader.frame != frame else { return }
			listHeader.frame = frame
			tableView.tableHeaderView = listHeader
		}

		func setSummaryCount(_ count: Int?) {
			let text = count.flatMap { $0 > 0 ? $0.formatted() : nil }
			summaryCountLabel.text = text
			summaryCountLabel.accessibilityValue = text
			summaryCountLabel.isHidden = text == nil
		}

		func setState(_ state: SurfaceState, text: String) {
			self.state = state
			accessibilityValue = state.rawValue
			tableView.accessibilityValue = state.rawValue
			stateLabel.accessibilityValue = state.rawValue
			stateLabel.text = text
			stateLabel.isHidden = state == .loaded
			retryButton.isHidden = state != .error
			tableView.isUserInteractionEnabled = state == .loaded
		}
	}

	let environment: AppEnvironment
	private let localizationBundle: Bundle
	private let titleLabel = UILabel()
	private let addButton = UIButton(type: .system)
	/// 左上角设置入口（Slice 6，2026-09-25 用户同意；与右上角「+」左右对称）。
	private let settingsButton = UIButton(type: .system)
	private let syncArrow = UIButton(type: .system)
	private let syncGlyph = BabelSyncGlyphView()
	private let syncSubtitleLabel = UILabel()
	private let bottomBar = UIView()
	/// 底部三档：与订阅源文章列表页共用同一组件（2026-09-25 修复切回「未读」时胶囊错位，用户选方案 A）。
	/// 按钮沿用原无障碍标识 babel2.scope.*；按钮外观与胶囊由组件负责，本页只负责切换列表内容。
	private lazy var scopeStack = Babel2ScopeFilterControl(
		selectedScope: selectedScope,
		identifierPrefix: "babel2.scope",
		controlIdentifier: "babel2.scope.controls",
		localizationBundle: localizationBundle
	)
	private var scopeSurfaces = [Babel2FeedScope: ScopeSurface]()
	private var libraryTasks = [Babel2FeedScope: Task<Void, Never>]()
	private var scopeTransitionAnimator: UIViewPropertyAnimator?
	private var scopeTransitionToken = UUID()
	private var presentationNeedsSettlement = false
	private let motionRecorder: any Babel2MotionRecording
	private var filterMotionSequence: UInt64 = 0
	private var activeFilterMotionToken: MotionInteractionToken?
	private var filterMotionFromScope: Babel2FeedScope?
	private var filterMotionToScope: Babel2FeedScope?
	private var collapsedFolders = Set<FolderSnapshot.ID>()
	private(set) var selectedScope: Babel2FeedScope = .unread
	private var displayedScope: Babel2FeedScope = .unread
	private var hasAppeared = false
	private var didAutoOpenFirstFeed = false
	private var didPresentContentFirstFrame = false
	private var contentFirstFrameDisplayLink: CADisplayLink?
	private var contentFirstFrameDisplayLinkTarget: DisplayLinkTarget?

	var onSettingsRequested: (() -> Void)?
	var onAddRequested: (() -> Void)?
	var onFeedRequested: ((FeedSnapshot, Babel2FeedScope) -> Void)?
	var onContentFirstFramePresented: (() -> Void)?

	@MainActor
	private final class DisplayLinkTarget: NSObject {
		weak var owner: Babel2RootViewController?

		init(owner: Babel2RootViewController) {
			self.owner = owner
		}

		@objc func displayLinkFired(_ displayLink: CADisplayLink) {
			owner?.presentContentFirstFrame(on: displayLink)
		}
	}

	init(
		environment: AppEnvironment,
		localizationBundle: Bundle = .main,
		motionRecorder: any Babel2MotionRecording = Babel2OSLogMotionRecorder()
	) {
		self.environment = environment
		self.localizationBundle = localizationBundle
		self.motionRecorder = motionRecorder
		super.init(nibName: nil, bundle: nil)
		restorationIdentifier = "babel2.home"
		NotificationCenter.default.addObserver(
			self,
			selector: #selector(libraryDidChange(_:)),
			name: .babel2LibraryDidChange,
			object: nil
		)
	}

	required init?(coder: NSCoder) {
		return nil
	}

	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)
		hasAppeared = true
		scheduleContentFirstFrameOnNextDisplayTickIfReady()
		applyLaunchScopeOverrideIfNeeded()
		loadLibraryIfNeeded()
	}

	/// Evidence/simctl-only override via `SIMCTL_CHILD_BABEL2_FEEDS_SCOPE=unread|starred|all`.
	private func applyLaunchScopeOverrideIfNeeded() {
		guard let raw = ProcessInfo.processInfo.environment["BABEL2_FEEDS_SCOPE"],
			let scope = Babel2FeedScope(rawValue: raw),
			scope != selectedScope else { return }
		selectedScope = scope
		displayedScope = scope
		for surface in scopeSurfaces.values {
			surface.alpha = surface.scope == scope ? 1 : 0
			surface.accessibilityElementsHidden = surface.scope != scope
		}
		updateScopeButtons()
		requestLibrary(for: scope, showLoading: true)
	}

	/// Evidence/simctl-only: `SIMCTL_CHILD_BABEL2_OPEN_FIRST_FEED=1` opens the first feed after load.
	private func openFirstFeedIfRequested(from surface: ScopeSurface) {
		guard !didAutoOpenFirstFeed else { return }
		guard ProcessInfo.processInfo.environment["BABEL2_OPEN_FIRST_FEED"] == "1" else { return }
		guard surface.scope == displayedScope else { return }
		guard let firstFeed = surface.rows.compactMap({ row -> FeedSnapshot? in
			if case .feed(let feed, _) = row { return feed }
			return nil
		}).first else { return }
		didAutoOpenFirstFeed = true
		onFeedRequested?(firstFeed, displayedScope)
	}

	override func viewDidDisappear(_ animated: Bool) {
		super.viewDidDisappear(animated)
		hasAppeared = false
		contentFirstFrameDisplayLink?.invalidate()
		contentFirstFrameDisplayLink = nil
		contentFirstFrameDisplayLinkTarget = nil
	}

	override func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)
		if isMovingFromParent {
			cancelLibraryLoading()
		}
	}

	deinit {
		libraryTasks.values.forEach { $0.cancel() }
	}

	@objc private func libraryDidChange(_ notification: Notification) {
		reloadLibraryIfVisible()
	}

	override func viewDidLayoutSubviews() {
		super.viewDidLayoutSubviews()
		if scopeTransitionAnimator == nil && !presentationNeedsSettlement {
			// 约束已经确定按钮位置；只在没有过渡时让 pill 对齐当前按钮。
			updateScopeButtons()
		}
		scheduleContentFirstFrameOnNextDisplayTickIfReady()
	}

	func cancelContentFirstFramePresentation() {
		contentFirstFrameDisplayLink?.invalidate()
		contentFirstFrameDisplayLink = nil
		contentFirstFrameDisplayLinkTarget = nil
		onContentFirstFramePresented = nil
	}

	func cancelLibraryLoading() {
		libraryTasks.values.forEach { $0.cancel() }
		libraryTasks.removeAll()
		scopeTransitionToken = UUID()
		scopeTransitionAnimator?.stopAnimation(true)
		scopeTransitionAnimator = nil
		presentationNeedsSettlement = false
	}

	private func scheduleContentFirstFrameOnNextDisplayTickIfReady() {
		guard hasAppeared,
			!didPresentContentFirstFrame,
			contentFirstFrameDisplayLink == nil,
			viewIfLoaded?.window != nil else { return }
		view.layoutIfNeeded()
		guard view.bounds.width > 0,
			view.bounds.height > 0,
			titleLabel.frame.width > 0,
			titleLabel.frame.height > 0,
			addButton.frame.width > 0,
			addButton.frame.height > 0 else { return }

		let target = DisplayLinkTarget(owner: self)
		contentFirstFrameDisplayLinkTarget = target
		let displayLink = CADisplayLink(target: target, selector: #selector(DisplayLinkTarget.displayLinkFired(_:)))
		contentFirstFrameDisplayLink = displayLink
		displayLink.add(to: .main, forMode: .common)
	}

	private func presentContentFirstFrame(on displayLink: CADisplayLink) {
		displayLink.invalidate()
		contentFirstFrameDisplayLink = nil
		contentFirstFrameDisplayLinkTarget = nil
		guard hasAppeared,
			!didPresentContentFirstFrame,
			viewIfLoaded?.window != nil,
			view.bounds.width > 0,
			view.bounds.height > 0,
			titleLabel.frame.width > 0,
			titleLabel.frame.height > 0,
			addButton.frame.width > 0,
			addButton.frame.height > 0 else { return }
		didPresentContentFirstFrame = true
		let callback = onContentFirstFramePresented
		onContentFirstFramePresented = nil
		callback?()
	}

	override func loadView() {
		let rootView = UIView()
		rootView.backgroundColor = BabelPalette.background
		rootView.isOpaque = true
		view = rootView
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		view.backgroundColor = BabelPalette.background
		view.isOpaque = true
		configureControls()
		configureScopeSurfaces()
		installLayout()
	}

	private func configureControls() {
		titleLabel.text = Babel2Localization.text(.feeds, bundle: localizationBundle)
		titleLabel.font = .systemFont(ofSize: 36, weight: .semibold)
		titleLabel.adjustsFontForContentSizeCategory = false
		titleLabel.textColor = BabelPalette.ink
		titleLabel.textAlignment = .center
		titleLabel.accessibilityIdentifier = Babel2LocalizationKey.feeds.accessibilityIdentifier

		addButton.setImage(UIImage(named: "BabelHomeAdd")?.withRenderingMode(.alwaysTemplate), for: .normal)
		addButton.tintColor = BabelPalette.mutedInk
		addButton.accessibilityLabel = Babel2Localization.text(.add, bundle: localizationBundle)
		addButton.accessibilityIdentifier = Babel2LocalizationKey.add.accessibilityIdentifier
		addButton.configuration = .plain()
		addButton.addTarget(self, action: #selector(addTapped), for: .touchUpInside)
		settingsButton.setImage(UIImage(systemName: "gearshape", withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .regular)), for: .normal)
		settingsButton.tintColor = BabelPalette.mutedInk
		settingsButton.accessibilityLabel = Babel2Localization.text(.settings, bundle: localizationBundle)
		settingsButton.accessibilityIdentifier = Babel2LocalizationKey.settings.accessibilityIdentifier
		settingsButton.configuration = .plain()
		settingsButton.addTarget(self, action: #selector(settingsTapped), for: .touchUpInside)
		configureScopeControls()
		syncArrow.configuration = .plain()
		syncArrow.accessibilityLabel = Babel2Localization.text(.syncing, bundle: localizationBundle)
		syncArrow.accessibilityIdentifier = "babel2.sync.arrow"
		syncArrow.isHidden = true
		syncGlyph.isAccessibilityElement = false
		syncGlyph.translatesAutoresizingMaskIntoConstraints = false
		syncArrow.addSubview(syncGlyph)
		NSLayoutConstraint.activate([
			syncGlyph.centerXAnchor.constraint(equalTo: syncArrow.centerXAnchor),
			syncGlyph.centerYAnchor.constraint(equalTo: syncArrow.centerYAnchor),
			syncGlyph.widthAnchor.constraint(equalToConstant: 24),
			syncGlyph.heightAnchor.constraint(equalToConstant: 24)
		])

		syncSubtitleLabel.font = .systemFont(ofSize: 16, weight: .medium)
		syncSubtitleLabel.textColor = BabelPalette.tertiaryInk
		syncSubtitleLabel.textAlignment = .center
		syncSubtitleLabel.accessibilityIdentifier = Babel2LocalizationKey.syncing.accessibilityIdentifier
		syncSubtitleLabel.isHidden = true
		syncSubtitleLabel.translatesAutoresizingMaskIntoConstraints = false

		bottomBar.backgroundColor = BabelPalette.background
		bottomBar.isOpaque = true
		bottomBar.accessibilityIdentifier = "babel2.feeds.bottom-bar"
		let hairline = UIView()
		hairline.backgroundColor = BabelPalette.hairline
		hairline.translatesAutoresizingMaskIntoConstraints = false
		hairline.tag = 8_021
		bottomBar.addSubview(hairline)

		view.addSubview(titleLabel)
		view.addSubview(addButton)
		view.addSubview(settingsButton)
		view.addSubview(syncArrow)
		view.addSubview(syncSubtitleLabel)
		view.addSubview(bottomBar)
		bottomBar.addSubview(scopeStack)
		NSLayoutConstraint.activate([
			hairline.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor),
			hairline.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor),
			hairline.topAnchor.constraint(equalTo: bottomBar.topAnchor),
			hairline.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale)
		])
	}

	private func configureScopeControls() {
		scopeStack.onSelect = { [weak self] scope in self?.scopeTapped(scope) }
	}

	/// 让组件显示当前的档位意图（切换期间以用户最后一次点的为准）。
	private func updateScopeButtons() {
		scopeStack.setSelectedScope(selectedScope, animated: false)
	}

	private func installLayout() {
		for item in [titleLabel, addButton, settingsButton, syncArrow, syncSubtitleLabel, bottomBar, scopeStack] {
			item.translatesAutoresizingMaskIntoConstraints = false
		}
		for surface in scopeSurfaces.values {
			surface.translatesAutoresizingMaskIntoConstraints = false
		}
		var constraints = [NSLayoutConstraint]()
		constraints += [
			addButton.centerXAnchor.constraint(equalTo: view.leadingAnchor, constant: 370),
			addButton.centerYAnchor.constraint(equalTo: view.topAnchor, constant: 81),
			addButton.widthAnchor.constraint(equalToConstant: 44),
			addButton.heightAnchor.constraint(equalToConstant: 44),
			settingsButton.centerXAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
			settingsButton.centerYAnchor.constraint(equalTo: view.topAnchor, constant: 81),
			settingsButton.widthAnchor.constraint(equalToConstant: 44),
			settingsButton.heightAnchor.constraint(equalToConstant: 44),
			syncArrow.centerXAnchor.constraint(equalTo: view.leadingAnchor, constant: 201),
			syncArrow.centerYAnchor.constraint(equalTo: view.topAnchor, constant: 81),
			syncArrow.widthAnchor.constraint(equalToConstant: 44),
			syncArrow.heightAnchor.constraint(equalToConstant: 44),
			titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
			titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
			titleLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 94),
			titleLabel.heightAnchor.constraint(equalToConstant: 43),
			syncSubtitleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
			syncSubtitleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
			syncSubtitleLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 135),
			syncSubtitleLabel.heightAnchor.constraint(equalToConstant: 22),
			bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			bottomBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
			bottomBar.heightAnchor.constraint(equalToConstant: 72),
			scopeStack.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor),
			scopeStack.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor),
			scopeStack.topAnchor.constraint(equalTo: bottomBar.topAnchor),
			scopeStack.heightAnchor.constraint(equalToConstant: 48)
		]
		for surface in scopeSurfaces.values {
			constraints += [
				surface.leadingAnchor.constraint(equalTo: view.leadingAnchor),
				surface.trailingAnchor.constraint(equalTo: view.trailingAnchor),
				surface.topAnchor.constraint(equalTo: view.topAnchor, constant: 184),
				surface.bottomAnchor.constraint(equalTo: bottomBar.topAnchor)
			]
		}
		NSLayoutConstraint.activate(constraints)
	}

	private func configureScopeSurfaces() {
		for scope in Babel2FeedScope.allCases {
			let surface = ScopeSurface(scope: scope, localizationBundle: localizationBundle)
			surface.tableView.dataSource = self
			surface.tableView.delegate = self
			surface.tableView.register(Babel2LibraryRowCell.self, forCellReuseIdentifier: Babel2LibraryRowCell.reuseIdentifier)
			surface.onRetry = { [weak self] in
				self?.retry(scope: scope)
			}
			surface.alpha = scope == .unread ? 1 : 0
			surface.accessibilityElementsHidden = scope != .unread
			view.insertSubview(surface, belowSubview: bottomBar)
			scopeSurfaces[scope] = surface
		}
	}

	private func loadLibraryIfNeeded() {
		guard let surface = scopeSurfaces[.unread], !surface.hasLoaded, libraryTasks[.unread] == nil else { return }
		requestLibrary(for: .unread, showLoading: true)
	}

	private func reloadLibraryIfVisible() {
		guard hasAppeared else { return }
		requestLibrary(for: displayedScope, showLoading: false)
	}

	private func retry(scope: Babel2FeedScope) {
		requestLibrary(for: scope, showLoading: true)
	}

	private func requestLibrary(for scope: Babel2FeedScope, showLoading: Bool) {
		guard let surface = scopeSurfaces[scope] else { return }
		let requestID = UUID()
		surface.requestID = requestID
		surface.hasLoaded = false
		libraryTasks[scope]?.cancel()
		if showLoading && surface.rows.isEmpty {
			surface.setState(.loading, text: Babel2Localization.text(.loading, bundle: localizationBundle))
		}
		let environment = self.environment
		libraryTasks[scope] = Task { @MainActor [weak self, environment, requestID, scope] in
			defer {
				if let self, self.scopeSurfaces[scope]?.requestID == requestID {
					self.libraryTasks[scope] = nil
				}
			}
			do {
				let snapshot = try await environment.dataProvider.librarySnapshot(for: scope)
				guard !Task.isCancelled, let self, self.hasAppeared,
					self.scopeSurfaces[scope]?.requestID == requestID else { return }
				self.publish(.snapshot(snapshot), for: scope, requestID: requestID)
			} catch is CancellationError {
				return
			} catch {
				guard !Task.isCancelled, let self, self.hasAppeared,
					self.scopeSurfaces[scope]?.requestID == requestID else { return }
				self.publish(.error, for: scope, requestID: requestID)
			}
		}
	}

	private func publish(_ update: SurfaceUpdate, for scope: Babel2FeedScope, requestID: UUID) {
		guard let surface = scopeSurfaces[scope], surface.requestID == requestID else { return }
		if scopeTransitionAnimator != nil {
			surface.pendingUpdate = (requestID, update)
			return
		}
		apply(update, to: surface)
		if scope == selectedScope, scope != displayedScope, surface.hasLoaded {
			startScopeTransition(to: scope)
		}
	}

	private func apply(_ update: SurfaceUpdate, to surface: ScopeSurface) {
		surface.pendingUpdate = nil
		switch update {
		case .snapshot(let snapshot):
			surface.snapshot = snapshot
			surface.rows = Self.makeRows(from: snapshot, scope: surface.scope, collapsedFolders: collapsedFolders)
			surface.hasLoaded = true
			surface.isSyncing = snapshot.isSyncing
			let summaryCount = snapshot.feeds.reduce(into: 0) { total, feed in
				guard !feed.isMuted else { return }
				let count = feed.articleCount ?? 0
				switch surface.scope {
				case .all:
					total += count
				case .unread, .starred:
					if count > 0 { total += count }
				}
			}
			surface.setSummaryCount(summaryCount)
			surface.tableView.reloadData()
			let state: SurfaceState = surface.rows.isEmpty ? .empty : .loaded
			let textKey: Babel2LocalizationKey = surface.rows.isEmpty ? .noFeeds : .loading
			surface.setState(state, text: Babel2Localization.text(textKey, bundle: localizationBundle))
			if surface.scope == displayedScope {
				updateSyncState(snapshot.isSyncing)
				openFirstFeedIfRequested(from: surface)
			}
		case .error:
			surface.snapshot = nil
			surface.rows.removeAll(keepingCapacity: true)
			surface.hasLoaded = true
			surface.isSyncing = false
			surface.setSummaryCount(nil)
			surface.tableView.reloadData()
			surface.setState(.error, text: Babel2Localization.text(.unableToLoadFeeds, bundle: localizationBundle))
			if surface.scope == displayedScope {
				updateSyncState(false)
			}
		}
	}

	private static func makeRows(
		from snapshot: LibrarySnapshot,
		scope: Babel2FeedScope,
		collapsedFolders: Set<FolderSnapshot.ID>
	) -> [LibraryRow] {
		func isVisible(_ feed: FeedSnapshot) -> Bool {
			guard !feed.isMuted else { return false }
			switch scope {
			case .all:
				return true
			case .unread, .starred:
				return (feed.articleCount ?? 0) > 0
			}
		}

		let feedsByID = Dictionary(uniqueKeysWithValues: snapshot.feeds.map { ($0.id, $0) })
		let nestedIDs = Set(snapshot.folders.flatMap(\.feedIDs))
		var rows = [LibraryRow]()
		for folder in snapshot.folders.sorted(by: { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }) {
			let childFeeds = folder.feedIDs.compactMap { feedsByID[$0] }.filter(isVisible)
			guard !childFeeds.isEmpty else { continue }
			let expanded = !collapsedFolders.contains(folder.id)
			rows.append(.folder(folder, expanded: expanded))
			if expanded {
				for feed in childFeeds.sorted(by: feedComesFirst) {
					rows.append(.feed(feed, nested: true))
				}
			}
		}
		let topLevel = snapshot.feeds
			.filter { isVisible($0) && !nestedIDs.contains($0.id) }
			.sorted(by: feedComesFirst)
		rows.append(contentsOf: topLevel.map { LibraryRow.feed($0, nested: false) })
		return rows
	}

	private static func feedComesFirst(_ lhs: FeedSnapshot, _ rhs: FeedSnapshot) -> Bool {
		let titleOrder = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
		guard titleOrder == .orderedSame else { return titleOrder == .orderedAscending }
		guard lhs.id.accountID == rhs.id.accountID else { return lhs.id.accountID < rhs.id.accountID }
		return lhs.id.feedID < rhs.id.feedID
	}

	private func updateSyncState(_ isSyncing: Bool) {
		if !isSyncing {
			syncArrow.isHidden = true
			syncSubtitleLabel.text = nil
			syncSubtitleLabel.isHidden = true
			syncGlyph.setSyncing(false)
			return
		}
		syncArrow.isHidden = false
		syncSubtitleLabel.text = Babel2Localization.text(.syncing, bundle: localizationBundle)
		syncSubtitleLabel.isHidden = false
		syncGlyph.setSyncing(true)
	}

	/// 仅供自动化测试：切换动画已结束、显示的档位就是最后点的档位。
	/// （按钮的「选中」样式现在一点就变，不能再当作「切换结束」的信号。）
	var isScopeTransitionSettledForTesting: Bool {
		scopeTransitionAnimator == nil && displayedScope == selectedScope
	}

	/// 档位是全局的：在订阅源文章列表里切了档位，返回首页时首页也换到同一档（ADR-023）。
	func applyScope(_ scope: Babel2FeedScope) {
		scopeStack.setSelectedScope(scope, animated: false)
		scopeTapped(scope)
	}

	private func scopeTapped(_ scope: Babel2FeedScope) {
		guard scope != selectedScope || scope != displayedScope else { return }
		let previousIntent = selectedScope
		if previousIntent != displayedScope, previousIntent != scope {
			invalidateLibraryRequest(for: previousIntent)
		}
		selectedScope = scope
		if scopeTransitionAnimator != nil {
			interruptScopeTransition()
		}
		guard let surface = scopeSurfaces[scope] else { return }
		if !surface.hasLoaded {
			requestLibrary(for: scope, showLoading: true)
			return
		}
		startScopeTransition(to: scope)
	}

	private func invalidateLibraryRequest(for scope: Babel2FeedScope) {
		guard let surface = scopeSurfaces[scope] else { return }
		surface.requestID = UUID()
		libraryTasks[scope]?.cancel()
		libraryTasks[scope] = nil
		surface.pendingUpdate = nil
	}

	private func interruptScopeTransition() {
		guard let animator = scopeTransitionAnimator else { return }
		if let token = activeFilterMotionToken, let from = filterMotionFromScope, let to = filterMotionToScope {
			recordFilterMotionEvent(
				token: token,
				from: from,
				to: to,
				progress: MotionProgress(Double(animator.fractionComplete)),
				phase: .event
			)
		}
		let surfaces = Array(scopeSurfaces.values)
		for surface in surfaces {
			if let presentation = surface.layer.presentation() {
				surface.alpha = CGFloat(presentation.opacity)
				surface.transform = presentation.affineTransform()
			}
		}
		scopeTransitionToken = UUID()
		presentationNeedsSettlement = true
		animator.stopAnimation(true)
		scopeTransitionAnimator = nil
		for surface in surfaces {
			surface.layer.removeAllAnimations()
		}
		applyActiveSurface(displayedScope)
	}

	private func startScopeTransition(to target: Babel2FeedScope) {
		let isSettlement = target == displayedScope && presentationNeedsSettlement
		guard (target != displayedScope || isSettlement),
			let sourceSurface = scopeSurfaces[displayedScope],
			let destinationSurface = scopeSurfaces[target],
			destinationSurface.hasLoaded,
			scopeTransitionAnimator == nil else { return }

		let token = UUID()
		scopeTransitionToken = token
		do {
			let fromScope = displayedScope
			filterMotionSequence &+= 1
			let motionToken = MotionInteractionToken(interaction: .libraryFilter, sequence: filterMotionSequence)
			activeFilterMotionToken = motionToken
			filterMotionFromScope = fromScope
			filterMotionToScope = target
			recordFilterMotionEvent(token: motionToken, from: fromScope, to: target, progress: .zero, phase: .begin)
			let direction: CGFloat = scopeIndex(target) >= scopeIndex(displayedScope) ? 1 : -1
			let offset: CGFloat = 12 * direction
			if !presentationNeedsSettlement {
				destinationSurface.alpha = 0
				destinationSurface.transform = CGAffineTransform(translationX: offset, y: 0)
			}
			destinationSurface.accessibilityElementsHidden = true
			destinationSurface.tableView.isUserInteractionEnabled = false
			sourceSurface.tableView.isUserInteractionEnabled = false
			let animator = UIViewPropertyAnimator(duration: 0.18, curve: .linear) { [weak self] in
				guard let self else { return }
				for surface in self.scopeSurfaces.values {
					if surface.scope == target {
						surface.alpha = 1
						surface.transform = .identity
					} else {
						let side: CGFloat = self.scopeIndex(surface.scope) < self.scopeIndex(target) ? -1 : 1
						surface.alpha = 0
						surface.transform = CGAffineTransform(translationX: 12 * side, y: 0)
					}
				}
			}
			scopeTransitionAnimator = animator
			animator.addCompletion { [weak self, weak animator] _ in
				guard let self, let animator,
					self.scopeTransitionAnimator === animator,
					self.scopeTransitionToken == token,
					self.selectedScope == target else { return }
				self.scopeTransitionAnimator = nil
				self.displayedScope = target
				self.presentationNeedsSettlement = false
				for surface in self.scopeSurfaces.values {
					surface.alpha = surface.scope == target ? 1 : 0
					surface.transform = .identity
				}
				self.applyActiveSurface(target)
				self.updateScopeButtons()
				self.updateSyncState(destinationSurface.isSyncing)
				destinationSurface.tableView.setContentOffset(.zero, animated: false)
				self.applyPendingSurfaceUpdates()
				if self.activeFilterMotionToken == motionToken {
					self.recordFilterMotionEvent(token: motionToken, from: fromScope, to: target, progress: .one, phase: .end)
					self.activeFilterMotionToken = nil
					self.filterMotionFromScope = nil
					self.filterMotionToScope = nil
				}
				if self.selectedScope != self.displayedScope,
					let next = self.scopeSurfaces[self.selectedScope], next.hasLoaded {
					self.startScopeTransition(to: self.selectedScope)
				}
			}
			animator.startAnimation()
		}
	}

	private func applyPendingSurfaceUpdates() {
		for surface in scopeSurfaces.values {
			guard let pending = surface.pendingUpdate,
				surface.requestID == pending.0 else { continue }
			apply(pending.1, to: surface)
		}
	}

	private func applyActiveSurface(_ scope: Babel2FeedScope) {
		for surface in scopeSurfaces.values {
			let active = surface.scope == scope
			surface.accessibilityElementsHidden = !active
			surface.tableView.isUserInteractionEnabled = active && surface.state == .loaded
		}
	}

	private func scopeIndex(_ scope: Babel2FeedScope) -> Int {
		Self.filterDisplayOrder.firstIndex(of: scope) ?? 0
	}

	/// [动效] pFilter 仪表化：`Babel2FeedScope` → `MotionLibraryFilter`，供
	/// `Babel2.Library.Filter` signpost 使用；两个枚举的原始值一一对应。
	private static func motionFilter(for scope: Babel2FeedScope) -> MotionLibraryFilter {
		switch scope {
		case .starred: return .starred
		case .unread: return .unread
		case .all: return .all
		}
	}

	/// [动效] 记录一次 `Babel2.Library.Filter` typed signpost。`phase` 语义：
	/// `.begin` = 全新过渡开始（pFilter=0）；`.event` = 被中途打断时的采样进度；
	/// `.end` = 真正结算完成（pFilter=1）。
	private func recordFilterMotionEvent(
		token: MotionInteractionToken,
		from: Babel2FeedScope,
		to: Babel2FeedScope,
		progress: MotionProgress,
		phase: MotionSignpostPhase
	) {
		motionRecorder.record(MotionSignpostEvent(
			payload: .libraryFilter(MotionLibraryFilterPayload(
				fromFilter: Self.motionFilter(for: from),
				toFilter: Self.motionFilter(for: to),
				pFilter: progress,
				token: token
			)),
			phase: phase
		))
	}

	@objc private func settingsTapped() {
		onSettingsRequested?() ?? presentNotAvailable()
	}

	@objc private func addTapped() {
		onAddRequested?() ?? presentNotAvailable()
	}

	private func presentNotAvailable() {
		let alert = UIAlertController(
			title: Babel2Localization.text(.feeds, bundle: localizationBundle),
			message: Babel2Localization.text(.notAvailable, bundle: localizationBundle),
			preferredStyle: .alert
		)
		alert.addAction(UIAlertAction(title: Babel2Localization.text(.ok, bundle: localizationBundle), style: .default))
		present(alert, animated: true)
	}

	private func toggleFolder(_ folderID: FolderSnapshot.ID) {
		if collapsedFolders.contains(folderID) {
			collapsedFolders.remove(folderID)
		} else {
			collapsedFolders.insert(folderID)
		}
		for surface in scopeSurfaces.values {
			guard let snapshot = surface.snapshot else { continue }
			surface.rows = Self.makeRows(from: snapshot, scope: surface.scope, collapsedFolders: collapsedFolders)
			surface.tableView.reloadData()
		}
	}

	func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		guard let surface = scopeSurfaces.values.first(where: { $0.tableView === tableView }) else { return 0 }
		return surface.rows.count
	}

	func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		let cell = tableView.dequeueReusableCell(withIdentifier: Babel2LibraryRowCell.reuseIdentifier, for: indexPath) as! Babel2LibraryRowCell
		guard let surface = scopeSurfaces.values.first(where: { $0.tableView === tableView }),
			indexPath.row < surface.rows.count else { return cell }
		switch surface.rows[indexPath.row] {
		case .folder(let folder, let expanded):
			let count = folder.articleCount.flatMap { $0 > 0 ? $0 : nil }
			cell.configureFolder(title: folder.title, count: count, expanded: expanded) { [weak self] in
				self?.toggleFolder(folder.id)
			}
			cell.accessibilityIdentifier = "babel2.folder.\(surface.scope.rawValue).\(folder.id)"
			cell.accessibilityLabel = folder.title
			cell.accessibilityValue = count.map(String.init)
		case .feed(let feed, let nested):
			let count = feed.articleCount.flatMap { $0 > 0 ? $0 : nil }
			let icon = feed.iconData.flatMap(UIImage.init(data:))
			cell.configureFeed(title: feed.title, count: count, icon: icon, nested: nested)
			cell.accessibilityIdentifier = "babel2.feed.\(surface.scope.rawValue).\(feed.id.accountID).\(feed.id.feedID)"
			cell.accessibilityLabel = feed.title
			cell.accessibilityValue = count.map(String.init)
		}
		return cell
	}

	func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		tableView.deselectRow(at: indexPath, animated: true)
		guard scopeTransitionAnimator == nil,
			let surface = scopeSurfaces.values.first(where: { $0.tableView === tableView }),
			surface.scope == displayedScope,
			indexPath.row < surface.rows.count else { return }
		switch surface.rows[indexPath.row] {
		case .folder(let folder, _):
			toggleFolder(folder.id)
		case .feed(let feed, _):
			onFeedRequested?(feed, displayedScope)
		}
	}
}

private final class Babel2LibraryRowCell: UITableViewCell {
	static let reuseIdentifier = "Babel2LibraryRowCell"
	private let iconView = UIImageView()
	private let initialsLabel = UILabel()
	private let chevronView = UIImageView()
	private let titleLabel = UILabel()
	private let countLabel = UILabel()
	private var toggleFolder: (() -> Void)?
	private var iconLeadingConstraint: NSLayoutConstraint!
	private var initialsLeadingConstraint: NSLayoutConstraint!
	private var titleLeadingConstraint: NSLayoutConstraint!
	private var countTrailingConstraint: NSLayoutConstraint!
	private var countWidthConstraint: NSLayoutConstraint!

	override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
		super.init(style: style, reuseIdentifier: reuseIdentifier)
		backgroundColor = .clear
		contentView.backgroundColor = .clear
		selectionStyle = .default
		let selection = UIView()
		selection.backgroundColor = BabelPalette.raisedBackground
		selection.layer.cornerRadius = 10
		selectedBackgroundView = selection

		iconView.contentMode = .scaleAspectFit
		iconView.layer.cornerRadius = 3
		iconView.clipsToBounds = true
		iconView.translatesAutoresizingMaskIntoConstraints = false
		contentView.addSubview(iconView)

		initialsLabel.font = .systemFont(ofSize: 10, weight: .medium)
		initialsLabel.textColor = BabelPalette.mutedInk
		initialsLabel.textAlignment = .center
		initialsLabel.translatesAutoresizingMaskIntoConstraints = false
		initialsLabel.isHidden = true
		contentView.addSubview(initialsLabel)

		chevronView.contentMode = .scaleAspectFit
		chevronView.tintColor = BabelPalette.mutedInk
		chevronView.translatesAutoresizingMaskIntoConstraints = false
		contentView.addSubview(chevronView)

		titleLabel.font = .systemFont(ofSize: 17, weight: .medium)
		titleLabel.textColor = BabelPalette.ink
		titleLabel.lineBreakMode = .byTruncatingTail
		titleLabel.translatesAutoresizingMaskIntoConstraints = false
		contentView.addSubview(titleLabel)

		countLabel.font = .systemFont(ofSize: 17, weight: .regular)
		countLabel.textColor = BabelPalette.tertiaryInk
		countLabel.textAlignment = .right
		countLabel.translatesAutoresizingMaskIntoConstraints = false
		contentView.addSubview(countLabel)

		iconLeadingConstraint = iconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 32)
		initialsLeadingConstraint = initialsLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 32)
		titleLeadingConstraint = titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 62)
		countTrailingConstraint = countLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20)
		countWidthConstraint = countLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 72)
		NSLayoutConstraint.activate([
			chevronView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 30),
			chevronView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
			chevronView.widthAnchor.constraint(equalToConstant: 18),
			chevronView.heightAnchor.constraint(equalToConstant: 18),
			iconLeadingConstraint,
			iconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
			iconView.widthAnchor.constraint(equalToConstant: 24),
			iconView.heightAnchor.constraint(equalToConstant: 24),
			initialsLeadingConstraint,
			initialsLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
			initialsLabel.widthAnchor.constraint(equalToConstant: 24),
			initialsLabel.heightAnchor.constraint(equalToConstant: 24),
			titleLeadingConstraint,
			titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
			titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: countLabel.leadingAnchor, constant: -12),
			countTrailingConstraint,
			countLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
			countWidthConstraint
		])
	}

	required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

	override func layoutSubviews() {
		super.layoutSubviews()
		selectedBackgroundView?.frame = bounds.insetBy(dx: 10, dy: 0)
	}

	override func setSelected(_ selected: Bool, animated: Bool) {
		super.setSelected(selected, animated: animated)
		initialsLabel.textColor = selected ? BabelPalette.ink : BabelPalette.mutedInk
	}

	func configureFolder(title: String, count: Int?, expanded: Bool, toggle: @escaping () -> Void) {
		toggleFolder = toggle
		selectionStyle = .default
		titleLabel.text = title
		titleLabel.font = .systemFont(ofSize: 18, weight: .semibold)
		countLabel.text = count?.formatted()
		countLabel.font = .systemFont(ofSize: 18, weight: .regular)
		countLabel.isHidden = count == nil
		iconView.isHidden = true
		iconView.image = nil
		initialsLabel.isHidden = true
		initialsLabel.text = nil
		initialsLabel.textColor = isSelected ? BabelPalette.ink : BabelPalette.mutedInk
		chevronView.isHidden = false
		chevronView.image = UIImage(
			systemName: expanded ? "chevron.down" : "chevron.right",
			withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
		)
		titleLeadingConstraint.constant = 56
		countTrailingConstraint.constant = -20
		countWidthConstraint.constant = 72
	}

	func configureFeed(title: String, count: Int?, icon: UIImage?, nested: Bool) {
		toggleFolder = nil
		selectionStyle = .default
		titleLabel.text = title
		titleLabel.font = .systemFont(ofSize: 17, weight: .medium)
		countLabel.text = count?.formatted()
		countLabel.font = .systemFont(ofSize: 17, weight: .regular)
		countLabel.isHidden = count == nil
		chevronView.isHidden = true
		chevronView.image = nil
		iconView.isHidden = false
		iconView.image = icon
		iconView.tintColor = BabelPalette.mutedInk
		let leading: CGFloat = nested ? 49 : 32
		iconLeadingConstraint.constant = leading
		initialsLeadingConstraint.constant = leading
		countTrailingConstraint.constant = -18
		countWidthConstraint.constant = 65
		titleLeadingConstraint.constant = nested ? 79 : 62
		initialsLabel.text = icon == nil ? Self.feedInitials(for: title) : nil
		initialsLabel.isHidden = icon != nil || initialsLabel.text?.isEmpty != false
		initialsLabel.textColor = isSelected ? BabelPalette.ink : BabelPalette.mutedInk
		iconView.isHidden = icon == nil
	}

	private static func feedInitials(for title: String) -> String {
		if title.lowercased().hasPrefix("www.") {
			let domain = title.dropFirst(4).split(separator: ".").first.map(String.init) ?? title
			return String(domain.prefix(1)).uppercased()
		}
		let characters = Array(title)
		if characters.contains(where: { $0.unicodeScalars.contains(where: { $0.value >= 0x3000 }) }) {
			return String(characters.prefix(2))
		}
		let tokens = title.split { !$0.isLetter && !$0.isNumber }.filter { !$0.isEmpty }
		if tokens.count >= 2 {
			return tokens.suffix(2).compactMap(\.first).map(String.init).joined().uppercased()
		}
		return tokens.first.map { String($0.prefix(2)).uppercased() } ?? ""
	}
}
