import Foundation
import TraceRookContracts
import TraceRookPrivacy

/// Fixed vocabularies keep raw host text out of the cloud contract.
public enum CloudSignal: String, Codable, Sendable, CaseIterable {
    case sensitiveConfigRead = "sensitive_config_read", outboundTransfer = "outbound_transfer", taskMismatch = "task_mismatch"
    case readsCredentialStore = "reads_credential_store", outboundPost = "outbound_post", writesRepoConfig = "writes_repo_config"
    case destructiveDelete = "destructive_delete", remoteEndpointUnfamiliar = "remote_endpoint_unfamiliar"
    case promptInjection = "prompt_injection", privilegeChange = "privilege_change", untrustedInstructions = "untrusted_instructions", sessionDrift = "session_drift"
}
public enum CloudTaskClass: String, Codable, Sendable {
    case interfaceChange, projectTests, repositoryMaintenance, unspecified
    var summary: String {
        switch self {
        case .interfaceChange: "Implement a user interface change"
        case .projectTests: "Validate a project with tests"
        case .repositoryMaintenance: "Perform user-authorized repository maintenance"
        case .unspecified: "Task intent has not been classified locally"
        }
    }
}
public enum CloudActionClass: String, Codable, Sendable {
    case shellExec = "shell_exec", fileRead = "file_read", fileWrite = "file_write", network, other
    var summary: String {
        switch self {
        case .shellExec: "Execute a shell operation; raw command omitted"
        case .fileRead: "Read a file; path and contents omitted"
        case .fileWrite: "Modify a file; path and contents omitted"
        case .network: "Perform a network operation; destination and body omitted"
        case .other: "Perform an unclassified tool operation; raw arguments omitted"
        }
    }
}
public struct CloudContext: Codable, Sendable, Equatable {
    public let taskSummary: String
    public let actionClass: CloudActionClass
    public let proposedActionSummary: String
    public let localSignals: [CloudSignal]
    public let recentActivity: [String]
    public let containsCodeExcerpts: Bool
    fileprivate init(task: CloudTaskClass, action: CloudActionClass, signals: [CloudSignal]) {
        taskSummary = task.summary; actionClass = action; proposedActionSummary = action.summary
        localSignals = signals; recentActivity = []; containsCodeExcerpts = false
    }
    enum CodingKeys: String, CodingKey {
        case taskSummary = "task_summary", actionClass = "action_class", proposedActionSummary = "proposed_action_summary"
        case localSignals = "local_signals", recentActivity = "recent_activity", containsCodeExcerpts = "contains_code_excerpts"
    }
    static let keys: Set<String> = ["task_summary", "action_class", "proposed_action_summary", "local_signals", "recent_activity", "contains_code_excerpts"]
    func validate() throws {
        guard !containsCodeExcerpts, localSignals.count <= 12, Set(localSignals).count == localSignals.count,
              taskSummary.unicodeScalars.count <= 512, taskSummary.utf8.count <= 1024,
              proposedActionSummary.unicodeScalars.count <= 1024, proposedActionSummary.utf8.count <= 2048,
              recentActivity.count <= 6, recentActivity.allSatisfy({ $0.unicodeScalars.count <= 160 && $0.utf8.count <= 512 })
        else { throw TraceRookError.unsafePayload }
        for text in [taskSummary, proposedActionSummary] + recentActivity { try CloudEgress.validateSummary(text) }
    }
}
public struct CloudAnalysisRequest: IPCMessage, Equatable {
    public let schemaVersion: Int
    public let requestID: UUID
    public let deviceID: UUID
    public let sessionPseudonym: UUID
    public let source: AgentProvider
    public let event: HookKind
    public let deadlineMS: Int
    public let privacyPolicyVersion: Int
    public let context: CloudContext
    /// Origin is checked before a live request is formed. Pseudonyms must be
    /// randomly generated locally; never pass an agent's session identifier.
    public init(origin: DataOrigin, deviceID: UUID, sessionPseudonym: UUID, source: AgentProvider,
                task: CloudTaskClass, action: CloudActionClass, signals: [CloudSignal], deadlineMS: Int,
                requestID: UUID = UUID()) throws {
        guard origin == .live else { throw TraceRookError.notDemoData }
        schemaVersion = 1; self.requestID = requestID; self.deviceID = deviceID
        self.sessionPseudonym = sessionPseudonym; self.source = source; event = .preToolUse
        self.deadlineMS = deadlineMS; privacyPolicyVersion = 2
        context = CloudContext(task: task, action: action, signals: signals)
        try validate()
    }
    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version", requestID = "request_id", deviceID = "device_id", sessionPseudonym = "session_pseudonym"
        case source, event, deadlineMS = "deadline_ms", privacyPolicyVersion = "privacy_policy_version", context
    }
    public static let wireKeys: Set<String> = ["schema_version", "request_id", "device_id", "session_pseudonym", "source", "event", "deadline_ms", "privacy_policy_version", "context"]
    public static func validateWireShape(_ value: JSONValue) throws {
        try CloudWire.exact(value, keys: wireKeys); try CloudWire.exact(value["context"], keys: CloudContext.keys)
    }
    public func validate() throws {
        guard schemaVersion == 1, event == .preToolUse, privacyPolicyVersion == 2, (1000...12000).contains(deadlineMS) else { throw TraceRookError.unsafePayload }
        try context.validate()
    }
}
public struct CloudLimits: Codable, Sendable, Equatable {
    public let evaluationsPerDay: Int?
    public let inputTokensPerDay: Int?
    public let outputTokensPerDay: Int?
    public let devicesPerAccount: Int
    enum CodingKeys: String, CodingKey {
        case evaluationsPerDay = "evaluations_per_day", inputTokensPerDay = "input_tokens_per_day"
        case outputTokensPerDay = "output_tokens_per_day", devicesPerAccount = "devices_per_account"
    }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(evaluationsPerDay, forKey: .evaluationsPerDay)
        try c.encode(inputTokensPerDay, forKey: .inputTokensPerDay)
        try c.encode(outputTokensPerDay, forKey: .outputTokensPerDay)
        try c.encode(devicesPerAccount, forKey: .devicesPerAccount)
    }
    static let keys: Set<String> = ["evaluations_per_day", "input_tokens_per_day", "output_tokens_per_day", "devices_per_account"]
    func validate() throws {
        guard (1...3).contains(devicesPerAccount), [evaluationsPerDay, inputTokensPerDay, outputTokensPerDay].allSatisfy({ $0 == nil || (0...1_000_000_000).contains($0!) }) else { throw TraceRookError.malformedResponse }
    }
}
public struct CloudCredential: IPCMessage, CustomStringConvertible, CustomDebugStringConvertible {
    public let schemaVersion: Int
    public let deviceID: UUID
    public let deviceToken: String
    public let tokenExpiresAt: String
    public let limits: CloudLimits
    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version", deviceID = "device_id", deviceToken = "device_token", tokenExpiresAt = "token_expires_at", limits
    }
    public static let wireKeys: Set<String> = ["schema_version", "device_id", "device_token", "token_expires_at", "limits"]
    public static func validateWireShape(_ value: JSONValue) throws {
        try CloudWire.exact(value, keys: wireKeys); try CloudWire.exact(value["limits"], keys: CloudLimits.keys)
    }
    public var description: String { "<cloud credential redacted>" }
    public var debugDescription: String { description }
    public func validate() throws {
        guard (43...256).contains(deviceToken.utf8.count), deviceToken.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }),
              schemaVersion == 1, let expiry = CloudWire.timestamp(tokenExpiresAt), expiry.timeIntervalSinceNow > 0,
              expiry.timeIntervalSinceNow <= 31 * 86400 else { throw TraceRookError.malformedResponse }
        try limits.validate()
    }
}
public struct CloudCapabilities: IPCMessage, Equatable {
    public struct Retention: Codable, Sendable, Equatable {
        public let receiptDays: Int; public let usageDays: Int; public let verdictCacheSeconds: Int
        enum CodingKeys: String, CodingKey { case receiptDays = "receipt_days", usageDays = "usage_days", verdictCacheSeconds = "verdict_cache_seconds" }
    }
    public let schemaVersion: Int
    public let provider: String; public let transport: String; public let modelID: String
    public let analysisEnabled: Bool; public let privacyPolicyVersion: Int
    public let retention: Retention; public let limits: CloudLimits
    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version", provider, transport, modelID = "model_id", analysisEnabled = "analysis_enabled"
        case privacyPolicyVersion = "privacy_policy_version", retention, limits
    }
    public static let wireKeys: Set<String> = ["schema_version", "provider", "transport", "model_id", "analysis_enabled", "privacy_policy_version", "retention", "limits"]
    public static func validateWireShape(_ value: JSONValue) throws {
        try CloudWire.exact(value, keys: wireKeys); try CloudWire.exact(value["limits"], keys: CloudLimits.keys)
        try CloudWire.exact(value["retention"], keys: ["receipt_days", "usage_days", "verdict_cache_seconds"])
    }
    public func validate() throws {
        guard schemaVersion == 1, provider == "anthropic", transport == "tracerook_cloud", modelID == "claude-haiku-5-5", privacyPolicyVersion == 2,
              retention.receiptDays == 30, retention.usageDays == 90, retention.verdictCacheSeconds == 600 else { throw TraceRookError.malformedResponse }
        try limits.validate()
    }
}
public struct LiveCloudUsage: IPCMessage, Equatable {
    public let schemaVersion: Int; public let dateUTC: String; public let evaluationsToday: Int
    public let inputTokens: Int; public let outputTokens: Int; public let reservedInputTokens: Int; public let reservedOutputTokens: Int
    public let limits: CloudLimits
    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version", dateUTC = "date_utc", evaluationsToday = "evaluations_today"
        case inputTokens = "input_tokens", outputTokens = "output_tokens", reservedInputTokens = "reserved_input_tokens", reservedOutputTokens = "reserved_output_tokens", limits
    }
    public static let wireKeys: Set<String> = ["schema_version", "date_utc", "evaluations_today", "input_tokens", "output_tokens", "reserved_input_tokens", "reserved_output_tokens", "limits"]
    public static func validateWireShape(_ value: JSONValue) throws { try CloudWire.exact(value, keys: wireKeys); try CloudWire.exact(value["limits"], keys: CloudLimits.keys) }
    public func validate() throws {
        guard schemaVersion == 1, CloudWire.timestamp(dateUTC + "T00:00:00Z") != nil,
              [evaluationsToday, inputTokens, outputTokens, reservedInputTokens, reservedOutputTokens].allSatisfy({ (0...1_000_000_000).contains($0) }) else { throw TraceRookError.malformedResponse }
        try limits.validate()
    }
}
public struct LiveCloudAnalysisResponse: IPCMessage, Equatable {
    public struct Provenance: Codable, Sendable, Equatable {
        public let provider: String; public let transport: String; public let modelID: String; public let policyVersion: Int
        public let promptVersion: String; public let traceID: String; public let validatedAt: String
        enum CodingKeys: String, CodingKey {
            case provider, transport, modelID = "model_id", policyVersion = "policy_version", promptVersion = "prompt_version", traceID = "trace_id", validatedAt = "validated_at"
        }
    }
    public let schemaVersion: Int; public let requestID: UUID; public let analysisID: String
    public let verdict: AnalysisVerdict; public let provenance: Provenance; public let usage: LocalAPIDemoUsage; public let serverElapsedMS: Int
    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version", requestID = "request_id", analysisID = "analysis_id", verdict, provenance, usage, serverElapsedMS = "server_elapsed_ms"
    }
    public static let wireKeys: Set<String> = ["schema_version", "request_id", "analysis_id", "verdict", "provenance", "usage", "server_elapsed_ms"]
    public static func validateWireShape(_ value: JSONValue) throws {
        try CloudWire.exact(value, keys: wireKeys)
        try CloudWire.exact(value["provenance"], keys: ["provider", "transport", "model_id", "policy_version", "prompt_version", "trace_id", "validated_at"])
        try CloudWire.exact(value["usage"], keys: LocalAPIDemoUsage.wireKeys)
        try CloudWire.exact(value["verdict"], keys: ["schema_version", "category", "severity", "confidence", "suspicious", "rationale", "evidence", "recommended_action", "session_drift", "limitations"])
    }
    public func validate() throws {
        guard schemaVersion == 1, CloudWire.identifier(analysisID, prefix: "an_"), (0...12000).contains(serverElapsedMS),
              provenance.provider == "anthropic", provenance.transport == "tracerook_cloud", provenance.modelID == "claude-haiku-5-5",
              provenance.policyVersion == 1, provenance.promptVersion == "risk-eval-v1", CloudWire.identifier(provenance.traceID, prefix: "tr_"),
              CloudWire.timestamp(provenance.validatedAt) != nil, usage.billedUnits == 1,
              (1...16_384).contains(usage.inputTokens), (1...1024).contains(usage.outputTokens),
              Set(verdict.category.map(\.rawValue)).count == verdict.category.count else { throw TraceRookError.malformedResponse }
        try verdict.validate(); try PersistedPrivacy.validate(self)
    }
    public func validate(matching request: CloudAnalysisRequest, now: Date = .now) throws {
        try validate(); try request.validate()
        guard requestID == request.requestID else { throw TraceRookError.wrongBinding }
        guard let date = CloudWire.timestamp(provenance.validatedAt), now.timeIntervalSince(date) >= -30,
              now.timeIntervalSince(date) <= 600, serverElapsedMS <= request.deadlineMS else { throw TraceRookError.malformedResponse }
    }
}
/// Exact shape and duplicate-key validation run through WireCodec before decode.
enum CloudWire {
    static func exact(_ value: JSONValue?, keys: Set<String>) throws {
        guard case .object(let object) = value, Set(object.keys) == keys else { throw TraceRookError.malformedInput }
    }
    static func timestamp(_ value: String) -> Date? { LocalAPIDemoWire.timestamp(value) }
    static func identifier(_ value: String, prefix: String) -> Bool { LocalAPIDemoWire.identifier(value, prefix: prefix) }
}
