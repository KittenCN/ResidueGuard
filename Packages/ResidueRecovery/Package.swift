// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "ResidueRecovery", platforms: [.macOS(.v14)],
    products: [.library(name: "ResidueRecovery", targets: ["ResidueRecovery"])],
    dependencies: [.package(path: "../ResidueCore")],
    targets: [.target(name: "ResidueRecovery", dependencies: ["ResidueCore"]),
              .testTarget(name: "ResidueRecoveryTests", dependencies: ["ResidueRecovery", "ResidueCore"])],
    swiftLanguageModes: [.v6]
)
