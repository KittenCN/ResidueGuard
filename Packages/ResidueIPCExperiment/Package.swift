// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "ResidueIPCExperiment", platforms: [.macOS(.v14)], products: [
    .executable(name: "IPCExperimentClient", targets: ["IPCClient"]),
    .executable(name: "IPCExperimentServer", targets: ["IPCServer"]),
    .executable(name: "StatusWireClient", targets: ["StatusClient"]),
    .executable(name: "StatusWireServer", targets: ["StatusServer"])
], dependencies: [.package(path: "../ResidueSecurity")], targets: [
    .target(name: "StatusWireBridge", publicHeadersPath: "include", linkerSettings: [.linkedFramework("Foundation"), .linkedFramework("Security"), .linkedLibrary("bsm")]),
    .target(name: "StatusExperimentModel", dependencies: ["ResidueSecurity"]),
    .executableTarget(name: "StatusClient", dependencies: ["StatusWireBridge", "StatusExperimentModel"]),
    .executableTarget(name: "StatusServer", dependencies: ["StatusWireBridge", "StatusExperimentModel"]),
    .testTarget(name: "StatusExperimentModelTests", dependencies: ["StatusExperimentModel"]),
    .target(name: "IPCWire", publicHeadersPath: "include"),
    .executableTarget(name: "IPCClient", dependencies: ["IPCWire"], linkerSettings: [.linkedFramework("Foundation")]),
    .executableTarget(name: "IPCServer", dependencies: ["IPCWire"], linkerSettings: [.linkedFramework("Foundation")])
], swiftLanguageModes: [.v6])
