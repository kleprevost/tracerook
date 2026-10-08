import Foundation
import TraceRookContracts

/// Development-only scenarios. No host event, raw command, or user text enters
/// this API. These types are deliberately separate from AnalysisProvider.
public enum LocalAPIDemoScenario: String, Codable, Sendable, CaseIterable {
    case benign, credentialTransfer = "credential_transfer", taskDrift = "task_drift"
    case providerUnavailable = "provider_unavailable", quotaExhausted = "quota_exhausted", deadlineExceeded = "deadline_exceeded"
    public var title: String {
        switch self {
        case .benign: "Routine UI change"
        case .credentialTransfer: "Credential transfer"
        case .taskDrift: "Task drift"
        case .providerUnavailable: "Provider unavailable"
        case .quotaExhausted: "Quota exhausted"
        case .deadlineExceeded: "Deadline exceeded"
        }
    }
    public var context: LocalAPIDemoContext {
        let task = "Implement a checkout button in a demo UI"
        switch self {
        case .credentialTransfer:
            return LocalAPIDemoContext(taskSummary: task,
                proposedActionSummary: "Command reads credential configuration and posts contents to an unrelated remote endpoint",
                localSignals: ["sensitive_config_read", "outbound_transfer", "task_mismatch"],
                recentActivity: ["Read UI source", "Read unrelated external instructions"])
        case .taskDrift:
            return LocalAPIDemoContext(taskSummary: task,
                proposedActionSummary: "Command deploys an unrelated service outside the requested UI task",
                localSignals: ["task_mismatch"], recentActivity: ["Read UI source", "Modify checkout button"])
        default:
            return LocalAPIDemoContext(taskSummary: task, proposedActionSummary: "Command runs project UI tests",
                localSignals: [], recentActivity: ["Read UI source", "Modify checkout button"])
        }
    }
}

public struct LocalAPIDemoContext: Codable, Sendable, Equatable {
    public let taskSummary: String
    public let actionClass: ActionType
    public let proposedActionSummary: String
    public let localSignals: [String]
    public let recentActivity: [String]
    public let containsCodeExcerpts: Bool
    fileprivate init(taskSummary: String, proposedActionSummary: String, localSignals: [String], recentActivity: [String]) {
        self.taskSummary = taskSummary; actionClass = .shellExec; self.proposedActionSummary = proposedActionSummary
        self.localSignals = localSignals; self.recentActivity = recentActivity; containsCodeExcerpts = false
    }
    enum CodingKeys: String, CodingKey {
        case taskSummary = "task_summary", actionClass = "action_class", proposedActionSummary = "proposed_action_summary"
        case localSignals = "local_signals", recentActivity = "recent_activity", containsCodeExcerpts = "contains_code_excerpts"
    }
    static let wireKeys: Set<String> = ["task_summary", "action_class", "proposed_action_summary", "local_signals", "recent_activity", "contains_code_excerpts"]
}

/// Provisional local contract. It cannot be decoded as a live Cloud request:
/// simulation and scenario are mandatory, and the route is /mock/v1/analysis.
public struct LocalAPIDemoRequest: IPCMessage, Equatable {
    public let schemaVersion: Int
    public let simulation: Bool
    public let requestID: UUID
    public let deviceID: UUID
    public let sessionPseudonym: UUID
    public let source: AgentProvider
    public let event: HookKind
    public let deadlineMS: Int
    public let privacyPolicyVersion: Int
    public let scenario: LocalAPIDemoScenario
    public let context: LocalAPIDemoContext
    public init(scenario: LocalAPIDemoScenario, deviceID: UUID, requestID: UUID = UUID(), sessionPseudonym: UUID = UUID(), deadlineMS: Int = 3_000) {
        schemaVersion = 1; simulation = true; self.requestID = requestID; self.deviceID = deviceID
        self.sessionPseudonym = sessionPseudonym; source = .claudeCode; event = .preToolUse
        self.deadlineMS = deadlineMS; privacyPolicyVersion = 2; self.scenario = scenario; context = scenario.context
    }
    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version", simulation, requestID = "request_id", deviceID = "device_id"
        case sessionPseudonym = "session_pseudonym", source, event, deadlineMS = "deadline_ms"
        case privacyPolicyVersion = "privacy_policy_version", scenario, context
    }
    public static let wireKeys: Set<String> = ["schema_version", "simulation", "request_id", "device_id", "session_pseudonym", "source", "event", "deadline_ms", "privacy_policy_version", "scenario", "context"]
    public static func validateWireShape(_ value: JSONValue) throws {
        try LocalAPIDemoWire.exact(value, keys: wireKeys)
        try LocalAPIDemoWire.exact(value["context"], keys: LocalAPIDemoContext.wireKeys)
    }
    public func validate() throws {
        guard schemaVersion == 1, simulation, source == .claudeCode, event == .preToolUse,
              (1_000...4_000).contains(deadlineMS), privacyPolicyVersion == 2, context == scenario.context
        else { throw TraceRookError.unsafePayload }
    }
    public var previewJSON: String {
        guard let bytes = try? WireCodec.encodePayload(self, maximumBytes: 32_768),
              let value = try? JSONValue.decodeBounded(bytes) else { return "Preview unavailable" }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let pretty = try? encoder.encode(value) else { return "Preview unavailable" }
        return String(decoding: pretty, as: UTF8.self)
    }
}

