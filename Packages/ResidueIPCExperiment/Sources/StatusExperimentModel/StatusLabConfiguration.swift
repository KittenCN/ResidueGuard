import Foundation
import Darwin

public struct StatusLabConfiguration {
    public let scenario: StatusLabCase
    public let peerRequirement: String
    public static func load(server: Bool) throws -> StatusLabConfiguration {
        guard getuid() > 0, getuid() == geteuid(),
              let raw = Bundle.main.infoDictionary?["RGStatusCase"] as? String,
              let scenario = StatusLabCase(rawValue: raw) else { throw CocoaError(.coderInvalidValue) }
        var root = Bundle.main.bundleURL
        for _ in 0..<(server ? 4 : 1) { root.deleteLastPathComponent() }
        let prefix = "status-wire-lab-", name = root.lastPathComponent
        guard name.hasPrefix(prefix), let token = UUID(uuidString: String(name.dropFirst(prefix.count))),
              name == prefix + token.uuidString else { throw CocoaError(.coderInvalidValue) }
        let fd = open(root.appendingPathComponent("status-peer-pins.plist").path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw CocoaError(.fileReadNoSuchFile) }; defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_uid == getuid(),
              info.st_mode & 0o7777 == 0o600, info.st_nlink == 1, info.st_size > 0, info.st_size <= 65536 else { throw CocoaError(.fileReadNoPermission) }
        var data = Data(count: Int(info.st_size))
        let count = data.withUnsafeMutableBytes { pread(fd, $0.baseAddress, $0.count, 0) }
        guard count == data.count,
              let manifest = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: [String: String]],
              let pin = manifest[scenario.rawValue]?[server ? "client" : "server"],
              pin.range(of: #"^cdhash H"[0-9a-f]{40}"$"#, options: .regularExpression) != nil else { throw CocoaError(.coderInvalidValue) }
        return .init(scenario: scenario, peerRequirement: pin)
    }
}
