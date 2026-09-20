// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "ResidueBackup", platforms: [.macOS(.v14)],
    products: [
        .library(name: "ResidueBackup", targets: ["ResidueBackup"]),
        .library(name: "ResidueQuarantine", targets: ["ResidueQuarantine"]),
        .executable(name: "ResidueBackupVMProbe", targets: ["ResidueBackupVMProbe"]),
        .executable(name: "ResidueOwnedFixtureVMProbe", targets: ["ResidueOwnedFixtureVMProbe"])
    ],
    dependencies: [.package(path: "../ResiduePlatform")],
    targets: [
        .target(name: "ResidueBackup"),
        .target(name: "ResidueQuarantine", dependencies: ["ResidueBackup", "ResiduePlatform"]),
        .executableTarget(name: "ResidueBackupVMProbe", dependencies: ["ResidueBackup"]),
        .executableTarget(name: "ResidueOwnedFixtureVMProbe", dependencies: ["ResidueQuarantine", "ResidueBackup"]),
        .testTarget(name: "ResidueBackupTests", dependencies: ["ResidueBackup"]),
        .testTarget(name: "ResidueQuarantineTests", dependencies: ["ResidueQuarantine", "ResidueBackup"])
    ], swiftLanguageModes: [.v6]
)
