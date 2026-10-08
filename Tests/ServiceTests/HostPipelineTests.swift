import Foundation
import Testing
import TraceRookContracts
import TraceRookCore

private func hostFixture(_ command: String, timeout: Int64 = 5000, nonce: String? = nil, requestID: UUID = UUID()) throws -> (HookEnvelopeV2, AgentEvent) {
    let now = Int64(Date.now.timeIntervalSince1970 * 1000)
    let envelope = HookEnvelopeV2(requestID: requestID, requestKind: .preToolUse, adapter: .claudeCode,
        receivedAtMS: now, hardDeadlineMS: now + timeout, hostVersion: "test",
        invocationNonce: try nonce ?? InvocationNonce.generate(), hostPayload: .object([
            "session_id": .string("test-host-session"), "cwd": .string("/tmp/project"),
            "hook_event_name": .string("PreToolUse"), "tool_name": .string("Bash"),
            "tool_input": .object(["command": .string(command)])]))
    let event = AgentEvent(agent: .claudeCode, sourceSessionID: "test-host-session", sourceToolCallID: "call",
        kind: .preToolUse, cwd: "[PROJECT]", toolName: "Bash", actionType: .shellExec,
        argsSummary: "Bash · shell_exec", actionFingerprint: String(repeating: "a", count: 64))
    return (envelope, event)
}
private func hostStore() throws -> (SessionStore, URL) {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("tracerook-host-\(UUID())")
    return (try SessionStore(directory: directory), directory)
}
@Test func operationalLocalCriticalDenialPersistsOnlySanitizedEvidence() async throws {
    let (store, directory) = try hostStore()
    defer { try? FileManager.default.removeItem(at: directory) }
    let reviews = ApprovalCoordinator(store: store)
    let pipeline = HostEventPipeline(store: store, reviews: reviews)
    let (envelope, event) = try hostFixture("rm -rf /Users/unrelated-project")
    let reply = await pipeline.handle(envelope, event: event)
    #expect(reply.decision == .deny && reply.decisionSource == .localRule)
    #expect(await reviews.activeRequests().isEmpty)
    let snapshot = try await store.snapshot(mode: .developer)
    #expect(snapshot.incidents.count == 1)
    #expect(snapshot.incidents.first?.execution == .executionUnknown)
    let persisted = String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self)
    #expect(!persisted.contains("rm -rf") && !persisted.contains("/Users/"))
    await store.close()
}
@Test func operationalFallbackPreservesNativePermissionsAndRejectsReplay() async throws {
    let (store, directory) = try hostStore()
    defer { try? FileManager.default.removeItem(at: directory) }
    let pipeline = HostEventPipeline(store: store, reviews: ApprovalCoordinator(store: store))
    let (envelope, event) = try hostFixture("printf benign")
    #expect(await pipeline.handle(envelope, event: event).decision == .noOverride)
    #expect(await pipeline.handle(envelope, event: event).reasonCode == "replay_rejected")
    let (second, secondEvent) = try hostFixture("printf benign", nonce: envelope.invocationNonce)
    #expect(await pipeline.handle(second, event: secondEvent).decision == .deny)
    await store.close()
}
@Test func operationalHumanAllowAppliesOnlyToOriginalWaitingInvocation() async throws {
    let (store, directory) = try hostStore()
    defer { try? FileManager.default.removeItem(at: directory) }
    let reviews = ApprovalCoordinator(store: store)
    let pipeline = HostEventPipeline(store: store, reviews: reviews)
    let (envelope, event) = try hostFixture("sudo true")
    let waiting = Task { await pipeline.handle(envelope, event: event) }
    var request: ReviewRequest?
    for _ in 0..<100 {
        request = await reviews.activeRequests().first
        if request != nil { break }
        try await Task.sleep(for: .milliseconds(10))
    }
    let active = try #require(request)
    try await reviews.resolve(ReviewResolution(requestID: active.requestID, approvalID: active.approvalID, binding: active.binding, invocationNonce: active.invocationNonce, choice: .allowOnce))
    let reply = await waiting.value
    #expect(reply.decision == .noOverride && reply.decisionSource == .human)
    #expect(await pipeline.handle(envelope, event: event).decision == .deny)
    await store.close()
}
@Test func operationalExpiredInvocationNeverCreatesApproval() async throws {
    let (store, directory) = try hostStore()
    defer { try? FileManager.default.removeItem(at: directory) }
    let reviews = ApprovalCoordinator(store: store)
    let pipeline = HostEventPipeline(store: store, reviews: reviews)
    let (envelope, event) = try hostFixture("sudo true", timeout: 500)
    #expect(await pipeline.handle(envelope, event: event).decision == .deny)
    #expect(await reviews.activeRequests().isEmpty)
    await store.close()
}

