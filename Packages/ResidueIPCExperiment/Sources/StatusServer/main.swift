@preconcurrency import Foundation
import Darwin
import StatusWireBridge
import StatusExperimentModel

final class StatusConnection: NSObject, RGStatusWire, @unchecked Sendable {
    private weak var connection: NSXPCConnection?
    private let lock = NSLock()
    private var budget = StatusLabMessageBudget()
    private let uid: UInt32
    private let session: Int32
    init(connection: NSXPCConnection, uid: UInt32, session: Int32) {
        self.connection = connection; self.uid = uid; self.session = session
    }
    func inspectFrame(_ frame: Data, reply: @escaping (Data) -> Void) {
        lock.lock(); defer { lock.unlock() }
        guard let connection, NSXPCConnection.current() === connection,
              StatusLabPolicy.acceptsPeer(actualUID: connection.effectiveUserIdentifier,
                actualSession: connection.auditSessionIdentifier, currentUID: uid, currentSession: session) else {
            reply(StatusLabReply("peerRejected").encoded()); return
        }
        switch budget.next() {
        case .allow(let number): reply(StatusLabPolicy.evaluate(frame, messageNumber: number).encoded())
        case .rejectAndClose:
            reply(StatusLabReply("messageLimit").encoded())
            connection.scheduleSendBarrierBlock { [weak self] in self?.connection?.invalidate() }
        case .closed: connection.invalidate()
        }
    }
}
final class StatusDelegate: NSObject, NSXPCListenerDelegate, @unchecked Sendable {
    let configuration: StatusLabConfiguration
    let session: Int32
    private let lock = NSLock()
    private var connections = 0
    init(configuration: StatusLabConfiguration, session: Int32) { self.configuration = configuration; self.session = session }
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        lock.lock(); defer { lock.unlock() }
        let expectedUID = configuration.scenario == .uidMismatch ? getuid() &+ 1 : getuid()
        let expectedSession = configuration.scenario == .sessionMismatch ? session &+ 1 : session
        guard connections < 4,
              StatusLabPolicy.acceptsPeer(actualUID: connection.effectiveUserIdentifier,
                actualSession: connection.auditSessionIdentifier, currentUID: expectedUID, currentSession: expectedSession),
              RGStatusConfigureRequirement(connection, configuration.peerRequirement) else { return false }
        connections += 1
        connection.exportedInterface = RGStatusInterface()
        connection.exportedObject = StatusConnection(connection: connection, uid: getuid(), session: session)
        connection.invalidationHandler = { exit(0) }
        connection.activate()
        return true
    }
}
guard CommandLine.arguments.count == 1, getuid() > 0 else { exit(64) }
do {
    var session: Int32 = -1
    guard RGStatusCurrentAuditSession(&session) else { exit(65) }
    let configuration = try StatusLabConfiguration.load(server: true)
    let delegate = StatusDelegate(configuration: configuration, session: session)
    let listener = NSXPCListener.service()
    listener.delegate = delegate
    dispatch_after_compat()
    listener.resume()
    withExtendedLifetime(delegate) { dispatchMain() }
} catch { exit(65) }
func dispatch_after_compat() {
    DispatchQueue.global().asyncAfter(deadline: .now() + 12) { exit(0) }
}
