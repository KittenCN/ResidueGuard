// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "ResidueQuarantine", platforms: [.macOS(.v14)],
    products: [.library(name: "ResidueQuarantine", targets: ["ResidueQuarantine"])],
    dependencies: [.package(path: "../ResidueBackup")],
    targets: [
        .target(name: "ResidueQuarantine", dependencies: ["ResidueBackup"]),
        .testTarget(name: "ResidueQuarantineTests", dependencies: ["ResidueQuarantine", "ResidueBackup"])
    ]
)
