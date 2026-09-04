import Babel2Core
import Babel2UI

/// App-facing seam for Babel 2.0. The scene composition receives only narrow
/// Babel2Core collaborators; account and synchronization lifecycles remain outside.
public enum Babel2AppAssembly {
	public static let productName = Babel2Core.productName

	public static func makeEnvironment(
		dataProvider: any DataProviding,
		actionHandler: any ActionHandling,
		settingsProvider: any SettingsProviding,
		articleRenderer: any ArticleRendering,
		imageProvider: any ImageProviding
	) -> AppEnvironment {
		Babel2Assembly.makeEnvironment(
			dataProvider: dataProvider,
			actionHandler: actionHandler,
			settingsProvider: settingsProvider,
			articleRenderer: articleRenderer,
			imageProvider: imageProvider
		)
	}

	public static func initialNavigationState() -> NavigationState {
		NavigationState(path: [.home])
	}

	/// The app's production dependency graph. All account/database access stays
	/// behind Babel2 adapters; screens never reach into the legacy controller
	/// graph directly.
	@MainActor
	static func makeLiveEnvironment() -> AppEnvironment {
		Babel2Assembly.makeEnvironment(
			dataProvider: Babel2LiveDataProvider(),
			actionHandler: Babel2LiveActionHandler(),
			settingsProvider: Babel2LiveSettingsProvider(),
			articleRenderer: Babel2LiveArticleRenderer(),
			imageProvider: Babel2LiveImageProvider()
		)
	}

	static func makePreviewEnvironment() -> AppEnvironment {
		Babel2Assembly.makeEnvironment(
			dataProvider: Babel2EmptyDataProvider(),
			actionHandler: Babel2NoopActionHandler(),
			settingsProvider: Babel2DefaultSettingsProvider(),
			articleRenderer: Babel2PassthroughArticleRenderer(),
			imageProvider: Babel2EmptyImageProvider()
		)
	}
}
