// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "ResidueTransactions", platforms: [.macOS(.v14)],
    products: [.library(name: "ResidueTransactions", targets: ["ResidueTransactions"])],
    dependencies: [.package(path: "../ResidueCore"), .package(path: "../ResiduePersistence")],
    targets: [
        .target(name: "ResidueTransactions", dependencies: ["ResidueCore", "ResiduePersistence"]),
        .testTarget(name: "ResidueTransactionsTests", dependencies: ["ResidueTransactions", "ResidueCore", "ResiduePersistence"])
    ], swiftLanguageModes: [.v6]
)
