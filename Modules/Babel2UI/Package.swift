// swift-tools-version: 6.2
import PackageDescription

let package = Package(
	name: "Babel2UI",
	platforms: [.macOS(.v15), .iOS(.v17)],
	products: [
		.library(name: "Babel2UI", type: .dynamic, targets: ["Babel2Core", "Babel2UI"])
	],
	targets: [
		.target(
			name: "Babel2Core",
			path: "Sources/Babel2Core",
			swiftSettings: [
				.enableUpcomingFeature("NonisolatedNonsendingByDefault"),
				.enableUpcomingFeature("InferIsolatedConformances")
			]
		),
		.target(
			name: "Babel2UI",
			dependencies: ["Babel2Core"],
			path: "Sources/Babel2UI"
		),
		.testTarget(
			name: "Babel2UITests",
			dependencies: ["Babel2Core", "Babel2UI"],
			swiftSettings: [.swiftLanguageMode(.v6)]
		)
	]
)
