// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "ResidueBackup", platforms: [.macOS(.v14)], products: [.library(name: "ResidueBackup", targets: ["ResidueBackup"]), .executable(name: "ResidueBackupVMProbe", targets: ["ResidueBackupVMProbe"])], targets: [.target(name: "ResidueBackup"), .executableTarget(name: "ResidueBackupVMProbe", dependencies: ["ResidueBackup"]), .testTarget(name: "ResidueBackupTests", dependencies: ["ResidueBackup"])])
