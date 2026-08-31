//
//  BabelShellViewController.swift
//  NetNewsWire
//

import UIKit
import Account

final class BabelShellViewController: UINavigationController, UIGestureRecognizerDelegate, UINavigationControllerDelegate {

	var onOpenSubscribe: (() -> Void)?

	private let responsivePopAnimator = BabelResponsivePopAnimator()
	private var responsivePopInteraction: UIPercentDrivenInteractiveTransition?
	private lazy var responsivePopGestureRecognizer: UIPanGestureRecognizer = {
		let gesture = UIPanGestureRecognizer(target: self, action: #selector(handleResponsivePop(_:)))
		gesture.delegate = self
		gesture.maximumNumberOfTouches = 1
		gesture.cancelsTouchesInView = true
		return gesture
	}()

	override func viewDidLoad() {
		super.viewDidLoad()
		configureNavigation()
		installFeedsRoot()
	}

	private func configureNavigation() {
		delegate = self
		setNavigationBarHidden(true, animated: false)
		// The system edge recognizer only owns a very narrow strip and can lose
		// arbitration to table/web-view pans. Babel uses a public, interactive
		// 64pt edge pan instead so every pushed screen has the same reliable back
		// gesture without relying on a private navigation-transition selector.
		interactivePopGestureRecognizer?.isEnabled = false
		view.addGestureRecognizer(responsivePopGestureRecognizer)
		navigationBar.prefersLargeTitles = true
		navigationBar.preferredBehavioralStyle = .pad
		navigationBar.tintColor = BabelPalette.mutedInk

		let appearance = UINavigationBarAppearance()
		appearance.configureWithTransparentBackground()
		appearance.backgroundColor = BabelPalette.background
		appearance.shadowColor = .clear
		appearance.titleTextAttributes = [.foregroundColor: BabelPalette.ink]
		appearance.largeTitleTextAttributes = [
			.foregroundColor: BabelPalette.ink,
			.font: BabelTypography.display(size: 36)
		]
		let plainButtonAppearance = UIBarButtonItemAppearance(style: .plain)
		plainButtonAppearance.normal.backgroundImage = nil
		plainButtonAppearance.highlighted.backgroundImage = nil
		appearance.buttonAppearance = plainButtonAppearance
		appearance.backButtonAppearance = plainButtonAppearance
		navigationBar.standardAppearance = appearance
		navigationBar.scrollEdgeAppearance = appearance
		navigationBar.compactAppearance = appearance
	}

	func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
		guard gestureRecognizer === responsivePopGestureRecognizer,
			  let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
		return BabelResponsivePopPolicy.shouldBegin(
			stackDepth: viewControllers.count,
			transitionInFlight: transitionCoordinator != nil,
			interactionInFlight: responsivePopInteraction != nil,
			translation: pan.translation(in: view),
			velocity: pan.velocity(in: view),
			currentLocationX: pan.location(in: view).x
		)
	}

