import Foundation
import Testing
import TraceRookContracts

private func envelope(payload: JSONValue = .object([:])) -> HookEnvelopeV2 {
    HookEnvelopeV2(requestKind: .preToolUse, adapter: .codex, receivedAtMS: 1_000,
                   hardDeadlineMS: 81_000, hostVersion: "synthetic", invocationNonce: String(repeating: "a", count: 32), hostPayload: payload)
}
private func replacing<T: Encodable>(_ message: T, key: String, value: JSONValue) throws -> Data {
    guard case .object(var object) = try JSONValue.decodeBounded(JSONEncoder().encode(message)) else { throw TraceRookError.malformedInput }
    object[key] = value
    return try JSONValue.object(object).canonicalData()
}
private func frame(_ payload: Data) -> Data {
    let size = UInt32(payload.count)
    return Data([UInt8((size >> 24) & 255), UInt8((size >> 16) & 255), UInt8((size >> 8) & 255), UInt8(size & 255)]) + payload
}
private func reply() -> HookReplyV2 {
    HookReplyV2(requestID: UUID(), decision: .noOverride, reasonCode: "ordinary_action", explanation: "No additional denial",
                decisionSource: .localRule, coverageClass: .shellExec)
}

@Test func liveEnvelopeRoundTripsWithoutChangingV1Versions() throws {
    let original = envelope()
    let encoded = try WireCodec.encode(original)
    let count = encoded.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    #expect(Int(count) == encoded.count - 4)
    #expect(try WireCodec.decode(HookEnvelopeV2.self, frame: encoded) == original)
    #expect(TraceRookVersion.schema == 1 && TraceRookVersion.ipc == 1 && TraceRookVersion.adapter == "1.0.0")
}

@Test func liveRepliesNeverGrantPermissionsOrAssertExecution() throws {
    let original = reply()
    let encoded = try WireCodec.encode(original, maximumBytes: WireLimits.replyBytes)
    #expect(try WireCodec.decodeReply(frame: encoded, matching: original.requestID) == original)
    let object = try JSONValue.decodeBounded(Data(encoded.dropFirst(4)))
    #expect(object["decision"]?.string == "no_override")
    #expect(object["incident_id"] == .null)
    #expect(object["execution_observed"]?.string == "unknown")
    for grant in ["allow", "ask", "request_approval", "warn_allow"] {
        #expect(throws: TraceRookError.malformedInput) {
            try WireCodec.decodePayload(HookReplyV2.self, payload: replacing(original, key: "decision", value: .string(grant)))
        }
    }
    #expect(throws: TraceRookError.malformedInput) {
        try WireCodec.decodePayload(HookReplyV2.self, payload: replacing(original, key: "execution_observed", value: .string("executed")))
    }
}

@Test func protocolAndAdapterVersionsMustMatch() throws {
    #expect(throws: TraceRookError.unsupportedVersion) {
        try WireCodec.decodePayload(HookEnvelopeV2.self, payload: replacing(envelope(), key: "protocol_version", value: .number(1)))
    }
    #expect(throws: TraceRookError.incompatibleHost) {
        try WireCodec.decodePayload(HookEnvelopeV2.self, payload: replacing(envelope(), key: "adapter_version", value: .string("9.0.0")))
    }
    #expect(throws: TraceRookError.unsupportedVersion) {
        try WireCodec.decodePayload(HookReplyV2.self, payload: replacing(reply(), key: "protocol_version", value: .number(99)))
    }
}

@Test func unknownMissingAndMutationFieldsAreRejected() throws {
    for field in ["approval", "allow_once", "resolve_review", "future_field"] {
        #expect(throws: TraceRookError.malformedInput) {
            try WireCodec.decodePayload(HookEnvelopeV2.self, payload: replacing(envelope(), key: field, value: .bool(true)))
        }
    }
    #expect(throws: TraceRookError.malformedInput) { try WireCodec.decodePayload(HookEnvelopeV2.self, payload: Data("{}".utf8)) }
    #expect(throws: TraceRookError.malformedInput) {
        try WireCodec.decode(HookEnvelopeV2.self, frame: WireCodec.encode(RequestBudget()))
    }
}

@Test func duplicateKeysIncludingEscapedAndNestedKeysAreRejected() throws {
    let encoded = String(decoding: try JSONEncoder().encode(envelope()), as: UTF8.self)
    let ambiguousRoot = "{\"protocol_version\":2," + encoded.dropFirst()
    #expect(throws: TraceRookError.malformedInput) {
        try WireCodec.decodePayload(HookEnvelopeV2.self, payload: Data(ambiguousRoot.utf8))
    }
    for object in [#"{"command":"safe","command":"changed"}"#, #"{"command":"safe","\u0063ommand":"changed"}"#, #"{"nested":[{"x":1,"x":2}]}"#] {
        let raw = encoded.replacingOccurrences(of: "\"host_payload\":{}", with: "\"host_payload\":" + object)
        #expect(throws: TraceRookError.malformedInput) {
            try WireCodec.decodePayload(HookEnvelopeV2.self, payload: Data(raw.utf8))
        }
    }
}

