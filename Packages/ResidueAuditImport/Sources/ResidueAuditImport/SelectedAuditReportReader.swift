import Darwin
import Foundation
import ResidueRecovery

public enum AuditImportError: Error, Equatable, Sendable {
    case inaccessible, unsupportedFile, oversized, changedDuringRead
}

/// Reads only the caller-selected current-user file. The caller owns the temporary
/// security-scope grant and must call this synchronous API off the main actor.
/// No bookmarks, directory enumeration, authorization grants or writes occur here.
public enum SelectedAuditReportReader {
    public static func readSummary(from url: URL) throws -> RecoveryReviewSummary {
        try readSummary(from: url, cancellationCheck: { try Task.checkCancellation() })
    }

    // Internal injection allows deterministic cancellation/concurrent-change tests;
    // it does not make arbitrary hooks part of the public import API.
    static func readSummary(from url: URL, cancellationCheck: () throws -> Void) throws -> RecoveryReviewSummary {
        try cancellationCheck()
        let path = url.path
        guard url.isFileURL, path.hasPrefix("/"), !path.contains("\0"),
              !url.path(percentEncoded: true).contains("%00"), path.utf8.count < Int(PATH_MAX),
              url.host == nil || url.host == "" || url.host == "localhost" else {
            throw AuditImportError.unsupportedFile
        }
        // O_NOFOLLOW_ANY alone rejects links in every path component. On Darwin,
        // combining it with O_NOFOLLOW is invalid. O_NONBLOCK prevents FIFO waits.
        let fd = open(path, O_RDONLY | O_NOFOLLOW_ANY | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else {
            if errno == ELOOP || errno == EMLINK { throw AuditImportError.unsupportedFile }
            throw AuditImportError.inaccessible
        }
        defer { close(fd) }
        let before = try inspect(fd)
        let limit = RecoveryAudit.maximumEnvelopeBytes
        guard before.st_size >= 0, before.st_size <= limit else { throw AuditImportError.oversized }
        var data = Data(capacity: Int(before.st_size))
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while data.count <= limit {
            try cancellationCheck()
            let remaining = min(buffer.count, limit + 1 - data.count)
            let count = buffer.withUnsafeMutableBytes { read(fd, $0.baseAddress!, remaining) }
            if count < 0 {
                if errno == EINTR { continue }
                throw AuditImportError.inaccessible
            }
            if count == 0 { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        guard data.count <= limit else { throw AuditImportError.oversized }
        try cancellationCheck()
        let after = try inspect(fd)
        guard sameObservation(before, after), data.count == Int(after.st_size) else { throw AuditImportError.changedDuringRead }
        let snapshot = try RecoveryAudit.decode(data)
        try cancellationCheck()
        return try RecoveryAudit.summary(snapshot)
    }

    private static func inspect(_ fd: Int32) throws -> stat {
        var value = stat()
        guard fstat(fd, &value) == 0 else { throw AuditImportError.inaccessible }
        guard value.st_mode & S_IFMT == S_IFREG, value.st_uid == geteuid(), value.st_nlink == 1 else {
            throw AuditImportError.unsupportedFile
        }
        return value
    }
    private static func sameObservation(_ a: stat, _ b: stat) -> Bool {
        a.st_dev == b.st_dev && a.st_ino == b.st_ino && a.st_size == b.st_size &&
        a.st_uid == b.st_uid && a.st_gid == b.st_gid && a.st_mode == b.st_mode &&
        a.st_mtimespec.tv_sec == b.st_mtimespec.tv_sec && a.st_mtimespec.tv_nsec == b.st_mtimespec.tv_nsec &&
        a.st_ctimespec.tv_sec == b.st_ctimespec.tv_sec && a.st_ctimespec.tv_nsec == b.st_ctimespec.tv_nsec
    }
}
