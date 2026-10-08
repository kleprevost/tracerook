import Foundation
import TraceRookContracts
import TraceRookPrivacy

public enum ServiceSecurityMode: String, Codable, Sendable { case developer, developerID = "developer_id" }
public enum ActivityProvenance: String, Codable, Sendable { case hostHook = "host_hook", serviceSimulation = "service_simulation" }

/// UI transport only. The hook decoder cannot accept this method set.
public enum ControlMethod: String, Codable, Sendable {
    case snapshot, resolveReview = "resolve_review", clearHistory = "clear_history"
    case simulatedIngestion = "simulated_ingestion"
    case localAPIDemo = "local_api_demo"
}
public struct ServiceControlRequest: IPCMessage {
    public let protocolVersion: Int
    public let requestID: UUID
    public let method: ControlMethod
    public let payload: JSONValue
    public init(requestID: UUID = UUID(), method: ControlMethod, payload: JSONValue = .object([:])) {
        protocolVersion = TraceRookVersion.liveIPC; self.requestID = requestID; self.method = method; self.payload = payload
    }
    public static let wireKeys: Set<String> = ["protocolVersion", "requestID", "method", "payload"]
    public func validate() throws {
        guard protocolVersion == TraceRookVersion.liveIPC, case .object(let object) = payload else { throw TraceRookError.malformedInput }
        switch method {
        case .snapshot:
            guard Set(object.keys) == ["limit"], case .number(let limit) = object["limit"], limit >= 1, limit <= 25,
                  limit == Decimal(NSDecimalNumber(decimal: limit).intValue) else { throw TraceRookError.malformedInput }
        case .clearHistory, .simulatedIngestion: guard object.isEmpty else { throw TraceRookError.malformedInput }
        case .resolveReview:
            _ = try WireCodec.decodePayload(ReviewResolution.self, payload: payload.canonicalData(), maximumBytes: WireLimits.replyBytes)
        case .localAPIDemo:
            _ = try WireCodec.decodePayload(LocalAPIDemoControl.self, payload: payload.canonicalData(), maximumBytes: WireLimits.replyBytes)
        }
    }
}
public enum ServiceErrorCode: String, Codable, Sendable {
    case unavailable, invalidRequest = "invalid_request", wrongBinding = "wrong_binding", staleReview = "stale_review"
    case forbidden, storageFailure = "storage_failure", timeout
}
public struct ServiceControlReply: IPCMessage {
    public let protocolVersion: Int
    public let requestID: UUID
    public let error: ServiceErrorCode?
    public let payload: JSONValue
    public init(requestID: UUID, error: ServiceErrorCode? = nil, payload: JSONValue = .object([:])) {
        protocolVersion = TraceRookVersion.liveIPC; self.requestID = requestID; self.error = error; self.payload = payload
    }
    public static let wireKeys: Set<String> = ["protocolVersion", "requestID", "error", "payload"]
    public func validate() throws {
        guard protocolVersion == TraceRookVersion.liveIPC, case .object = payload else { throw TraceRookError.malformedInput }
        if error != nil { guard payload == .object([:]) else { throw TraceRookError.malformedInput } }
    }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(protocolVersion, forKey: .protocolVersion); try c.encode(requestID, forKey: .requestID)
        try c.encode(error, forKey: .error); try c.encode(payload, forKey: .payload)
    }
    enum Keys: String, CodingKey { case protocolVersion, requestID, error, payload }
}

public struct ServiceSnapshot: Codable, Sendable {
    public let schemaVersion: Int
    public let securityMode: ServiceSecurityMode
    public let sessions: [SessionRecord]
    public let incidents: [IncidentRecord]
    public let approvals: [ApprovalRecord]
    public let reviewRequests: [ReviewRequest]
    public let simulatedSessionIDs: [UUID]
    public let hasMore: Bool
    public init(securityMode: ServiceSecurityMode, sessions: [SessionRecord], incidents: [IncidentRecord], approvals: [ApprovalRecord],
                reviewRequests: [ReviewRequest] = [], simulatedSessionIDs: [UUID] = [], hasMore: Bool = false) {
        schemaVersion = 1; self.securityMode = securityMode; self.sessions = sessions; self.incidents = incidents
        self.approvals = approvals; self.reviewRequests = reviewRequests; self.simulatedSessionIDs = simulatedSessionIDs; self.hasMore = hasMore
    }
    public func validate() throws {
        guard schemaVersion == 1, sessions.count <= 25, incidents.count <= 25, approvals.count <= 25,
              reviewRequests.count <= 25, simulatedSessionIDs.count <= 25,
              sessions.allSatisfy({ $0.origin == .live && $0.events.count <= 20 }),
              incidents.allSatisfy({ $0.origin == .live }), approvals.allSatisfy({ $0.origin == .live }) else { throw TraceRookError.malformedResponse }
        for request in reviewRequests { try request.validate() }
        for record in sessions { try PersistedPrivacy.validate(record) }
        for record in incidents { try PersistedPrivacy.validate(record) }
        for record in approvals { try PersistedPrivacy.validate(record) }
    }
}

/// Persistence accepts bounded sanitized domain records, never host envelopes.
public enum PersistedPrivacy {
    public static func validate<T: Encodable>(_ record: T) throws {
        let bytes = try JSONEncoder().encode(record)
        guard bytes.count <= 65_536 else { throw TraceRookError.oversizedInput }
        let value = try JSONValue.decodeBounded(bytes)
        try inspect(value)
    }
    private static func inspect(_ value: JSONValue) throws {
        switch value {
        case .string(let string):
            guard string.utf8.count <= 2_048, Redactor().redact(string).count == 0,
                  !string.contains("-----BEGIN"), !string.contains("/Users/"), !string.contains("/home/") else { throw TraceRookError.unsafePayload }
        case .object(let object): for (key, value) in object {
            guard !["host_payload", "original_tool_input", "raw_input", "transcript", "api_key"].contains(key.lowercased()) else { throw TraceRookError.unsafePayload }
            try inspect(value)
        }
        case .array(let array): guard array.count <= 100 else { throw TraceRookError.oversizedInput }; for element in array { try inspect(element) }
        default: break
        }
    }
}
