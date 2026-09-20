import Foundation
import Darwin
import ResiduePlatform

@main struct ResidueBTMExperiment {
    static func main() async {
        let report = await BTMExperiment.run(arguments: Array(CommandLine.arguments.dropFirst()))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        do {
            let data = try encoder.encode(report)
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data([10]))
        } catch { exit(74) }
        if report.refusal != nil { exit(77) }
        if report.failure != nil || report.exitCode != 0 { exit(1) }
    }
}
