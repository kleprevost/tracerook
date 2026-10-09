import Foundation

public enum TraceRookVersion {
    public static let app = "0.1.0"
    public static let schema = 1
    public static let ipc = 1
    public static let adapter = "1.0.0"
    // Additive live contracts. The v1 fixture/persistence versions remain unchanged.
    public static let liveIPC = 2
    public static let liveAdapter = "2.0.0"
    public static let maxInputBytes = 1_048_576
    public static let maxNestingDepth = 32
}

public enum AgentProvider: String, Codable, Sendable, CaseIterable {
    case claudeCode = "claude_code", codex
    public var title: String { self == .claudeCode ? "Claude Code" : "Codex" }
}
public enum HookKind: String, Codable, Sendable, CaseIterable {
    case sessionStart = "session_start", userPrompt = "user_prompt", preToolUse = "pre_tool_use"
    case postToolUse = "post_tool_use", postToolFailure = "post_tool_failure"
    case sessionEnd = "session_end", instructionLoaded = "instruction_loaded"
    public var hostName: String {
        switch self {
        case .sessionStart: "SessionStart"
        case .userPrompt: "UserPromptSubmit"
        case .preToolUse: "PreToolUse"
        case .postToolUse: "PostToolUse"
        case .postToolFailure: "PostToolUseFailure"
        case .sessionEnd: "SessionEnd"
        case .instructionLoaded: "InstructionsLoaded"
        }
    }
}
public enum ActionType: String, Codable, Sendable {
    case shellExec = "shell_exec", fileRead = "file_read", fileWrite = "file_write", fileEdit = "file_edit"
    case network, mcp, subagent, other
    public var isMutableOrExec: Bool { [.shellExec, .fileWrite, .fileEdit, .network, .mcp, .other].contains(self) }
}
public enum Severity: String, Codable, Sendable, CaseIterable {
    case critical, high, medium, low, unknown
    public var score: Int { switch self { case .critical: 95; case .high: 80; case .medium: 55; case .low: 10; case .unknown: 0 } }
}
public enum DecisionOutcome: String, Codable, Sendable {
    case allow, deny, requestApproval = "request_approval", warnAllow = "warn_allow", unavailable
}
public enum ExecutionState: String, Codable, Sendable {
    case intercepted, blockedBeforeExecution = "blocked_before_execution", allowedByTraceRook = "allowed_by_tracerook"
    case hostExecutedObserved = "host_executed_observed", executionUnknown = "execution_unknown"
    public var title: String {
        switch self {
        case .intercepted: "Intercepted"
        case .blockedBeforeExecution: "Blocked before execution"
        case .allowedByTraceRook: "Allowed past TraceRook · host execution unconfirmed"
        case .hostExecutedObserved: "Host execution observed"
        case .executionUnknown: "Execution unknown"
        }
    }
}
public enum DataOrigin: String, Codable, Sendable { case live, demo }
public enum AnalysisMode: String, Codable, Sendable, CaseIterable {
    case anthropicBYOK, traceRookCloudDemo, traceRookCloud, localRulesOnly
    public var title: String {
        switch self {
        case .anthropicBYOK: "Anthropic BYOK"
        case .traceRookCloudDemo: "TraceRook Cloud · Demo"
        case .traceRookCloud: "TraceRook Cloud · Claude analysis"
        case .localRulesOnly: "Local rules only"
        }
    }
}
public enum CoverageStatus: String, Codable, Sendable {
    case verified, monitoringOnly, degraded, notIntegrated, needsTrust, verificationNotRecent, demo, paused
    public var title: String {
        switch self {
        case .verified: "Protected (verified hooks)"
        case .monitoringOnly: "Monitoring only"
        case .degraded: "Degraded"
        case .notIntegrated: "Not integrated"
        case .needsTrust: "Needs approval"
        case .verificationNotRecent: "Verification not recent"
        case .demo: "Demo data"
        case .paused: "Protection off"
        }
    }
}
public enum TraceRookError: String, Error, Codable, Sendable {
    case malformedInput, oversizedInput, excessiveNesting, unsupportedVersion, mismatchedEvent
    case invalidFingerprint, notAuthenticated, quotaExhausted, rateLimited, providerUnavailable
    case malformedResponse, timeout, unsafePayload, notDemoData, conflict, unsupportedOperation
    case staleApproval, wrongBinding, disconnected, incompatibleHost, fixtureInvalid
    case entropyUnavailable
}

