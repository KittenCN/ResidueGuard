import Foundation
import Testing
import ResidueCore
@testable import ResiduePlatform

private func fixture(_ values: [String: Any], format: PropertyListSerialization.PropertyListFormat = .xml) throws -> Data {
    try PropertyListSerialization.data(fromPropertyList: values, format: format, options: 0)
}
private func directory() throws -> URL {
    // /tmp on macOS is a symlink; canonicalize our own generated fixture location only.
    let root = URL(fileURLWithPath: "/private/tmp").appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}
@Test func parsesXMLAndBinaryAndPreservesUnknownFields() throws {
    for format in [PropertyListSerialization.PropertyListFormat.xml, .binary] {
        let data = try fixture(["Label": "fixture.a", "Program": "/nonexistent-fixture", "Unknown": ["nested": true]], format: format)
        let r = try LaunchConfigurationParser.parse(data, source: URL(fileURLWithPath: "/fixture/a.plist"), scope: "user", generation: "g")
        #expect(r.targetReferences == ["/nonexistent-fixture"])
        #expect(r.parseWarnings.contains("additionalLaunchSemanticsUnverified"))
        #expect(Data(base64Encoded: r.rawMetadata["rawPropertyListBase64"]!) == data)
        #expect(r.rawMetadata["contentSHA256"]?.count == 64)
    }
}
@Test func programTakesPrecedenceAndShellIsAmbiguous() throws {
    let r = try LaunchConfigurationParser.parse(fixture(["Label": "fixture", "Program": "/bin/sh", "ProgramArguments": ["/misleading", "-c", "touch /should-never-run"]]), source: URL(fileURLWithPath: "/fixture/a"), scope: "user", generation: "g")
    #expect(r.targetReferences == ["/bin/sh"])
    #expect(r.parseWarnings.contains("ambiguousPayload"))
}
@Test func malformedAndOversizedFieldsRejected() throws {
    #expect(throws: (any Error).self) { try LaunchConfigurationParser.parse(Data("no plist".utf8), source: URL(fileURLWithPath: "/a"), scope: "u", generation: "g") }
    #expect(throws: (any Error).self) { try LaunchConfigurationParser.parse(fixture(["Label": String(repeating: "a", count: 16385)]), source: URL(fileURLWithPath: "/a"), scope: "u", generation: "g") }
}
@Test func noFollowRejectsFileAndAncestorSymlinks() throws {
    let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
    let real = root.appendingPathComponent("real")
    try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
    try Data("payload".utf8).write(to: real.appendingPathComponent("file"))
    try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link"), withDestinationURL: real)
    try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("filelink"), withDestinationURL: real.appendingPathComponent("file"))
    #expect(throws: (any Error).self) { try SafeFiles.read(root.appendingPathComponent("link/file"), limit: 100) }
    #expect(throws: (any Error).self) { try SafeFiles.read(root.appendingPathComponent("filelink"), limit: 100) }
    #expect(try SafeFiles.read(real.appendingPathComponent("file"), limit: 100) == Data("payload".utf8))
    #expect(throws: (any Error).self) { try SafeFiles.read(real.appendingPathComponent("file"), limit: 2) }
}
@Test func scanKeepsMissingTargetsConservativeAndFailuresVisible() async throws {
    let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
    try fixture(["Label": "fixture.missing", "Program": root.appendingPathComponent("absent").path]).write(to: root.appendingPathComponent("a.plist"))
    try Data("invalid".utf8).write(to: root.appendingPathComponent("b.plist"))
    let snapshot = await ScanService(configuration: ScanConfiguration(launchRoots: [ScanRoot(url: root, scope: "test")], applicationRoots: [])).scan()
    #expect(snapshot.rows.count == 2)
    #expect(snapshot.rows.first?.presence == .suspectedOrphan)
    #expect(snapshot.coverage.first?.state == .partial)
    #expect(snapshot.coverage.first?.unparsedCount == 1)
    #expect(snapshot.rows.allSatisfy { $0.capability.support(for: .removeRegistration) == .blockedByPolicy })
    #expect(snapshot.coverage.contains { $0.providerID == "permissions.TCC" && $0.state == .unsupported })
}
@Test func duplicateLabelsBlockPresenceAndScopeQualifiesIdentity() async throws {
    let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
    let data = try fixture(["Label": "duplicate", "Program": "/bin/ls"])
    try data.write(to: root.appendingPathComponent("a.plist")); try data.write(to: root.appendingPathComponent("b.plist"))
    let snapshot = await ScanService(configuration: ScanConfiguration(launchRoots: [ScanRoot(url: root, scope: "test")], applicationRoots: [])).scan()
    #expect(snapshot.rows.count == 2)
    #expect(Set(snapshot.rows.map(\.id)).count == 2)
    #expect(snapshot.rows.allSatisfy { $0.presence == .unknown })
}
@Test func entryLimitAndMissingRootAreNotSuccessfulEmptyScans() async throws {
    let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
    for name in ["a", "b"] { try fixture(["Label": name, "Program": "/bin/ls"]).write(to: root.appendingPathComponent(name + ".plist")) }
    let config = ScanConfiguration(launchRoots: [ScanRoot(url: root, scope: "test"), ScanRoot(url: root.appendingPathComponent("absent"), scope: "test")], applicationRoots: [], maximumEntries: 1)
    let snapshot = await ScanService(configuration: config).scan()
    #expect(snapshot.coverage[0].state == .partial)
    #expect(snapshot.coverage[0].skippedAreas.contains("entryLimit"))
    #expect(snapshot.coverage[1].state == .partial)
    #expect(!snapshot.coverage[1].errors.isEmpty)
}
@Test func cancelledTaskHasCancelledCoverage() async throws {
    let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
    let service = ScanService(configuration: ScanConfiguration(launchRoots: [ScanRoot(url: root, scope: "test")], applicationRoots: []))
    let task = Task { await service.scan() }; task.cancel()
    let snapshot = await task.value
    #expect(snapshot.isCancelled)
}

