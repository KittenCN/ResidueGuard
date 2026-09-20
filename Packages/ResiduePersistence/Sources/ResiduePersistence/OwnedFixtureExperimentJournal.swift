import Foundation
import CryptoKit
import Darwin

/// Records only a fixed owned ISO01 experiment. Never executes or resumes an action,
/// creates a Core verified plan, imports reports, or consumes transaction nonces.
public actor OwnedFixtureExperimentJournal {
    private let storage: OwnedExperimentStorage
    public init(directoryFD: Int32, createNew: Bool = false, readOnly: Bool = false) throws {
        storage = try OwnedExperimentStorage(directoryFD: directoryFD, createNew: createNew, readOnly: readOnly)
    }
    public func create(plan: OwnedFixtureExperimentPlan) throws {
        try storage.transaction {
            var entries = try readEntries()
            guard !entries.contains(where: { $0.plan.id == plan.id }) else { throw JournalError.replay }
            guard entries.count < 128 else { throw JournalError.resourceLimit }
            let entry = OwnedFixtureExperimentEntry(plan: plan, steps: [])
            try validate(entry)
            entries.append(entry)
            try write(entry, insert: true)
        }
    }
    /// Must commit successfully before the caller considers performing its fixed experiment step.
    public func prepare(planID: UUID, phase: OwnedFixtureExperimentPhase, backup: OwnedFixtureBackupEvidence, at: Date = Date()) throws {
        try storage.transaction {
            var entry = try requireEntry(planID)
            guard at >= entry.plan.createdAt, at <= entry.plan.expiresAt else { throw JournalError.invalidTransition }
            if phase == .isolation { guard entry.steps.isEmpty else { throw JournalError.invalidTransition } }
            else {
                guard entry.steps.count == 1, let effects = entry.steps[0].effects,
                      effects.file == .quarantinedVerified, effects.runtime == .observedRegisteredNotRunning,
                      sameBackup(entry.steps[0].backup, backup) else { throw JournalError.invalidTransition }
            }
            entry.steps.append(.init(phase: phase, backup: backup, preparedAt: at, effects: nil, recordedAt: nil))
            try validate(entry); try write(entry, insert: false)
        }
    }
    /// Results are historical observations, not fresh authorization. Recording after
    /// plan expiry remains allowed so outcomes are not lost. A pending step cannot retry.
    public func recordResult(planID: UUID, phase: OwnedFixtureExperimentPhase, effects: OwnedFixtureExperimentEffects, at: Date = Date()) throws {
        try storage.transaction {
            var entry = try requireEntry(planID)
            guard let index = entry.steps.indices.last, entry.steps[index].phase == phase,
                  entry.steps[index].effects == nil else { throw JournalError.invalidTransition }
            entry.steps[index].effects = effects; entry.steps[index].recordedAt = at
            try validate(entry); try write(entry, insert: false)
        }
    }
    public func entries() throws -> [OwnedFixtureExperimentEntry] { try storage.snapshot { try readEntries() } }
    private func requireEntry(_ id: UUID) throws -> OwnedFixtureExperimentEntry {
        guard let entry = try readEntries().first(where: { $0.plan.id == id }) else { throw JournalError.invalidTransition }
        return entry
    }
    private struct Envelope: Codable {
        let version: Int
        let profile: String
        let registration: String
        let permission: String
        let entry: OwnedFixtureExperimentEntry
    }
    private func encoded(_ entry: OwnedFixtureExperimentEntry) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(Envelope(version: 1, profile: entry.plan.profile, registration: "noMutation", permission: "noMutation", entry: entry))
    }
    private func write(_ entry: OwnedFixtureExperimentEntry, insert: Bool) throws {
        let data = try encoded(entry)
        guard data.count <= 131072 else { throw JournalError.resourceLimit }
        let payload = String(decoding: data, as: UTF8.self), digest = Self.hash(data)
        if insert { try storage.execute("INSERT INTO experiments(id,payload,digest) VALUES(?,?,?)", [entry.plan.id.uuidString, payload, digest]) }
        else { try storage.execute("UPDATE experiments SET payload=?,digest=? WHERE id=?", [payload, digest, entry.plan.id.uuidString]) }
        _ = try readEntries()
    }
    private func readEntries() throws -> [OwnedFixtureExperimentEntry] {
        guard try storage.integer("SELECT count(*) FROM experiments") <= 128,
              try storage.integer("SELECT coalesce(sum(length(CAST(payload AS BLOB))),0) FROM experiments") <= 8 * 1024 * 1024,
              try storage.integer("SELECT count(*) FROM experiments WHERE length(CAST(payload AS BLOB))>131072 OR length(id)>36 OR length(digest)>64") == 0 else { throw JournalError.resourceLimit }
        return try storage.rows("SELECT id,payload,digest FROM experiments ORDER BY id").map { row in
            guard let id = row[0], let payload = row[1], let digest = row[2] else { throw JournalError.storageFailure }
            let data = Data(payload.utf8)
            guard Self.hash(data) == digest else { throw JournalError.storageFailure }
            let envelope: Envelope
            do { envelope = try JSONDecoder().decode(Envelope.self, from: data) } catch { throw JournalError.storageFailure }
            guard envelope.version == 1, envelope.profile == envelope.entry.plan.profile,
                  envelope.registration == "noMutation", envelope.permission == "noMutation" else { throw JournalError.unsupportedSchema }
            guard envelope.entry.plan.id.uuidString == id, try encoded(envelope.entry) == data else { throw JournalError.storageFailure }
            try validate(envelope.entry)
            return envelope.entry
        }
    }
    private func sameBackup(_ prior: OwnedFixtureBackupEvidence, _ next: OwnedFixtureBackupEvidence) -> Bool {
        prior.backupID == next.backupID && prior.planID == next.planID && prior.root == next.root
        && prior.contentSHA256 == next.contentSHA256 && prior.metadataSHA256 == next.metadataSHA256
        && prior.manifestSHA256 == next.manifestSHA256 && next.observedAt >= prior.observedAt
    }
    private static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private func validate(_ entry: OwnedFixtureExperimentEntry) throws {
        let p = entry.plan
        func known(_ s: String, _ count: Int) -> Bool { !s.isEmpty && s.utf8.count <= count && !s.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) }
        func digest(_ s: String) -> Bool { s.utf8.count == 64 && s.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) } }
        func file(_ f: OwnedFixtureFileIdentity) -> Bool {
            f.inode > 0 && f.size >= 0 && f.size <= 16 * 1024 * 1024 && digest(f.sha256)
            && (0..<1_000_000_000).contains(f.modifiedNanos) && (0..<1_000_000_000).contains(f.changedNanos)
            && f.extendedAttributes.count <= 32 && f.extendedAttributes.allSatisfy { known($0.key, 256) && $0.value.count <= 16384 }
            && f.extendedAttributes.values.reduce(0, { $0 + $1.count }) <= 32768
        }
        guard p.userID > 0, p.userID == geteuid(), p.osBuild == "26A428", p.createdAt.timeIntervalSince1970.isFinite,
              p.expiresAt.timeIntervalSince1970.isFinite, p.expiresAt > p.createdAt,
              p.expiresAt.timeIntervalSince(p.createdAt) <= 3600, file(p.source), file(p.program),
              p.source.mode & 0o170000 == 0o100000, p.program.mode & 0o170000 == 0o100000,
              p.source.mode & 0o022 == 0, p.program.mode & 0o022 == 0,
              p.source.device == p.sourceRoot.device, p.quarantineRoot.device == p.source.device,
              p.source.owner == p.userID, p.program.owner == p.userID, p.sourceRoot.owner == p.userID, p.sourceRoot.inode > 0,
              p.quarantineRoot.owner == p.userID, p.quarantineRoot.inode > 0,
              entry.steps.count <= 2 else { throw JournalError.invalidInput }
        let metadataEncoder = JSONEncoder(); metadataEncoder.outputFormatting = [.sortedKeys]
        let sourceMetadataDigest = Self.hash(try metadataEncoder.encode(p.source))
        for (index, step) in entry.steps.enumerated() {
            let backup = step.backup, root = backup.root
            guard step.phase == (index == 0 ? .isolation : .restoration), backup.planID == p.id,
                  backup.contentSHA256 == p.source.sha256, backup.metadataSHA256 == sourceMetadataDigest, digest(backup.manifestSHA256),
                  root.owner == p.userID, root.inode > 0, root.parentInode > 0,
                  root.directoryName == "ResidueGuard-VM-VerifiedBackup-" + root.rootID.uuidString,
                  root.device == p.source.device, root.parentDevice == root.device,
                  backup.observedAt.timeIntervalSince1970.isFinite, backup.observedAt >= p.createdAt,
                  backup.observedAt <= step.preparedAt, step.preparedAt.timeIntervalSince(backup.observedAt) <= 120, step.preparedAt >= p.createdAt, step.preparedAt <= p.expiresAt else { throw JournalError.invalidInput }
            if index == 1 {
                guard let previous = entry.steps[0].effects, previous.file == .quarantinedVerified,
                      previous.runtime == .observedRegisteredNotRunning, sameBackup(entry.steps[0].backup, backup),
                      let previousTime = entry.steps[0].recordedAt, step.preparedAt >= previousTime else { throw JournalError.invalidTransition }
            }
            guard (step.effects == nil) == (step.recordedAt == nil) else { throw JournalError.invalidInput }
            if let effects = step.effects, let date = step.recordedAt {
                guard date.timeIntervalSince1970.isFinite, date >= step.preparedAt,
                      effects.sourceObject.map(file) ?? true, effects.quarantineObject.map(file) ?? true else { throw JournalError.invalidInput }
                if let runtime = effects.runtimeEvidence {
                    let failures = ["none", "invalidRequest", "launchFailed", "timedOut", "cancelled", "outputLimit", "ioFailure"]
                    let coverage = ["completeWithinDeclaredScope", "partial", "permissionDenied", "unsupported", "failed", "cancelled"]
                    func token(_ value: String) -> Bool {
                        !value.isEmpty && value.utf8.count <= 128 && value.utf8.allSatisfy {
                            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || [45, 46, 95].contains($0)
                        }
                    }
                    guard runtime.generation.utf8.count == 36, UUID(uuidString: runtime.generation) != nil,
                          runtime.providerID == "launchd.runtime", runtime.scope == "gui/\(p.userID)", runtime.nativeLabel == p.label,
                          token(runtime.osBuild), token(runtime.parserProfile), digest(runtime.stdoutSHA256),
                          failures.contains(runtime.captureFailure), coverage.contains(runtime.coverage),
                          ["running", "registeredNotRunning", "unknown"].contains(runtime.state),
                          runtime.observedAt.timeIntervalSince1970.isFinite, runtime.observedAt >= step.preparedAt,
                          runtime.observedAt <= date, date.timeIntervalSince(runtime.observedAt) <= 120 else { throw JournalError.invalidInput }
                    if effects.runtime == .observedRegisteredNotRunning {
                        guard runtime.osBuild == p.osBuild, runtime.parserProfile == "launchctl-print-gui-26A428-v1",
                              runtime.exitCode == 0, runtime.captureFailure == "none", !runtime.outputTruncated,
                              runtime.coverage == "completeWithinDeclaredScope", runtime.state == "registeredNotRunning" else { throw JournalError.invalidInput }
                    }
                }
                guard step.phase == .isolation ? effects.file != .restoredVerified : effects.file != .quarantinedVerified else { throw JournalError.invalidInput }
                func matchesSource(_ observed: OwnedFixtureFileIdentity?) -> Bool {
                    guard let observed else { return false }
                    let source = p.source
                    return observed.device == source.device && observed.inode == source.inode
                        && observed.owner == source.owner && observed.group == source.group && observed.mode == source.mode
                        && observed.size == source.size && observed.sha256 == source.sha256
                        && observed.modifiedSeconds == source.modifiedSeconds && observed.modifiedNanos == source.modifiedNanos
                        && observed.extendedAttributes == source.extendedAttributes
                    // rename may legitimately change ctime; it is still retained as an observation.
                }
                if effects.file == .quarantinedVerified {
                    guard matchesSource(effects.quarantineObject), effects.sourceObject == nil else { throw JournalError.invalidInput }
                }
                if effects.file == .restoredVerified {
                    guard matchesSource(effects.sourceObject), effects.quarantineObject == nil else { throw JournalError.invalidInput }
                }
            }
        }
    }
}
