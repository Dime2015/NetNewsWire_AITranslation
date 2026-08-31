import Foundation

public enum Route: Hashable, Sendable {
	case home
	case feed(FeedSnapshot.ID)
	case folder(FolderSnapshot.ID)
	case article(ArticleSnapshot.ID)
	case settings
}

/// A value-only navigation model. Platform navigation controllers are intentionally
/// outside this package and may consume this state later.
public struct NavigationState: Hashable, Sendable {
	public let path: [Route]

	public init(path: [Route] = []) {
		self.path = path
	}

	public var currentRoute: Route? {
		path.last
	}

	public func pushing(_ route: Route) -> NavigationState {
		NavigationState(path: path + [route])
	}

	public func popping() -> NavigationState {
		guard !path.isEmpty else { return self }
		return NavigationState(path: path.dropLast())
	}

	public func replacing(with route: Route) -> NavigationState {
		NavigationState(path: [route])
	}
}
