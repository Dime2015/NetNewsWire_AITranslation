//
//  BabelShellViewController.swift
//  NetNewsWire
//

import UIKit

final class BabelShellViewController: UINavigationController {

	var onOpenGenesisV2: (() -> Void)?

	override func viewDidLoad() {
		super.viewDidLoad()
		configureNavigation()
		installHome()
	}

	private func configureNavigation() {
		navigationBar.prefersLargeTitles = true
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
		navigationBar.standardAppearance = appearance
		navigationBar.scrollEdgeAppearance = appearance
		navigationBar.compactAppearance = appearance
	}

	private func installHome() {
		guard viewControllers.isEmpty else { return }

		let homeViewController = BabelHomeViewController()
		homeViewController.onSelectSection = { [weak self] section in
			self?.pushViewController(BabelTimelineViewController(section: section), animated: true)
		}
		homeViewController.onSelectArticle = { [weak self] article in
			self?.pushViewController(BabelReaderViewController(article: article), animated: true)
		}
		homeViewController.onOpenGenesisV2 = { [weak self] in
			self?.onOpenGenesisV2?()
		}
		setViewControllers([homeViewController], animated: false)
	}
}
