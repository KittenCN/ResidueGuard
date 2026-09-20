import Darwin
import Foundation
import Testing
import ResidueRecovery
@testable import ResidueAuditImport

private struct Fixture {
    let directory: URL
    let file: URL
    init(data: Data? = nil) throws {
        directory = URL(fileURLWithPath: "/private/tmp/ResidueAuditImportTests-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        file = directory.appendingPathComponent("report.json")
        let contents: Data
        if let data { contents = data }
        else {
            let resource = try #require(Bundle.module.url(forResource: "valid-audit", withExtension: "json", subdirectory: "Fixtures"))
            contents = try Data(contentsOf: resource)
        }
        try contents.write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
    func clean() { try? FileManager.default.removeItem(at: directory) }
}

@Test func selectedRealFileIsReadAndOnlyRedactedSummaryReturned() throws {
    let f = try Fixture(); defer { f.clean() }
    let summary = try SelectedAuditReportReader.readSummary(from: f.file)
    #expect(summary.targetCount == 1)
    #expect(summary.steps.first?.effects?.runtime == .succeeded)
    #expect(!summary.automaticExecutionAllowed && !summary.contentAuthenticityEstablished)
    #expect(!String(reflecting: summary).contains("fixture-fingerprint"))
}
@Test func oversizedFileIsRejectedBeforeReadingItsContents() throws {
    let f = try Fixture(data: Data(repeating: 0, count: RecoveryAudit.maximumEnvelopeBytes + 1)); defer { f.clean() }
    #expect(throws: AuditImportError.oversized) { try SelectedAuditReportReader.readSummary(from: f.file) }
}
@Test func finalAndAncestorSymlinksAreRejected() throws {
    let f = try Fixture(); defer { f.clean() }
    let fileLink = f.directory.appendingPathComponent("file-link.json")
    try FileManager.default.createSymbolicLink(at: fileLink, withDestinationURL: f.file)
    #expect(throws: AuditImportError.unsupportedFile) { try SelectedAuditReportReader.readSummary(from: fileLink) }
    let real = f.directory.appendingPathComponent("real")
    try FileManager.default.createDirectory(at: real, withIntermediateDirectories: false)
    try FileManager.default.copyItem(at: f.file, to: real.appendingPathComponent("report.json"))
    let alias = f.directory.appendingPathComponent("alias")
    try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: real)
    #expect(throws: AuditImportError.unsupportedFile) { try SelectedAuditReportReader.readSummary(from: alias.appendingPathComponent("report.json")) }
}
@Test func hardlinksAndDirectoriesAreRejected() throws {
    let f = try Fixture(); defer { f.clean() }
    #expect(throws: AuditImportError.unsupportedFile) { try SelectedAuditReportReader.readSummary(from: f.directory) }
    let alias = f.directory.appendingPathComponent("hardlink.json")
    #expect(link(f.file.path, alias.path) == 0)
    #expect(throws: AuditImportError.unsupportedFile) { try SelectedAuditReportReader.readSummary(from: f.file) }
    #expect(throws: AuditImportError.unsupportedFile) { try SelectedAuditReportReader.readSummary(from: alias) }
}
@Test func vanishedAndUnreadableFilesAreErrorsNotEmptyReports() throws {
    let f = try Fixture(); defer { f.clean() }
    #expect(chmod(f.file.path, 0) == 0)
    if geteuid() != 0 {
        #expect(throws: AuditImportError.inaccessible) { try SelectedAuditReportReader.readSummary(from: f.file) }
    }
    #expect(chmod(f.file.path, 0o600) == 0)
    try FileManager.default.removeItem(at: f.file)
    #expect(throws: AuditImportError.inaccessible) { try SelectedAuditReportReader.readSummary(from: f.file) }
}
@Test func fifoIsRejectedWithoutWaitingForWriter() throws {
    let f = try Fixture(); defer { f.clean() }
    let fifo = f.directory.appendingPathComponent("fifo.json")
    #expect(mkfifo(fifo.path, 0o600) == 0)
    #expect(throws: AuditImportError.unsupportedFile) { try SelectedAuditReportReader.readSummary(from: fifo) }
}
@Test func corruptionAndUnknownVersionRemainExplicitModelErrors() throws {
    let f = try Fixture(data: Data("invalid".utf8)); defer { f.clean() }
    #expect(throws: RecoveryAuditError.corrupt) { try SelectedAuditReportReader.readSummary(from: f.file) }
    try Data(#"{"schemaVersion":99,"contentSHA256":"a","payload":""}"#.utf8).write(to: f.file)
    #expect(throws: RecoveryAuditError.unsupportedVersion) { try SelectedAuditReportReader.readSummary(from: f.file) }
}
@Test func cancelledTaskDoesNotReadEvenAnExistingValidFile() async throws {
    let f = try Fixture(); defer { f.clean() }
    let cancelled = Task {
        withUnsafeCurrentTask { $0?.cancel() }
        return try SelectedAuditReportReader.readSummary(from: f.file)
    }
    await #expect(throws: CancellationError.self) { try await cancelled.value }
}
@Test func cancellationIsCheckedBetweenReadChunks() throws {
    let f = try Fixture(data: Data(repeating: 32, count: 32_000)); defer { f.clean() }
    var checks = 0
    #expect(throws: CancellationError.self) {
        try SelectedAuditReportReader.readSummary(from: f.file) {
            checks += 1
            if checks == 3 { throw CancellationError() } // Initial, before first chunk, before second chunk.
        }
    }
    #expect(checks == 3)
}
@Test func concurrentMetadataOrSizeChangeRejectsSnapshot() throws {
    let f = try Fixture(); defer { f.clean() }
    var checks = 0
    #expect(throws: AuditImportError.changedDuringRead) {
        try SelectedAuditReportReader.readSummary(from: f.file) {
            checks += 1
            if checks == 3 {
                let writer = try FileHandle(forWritingTo: f.file)
                try writer.seekToEnd(); try writer.write(contentsOf: Data(" ".utf8)); try writer.close()
            }
        }
    }
}
@Test func ordinaryModeChangeDuringReadRejectsSnapshot() throws {
    let f = try Fixture(); defer { f.clean() }
    var checks = 0
    #expect(throws: AuditImportError.changedDuringRead) {
        try SelectedAuditReportReader.readSummary(from: f.file) {
            checks += 1
            if checks == 3 { #expect(chmod(f.file.path, 0o640) == 0) }
        }
    }
}

