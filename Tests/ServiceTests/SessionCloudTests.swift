import Foundation
import Testing
import TraceRookContracts
import TraceRookCore

private let sessionLimits: JSONValue = .object(["evaluations_per_day": .null, "input_tokens_per_day": .null, "output_tokens_per_day": .null, "devices_per_account": .number(3)])
private func sessionCredential(expiry: Date = .now.addingTimeInterval(86400)) throws -> CloudCredential {
    let value: JSONValue = .object(["schema_version": .number(1), "device_id": .string(UUID().uuidString),
        "device_token": .string("trd_" + String(repeating: "a", count: 64)),
        "token_expires_at": .string(ISO8601DateFormatter().string(from: expiry)), "limits": sessionLimits])
    return try WireCodec.decodePayload(CloudCredential.self, payload: value.canonicalData(), maximumBytes: 2048)
}
private func encodedSessionCode(_ bytes: Data) -> String {
    "trb_" + bytes.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
}
@Test func sessionMemoryCredentialsAreIsolatedValidatedAndClearable() async throws {
    let first = SessionCloudCredentialStore(), second = SessionCloudCredentialStore()
    #expect(await first.load() == nil)
    let enrollment = CloudStoredEnrollment(credential: try sessionCredential(), consent: CloudConsent())
    try await first.save(enrollment)
    #expect(await first.load()?.credential.deviceID == enrollment.credential.deviceID)
    #expect(await second.load() == nil)
    let invalid = CloudStoredEnrollment(credential: enrollment.credential, consent: CloudConsent(acceptedAt: .now.addingTimeInterval(3600)))
    await #expect(throws: LiveCloudFailure.consentRequired) { try await first.save(invalid) }
    #expect(await first.load()?.credential.deviceID == enrollment.credential.deviceID)
    await first.clear()
    #expect(await first.load() == nil)
    // A fresh service-owned memory vault has no persisted enrollment to restore.
    #expect(await SessionCloudCredentialStore().load() == nil)
}
@Test func sessionBetaAccessCodeIsCanonicalAndRoundTripsCredential() throws {
    let credential = try sessionCredential()
    let code = try BetaAccessCode.encode(credential)
    #expect(code.hasPrefix("trb_") && !code.contains("=") && !code.contains("+") && !code.contains("/"))
    let decoded = try BetaAccessCode.decode(code)
    #expect(decoded.deviceID == credential.deviceID && decoded.deviceToken == credential.deviceToken)
    #expect(try BetaAccessCode.encode(decoded) == code)
    try LiveCloudControl(operation: .connect, invitation: code, consent: CloudConsent()).validate()
    #expect(!String(describing: decoded).contains(credential.deviceToken))
    #expect(!String(describing: CloudStoredEnrollment(credential: decoded, consent: CloudConsent())).contains(credential.deviceToken))
}
@Test func sessionBetaAccessCodeRejectsMalformedNoncanonicalExpiredAndDuplicatePayloads() throws {
    let credential = try sessionCredential(), code = try BetaAccessCode.encode(credential)
    for invalid in ["", "tri_" + String(repeating: "a", count: 64), code + "=", " " + code, code + "\n", "trb_" + String(repeating: "!", count: 100), "trb_" + String(repeating: "a", count: 3001)] {
        #expect(throws: (any Error).self) { try BetaAccessCode.decode(invalid) }
    }
    let canonical = try WireCodec.encodePayload(credential, maximumBytes: 2048)
    // Equivalent JSON with whitespace must not acquire a second accepted bearer representation.
    #expect(throws: (any Error).self) { try BetaAccessCode.decode(encodedSessionCode(Data(" ".utf8) + canonical)) }
    let object = try JSONValue.decodeBounded(canonical)
    guard case .object(var fields) = object else { throw TraceRookError.malformedInput }
    fields["token_expires_at"] = .string("2020-01-01T00:00:00Z")
    #expect(throws: (any Error).self) { try BetaAccessCode.decode(encodedSessionCode(try JSONValue.object(fields).canonicalData())) }
    fields = { if case .object(let values) = object { return values }; return [:] }()
    fields["unexpected"] = .bool(true)
    #expect(throws: (any Error).self) { try BetaAccessCode.decode(encodedSessionCode(try JSONValue.object(fields).canonicalData())) }
    let duplicate = Data(("{\"schema_version\":1," + String(decoding: canonical.dropFirst(), as: UTF8.self)).utf8)
    #expect(throws: (any Error).self) { try BetaAccessCode.decode(encodedSessionCode(duplicate)) }
    #expect(throws: TraceRookError.malformedInput) { try LiveCloudControl(operation: .connect, invitation: code).validate() }
}

