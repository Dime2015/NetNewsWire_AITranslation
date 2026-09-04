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

	@MainActor
	private final class ScopeSurface: UIView {
		let scope: Babel2FeedScope
		let tableView = UITableView(frame: .zero, style: .insetGrouped)
		let stateLabel = UILabel()
		let retryButton = UIButton(type: .system)
		var rows = [FeedSnapshot]()
		var state: SurfaceState = .loading
		var hasLoaded = false
		var isSyncing = false
		var requestID = UUID()
		var pendingUpdate: (UUID, SurfaceUpdate)?
		var onRetry: (() -> Void)?

		init(scope: Babel2FeedScope, localizationBundle: Bundle) {
			self.scope = scope
			super.init(frame: .zero)
			backgroundColor = .systemBackground
			isOpaque = true
			accessibilityIdentifier = "babel2.feeds.surface.\(scope.rawValue)"

			tableView.backgroundColor = .systemBackground
			tableView.backgroundView = nil
			tableView.separatorStyle = .singleLine
			tableView.rowHeight = 56
			tableView.accessibilityIdentifier = "babel2.feeds.table.\(scope.rawValue)"
			tableView.accessibilityValue = SurfaceState.loading.rawValue
			tableView.translatesAutoresizingMaskIntoConstraints = false
			addSubview(tableView)

			stateLabel.text = Babel2Localization.text(.loading, bundle: localizationBundle)
			stateLabel.accessibilityIdentifier = scope == .all ? "babel2.feeds.state" : "babel2.feeds.state.\(scope.rawValue)"
			stateLabel.accessibilityValue = SurfaceState.loading.rawValue
			stateLabel.font = .preferredFont(forTextStyle: .body)
			stateLabel.adjustsFontForContentSizeCategory = true
			stateLabel.textColor = .secondaryLabel
			stateLabel.textAlignment = .center
			stateLabel.isHidden = false
			stateLabel.translatesAutoresizingMaskIntoConstraints = false
			addSubview(stateLabel)

			retryButton.configuration = .plain()
			retryButton.setTitle(Babel2Localization.text(.retry, bundle: localizationBundle), for: .normal)
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
	private let scopeStack = UIView()
	private let selectionPill = UIView()
	private var scopeButtons = [Babel2FeedScope: UIButton]()
	private var scopeSurfaces = [Babel2FeedScope: ScopeSurface]()
	private var libraryTasks = [Babel2FeedScope: Task<Void, Never>]()
	private var scopeTransitionAnimator: UIViewPropertyAnimator?
	private var scopeTransitionToken = UUID()
	private var presentationNeedsSettlement = false
	private(set) var selectedScope: Babel2FeedScope = .all
	private var displayedScope: Babel2FeedScope = .all
	private var hasAppeared = false
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
		loadLibraryIfNeeded()
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
		let count = CGFloat(scopeButtons.count)
		guard count > 0 else { return }
		let spacing: CGFloat = 8
		let width = max(44, (scopeStack.bounds.width - spacing * (count - 1)) / count)
		let height = max(44, scopeStack.bounds.height)
		for (index, scope) in Babel2FeedScope.allCases.enumerated() {
			guard let button = scopeButtons[scope] else { continue }
			button.frame = CGRect(x: CGFloat(index) * (width + spacing), y: 0, width: width, height: height)
		}
		updateScopeButtons()
	}

	/// Cancels the one-shot display tick when the owning scene tears down. The
	/// generation token in the owning scene additionally rejects a stale callback.
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
		rootView.backgroundColor = .systemBackground
		rootView.isOpaque = true
		view = rootView
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		view.backgroundColor = .systemBackground
		view.isOpaque = true
		configureControls()
		configureScopeSurfaces()
		installLayout()
	}

	private func configureControls() {
		titleLabel.text = Babel2Localization.text(.feeds, bundle: localizationBundle)
		titleLabel.font = .preferredFont(forTextStyle: .largeTitle)
		titleLabel.adjustsFontForContentSizeCategory = true
		titleLabel.textColor = .label
		titleLabel.textAlignment = .center
		titleLabel.accessibilityIdentifier = Babel2LocalizationKey.feeds.accessibilityIdentifier

		configureSymbolButton(settingsButton, symbolName: "gearshape", key: .settings, action: #selector(settingsTapped))
		configureSymbolButton(addButton, symbolName: "plus", key: .add, action: #selector(addTapped))
		configureScopeControls()
		syncArrow.setImage(UIImage(systemName: "arrow.triangle.2.circlepath"), for: .normal)
		syncArrow.tintColor = .label
		syncArrow.accessibilityLabel = "Syncing"
		syncArrow.accessibilityIdentifier = "babel2.sync.arrow"
		syncArrow.configuration = .plain()
		syncArrow.configuration?.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 19, weight: .regular)
		syncArrow.isHidden = true
		view.addSubview(titleLabel)
		view.addSubview(settingsButton)
		view.addSubview(addButton)
		view.addSubview(scopeStack)
		view.addSubview(syncArrow)
	}

	private func configureScopeControls() {
		scopeStack.accessibilityIdentifier = "babel2.scope.controls"
		selectionPill.backgroundColor = .secondarySystemBackground
		selectionPill.layer.cornerRadius = 12
		selectionPill.isUserInteractionEnabled = false
		selectionPill.accessibilityElementsHidden = true
		scopeStack.addSubview(selectionPill)
		for scope in Babel2FeedScope.allCases {
			let button = UIButton(type: .system)
			button.configuration = .plain()
			button.setImage(Self.image(for: scope), for: .normal)
			button.tintColor = .label
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
		if scope == .all {
			let renderer = UIGraphicsImageRenderer(size: CGSize(width: 24, height: 24))
			return renderer.image { context in
				UIColor.label.setFill()
				for index in 0..<4 {
					let y = 2 + CGFloat(index) * 5.5
					UIBezierPath(roundedRect: CGRect(x: 3, y: y, width: 18, height: 2), cornerRadius: 1).fill()
				}
			}.withRenderingMode(.alwaysTemplate)
		}
		return UIImage(systemName: scope == .unread ? "circle.fill" : "star")
	}

	private func updateScopeButtons() {
		for (scope, button) in scopeButtons {
			let isSelected = scope == displayedScope
			button.accessibilityValue = isSelected ? "Selected" : "Not selected"
			button.accessibilityTraits = isSelected ? [.button, .selected] : [.button]
			button.backgroundColor = .clear
		}
		if let button = scopeButtons[displayedScope] {
			selectionPill.frame = button.frame.insetBy(dx: 2, dy: 2)
			selectionPill.layer.cornerRadius = min(selectionPill.bounds.height, 24) / 2
		}
	}

	private func configureSymbolButton(
		_ button: UIButton,
		symbolName: String,
		key: Babel2LocalizationKey,
		action: Selector
	) {
		button.setImage(UIImage(systemName: symbolName), for: .normal)
		button.tintColor = .label
		button.accessibilityLabel = Babel2Localization.text(key, bundle: localizationBundle)
		button.accessibilityIdentifier = key.accessibilityIdentifier
		button.configuration = .plain()
		button.configuration?.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 20, weight: .regular)
		button.addTarget(self, action: action, for: .touchUpInside)
		button.isOpaque = true
	}

	private func installLayout() {
		for item in [titleLabel, settingsButton, addButton, syncArrow, scopeStack] {
			item.translatesAutoresizingMaskIntoConstraints = false
		}
		for surface in scopeSurfaces.values {
			surface.translatesAutoresizingMaskIntoConstraints = false
		}
		let safeArea = view.safeAreaLayoutGuide
		var constraints = [NSLayoutConstraint]()
		constraints += [
			titleLabel.centerXAnchor.constraint(equalTo: safeArea.centerXAnchor),
			titleLabel.topAnchor.constraint(equalTo: safeArea.topAnchor, constant: 28),
			settingsButton.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor, constant: 16),
			settingsButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
			settingsButton.widthAnchor.constraint(equalToConstant: 44),
			settingsButton.heightAnchor.constraint(equalToConstant: 44),
			addButton.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor, constant: -16),
			addButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
			addButton.widthAnchor.constraint(equalToConstant: 44),
			addButton.heightAnchor.constraint(equalToConstant: 44),
			scopeStack.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor, constant: 16),
			scopeStack.trailingAnchor.constraint(lessThanOrEqualTo: syncArrow.leadingAnchor, constant: -8),
			scopeStack.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
			scopeStack.heightAnchor.constraint(equalToConstant: 44),
			syncArrow.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor, constant: -16),
			syncArrow.centerYAnchor.constraint(equalTo: scopeStack.centerYAnchor),
			syncArrow.widthAnchor.constraint(equalToConstant: 44),
			syncArrow.heightAnchor.constraint(equalToConstant: 44)
		]
		for surface in scopeSurfaces.values {
			constraints += [
				surface.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor),
				surface.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor),
				surface.topAnchor.constraint(equalTo: scopeStack.bottomAnchor, constant: 8),
				surface.bottomAnchor.constraint(equalTo: safeArea.bottomAnchor)
			]
		}
		NSLayoutConstraint.activate(constraints)
	}

	private func configureScopeSurfaces() {
		for scope in Babel2FeedScope.allCases {
			let surface = ScopeSurface(scope: scope, localizationBundle: localizationBundle)
			surface.tableView.dataSource = self
			surface.tableView.delegate = self
			surface.tableView.register(UITableViewCell.self, forCellReuseIdentifier: Self.feedCellReuseIdentifier)
			surface.onRetry = { [weak self] in
				self?.retry(scope: scope)
			}
			surface.alpha = scope == .all ? 1 : 0
			surface.accessibilityElementsHidden = scope != .all
			view.addSubview(surface)
			scopeSurfaces[scope] = surface
		}
	}

	private func loadLibraryIfNeeded() {
		guard let surface = scopeSurfaces[.all], !surface.hasLoaded, libraryTasks[.all] == nil else { return }
		requestLibrary(for: .all, showLoading: true)
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
			surface.rows = snapshot.feeds
				.filter { !$0.isMuted && ($0.articleCount ?? 0) > 0 }
				.sorted(by: Self.feedComesFirst)
			surface.hasLoaded = true
			surface.isSyncing = snapshot.isSyncing
			surface.tableView.reloadData()
			let state: SurfaceState = surface.rows.isEmpty ? .empty : .loaded
			let textKey: Babel2LocalizationKey = surface.rows.isEmpty ? .noFeeds : .loading
			surface.setState(state, text: Babel2Localization.text(textKey, bundle: localizationBundle))
			if surface.scope == displayedScope {
				updateSyncState(snapshot.isSyncing)
			}
		case .error:
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
				selectionPill.frame = sourceButton.frame.insetBy(dx: 2, dy: 2)
				selectionPill.transform = .identity
			}
			let targetPillFrame = destinationButton.frame.insetBy(dx: 2, dy: 2)
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
		Babel2FeedScope.allCases.firstIndex(of: scope) ?? 0
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

	func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		guard let surface = scopeSurfaces.values.first(where: { $0.tableView === tableView }) else { return 0 }
		return surface.rows.count
	}

	func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		let cell = tableView.dequeueReusableCell(withIdentifier: Self.feedCellReuseIdentifier, for: indexPath)
		guard let surface = scopeSurfaces.values.first(where: { $0.tableView === tableView }),
			indexPath.row < surface.rows.count else { return cell }
		let feed = surface.rows[indexPath.row]
		var content = cell.defaultContentConfiguration()
		content.text = feed.title
		content.secondaryText = feed.articleCount.map { $0.formatted() }
		content.image = feed.iconData.flatMap(UIImage.init(data:)) ?? UIImage(systemName: "circle")
		content.imageProperties.maximumSize = CGSize(width: 28, height: 28)
		content.textProperties.font = .preferredFont(forTextStyle: .body)
		content.secondaryTextProperties.font = .preferredFont(forTextStyle: .footnote)
		content.secondaryTextProperties.color = .secondaryLabel
		cell.contentConfiguration = content
		cell.accessibilityIdentifier = "babel2.feed.\(surface.scope.rawValue).\(feed.id.accountID).\(feed.id.feedID)"
		cell.accessibilityLabel = feed.title
		cell.accessibilityValue = feed.articleCount.map { String($0) }
		return cell
	}

	func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		tableView.deselectRow(at: indexPath, animated: true)
		guard scopeTransitionAnimator == nil,
			let surface = scopeSurfaces.values.first(where: { $0.tableView === tableView }),
			surface.scope == displayedScope,
			indexPath.row < surface.rows.count else { return }
		onFeedRequested?(surface.rows[indexPath.row], displayedScope)
	}

	private static let feedCellReuseIdentifier = "Babel2FeedCell"
}