@Test func growthAfterInitialStatStillCannotExceedReadBound() throws {
    let f = try Fixture(); defer { f.clean() }
    var checks = 0
    #expect(throws: AuditImportError.oversized) {
        try SelectedAuditReportReader.readSummary(from: f.file) {
            checks += 1
            if checks == 3 {
                let writer = try FileHandle(forWritingTo: f.file)
                try writer.seekToEnd()
                try writer.write(contentsOf: Data(repeating: 32, count: RecoveryAudit.maximumEnvelopeBytes))
                try writer.close()
            }
        }
    }
}

@Test func nulSuffixCannotReadTruncatedDifferentPath() throws {
    let f = try Fixture(); defer { f.clean() }
    let truncated = URL(fileURLWithPath: f.file.path + "\0ignored.json")
    // Foundation may preserve NUL as %00 in .path; it must not select the
    // different literal-percent filename either.
    try FileManager.default.copyItem(at: f.file, to: URL(fileURLWithPath: f.file.path + "%00ignored.json"))
    #expect(throws: AuditImportError.unsupportedFile) { try SelectedAuditReportReader.readSummary(from: truncated) }
}
@Test func overlongPathsAreRejectedBeforeOpen() throws {
    let url = URL(fileURLWithPath: "/" + String(repeating: "a", count: Int(PATH_MAX)))
    #expect(throws: AuditImportError.unsupportedFile) { try SelectedAuditReportReader.readSummary(from: url) }
}

@Test func literalPercentZeroFilenameIsNotConfusedWithEncodedNul() throws {
    let f = try Fixture(); defer { f.clean() }
    let literal = f.directory.appendingPathComponent("literal%00report.json")
    try FileManager.default.copyItem(at: f.file, to: literal)
    #expect(try SelectedAuditReportReader.readSummary(from: literal).targetCount == 1)
}
