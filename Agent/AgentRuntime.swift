import Foundation
import TraceRookContracts
import TraceRookCore
import TraceRookIPC

final class AgentRuntime {
    let store: SessionStore
    let broker: EventBroker
    let control: UIControlService
    let socket: HookSocketServer
    init(bundle: URL, stateDirectory: URL = PrivateStateDirectory.standard) throws {
        let family = try SignedFamily(bundle: bundle)
        store = try SessionStore(directory: stateDirectory)
        broker = EventBroker(store: store, securityMode: family.mode)
        control = UIControlService(broker: broker, app: family.app)
        socket = try HookSocketServer(path: stateDirectory.appendingPathComponent("hook.sock").path, peer: family.hook) { frame in
            let envelope = try WireCodec.decode(HookEnvelopeV2.self, frame: frame)
            let reply = HookReplyV2(requestID: envelope.requestID, decision: .deny, reasonCode: "policy_unavailable",
                explanation: "Local policy is not yet available. No host permission was granted.", decisionSource: .fallback, coverageClass: .other)
            return try WireCodec.encode(reply, maximumBytes: WireLimits.replyBytes)
        }
        control.start()
        Task { [store] in try? await store.retain() }
    }
}

final class UIControlService: NSObject, NSXPCListenerDelegate, @unchecked Sendable {
    private let broker: EventBroker
    private let listener: NSXPCListener
    private let observers = ServiceObservers()
    init(broker: EventBroker, app: PeerIdentity) {
        self.broker = broker
        listener = NSXPCListener(machServiceName: "com.tracerook.agent.ui")
        super.init()
        listener.setConnectionCodeSigningRequirement(app.requirement)
        listener.delegate = self
    }
    func start() { listener.resume() }
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard connection.effectiveUserIdentifier == geteuid() else { return false }
        connection.exportedInterface = NSXPCInterface(with: AgentControlProtocol.self)
        connection.remoteObjectInterface = NSXPCInterface(with: AgentObserverProtocol.self)
        connection.exportedObject = ControlEndpoint(broker: broker, connection: connection, observers: observers)
        connection.resume(); return true
    }
}

private final class ControlEndpoint: NSObject, AgentControlProtocol, @unchecked Sendable {
    let broker: EventBroker
    private weak var connection: NSXPCConnection?
    private let observers: ServiceObservers
    init(broker: EventBroker, connection: NSXPCConnection, observers: ServiceObservers) {
        self.broker = broker; self.connection = connection; self.observers = observers
    }
    func observe() { if let connection { observers.add(connection) } }
    func request(_ frame: Data, reply: @escaping (Data) -> Void) {
        let sender = ReplySender(reply)
        Task {
            guard let request = try? WireCodec.decode(ServiceControlRequest.self, frame: frame, maximumBytes: 16_384) else { sender.send(Data()); return }
            let response = await broker.control(request)
            sender.send((try? WireCodec.encode(response)) ?? Data())
            if request.method != .snapshot { observers.pulse() }
        }
    }
}
private final class ServiceObservers: @unchecked Sendable {
    private let lock = NSLock()
    private var connections: [UUID: NSXPCConnection] = [:]
    func add(_ connection: NSXPCConnection) {
        let id = UUID()
        let added = lock.withLock { guard connections.count < 16 else { return false }; connections[id] = connection; return true }
        guard added else { return }
        connection.invalidationHandler = { [weak self] in self?.remove(id) }
        connection.interruptionHandler = { [weak self] in self?.remove(id) }
    }
    private func remove(_ id: UUID) { lock.withLock { _ = connections.removeValue(forKey: id) } }
    func pulse() {
        let values = lock.withLock { Array(connections.values) }
        for connection in values { (connection.remoteObjectProxy as? AgentObserverProtocol)?.didChange() }
    }
}
private final class ReplySender: @unchecked Sendable {
    let reply: (Data) -> Void
    init(_ reply: @escaping (Data) -> Void) { self.reply = reply }
    func send(_ data: Data) { reply(data) }
}