/// Codable JSON without bridging untrusted inputs into non-Sendable Any dictionaries.
public indirect enum JSONValue: Codable, Sendable, Equatable {
    case object([String: JSONValue]), array([JSONValue]), string(String), number(Decimal), bool(Bool), null
    public init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode(Decimal.self) { self = .number(v) }
        else if let v = try? c.decode([String: JSONValue].self) { self = .object(v) }
        else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
        else { throw TraceRookError.malformedInput }
    }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
    public subscript(key: String) -> JSONValue? { if case .object(let v) = self { v[key] } else { nil } }
    public var string: String? { if case .string(let v) = self { v } else { nil } }
    public var depth: Int {
        switch self {
        case .object(let v): 1 + (v.values.map(\.depth).max() ?? 0)
        case .array(let v): 1 + (v.map(\.depth).max() ?? 0)
        default: 0
        }
    }
    public static func decodeBounded(_ data: Data) throws -> JSONValue {
        guard data.count <= TraceRookVersion.maxInputBytes else { throw TraceRookError.oversizedInput }
        // Check depth before recursion, respecting escaped quotes and braces inside strings.
        var nesting = 0, inString = false, escaped = false
        for byte in data {
            if inString {
                if escaped { escaped = false }
                else if byte == 92 { escaped = true }
                else if byte == 34 { inString = false }
            } else if byte == 34 { inString = true }
            else if byte == 123 || byte == 91 {
                nesting += 1
                guard nesting <= TraceRookVersion.maxNestingDepth else { throw TraceRookError.excessiveNesting }
            } else if byte == 125 || byte == 93 { nesting -= 1 }
        }
        // JSONDecoder's Decimal path preserves base-10 precision. Reject unsupported
        // precision/exponents rather than silently colliding fingerprints through Double.
        try validateNumbers(data)
        do { return try JSONDecoder().decode(Self.self, from: data) }
        catch { throw TraceRookError.malformedInput }
    }
    public func canonicalData() throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
    private static func validateNumbers(_ data: Data) throws {
        let bytes = Array(data)
        var index = 0, inString = false, escaped = false
        while index < bytes.count {
            let byte = bytes[index]
            if inString {
                if escaped { escaped = false }
                else if byte == 92 { escaped = true }
                else if byte == 34 { inString = false }
                index += 1; continue
            }
            if byte == 34 { inString = true; index += 1; continue }
            if byte == 45 || (48...57).contains(byte) {
                let start = index
                while index < bytes.count && ((48...57).contains(bytes[index]) || [45, 43, 46, 69, 101].contains(bytes[index])) { index += 1 }
                let token = String(decoding: bytes[start..<index], as: UTF8.self)
                let parts = token.lowercased().split(separator: "e", omittingEmptySubsequences: false)
                let mantissa = String(parts[0]), digits = mantissa.filter(\.isNumber).count
                let fractional = mantissa.split(separator: ".", omittingEmptySubsequences: false).dropFirst().first?.count ?? 0
                let exponent = parts.count == 2 ? Int(parts[1]) : 0
                guard parts.count <= 2, digits <= 38, let exponent, (-120...120).contains(exponent), (-120...100).contains(exponent - fractional)
                else { throw TraceRookError.malformedInput }
            } else { index += 1 }
        }
    }
}

