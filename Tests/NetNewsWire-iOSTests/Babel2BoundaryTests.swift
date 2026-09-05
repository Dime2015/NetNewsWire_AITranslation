import Foundation
import Testing
import UIKit
import Babel2Core
import Babel2UI
@testable import NetNewsWire

@Suite struct Babel2BoundaryTests {
	@Test func appAssemblyKeepsBabel2IdentityAndPureInitialRoute() {
		#expect(Babel2AppAssembly.productName == Babel2Core.productName)
		#expect(Babel2Core.productName == "Babel 2.0")
		#expect(Babel2AppAssembly.initialNavigationState().path == [.home])
	}

	@Test func sourceBoundaryContainsNoLegacyUIOrWebViewDependencies() throws {
		let projectRoot = URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.deletingLastPathComponent()
		let coreRoot = projectRoot.appendingPathComponent("Modules/Babel2UI/Sources/Babel2Core")
		let uiRoot = projectRoot.appendingPathComponent("Modules/Babel2UI/Sources/Babel2UI")
		let appRoot = projectRoot.appendingPathComponent("iOS/Babel2")
		// The two integration-layer files were previously outside this sweep's
		// scan roots (only iOS/Babel2 itself was scanned) even though they are
		// new Babel2 content -- Gate A's per-directory scope must not silently
		// exclude new files just because they live one level up. Scanning them
		// surfaced one legitimate hit (AccountManager.shared in
		// Babel2LiveDataAdapters.swift, the single designated bridge into the
		// real account singleton), allowlisted below the same way
		// Babel2FeatureGate.swift's trace-only tokens are.
		let integrationRoot = projectRoot.appendingPathComponent("iOS/Babel2Integration")
		let parserFile = projectRoot.appendingPathComponent("iOS/Babel2ExternalActionParser.swift")
		let packageManifest = projectRoot.appendingPathComponent("Modules/Babel2UI/Package.swift")
		let fileManager = FileManager.default

		for root in [coreRoot, uiRoot, appRoot, integrationRoot] {
			var isDirectory: ObjCBool = false
			#expect(fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory))
			#expect(isDirectory.boolValue)
			let entries = try #require(fileManager.enumerator(at: root, includingPropertiesForKeys: nil))
			#expect(entries.allObjects.isEmpty == false, "Babel 2.0 source root is empty: \(root.path)")
		}
		var isManifestDirectory: ObjCBool = false
		#expect(fileManager.fileExists(atPath: packageManifest.path, isDirectory: &isManifestDirectory))
		#expect(isManifestDirectory.boolValue == false)
		let manifestData = try Data(contentsOf: packageManifest)
		#expect(manifestData.isEmpty == false, "Babel2UI Package.swift is empty")
		var isParserFileDirectory: ObjCBool = false
		#expect(fileManager.fileExists(atPath: parserFile.path, isDirectory: &isParserFileDirectory))
		#expect(isParserFileDirectory.boolValue == false)

		let coreProhibitedTokens = [
			"UIKit",
			"WebKit",
			"WKWebView",
			"SceneDelegate",
			"SceneCoordinator",
			"RootSplitViewController",
			"BabelUI",
			"BabelArticleSearchViewController",
			"BabelBrowserViewController",
			"BabelDesignSystem",
			"BabelFeedsViewController",
			"BabelLibrary",
			"BabelReaderViewController",
			"BabelSettingsViewController",
			"BabelShellConfiguration",
			"BabelShellViewController",
			"BabelSubscriptionViewControllers",
			"BabelTimelineViewController",
			"WebViewProvider",
			"PreloadedWebView",
			"WebViewConfiguration",
			"AccountManager.shared",
			"SmartFeedsController.shared",
			"AppDefaults.shared",
			"AppDefaults.standard",
			"UserDefaults.standard"
		]
		let uiAndAppProhibitedTokens = [
			"SceneDelegate",
			"SceneCoordinator",
			"RootSplitViewController",
			"BabelUI",
			"BabelArticleSearchViewController",
			"BabelBrowserViewController",
			"BabelDesignSystem",
			"BabelFeedsViewController",
			"BabelLibrary",
			"BabelReaderViewController",
			"BabelSettingsViewController",
			"BabelShellConfiguration",
			"BabelShellViewController",
			"BabelSubscriptionViewControllers",
			"BabelTimelineViewController",
			"WebViewProvider",
			"PreloadedWebView",
			"WebViewConfiguration",
			"AccountManager.shared",
			"SmartFeedsController.shared",
			"AppDefaults.shared",
			"AppDefaults.standard",
			"UserDefaults.standard"
		]
		let permanentLegacyTokens = [
			"WebViewProvider",
			"PreloadedWebView",
			"WebViewConfiguration",
			"BabelArticleSearchViewController",
			"BabelBrowserViewController",
			"BabelFeedsViewController",
			"BabelReaderViewController",
			"BabelSettingsViewController",
			"BabelShellViewController",
			"BabelSubscriptionViewControllers",
			"BabelTimelineViewController"
		]
		let futureWebKitRoots = [
			uiRoot.appendingPathComponent("Reader/WebKit").standardizedFileURL,
			appRoot.appendingPathComponent("Reader/WebKit").standardizedFileURL
		]

		let rootsAndTokens: [(URL, [String])] = [
			(coreRoot, coreProhibitedTokens),
			(uiRoot, uiAndAppProhibitedTokens),
			(appRoot, uiAndAppProhibitedTokens),
			(integrationRoot, uiAndAppProhibitedTokens)
		]
		var filesToScan = [packageManifest, parserFile]
		let sourceExtensions: Set<String> = ["swift", "xcstrings", "json"]

		for (root, _) in rootsAndTokens {
			let enumerator = try #require(fileManager.enumerator(at: root, includingPropertiesForKeys: nil))
			for case let fileURL as URL in enumerator where sourceExtensions.contains(fileURL.pathExtension) {
				filesToScan.append(fileURL)
			}
		}

		for fileURL in filesToScan {
			let source = try String(contentsOf: fileURL, encoding: .utf8)
			#expect(source.isEmpty == false, "Babel 2.0 boundary file is empty: \(fileURL.path)")
			if fileURL == packageManifest {
				let normalizedManifest = source.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
				#expect(!normalizedManifest.contains("package(url:"), "Babel2UI manifest has an external package dependency")
				#expect(!normalizedManifest.contains("package(path:"), "Babel2UI manifest has a local package dependency")
				#expect(!normalizedManifest.contains("package(id:"), "Babel2UI manifest has a registry package dependency")
				let coreSection = try #require(section(named: "Babel2Core", in: normalizedManifest, endingAt: #".target( name: "Babel2UI""#))
				let uiSection = try #require(section(named: "Babel2UI", in: normalizedManifest, endingAt: ".testTarget("))
				let testSection = try #require(section(named: "Babel2UITests", in: normalizedManifest, endingAt: " ] )"))
				#expect(!coreSection.contains("dependencies:"), "Babel2Core must have no target dependencies")
				#expect(uiSection.contains(#"dependencies: ["Babel2Core"]"#), "Babel2UI must depend only on Babel2Core")
				#expect(testSection.contains(#"dependencies: ["Babel2Core", "Babel2UI"]"#), "Babel2UITests must depend only on Core and UI")
				continue
			}

			let tokens = fileURL.path.hasPrefix(coreRoot.path) ? coreProhibitedTokens : uiAndAppProhibitedTokens
			// These are trace-only identity/diagnostic tokens in this model, not
			// legacy UI dependencies. Keep the exception exact and file-scoped;
			// all other legacy tokens remain prohibited.
			let traceOnlyTokens: Set<String>
			switch fileURL.lastPathComponent {
			case "Babel2FeatureGate.swift":
				traceOnlyTokens = ["SceneCoordinator", "SceneDelegate"]
			case "Babel2LiveDataAdapters.swift":
				// The single designated bridge into the real account singleton
				// (ADR-001: reuse account/sync/article services, don't reimplement
				// them). No other Babel2 file may reference this singleton.
				traceOnlyTokens = ["AccountManager.shared"]
			default:
				traceOnlyTokens = []
			}
			for token in tokens {
				#expect(traceOnlyTokens.contains(token) || !source.contains(token), "Babel 2.0 source contains prohibited token \(token): \(fileURL.path)")
			}
			for token in permanentLegacyTokens {
				#expect(!source.contains(token), "Babel 2.0 source contains permanent legacy token \(token): \(fileURL.path)")
			}
			if source.contains("WebKit") || source.contains("WKWebView") {
				let normalizedPath = fileURL.standardizedFileURL.path
				let isWhitelisted = futureWebKitRoots.contains { root in
					normalizedPath == root.path || normalizedPath.hasPrefix(root.path + "/")
				}
				#expect(isWhitelisted, "WebKit is only allowed under a future reader whitelist path: \(fileURL.path)")
			}
		}
	}