	func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
						   shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
		// A navigation transition and a row/web-view pan must never both own the
		// same touch stream; that produces the half-transition feeling reported
		// by the user. The explicit failure ordering installed below gives the
		// responsive pop priority only inside its 64pt activation region.
		gestureRecognizer !== responsivePopGestureRecognizer
	}

	func navigationController(_ navigationController: UINavigationController, didShow viewController: UIViewController, animated: Bool) {
		setNavigationBarHidden(!usesSystemNavigationBar(for: viewController), animated: false)
		responsivePopInteraction = nil
		prioritizeResponsivePopGesture(in: viewController.view)
	}

	func navigationController(_ navigationController: UINavigationController, willShow viewController: UIViewController, animated: Bool) {
		// Babel screens, including the Figma settings home and its first-level
		// categories, draw their own chrome. Existing specialized editors still
		// use UIKit navigation. Change bar state as part of the same transition.
		setNavigationBarHidden(!usesSystemNavigationBar(for: viewController), animated: animated)
	}

	func navigationController(_ navigationController: UINavigationController,
						  animationControllerFor operation: UINavigationController.Operation,
						  from fromVC: UIViewController,
						  to toVC: UIViewController) -> UIViewControllerAnimatedTransitioning? {
		guard operation == .pop, responsivePopInteraction != nil else { return nil }
		return responsivePopAnimator
	}

	func navigationController(_ navigationController: UINavigationController,
						  interactionControllerFor animationController: UIViewControllerAnimatedTransitioning)
		-> UIViewControllerInteractiveTransitioning? {
		responsivePopInteraction
	}

	@objc private func handleResponsivePop(_ gesture: UIPanGestureRecognizer) {
		let width = max(view.bounds.width, 1)
		let translationX = max(gesture.translation(in: view).x, 0)
		let progress = min(translationX / width, 1)

		switch gesture.state {
		case .began:
			let interaction = UIPercentDrivenInteractiveTransition()
			interaction.completionCurve = .easeOut
			interaction.wantsInteractiveStart = true
			responsivePopInteraction = interaction
			popViewController(animated: true)

		case .changed:
			responsivePopInteraction?.update(progress)

		case .ended:
			let velocityX = gesture.velocity(in: view).x
			let shouldFinish = BabelResponsivePopPolicy.shouldFinish(progress: progress, velocityX: velocityX)
			responsivePopInteraction?.completionSpeed = min(max(0.72 + abs(velocityX) / 2_400, 0.72), 1)
			if shouldFinish {
				responsivePopInteraction?.finish()
			} else {
				responsivePopInteraction?.cancel()
			}

		case .cancelled, .failed:
			responsivePopInteraction?.completionSpeed = 0.86
			responsivePopInteraction?.cancel()

		default:
			break
		}
	}

	private func prioritizeResponsivePopGesture(in rootView: UIView) {
		if let scrollView = rootView as? UIScrollView {
			scrollView.panGestureRecognizer.require(toFail: responsivePopGestureRecognizer)
		}
		for subview in rootView.subviews {
			prioritizeResponsivePopGesture(in: subview)
		}
	}

	private func usesSystemNavigationBar(for viewController: UIViewController) -> Bool {
		guard let settingsIndex = viewControllers.firstIndex(where: { $0 is BabelSettingsViewController }),
			  let viewControllerIndex = viewControllers.firstIndex(where: { $0 === viewController }) else {
			return false
		}
		return viewControllerIndex > settingsIndex && !(viewController is BabelSettingsCategoryViewController)
	}

	private func installFeedsRoot() {
		guard viewControllers.isEmpty else { return }
		setViewControllers([makeFeedsViewController()], animated: false)
	}

	func openFeedsForDebug() {
		popToRootViewController(animated: false)
	}

	func openFeedsAtTopForDebug() {
		popToRootViewController(animated: false)
		let feeds = makeFeedsViewController()
		feeds.debugInitialScrollOffset = 0
		feeds.debugExpandedFolderNames = ["财经", "旅行"]
		feeds.debugSelectedFeedName = "Marginal REVOLUTION"
		setViewControllers([feeds], animated: false)
	}

	func openFeedsStarredForDebug() {
		popToRootViewController(animated: false)
		let feeds = makeFeedsViewController()
		feeds.debugInitialScrollOffset = 0
		setViewControllers([feeds], animated: false)
		DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
			feeds.presentStarredFilterForDebug()
		}
	}

	func openFeedIssuesForDebug() {
		popToRootViewController(animated: false)
		let feeds = makeFeedsViewController()
		setViewControllers([feeds], animated: false)
		DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
			feeds.presentFeedIssuesForDebug()
		}
	}

	func openTimelineForDebug() {
		popToRootViewController(animated: false)
		pushViewController(BabelTimelineViewController(section: .today), animated: false)
	}

	func openFirstFeedTimelineForDebug() {
		popToRootViewController(animated: false)
		let feed = AccountManager.shared.sortedActiveAccounts
			.flatMap { account in
				(account.topLevelFeeds + (account.folders ?? []).flatMap { $0.topLevelFeeds })
			}
			.sorted { $0.nameForDisplay < $1.nameForDisplay }
			.first
		if let feed {
			pushViewController(BabelTimelineViewController(feed: feed), animated: false)
		} else {
			pushViewController(BabelTimelineViewController(section: .today), animated: false)
		}
	}

	func openFirstFeedTimelineCompactForDebug() {
		popToRootViewController(animated: false)
		let feed = AccountManager.shared.sortedActiveAccounts
			.flatMap { account in account.topLevelFeeds + (account.folders ?? []).flatMap { $0.topLevelFeeds } }
			.sorted { $0.nameForDisplay < $1.nameForDisplay }
			.first
		guard let feed else {
			openTimelineForDebug()
			return
		}
		// Use the complete feed so the table is tall enough to reach the real
		// compact-hero scroll position during screenshot verification.
		let timeline = BabelTimelineViewController(feed: feed, filter: .all)
		pushViewController(timeline, animated: false)
		DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { timeline.collapseFeedHeroForDebug() }
	}

	func openFirstFeedTimelineTranslationStressForDebug() {
		popToRootViewController(animated: false)
		let feed = AccountManager.shared.sortedActiveAccounts
			.flatMap { account in account.topLevelFeeds + (account.folders ?? []).flatMap { $0.topLevelFeeds } }
			.sorted { $0.nameForDisplay < $1.nameForDisplay }
			.first
		guard let feed else { return }
		let timeline = BabelTimelineViewController(feed: feed, filter: .all)
		pushViewController(timeline, animated: false)
		DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
			timeline.runTranslationScrollStressForDebug()
		}
	}

	func openFirstFeedReaderForDebug() {
		popToRootViewController(animated: false)
		let allFeeds: [Feed] = AccountManager.shared.sortedActiveAccounts
			.flatMap { account in
				(account.topLevelFeeds + (account.folders ?? []).flatMap { $0.topLevelFeeds })
			}
		let timeline: BabelTimelineViewController
		if let firstFeed = allFeeds.sorted(by: { $0.nameForDisplay < $1.nameForDisplay }).first {
			timeline = BabelTimelineViewController(feed: firstFeed)
		} else {
			timeline = BabelTimelineViewController(section: .today)
		}
		pushViewController(timeline, animated: false)
		DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { timeline.openFirstArticleForDebug() }
	}

	func openUnreadReaderForDebug() {
		popToRootViewController(animated: false)
		let timeline = BabelTimelineViewController(section: .unread)
		pushViewController(timeline, animated: false)
		DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { timeline.openFirstArticleForDebug() }
	}

	func openReaderForDebug() {
		// Device Hub can restore the previous navigation stack between launches.
		// Always reset it so the reader debug route is deterministic.
		popToRootViewController(animated: false)
		// Unread can legitimately be empty after a reader test marks an item read.
		// Use Today for the debug reader route so a current article remains available.
		let timeline = BabelTimelineViewController(section: .today)
		pushViewController(timeline, animated: false)
		DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { timeline.openFirstArticleForDebug() }
	}

	func openReaderMenuForDebug() {
		openReaderForDebug()
		DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
			(self?.topViewController as? BabelReaderViewController)?.presentActionsForDebug()
		}
	}

	func openReaderScrolledForDebug() {
		openReaderForDebug()
		DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { [weak self] in
			(self?.topViewController as? BabelReaderViewController)?.hideChromeForDebug()
		}
	}

	func openReaderPinnedUpForDebug() {
		openReaderForDebug()
		DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { [weak self] in
			(self?.topViewController as? BabelReaderViewController)?.showPinnedChromeForDebug()
		}
	}

	func openTimelineFilterForDebug() {
		guard viewControllers.count == 1 else { return }
		let timeline = BabelTimelineViewController(section: .today)
		pushViewController(timeline, animated: false)
		DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
			timeline.presentFilterForDebug()
		}
	}

	func openAddSubscriptionForDebug() {
		popToRootViewController(animated: false)
		pushViewController(BabelAddSubscriptionViewController(), animated: false)
	}

	func openSubscriptionManagementForDebug() {
		popToRootViewController(animated: false)
		pushViewController(BabelSubscriptionManagementViewController(), animated: false)
	}

	func openFeedDiscoveryForDebug() {
		popToRootViewController(animated: false)
		pushViewController(BabelFeedDiscoveryViewController(), animated: false)
	}

	func openSearchForDebug() {
		popToRootViewController(animated: false)
		let timeline = BabelTimelineViewController(section: .today)
		pushViewController(timeline, animated: false)
		DispatchQueue.main.asyncAfter(deadline: .now() + 1.25) {
			timeline.presentSearchForDebug()
		}
	}

	func openSettingsForDebug() {
		popToRootViewController(animated: false)
		showSettings(animated: false)
	}

	private func showSettings(animated: Bool = true) {
		guard !viewControllers.contains(where: { $0 is BabelSettingsViewController }) else { return }
		pushViewController(BabelSettingsViewController(), animated: animated)
	}

	private func makeFeedsViewController() -> BabelFeedsViewController {
		let feedsViewController = BabelFeedsViewController()
		feedsViewController.onOpenSubscribe = { [weak self] in
			self?.pushViewController(BabelAddSubscriptionViewController(), animated: true)
		}
		feedsViewController.onOpenSettings = { [weak self] in
			self?.showSettings()
		}
		feedsViewController.onSelectUnread = { [weak self] filter in
			self?.pushViewController(BabelTimelineViewController(section: .unread, filter: filter), animated: true)
		}
		feedsViewController.onSelectFolder = { [weak self] folder, filter in
			self?.pushViewController(BabelTimelineViewController(folder: folder, filter: filter), animated: true)
		}
		feedsViewController.onSelectFeed = { [weak self] feed, filter in
			self?.pushViewController(BabelTimelineViewController(feed: feed, filter: filter), animated: true)
		}
		return feedsViewController
	}
}

