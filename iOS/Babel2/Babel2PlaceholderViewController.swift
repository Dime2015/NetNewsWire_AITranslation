import Babel2Core
import UIKit

@MainActor
final class Babel2PlaceholderViewController: UIViewController {
	private let route: Babel2RouteState
	private let environment: AppEnvironment
	private let localizationBundle: Bundle
	private let titleLabel = UILabel()

	init(route: Babel2RouteState, environment: AppEnvironment, localizationBundle: Bundle = .main) {
		self.route = route
		self.environment = environment
		self.localizationBundle = localizationBundle
		super.init(nibName: nil, bundle: nil)
		restorationIdentifier = route == .settings ? "babel2.settings" : "babel2.add-subscription"
	}

	required init?(coder: NSCoder) {
		return nil
	}

	override func loadView() {
		let rootView = UIView()
		rootView.backgroundColor = .systemBackground
		rootView.isOpaque = true
		view = rootView
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		// Keep the narrow environment attached to the route for the next slice;
		// no global service lookup is introduced by the placeholder.
		_ = environment.settingsProvider
		titleLabel.text = route == .settings
			? Babel2Localization.text(.settings, bundle: localizationBundle)
			: Babel2Localization.text(.add, bundle: localizationBundle)
		titleLabel.font = .preferredFont(forTextStyle: .largeTitle)
		titleLabel.adjustsFontForContentSizeCategory = true
		titleLabel.textColor = .label
		titleLabel.textAlignment = .center
		titleLabel.accessibilityIdentifier = route == .settings ? "babel2.settings.title" : "babel2.add.title"
		view.addSubview(titleLabel)
		titleLabel.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			titleLabel.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
			titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 32),
			titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
			titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20)
		])
	}
}
