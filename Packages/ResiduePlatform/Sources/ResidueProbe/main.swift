import Foundation
import ResiduePlatform
import Darwin

@main struct ResidueProbe {
    static func main() async {
        guard CommandLine.arguments.count == 2 else {
            rejectArguments()
        }
        switch CommandLine.arguments[1] {
        case "--vm-fixture-runtime":
            await probeVMFixture()
            return
        case "--host-readonly": break
        default: rejectArguments()
        }
        let snapshot = await ScanService().scan()
        print("readOnly=true mutationAvailable=false")
        print("rows=\(snapshot.rows.count) applicationInstances=\(snapshot.applications.count) cancelled=\(snapshot.isCancelled)")
        for source in snapshot.coverage {
            // Deliberately exclude roots, record identities, raw payloads and error paths.
            print("provider=\(source.providerID) state=\(source.state.rawValue) parsed=\(source.parsedCount) unparsed=\(source.unparsedCount) errors=\(source.errors.count) skipped=\(source.skippedAreas.count)")
        }
        for status in Set(snapshot.applications.map(\.signingStatus)).sorted() {
            print("signingStatus=\(status) count=\(snapshot.applications.filter { $0.signingStatus == status }.count)")
        }
        let red = snapshot.rows.filter { $0.presence.rawValue == "highConfidenceOrphan" }.count
        print("highConfidenceOrphans=\(red)")
    }

    private static func rejectArguments() -> Never {
        print("No scan performed. Expected exactly --host-readonly or --vm-fixture-runtime.")
        exit(64)
    }

    private static func probeVMFixture() async {
        var length = 0
        guard getuid() != 0,
              sysctlbyname("hw.model", nil, &length, nil, 0) == 0,
              length > 0, length <= 256 else {
            print("readOnly=true mutationAvailable=false refused=vmProfileRequired")
            exit(77)
        }
        var model = [CChar](repeating: 0, count: length)
        guard sysctlbyname("hw.model", &model, &length, nil, 0) == 0,
              model.withUnsafeBufferPointer({ String(cString: $0.baseAddress!) }).hasPrefix("VirtualMac") else {
            print("readOnly=true mutationAvailable=false refused=vmProfileRequired")
            exit(77)
        }
        // Fixed self-owned fixture only. No CLI/environment-supplied identity or path.
        let home = FileManager.default.homeDirectoryForCurrentUser
        let expected = LaunchRuntimeIdentity(userID: getuid(), label: "example.residueguard.fixture.iso01",
            sourcePath: home.appendingPathComponent("Library/LaunchAgents/example.residueguard.fixture.iso01.plist").path,
            program: home.appendingPathComponent("Library/ResidueGuard-VM-ISO01/fixture").path)
        let observation = await LaunchRuntimeCollector(configuration: .exactCurrentUserService(profile: LaunchRuntimeParser.profile))
            .collect(expected: expected, generation: UUID().uuidString)
        print("readOnly=true mutationAvailable=false fixture=iso01")
        print("runtimeState=\(observation.state.rawValue) coverage=\(observation.coverage.state.rawValue)")
        print("captureFailure=\(observation.provenance.rawMetadata["captureFailure"] ?? "unavailable") exitCode=\(observation.provenance.rawMetadata["exitCode"] ?? "unavailable")")
        print("profile=\(LaunchRuntimeParser.profile) parsed=\(observation.coverage.parsedCount) unparsed=\(observation.coverage.unparsedCount)")
        print("absenceProven=false signingIdentityProven=false")
    }
}
