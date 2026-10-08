import Foundation
import TraceRookContracts

public enum FindingCategory: String, Codable, Sendable { case unsafeAction = "unsafe_action", agentMisbehavior = "agent_misbehavior" }
public struct AnalysisVerdict: Codable, Sendable, Equatable {
    public let schemaVersion: Int
    public let category: [FindingCategory]
    public let severity: Severity
    public let confidence: Double
    public let suspicious: Bool
    public let rationale: String
    public let evidence: [String]
    public let recommendedAction: DecisionOutcome
    public let sessionDrift: Bool
    public let limitations: [String]
    enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion = "schema_version", category, severity, confidence, suspicious, rationale, evidence
        case recommendedAction = "recommended_action", sessionDrift = "session_drift", limitations
    }
    private struct AnyKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }
    public init(from decoder: any Decoder) throws {
        let keys = try decoder.container(keyedBy: AnyKey.self)
        guard Set(keys.allKeys.map(\.stringValue)) == Set(CodingKeys.allCases.map(\.rawValue)) else { throw TraceRookError.malformedResponse }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion); category = try c.decode([FindingCategory].self, forKey: .category)
        severity = try c.decode(Severity.self, forKey: .severity); confidence = try c.decode(Double.self, forKey: .confidence)
        suspicious = try c.decode(Bool.self, forKey: .suspicious); rationale = try c.decode(String.self, forKey: .rationale)
        evidence = try c.decode([String].self, forKey: .evidence); recommendedAction = try c.decode(DecisionOutcome.self, forKey: .recommendedAction)
        sessionDrift = try c.decode(Bool.self, forKey: .sessionDrift); limitations = try c.decode([String].self, forKey: .limitations)
        try validate()
    }
    public func validate() throws {
        guard schemaVersion == 1, confidence.isFinite, (0...1).contains(confidence),
              !category.isEmpty, category.count <= 2, rationale.utf8.count <= 2048,
              evidence.count <= 10, limitations.count <= 10,
              (evidence + limitations).allSatisfy({ $0.utf8.count <= 512 }),
              [.allow, .requestApproval, .warnAllow].contains(recommendedAction)
        else { throw TraceRookError.malformedResponse }
    }
}
public struct AnalysisRequest: Codable, Sendable {
    public let requestID: UUID
    public let origin: DataOrigin
    public let sessionPseudonym: String
    public let taskAnchorRedacted: String
    public let proposedActionRedacted: String
    public let priorEventsRedacted: [String]
    public let policyMatches: [String]
    public init(requestID: UUID = UUID(), origin: DataOrigin, sessionPseudonym: String, taskAnchorRedacted: String,
                proposedActionRedacted: String, priorEventsRedacted: [String] = [], policyMatches: [String] = []) {
        self.requestID = requestID; self.origin = origin; self.sessionPseudonym = sessionPseudonym
        self.taskAnchorRedacted = taskAnchorRedacted; self.proposedActionRedacted = proposedActionRedacted
        self.priorEventsRedacted = priorEventsRedacted; self.policyMatches = policyMatches
    }
}
public struct ProviderHealth: Codable, Sendable {
    public let mode: AnalysisMode
    public let available: Bool
    public let explanation: String
    public init(mode: AnalysisMode, available: Bool, explanation: String) {
        self.mode = mode; self.available = available; self.explanation = explanation
    }
}
public protocol AnalysisProvider: Sendable {
    var mode: AnalysisMode { get }
    func checkAvailability() async -> ProviderHealth
    func analyze(_ request: AnalysisRequest, deadline: ContinuousClock.Instant) async throws -> AnalysisVerdict
}
public struct LocalRulesOnlyProvider: AnalysisProvider {
    public let mode = AnalysisMode.localRulesOnly
    public init() {}
    public func checkAvailability() async -> ProviderHealth {
        ProviderHealth(mode: mode, available: true, explanation: "No remote analysis; local rules require an executing, verified hook.")
    }
    public func analyze(_ request: AnalysisRequest, deadline: ContinuousClock.Instant) async throws -> AnalysisVerdict {
        throw TraceRookError.providerUnavailable
    }
}

public struct SessionRecord: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public let origin: DataOrigin
    public let provider: AgentProvider
    public let project: String
    public let taskAnchor: String
    public let coverage: CoverageStatus
    public let firstSeenAt: Date
    public let lastSeenAt: Date
    public let endedAt: Date?
    public let risk: Severity
    public let events: [TimelineEntry]
    public func activity(at now: Date) -> String {
        if endedAt != nil { return "Ended" }
        let age = now.timeIntervalSince(lastSeenAt)
        if age < 300 { return "Active" }
        if age < 600 { return "Recently active" }
        return "Stale"
    }
}
public struct TimelineEntry: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public let at: Date
    public let tool: String
    public let summary: String
    public let severity: Severity
    public let execution: ExecutionState
}
public struct IncidentRecord: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public let sessionID: UUID
    public let origin: DataOrigin
    public let title: String
    public let severity: Severity
    public let categories: [FindingCategory]
    public let ruleIDs: [String]
    public let summary: String
    public let rationale: String
    public let evidence: [String]
    public let limitations: [String]
    public let execution: ExecutionState
    public let createdAt: Date
    public let providerMode: AnalysisMode
    public var reviewed: Bool
    public var falsePositive: Bool
}
public enum ApprovalState: String, Codable, Sendable {
    case pending, approvedOnce = "approved_once", denied, expired, aborted
    public var title: String {
        switch self { case .pending: "Pending"; case .approvedOnce: "Allowed once"; case .denied: "Blocked"; case .expired: "Expired · denied"; case .aborted: "Aborted" }
    }
}
public struct ApprovalBinding: Codable, Sendable, Equatable {
    public let provider: AgentProvider
    public let sessionID: UUID
    public let turnID: String?
    public let eventID: UUID
    public let toolCallID: String
    public let fingerprint: String
    public init(provider: AgentProvider, sessionID: UUID, turnID: String?, eventID: UUID, toolCallID: String, fingerprint: String) {
        self.provider = provider; self.sessionID = sessionID; self.turnID = turnID; self.eventID = eventID
        self.toolCallID = toolCallID; self.fingerprint = fingerprint
    }
}
public struct ApprovalRecord: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public let incidentID: UUID
    public let origin: DataOrigin
    public let binding: ApprovalBinding
    public let requestedAt: Date
    public let expiresAt: Date
    public var state: ApprovalState
    public var respondedAt: Date?
    public init(id: UUID = UUID(), incidentID: UUID, origin: DataOrigin, binding: ApprovalBinding, requestedAt: Date,
                expiresAt: Date, state: ApprovalState = .pending, respondedAt: Date? = nil) {
        self.id = id; self.incidentID = incidentID; self.origin = origin; self.binding = binding
        self.requestedAt = requestedAt; self.expiresAt = expiresAt; self.state = state; self.respondedAt = respondedAt
    }
    public func isPending(at now: Date) -> Bool { state == .pending && now < expiresAt }
}