	@Test func productionLifecycleHasNoLegacyRootOrFallbackRoute() throws {
		let projectRoot = URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.deletingLastPathComponent()
		let appDelegateURL = projectRoot.appendingPathComponent("iOS/AppDelegate.swift")
		let sceneDelegateURL = projectRoot.appendingPathComponent("iOS/SceneDelegate.swift")
		let integrationURL = projectRoot.appendingPathComponent("iOS/Babel2Integration/Babel2LiveDataAdapters.swift")
		let parserURL = projectRoot.appendingPathComponent("iOS/Babel2ExternalActionParser.swift")
		let infoPlistURL = projectRoot.appendingPathComponent("iOS/Resources/Info.plist")
		let appDelegate = try String(contentsOf: appDelegateURL, encoding: .utf8)
		let sceneDelegate = try String(contentsOf: sceneDelegateURL, encoding: .utf8)
		let integration = try String(contentsOf: integrationURL, encoding: .utf8)
		let parser = try String(contentsOf: parserURL, encoding: .utf8)
		let infoPlist = try String(contentsOf: infoPlistURL, encoding: .utf8)

		let forbiddenProductionRoutes = [
			"bootstrapLegacyGenerationIfNeeded",
			"startLegacyLifecycleIfNeeded",
			"ensureLegacyGeneration",
			"showLegacyCompatibilityInterface",
			"fallbackToLegacyForExternalAction",
			"scheduleLegacyExternalActionDismissal",
			"beginLaunchCompatibilityFallback",
			"RootSplitViewController",
			"SceneCoordinator",
			"BabelShellViewController",
			"BabelReaderWebViewPool",
			"WebViewConfiguration.compileContentBlockingRules",
			"ProcessInfo.processInfo.arguments",
			"UIStoryboard(name: \"Main\"",
			"Main.storyboard"
		]
		for token in forbiddenProductionRoutes {
			#expect(!appDelegate.contains(token), "AppDelegate contains removed production route \(token)")
			#expect(!sceneDelegate.contains(token), "SceneDelegate contains removed production route \(token)")
		}

		#expect(integration.contains("final class Babel2LiveDataProvider"))
		#expect(integration.contains("final class Babel2LiveActionHandler"))
		#expect(parser.components(separatedBy: "enum Babel2ExternalActionParser").count == 2)
		#expect(!sceneDelegate.contains("enum Babel2ExternalActionParser"))
		#expect(infoPlist.contains("<key>UISceneConfigurations</key>"))
		#expect(infoPlist.contains("<string>Babel2 Configuration</string>"))
		#expect(!infoPlist.contains("Default Configuration"))
		#expect(!infoPlist.contains("Main.storyboard"))
	}

