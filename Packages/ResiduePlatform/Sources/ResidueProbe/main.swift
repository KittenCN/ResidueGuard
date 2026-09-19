import Foundation
import ResiduePlatform

@main struct ResidueProbe {
    static func main() async {
        guard CommandLine.arguments == [CommandLine.arguments[0], "--host-readonly"] else {
            print("No scan performed. Explicit --host-readonly required.")
            return
        }
        let snapshot = await ScanService().scan()
        print("readOnly=true mutationAvailable=false")
        print("rows=\(snapshot.rows.count) applicationInstances=\(snapshot.applications.count) cancelled=\(snapshot.isCancelled)")
        for source in snapshot.coverage {
            // Deliberately exclude roots, record identities, raw payloads and error paths.
            print("provider=\(source.providerID) state=\(source.state.rawValue) parsed=\(source.parsedCount) unparsed=\(source.unparsedCount) errors=\(source.errors.count) skipped=\(source.skippedAreas.count)")
        }
        let red = snapshot.rows.filter { $0.presence.rawValue == "highConfidenceOrphan" }.count
        print("highConfidenceOrphans=\(red)")
    }
}
