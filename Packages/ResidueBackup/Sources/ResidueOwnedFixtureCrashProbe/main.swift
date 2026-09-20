import Foundation
import Darwin
import ResidueQuarantine

#if DEBUG
let arguments = CommandLine.arguments
// Only canonical UUID tokens and a closed checkpoint/verify vocabulary are accepted.
guard arguments.count == 3, let token = UUID(uuidString: arguments[2]), token.uuidString == arguments[2],
      arguments[1] == "verify" || arguments[1] == "bootoutVerify" ||
        OwnedFixtureCrashPhase(rawValue: arguments[1]) != nil || OwnedBootoutCrashPhase(rawValue: arguments[1]) != nil else {
    print("REFUSED: fixed phase and canonical UUID required"); exit(64)
}
do {
    if arguments[1] == "bootoutVerify" { print(try OwnedBootoutCrashLab.verify(token: token)) }
    else if let phase = OwnedBootoutCrashPhase(rawValue: arguments[1]) { try await OwnedBootoutCrashLab.run(phase: phase, token: token) }
    else if arguments[1] == "verify" { print(try await OwnedFixtureCrashLab.verify(token: token)) }
    else { try await OwnedFixtureCrashLab.run(phase: OwnedFixtureCrashPhase(rawValue: arguments[1])!, token: token) }
} catch { print("REFUSED: crash fixture validation failed; no recovery performed"); exit(65) }
#else
print("REFUSED: crash experiment is DEBUG-only")
exit(77)
#endif
