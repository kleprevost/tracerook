import Foundation

/// Only bounded, versioned Data DTOs cross XPC. The listener and client both set
/// signing requirements before resume; this protocol itself confers no trust.
@objc public protocol AgentControlProtocol {
    func request(_ frame: Data, reply: @escaping (Data) -> Void)
    func observe()
}
@objc public protocol AgentObserverProtocol { func didChange() }

private final class ClientObserver: NSObject, AgentObserverProtocol, @unchecked Sendable {
    let onChange: @Sendable () -> Void
    init(_ onChange: @escaping @Sendable () -> Void) { self.onChange = onChange }
    func didChange() { onChange() }
}

public final class XPCClient: @unchecked Sendable {
    private let connection: NSXPCConnection
    public init(agent: PeerIdentity, onChange: @escaping @Sendable () -> Void = {}) {
        connection = NSXPCConnection(machServiceName: "com.tracerook.agent.ui")
        connection.remoteObjectInterface = NSXPCInterface(with: AgentControlProtocol.self)
        connection.exportedInterface = NSXPCInterface(with: AgentObserverProtocol.self)
        connection.exportedObject = ClientObserver(onChange)
        connection.setCodeSigningRequirement(agent.requirement)
        connection.resume()
        (connection.remoteObjectProxy as? AgentControlProtocol)?.observe()
    }
    deinit { connection.invalidate() }
    public func call(_ frame: Data) async throws -> Data {
        guard frame.count <= 1_048_580 else { throw IPCError.transport }
        let result = ReplyLatch()
        return try await withCheckedThrowingContinuation { continuation in
            result.install(continuation)
            let proxy = connection.remoteObjectProxyWithErrorHandler { _ in result.finish(.failure(IPCError.transport)) }
            guard let remote = proxy as? AgentControlProtocol else { result.finish(.failure(IPCError.transport)); return }
            remote.request(frame) { data in
                guard data.count <= 1_048_580 else { result.finish(.failure(IPCError.transport)); return }
                result.finish(.success(data))
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 5) { result.finish(.failure(IPCError.timeout)) }
        }
    }
}

private final class ReplyLatch: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Data, any Error>?
    func install(_ value: CheckedContinuation<Data, any Error>) { lock.withLock { continuation = value } }
    func finish(_ value: Result<Data, any Error>) {
        let target = lock.withLock { let target = continuation; continuation = nil; return target }
        target?.resume(with: value)
    }
}
