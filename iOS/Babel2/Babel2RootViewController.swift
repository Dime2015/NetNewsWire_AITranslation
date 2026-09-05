import UIKit
import Babel2Core
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
		let scope: Babel2FeedScope
		let tableView = UITableView(frame: .zero, style: .plain)
		let stateLabel = UILabel()
		let retryButton = UIButton(type: .system)
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

			tableView.backgroundColor = BabelPalette.background
			tableView.backgroundView = nil
			tableView.separatorStyle = .none
			tableView.rowHeight = 44
			tableView.estimatedRowHeight = 44
			tableView.contentInsetAdjustmentBehavior = .never
			tableView.accessibilityIdentifier = "babel2.feeds.table.\(scope.rawValue)"
			tableView.accessibilityValue = SurfaceState.loading.rawValue
			tableView.translatesAutoresizingMaskIntoConstraints = false
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
	private let settingsButton = UIButton(type: .system)
	private let addButton = UIButton(type: .system)
	private let syncArrow = UIButton(type: .system)
	private let bottomBar = UIView()
	private let scopeStack = UIView()
	private let selectionPill = UIView()
	private var scopeButtons = [Babel2FeedScope: UIButton]()
	private var scopeSurfaces = [Babel2FeedScope: ScopeSurface]()
	private var libraryTasks = [Babel2FeedScope: Task<Void, Never>]()
	private var scopeTransitionAnimator: UIViewPropertyAnimator?
	private var scopeTransitionToken = UUID()
	private var presentationNeedsSettlement = false
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

	init(environment: AppEnvironment, localizationBundle: Bundle = .main) {
		self.environment = environment
		self.localizationBundle = localizationBundle
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
		layoutScopeControlsIfNeeded()
		scheduleContentFirstFrameOnNextDisplayTickIfReady()
	}

	private func layoutScopeControlsIfNeeded() {
		guard scopeTransitionAnimator == nil else { return }
		let order = Self.filterDisplayOrder
		let count = CGFloat(order.count)
		guard count > 0 else { return }
		let height = max(44, scopeStack.bounds.height)
		if scopeStack.bounds.width > 0 {
			// Figma-calibrated absolute centers for the real design width.
			let centers: [CGFloat] = [104, 201, 290.5]
			let width: CGFloat = 90
			for (index, scope) in order.enumerated() {
				guard let button = scopeButtons[scope] else { continue }
				let centerX = centers[index]
				button.frame = CGRect(x: centerX - width / 2, y: (height - 44) / 2, width: width, height: 44)
			}
		} else {
			// No measured width yet (e.g. a host that never attaches the view to a
			// window). Guarantee a valid >=44pt tappable rect instead of leaving
			// buttons at their zero-size initial frame; a later layout pass with a
			// real width replaces this with the calibrated centers above.
			let spacing: CGFloat = 8
			let width = max(44, (scopeStack.bounds.width - spacing * (count - 1)) / count)
			for (index, scope) in order.enumerated() {
				guard let button = scopeButtons[scope] else { continue }
				button.frame = CGRect(x: CGFloat(index) * (width + spacing), y: 0, width: width, height: height)
			}
		}
		updateScopeButtons()
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
			settingsButton.frame.width > 0,
			settingsButton.frame.height > 0,
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
			settingsButton.frame.width > 0,
			settingsButton.frame.height > 0,
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

		configureSymbolButton(settingsButton, symbolName: "gearshape", key: .settings, action: #selector(settingsTapped))
		configureSymbolButton(addButton, symbolName: "plus", key: .add, action: #selector(addTapped))
		configureScopeControls()
		syncArrow.setImage(UIImage(systemName: "arrow.triangle.2.circlepath"), for: .normal)
		syncArrow.tintColor = BabelPalette.mutedInk
		syncArrow.accessibilityLabel = "Syncing"
		syncArrow.accessibilityIdentifier = "babel2.sync.arrow"
		syncArrow.configuration = .plain()
		syncArrow.configuration?.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 19, weight: .regular)
		syncArrow.isHidden = true

		bottomBar.backgroundColor = BabelPalette.background
		bottomBar.isOpaque = true
		bottomBar.accessibilityIdentifier = "babel2.feeds.bottom-bar"
		let hairline = UIView()
		hairline.backgroundColor = BabelPalette.hairline
		hairline.translatesAutoresizingMaskIntoConstraints = false
		hairline.tag = 8_021
		bottomBar.addSubview(hairline)

		view.addSubview(titleLabel)
		view.addSubview(settingsButton)
		view.addSubview(addButton)
		view.addSubview(syncArrow)
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
		scopeStack.accessibilityIdentifier = "babel2.scope.controls"
		selectionPill.backgroundColor = BabelPalette.raisedBackground.withAlphaComponent(0.62)
		selectionPill.layer.cornerRadius = 13
		selectionPill.isUserInteractionEnabled = false
		selectionPill.accessibilityElementsHidden = true
		scopeStack.addSubview(selectionPill)
		for scope in Self.filterDisplayOrder {
			let button = UIButton(type: .system)
			button.configuration = .plain()
			button.setImage(Self.image(for: scope), for: .normal)
			button.tintColor = BabelPalette.ink
			button.accessibilityIdentifier = "babel2.scope.\(scope.rawValue)"
			button.accessibilityLabel = Babel2Localization.text(scope.localizationKey, bundle: localizationBundle)
			button.accessibilityTraits.insert(.button)
			button.addAction(UIAction { [weak self] _ in self?.scopeTapped(scope) }, for: .touchUpInside)
			button.backgroundColor = .clear
			button.translatesAutoresizingMaskIntoConstraints = true
			scopeStack.addSubview(button)
			scopeButtons[scope] = button
		}
		updateScopeButtons()
	}

	private static func image(for scope: Babel2FeedScope) -> UIImage? {
		let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .regular)
		switch scope {
		case .starred:
			return UIImage(systemName: "star", withConfiguration: config)
		case .unread:
			return UIImage(systemName: "circle.fill", withConfiguration: config)
		case .all:
			let renderer = UIGraphicsImageRenderer(size: CGSize(width: 24, height: 24))
			return renderer.image { _ in
				UIColor.black.setFill()
				for index in 0..<3 {
					let y = 5 + CGFloat(index) * 5
					let width = 18 - CGFloat(index) * 3
					UIBezierPath(roundedRect: CGRect(x: 3, y: y, width: width, height: 2), cornerRadius: 1).fill()
				}
			}.withRenderingMode(.alwaysTemplate)
		}
	}

	private func updateScopeButtons() {
		let symbol = UIImage.SymbolConfiguration(pointSize: 20, weight: .regular)
		for (scope, button) in scopeButtons {
			let isSelected = scope == displayedScope
			button.accessibilityValue = isSelected ? "Selected" : "Not selected"
			button.accessibilityTraits = isSelected ? [.button, .selected] : [.button]
			button.backgroundColor = .clear
			button.tintColor = BabelPalette.ink
			switch scope {
			case .starred:
				button.setImage(UIImage(systemName: isSelected ? "star.fill" : "star", withConfiguration: symbol), for: .normal)
			case .unread, .all:
				button.setImage(Self.image(for: scope), for: .normal)
			}
		}
		if let button = scopeButtons[displayedScope] {
			selectionPill.frame = button.frame.insetBy(dx: 6, dy: 9)
			selectionPill.layer.cornerRadius = min(selectionPill.bounds.height, 26) / 2
		}
	}

	private func configureSymbolButton(
		_ button: UIButton,
		symbolName: String,
		key: Babel2LocalizationKey,
		action: Selector
	) {
		button.setImage(UIImage(systemName: symbolName), for: .normal)
		button.tintColor = BabelPalette.mutedInk
		button.accessibilityLabel = Babel2Localization.text(key, bundle: localizationBundle)
		button.accessibilityIdentifier = key.accessibilityIdentifier
		button.configuration = .plain()
		button.configuration?.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 20, weight: .regular)
		button.addTarget(self, action: action, for: .touchUpInside)
		button.isOpaque = true
	}

	private func installLayout() {
		for item in [titleLabel, settingsButton, addButton, syncArrow, bottomBar, scopeStack] {
			item.translatesAutoresizingMaskIntoConstraints = false
		}
		for surface in scopeSurfaces.values {
			surface.translatesAutoresizingMaskIntoConstraints = false
		}
		let safeArea = view.safeAreaLayoutGuide
		var constraints = [NSLayoutConstraint]()
		constraints += [
			settingsButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
			settingsButton.topAnchor.constraint(equalTo: safeArea.topAnchor, constant: 0),
			settingsButton.widthAnchor.constraint(equalToConstant: 44),
			settingsButton.heightAnchor.constraint(equalToConstant: 44),
			addButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
			addButton.centerYAnchor.constraint(equalTo: settingsButton.centerYAnchor),
			addButton.widthAnchor.constraint(equalToConstant: 44),
			addButton.heightAnchor.constraint(equalToConstant: 44),
			syncArrow.centerXAnchor.constraint(equalTo: view.leadingAnchor, constant: 201),
			syncArrow.centerYAnchor.constraint(equalTo: settingsButton.centerYAnchor),
			syncArrow.widthAnchor.constraint(equalToConstant: 44),
			syncArrow.heightAnchor.constraint(equalToConstant: 44),
			titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
			titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
			titleLabel.topAnchor.constraint(equalTo: settingsButton.bottomAnchor, constant: 8),
			titleLabel.heightAnchor.constraint(equalToConstant: 43),
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
				surface.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
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
			syncArrow.layer.removeAnimation(forKey: "babel2.sync.rotation")
			return
		}
		syncArrow.isHidden = false
		guard syncArrow.layer.animation(forKey: "babel2.sync.rotation") == nil else { return }
		let animation = CABasicAnimation(keyPath: "transform.rotation.z")
		animation.fromValue = 0
		animation.toValue = CGFloat.pi * 2
		animation.duration = 1
		animation.repeatCount = .infinity
		syncArrow.layer.add(animation, forKey: "babel2.sync.rotation")
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
		let surfaces = Array(scopeSurfaces.values)
		for surface in surfaces {
			if let presentation = surface.layer.presentation() {
				surface.alpha = CGFloat(presentation.opacity)
				surface.transform = presentation.affineTransform()
			}
		}
		if let presentation = selectionPill.layer.presentation() {
			selectionPill.frame = presentation.frame
			selectionPill.transform = .identity
		}
		scopeTransitionToken = UUID()
		presentationNeedsSettlement = true
		animator.stopAnimation(true)
		scopeTransitionAnimator = nil
		for surface in surfaces {
			surface.layer.removeAllAnimations()
		}
		selectionPill.layer.removeAllAnimations()
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
		let sourceButton = scopeButtons[displayedScope]
		let destinationButton = scopeButtons[target]
		if let sourceButton, let destinationButton {
			if !presentationNeedsSettlement {
				selectionPill.frame = sourceButton.frame.insetBy(dx: 6, dy: 9)
				selectionPill.transform = .identity
			}
			let targetPillFrame = destinationButton.frame.insetBy(dx: 6, dy: 9)
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
				self.selectionPill.frame = targetPillFrame
				self.selectionPill.transform = .identity
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
				self.selectionPill.frame = targetPillFrame
				self.selectionPill.transform = .identity
				for surface in self.scopeSurfaces.values {
					surface.alpha = surface.scope == target ? 1 : 0
					surface.transform = .identity
				}
				self.applyActiveSurface(target)
				self.updateScopeButtons()
				self.updateSyncState(destinationSurface.isSyncing)
				destinationSurface.tableView.setContentOffset(.zero, animated: false)
				self.applyPendingSurfaceUpdates()
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
	private let chevronView = UIImageView()
	private let titleLabel = UILabel()
	private let countLabel = UILabel()
	private var toggleFolder: (() -> Void)?

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

		NSLayoutConstraint.activate([
			chevronView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 17),
			chevronView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
			chevronView.widthAnchor.constraint(equalToConstant: 14),
			chevronView.heightAnchor.constraint(equalToConstant: 14),
			iconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 32),
			iconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
			iconView.widthAnchor.constraint(equalToConstant: 19),
			iconView.heightAnchor.constraint(equalToConstant: 19),
			titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
			titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: countLabel.leadingAnchor, constant: -10),
			countLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -36),
			countLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
			countLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 28)
		])
	}

	required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

	func configureFolder(title: String, count: Int?, expanded: Bool, toggle: @escaping () -> Void) {
		toggleFolder = toggle
		titleLabel.text = title
		titleLabel.font = .systemFont(ofSize: 18, weight: .semibold)
		countLabel.text = count?.formatted()
		countLabel.isHidden = count == nil
		iconView.isHidden = true
		chevronView.isHidden = false
		chevronView.image = UIImage(
			systemName: expanded ? "chevron.down" : "chevron.right",
			withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
		)
		titleLabelLeading(to: 56)
	}

	func configureFeed(title: String, count: Int?, icon: UIImage?, nested: Bool) {
		toggleFolder = nil
		titleLabel.text = title
		titleLabel.font = .systemFont(ofSize: 17, weight: .medium)
		countLabel.text = count?.formatted()
		countLabel.isHidden = count == nil
		chevronView.isHidden = true
		iconView.isHidden = false
		iconView.image = icon ?? UIImage(systemName: "circle.fill")
		iconView.tintColor = BabelPalette.mutedInk
		let leading: CGFloat = nested ? 54 : 32
		iconView.constraints.filter { $0.firstAttribute == .leading }.forEach { $0.isActive = false }
		iconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: leading).isActive = true
		titleLabelLeading(to: leading + 27)
	}

	private func titleLabelLeading(to constant: CGFloat) {
		titleLabel.constraints.filter { $0.firstAttribute == .leading }.forEach { $0.isActive = false }
		contentView.constraints.filter {
			($0.firstItem as? UIView) === titleLabel && $0.firstAttribute == .leading
		}.forEach { $0.isActive = false }
		titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: constant).isActive = true
	}
}
