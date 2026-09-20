import Foundation

/// An observed installation, not a verified owner. Signing fields are metadata only.
public struct OwnershipApplicationObservation: Equatable, Sendable {
    public let generation: String
    public let volumeIdentity: String
    public let fileIdentity: String
    public let path: String
    public let declaredBundleID: String
    public let signingIdentifier: String?
    public let signingStatus: String
    public let teamID: String?
    public let designatedRequirement: String?
    public let observedAt: Date
    public init(generation: String, volumeIdentity: String, fileIdentity: String, path: String,
                declaredBundleID: String, signingIdentifier: String? = nil,
                signingStatus: String = "unverified", teamID: String? = nil,
                designatedRequirement: String? = nil, observedAt: Date) {
        self.generation = generation; self.volumeIdentity = volumeIdentity; self.fileIdentity = fileIdentity
        self.path = path; self.declaredBundleID = declaredBundleID; self.signingIdentifier = signingIdentifier
        self.signingStatus = signingStatus; self.teamID = teamID; self.designatedRequirement = designatedRequirement
        self.observedAt = observedAt
    }
}
public enum CandidateOwnershipReason: String, Equatable, Sendable {
    case declaredBundleIdentifier, lexicalTargetWithinBundle
}
public enum OwnershipIssueKind: String, Equatable, Sendable {
    case duplicateBundleIdentifier, conflictingInstanceObservations, differingIdentityHints
    case ambiguousRecordIdentity, possibleSharedPayload, insufficientCoverage
    case unknownGeneration, unknownIdentity, unparsedRecord, malformedTargetPath, inputLimit
}
public struct OwnershipApplicationNode: Identifiable, Sendable {
    /// Presentation key scoped to one scan, not an execution target identity.
    public let id: String
    public let observations: [OwnershipApplicationObservation]
    public let issues: [OwnershipIssueKind]
}
public struct CandidateOwnershipEdge: Sendable {
    public let recordID: RecordIdentity
    public let applicationNodeID: String
    public let reasons: [CandidateOwnershipReason]
}
public struct OwnershipGraphIssue: Sendable {
    public let kind: OwnershipIssueKind
    public let recordID: RecordIdentity?
    public let applicationNodeIDs: [String]
    public let relatedRecordIDs: [RecordIdentity]
}
public struct CandidateOwnershipGraph: Sendable {
    public let generation: String
    public let applications: [OwnershipApplicationNode]
    public let edges: [CandidateOwnershipEdge]
    public let issues: [OwnershipGraphIssue]
    public let isPartial: Bool
    /// No observation or empty candidate set is proof of ownership, removal, or cleanup safety.
    public var ownershipVerified: Bool { false }
}
public struct CandidateOwnershipLimits: Sendable {
    public let maximumRecords: Int
    public let maximumApplications: Int
    public let maximumEdges: Int
    public let maximumWork: Int
    public let maximumIssues: Int
    public init(maximumRecords: Int = 4096, maximumApplications: Int = 4096,
                maximumEdges: Int = 16384, maximumWork: Int = 131072, maximumIssues: Int = 4096) {
        self.maximumRecords = max(1, min(maximumRecords, 20000))
        self.maximumApplications = max(1, min(maximumApplications, 20000))
        self.maximumEdges = max(1, min(maximumEdges, 40000))
        self.maximumWork = max(1, min(maximumWork, 262144))
        self.maximumIssues = max(1, min(maximumIssues, 8192))
    }
}