/// The persisted envelope intentionally has no original tool-input or transcript field.
public struct AgentEvent: Codable, Sendable, Identifiable, Equatable {
    public let schemaVersion: Int
    public let id: UUID
    public let agent: AgentProvider
    public let sourceSessionID: String
    public let agentSubID: String?
    public let sourceTurnID: String?
    public let sourceToolCallID: String
    public let kind: HookKind
    public let occurredAt: Date
    public let cwd: String
    public let repoRoot: String?
    public let toolName: String?
    public let actionType: ActionType
    public let argsSummary: String
    public let riskFeatures: [String]
    public let redactionCount: Int
    public let rawInputTruncated: Bool
    public let actionFingerprint: String
    public let metadata: [String: String]
    public init(id: UUID = UUID(), agent: AgentProvider, sourceSessionID: String, agentSubID: String? = nil,
                sourceTurnID: String? = nil, sourceToolCallID: String, kind: HookKind, occurredAt: Date = .now,
                cwd: String, repoRoot: String? = nil, toolName: String? = nil, actionType: ActionType,
                argsSummary: String, riskFeatures: [String] = [], redactionCount: Int = 0,
                rawInputTruncated: Bool = false, actionFingerprint: String, metadata: [String: String] = [:]) {
        schemaVersion = TraceRookVersion.schema; self.id = id; self.agent = agent; self.sourceSessionID = sourceSessionID
        self.agentSubID = agentSubID; self.sourceTurnID = sourceTurnID; self.sourceToolCallID = sourceToolCallID
        self.kind = kind; self.occurredAt = occurredAt; self.cwd = cwd; self.repoRoot = repoRoot; self.toolName = toolName
        self.actionType = actionType; self.argsSummary = argsSummary; self.riskFeatures = riskFeatures
        self.redactionCount = redactionCount; self.rawInputTruncated = rawInputTruncated
        self.actionFingerprint = actionFingerprint; self.metadata = metadata
    }
    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version", id = "event_id", agent, sourceSessionID = "source_session_id"
        case agentSubID = "agent_sub_id", sourceTurnID = "source_turn_id", sourceToolCallID = "source_tool_call_id"
        case kind, occurredAt = "occurred_at", cwd, repoRoot = "repo_root", toolName = "tool_name"
        case actionType = "action_type", argsSummary = "args_summary", riskFeatures = "risk_features"
        case redactionCount = "redaction_count", rawInputTruncated = "raw_input_truncated"
        case actionFingerprint = "action_fingerprint", metadata
    }
    public func validate() throws {
        guard schemaVersion == TraceRookVersion.schema else { throw TraceRookError.unsupportedVersion }
        guard !sourceSessionID.isEmpty, sourceSessionID.utf8.count <= 256, argsSummary.utf8.count <= 4096,
              actionFingerprint.count == 64, actionFingerprint.allSatisfy({ $0.isHexDigit && $0.isASCII })
        else { throw TraceRookError.malformedInput }
    }
}

public struct HookDecision: Codable, Sendable, Equatable {
    public let outcome: DecisionOutcome
    public let reasonCode: String
    public let sanitizedExplanation: String
    public let severity: Severity
    public let expiresAt: Date?
    enum CodingKeys: String, CodingKey {
        case outcome, reasonCode = "reason_code", sanitizedExplanation = "sanitized_explanation", severity, expiresAt = "expires_at"
    }
    public init(_ outcome: DecisionOutcome, reasonCode: String, explanation: String, severity: Severity, expiresAt: Date? = nil) {
        self.outcome = outcome; self.reasonCode = reasonCode; sanitizedExplanation = explanation
        self.severity = severity; self.expiresAt = expiresAt
    }
}
public struct HookProcessResult: Sendable {
    public let stdout: Data
    public let stderr: Data
    public let exitCode: Int32
    public init(stdout: Data = Data(), stderr: Data = Data(), exitCode: Int32 = 0) {
        self.stdout = stdout; self.stderr = stderr; self.exitCode = exitCode
    }
}
public struct HookRequest: Codable, Sendable {
    public let protocolVersion: Int
    public let requestID: UUID
    public let adapter: AgentProvider
    public let hookKind: HookKind
    public let hostPayload: JSONValue
    public let cliVersion: String
    public let deadlineEpochMS: Int64
    enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol_version", requestID = "request_id", adapter, hookKind = "hook_kind"
        case hostPayload = "host_payload", cliVersion = "cli_version", deadlineEpochMS = "deadline_epoch_ms"
    }
}
public struct HookResponse: Codable, Sendable {
    public let requestID: UUID
    public let decision: HookDecision
    public init(requestID: UUID, decision: HookDecision) { self.requestID = requestID; self.decision = decision }
    enum CodingKeys: String, CodingKey {
        case requestID = "request_id", decision, reasonCode = "reason_code", explanation = "sanitized_explanation", severity, expiresAt = "expires_at"
    }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        requestID = try c.decode(UUID.self, forKey: .requestID)
        decision = HookDecision(try c.decode(DecisionOutcome.self, forKey: .decision), reasonCode: try c.decode(String.self, forKey: .reasonCode),
            explanation: try c.decode(String.self, forKey: .explanation), severity: try c.decode(Severity.self, forKey: .severity), expiresAt: try c.decodeIfPresent(Date.self, forKey: .expiresAt))
    }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(requestID, forKey: .requestID); try c.encode(decision.outcome, forKey: .decision)
        try c.encode(decision.reasonCode, forKey: .reasonCode); try c.encode(decision.sanitizedExplanation, forKey: .explanation)
        try c.encode(decision.severity, forKey: .severity); try c.encodeIfPresent(decision.expiresAt, forKey: .expiresAt)
    }
}

