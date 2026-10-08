import Foundation
import Testing
import TraceRookContracts
import TraceRookFixtures

@Test func demoSchemaIsExplicitAndInternallyConsistent() throws {
    let snapshot = try FixtureLoader.loadDemo()
    try snapshot.validate()
    #expect(snapshot.origin == .demo)
    #expect(snapshot.sessions.allSatisfy { $0.coverage == .demo })
}
@Test func boundsAreEnforcedBeforeJSONRecursion() throws {
    #expect(throws: TraceRookError.oversizedInput) { try JSONValue.decodeBounded(Data(repeating: 32, count: 1_048_577)) }
    #expect(throws: TraceRookError.excessiveNesting) { try JSONValue.decodeBounded(Data((String(repeating: "[", count: 33) + "0" + String(repeating: "]", count: 33)).utf8)) }
    #expect(throws: TraceRookError.malformedInput) { try JSONValue.decodeBounded(Data([0xFF])) }
    #expect(try JSONValue.decodeBounded(Data(#"{"text":"[[[\\\""}"#.utf8)).depth == 1)
}
@Test func coverageRequiresEveryVerificationFact() {
    let now = Date()
    #expect(IntegrationHealth(provider: .codex, status: .verified).effectiveStatus() == .notIntegrated)
    #expect(IntegrationHealth(provider: .codex, status: .verified, configured: true, schemaCheck: true, signedHelper: true).effectiveStatus() == .needsTrust)
    #expect(IntegrationHealth(provider: .codex, status: .verified, configured: true, trusted: true, schemaCheck: true, signedHelper: true).effectiveStatus() == .monitoringOnly)
    #expect(IntegrationHealth(provider: .codex, configured: true, trusted: true, schemaCheck: true, signedHelper: true, lastSuccessfulHookAt: now, lastPreToolTestAt: now.addingTimeInterval(-90_000)).effectiveStatus(now: now) == .verificationNotRecent)
    #expect(IntegrationHealth(provider: .codex, configured: true, trusted: true, schemaCheck: true, signedHelper: true, lastPreToolTestAt: now).effectiveStatus(now: now) == .monitoringOnly)
    #expect(IntegrationHealth(provider: .codex, detectedVersion: "fixture-version", configured: true, trusted: true, schemaCheck: true, signedHelper: true, lastSuccessfulHookAt: now, lastPreToolTestAt: now).effectiveStatus(now: now) == .verified)
}

@Test func numbersDoNotLoseExactActionPrecision() throws {
    let a = try JSONValue.decodeBounded(Data(#"{"value":9007199254740992}"#.utf8))
    let b = try JSONValue.decodeBounded(Data(#"{"value":9007199254740993}"#.utf8))
    #expect(try a.canonicalData() != b.canonicalData())
    let decimal = try JSONValue.decodeBounded(Data(#"{"value":0.12345678901234567890123456789}"#.utf8))
    #expect(String(data: try decimal.canonicalData(), encoding: .utf8)?.contains("0.12345678901234567890123456789") == true)
    #expect(throws: TraceRookError.malformedInput) { try JSONValue.decodeBounded(Data("1.0e-9223372036854775808".utf8)) }
    #expect(throws: TraceRookError.malformedInput) { try JSONValue.decodeBounded(Data(String(repeating: "9", count: 39).utf8)) }
}

@Test func hookWireSchemaMatchesTheSpecification() throws {
    let json = Data(#"{"protocol_version":1,"request_id":"00000000-0000-0000-0000-000000000001","adapter":"codex","hook_kind":"pre_tool_use","host_payload":{},"cli_version":"0.1.0","deadline_epoch_ms":1}"#.utf8)
    let request = try JSONDecoder().decode(HookRequest.self, from: json)
    #expect(request.protocolVersion == 1 && request.adapter == .codex)
    let response = HookResponse(requestID: request.requestID, decision: .init(.deny, reasonCode: "TR-CRED-EXFIL", explanation: "Sensitive upload", severity: .critical))
    let encoded = try JSONValue.decodeBounded(JSONEncoder().encode(response))
    #expect(encoded["decision"]?.string == "deny")
    #expect(encoded["reason_code"]?.string == "TR-CRED-EXFIL")
    #expect(encoded["request_id"]?.string != nil && encoded["requestID"] == nil)
}
