// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "ResidueSecurity", platforms: [.macOS(.v14)], products: [.library(name: "ResidueSecurity", targets: ["ResidueSecurity"])], targets: [.target(name: "ResidueSecurity"), .testTarget(name: "ResidueSecurityTests", dependencies: ["ResidueSecurity"])], swiftLanguageModes: [.v6])
