import UIKit

@MainActor
final class Babel2NavigationController: UINavigationController, UIGestureRecognizerDelegate {
	var generation: Babel2Generation { .babel2 }
	private var ownsInteractivePopGesture = false
	private var didAppearAsContainer = false
	var onContainerAppeared: (() -> Void)?
	var routeFactory: ((Babel2RouteState) -> UIViewController?)?
	// [动效] M1 页面消费者：只接管左边缘滑动返回，见 Babel2NavigationPopMotion.swift。
	// internal (not private) so `@testable import` can drive it directly without
	// a live gesture recognizer/window.
	private(set) var popMotion: Babel2NavigationPopMotion?

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
		popMotion = Babel2NavigationPopMotion(navigationController: self)
	}

	/// 拆除时由装配层做的清理（例如移除通知观察）。
	var onTearDown: (() -> Void)?

	/// 设置里的配色模式（自动 / 浅色 / 深色）：由装配层提供，应用到整个窗口（含弹出的页面）。Slice 6。
	var interfaceStyleProvider: (() -> UIUserInterfaceStyle)? {
		didSet { applyInterfaceStyle() }
	}

	func applyInterfaceStyle() {
		guard let interfaceStyleProvider, let window = viewIfLoaded?.window else { return }
		window.overrideUserInterfaceStyle = interfaceStyleProvider()
	}

	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)
		applyInterfaceStyle()
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

	/// 用新页面原地替换栈顶（「下一篇」，ADR-022）：导航层数不变，看多少篇都只需一次返回。
	/// 动画（ADR-034，比原来整页上滑轻）：旧页上移 24pt 并淡出，新页从下方 40pt 升起，0.32 秒 ease-out。
	/// 旧页截图连同纸色底板盖在最上面整体淡出，新页在下面升起露出来；中途不透出系统底色。
	/// 减弱动态效果时没有位移，只交叉淡入。
	func replaceTopBabel2(with viewController: UIViewController, animated: Bool) {
		guard viewControllers.count > 1, let current = topViewController else {
			pushBabel2(viewController, animated: animated)
			return
		}
		var stack = viewControllers
		stack[stack.count - 1] = viewController
		let snapshot = animated && view.window != nil ? current.view.snapshotView(afterScreenUpdates: false) : nil
		setViewControllers(stack, animated: false)
		guard let snapshot else { return }
		view.layoutIfNeeded()
		let overlay = UIView(frame: view.bounds)
		overlay.backgroundColor = BabelPalette.background
		overlay.isUserInteractionEnabled = false
		snapshot.frame = current.view.frame
		overlay.addSubview(snapshot)
		view.addSubview(overlay)
		viewController.view.transform = CGAffineTransform(translationX: 0, y: Babel2Motion.offset(40))
		Babel2Motion.animate(Babel2Motion.page, {
			snapshot.transform = CGAffineTransform(translationX: 0, y: -Babel2Motion.offset(24))
			overlay.alpha = 0
			viewController.view.transform = .identity
		}, completion: { _ in
			overlay.removeFromSuperview()
			viewController.view.transform = .identity
		})
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
		popMotion?.tearDown()
		popMotion = nil
		onContainerAppeared = nil
		if let root = viewControllers.first as? Babel2RootViewController {
			root.onSettingsRequested = nil
			root.onAddRequested = nil
			root.onFeedRequested = nil
			root.cancelLibraryLoading()
			root.cancelContentFirstFramePresentation()
		}
		routeFactory = nil
		interfaceStyleProvider = nil
		onTearDown?()
		onTearDown = nil
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