@Test func framedInputRejectsTruncationConcatenationAndOversizedDeclarations() throws {
    let valid = try WireCodec.encode(envelope())
    for invalid in [Data(), Data([0, 0, 0]), Data([0, 0, 0, 0]), Data(valid.dropLast()), valid + Data([32]), valid + valid] {
        #expect(throws: TraceRookError.malformedInput) { try WireCodec.decode(HookEnvelopeV2.self, frame: invalid) }
    }
    #expect(throws: TraceRookError.oversizedInput) { try WireCodec.decode(HookEnvelopeV2.self, frame: Data([0, 16, 0, 1])) }
    #expect(throws: TraceRookError.oversizedInput) { try WireCodec.decode(HookEnvelopeV2.self, frame: valid, maximumBytes: 0) }
}

@Test func responseIsBoundToRequestAndSmallerPacketLimit() throws {
    let original = reply()
    #expect(throws: TraceRookError.wrongBinding) {
        try WireCodec.decodeReply(frame: WireCodec.encode(original), matching: UUID())
    }
    #expect(throws: TraceRookError.oversizedInput) {
        try WireCodec.decodeReply(frame: frame(Data(repeating: 32, count: WireLimits.replyBytes + 1)), matching: original.requestID)
    }
    #expect(throws: TraceRookError.malformedInput) {
        try WireCodec.encode(HookReplyV2(requestID: UUID(), decision: .deny, reasonCode: "invalid\ncode",
            explanation: "Safe explanation", decisionSource: .fallback, coverageClass: .other))
    }
}

@Test func nestedCardinalityStringAndDepthLimitsApplyToOriginalInput() throws {
    let tooManyMembers = Dictionary(uniqueKeysWithValues: (0...WireLimits.objectMembers).map { (String($0), JSONValue.null) })
    let tooManyElements = [JSONValue](repeating: .null, count: WireLimits.arrayElements + 1)
    for payload in [JSONValue.object(tooManyMembers), .object(["array": .array(tooManyElements)]),
                    .object(["text": .string(String(repeating: "x", count: WireLimits.stringBytes + 1))])] {
        let raw = try JSONEncoder().encode(envelope(payload: payload))
        #expect(throws: TraceRookError.oversizedInput) { try WireCodec.decodePayload(HookEnvelopeV2.self, payload: raw) }
    }
    let deep = String(repeating: "[", count: 33) + "0" + String(repeating: "]", count: 33)
    let encoded = String(decoding: try JSONEncoder().encode(envelope()), as: UTF8.self)
    let raw = encoded.replacingOccurrences(of: "\"host_payload\":{}", with: "\"host_payload\":{\"nested\":" + deep + "}")
    #expect(throws: TraceRookError.excessiveNesting) { try WireCodec.decodePayload(HookEnvelopeV2.self, payload: Data(raw.utf8)) }
}

@Test func boundarySizedInputsRemainUsableWithoutTruncation() throws {
    let members = Dictionary(uniqueKeysWithValues: (0..<WireLimits.objectMembers).map { (String($0), JSONValue.null) })
    for payload in [JSONValue.object(members), .object(["array": .array([JSONValue](repeating: .null, count: WireLimits.arrayElements))]),
                    .object(["text": .string(String(repeating: "x", count: WireLimits.stringBytes))])] {
        let original = envelope(payload: payload)
        let decoded = try WireCodec.decode(HookEnvelopeV2.self, frame: WireCodec.encode(original))
        #expect(decoded.hostPayload == payload)
    }
}

@Test func wireRejectsMalformedUnicodeGrammarAndTrailingData() throws {
    let encoded = String(decoding: try JSONEncoder().encode(envelope()), as: UTF8.self)
    for object in [#"{"a":"\q"}"#, #"{"a":"\uD800"}"#, #"{"a":true,}"#, #"{"a":01}"#,
                   "{\"a\":" + String(repeating: "9", count: 39) + "}"] {
        let raw = Data(encoded.replacingOccurrences(of: "\"host_payload\":{}", with: "\"host_payload\":" + object).utf8)
        #expect(throws: TraceRookError.malformedInput) { try WireCodec.decodePayload(HookEnvelopeV2.self, payload: raw) }
    }
    #expect(throws: TraceRookError.malformedInput) { try WireCodec.decodePayload(HookEnvelopeV2.self, payload: Data([255])) }
    #expect(throws: TraceRookError.malformedInput) { try WireCodec.decodePayload(HookEnvelopeV2.self, payload: Data((encoded + "{}").utf8)) }
    let bracesInString = envelope(payload: .object(["command": .string("printf '[{\\\"}]'"), "unicode": .string("こんにちは 🐦")]))
    #expect(try WireCodec.decode(HookEnvelopeV2.self, frame: WireCodec.encode(bracesInString)) == bracesInString)
}

