import Foundation
import Testing
import TraceRookContracts
import TraceRookCore

private let demoTime = Date(timeIntervalSince1970: 1_791_504_000)
private func demoRequest(_ scenario: LocalAPIDemoScenario = .credentialTransfer) -> LocalAPIDemoRequest {
    LocalAPIDemoRequest(scenario: scenario, deviceID: UUID())
}
private func replyValue(_ request: LocalAPIDemoRequest, date: Date = demoTime) -> JSONValue {
    let formatter = ISO8601DateFormatter()
    return .object([
        "schema_version": .number(1), "simulation": .bool(true), "request_id": .string(request.requestID.uuidString),
        "analysis_id": .string("an_" + UUID().uuidString), "server_elapsed_ms": .number(20),
        "verdict": .object([
            "schema_version": .number(1), "category": .array([.string("unsafe_action")]), "severity": .string("high"),
            "confidence": .number(Decimal(string: "0.92")!), "suspicious": .bool(true),
            "rationale": .string("Synthetic sample action is unrelated to the sample task."),
            "evidence": .array([.string("Sample credential read and outbound transfer")]),
            "recommended_action": .string("request_approval"), "session_drift": .bool(true),
            "limitations": .array([.string("Fixture only; no Claude call or host execution")])
        ]),
        "provenance": .object([
            "provider": .string("fixture"), "transport": .string("local_mock"), "model_id": .string("synthetic-v1"),
            "policy_version": .number(1), "prompt_version": .string("mock-risk-eval-v1"),
            "trace_id": .string("tr_" + UUID().uuidString), "validated_at": .string(formatter.string(from: date))
        ]),
        "usage": .object(["input_tokens": .number(0), "output_tokens": .number(0), "billed_units": .number(0)])
    ])
}
private func changed(_ value: JSONValue, path: [String], to replacement: JSONValue) -> JSONValue {
    guard case .object(var object) = value, let key = path.first else { return value }
    if path.count == 1 { object[key] = replacement }
    else if let child = object[key] { object[key] = changed(child, path: Array(path.dropFirst()), to: replacement) }
    return .object(object)
}
private func decode(_ value: JSONValue) throws -> LocalAPIDemoResponse {
    try WireCodec.decodePayload(LocalAPIDemoResponse.self, payload: value.canonicalData(), maximumBytes: 32_768)
}

@Test(arguments: LocalAPIDemoScenario.allCases)
func apiDemoOnlyEncodesFixedSyntheticExamples(_ scenario: LocalAPIDemoScenario) throws {
    let request = demoRequest(scenario)
    let bytes = try WireCodec.encodePayload(request, maximumBytes: 32_768)
    #expect(bytes.first == 123) // HTTP JSON, not an IPC length prefix.
    #expect(try WireCodec.decodePayload(LocalAPIDemoRequest.self, payload: bytes, maximumBytes: 32_768) == request)
    #expect(request.context == scenario.context && request.simulation)
    #expect(!request.previewJSON.contains("api_key"))
    #expect(!request.previewJSON.contains("/Users/"))
    #expect(!request.context.containsCodeExcerpts)
    #expect(try JSONValue.decodeBounded(Data(request.previewJSON.utf8)) == JSONValue.decodeBounded(bytes))
    #expect(try WireCodec.encode(request).dropFirst(4) == bytes)
}

@Test func apiDemoCannotAcceptArbitraryHostContentOrLiveOrigin() throws {
    let value = try JSONValue.decodeBounded(WireCodec.encodePayload(demoRequest()))
    for replacement in [
        changed(value, path: ["simulation"], to: .bool(false)),
        changed(value, path: ["origin"], to: .string("live")),
        changed(value, path: ["context", "task_summary"], to: .string("Untrusted user task")),
        changed(value, path: ["context", "raw_command"], to: .string("echo host input")),
        changed(value, path: ["context", "contains_code_excerpts"], to: .bool(true)),
        changed(value, path: ["context", "local_signals"], to: .array([.string("unknown_signal")]))
    ] {
        #expect(throws: (any Error).self) {
            try WireCodec.decodePayload(LocalAPIDemoRequest.self, payload: replacement.canonicalData(), maximumBytes: 32_768)
        }
    }
    for deadline in [0, 999, 4_001, 12_001] {
        #expect(throws: TraceRookError.unsafePayload) {
            try WireCodec.encodePayload(LocalAPIDemoRequest(scenario: .benign, deviceID: UUID(), deadlineMS: deadline))
        }
    }
}

