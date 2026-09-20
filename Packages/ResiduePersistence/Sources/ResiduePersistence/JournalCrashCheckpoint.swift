#if DEBUG
import Foundation

/// Internal deterministic test seam, absent from Release. Set only by the test
/// subprocess; TaskLocal scope prevents other concurrent tests seeing the hook.
enum JournalCrashCheckpoint {
    @TaskLocal static var beforeCommit: (@Sendable (String) -> Void)?
}
#endif