private actor SessionCloudHTTP: CloudHTTPTransport {
    private var paths: [String] = []
    private let failUsage: Bool
    init(failUsage: Bool = false) { self.failUsage = failUsage }
    func recordedPaths() -> [String] { paths }
    func send(_ request: URLRequest, deadline: ContinuousClock.Instant) async throws -> LocalAPIDemoHTTPResponse {
        let path = request.url!.path; paths.append(path)
        #expect(request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Bearer trd_") == true)
        let value: JSONValue
        switch path {
        case "/v1/capabilities":
            value = .object(["schema_version": .number(1), "provider": .string("anthropic"), "transport": .string("tracerook_cloud"),
                "model_id": .string("claude-haiku-5-5"), "analysis_enabled": .bool(true), "privacy_policy_version": .number(2),
                "retention": .object(["receipt_days": .number(30), "usage_days": .number(90), "verdict_cache_seconds": .number(600)]), "limits": sessionLimits])
        case "/v1/usage":
            if failUsage { throw URLError(.notConnectedToInternet) }
            value = .object(["schema_version": .number(1), "date_utc": .string("2026-10-08"), "evaluations_today": .number(0), "input_tokens": .number(0),
                "output_tokens": .number(0), "reserved_input_tokens": .number(0), "reserved_output_tokens": .number(0), "limits": sessionLimits])
        case "/v1/analysis":
            let body = try JSONValue.decodeBounded(request.httpBody!)
            value = .object(["schema_version": .number(1), "request_id": body["request_id"]!, "analysis_id": .string("an_" + UUID().uuidString),
                "verdict": .object(["schema_version": .number(1), "category": .array([.string("unsafe_action")]), "severity": .string("low"),
                    "confidence": .number(1), "suspicious": .bool(false), "rationale": .string("Synthetic session test"), "evidence": .array([]),
                    "recommended_action": .string("allow"), "session_drift": .bool(false), "limitations": .array([])]),
                "provenance": .object(["provider": .string("anthropic"), "transport": .string("tracerook_cloud"), "model_id": .string("claude-haiku-5-5"),
                    "policy_version": .number(1), "prompt_version": .string("risk-eval-v1"), "trace_id": .string("tr_" + UUID().uuidString),
                    "validated_at": .string(ISO8601DateFormatter().string(from: .now))]),
                "usage": .object(["input_tokens": .number(20), "output_tokens": .number(20), "billed_units": .number(1)]), "server_elapsed_ms": .number(1)])
        case "/v1/device/revoke": value = .object(["schema_version": .number(1), "revoked": .bool(true)])
        default: throw TraceRookError.unsupportedOperation
        }
        return LocalAPIDemoHTTPResponse(body: try value.canonicalData(), status: 200)
    }
}
private func sessionSettled(_ client: LiveCloudClient) async throws -> LiveCloudStatus {
    for _ in 0..<100 {
        let status = await client.status()
        if !status.busy { return status }
        try await Task.sleep(for: .milliseconds(10))
    }
    throw TraceRookError.timeout
}
private func sessionAnalysis(_ credential: CloudCredential) throws -> CloudAnalysisRequest {
    try CloudAnalysisRequest(origin: .live, deviceID: credential.deviceID, sessionPseudonym: UUID(), source: .claudeCode,
        task: .unspecified, action: .shellExec, signals: [], deadlineMS: 3000)
}
@Test func sessionManualConnectionEnablesAnalysisAndPausePreventsNetworkUntilResume() async throws {
    let credential = try sessionCredential(), vault = SessionCloudCredentialStore(), transport = SessionCloudHTTP()
    let client = LiveCloudClient(vault: vault, transport: transport)
    let initial = await client.status()
    #expect(!initial.connected && !initial.analysisEnabledLocally)
    let connecting = try await client.start(LiveCloudControl(operation: .connect, invitation: try BetaAccessCode.encode(credential), consent: CloudConsent()))
    #expect(connecting.busy && !connecting.connected && !connecting.analysisEnabledLocally)
    let connected = try await sessionSettled(client)
    #expect(connected.connected && connected.analysisEnabledLocally && connected.capabilities?.analysisEnabled == true)
    #expect(await transport.recordedPaths() == ["/v1/capabilities", "/v1/usage"])
    #expect(await vault.load()?.credential.deviceID == credential.deviceID)
    let paused = try await client.start(LiveCloudControl(operation: .pause))
    #expect(paused.connected && !paused.analysisEnabledLocally)
    let request = try sessionAnalysis(credential)
    await #expect(throws: LiveCloudFailure.notConnected) { try await client.analyze(request, deadline: ContinuousClock().now.advanced(by: .seconds(3))) }
    #expect(await transport.recordedPaths().count == 2)
    let resumed = try await client.start(LiveCloudControl(operation: .resume))
    #expect(resumed.connected && resumed.analysisEnabledLocally)
    _ = try await client.analyze(request, deadline: ContinuousClock().now.advanced(by: .seconds(3)))
    #expect(await transport.recordedPaths().last == "/v1/analysis")
    let disconnected = try await client.start(LiveCloudControl(operation: .disconnect))
    #expect(!disconnected.connected && !disconnected.analysisEnabledLocally)
    _ = try await sessionSettled(client)
    #expect(await vault.load() == nil)
    await #expect(throws: LiveCloudFailure.notConnected) { try await client.start(LiveCloudControl(operation: .resume)) }
}
@Test func sessionFailedAuthenticationChecksNeverAcceptManualCredential() async throws {
    let credential = try sessionCredential(), vault = SessionCloudCredentialStore(), transport = SessionCloudHTTP(failUsage: true)
    let client = LiveCloudClient(vault: vault, transport: transport)
    _ = try await client.start(LiveCloudControl(operation: .connect, invitation: try BetaAccessCode.encode(credential), consent: CloudConsent()))
    let status = try await sessionSettled(client)
    #expect(!status.connected && !status.analysisEnabledLocally && status.failure != nil)
    #expect(await vault.load() == nil)
    #expect(await transport.recordedPaths() == ["/v1/capabilities", "/v1/usage"])
}
@Test func sessionRestoreAndRefreshRequireExplicitAnalysisResume() async throws {
    let credential = try sessionCredential(), vault = SessionCloudCredentialStore(), transport = SessionCloudHTTP()
    try await vault.save(CloudStoredEnrollment(credential: credential, consent: CloudConsent()))
    let client = LiveCloudClient(vault: vault, transport: transport)
    await client.restore()
    let restored = await client.status()
    #expect(restored.connected && !restored.analysisEnabledLocally)
    #expect(await transport.recordedPaths().isEmpty)
    _ = try await client.start(LiveCloudControl(operation: .refresh))
    let status = try await sessionSettled(client)
    #expect(status.connected && !status.analysisEnabledLocally && status.capabilities != nil)
    let request = try sessionAnalysis(credential)
    await #expect(throws: LiveCloudFailure.notConnected) { try await client.analyze(request, deadline: ContinuousClock().now.advanced(by: .seconds(3))) }
    #expect(await transport.recordedPaths().count == 2)
    #expect(try await client.start(LiveCloudControl(operation: .resume)).analysisEnabledLocally)
}
