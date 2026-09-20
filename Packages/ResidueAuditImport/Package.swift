// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "ResidueAuditImport", platforms: [.macOS(.v14)],
    products: [.library(name: "ResidueAuditImport", targets: ["ResidueAuditImport"])],
    dependencies: [.package(path: "../ResidueRecovery")],
    targets: [
        .target(name: "ResidueAuditImport", dependencies: ["ResidueRecovery"]),
        .testTarget(name: "ResidueAuditImportTests", dependencies: ["ResidueAuditImport", "ResidueRecovery"], resources: [.copy("Fixtures")])
    ], swiftLanguageModes: [.v6]
)
