import UIKit

@MainActor
final class Babel2NavigationController: UINavigationController, UIGestureRecognizerDelegate {
	var generation: Babel2Generation { .babel2 }
	private var ownsInteractivePopGesture = false
	private var didAppearAsContainer = false
	var onContainerAppeared: (() -> Void)?
	var routeFactory: ((Babel2RouteState) -> UIViewController?)?

	override init(rootViewController: UIViewController) {
		super.init(rootViewController: rootViewController)
		restorationIdentifier = "babel2.navigation"
	}

	required init?(coder: NSCoder) {
		super.init(coder: coder)
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		navigationBar.isHidden = true
		view.backgroundColor = .systemBackground
		if let interactivePopGestureRecognizer {
			interactivePopGestureRecognizer.delegate = self
			ownsInteractivePopGesture = true
		}
	}

	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)
		guard !didAppearAsContainer,
			viewIfLoaded?.window != nil,
			view.bounds.width > 0,
			view.bounds.height > 0 else { return }
		didAppearAsContainer = true
		let callback = onContainerAppeared
		onContainerAppeared = nil
		callback?()
	}

	func pushBabel2(_ viewController: UIViewController, animated: Bool) {
		precondition(viewController !== self, "Babel2 navigation cannot push itself")
		pushViewController(viewController, animated: animated)
	}

	@discardableResult
	func popBabel2(animated: Bool) -> UIViewController? {
		guard viewControllers.count > 1 else { return nil }
		return popViewController(animated: animated)
	}

	/// Breaks the navigation/root ownership graph before a scene is replaced or
	/// disconnected. UIKit may otherwise keep a transition or gesture delegate
	/// alive until the next run-loop turn.
	func tearDown() {
		interactivePopGestureRecognizer?.delegate = nil
		onContainerAppeared = nil
		if let root = viewControllers.first as? Babel2RootViewController {
			root.onSettingsRequested = nil
			root.onAddRequested = nil
			root.onFeedRequested = nil
			root.cancelLibraryLoading()
			root.cancelContentFirstFramePresentation()
		}
		routeFactory = nil
		setViewControllers([], animated: false)
	}

	func restorationValue() -> Babel2NavigationRestoration {
		let routes = viewControllers.map { viewController -> Babel2RouteState in
			switch viewController.restorationIdentifier {
			case "babel2.settings": return .settings
			case "babel2.add-subscription": return .addSubscription
			default: return .home
			}
		}
		return Babel2NavigationRestoration(routes: routes.isEmpty ? [.home] : routes)
	}

	func applyRestoration(
		_ restoration: Babel2NavigationRestoration,
		routeFactory: ((Babel2RouteState) -> UIViewController?)? = nil
	) {
		let safeValue = restoration.safeValue
		guard let root = viewControllers.first else { return }
		var restoredViewControllers = [root]
		for route in safeValue.routes.dropFirst() {
			if let viewController = routeFactory?(route) {
				restoredViewControllers.append(viewController)
			}
		}
		setViewControllers(restoredViewControllers, animated: false)
	}

	func makeRestorationActivity() -> NSUserActivity {
		let activity = NSUserActivity(activityType: "babel2.navigation")
		if let data = try? restorationValue().encoded() {
			activity.addUserInfoEntries(from: ["babel2.restoration": data])
		}
		return activity
	}

	func restore(from activity: NSUserActivity?) {
		guard let data = activity?.userInfo?["babel2.restoration"] as? Data else { return }
		applyRestoration(Babel2NavigationRestoration.decoded(data), routeFactory: routeFactory)
	}

	func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
		guard ownsInteractivePopGesture, gestureRecognizer === interactivePopGestureRecognizer else { return false }
		return viewControllers.count > 1
	}
}
