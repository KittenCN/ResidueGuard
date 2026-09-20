import Foundation
import Darwin

/// Opens only the requested object; kernel O_NOFOLLOW_ANY rejects every symlink component.
/// No plist-supplied executable is ever launched, and no special file is read.
enum SafeFiles {
    enum Failure: Error { case invalidPath, posix(Int32), notRegular, tooLarge, changed }
    static func descriptor(_ url: URL, directory: Bool = false) throws -> Int32 {
        guard url.isFileURL, allowedUserPath(url.path) else { throw Failure.invalidPath }
        let parts = url.path.split(separator: "/").map(String.init)
        guard !parts.contains("..") else { throw Failure.invalidPath }
        // The selected-directory sandbox grant does not authorize enumerating
        // its ancestors. Ask the kernel to reject links across the whole path,
        // opening only the requested object instead of reading each ancestor.
        let flags = O_RDONLY | O_NOFOLLOW_ANY | O_CLOEXEC | O_NONBLOCK | (directory ? O_DIRECTORY : 0)
        let fd = open(url.path, flags)
        guard fd >= 0 else { throw Failure.posix(errno) }
        return fd
    }
    static func read(_ url: URL, limit: Int) throws -> Data {
        let fd = try descriptor(url)
        defer { close(fd) }
        var before = stat()
        guard fstat(fd, &before) == 0 else { throw Failure.posix(errno) }
        guard (before.st_mode & S_IFMT) == S_IFREG else { throw Failure.notRegular }
        guard before.st_size >= 0, before.st_size <= limit else { throw Failure.tooLarge }
        var data = Data(); var buffer = [UInt8](repeating: 0, count: min(limit + 1, 65_536))
        while true {
            try Task.checkCancellation()
            let count = Darwin.read(fd, &buffer, min(buffer.count, limit + 1 - data.count))
            if count < 0 { if errno == EINTR { continue }; throw Failure.posix(errno) }
            if count == 0 { break }
            data.append(contentsOf: buffer.prefix(count))
            if data.count > limit { throw Failure.tooLarge }
        }
        var after = stat()
        guard fstat(fd, &after) == 0, before.st_ino == after.st_ino, before.st_size == after.st_size,
              before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec, before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec else { throw Failure.changed }
        return data
    }
    static func list(_ url: URL, limit: Int) throws -> (names: [String], truncated: Bool) {
        let fd = try descriptor(url, directory: true)
        guard let stream = fdopendir(fd) else { let code = errno; close(fd); throw Failure.posix(code) }
        defer { closedir(stream) }
        var names: [String] = []
        while true {
            try Task.checkCancellation()
            errno = 0
            guard let entry = readdir(stream) else { if errno != 0 { throw Failure.posix(errno) }; break }
            let name = withUnsafePointer(to: &entry.pointee.d_name) { pointer in pointer.withMemoryRebound(to: CChar.self, capacity: Int(entry.pointee.d_namlen) + 1) { String(cString: $0) } }
            if name == "." || name == ".." { continue }
            if names.count == limit { return (names.sorted(), true) }
            names.append(name)
        }
        return (names.sorted(), false)
    }
    static func diagnostic(_ error: Error) -> String {
        switch error {
        case Failure.posix(let code): return "POSIX \(code)"
        case Failure.invalidPath: return "invalidPath"
        case Failure.notRegular: return "notRegular"
        case Failure.tooLarge: return "sizeLimit"
        case Failure.changed: return "identityChangedDuringRead"
        default: return "invalidPropertyList"
        }
    }
}

extension SafeFiles {
    static var osBuild: String {
        var size = 0
        guard sysctlbyname("kern.osversion", nil, &size, nil, 0) == 0, size > 0, size <= 4096 else { return "unverified" }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname("kern.osversion", &bytes, &size, nil, 0) == 0 else { return "unverified" }
        return bytes.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
    }
    static var realUserHome: String {
        var entry = passwd(); var result: UnsafeMutablePointer<passwd>?
        var buffer = [CChar](repeating: 0, count: 16_384)
        return buffer.withUnsafeMutableBufferPointer { bytes in
            guard getpwuid_r(getuid(), &entry, bytes.baseAddress!, bytes.count, &result) == 0,
                  result != nil, let home = entry.pw_dir else { return "" }
            return String(cString: home)
        }
    }
    static func allowedUserPath(_ path: String) -> Bool {
        guard let parts = absolutePathComponents(path) else { return false }
        // Alternate Data-volume paths must not bypass the ordinary user boundary.
        // These aliases have no independently authorized scope in the baseline.
        if parts.count >= 2, componentMatches(parts[0], "System"), componentMatches(parts[1], "Volumes") { return false }
        guard let first = parts.first, componentMatches(first, "Users") else { return true }
        guard let home = absolutePathComponents(realUserHome), !home.isEmpty else { return false }
        // Preserve exact case for identity. Case-insensitive matching above is only
        // a conservative exclusion, never proof that differently named files match.
        return parts.count >= home.count && Array(parts.prefix(home.count)) == home
    }
    static func absolutePathComponents(_ path: String) -> [String]? {
        guard path.hasPrefix("/"), !path.contains("\0") else { return nil }
        let parts = path.split(separator: "/").map(String.init)
        guard !parts.contains("."), !parts.contains("..") else { return nil }
        return parts
    }
    static func componentMatches(_ component: String, _ protectedName: String) -> Bool {
        component.caseInsensitiveCompare(protectedName) == .orderedSame
    }
    static func isExternalVolumePath(_ path: String) -> Bool {
        guard let first = absolutePathComponents(path)?.first else { return false }
        return componentMatches(first, "Volumes")
    }
    static func isTrashPath(_ path: String) -> Bool {
        absolutePathComponents(path)?.contains { componentMatches($0, ".Trash") || componentMatches($0, ".Trashes") } ?? false
    }
}
