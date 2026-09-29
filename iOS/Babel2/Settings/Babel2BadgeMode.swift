import Foundation

/// App 图标角标显示什么（2026-09-29 用户要求：全部未读 / 今日未读 / 今日有更新的源，默认今日未读）。
/// 存在本机 UserDefaults；改了就发通知，由 Babel2AppBadge 重新算一次角标。
enum Babel2BadgeMode: String, CaseIterable {
	case allUnread
	case todayUnread
	case feedsUpdatedToday

	private static let defaultsKey = "babel2.appBadgeMode"

	static var current: Babel2BadgeMode {
		get { UserDefaults.standard.string(forKey: defaultsKey).flatMap(Self.init(rawValue:)) ?? .todayUnread }
		set {
			UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey)
			NotificationCenter.default.post(name: .babel2BadgeModeDidChange, object: nil)
		}
	}

	/// 设置页上显示的名字（Babel2Localizable 里的键）。
	var titleKey: String {
		switch self {
		case .allUnread: return "All Unread"
		case .todayUnread: return "Today's Unread"
		case .feedsUpdatedToday: return "Feeds Updated Today"
		}
	}
}

extension Notification.Name {
	static let babel2BadgeModeDidChange = Notification.Name("babel2BadgeModeDidChange")
}
