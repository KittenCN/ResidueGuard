// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "ResidueIPCExperiment", platforms: [.macOS(.v14)], products: [
    .executable(name: "IPCExperimentClient", targets: ["IPCClient"]),
    .executable(name: "IPCExperimentServer", targets: ["IPCServer"])
], targets: [
    .target(name: "IPCWire", publicHeadersPath: "include"),
    .executableTarget(name: "IPCClient", dependencies: ["IPCWire"], linkerSettings: [.linkedFramework("Foundation")]),
    .executableTarget(name: "IPCServer", dependencies: ["IPCWire"], linkerSettings: [.linkedFramework("Foundation")])
])
