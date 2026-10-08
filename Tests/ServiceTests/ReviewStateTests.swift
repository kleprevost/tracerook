import Foundation
import Testing
import TraceRookContracts
import TraceRookCore

private func setup() async throws -> (URL, SessionStore, ApprovalCoordinator, ReviewRequest) {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("tracerook-review-\(UUID())")
    let store = try SessionStore(directory: url)
    let event = AgentEvent(agent: .codex, sourceSessionID: "review-test", sourceToolCallID: "call", kind: .preToolUse,
        cwd: "[PROJECT]", toolName: "Bash", actionType: .shellExec, argsSummary: "Synthetic high-risk action", actionFingerprint: String(repeating: "a", count: 64))
    let session = try await store.record(event, provenance: .serviceSimulation)
    let incident = IncidentRecord(sessionID: session.id, origin: .live, title: "Synthetic review", severity: .high,
        ruleIDs: ["test"], summary: "No host tool was running", rationale: "State-machine test")
    try await store.saveIncident(incident)
    let coordinator = ApprovalCoordinator(store: store)
    let binding = ApprovalBinding(provider: .codex, sessionID: session.id, turnID: nil, eventID: event.id,
        toolCallID: "test-call", fingerprint: event.actionFingerprint)
    let request = try await coordinator.create(requestID: UUID(), incidentID: incident.id, binding: binding,
        nonce: try InvocationNonce.generate(), deadline: ContinuousClock().now.advanced(by: .seconds(10)))
    return (url, store, coordinator, request)
}
private func resolution(_ request: ReviewRequest, choice: ReviewChoice = .allowOnce, nonce: String? = nil) -> ReviewResolution {
    ReviewResolution(requestID: request.requestID, approvalID: request.approvalID, binding: request.binding,
        invocationNonce: nonce ?? request.invocationNonce, choice: choice)
}

@Test func exactReviewConsumesOnceAndRejectsChangedNonceAndReplay() async throws {
    let (url, store, coordinator, request) = try await setup()
    defer { try? FileManager.default.removeItem(at: url) }
    await #expect(throws: TraceRookError.wrongBinding) { try await coordinator.resolve(resolution(request, nonce: String(repeating: "f", count: 32))) }
    try await coordinator.resolve(resolution(request))
    #expect(await coordinator.wait(requestID: request.requestID) == .approvedOnce)
    #expect(await coordinator.wait(requestID: request.requestID) == .aborted)
    await #expect(throws: TraceRookError.staleApproval) { try await coordinator.resolve(resolution(request)) }
    #expect(try await store.snapshot(mode: .developer).approvals.first?.state == .approvedOnce)
    await store.close()
}

@Test func restartNeverRestoresPendingAuthority() async throws {
    let (url, store, _, _) = try await setup()
    defer { try? FileManager.default.removeItem(at: url) }
    await store.close()
    let restarted = try SessionStore(directory: url)
    let snapshot = try await restarted.snapshot(mode: .developer)
    #expect(snapshot.approvals.count == 1 && snapshot.approvals[0].state == .aborted)
    #expect(snapshot.reviewRequests.isEmpty)
    await restarted.close()
}

@Test func abortAndConcurrentResolutionCannotGrantTwice() async throws {
    let (url, store, coordinator, request) = try await setup()
    defer { try? FileManager.default.removeItem(at: url) }
    let accepted = await withTaskGroup(of: Bool.self) { group in
        for _ in 0..<20 { group.addTask { do { try await coordinator.resolve(resolution(request, choice: .block)); return true } catch { return false } } }
        var results = 0; for await success in group where success { results += 1 }; return results
    }
    #expect(accepted == 1)
    #expect(await coordinator.wait(requestID: request.requestID) == .denied)
    await store.close()
}
@Test func clearCancelsUnconsumedApprovalAndMutationReplay() async throws {
    let (url, store, coordinator, request) = try await setup()
    defer { try? FileManager.default.removeItem(at: url) }
    try await coordinator.resolve(resolution(request))
    await coordinator.abortAll()
    #expect(await coordinator.wait(requestID: request.requestID) == .aborted)
    #expect(try await store.snapshot(mode: .developer).approvals.first?.state == .aborted)
    let broker = EventBroker(store: store, securityMode: .developer)
    let clear = ServiceControlRequest(method: .clearHistory)
    #expect(await broker.control(clear).error == nil)
    #expect(await broker.control(clear).error == .invalidRequest)
    #expect(try await store.snapshot(mode: .developer).sessions.isEmpty)
    await store.close()
}
