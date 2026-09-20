// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "ResidueBackup", platforms: [.macOS(.v14)],
    products: [
        .library(name: "ResidueBackup", targets: ["ResidueBackup"]),
        .library(name: "ResidueQuarantine", targets: ["ResidueQuarantine"]),
        .executable(name: "ResidueBackupVMProbe", targets: ["ResidueBackupVMProbe"]),
        .executable(name: "ResidueOwnedFixtureVMProbe", targets: ["ResidueOwnedFixtureVMProbe"]),
        .executable(name: "ResidueOwnedFixtureAuditProbe", targets: ["ResidueOwnedFixtureAuditProbe"]),
        .executable(name: "ResidueOwnedFixtureBootoutProbe", targets: ["ResidueOwnedFixtureBootoutProbe"]),
        .executable(name: "ResidueOwnedFixtureCrashProbe", targets: ["ResidueOwnedFixtureCrashProbe"])
    ],
    dependencies: [.package(path: "../ResiduePlatform"), .package(path: "../ResiduePersistence")],
    targets: [
        .target(name: "ResidueBackup"),
        .target(name: "ResidueQuarantine", dependencies: ["ResidueBackup", "ResiduePlatform", "ResiduePersistence"]),
        .executableTarget(name: "ResidueBackupVMProbe", dependencies: ["ResidueBackup"]),
        .executableTarget(name: "ResidueOwnedFixtureVMProbe", dependencies: ["ResidueQuarantine", "ResidueBackup"]),
        .executableTarget(name: "ResidueOwnedFixtureAuditProbe", dependencies: ["ResidueQuarantine", "ResidueBackup"]),
        .executableTarget(name: "ResidueOwnedFixtureBootoutProbe", dependencies: ["ResidueQuarantine"]),
        .executableTarget(name: "ResidueOwnedFixtureCrashProbe", dependencies: ["ResidueQuarantine"]),
        .testTarget(name: "ResidueBackupTests", dependencies: ["ResidueBackup"]),
        .testTarget(name: "ResidueQuarantineTests", dependencies: ["ResidueQuarantine", "ResidueBackup", "ResiduePersistence", "ResiduePlatform"])
    ], swiftLanguageModes: [.v6]
)
