import Foundation
import Darwin
import ResidueQuarantine

guard CommandLine.arguments.count == 1 else { print("REFUSED zero arguments required"); exit(64) }
do {
    let report = try QuarantineStore.inspectISO01VirtualMachineBootoutExperiments()
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
    FileHandle.standardOutput.write(try encoder.encode(report))
    FileHandle.standardOutput.write(Data([10]))
} catch OwnedBootoutEnvironmentError.unsupported {
    print("REFUSED environment gate; inspectionOnly=true mutationAvailable=false"); exit(77)
} catch {
    print("UNAVAILABLE fixed experiment audit; inspectionOnly=true mutationAvailable=false"); exit(65)
}
