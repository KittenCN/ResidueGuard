// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "ResiduePersistence", platforms: [.macOS(.v14)],
    products: [.library(name: "ResiduePersistence", targets: ["ResiduePersistence"])],
    dependencies: [.package(path: "../ResidueCore"), .package(path: "../ResidueRecovery")],
    targets: [
        .systemLibrary(name: "CSQLite"),
        .target(name: "ResiduePersistence", dependencies: ["CSQLite", "ResidueCore", "ResidueRecovery"]),
        .executableTarget(name: "JournalCrashProbe", dependencies: ["ResiduePersistence", "CSQLite", "ResidueCore", "ResidueRecovery"]),
        .testTarget(name: "ResiduePersistenceTests", dependencies: ["ResiduePersistence", "CSQLite", "JournalCrashProbe", "ResidueCore", "ResidueRecovery"])
    ], swiftLanguageModes: [.v6]
)
