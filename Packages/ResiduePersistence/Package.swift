// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "ResiduePersistence", platforms: [.macOS(.v14)],
    products: [.library(name: "ResiduePersistence", targets: ["ResiduePersistence"])],
    targets: [
        .systemLibrary(name: "CSQLite"),
        .target(name: "ResiduePersistence", dependencies: ["CSQLite"]),
        .testTarget(name: "ResiduePersistenceTests", dependencies: ["ResiduePersistence", "CSQLite"])
    ], swiftLanguageModes: [.v6]
)
