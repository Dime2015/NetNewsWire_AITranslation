//
//  BabelShellConfigurationTests.swift
//  NetNewsWire-iOSTests
//

import Testing
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
}