/// Pure, bounded candidate discovery. Never changes presence, capabilities, or an impact graph.
public enum CandidateOwnershipGraphBuilder {
    public static func build(records: [SourceRecord], applications: [OwnershipApplicationObservation],
                             sourceCoverage: [ScanCoverage], generation: String,
                             limits: CandidateOwnershipLimits = .init()) -> CandidateOwnershipGraph {
        var issues: [OwnershipGraphIssue] = []
        var partial = false
        var detailTruncated = false
        func issue(_ kind: OwnershipIssueKind, record: RecordIdentity? = nil, nodes: [String] = [], related: [RecordIdentity] = []) {
            // Bound related payloads as well as issue count. Explicitly signal omitted detail.
            if nodes.count > 64 || related.count > 64 { partial = true; detailTruncated = true }
            let value = OwnershipGraphIssue(kind: kind, recordID: record,
                applicationNodeIDs: Array(nodes.prefix(64)), relatedRecordIDs: Array(related.prefix(64)))
            if issues.count < limits.maximumIssues { issues.append(value) }
            else {
                partial = true
                issues[issues.count - 1] = .init(kind: .inputLimit, recordID: nil, applicationNodeIDs: [], relatedRecordIDs: [])
            }
        }
        if records.count > limits.maximumRecords || applications.count > limits.maximumApplications || sourceCoverage.count > 256 {
            partial = true; issue(.inputLimit)
        }
        let expectedGenerationKnown = known(generation, limit: 256)
        if !expectedGenerationKnown { partial = true; issue(.unknownGeneration) }
        if sourceCoverage.isEmpty || sourceCoverage.prefix(256).contains(where: { $0.state != .completeWithinDeclaredScope || $0.generation != generation }) {
            partial = true; issue(.insufficientCoverage)
        }
        var groups: [String: [OwnershipApplicationObservation]] = [:]
        var order: [String] = []
        for (index, app) in applications.prefix(limits.maximumApplications).enumerated() {
            let identityKnown = known(app.volumeIdentity, limit: 256) && known(app.fileIdentity, limit: 256)
            let key = identityKnown && expectedGenerationKnown && app.generation == generation
                ? [generation, app.volumeIdentity, app.fileIdentity].map { "\($0.utf8.count):\($0)" }.joined()
                : "unidentified-observation:\(index)"
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(app)
        }
        var nodes: [OwnershipApplicationNode] = []
        var bundleIndex: [String: [Int]] = [:]
        var pathIndex: [String: [Int]] = [:]
        for key in order {
            let observations = groups[key]!
            var flags: [OwnershipIssueKind] = []
            if !expectedGenerationKnown || observations.contains(where: { $0.generation != generation }) { flags.append(.unknownGeneration) }
            if observations.contains(where: { !known($0.volumeIdentity, limit: 256) || !known($0.fileIdentity, limit: 256) || !known($0.declaredBundleID, limit: 255) || components($0.path)?.last?.hasSuffix(".app") != true || !$0.observedAt.timeIntervalSince1970.isFinite || $0.signingStatus.utf8.count > 128 || ($0.signingIdentifier?.utf8.count ?? 0) > 4096 || ($0.teamID?.utf8.count ?? 0) > 255 || ($0.designatedRequirement?.utf8.count ?? 0) > 16384 }) {
                flags.append(.unknownIdentity)
            }
            // One physical instance with inconsistent metadata is retained but never associated.
            let claims = Set(observations.map { [$0.declaredBundleID, $0.signingIdentifier ?? "", $0.signingStatus, $0.teamID ?? "", $0.designatedRequirement ?? ""] })
            if claims.count > 1 { flags.append(.conflictingInstanceObservations) }
            if observations.contains(where: { $0.signingIdentifier != nil && $0.signingIdentifier != $0.declaredBundleID }) { flags.append(.differingIdentityHints) }
            let nodeIndex = nodes.count
            nodes.append(.init(id: key, observations: observations, issues: flags))
            for flag in flags { issue(flag, nodes: [key]) }
            guard !flags.contains(.unknownGeneration), !flags.contains(.unknownIdentity), !flags.contains(.conflictingInstanceObservations) else { partial = true; continue }
            let app = observations[0]
            bundleIndex[app.declaredBundleID, default: []].append(nodeIndex)
            // Same-instance aliases remain observations; each observed bundle path can supply a weak hint.
            for path in Set(observations.compactMap { components($0.path).map(canonical) }) {
                pathIndex[path, default: []].append(nodeIndex)
            }
        }
        for identifier in bundleIndex.keys.sorted() {
            let matches = bundleIndex[identifier]!
            if matches.count > 1 { issue(.duplicateBundleIdentifier, nodes: matches.map { nodes[$0].id }) }
        }
        let boundedRecords = Array(records.prefix(limits.maximumRecords))
        var identityCounts: [RecordIdentity: Int] = [:]
        for record in boundedRecords where valid(record.id) { identityCounts[record.id, default: 0] += 1 }
        var edges: [CandidateOwnershipEdge] = []
        var work = 0
        var payloadRecords: [String: [RecordIdentity]] = [:]
        var recordNodes: [RecordIdentity: Set<String>] = [:]
        var exhausted = false
        for record in boundedRecords {
            guard !exhausted else { break }
            guard expectedGenerationKnown, record.generation == generation else { partial = true; issue(.unknownGeneration, record: record.id); continue }
            guard valid(record.id), record.observedAt.timeIntervalSince1970.isFinite else { partial = true; issue(.unknownIdentity, record: record.id); continue }
            guard identityCounts[record.id] == 1 else { partial = true; issue(.ambiguousRecordIdentity, record: record.id); continue }
            guard record.parseWarnings.isEmpty else { partial = true; issue(.unparsedRecord, record: record.id); continue }
            guard record.declaredAppIDs.count <= 32, record.targetReferences.count <= 32 else { partial = true; issue(.inputLimit, record: record.id); continue }
            var candidateReasons: [Int: Set<CandidateOwnershipReason>] = [:]
            var declared = Set<Int>(), located = Set<Int>()
            func add(_ indices: [Int], reason: CandidateOwnershipReason) {
                for index in indices {
                    guard work < limits.maximumWork, edges.count + candidateReasons.count < limits.maximumEdges || candidateReasons[index] != nil else { exhausted = true; return }
                    work += 1
                    candidateReasons[index, default: []].insert(reason)
                    if reason == .declaredBundleIdentifier { declared.insert(index) } else { located.insert(index) }
                }
            }
            for identifier in Set(record.declaredAppIDs).sorted() {
                guard !exhausted else { break }
                guard known(identifier, limit: 255) else { issue(.unknownIdentity, record: record.id); partial = true; continue }
                add(bundleIndex[identifier] ?? [], reason: .declaredBundleIdentifier)
            }
            for target in Set(record.targetReferences).sorted() {
                guard !exhausted else { break }
                guard let parts = components(target) else { issue(.malformedTargetPath, record: record.id); partial = true; continue }
                payloadRecords[canonical(parts), default: []].append(record.id)
                // Component prefixes avoid O(records * installations) and Foo.app/Foo.app.other collisions.
                guard parts.count > 1 else { continue }
                for length in 1..<parts.count {
                    guard !exhausted else { break }
                    guard work < limits.maximumWork else { exhausted = true; break }
                    work += 1
                    add(pathIndex[canonical(Array(parts.prefix(length)))] ?? [], reason: .lexicalTargetWithinBundle)
                }
            }
            if located.count > 1 || (!declared.isEmpty && !located.isEmpty && declared != located) {
                issue(.differingIdentityHints, record: record.id, nodes: declared.union(located).sorted().map { nodes[$0].id })
            }
            if Set(declared.map { nodes[$0].observations[0].declaredBundleID }).count > 1 {
                issue(.possibleSharedPayload, record: record.id, nodes: declared.sorted().map { nodes[$0].id }, related: [record.id])
            }
            for index in candidateReasons.keys.sorted() {
                edges.append(.init(recordID: record.id, applicationNodeID: nodes[index].id,
                    reasons: candidateReasons[index]!.sorted { $0.rawValue < $1.rawValue }))
                recordNodes[record.id, default: []].insert(nodes[index].id)
            }
        }
        if exhausted { partial = true; issue(.inputLimit) }
        // This is only possible sharing; no live owner or runtime state is asserted.
        for payload in payloadRecords.keys.sorted() {
            let related = Array(Set(payloadRecords[payload]!)).sorted { identityText($0) < identityText($1) }
            guard related.count > 1 else { continue }
            let owners = Set(related.flatMap { recordNodes[$0] ?? [] })
            if owners.count > 1 { issue(.possibleSharedPayload, nodes: owners.sorted(), related: related) }
        }
        if detailTruncated { issue(.inputLimit) }
        return .init(generation: generation, applications: nodes, edges: edges, issues: issues, isPartial: partial)
    }
    private static func known(_ text: String, limit: Int) -> Bool {
        !text.isEmpty && text.utf8.count <= limit && text == text.trimmingCharacters(in: .whitespacesAndNewlines)
        && !["unknown", "unverified", "unavailable"].contains(text.lowercased())
        && !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    }
    private static func valid(_ id: RecordIdentity) -> Bool {
        known(id.providerID, limit: 128) && known(id.scope, limit: 256) && known(id.nativeIdentity, limit: 2048)
    }
    private static func components(_ path: String) -> [String]? {
        guard path.hasPrefix("/"), known(path, limit: 4096) else { return nil }
        let parts = path.split(separator: "/").map(String.init)
        guard !parts.isEmpty, parts.count <= 128, !parts.contains("."), !parts.contains("..") else { return nil }
        return parts
    }
    private static func canonical(_ parts: [String]) -> String { "/" + parts.joined(separator: "/") }
    private static func identityText(_ id: RecordIdentity) -> String {
        [id.providerID, id.scope, id.nativeIdentity].map { "\($0.utf8.count):\($0)" }.joined()
    }
}