@Test func decimalPrecisionSurvivesTheLiveWireBoundary() throws {
    let a = envelope(payload: try JSONValue.decodeBounded(Data(#"{"value":9007199254740992}"#.utf8)))
    let b = envelope(payload: try JSONValue.decodeBounded(Data(#"{"value":9007199254740993}"#.utf8)))
    let decodedA = try WireCodec.decode(HookEnvelopeV2.self, frame: WireCodec.encode(a))
    let decodedB = try WireCodec.decode(HookEnvelopeV2.self, frame: WireCodec.encode(b))
    #expect(try decodedA.hostPayload.canonicalData() != decodedB.hostPayload.canonicalData())
    #expect(throws: TraceRookError.malformedInput) {
        try WireCodec.decodePayload(HookEnvelopeV2.self, payload: replacing(a, key: "received_at_ms", value: .string("1000")))
    }
}

@Test func decodeDeadlineRejectsAlreadyExpiredWork() throws {
    let past = ContinuousClock().now.advanced(by: .seconds(-1))
    #expect(throws: TraceRookError.timeout) { try WireCodec.decode(HookEnvelopeV2.self, frame: WireCodec.encode(envelope()), deadline: past) }
}

@Test func nonceUses128BitsOfSystemRandomnessAndRequiresCanonicalShape() throws {
    let values = try (0..<100).map { _ in try InvocationNonce.generate() }
    #expect(Set(values).count == values.count)
    for value in values { try InvocationNonce.validate(value) }
    for value in ["", String(repeating: "f", count: 31), String(repeating: "F", count: 32), String(repeating: "g", count: 32)] {
        #expect(throws: TraceRookError.wrongBinding) { try InvocationNonce.validate(value) }
    }
}

@Test func deadlinesAndBudgetsRejectOverflowAndInsufficientReserve() throws {
    try RequestBudget().validate()
    for budget in [RequestBudget(hookMilliseconds: Int64.max), RequestBudget(modelMilliseconds: Int64.max),
                   RequestBudget(reviewMilliseconds: -1), RequestBudget(outputReserveMilliseconds: 0), RequestBudget(hookMilliseconds: 54_000)] {
        #expect(throws: TraceRookError.malformedInput) { try budget.validate() }
    }
    for value in [JSONValue.number(-1), .number(1_000), .number(81_001), .number(Decimal(Int64.max))] {
        #expect(throws: TraceRookError.malformedInput) {
            try WireCodec.decodePayload(HookEnvelopeV2.self, payload: replacing(envelope(), key: "hard_deadline_ms", value: value))
        }
    }
}

@Test func providerStatusKeepsDemoAndCoverageSeparate() throws {
    for status in [ProviderStatus(mode: .traceRookCloudDemo, availability: .demo, reasonCode: "synthetic"),
                   ProviderStatus(mode: .anthropicBYOK, availability: .notConfigured, reasonCode: "no_key"),
                   ProviderStatus(mode: .localRulesOnly, availability: .localOnly, reasonCode: "no_remote")] {
        #expect(try WireCodec.decode(ProviderStatus.self, frame: WireCodec.encode(status)) == status)
    }
    #expect(throws: TraceRookError.notDemoData) { try ProviderStatus(mode: .traceRookCloudDemo, availability: .ready, reasonCode: "invalid").validate() }
    #expect(throws: TraceRookError.malformedInput) { try ProviderStatus(mode: .anthropicBYOK, availability: .demo, reasonCode: "invalid").validate() }
}

@Test func evidenceRetainsExactHostAndClassWithoutInferringProtection() throws {
    let evidence = IntegrationEvidence(provider: .claudeCode, hostVersion: "synthetic", toolClass: .fileEdit, testedAtMS: 1,
        schemaHash: String(repeating: "a", count: 64), hookBinarySignature: "synthetic-ad-hoc", callbackObserved: true,
        hostReportedDenial: false, canaryAbsent: true)
    let decoded = try WireCodec.decode(IntegrationEvidence.self, frame: WireCodec.encode(evidence))
    #expect(decoded == evidence && !decoded.hostReportedDenial)
    #expect(throws: TraceRookError.invalidFingerprint) {
        try WireCodec.decodePayload(IntegrationEvidence.self, payload: replacing(evidence, key: "schema_hash", value: .string("bad")))
    }
}