private actor HostCloudDouble: CloudHTTPTransport {
    var analysisBodies: [Data] = []
    private let critical: Bool
    private let malformed: Bool
    init(critical: Bool = false, malformed: Bool = false) { self.critical = critical; self.malformed = malformed }
    func bodies() -> [Data] { analysisBodies }
    func send(_ request: URLRequest, deadline: ContinuousClock.Instant) async throws -> LocalAPIDemoHTTPResponse {
        let limits: JSONValue = .object(["evaluations_per_day": .null, "input_tokens_per_day": .null, "output_tokens_per_day": .null, "devices_per_account": .number(3)])
        let formatter = ISO8601DateFormatter()
        let value: JSONValue
        switch request.url?.path {
        case "/v1/alpha/enroll":
            let submitted = try JSONValue.decodeBounded(request.httpBody!)
            value = .object(["schema_version": .number(1), "device_id": submitted["device_id"]!,
                "device_token": .string("trd_" + String(repeating: "a", count: 64)),
                "token_expires_at": .string(formatter.string(from: .now.addingTimeInterval(86400))), "limits": limits])
        case "/v1/capabilities":
            value = .object(["schema_version": .number(1), "provider": .string("anthropic"), "transport": .string("tracerook_cloud"),
                "model_id": .string("claude-haiku-5-5"), "analysis_enabled": .bool(true), "privacy_policy_version": .number(2),
                "retention": .object(["receipt_days": .number(30), "usage_days": .number(90), "verdict_cache_seconds": .number(600)]), "limits": limits])
        case "/v1/usage":
            value = .object(["schema_version": .number(1), "date_utc": .string("2026-10-08"), "evaluations_today": .number(0),
                "input_tokens": .number(0), "output_tokens": .number(0), "reserved_input_tokens": .number(0), "reserved_output_tokens": .number(0), "limits": limits])
        case "/v1/analysis":
            let body = request.httpBody!; analysisBodies.append(body)
            let input = try JSONValue.decodeBounded(body)
            if malformed { return LocalAPIDemoHTTPResponse(body: Data("{}".utf8), status: 200) }
            value = .object(["schema_version": .number(1), "request_id": input["request_id"]!, "analysis_id": .string("an_" + UUID().uuidString),
                "verdict": .object(["schema_version": .number(1), "category": .array([.string("unsafe_action")]),
                    "severity": .string(critical ? "critical" : "low"), "confidence": .number(1), "suspicious": .bool(critical),
                    "rationale": .string("Synthetic cloud result"), "evidence": .array([]), "recommended_action": .string(critical ? "request_approval" : "allow"),
                    "session_drift": .bool(false), "limitations": .array([])]),
                "provenance": .object(["provider": .string("anthropic"), "transport": .string("tracerook_cloud"), "model_id": .string("claude-haiku-5-5"),
                    "policy_version": .number(1), "prompt_version": .string("risk-eval-v1"), "trace_id": .string("tr_" + UUID().uuidString),
                    "validated_at": .string(formatter.string(from: .now))]),
                "usage": .object(["input_tokens": .number(20), "output_tokens": .number(20), "billed_units": .number(1)]), "server_elapsed_ms": .number(1)])
        default: throw TraceRookError.unsupportedOperation
        }
        return LocalAPIDemoHTTPResponse(body: try value.canonicalData(), status: 200)
    }
}
private func hostCloud(_ transport: HostCloudDouble) async throws -> LiveCloudClient {
    let client = LiveCloudClient(vault: SessionCloudCredentialStore(), transport: transport)
    _ = try await client.start(LiveCloudControl(operation: .connect, invitation: "tri_" + String(repeating: "a", count: 64), consent: CloudConsent()))
    for _ in 0..<100 {
        if !(await client.status().busy) { break }
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(await client.status().connected)
    return client
}
@Test func operationalCriticalEvidenceSkipsCloudAndBenignCloudEgressContainsNoRawAction() async throws {
    let (store, directory) = try hostStore()
    defer { try? FileManager.default.removeItem(at: directory) }
    let transport = HostCloudDouble(), client = try await hostCloud(transport)
    let pipeline = HostEventPipeline(store: store, reviews: ApprovalCoordinator(store: store), liveCloud: client)
    let (danger, dangerEvent) = try hostFixture("rm -rf /Users/other-project")
    #expect(await pipeline.handle(danger, event: dangerEvent).decision == .deny)
    #expect(await transport.bodies().isEmpty)
    let (benign, benignEvent) = try hostFixture("printf private-task-marker")
    #expect(await pipeline.handle(benign, event: benignEvent).decisionSource == .modelReview)
    let bodies = await transport.bodies()
    #expect(bodies.count == 1)
    #expect(!String(decoding: bodies[0], as: UTF8.self).contains("private-task-marker"))
    #expect(!String(decoding: bodies[0], as: UTF8.self).contains("test-host-session"))
    await store.close()
}
@Test func operationalModelCriticalRequiresHumanReviewInsteadOfHardDeny() async throws {
    let (store, directory) = try hostStore()
    defer { try? FileManager.default.removeItem(at: directory) }
    let transport = HostCloudDouble(critical: true), client = try await hostCloud(transport)
    let reviews = ApprovalCoordinator(store: store)
    let pipeline = HostEventPipeline(store: store, reviews: reviews, liveCloud: client)
    let (envelope, event) = try hostFixture("printf benign")
    let waiting = Task { await pipeline.handle(envelope, event: event) }
    var request: ReviewRequest?
    for _ in 0..<100 {
        request = await reviews.activeRequests().first
        if request != nil { break }
        try await Task.sleep(for: .milliseconds(10))
    }
    let active = try #require(request)
    try await reviews.resolve(ReviewResolution(requestID: active.requestID, approvalID: active.approvalID, binding: active.binding, invocationNonce: active.invocationNonce, choice: .allowOnce))
    #expect(await waiting.value.decision == .noOverride)
    #expect(await transport.bodies().count == 1)
    await store.close()
}
@Test func operationalMalformedCloudResponseUsesExplicitLocalFallback() async throws {
    let (store, directory) = try hostStore()
    defer { try? FileManager.default.removeItem(at: directory) }
    let transport = HostCloudDouble(malformed: true), client = try await hostCloud(transport)
    let pipeline = HostEventPipeline(store: store, reviews: ApprovalCoordinator(store: store), liveCloud: client)
    let (envelope, event) = try hostFixture("printf benign")
    let reply = await pipeline.handle(envelope, event: event)
    #expect(reply.decision == .noOverride && reply.decisionSource == .fallback)
    let snapshot = try await store.snapshot(mode: .developer)
    #expect(snapshot.incidents.first?.providerMode == .localRulesOnly)
    #expect(snapshot.incidents.first?.rationale.contains("unavailable") == true)
    await store.close()
}
