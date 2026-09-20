import Foundation
import Darwin
import StatusWireBridge
// Harness-only observation of this process. No paths, commands, IPC, or authority.
guard CommandLine.arguments.count == 1, getuid() > 0, getuid() == geteuid() else { exit(77) }
var session: Int32 = -1
guard RGStatusCurrentAuditSession(&session) else { exit(65) }
print(session)
