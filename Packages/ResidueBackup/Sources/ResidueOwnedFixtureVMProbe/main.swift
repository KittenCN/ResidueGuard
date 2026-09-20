import Foundation
import Darwin
import ResidueBackup
import ResidueQuarantine

guard CommandLine.arguments.count == 1 else { print("REFUSED: no arguments accepted"); exit(64) }
do { print(try await QuarantineStore.runISO01VirtualMachineProbe()) }
catch VMLabProbeError.virtualMachineRequired { print("REFUSED: non-root VirtualMac guest required"); exit(77) }
catch let failure as OwnedFixtureProbeFailure {
    print("STOPPED phase=\(failure.phase.rawValue) fileState=\(failure.fileState.rawValue) backupID=\(failure.backupID?.uuidString ?? "none"); no automatic compensation; inspect retained evidence")
    exit(65)
}
catch { print("REFUSED: fixed ISO01 validation or backup failed; no automatic compensation"); exit(65) }
