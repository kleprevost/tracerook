import Foundation
import Security

public enum InvocationNonce {
    public static func generate() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        let result = bytes.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
        }
        guard result == errSecSuccess else { throw TraceRookError.entropyUnavailable }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
    public static func validate(_ value: String) throws {
        guard value.utf8.count == 32, value.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            throw TraceRookError.wrongBinding
        }
    }
}

/// Raw host payload is transient decision input. Never persist, log, or export it.
public struct HookEnvelopeV2: IPCMessage, Equatable {
    public let protocolVersion: Int
    public let requestID: UUID
    public let requestKind: HookKind
    public let adapter: AgentProvider
    public let adapterVersion: String
    public let receivedAtMS: Int64
    public let hardDeadlineMS: Int64
    public let hostVersion: String
    public let invocationNonce: String
    public let hostPayload: JSONValue

    public init(requestID: UUID = UUID(), requestKind: HookKind, adapter: AgentProvider,
                adapterVersion: String = TraceRookVersion.liveAdapter, receivedAtMS: Int64, hardDeadlineMS: Int64,
                hostVersion: String, invocationNonce: String, hostPayload: JSONValue) {
        protocolVersion = TraceRookVersion.liveIPC; self.requestID = requestID; self.requestKind = requestKind
        self.adapter = adapter; self.adapterVersion = adapterVersion; self.receivedAtMS = receivedAtMS
        self.hardDeadlineMS = hardDeadlineMS; self.hostVersion = hostVersion
        self.invocationNonce = invocationNonce; self.hostPayload = hostPayload
    }
    enum CodingKeys: String, CodingKey, CaseIterable {
        case protocolVersion = "protocol_version", requestID = "request_id", requestKind = "request_kind"
        case adapter, adapterVersion = "adapter_version", receivedAtMS = "received_at_ms", hardDeadlineMS = "hard_deadline_ms"
        case hostVersion = "host_version", invocationNonce = "invocation_nonce", hostPayload = "host_payload"
    }
    public static let wireKeys = Set(CodingKeys.allCases.map(\.rawValue))
    public func validate() throws {
        guard protocolVersion == TraceRookVersion.liveIPC else { throw TraceRookError.unsupportedVersion }
        guard adapterVersion == TraceRookVersion.liveAdapter else { throw TraceRookError.incompatibleHost }
        try IPCValidation.text(hostVersion, maximumBytes: 128)
        try InvocationNonce.validate(invocationNonce)
        guard receivedAtMS >= 0, hardDeadlineMS > receivedAtMS,
              hardDeadlineMS - receivedAtMS <= RequestBudget.maximumHookMilliseconds,
              case .object = hostPayload else { throw TraceRookError.malformedInput }
    }
}

public enum HookPolicyDecision: String, Codable, Sendable { case noOverride = "no_override", deny }
public enum DecisionSource: String, Codable, Sendable {
    case localRule = "local_rule", human, modelReview = "model_review", emergencyFallback = "emergency_fallback", fallback
}
public enum HookExecutionObservation: String, Codable, Sendable { case unknown }

/// A policy result never grants host permission or proves the tool body ran.
public struct HookReplyV2: IPCMessage, Equatable {
    public let protocolVersion: Int
    public let requestID: UUID
    public let decision: HookPolicyDecision
    public let reasonCode: String
    public let explanation: String
    public let incidentID: UUID?
    public let decisionSource: DecisionSource
    public let coverageClass: ActionType
    public let executionObserved: HookExecutionObservation

    public init(requestID: UUID, decision: HookPolicyDecision, reasonCode: String, explanation: String,
                incidentID: UUID? = nil, decisionSource: DecisionSource, coverageClass: ActionType) {
        protocolVersion = TraceRookVersion.liveIPC; self.requestID = requestID; self.decision = decision
        self.reasonCode = reasonCode; self.explanation = explanation; self.incidentID = incidentID
        self.decisionSource = decisionSource; self.coverageClass = coverageClass; executionObserved = .unknown
    }
    enum CodingKeys: String, CodingKey, CaseIterable {
        case protocolVersion = "protocol_version", requestID = "request_id", decision, reasonCode = "reason_code", explanation
        case incidentID = "incident_id", decisionSource = "decision_source", coverageClass = "coverage_class", executionObserved = "execution_observed"
    }
    public static let wireKeys = Set(CodingKeys.allCases.map(\.rawValue))
    public func validate() throws {
        guard protocolVersion == TraceRookVersion.liveIPC else { throw TraceRookError.unsupportedVersion }
        try IPCValidation.text(reasonCode, maximumBytes: 64)
        guard reasonCode.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || [45, 95].contains($0) }) else { throw TraceRookError.malformedInput }
        try IPCValidation.text(explanation, maximumBytes: 512)
    }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(protocolVersion, forKey: .protocolVersion); try c.encode(requestID, forKey: .requestID)
        try c.encode(decision, forKey: .decision); try c.encode(reasonCode, forKey: .reasonCode)
        try c.encode(explanation, forKey: .explanation); try c.encode(incidentID, forKey: .incidentID)
        try c.encode(decisionSource, forKey: .decisionSource); try c.encode(coverageClass, forKey: .coverageClass)
        try c.encode(executionObserved, forKey: .executionObserved)
    }
}