@Test func anotherUserRootsAreBlocked() {
    #expect(!SafeFiles.allowedUserPath("/Users/another-user/Library/LaunchAgents"))
    #expect(!SafeFiles.allowedUserPath("/Users"))
    #expect(SafeFiles.allowedUserPath(SafeFiles.realUserHome + "/Library/LaunchAgents"))
}

@Test func rawProvenanceTruncationIsExplicit() throws {
    let data = try fixture(["Label": "large", "Program": "/bin/ls", "Description": String(repeating: "x", count: 5000)])
    let row = try LaunchConfigurationParser.parse(data, source: URL(fileURLWithPath: "/fixture/a.plist"), scope: "test", generation: "g")
    #expect(row.parseWarnings.contains("rawProvenanceTruncated"))
    #expect(Data(base64Encoded: row.rawMetadata["rawPropertyListBase64"]!)?.count == 4096)
}
@Test func applicationInventoryRetainsDuplicateInstallations() async throws {
    let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
    for name in ["a.app", "b.app"] {
        let contents = root.appendingPathComponent(name + "/Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        try fixture(["CFBundleIdentifier": "test.same.bundle"]).write(to: contents.appendingPathComponent("Info.plist"))
    }
    let snapshot = await ScanService(configuration: ScanConfiguration(launchRoots: [], applicationRoots: [root])).scan()
    #expect(snapshot.applications.count == 2)
    #expect(Set(snapshot.applications.map(\.fileIdentity)).count == 2)
    #expect(snapshot.applications.allSatisfy { $0.signingStatus == "unavailable" })
    #expect(snapshot.coverage[0].state == .partial)
}
@Test func rootTruncationIsExplicit() async {
    let roots = (0..<17).map { ScanRoot(url: URL(fileURLWithPath: "/nonexistent-fixture-\($0)"), scope: "test") }
    let snapshot = await ScanService(configuration: ScanConfiguration(launchRoots: roots, applicationRoots: [])).scan()
    #expect(snapshot.coverage.contains { $0.providerID == "scan.limits" && $0.skippedAreas.contains("rootLimit") })
}

@Test func alternatePathSpellingsCannotBypassUserBoundary() {
    for path in ["//Users/another-user/private", "/users/another-user/private", "/USERS/another-user/private", "/System/Volumes/Data/Users/another-user/private", "/Users/another-user\0/ignored"] {
        #expect(!SafeFiles.allowedUserPath(path), "Must block alternate spelling: \(path)")
    }
    #expect(SafeFiles.allowedUserPath(SafeFiles.realUserHome + "//Library/LaunchAgents"))
    #expect(!SafeFiles.allowedUserPath(SafeFiles.realUserHome + "-different/Library"))
}

@Test(arguments: ["//Volumes/", "/volumes/", "/VOLUMES//"])
func alternateExternalVolumeSpellingDoesNotBecomeMissingTarget(prefix: String) async throws {
    let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
    try fixture(["Label": "fixture.volume", "Program": "\(prefix)residue-fixture-offline-\(UUID().uuidString)/tool"]).write(to: root.appendingPathComponent("a.plist"))
    let snapshot = await ScanService(configuration: ScanConfiguration(launchRoots: [ScanRoot(url: root, scope: "test")], applicationRoots: [])).scan()
    #expect(snapshot.rows.first?.presence == .unknown)
    #expect(snapshot.rows.first?.evidence.contains("externalVolumeNotAuthorized; availabilityUnknown") == true)
    #expect(CodeIdentityInspector().inspect(application: URL(fileURLWithPath: prefix + "fixture.app")).diagnostic == "scopeNotAuthorized")
}

@Test func pathClassificationRejectsTraversalAndPreservesCase() {
    #expect(SafeFiles.absolutePathComponents("/fixture/../other") == nil)
    #expect(SafeFiles.absolutePathComponents("/fixture/./other") == nil)
    #expect(SafeFiles.absolutePathComponents("/fixture\0/other") == nil)
    #expect(SafeFiles.absolutePathComponents("//CaseSensitive//File") == ["CaseSensitive", "File"])
    #expect(SafeFiles.isTrashPath("/fixture//.Trash//tool"))
    #expect(SafeFiles.isTrashPath("/fixture/.trash/tool"))
    #expect(!SafeFiles.isExternalVolumePath("/VolumesOther/tool"))
}
