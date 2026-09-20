@preconcurrency import Foundation
import Darwin
import StatusWireBridge
import StatusExperimentModel
import OSLog

private enum ServerStage: String {
    case entry = "S_ENTRY", entryRefused = "S_ENTRY_REFUSED"
    case sessionQueryFailed = "S_SESSION_QUERY_FAILED", sessionUnknown = "S_SESSION_UNKNOWN", sessionReady = "S_SESSION_READY"
    case configLoading = "S_CONFIG_LOADING", configReady = "S_CONFIG_READY", configFailed = "S_CONFIG_FAILED"
    case listenerStarting = "S_LISTENER_STARTING", listenerCalled = "S_LISTENER_CALLED"
    case connectionLimit = "S_CONNECTION_LIMIT", peerUIDRejected = "S_PEER_UID_REJECTED", peerSessionRejected = "S_PEER_SESSION_REJECTED"
    case peerReady = "S_PEER_READY", pinRejected = "S_PIN_REJECTED", pinReady = "S_PIN_READY"
    case activated = "S_ACTIVATED", invalidated = "S_INVALIDATED", requestCalled = "S_REQUEST_CALLED"
    case currentConnectionRejected = "S_CURRENT_CONNECTION_REJECTED", requestPeerRejected = "S_REQUEST_PEER_REJECTED"
    case watchdog = "S_WATCHDOG"
}
private let stageLogger = Logger(subsystem: "example.residueguard.status-wire", category: "server")
private func stage(_ value: ServerStage) { stageLogger.notice("stage=\(value.rawValue, privacy: .public)") }


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
        stage(.requestCalled)
        guard let connection, NSXPCConnection.current() === connection else {
            stage(.currentConnectionRejected); reply(StatusLabReply("peerRejected").encoded()); return
        }
        guard StatusLabPolicy.acceptsPeer(actualUID: connection.effectiveUserIdentifier,
                actualSession: connection.auditSessionIdentifier, expectedUID: uid, expectedSession: session) else {
            stage(.requestPeerRejected); reply(StatusLabReply("peerRejected").encoded()); return
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
    private let lock = NSLock()
    private var connections = 0
    init(configuration: StatusLabConfiguration) { self.configuration = configuration }
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        lock.lock(); defer { lock.unlock() }
        let expectedUID = configuration.scenario == .uidMismatch ? getuid() &+ 1 : getuid()
        let callerSession = configuration.expectedCallerSession
        let expectedSession = configuration.scenario == .sessionMismatch ? (callerSession == Int32.max ? 1 : callerSession + 1) : callerSession
        stage(.listenerCalled)
        guard connections < 4 else { stage(.connectionLimit); return false }
        guard expectedUID > 0, connection.effectiveUserIdentifier == expectedUID else { stage(.peerUIDRejected); return false }
        guard expectedSession > 0, connection.auditSessionIdentifier == expectedSession else { stage(.peerSessionRejected); return false }
        stage(.peerReady)
        guard RGStatusConfigureRequirement(connection, configuration.peerRequirement) else { stage(.pinRejected); return false }
        stage(.pinReady)
        connections += 1
        connection.exportedInterface = RGStatusInterface()
        connection.exportedObject = StatusConnection(connection: connection, uid: getuid(), session: expectedSession)
        connection.invalidationHandler = { stage(.invalidated); exit(0) }
        connection.activate()
        stage(.activated)
        return true
    }
}
stage(.entry)
guard CommandLine.arguments.count == 1, getuid() > 0 else { stage(.entryRefused); exit(64) }
do {
    var session: Int32 = -1
    switch RGStatusAuditSessionResult(&session) {
    case 0: stage(.sessionReady)
    case 1: stage(.sessionQueryFailed); exit(65)
    default: stage(.sessionUnknown); exit(65)
    }
    stage(.configLoading)
    let configuration = try StatusLabConfiguration.load(server: true)
    stage(.configReady)
    let delegate = StatusDelegate(configuration: configuration)
    let listener = NSXPCListener.service()
    listener.delegate = delegate
    dispatch_after_compat()
    stage(.listenerStarting)
    listener.resume()
    withExtendedLifetime(delegate) { dispatchMain() }
} catch { stage(.configFailed); exit(65) }
func dispatch_after_compat() {
    DispatchQueue.global().asyncAfter(deadline: .now() + 12) { stage(.watchdog); exit(0) }
}
