import Foundation
import Darwin
import ResidueQuarantine

guard CommandLine.arguments.count == 1 else { print("REFUSED zero arguments required"); exit(64) }
do { print(try await QuarantineStore.runISO01VirtualMachineBootoutProbe()) }
catch OwnedBootoutEnvironmentError.unsupported {
    print("REFUSED environment gate; mayHaveExecuted=false noAutomaticRetry=true")
    exit(77)
}
catch {
    print("STOPPED mayHaveExecuted=unknown noAutomaticRetry=true automaticBootstrap=false; inspect private intent/outcome")
    exit(65)
}
