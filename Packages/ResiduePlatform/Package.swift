// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "ResiduePlatform", platforms: [.macOS(.v14)], products: [.library(name: "ResiduePlatform", targets: ["ResiduePlatform"]), .executable(name: "ResidueProbe", targets: ["ResidueProbe"])], dependencies: [.package(path: "../ResidueCore")], targets: [.target(name: "ResiduePlatform", dependencies: ["ResidueCore"]), .executableTarget(name: "ResidueProbe", dependencies: ["ResiduePlatform"]), .testTarget(name: "ResiduePlatformTests", dependencies: ["ResiduePlatform"])], swiftLanguageModes: [.v6])