/// Allocation defaults, not evidence of an installed host timeout. Runtime waits
/// must derive a local monotonic deadline and reserve output time before waiting.
public struct RequestBudget: IPCMessage, Equatable {
    public static let maximumHookMilliseconds: Int64 = 80_000
    public let hookMilliseconds: Int64
    public let modelMilliseconds: Int64
    public let reviewMilliseconds: Int64
    public let outputReserveMilliseconds: Int64
    public init(hookMilliseconds: Int64 = 80_000, modelMilliseconds: Int64 = 8_000,
                reviewMilliseconds: Int64 = 45_000, outputReserveMilliseconds: Int64 = 1_000) {
        self.hookMilliseconds = hookMilliseconds; self.modelMilliseconds = modelMilliseconds
        self.reviewMilliseconds = reviewMilliseconds; self.outputReserveMilliseconds = outputReserveMilliseconds
    }
    enum CodingKeys: String, CodingKey, CaseIterable {
        case hookMilliseconds = "hook_ms", modelMilliseconds = "model_ms", reviewMilliseconds = "review_ms", outputReserveMilliseconds = "output_reserve_ms"
    }
    public static let wireKeys = Set(CodingKeys.allCases.map(\.rawValue))
    public func validate() throws {
        guard (1...Self.maximumHookMilliseconds).contains(hookMilliseconds),
              (1...8_000).contains(modelMilliseconds), (1...45_000).contains(reviewMilliseconds),
              (1...5_000).contains(outputReserveMilliseconds),
              modelMilliseconds + reviewMilliseconds + outputReserveMilliseconds < hookMilliseconds else {
            throw TraceRookError.malformedInput
        }
    }
}

/// Evidence record, not a trusted identity or a computed Protected badge.
/// Only the future authenticated health monitor can attest these facts.
public struct IntegrationEvidence: IPCMessage, Equatable {
    public let protocolVersion: Int
    public let provider: AgentProvider
    public let hostVersion: String
    public let adapterVersion: String
    public let toolClass: ActionType
    public let testedAtMS: Int64
    public let schemaHash: String
    public let hookBinarySignature: String
    public let callbackObserved: Bool
    public let hostReportedDenial: Bool
    public let canaryAbsent: Bool
    public init(provider: AgentProvider, hostVersion: String, toolClass: ActionType, testedAtMS: Int64,
                schemaHash: String, hookBinarySignature: String, callbackObserved: Bool, hostReportedDenial: Bool, canaryAbsent: Bool) {
        protocolVersion = TraceRookVersion.liveIPC; self.provider = provider; self.hostVersion = hostVersion
        adapterVersion = TraceRookVersion.liveAdapter; self.toolClass = toolClass; self.testedAtMS = testedAtMS
        self.schemaHash = schemaHash; self.hookBinarySignature = hookBinarySignature
        self.callbackObserved = callbackObserved; self.hostReportedDenial = hostReportedDenial; self.canaryAbsent = canaryAbsent
    }
    enum CodingKeys: String, CodingKey, CaseIterable {
        case protocolVersion = "protocol_version", provider, hostVersion = "host_version", adapterVersion = "adapter_version"
        case toolClass = "tool_class", testedAtMS = "tested_at_ms", schemaHash = "schema_hash", hookBinarySignature = "hook_binary_signature"
        case callbackObserved = "callback_observed", hostReportedDenial = "host_reported_denial", canaryAbsent = "canary_absent"
    }
    public static let wireKeys = Set(CodingKeys.allCases.map(\.rawValue))
    public func validate() throws {
        guard protocolVersion == TraceRookVersion.liveIPC else { throw TraceRookError.unsupportedVersion }
        guard adapterVersion == TraceRookVersion.liveAdapter, testedAtMS >= 0 else { throw TraceRookError.malformedInput }
        try IPCValidation.text(hostVersion, maximumBytes: 128)
        try IPCValidation.text(hookBinarySignature, maximumBytes: 512)
        try IPCValidation.digest(schemaHash)
    }
}

public enum ProviderAvailability: String, Codable, Sendable {
    case notConfigured = "not_configured", consentRequired = "consent_required", ready, degraded, localOnly = "local_only", demo
}
/// Analysis availability is separate from hook coverage and host trust.
public struct ProviderStatus: IPCMessage, Equatable {
    public let protocolVersion: Int
    public let mode: AnalysisMode
    public let availability: ProviderAvailability
    public let reasonCode: String
    public init(mode: AnalysisMode, availability: ProviderAvailability, reasonCode: String) {
        protocolVersion = TraceRookVersion.liveIPC; self.mode = mode; self.availability = availability; self.reasonCode = reasonCode
    }
    enum CodingKeys: String, CodingKey, CaseIterable {
        case protocolVersion = "protocol_version", mode, availability, reasonCode = "reason_code"
    }
    public static let wireKeys = Set(CodingKeys.allCases.map(\.rawValue))
    public func validate() throws {
        guard protocolVersion == TraceRookVersion.liveIPC else { throw TraceRookError.unsupportedVersion }
        switch mode {
        case .traceRookCloudDemo: guard availability == .demo else { throw TraceRookError.notDemoData }
        case .localRulesOnly: guard availability == .localOnly || availability == .degraded else { throw TraceRookError.malformedInput }
        case .anthropicBYOK: guard [.notConfigured, .consentRequired, .ready, .degraded].contains(availability) else { throw TraceRookError.malformedInput }
        }
        try IPCValidation.text(reasonCode, maximumBytes: 64)
    }
}

public enum IPCValidation {
    /// This is a shape bound, not secret redaction. Callers must supply sanitized text.
    public static func text(_ value: String, maximumBytes: Int) throws {
        guard !value.isEmpty, value.utf8.count <= maximumBytes,
              !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw TraceRookError.malformedInput
        }
    }
    public static func digest(_ value: String) throws {
        guard value.utf8.count == 64, value.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            throw TraceRookError.invalidFingerprint
        }
    }
}
