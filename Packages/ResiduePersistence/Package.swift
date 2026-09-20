// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "ResiduePersistence", platforms: [.macOS(.v14)],
    products: [.library(name: "ResiduePersistence", targets: ["ResiduePersistence"])],
    targets: [
        .systemLibrary(name: "CSQLite"),
        .target(name: "ResiduePersistence", dependencies: ["CSQLite"]),
        .executableTarget(name: "JournalCrashProbe", dependencies: ["ResiduePersistence", "CSQLite"]),
        .testTarget(name: "ResiduePersistenceTests", dependencies: ["ResiduePersistence", "CSQLite", "JournalCrashProbe"])
    ], swiftLanguageModes: [.v6]
)
