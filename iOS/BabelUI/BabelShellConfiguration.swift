//
//  BabelShellConfiguration.swift
//  NetNewsWire
//
//  The new Babel interface stays opt-in until each migration stage is accepted.
//

import Foundation

enum BabelShellConfiguration {

	static let defaultsKey = "BabelShellEnabled"
	static let environmentKey = "BABEL_SHELL"

	static var isEnabled: Bool {
#if DEBUG
		return resolve(
			arguments: ProcessInfo.processInfo.arguments,
			environment: ProcessInfo.processInfo.environment,
			storedValue: UserDefaults.standard.bool(forKey: defaultsKey)
		)
#else
		return false
#endif
	}

	static func resolve(arguments: [String], environment: [String: String], storedValue: Bool) -> Bool {
		if arguments.contains("-BabelShell") {
			return true
		}

		if arguments.contains("-GenesisV2") {
			return false
		}

		if let environmentValue = environment[environmentKey]?.lowercased() {
			switch environmentValue {
			case "1", "true", "yes":
				return true
			case "0", "false", "no":
				return false
			default:
				break
			}
		}

		return storedValue
	}
}
