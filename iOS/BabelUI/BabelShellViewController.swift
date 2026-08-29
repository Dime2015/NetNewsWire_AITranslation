//
//  BabelShellViewController.swift
//  NetNewsWire
//

import UIKit
import Account

final class BabelShellViewController: UINavigationController {

	var onOpenGenesisV2: (() -> Void)?
	var onOpenSubscribe: (() -> Void)?
	var onOpenSettings: (() -> Void)?

	override func viewDidLoad() {
		super.viewDidLoad()
		configureNavigation()
		installHome()
	}

	private func configureNavigation() {
		navigationBar.prefersLargeTitles = true
		navigationBar.preferredBehavioralStyle = .pad
		navigationBar.tintColor = BabelPalette.accent

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

	private func installHome() {
		guard viewControllers.isEmpty else { return }

		let homeViewController = BabelHomeViewController()
		homeViewController.onOpenSubscribe = { [weak self] in
			self?.onOpenSubscribe?()
		}
		homeViewController.onOpenSettings = { [weak self] in
			self?.onOpenSettings?()
		}
		homeViewController.onSelectSection = { [weak self] section in
			self?.pushViewController(BabelTimelineViewController(section: section), animated: true)
		}
		homeViewController.onOpenFeeds = { [weak self] in
			guard let self else { return }
			self.pushViewController(self.makeFeedsViewController(), animated: true)
		}
		homeViewController.onSelectArticle = { [weak self] article in
			self?.pushViewController(BabelReaderViewController(article: article), animated: true)
		}
		homeViewController.onOpenGenesisV2 = { [weak self] in
			self?.onOpenGenesisV2?()
		}
		setViewControllers([homeViewController], animated: false)
	}

	func openFeedsForDebug() {
		popToRootViewController(animated: false)
		pushViewController(makeFeedsViewController(), animated: false)
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

	func openFirstFeedReaderForDebug() {
		popToRootViewController(animated: false)
		let feed = AccountManager.shared.sortedActiveAccounts
			.flatMap { account in
				(account.topLevelFeeds + (account.folders ?? []).flatMap { $0.topLevelFeeds })
			}
			.sorted { $0.nameForDisplay < $1.nameForDisplay }
			.first
			.map(BabelTimelineViewController.init(feed:))
			?? BabelTimelineViewController(section: .today)
		pushViewController(feed, animated: false)
		DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { feed.openFirstArticleForDebug() }
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
		DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
			(self?.topViewController as? BabelReaderViewController)?.hideChromeForDebug()
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

	private func makeFeedsViewController() -> BabelFeedsViewController {
		let feedsViewController = BabelFeedsViewController()
		feedsViewController.onOpenSubscribe = { [weak self] in self?.onOpenSubscribe?() }
		feedsViewController.onOpenGenesisV2 = { [weak self] in self?.onOpenGenesisV2?() }
		feedsViewController.onSelectUnread = { [weak self] in
			self?.pushViewController(BabelTimelineViewController(section: .unread), animated: true)
		}
		feedsViewController.onSelectSaved = { [weak self] in
			self?.pushViewController(BabelTimelineViewController(section: .saved), animated: true)
		}
		feedsViewController.onSelectFolder = { [weak self] folder in
			self?.pushViewController(BabelTimelineViewController(folder: folder), animated: true)
		}
		feedsViewController.onSelectFeed = { [weak self] feed in
			self?.pushViewController(BabelTimelineViewController(feed: feed), animated: true)
		}
		return feedsViewController
	}
}
