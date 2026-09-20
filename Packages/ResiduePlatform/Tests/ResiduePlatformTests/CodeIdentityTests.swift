import Foundation
import Testing
@testable import ResiduePlatform

private func unsignedApp() throws -> URL {
    let root = URL(fileURLWithPath: "/private/tmp").appendingPathComponent(UUID().uuidString + ".app")
    try FileManager.default.createDirectory(at: root.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
    let info: [String: String] = ["CFBundleIdentifier": "test.unsigned.fixture", "CFBundleExecutable": "fixture", "CFBundlePackageType": "APPL"]
    try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: root.appendingPathComponent("Contents/Info.plist"))
    try Data("#!/bin/sh\nexit 0\n".utf8).write(to: root.appendingPathComponent("Contents/MacOS/fixture"))
    return root
}
@Test func unsignedFixtureNeverClaimsVerifiedIdentity() throws {
    let app = try unsignedApp(); defer { try? FileManager.default.removeItem(at: app) }
    let result = CodeIdentityInspector().inspect(application: app)
    #expect(result.status == .unsigned || result.status == .unavailable)
    #expect(result.teamID == nil)
    #expect(result.designatedRequirement == nil)
    #expect(!result.diagnostic.isEmpty)
}
@Test func signatureInspectorRejectsExecutableSymlink() throws {
    let app = try unsignedApp(); defer { try? FileManager.default.removeItem(at: app) }
    let executable = app.appendingPathComponent("Contents/MacOS/fixture")
    try FileManager.default.removeItem(at: executable)
    try FileManager.default.createSymbolicLink(atPath: executable.path, withDestinationPath: "/usr/bin/true")
    let result = CodeIdentityInspector().inspect(application: app)
    #expect(result.status == .unavailable)
    #expect(result.teamID == nil)
}
@Test func signatureInspectorRejectsUnapprovedOtherUserAndVolume() {
    for path in ["/Users/another-user/Applications/Example.app", "/Volumes/Example/Example.app"] {
        let result = CodeIdentityInspector().inspect(application: URL(fileURLWithPath: path))
        #expect(result.status == .unavailable)
        #expect(result.diagnostic == "scopeNotAuthorized")
    }
}