enum BabelResponsivePopPolicy {
	static let activationWidth: CGFloat = 64

	static func shouldBegin(
		stackDepth: Int,
		transitionInFlight: Bool,
		interactionInFlight: Bool,
		translation: CGPoint,
		velocity: CGPoint,
		currentLocationX: CGFloat
	) -> Bool {
		guard stackDepth > 1, !transitionInFlight, !interactionInFlight else { return false }
		let direction = abs(translation.x) + abs(translation.y) > 0.5 ? translation : velocity
		guard direction.x > 0, abs(direction.x) > abs(direction.y) * 1.08 else { return false }

		// UIKit asks after the finger has travelled a few points, so reconstruct
		// the touch-down coordinate instead of testing the current coordinate.
		let touchDownX = currentLocationX - translation.x
		return touchDownX <= activationWidth
	}

	static func shouldFinish(progress: CGFloat, velocityX: CGFloat) -> Bool {
		progress > 0.32 || (progress > 0.08 && velocityX > 500)
	}
}

/// Public-API interactive pop animator used by Babel's wider edge gesture.
/// The current page tracks the finger one-to-one; the previous page moves a
/// shorter distance underneath it, matching the depth cue of UIKit's native
/// navigation transition without depending on UIKit's private pop target.
private final class BabelResponsivePopAnimator: NSObject, UIViewControllerAnimatedTransitioning {