/// UI-independent exact-action transitions, shared by the demo and eventual service.
public enum ApprovalTransition {
    public static func respond(_ approval: ApprovalRecord, binding: ApprovalBinding, allow: Bool, now: Date) throws -> ApprovalRecord {
        guard approval.binding == binding else { throw TraceRookError.wrongBinding }
        guard approval.isPending(at: now) else { throw TraceRookError.staleApproval }
        var resolved = approval; resolved.state = allow ? .approvedOnce : .denied; resolved.respondedAt = now
        return resolved
    }
    public static func expire(_ approval: ApprovalRecord, now: Date) -> ApprovalRecord {
        guard approval.state == .pending, now >= approval.expiresAt else { return approval }
        var expired = approval; expired.state = .expired; expired.respondedAt = now; return expired
    }
}

// Future cloud DTOs are separate from real local events. No network transport ships in demo mode.
public struct CloudAccount: Codable, Sendable {
    public let accountID: String; public let email: String; public let plan: String; public let state: String
    enum CodingKeys: String, CodingKey { case accountID = "account_id", email, plan, state }
}
public struct CloudUsage: Codable, Sendable {
    public let period: String; public let analyzedActions: Int; public let tokensUsed: Int; public let quota: Int; public let dailyActions: [Int]
    enum CodingKeys: String, CodingKey { case period, analyzedActions = "analyzed_actions", tokensUsed = "tokens_used", quota, dailyActions = "daily_actions" }
}
public struct CloudPlan: Codable, Sendable, Identifiable { public let id: String; public let name: String; public let description: String; public let monthlyPriceLabel: String; public let features: [String] }
public struct CloudDeviceRegistration: Codable, Sendable {
    public let deviceID: String; public let enrollmentState: String
    enum CodingKeys: String, CodingKey { case deviceID = "device_id", enrollmentState = "enrollment_state" }
}
public struct CloudAnalysisPayload: Codable, Sendable {
    public let requestID: UUID; public let schemaVersion: Int; public let deviceID: String; public let sessionPseudonym: String
    public let taskAnchorRedacted: String; public let proposedActionRedacted: String; public let priorEventsRedacted: [String]
    public let privacyPolicyVersion: Int; public let clientDeadlineMS: Int
    public init(request: AnalysisRequest, deviceID: String, clientDeadlineMS: Int = 12_000) {
        requestID = request.requestID; schemaVersion = 1; self.deviceID = deviceID; sessionPseudonym = request.sessionPseudonym
        taskAnchorRedacted = request.taskAnchorRedacted; proposedActionRedacted = request.proposedActionRedacted
        priorEventsRedacted = request.priorEventsRedacted; privacyPolicyVersion = 1; self.clientDeadlineMS = clientDeadlineMS
    }
    enum CodingKeys: String, CodingKey {
        case requestID = "request_id", schemaVersion = "schema_version", deviceID = "device_id", sessionPseudonym = "session_pseudonym"
        case taskAnchorRedacted = "task_anchor_redacted", proposedActionRedacted = "proposed_action_redacted", priorEventsRedacted = "prior_events_redacted"
        case privacyPolicyVersion = "privacy_policy_version", clientDeadlineMS = "client_deadline_ms"
    }
}
public struct CloudAnalysisResponse: Codable, Sendable {
    public let requestID: UUID; public let verdict: AnalysisVerdict; public let modelID: String
    public let policyVersion: Int; public let traceID: String; public let expiresAt: Date; public let billedUnits: Int
    enum CodingKeys: String, CodingKey {
        case requestID = "request_id", verdict, modelID = "model_id", policyVersion = "policy_version", traceID = "trace_id", expiresAt = "expires_at", billedUnits = "billed_units"
    }
}
public protocol CloudAPIClient: Sendable {
    func registerDevice() async throws -> CloudDeviceRegistration
    func account() async throws -> CloudAccount
    func usage(month: String) async throws -> CloudUsage
    func plans() async throws -> [CloudPlan]
    func analyze(_ request: AnalysisRequest) async throws -> CloudAnalysisResponse
    func acknowledgeTelemetry(origin: DataOrigin) async throws -> Bool
}
