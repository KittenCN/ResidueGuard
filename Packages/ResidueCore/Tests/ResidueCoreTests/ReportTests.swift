import Foundation
import Testing
@testable import ResidueCore

@Test func reportDefaultsDoNotLeakPathsOrSoftwareIdentity() throws {
    let source = SourceRecord(id: .init(providerID: "launchd.configuration", scope: "currentUser", nativeIdentity: "secret.client"), category: "background", observedAt: .distantPast, generation: "generation", sourceArtifact: "/Users/Private/Library/secret.plist", displayName: "PrivateSoftware", declaredAppIDs: ["secret.client"], targetReferences: ["/private/payload"], rawMetadata: ["private": "HIDDEN-RAW"], parseWarnings: ["/private/path"])
    let report = AuditReport.make(entries: [.init(source: source, presence: .unknown)], coverage: [], includeIdentitiesAndPaths: false, salt: "test-salt")
    let output = String(decoding: try report.json(), as: UTF8.self) + report.csv()
    for privateValue in ["PrivateSoftware", "secret.client", "/Users/Private", "/private/", "HIDDEN-RAW"] { #expect(!output.contains(privateValue)) }
    #expect(report.records.count == 1)
    #expect(report.records[0].recordKey.count == 64)
    #expect(report.isExecutionInput == false)
}
@Test func csvFormulaInjectionAndQuotesAreEscaped() {
    #expect(AuditReport.csvCell(" =SUM(1,2)") == "\"' =SUM(1,2)\"")
    #expect(AuditReport.csvCell("\t@command") == "\"'\t@command\"")
    #expect(AuditReport.csvCell("a\"b\nc") == "\"a\"\"b\nc\"")
    #expect(AuditReport.csvCell("normal") == "\"normal\"")
}
@Test func pseudonymsAreStableWithinExportButSaltedBetweenExports() {
    #expect(AuditReport.pseudonym("id", salt: "a") == AuditReport.pseudonym("id", salt: "a"))
    #expect(AuditReport.pseudonym("id", salt: "a") != AuditReport.pseudonym("id", salt: "b"))
}
@Test func reportLargeSyntheticDatasetRemainsRedacted() throws {
    let start = ContinuousClock.now
    let entries = (0..<10_000).map { index in
        ReportEntry(source: SourceRecord(id: .init(providerID: "launchd.configuration", scope: "currentUser", nativeIdentity: "synthetic-\(index)"), category: "background", observedAt: .distantPast, generation: "fixture", sourceArtifact: "/Synthetic/\(index).plist", displayName: "Synthetic \(index)", declaredAppIDs: [], targetReferences: [], rawMetadata: [:], parseWarnings: []), presence: .unknown)
    }
    let report = AuditReport.make(entries: entries, coverage: [], salt: "benchmark", dataOrigin: .synthetic)
    #expect(report.records.count == 10_000)
    #expect(Set(report.records.map(\.recordKey)).count == 10_000)
    #expect(report.records.allSatisfy { $0.name == nil && $0.sourcePath == nil })
    #expect(try report.json().count > 0)
    #expect(report.csv().contains("\"synthetic\",\"false\""))
    print("Synthetic 10000-row report serialization elapsed: \(start.duration(to: .now)) (not GUI scrolling)")
}
