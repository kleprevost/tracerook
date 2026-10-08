import Foundation
import CryptoKit
import TraceRookContracts
import TraceRookPrivacy
import TraceRookRules

/// Service-owned policy and exact-invocation review. Raw host input remains transient.
public actor HostEventPipeline {
    private let store: SessionStore
    private let reviews: ApprovalCoordinator
    private let liveCloud: LiveCloudClient?
    private var seenRequests: [UUID: ContinuousClock.Instant] = [:]
    private var seenNonces: [String: ContinuousClock.Instant] = [:]
    public init(store: SessionStore, reviews: ApprovalCoordinator, liveCloud: LiveCloudClient? = nil) {
        self.store = store; self.reviews = reviews; self.liveCloud = liveCloud
    }
    public func handle(_ envelope: HookEnvelopeV2, event: AgentEvent) async -> HookReplyV2 {
        func reply(_ decision: HookPolicyDecision, _ code: String, _ explanation: String,
                   source: DecisionSource = .fallback, incident: UUID? = nil) -> HookReplyV2 {
            HookReplyV2(requestID: envelope.requestID, decision: decision, reasonCode: code,
                explanation: explanation, incidentID: incident, decisionSource: source, coverageClass: event.actionType)
        }
        do {
            try envelope.validate(); try event.validate()
            guard event.agent == envelope.adapter, event.kind == envelope.requestKind else { throw TraceRookError.wrongBinding }
            let nowMS = Int64(Date.now.timeIntervalSince1970 * 1000)
            guard envelope.receivedAtMS <= nowMS + 5000, envelope.hardDeadlineMS > nowMS + 1000 else { throw TraceRookError.timeout }
            let clock = ContinuousClock(), now = clock.now
            seenRequests = seenRequests.filter { $0.value > now }; seenNonces = seenNonces.filter { $0.value > now }
            guard seenRequests[envelope.requestID] == nil, seenNonces[envelope.invocationNonce] == nil,
                  seenRequests.count < 4096 else { return reply(.deny, "replay_rejected", "Invocation was replayed or admission capacity was exhausted.") }
            // Reserve before any suspension; no terminal result can be replayed into an approval.
            let expiry = now.advanced(by: .seconds(300))
            seenRequests[envelope.requestID] = expiry; seenNonces[envelope.invocationNonce] = expiry
            let remaining = min(envelope.hardDeadlineMS - nowMS - 1000, RequestBudget.maximumHookMilliseconds - 1000)
            let deadline = now.advanced(by: .milliseconds(remaining))
            let session = try await store.record(event, provenance: .hostHook)
            guard envelope.requestKind == .preToolUse else {
                return reply(.noOverride, "observed", "Lifecycle event recorded; execution remains unconfirmed.")
            }
            guard let tool = envelope.hostPayload["tool_name"]?.string,
                  let cwd = envelope.hostPayload["cwd"]?.string, cwd.hasPrefix("/"),
                  let input = envelope.hostPayload["tool_input"] else { throw TraceRookError.malformedInput }
            let assessment = LocalPolicy.evaluate(tool: tool, input: input, context: PolicyContext(cwd: cwd))
            var severity = assessment.severity
            var reason = assessment.catastrophic ? "Concrete catastrophic local evidence; action denied." : "Local policy inspected the action."
            var mode = AnalysisMode.localRulesOnly
            var modelReview = false
            var providerUnavailable = true
            // Deterministic catastrophic evidence always wins before any network access.
            if !assessment.catastrophic, let liveCloud, await liveCloud.status().analysisEnabledLocally,
               let device = await liveCloud.status().deviceID,
               clock.now < deadline.advanced(by: .seconds(-2)) {
                let budget = min(6000, max(1000, Int(remaining - 1000)))
                let request = try CloudAnalysisRequest(origin: .live, deviceID: device, sessionPseudonym: session.id,
                    source: event.agent, task: .unspecified, action: Self.cloudAction(event.actionType),
                    signals: Self.cloudSignals(assessment.evidence), deadlineMS: budget, requestID: envelope.requestID)
                do {
                    let receipt = try await liveCloud.analyze(request, deadline: min(deadline, clock.now.advanced(by: .milliseconds(budget))))
                    guard clock.now < deadline, !Task.isCancelled else { throw TraceRookError.timeout }
                    providerUnavailable = false; mode = .traceRookCloud
                    severity = severity.score >= receipt.verdict.severity.score ? severity : receipt.verdict.severity
                    modelReview = receipt.verdict.suspicious || receipt.verdict.recommendedAction == .requestApproval || receipt.verdict.severity.score >= Severity.high.score
                    // Persist fixed attribution, never model-origin text or raw host arguments.
                    reason = modelReview ? "Validated cloud analysis recommends local human review." : "Validated cloud analysis returned an advisory verdict."
                } catch { reason = "Cloud analysis unavailable; local fallback applied." }
            }
            let needsReview = !assessment.catastrophic && (severity.score >= Severity.high.score || !assessment.inspectionComplete || modelReview)
            let needsIncident = assessment.catastrophic || needsReview || !assessment.evidence.isEmpty || providerUnavailable
            var incident: IncidentRecord?
            if needsIncident {
                let record = IncidentRecord(sessionID: session.id, origin: .live,
                    title: assessment.catastrophic ? "Local policy denial" : needsReview ? "Action requires review" : "Local fallback applied",
                    severity: severity, ruleIDs: assessment.evidence.map(\.ruleID), summary: event.actionType.rawValue,
                    rationale: reason, evidence: assessment.evidence.map(\.summary),
                    limitations: ["Host execution is unconfirmed", "Hook coverage requires installed-host verification"], providerMode: mode)
                try await store.saveIncident(record); incident = record
            }
            if assessment.catastrophic {
                return reply(.deny, "local_critical", reason, source: .localRule, incident: incident?.id)
            }
            if needsReview, let incident {
                guard clock.now < deadline.advanced(by: .seconds(-1)), !Task.isCancelled else { throw TraceRookError.timeout }
                let binding = ApprovalBinding(provider: event.agent, sessionID: session.id, turnID: event.sourceTurnID.map(Self.digest),
                    eventID: event.id, toolCallID: Self.digest(event.sourceToolCallID), fingerprint: event.actionFingerprint)
                _ = try await reviews.create(requestID: envelope.requestID, incidentID: incident.id, binding: binding,
                    nonce: envelope.invocationNonce, deadline: deadline)
                let state = await reviews.wait(requestID: envelope.requestID)
                guard state == .approvedOnce, clock.now < deadline, !Task.isCancelled else {
                    return reply(.deny, "review_denied", "Human review was denied, expired, or aborted.", source: .human, incident: incident.id)
                }
                return reply(.noOverride, "human_allow_once", "Exact invocation reviewed; native host permissions still apply.", source: .human, incident: incident.id)
            }
            guard clock.now < deadline, !Task.isCancelled else { throw TraceRookError.timeout }
            return reply(.noOverride, providerUnavailable ? "local_fallback" : "advisory_clear", reason,
                source: providerUnavailable ? .fallback : .modelReview, incident: incident?.id)
        } catch {
            return reply(.deny, "inspection_unavailable", "Inspection failed or the invocation deadline expired; no host permission granted.")
        }
    }
    private static func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    public static func cloudAction(_ action: ActionType) -> CloudActionClass {
        switch action { case .shellExec: .shellExec; case .fileRead: .fileRead; case .fileWrite, .fileEdit: .fileWrite; case .network: .network; default: .other }
    }
    public static func cloudSignals(_ evidence: [RuleEvidence]) -> [CloudSignal] {
        var signals: Set<CloudSignal> = []
        for item in evidence {
            switch item.ruleID {
            case "TR-SENSITIVE-READ", "TR-DOTENV-ACCESS": signals.insert(.sensitiveConfigRead)
            case "TR-CRED-EXFIL": signals.formUnion([.readsCredentialStore, .outboundTransfer])
            case "TR-UNKNOWN-EGRESS": signals.formUnion([.outboundTransfer, .remoteEndpointUnfamiliar])
            case "TR-POLICY-TAMPER", "TR-SECURITY-CONFIG": signals.insert(.writesRepoConfig)
            case "TR-DESTRUCT-OUTSIDE": signals.insert(.destructiveDelete)
            case "TR-PUBLISH-DEPLOY": signals.insert(.taskMismatch)
            case "TR-PRIV-ESC": signals.insert(.privilegeChange)
            case "TR-REMOTE-EXEC", "TR-ENCODED-COMMAND", "TR-INSPECTION-INCOMPLETE": signals.insert(.untrustedInstructions)
            default: break
            }
        }
        return signals.sorted { $0.rawValue < $1.rawValue }
    }
}
