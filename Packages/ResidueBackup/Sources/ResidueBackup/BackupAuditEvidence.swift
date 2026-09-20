import Foundation
import Darwin

/// Package-only observation. No public/decoding initializer and no execution authority.
package struct BackupAuditEvidence: Sendable {
    package let backupID: UUID
    package let planID: UUID
    package let root: BackupAuditRootLocator
    package let contentSHA256: String
    package let metadataSHA256: String
    package let manifestSHA256: String
    package let metadataFormat = "source-fingerprint-json-sorted-keys-v1"
    package let observedAt: Date
    package let authorizesMutation = false
    init(backupID: UUID, planID: UUID, root: BackupAuditRootLocator, contentSHA256: String,
         metadataSHA256: String, manifestSHA256: String, observedAt: Date) {
        self.backupID = backupID; self.planID = planID; self.root = root
        self.contentSHA256 = contentSHA256; self.metadataSHA256 = metadataSHA256
        self.manifestSHA256 = manifestSHA256; self.observedAt = observedAt
    }
}

package struct BackupAuditRootLocator: Sendable, Equatable {
    package enum Namespace: String, Sendable { case ownedISO01VM, temporaryFixture }
    package let namespace: Namespace
    package let rootID: UUID
    package let directoryName: String
    package let parentDevice: Int32
    package let parentInode: UInt64
    package let device: Int32
    package let inode: UInt64
    package let owner: UInt32
    init(namespace: Namespace, rootID: UUID, directoryName: String, parent: stat, root: stat) {
        self.namespace = namespace; self.rootID = rootID; self.directoryName = directoryName
        parentDevice = parent.st_dev; parentInode = parent.st_ino
        device = root.st_dev; inode = root.st_ino; owner = root.st_uid
    }
}

final class BackupAuditRootAnchor {
    let parentFD: Int32
    let locator: BackupAuditRootLocator
    // Only the fixed owned-VM factory supplies this path, never a public caller.
    let fixedParentPath: String?
    init(parentFD: Int32, locator: BackupAuditRootLocator, fixedParentPath: String?) throws {
        let copy = dup(parentFD)
        guard copy >= 0 else { throw BackupFailure.io }
        self.parentFD = copy; self.locator = locator; self.fixedParentPath = fixedParentPath
    }
    deinit { close(parentFD) }
}
