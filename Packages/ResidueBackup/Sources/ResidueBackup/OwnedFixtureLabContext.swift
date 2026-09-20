import Foundation
import Darwin
import Security

/// Shared only by targets of this package. Never exported as a production path/fd API.
package final class OwnedFixtureLabContext {
    package let sourceFD: Int32
    package let labFD: Int32
    package let backup: VerifiedBackup
    package let sourceName: String
    package let fingerprint: SourceFingerprint
    package let home: String
    private init(sourceFD: Int32, labFD: Int32, backup: VerifiedBackup, name: String,
                 fingerprint: SourceFingerprint, home: String) throws {
        let sourceCopy = dup(sourceFD), labCopy = dup(labFD)
        guard sourceCopy >= 0, labCopy >= 0 else {
            if sourceCopy >= 0 { close(sourceCopy) }; if labCopy >= 0 { close(labCopy) }
            throw VMLabProbeError.invalidLab
        }
        self.sourceFD = sourceCopy; self.labFD = labCopy; self.backup = backup
        sourceName = name; self.fingerprint = fingerprint; self.home = home
    }
    deinit { close(sourceFD); close(labFD) }
    package static func createISO01() throws -> OwnedFixtureLabContext {
        var count = 0
        guard sysctlbyname("hw.model", nil, &count, nil, 0) == 0, count > 0, count < 256 else {
            throw VMLabProbeError.virtualMachineRequired
        }
        var bytes = [CChar](repeating: 0, count: count)
        guard sysctlbyname("hw.model", &bytes, &count, nil, 0) == 0,
              String(decoding: bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self).hasPrefix("VirtualMac"),
              getuid() != 0, geteuid() == getuid() else { throw VMLabProbeError.virtualMachineRequired }
        guard let entry = getpwuid(getuid()), let homePointer = entry.pointee.pw_dir else { throw VMLabProbeError.invalidLab }
        let home = String(cString: homePointer)
        guard home.hasPrefix("/Users/"), home.split(separator: "/").count == 2 else { throw VMLabProbeError.invalidLab }
        let homeFD = try labOpenChain(home)
        defer { close(homeFD) }
        let libraryFD = try labOpenDirectory(parent: homeFD, name: "Library", privateRequired: false)
        defer { close(libraryFD) }
        let sourceFD = try labOpenDirectory(parent: libraryFD, name: "LaunchAgents", privateRequired: false)
        defer { close(sourceFD) }
        let destinationName = "ResidueGuard-VM-VerifiedBackup-" + UUID().uuidString
        guard mkdirat(libraryFD, destinationName, 0o700) == 0 else { throw VMLabProbeError.invalidLab }
        let destinationFD = try labOpenDirectory(parent: libraryFD, name: destinationName, privateRequired: true)
        defer { close(destinationFD) }
        let store = try VerifiedBackup(testSourceFD: sourceFD, testDestinationFD: destinationFD)
        let name = "example.residueguard.fixture.iso01.plist"
        let (data, fingerprint) = try store.readSource(name)
        guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              Set(plist.keys) == ["Label", "ProgramArguments", "RunAtLoad", "KeepAlive"],
              plist["Label"] as? String == "example.residueguard.fixture.iso01",
              plist["ProgramArguments"] as? [String] == [home + "/Library/ResidueGuard-VM-ISO01/fixture"],
              let run = plist["RunAtLoad"] as? NSNumber, CFGetTypeID(run) == CFBooleanGetTypeID(), !run.boolValue,
              let keep = plist["KeepAlive"] as? NSNumber, CFGetTypeID(keep) == CFBooleanGetTypeID(), !keep.boolValue else {
            throw VMLabProbeError.invalidLab
        }
        let fixtureRoot = try labOpenDirectory(parent: libraryFD, name: "ResidueGuard-VM-ISO01", privateRequired: true)
        defer { close(fixtureRoot) }
        let fixtureFD = openat(fixtureRoot, "fixture", O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fixtureFD >= 0 else { throw VMLabProbeError.invalidLab }; defer { close(fixtureFD) }
        var before = stat()
        guard fstat(fixtureFD, &before) == 0, before.st_mode & S_IFMT == S_IFREG,
              before.st_uid == getuid(), before.st_mode & 0o7777 == 0o700,
              before.st_nlink == 1, before.st_flags == 0 else { throw VMLabProbeError.invalidLab }
        var code: SecStaticCode?
        var requirement: SecRequirement?
        guard SecStaticCodeCreateWithPath(URL(fileURLWithPath: home + "/Library/ResidueGuard-VM-ISO01/fixture") as CFURL, [], &code) == errSecSuccess,
              SecRequirementCreateWithString("identifier \"example.residueguard.fixture.iso01\"" as CFString, [], &requirement) == errSecSuccess,
              let code, let requirement,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate), requirement) == errSecSuccess else { throw VMLabProbeError.invalidLab }
        var after = stat()
        guard fstatat(fixtureRoot, "fixture", &after, AT_SYMLINK_NOFOLLOW) == 0,
              after.st_dev == before.st_dev, after.st_ino == before.st_ino,
              after.st_size == before.st_size, after.st_ctimespec.tv_sec == before.st_ctimespec.tv_sec,
              after.st_ctimespec.tv_nsec == before.st_ctimespec.tv_nsec else { throw VMLabProbeError.invalidLab }
        return try OwnedFixtureLabContext(sourceFD: sourceFD, labFD: destinationFD, backup: store,
                                          name: name, fingerprint: fingerprint, home: home)
    }
    package func makeQuarantineDirectory() throws -> Int32 {
        guard mkdirat(labFD, "quarantine", 0o700) == 0 else { throw VMLabProbeError.invalidLab }
        return try Self.labOpenDirectory(parent: labFD, name: "quarantine", privateRequired: true)
    }
    private static func labOpenChain(_ path: String) throws -> Int32 {
        var current = open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard current >= 0 else { throw VMLabProbeError.invalidLab }
        do {
            try labDirectoryPolicy(current, privateRequired: false)
            for component in path.split(separator: "/") {
                let next = try labOpenDirectory(parent: current, name: String(component), privateRequired: false)
                close(current); current = next
            }
            return current
        } catch { close(current); throw error }
    }
    private static func labOpenDirectory(parent: Int32, name: String, privateRequired: Bool) throws -> Int32 {
        let fd = openat(parent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw VMLabProbeError.invalidLab }
        do { try labDirectoryPolicy(fd, privateRequired: privateRequired); return fd }
        catch { close(fd); throw error }
    }
    private static func labDirectoryPolicy(_ fd: Int32, privateRequired: Bool) throws {
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFDIR,
              info.st_uid == 0 || info.st_uid == getuid(), info.st_mode & 0o7022 == 0,
              !privateRequired || (info.st_uid == getuid() && info.st_mode & 0o777 == 0o700) else {
            throw VMLabProbeError.invalidLab
        }
        guard let acl = acl_get_fd_np(fd, ACL_TYPE_EXTENDED) else {
            guard errno == ENOENT else { throw VMLabProbeError.invalidLab }; return
        }
        defer { acl_free(UnsafeMutableRawPointer(acl)) }
        var entry: acl_entry_t?
        var selector = Int32(ACL_FIRST_ENTRY.rawValue)
        while acl_get_entry(acl, selector, &entry) == 0 {
            guard let entry else { throw VMLabProbeError.invalidLab }
            var tag = ACL_UNDEFINED_TAG
            guard acl_get_tag_type(entry, &tag) == 0, tag == ACL_EXTENDED_DENY else { throw VMLabProbeError.invalidLab }
            selector = Int32(ACL_NEXT_ENTRY.rawValue)
        }
        guard errno == EINVAL else { throw VMLabProbeError.invalidLab }
    }
}
