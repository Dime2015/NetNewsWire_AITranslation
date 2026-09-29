import UIKit
import UserNotifications
import Account

/// 把 App 图标角标设成用户在「设置 → 通知」里选的数字（Babel2BadgeMode，2026-09-29）。
///
/// - 全部未读：账户管理器现成的总数（与上游原来的角标一样）。
/// - 今日未读 / 今日有更新的源：与首页「今日未读」同一口径（最近 24 小时，`.today`），每次取一遍今天的文章来数；
///   「有更新的源」= 今天有文章的源的个数，不管读没读。
///
/// 上游 AppDelegate 在未读数变化、进前台、进后台时调用这里（原来那一行 setBadgeCount 换成了本函数）。
/// 同步时未读数会一串串地变：在前台攒 0.3 秒再算；进后台时立即算（之后 App 可能很快被挂起）。
@MainActor
enum Babel2AppBadge {
	private static var pending: Task<Void, Never>?
	private static var observer: NSObjectProtocol?

	static func update(allUnreadCount: Int) {
		observeModeChanges()
		pending?.cancel()
		let mode = Babel2BadgeMode.current
		guard mode != .allUnread else {
			setBadge(allUnreadCount)
			return
		}
		let waits = UIApplication.shared.applicationState == .active
		pending = Task { @MainActor in
			if waits { try? await Task.sleep(for: .milliseconds(300)) }
			guard !Task.isCancelled else { return }
			let count = await todayCount(mode)
			guard !Task.isCancelled else { return }
			setBadge(count)
		}
	}

	private static func todayCount(_ mode: Babel2BadgeMode) async -> Int {
		var unread = 0
		var feeds = Set<String>()
		for account in AccountManager.shared.sortedActiveAccounts {
			let articles = await account.fetchArticlesAsync(.today(nil))
			unread += articles.filter { !$0.status.read }.count
			for article in articles { feeds.insert("\(article.accountID)\u{1}\(article.feedID)") }
		}
		return mode == .todayUnread ? unread : feeds.count
	}

	private static func setBadge(_ count: Int) {
		UNUserNotificationCenter.current().setBadgeCount(count)
	}

	/// 在设置里换了选项：马上按新选项算一次。
	private static func observeModeChanges() {
		guard observer == nil else { return }
		observer = NotificationCenter.default.addObserver(forName: .babel2BadgeModeDidChange, object: nil, queue: .main) { _ in
			MainActor.assumeIsolated {
				update(allUnreadCount: AccountManager.shared.unreadCount)
			}
		}
	}
}
