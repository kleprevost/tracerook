import Foundation
import Testing
import TraceRookContracts
import TraceRookCore
import TraceRookFixtures

@Test func cloudRefusesLiveAnalysis() async throws {
    let provider = try TraceRookCloudDemoProvider()
    let live = AnalysisRequest(origin: .live, sessionPseudonym: "s", taskAnchorRedacted: "task", proposedActionRedacted: "action")
    await #expect(throws: TraceRookError.notDemoData) { try await provider.analyze(live, deadline: .now.advanced(by: .seconds(1))) }
    #expect(await provider.checkAvailability().available == false)
    let demo = AnalysisRequest(origin: .demo, sessionPseudonym: "sample", taskAnchorRedacted: "task", proposedActionRedacted: "action")
    let verdict = try await provider.analyze(demo, deadline: .now.advanced(by: .seconds(1)))
    try verdict.validate()
}
@Test func approvalsRejectReplayWrongBindingAndExpiryBoundary() throws {
    let now = Date()
    let binding = ApprovalBinding(provider: .codex, sessionID: UUID(), turnID: "turn", eventID: UUID(), toolCallID: "call", fingerprint: String(repeating: "a", count: 64))
    let approval = ApprovalRecord(incidentID: UUID(), origin: .demo, binding: binding, requestedAt: now, expiresAt: now.addingTimeInterval(45))
    let resolved = try ApprovalTransition.respond(approval, binding: binding, allow: true, now: now)
    #expect(resolved.state == .approvedOnce)
    #expect(throws: TraceRookError.staleApproval) { try ApprovalTransition.respond(resolved, binding: binding, allow: true, now: now) }
    #expect(throws: TraceRookError.staleApproval) { try ApprovalTransition.respond(approval, binding: binding, allow: true, now: approval.expiresAt) }
    let wrong = ApprovalBinding(provider: .codex, sessionID: binding.sessionID, turnID: "turn", eventID: binding.eventID, toolCallID: "different", fingerprint: binding.fingerprint)
    #expect(throws: TraceRookError.wrongBinding) { try ApprovalTransition.respond(approval, binding: wrong, allow: true, now: now) }
    #expect(ApprovalTransition.expire(approval, now: approval.expiresAt).state == .expired)
}

@Test func modelSchemaRejectsAdditionalFieldsAndPermissionGrants() throws {
    let fixture = try FixtureLoader.loadDemo()
    let original = try JSONValue.decodeBounded(JSONEncoder().encode(fixture.verdict))
    guard case .object(var fields) = original else { Issue.record("Invalid fixture verdict"); return }
    #expect(fields["schema_version"] == .number(1))
    fields["execute_command"] = .string("untrusted instruction")
    #expect(throws: (any Error).self) { try JSONDecoder().decode(AnalysisVerdict.self, from: JSONValue.object(fields).canonicalData()) }
    fields.removeValue(forKey: "execute_command"); fields["recommended_action"] = .string("deny")
    #expect(throws: (any Error).self) { try JSONDecoder().decode(AnalysisVerdict.self, from: JSONValue.object(fields).canonicalData()) }
}

@Test func futureCloudPayloadExcludesLocalOriginAndHasVersionedFields() throws {
    let request = AnalysisRequest(origin: .demo, sessionPseudonym: "sample", taskAnchorRedacted: "task", proposedActionRedacted: "action")
    let payload = CloudAnalysisPayload(request: request, deviceID: "demo-device")
    let encoded = try JSONValue.decodeBounded(JSONEncoder().encode(payload))
    #expect(encoded["origin"] == nil)
    #expect(encoded["privacy_policy_version"] == .number(1))
    #expect(encoded["client_deadline_ms"] == .number(12000))
    #expect(encoded["request_id"]?.string == request.requestID.uuidString)
}
