import Foundation
import Testing
import TraceRookCore
import TraceRookContracts

private func review() -> ReviewRequest {
    ReviewRequest(requestID: UUID(), approvalID: UUID(), incidentID: UUID(),
        binding: ApprovalBinding(provider: .codex, sessionID: UUID(), turnID: nil, eventID: UUID(),
            toolCallID: "synthetic-call", fingerprint: String(repeating: "b", count: 64)),
        invocationNonce: String(repeating: "a", count: 32), createdAtMS: 1_000, expiresAtMS: 46_000)
}
private func modifiedReview<T: Encodable>(_ message: T, key: String, value: JSONValue) throws -> Data {
    guard case .object(var object) = try JSONValue.decodeBounded(JSONEncoder().encode(message)) else { throw TraceRookError.malformedInput }
    object[key] = value
    return try JSONValue.object(object).canonicalData()
}

@Test func reviewDTOsRetainTheExistingBindingAndExactInvocation() throws {
    let request = review()
    #expect(try WireCodec.decode(ReviewRequest.self, frame: WireCodec.encode(request)) == request)
    for choice in [ReviewChoice.allowOnce, .block] {
        let resolution = ReviewResolution(requestID: request.requestID, approvalID: request.approvalID,
            binding: request.binding, invocationNonce: request.invocationNonce, choice: choice)
        let decoded = try WireCodec.decode(ReviewResolution.self, frame: WireCodec.encode(resolution))
        try decoded.validateBinding(to: request)
        #expect(decoded == resolution)
    }
}

@Test func changedNonceIDsAndActionCannotMatchAWaitingReview() throws {
    let request = review()
    let changedAction = ApprovalBinding(provider: .codex, sessionID: request.binding.sessionID, turnID: nil,
        eventID: request.binding.eventID, toolCallID: request.binding.toolCallID, fingerprint: String(repeating: "c", count: 64))
    let invalid = [
        ReviewResolution(requestID: UUID(), approvalID: request.approvalID, binding: request.binding, invocationNonce: request.invocationNonce, choice: .allowOnce),
        ReviewResolution(requestID: request.requestID, approvalID: UUID(), binding: request.binding, invocationNonce: request.invocationNonce, choice: .allowOnce),
        ReviewResolution(requestID: request.requestID, approvalID: request.approvalID, binding: request.binding, invocationNonce: String(repeating: "d", count: 32), choice: .allowOnce),
        ReviewResolution(requestID: request.requestID, approvalID: request.approvalID, binding: changedAction, invocationNonce: request.invocationNonce, choice: .allowOnce)
    ]
    for resolution in invalid { #expect(throws: TraceRookError.wrongBinding) { try resolution.validateBinding(to: request) } }
}

@Test func demoOriginAndCriticalReviewsAreRejectedOnLiveControlPlane() throws {
    let request = review()
    #expect(throws: TraceRookError.notDemoData) {
        try WireCodec.decodePayload(ReviewRequest.self, payload: modifiedReview(request, key: "origin", value: .string("demo")))
    }
    #expect(throws: TraceRookError.malformedInput) {
        try WireCodec.decodePayload(ReviewRequest.self, payload: modifiedReview(request, key: "severity", value: .string("critical")))
    }
    let resolution = ReviewResolution(requestID: request.requestID, approvalID: request.approvalID,
        binding: request.binding, invocationNonce: request.invocationNonce, choice: .block)
    #expect(throws: TraceRookError.notDemoData) {
        try WireCodec.decodePayload(ReviewResolution.self, payload: modifiedReview(resolution, key: "origin", value: .string("demo")))
    }
}

@Test func reviewBoundsAndNestedUnknownFieldsAreRejected() throws {
    let request = review()
    for expiration in [JSONValue.number(1_000), .number(46_001), .number(Decimal(Int64.max))] {
        #expect(throws: TraceRookError.malformedInput) {
            try WireCodec.decodePayload(ReviewRequest.self, payload: modifiedReview(request, key: "expires_at_ms", value: expiration))
        }
    }
    guard case .object(var binding) = try JSONValue.decodeBounded(JSONEncoder().encode(request.binding)) else { throw TraceRookError.malformedInput }
    binding["session_grant"] = .bool(true)
    #expect(throws: TraceRookError.malformedInput) {
        try WireCodec.decodePayload(ReviewRequest.self, payload: modifiedReview(request, key: "binding", value: .object(binding)))
    }
    #expect(throws: TraceRookError.malformedInput) {
        try WireCodec.decodePayload(ReviewRequest.self, payload: modifiedReview(request, key: "authenticated", value: .bool(true)))
    }
}
