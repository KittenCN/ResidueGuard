import Foundation
import Darwin
import ResidueBackup
import ResidueQuarantine

guard CommandLine.arguments.count == 1 else { print("REFUSED: no arguments accepted"); exit(64) }
do {
    let report = try await QuarantineStore.inspectISO01VirtualMachineExperiments()
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
    FileHandle.standardOutput.write(try encoder.encode(report))
    FileHandle.standardOutput.write(Data([10]))
    if report.coverage != "complete" || report.failedJournals > 0 { exit(1) }
} catch VMLabProbeError.virtualMachineRequired {
    print("REFUSED: supported non-root VirtualMac guest required"); exit(77)
} catch { print("REFUSED: fixed owned experiment inspection unavailable; no actions performed"); exit(65) }
