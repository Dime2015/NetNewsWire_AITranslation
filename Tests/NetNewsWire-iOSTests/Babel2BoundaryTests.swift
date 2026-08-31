import Foundation
import Testing
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
		let packageManifest = projectRoot.appendingPathComponent("Modules/Babel2UI/Package.swift")
		let fileManager = FileManager.default

		for root in [coreRoot, uiRoot, appRoot] {
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
			(appRoot, uiAndAppProhibitedTokens)
		]
		var filesToScan = [packageManifest]

		for (root, _) in rootsAndTokens {
			let enumerator = try #require(fileManager.enumerator(at: root, includingPropertiesForKeys: nil))
			for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
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
			for token in tokens {
				#expect(!source.contains(token), "Babel 2.0 source contains prohibited token \(token): \(fileURL.path)")
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
}

private func section(named name: String, in source: String, endingAt marker: String) -> String? {
	guard let start = source.range(of: "name: \"" + name + "\"") else { return nil }
	guard let end = source.range(of: marker, range: start.upperBound..<source.endIndex) else { return nil }
	return String(source[start.lowerBound..<end.lowerBound])
}
