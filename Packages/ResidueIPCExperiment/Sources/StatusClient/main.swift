@preconcurrency import Foundation
import Darwin
import StatusWireBridge
import StatusExperimentModel
import OSLog

final class ReplyBox: @unchecked Sendable {
    private let lock = NSLock()
    private var result: String?
    let semaphore = DispatchSemaphore(value: 0)
    func finish(_ value: String) {
        lock.lock(); defer { lock.unlock() }
        if result == nil { result = value; semaphore.signal() }
    }
    func wait() -> String {
        guard semaphore.wait(timeout: .now() + 3) == .success else { return "timeout" }
        lock.lock(); defer { lock.unlock() }; return result ?? "error"
    }
}
final class ConnectionBox: @unchecked Sendable {
    let value: NSXPCConnection
    private let lock = NSLock()
    private var binding = StatusObservedServerSession()
    init(_ value: NSXPCConnection) {
        self.value = value
        value.invalidationHandler = { [weak self] in self?.invalidate() }
        value.interruptionHandler = { [weak self] in self?.invalidate() }
    }
    func accept(session: Int32, uid: UInt32) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return binding.accept(actualUID: uid, expectedUID: getuid(), session: session)
    }
    func invalidate() { lock.lock(); binding.invalidate(); lock.unlock() }

}
func request(_ frame: Data, peer: ConnectionBox) -> String {
    let box = ReplyBox(), connection = peer.value
    guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
        let value = error as NSError
        let domain = value.domain
        let safeDomain = domain.utf8.count <= 96 && domain.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || [45, 46, 95].contains($0) }) ? domain : "unrecognizedDomain"
        Logger(subsystem: "example.residueguard.status-wire", category: "client")
            .error("stage=C_TRANSPORT_REJECTED domain=\(safeDomain, privacy: .public) code=\(value.code, privacy: .public)")
        peer.invalidate(); box.finish("transportRejected")
    }) as? RGStatusWire else { return "transportRejected" }
    proxy.inspectFrame(frame) { data in
        guard let reply = try? StatusLabReply.decode(data),
              peer.accept(session: peer.value.auditSessionIdentifier, uid: peer.value.effectiveUserIdentifier) else {
            peer.invalidate(); box.finish("peerRejected"); return
        }
        box.finish(reply.outcome)
    }
    let outcome = box.wait()
    if outcome == "timeout" { peer.invalidate(); connection.invalidate() }
    return outcome
}
guard CommandLine.arguments.count == 1, getuid() > 0 else { exit(64) }
do {
    DispatchQueue.global().asyncAfter(deadline: .now() + 10) { exit(70) }
    var session: Int32 = -1
    guard RGStatusCurrentAuditSession(&session) else { exit(65) }
    let configuration = try StatusLabConfiguration.load(server: false)
    guard session == configuration.expectedCallerSession else {
        Logger(subsystem: "example.residueguard.status-wire", category: "client").error("stage=C_CALLER_SESSION_REJECTED")
        exit(65)
    }
    let connection = NSXPCConnection(serviceName: "example.residueguard.status-wire.server")
    connection.remoteObjectInterface = RGStatusInterface()
    guard RGStatusConfigureRequirement(connection, configuration.peerRequirement) else { exit(65) }
    let peer = ConnectionBox(connection)
    connection.activate()
    defer { connection.invalidate() }
    let frame = try StatusLabPolicy.frame(for: configuration.scenario)
    var outcomes: [String] = []
    if configuration.scenario == .messageLimit {
        for _ in 0..<9 {
            let outcome = request(frame, peer: peer); outcomes.append(outcome)
            if outcome == "timeout" || outcome == "transportRejected" || outcome == "peerRejected" { break }
        }
    } else if configuration.scenario == .connectionLimit {
        var retained = [peer]
        for index in 0..<5 {
            let candidate: NSXPCConnection
            let candidatePeer: ConnectionBox
            if index == 0 { candidate = connection; candidatePeer = peer }
            else {
                candidate = NSXPCConnection(serviceName: "example.residueguard.status-wire.server")
                candidate.remoteObjectInterface = RGStatusInterface()
                guard RGStatusConfigureRequirement(candidate, configuration.peerRequirement) else { exit(65) }
                candidatePeer = ConnectionBox(candidate)
                candidate.activate(); retained.append(candidatePeer)
            }
            let outcome = request(frame, peer: candidatePeer); outcomes.append(outcome)
            if outcome != "statusOnly" { break }
        }
        withExtendedLifetime(retained) {}
    } else if configuration.scenario == .invalidatedConnection {
        outcomes.append(request(frame, peer: peer))
        if outcomes.last == "statusOnly" {
            peer.invalidate(); connection.invalidate()
            outcomes.append(request(frame, peer: peer))
        }
    } else { outcomes.append(request(frame, peer: peer)) }
    let report: [String: Any] = ["case": configuration.scenario.rawValue, "outcomes": outcomes,
        "transportExperimentOnly": true, "manifestTrustedForProduction": false, "authorizesMutation": false]
    let data = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
    FileHandle.standardOutput.write(data); FileHandle.standardOutput.write(Data([10]))
    exit(outcomes.contains("timeout") ? 2 : 0)
} catch { print("REFUSED status experiment configuration"); exit(65) }
