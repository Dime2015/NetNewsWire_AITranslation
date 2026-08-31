//
//  BabelShellConfigurationTests.swift
//  NetNewsWire-iOSTests
//

import Testing
import CoreGraphics
import UIKit
@testable import NetNewsWire

@Suite struct BabelShellConfigurationTests {

	@Test func defaultsToStoredPreference() {
		#expect(BabelShellConfiguration.resolve(arguments: [], environment: [:], storedValue: true))
		#expect(!BabelShellConfiguration.resolve(arguments: [], environment: [:], storedValue: false))
	}

	@Test func environmentOverridesStoredPreference() {
		#expect(BabelShellConfiguration.resolve(arguments: [], environment: ["BABEL_SHELL": "1"], storedValue: false))
		#expect(!BabelShellConfiguration.resolve(arguments: [], environment: ["BABEL_SHELL": "false"], storedValue: true))
	}

	@Test func shellLaunchArgumentHasHighestPriority() {
		#expect(BabelShellConfiguration.resolve(
			arguments: ["NetNewsWire", "-BabelShell"],
			environment: ["BABEL_SHELL": "0"],
			storedValue: false
		))
	}

	@Test func genesisLaunchArgumentHasHighestPriority() {
		#expect(!BabelShellConfiguration.resolve(
			arguments: ["NetNewsWire", "-GenesisV2"],
			environment: ["BABEL_SHELL": "1"],
			storedValue: true
		))
	}

	@Test @MainActor func startsDirectlyAtFeeds() {
		let shell = BabelShellViewController()
		shell.loadViewIfNeeded()

		#expect(shell.viewControllers.count == 1)
		#expect(shell.viewControllers.first is BabelFeedsViewController)
	}

	@Test @MainActor func feedsSettingsControlOpensFigmaSettingsFlow() {
		let shell = BabelShellViewController()
		shell.loadViewIfNeeded()
		let feeds = shell.viewControllers.first as? BabelFeedsViewController

		let control = feeds?.view.firstDescendant(withAccessibilityIdentifier: "babel.feeds.settings") as? UIControl
		#expect(control != nil)
		control?.sendActions(for: .touchUpInside)

		let settings = shell.topViewController as? BabelSettingsViewController
		#expect(settings != nil)
	}
}

private extension UIView {
	func firstDescendant(withAccessibilityIdentifier identifier: String) -> UIView? {
		if accessibilityIdentifier == identifier { return self }
		for subview in subviews {
			if let match = subview.firstDescendant(withAccessibilityIdentifier: identifier) { return match }
		}
		return nil
	}
}

@Suite struct BabelResponsivePopPolicyTests {

	@Test func onlyBeginsForRightwardEdgePanOnDeeperStack() {
		#expect(BabelResponsivePopPolicy.shouldBegin(
			stackDepth: 2,
			transitionInFlight: false,
			interactionInFlight: false,
			translation: CGPoint(x: 12, y: 2),
			velocity: CGPoint(x: 500, y: 40),
			currentLocationX: 75
		))
		#expect(!BabelResponsivePopPolicy.shouldBegin(
			stackDepth: 1,
			transitionInFlight: false,
			interactionInFlight: false,
			translation: CGPoint(x: 12, y: 2),
			velocity: CGPoint(x: 500, y: 40),
			currentLocationX: 75
		))
		#expect(!BabelResponsivePopPolicy.shouldBegin(
			stackDepth: 2,
			transitionInFlight: false,
			interactionInFlight: false,
			translation: CGPoint(x: 12, y: 18),
			velocity: CGPoint(x: 300, y: 600),
			currentLocationX: 75
		))
		#expect(!BabelResponsivePopPolicy.shouldBegin(
			stackDepth: 2,
			transitionInFlight: false,
			interactionInFlight: false,
			translation: CGPoint(x: 12, y: 2),
			velocity: CGPoint(x: 500, y: 40),
			currentLocationX: 83
		))
	}

	@Test func completionBalancesTravelAndIntentionalFlicks() {
		#expect(BabelResponsivePopPolicy.shouldFinish(progress: 0.33, velocityX: 100))
		#expect(BabelResponsivePopPolicy.shouldFinish(progress: 0.12, velocityX: 620))
		#expect(!BabelResponsivePopPolicy.shouldFinish(progress: 0.07, velocityX: 900))
		#expect(!BabelResponsivePopPolicy.shouldFinish(progress: 0.25, velocityX: 200))
	}
}

@Suite struct BabelOriginalLinkSwipePolicyTests {

	@Test func beginsOnlyForLeftwardHorizontalArticleGesture() {
		#expect(BabelOriginalLinkSwipePolicy.shouldBegin(
			hasOriginalURL: true,
			transitionInFlight: false,
			translation: CGPoint(x: -14, y: 2),
			velocity: CGPoint(x: -500, y: 20)
		))
		#expect(!BabelOriginalLinkSwipePolicy.shouldBegin(
			hasOriginalURL: false,
			transitionInFlight: false,
			translation: CGPoint(x: -14, y: 2),
			velocity: CGPoint(x: -500, y: 20)
		))
		#expect(!BabelOriginalLinkSwipePolicy.shouldBegin(
			hasOriginalURL: true,
			transitionInFlight: false,
			translation: CGPoint(x: -8, y: 16),
			velocity: CGPoint(x: -200, y: 500)
		))
		#expect(!BabelOriginalLinkSwipePolicy.shouldBegin(
			hasOriginalURL: true,
			transitionInFlight: false,
			translation: CGPoint(x: 14, y: 2),
			velocity: CGPoint(x: 500, y: 20)
		))
	}

	@Test func opensAfterMeaningfulTravelOrIntentionalFlick() {
		#expect(BabelOriginalLinkSwipePolicy.shouldOpen(translationX: -73, velocityX: -100))
		#expect(BabelOriginalLinkSwipePolicy.shouldOpen(translationX: -28, velocityX: -720))
		#expect(!BabelOriginalLinkSwipePolicy.shouldOpen(translationX: -20, velocityX: -900))
		#expect(!BabelOriginalLinkSwipePolicy.shouldOpen(translationX: -60, velocityX: -200))
	}
}
