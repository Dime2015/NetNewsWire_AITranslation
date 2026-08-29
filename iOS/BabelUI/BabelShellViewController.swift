//
//  BabelShellViewController.swift
//  NetNewsWire
//

import UIKit

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
		guard viewControllers.count == 1 else { return }
		pushViewController(makeFeedsViewController(), animated: false)
	}

	func openTimelineForDebug() {
		guard viewControllers.count == 1 else { return }
		pushViewController(BabelTimelineViewController(section: .today), animated: false)
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