	func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
		0.34
	}

	func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
		guard let fromViewController = transitionContext.viewController(forKey: .from),
			  let toViewController = transitionContext.viewController(forKey: .to),
			  let fromView = transitionContext.view(forKey: .from) ?? fromViewController.view,
			  let toView = transitionContext.view(forKey: .to) ?? toViewController.view else {
			transitionContext.completeTransition(false)
			return
		}

		let container = transitionContext.containerView
		let width = max(container.bounds.width, 1)
		toView.frame = transitionContext.finalFrame(for: toViewController)
		toView.transform = CGAffineTransform(translationX: -width * 0.22, y: 0)
		toView.alpha = 0.96
		container.insertSubview(toView, belowSubview: fromView)

		let previousShadowColor = fromView.layer.shadowColor
		let previousShadowOpacity = fromView.layer.shadowOpacity
		let previousShadowRadius = fromView.layer.shadowRadius
		let previousShadowOffset = fromView.layer.shadowOffset
		fromView.layer.shadowColor = UIColor.black.cgColor
		fromView.layer.shadowOpacity = 0.16
		fromView.layer.shadowRadius = 12
		fromView.layer.shadowOffset = CGSize(width: -3, height: 0)

		UIView.animate(
			withDuration: transitionDuration(using: transitionContext),
			delay: 0,
			options: [.curveLinear, .allowUserInteraction]
		) {
			fromView.transform = CGAffineTransform(translationX: width, y: 0)
			toView.transform = .identity
			toView.alpha = 1
		} completion: { _ in
			let completed = !transitionContext.transitionWasCancelled
			fromView.transform = .identity
			toView.transform = .identity
			toView.alpha = 1
			fromView.layer.shadowColor = previousShadowColor
			fromView.layer.shadowOpacity = previousShadowOpacity
			fromView.layer.shadowRadius = previousShadowRadius
			fromView.layer.shadowOffset = previousShadowOffset
			transitionContext.completeTransition(completed)
		}
	}
}