public struct AgentInstallationStatus: Codable, Sendable {
    public let provider: AgentProvider
    public let detectedVersion: String?
    /// nil means detection has not run; absence must not be invented by a foundation adapter.
    public let installed: Bool?
    public init(provider: AgentProvider, detectedVersion: String? = nil, installed: Bool? = nil) {
        self.provider = provider; self.detectedVersion = detectedVersion; self.installed = installed
    }
}
public struct IntegrationChangePlan: Codable, Sendable {
    public let provider: AgentProvider
    public let configPath: String
    public let originalHash: String
    public let preview: String
    public let proposedData: Data
}
public struct IntegrationHealth: Codable, Sendable {
    public let provider: AgentProvider
    public let status: CoverageStatus
    public let detectedVersion: String?
    public let adapterVersion: String
    public let configured: Bool
    public let trusted: Bool
    public let schemaCheck: Bool
    public let signedHelper: Bool
    public let lastSuccessfulHookAt: Date?
    public let lastPreToolTestAt: Date?
    public let coverageNotes: [String]
    public init(provider: AgentProvider, status: CoverageStatus = .notIntegrated, detectedVersion: String? = nil,
                configured: Bool = false, trusted: Bool = false, schemaCheck: Bool = false, signedHelper: Bool = false,
                lastSuccessfulHookAt: Date? = nil, lastPreToolTestAt: Date? = nil, coverageNotes: [String] = []) {
        self.provider = provider; self.status = status; self.detectedVersion = detectedVersion
        adapterVersion = TraceRookVersion.adapter; self.configured = configured; self.trusted = trusted
        self.schemaCheck = schemaCheck; self.signedHelper = signedHelper
        self.lastSuccessfulHookAt = lastSuccessfulHookAt; self.lastPreToolTestAt = lastPreToolTestAt; self.coverageNotes = coverageNotes
    }
    public func effectiveStatus(now: Date = .now, recency: TimeInterval = 86400) -> CoverageStatus {
        guard status != .demo else { return .demo }
        guard configured else { return .notIntegrated }
        guard signedHelper, schemaCheck else { return .degraded }
        guard trusted else { return .needsTrust }
        guard let lastPreToolTestAt, let lastSuccessfulHookAt else { return .monitoringOnly }
        guard lastPreToolTestAt <= now, lastSuccessfulHookAt <= now else { return .degraded }
        guard now.timeIntervalSince(lastPreToolTestAt) < recency else { return .verificationNotRecent }
        guard detectedVersion?.isEmpty == false else { return .degraded }
        return status == .degraded ? .degraded : .verified
    }
}
public protocol AgentAdapter: Sendable {
    var provider: AgentProvider { get }
    func detectInstallation() async -> AgentInstallationStatus
    func planHookInstall() async throws -> IntegrationChangePlan
    func installHooks(_ plan: IntegrationChangePlan) async throws
    func uninstallHooks() async throws
    func verifyHookConfiguration() async -> IntegrationHealth
    func normalize(_ raw: Data, hookKind: HookKind) throws -> AgentEvent
    func encode(_ decision: HookDecision, for hookKind: HookKind) -> HookProcessResult
}