	@Test func repositoryHasExactlyOneCanonicalExternalActionParser() throws {
		let projectRoot = URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.deletingLastPathComponent()
		let parserURL = projectRoot.appendingPathComponent("iOS/Babel2ExternalActionParser.swift").standardizedFileURL
		let fileManager = FileManager.default
		var declarationFiles = [URL]()
		for root in ["iOS", "Modules", "Tests"].map({ projectRoot.appendingPathComponent($0) }) {
			let enumerator = try #require(fileManager.enumerator(at: root, includingPropertiesForKeys: nil))
			for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
				let source = try String(contentsOf: fileURL, encoding: .utf8)
				let declaresParser = source.split(separator: "\n", omittingEmptySubsequences: false).contains { line in
					let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
					return trimmed.hasPrefix("enum Babel2ExternalActionParser") ||
						trimmed.hasPrefix("public enum Babel2ExternalActionParser") ||
						trimmed.hasPrefix("internal enum Babel2ExternalActionParser")
				}
				if declaresParser { declarationFiles.append(fileURL.standardizedFileURL) }
			}
		}
		#expect(declarationFiles == [parserURL])
	}
}


private func section(named name: String, in source: String, endingAt marker: String) -> String? {
	guard let start = source.range(of: "name: \"" + name + "\"") else { return nil }
	guard let end = source.range(of: marker, range: start.upperBound..<source.endIndex) else { return nil }
	return String(source[start.lowerBound..<end.lowerBound])
}
