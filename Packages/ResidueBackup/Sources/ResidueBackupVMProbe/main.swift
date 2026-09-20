import Foundation
import ResidueBackup
import Darwin

guard CommandLine.arguments.count == 1 else { print("REFUSED: no arguments accepted"); exit(64) }
do { print(try VerifiedBackup.runISO01VirtualMachineProbe()) }
catch VMLabProbeError.virtualMachineRequired { print("REFUSED: non-root VirtualMac guest required"); exit(77) }
catch { print("REFUSED: fixed ISO01 backup validation failed; no source or service mutation"); exit(65) }