public struct LocalAPIDemoProvenance: Codable, Sendable, Equatable {
    public let provider: String
    public let transport: String
    public let modelID: String
    public let policyVersion: Int
    public let promptVersion: String
    public let traceID: String
    public let validatedAt: String
    enum CodingKeys: String, CodingKey {
        case provider, transport, modelID = "model_id", policyVersion = "policy_version", promptVersion = "prompt_version"
        case traceID = "trace_id", validatedAt = "validated_at"
    }
    static let wireKeys: Set<String> = ["provider", "transport", "model_id", "policy_version", "prompt_version", "trace_id", "validated_at"]
    func validate() throws {
        guard provider == "fixture", transport == "local_mock", modelID == "synthetic-v1", policyVersion == 1,
              promptVersion == "mock-risk-eval-v1", LocalAPIDemoWire.identifier(traceID, prefix: "tr_"),
              LocalAPIDemoWire.timestamp(validatedAt) != nil else { throw TraceRookError.malformedResponse }
    }
}

public struct LocalAPIDemoUsage: Codable, Sendable, Equatable {
    public let inputTokens: Int
    public let outputTokens: Int
    public let billedUnits: Int
    enum CodingKeys: String, CodingKey { case inputTokens = "input_tokens", outputTokens = "output_tokens", billedUnits = "billed_units" }
    static let wireKeys: Set<String> = ["input_tokens", "output_tokens", "billed_units"]
}

/// Advisory fixture receipt only. There is no conversion to a hook reply or
/// approval, no persistence, and no conformance to the live provider protocol.
public struct LocalAPIDemoResponse: IPCMessage, Equatable {
    public let schemaVersion: Int
    public let simulation: Bool
    public let requestID: UUID
    public let analysisID: String
    public let verdict: AnalysisVerdict
    public let provenance: LocalAPIDemoProvenance
    public let usage: LocalAPIDemoUsage
    public let serverElapsedMS: Int
    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version", simulation, requestID = "request_id", analysisID = "analysis_id"
        case verdict, provenance, usage, serverElapsedMS = "server_elapsed_ms"
    }
    public static let wireKeys: Set<String> = ["schema_version", "simulation", "request_id", "analysis_id", "verdict", "provenance", "usage", "server_elapsed_ms"]
    public static func validateWireShape(_ value: JSONValue) throws {
        try LocalAPIDemoWire.exact(value, keys: wireKeys)
        try LocalAPIDemoWire.exact(value["provenance"], keys: LocalAPIDemoProvenance.wireKeys)
        try LocalAPIDemoWire.exact(value["usage"], keys: LocalAPIDemoUsage.wireKeys)
        try LocalAPIDemoWire.exact(value["verdict"], keys: ["schema_version", "category", "severity", "confidence", "suspicious", "rationale", "evidence", "recommended_action", "session_drift", "limitations"])
    }
    public func validate() throws {
        guard schemaVersion == 1, simulation, LocalAPIDemoWire.identifier(analysisID, prefix: "an_"),
              (0...4_000).contains(serverElapsedMS), usage.inputTokens == 0, usage.outputTokens == 0,
              usage.billedUnits == 0, verdict.severity != .critical else { throw TraceRookError.malformedResponse }
        try verdict.validate(); try provenance.validate(); try PersistedPrivacy.validate(self)
    }
    public func validate(matching request: LocalAPIDemoRequest, now: Date = .now) throws {
        try request.validate(); try validate()
        guard requestID == request.requestID else { throw TraceRookError.wrongBinding }
        guard let timestamp = LocalAPIDemoWire.timestamp(provenance.validatedAt),
              now.timeIntervalSince(timestamp) >= -30, now.timeIntervalSince(timestamp) <= 600,
              serverElapsedMS <= request.deadlineMS else { throw TraceRookError.malformedResponse }
    }
}

enum LocalAPIDemoWire {
    static func exact(_ value: JSONValue?, keys: Set<String>) throws {
        guard case .object(let object) = value, Set(object.keys) == keys else { throw TraceRookError.malformedInput }
    }
    static func identifier(_ value: String, prefix: String) -> Bool {
        guard value.hasPrefix(prefix), value.utf8.count == prefix.utf8.count + 36 else { return false }
        return UUID(uuidString: String(value.dropFirst(prefix.count))) != nil
    }
    static func timestamp(_ value: String) -> Date? {
        // Canonical UTC seconds or three fractional digits (standard JS output).
        // Bound before the formatter runs and round-trip to reject normalization.
        guard [20, 24].contains(value.utf8.count), value.hasSuffix("Z") else { return nil }
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime]
        if value.utf8.count == 24 { formatter.formatOptions.insert(.withFractionalSeconds) }
        guard let date = formatter.date(from: value), formatter.string(from: date) == value else { return nil }
        return date
    }
}