@Test func apiDemoRejectsAmbiguousHTTPJSONAndOversizedBodies() throws {
    let raw = String(decoding: try WireCodec.encodePayload(demoRequest()), as: UTF8.self)
    for bad in [
        "{\"simulation\":true," + raw.dropFirst(),
        raw.replacingOccurrences(of: "\"task_summary\":", with: "\"task_summary\":\"changed\",\"\\u0074ask_summary\":"),
        raw + "{}"
    ] {
        #expect(throws: TraceRookError.malformedInput) {
            try WireCodec.decodePayload(LocalAPIDemoRequest.self, payload: Data(bad.utf8), maximumBytes: 32_768)
        }
    }
    #expect(throws: TraceRookError.malformedInput) {
        try WireCodec.decodePayload(LocalAPIDemoRequest.self, payload: Data([0xff]), maximumBytes: 32_768)
    }
    #expect(throws: TraceRookError.oversizedInput) {
        try WireCodec.decodePayload(LocalAPIDemoRequest.self, payload: Data(repeating: 32, count: 32_769), maximumBytes: 32_768)
    }
}

@Test func apiDemoReceiptBindsRequestTimeAndDeadline() throws {
    let request = demoRequest()
    let response = try decode(replyValue(request))
    try response.validate(matching: request, now: demoTime)
    let milliseconds = try decode(changed(replyValue(request), path: ["provenance", "validated_at"],
        to: .string("2026-10-08T12:00:00.000Z")))
    try milliseconds.validate()
    #expect(throws: TraceRookError.wrongBinding) { try response.validate(matching: demoRequest(), now: demoTime) }
    for offset in [-601.0, 31.0] {
        let invalid = try decode(replyValue(request, date: demoTime.addingTimeInterval(offset)))
        #expect(throws: TraceRookError.malformedResponse) { try invalid.validate(matching: request, now: demoTime) }
    }
    let late = try decode(changed(replyValue(request), path: ["server_elapsed_ms"], to: .number(3_001)))
    #expect(throws: TraceRookError.malformedResponse) { try late.validate(matching: request, now: demoTime) }
}

@Test func apiDemoNeverAcceptsRealProviderClaimsBillingOrPermission() throws {
    let value = replyValue(demoRequest())
    for mutation in [
        changed(value, path: ["simulation"], to: .bool(false)),
        changed(value, path: ["provenance", "provider"], to: .string("anthropic")),
        changed(value, path: ["provenance", "transport"], to: .string("tracerook_cloud")),
        changed(value, path: ["provenance", "model_id"], to: .string("claude-model")),
        changed(value, path: ["usage", "input_tokens"], to: .number(42)),
        changed(value, path: ["usage", "billed_units"], to: .number(1)),
        changed(value, path: ["verdict", "severity"], to: .string("critical")),
        changed(value, path: ["verdict", "recommended_action"], to: .string("deny")),
        changed(value, path: ["verdict", "permission"], to: .string("allow_once")),
        changed(value, path: ["provenance", "provider_ready"], to: .bool(true)),
        changed(value, path: ["usage", "account_id"], to: .string("other-account"))
    ] { #expect(throws: (any Error).self) { try decode(mutation) } }
}

@Test func apiDemoRejectsUnsafeOrUnboundedReturnedText() throws {
    let value = replyValue(demoRequest())
    for rationale in [String(repeating: "x", count: 2_049), "Unexpected source /Users/sample/private.txt", "-----BEGIN PRIVATE KEY-----"] {
        #expect(throws: (any Error).self) { try decode(changed(value, path: ["verdict", "rationale"], to: .string(rationale))) }
    }
    #expect(throws: (any Error).self) {
        try decode(changed(value, path: ["provenance", "trace_id"], to: .string("tr_not-a-uuid")))
    }
}

@Test func apiDemoReceiptCannotEnterHookOrApprovalControlChannels() throws {
    let bytes = try replyValue(demoRequest()).canonicalData()
    #expect(throws: TraceRookError.malformedInput) { try WireCodec.decodePayload(HookReplyV2.self, payload: bytes) }
    #expect(throws: TraceRookError.malformedInput) { try WireCodec.decodePayload(ReviewResolution.self, payload: bytes) }
    #expect(throws: TraceRookError.malformedInput) { try WireCodec.decodePayload(ServiceControlRequest.self, payload: bytes) }
}
