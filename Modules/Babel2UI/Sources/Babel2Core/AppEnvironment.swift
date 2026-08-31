import Foundation

/// All collaborators are supplied at construction time. There is deliberately no
/// global default, shared instance, or lookup into the legacy application shell.
public struct AppEnvironment: Sendable {
	public let dataProvider: any DataProviding
	public let actionHandler: any ActionHandling
	public let settingsProvider: any SettingsProviding
	public let articleRenderer: any ArticleRendering
	public let imageProvider: any ImageProviding

	public init(
		dataProvider: any DataProviding,
		actionHandler: any ActionHandling,
		settingsProvider: any SettingsProviding,
		articleRenderer: any ArticleRendering,
		imageProvider: any ImageProviding
	) {
		self.dataProvider = dataProvider
		self.actionHandler = actionHandler
		self.settingsProvider = settingsProvider
		self.articleRenderer = articleRenderer
		self.imageProvider = imageProvider
	}
}

public enum Babel2Assembly {
	public static func makeEnvironment(
		dataProvider: any DataProviding,
		actionHandler: any ActionHandling,
		settingsProvider: any SettingsProviding,
		articleRenderer: any ArticleRendering,
		imageProvider: any ImageProviding
	) -> AppEnvironment {
		AppEnvironment(
			dataProvider: dataProvider,
			actionHandler: actionHandler,
			settingsProvider: settingsProvider,
			articleRenderer: articleRenderer,
			imageProvider: imageProvider
		)
	}
}
