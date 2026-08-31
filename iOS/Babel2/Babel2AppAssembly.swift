import Babel2Core
import Babel2UI

/// App-facing seam for Babel 2.0. It exposes construction only; launch wiring is
/// intentionally deferred until the isolated UI has passed its own acceptance gates.
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
}
