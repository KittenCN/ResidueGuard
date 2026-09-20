// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "ResiduePreferences", platforms: [.macOS(.v14)],
    products: [.library(name: "ResiduePreferences", targets: ["ResiduePreferences"])],
    targets: [.target(name: "ResiduePreferences"), .testTarget(name: "ResiduePreferencesTests", dependencies: ["ResiduePreferences"])],
    swiftLanguageModes: [.v6]
)
