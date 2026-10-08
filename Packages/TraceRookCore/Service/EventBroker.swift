import Foundation
import TraceRookContracts

public actor EventBroker {
    public let store: SessionStore
    public let reviews: ApprovalCoordinator
    public let securityMode: ServiceSecurityMode
    private var mutations: [UUID: ContinuousClock.Instant] = [:]
    private let localAPIDemo: LocalAPIDemoClient?
    public init(store: SessionStore, securityMode: ServiceSecurityMode, localAPIDemo: LocalAPIDemoClient? = nil) {
        self.store = store; self.securityMode = securityMode; reviews = ApprovalCoordinator(store: store)
        self.localAPIDemo = localAPIDemo
    }
    public func control(_ request: ServiceControlRequest) async -> ServiceControlReply {
        do {
            try request.validate()
            if request.method != .snapshot {
                let now = ContinuousClock().now
                mutations = mutations.filter { now.duration(to: $0.value) > .zero }
                guard mutations[request.requestID] == nil else { return ServiceControlReply(requestID: request.requestID, error: .invalidRequest) }
                guard mutations.count < 512 else { return ServiceControlReply(requestID: request.requestID, error: .unavailable) }
                mutations[request.requestID] = now.advanced(by: .seconds(300))
            }
            switch request.method {
            case .snapshot:
                guard case .number(let value) = request.payload["limit"] else { throw TraceRookError.malformedInput }
                let snapshot = try await store.snapshot(mode: securityMode, limit: NSDecimalNumber(decimal: value).intValue,
                    requests: await reviews.activeRequests())
                return ServiceControlReply(requestID: request.requestID, payload: try JSONValue.decodeBounded(JSONEncoder().encode(snapshot)))
            case .resolveReview:
                let resolution = try WireCodec.decodePayload(ReviewResolution.self, payload: request.payload.canonicalData(), maximumBytes: 16_384)
                try await reviews.resolve(resolution)
            case .clearHistory:
                await reviews.abortAll(); try await store.clearHistory()
            case .simulatedIngestion:
                guard securityMode == .developer else { return ServiceControlReply(requestID: request.requestID, error: .forbidden) }
                let event = AgentEvent(agent: .claudeCode, sourceSessionID: "service-simulation", sourceToolCallID: UUID().uuidString,
                    kind: .preToolUse, cwd: "[PROJECT]", toolName: "Bash", actionType: .shellExec,
                    argsSummary: "SIMULATED INGESTION · No host tool was running", actionFingerprint: String(repeating: "0", count: 64))
                _ = try await store.record(event, provenance: .serviceSimulation)
            case .localAPIDemo:
                guard securityMode == .developer, let localAPIDemo else {
                    return ServiceControlReply(requestID: request.requestID, error: .forbidden)
                }
                let command = try WireCodec.decodePayload(LocalAPIDemoControl.self, payload: request.payload.canonicalData(), maximumBytes: WireLimits.replyBytes)
                let status = await localAPIDemo.control(command)
                return ServiceControlReply(requestID: request.requestID, payload: try JSONValue.decodeBounded(WireCodec.encodePayload(status, maximumBytes: WireLimits.replyBytes)))
            }
            return ServiceControlReply(requestID: request.requestID)
        } catch TraceRookError.wrongBinding { return ServiceControlReply(requestID: request.requestID, error: .wrongBinding) }
        catch TraceRookError.staleApproval { return ServiceControlReply(requestID: request.requestID, error: .staleReview) }
        catch { return ServiceControlReply(requestID: request.requestID, error: .storageFailure) }
    }
}
