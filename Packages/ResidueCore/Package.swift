// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ResidueCore", platforms: [.macOS(.v14)],
    products: [.library(name: "ResidueCore", targets: ["ResidueCore"])],
    targets: [.target(name: "ResidueCore"), .testTarget(name: "ResidueCoreTests", dependencies: ["ResidueCore"])],
    swiftLanguageModes: [.v6]
)
