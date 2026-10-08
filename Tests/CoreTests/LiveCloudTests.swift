import Foundation
import Testing
import TraceRookContracts
import TraceRookCore
import TraceRookPrivacy

private func cloudRequest(origin: DataOrigin = .live) throws -> CloudAnalysisRequest {
    try CloudAnalysisRequest(origin: origin, deviceID: UUID(), sessionPseudonym: UUID(), source: .claudeCode,
        task: .interfaceChange, action: .shellExec, signals: [.taskMismatch], deadlineMS: 9000)
}
private let unlimitedLimits: JSONValue = .object(["evaluations_per_day": .null, "input_tokens_per_day": .null, "output_tokens_per_day": .null, "devices_per_account": .number(3)])
private func cloudJSON(_ object: [String: JSONValue]) throws -> Data { try JSONValue.object(object).canonicalData() }
private actor TestCloudVault: CloudCredentialStore {
    var saved: CloudStoredEnrollment?
    func load() -> CloudStoredEnrollment? { saved }
    func save(_ enrollment: CloudStoredEnrollment) { saved = enrollment }
    func clear() { saved = nil }
}
private actor TestCloudHTTP: CloudHTTPTransport {
    var requests: [URLRequest] = []
    var failUsage = false
    func setFailUsage() { failUsage = true }
    func send(_ request: URLRequest, deadline: ContinuousClock.Instant) async throws -> LocalAPIDemoHTTPResponse {
        requests.append(request)
        let path = request.url!.path
        let body: Data
        if path == "/v1/alpha/enroll" {
            let submitted = try JSONValue.decodeBounded(request.httpBody!)
            let formatter = ISO8601DateFormatter()
            body = try cloudJSON(["schema_version": .number(1), "device_id": submitted["device_id"]!,
                "device_token": .string("trd_" + String(repeating: "a", count: 64)),
                "token_expires_at": .string(formatter.string(from: .now.addingTimeInterval(86400))), "limits": unlimitedLimits])
        } else if path == "/v1/capabilities" {
            body = try cloudJSON(["schema_version": .number(1), "provider": .string("anthropic"), "transport": .string("tracerook_cloud"),
                "model_id": .string("claude-haiku-5-5"), "analysis_enabled": .bool(true), "privacy_policy_version": .number(2),
                "retention": .object(["receipt_days": .number(30), "usage_days": .number(90), "verdict_cache_seconds": .number(600)]), "limits": unlimitedLimits])
        } else if path == "/v1/usage" {
            if failUsage { throw URLError(.notConnectedToInternet) }
            body = try cloudJSON(["schema_version": .number(1), "date_utc": .string("2026-10-08"), "evaluations_today": .number(987),
                "input_tokens": .number(50000), "output_tokens": .number(9000), "reserved_input_tokens": .number(0), "reserved_output_tokens": .number(0), "limits": unlimitedLimits])
        } else if path == "/v1/device/revoke" { body = try cloudJSON(["schema_version": .number(1), "revoked": .bool(true)]) }
        else { throw URLError(.unsupportedURL) }
        return LocalAPIDemoHTTPResponse(body: body, status: 200)
    }
    func count() -> Int { requests.count }
    func allRequests() -> [URLRequest] { requests }
}
private func settled(_ client: LiveCloudClient) async throws -> LiveCloudStatus {
    for _ in 0..<100 {
        let status = await client.status()
        if !status.busy { return status }
        try await Task.sleep(for: .milliseconds(10))
    }
    throw TraceRookError.timeout
}
@Test func cloudRejectsDemoAndUsesOnlyConstrainedContext() throws {
    #expect(throws: TraceRookError.notDemoData) { try cloudRequest(origin: .demo) }
    let request = try cloudRequest()
    let bytes = try WireCodec.encodePayload(request, maximumBytes: 32768)
    #expect(try WireCodec.decodePayload(CloudAnalysisRequest.self, payload: bytes, maximumBytes: 32768) == request)
    #expect(request.context.recentActivity.isEmpty && !request.context.containsCodeExcerpts)
    #expect(!String(decoding: bytes, as: UTF8.self).contains("simulation"))
    #expect(throws: (any Error).self) { try WireCodec.decodePayload(CloudAnalysisRequest.self, payload: Data("{\"schema_version\":1,\"schema_version\":1}".utf8), maximumBytes: 32768) }
}
@Test(arguments: ["Read /Users/person/project/file", "https://example.com/private", "api_key=unknown", "192.168.1.1", "person@example.com", "q9ZmA2wL5vT7nC3rD8pK6sJ4eH1bX0uF"])
func cloudPreflightRefusesSensitiveSummaries(_ text: String) {
    #expect(throws: TraceRookError.unsafePayload) { try CloudEgress.validateSummary(text) }
}
@Test func cloudPreflightAcceptsLongOrdinaryProse() throws {
    try CloudEgress.validateSummary("Implement a checkout button in a demo user interface and run project tests")
}
@Test func cloudEnrollmentPollsAndNeverInventsInferenceProofOrQuota() async throws {
    let vault = TestCloudVault(), http = TestCloudHTTP()
    let client = LiveCloudClient(vault: vault, transport: http)
    let control = LiveCloudControl(operation: .connect, invitation: "tri_" + String(repeating: "a", count: 64), consent: CloudConsent())
    let immediate = try await client.start(control)
    #expect(immediate.busy)
    let status = try await settled(client)
    #expect(status.connected && status.capabilities?.analysisEnabled == true)
    #expect(status.realAnalysisValidatedAt == nil && status.usage?.evaluationsToday == 987)
    #expect(status.usage?.limits.evaluationsPerDay == nil)
    let uiBytes = try WireCodec.encodePayload(status, maximumBytes: 16384)
    #expect(!String(decoding: uiBytes, as: UTF8.self).contains("trd_"))
    #expect(try await vault.load()?.consent.version == 2)
    let requests = await http.allRequests()
    #expect(requests.count == 3)
    #expect(requests.allSatisfy({ $0.url?.scheme == "https" && $0.url?.host == "api.tracerook.dev" }))
    #expect(requests[0].value(forHTTPHeaderField: "Authorization") == nil)
    #expect(requests[1].value(forHTTPHeaderField: "Authorization")?.hasPrefix("Bearer trd_") == true)
    _ = try await client.start(LiveCloudControl(operation: .disconnect))
    #expect(await client.status().connected == false)
    let disconnected = try await settled(client)
    #expect(!disconnected.connected && disconnected.usage == nil)
    #expect(try await vault.load() == nil)
}
@Test func cloudConsentAndUnavailableUsageNeverProduceProviderProof() async throws {
    let vault = TestCloudVault(), http = TestCloudHTTP()
    let client = LiveCloudClient(vault: vault, transport: http)
    #expect(throws: (any Error).self) { try LiveCloudControl(operation: .connect, invitation: "tri_" + String(repeating: "a", count: 64)).validate() }
    #expect(await http.count() == 0)
    await http.setFailUsage()
    _ = try await client.start(LiveCloudControl(operation: .connect, invitation: "tri_" + String(repeating: "b", count: 64), consent: CloudConsent()))
    let status = try await settled(client)
    #expect(status.connected && status.failure == .unavailable)
    #expect(status.capabilities == nil && status.realAnalysisValidatedAt == nil)
    #expect(await http.count() == 3) // No automatic retries.
}
@Test func cloudHTTPRejectsEndpointSubstitutionBeforeNetwork() async {
    let transport = CloudHTTPSTransport()
    for url in ["http://api.tracerook.dev/v1/analysis", "https://api.tracerook.dev.evil.example/v1/analysis", "https://api.tracerook.dev/v1/analysis?token=x", "https://api.tracerook.dev/v1/analysis#x"] {
        await #expect(throws: TraceRookError.unsafePayload) { try await transport.send(URLRequest(url: URL(string: url)!), deadline: ContinuousClock().now.advanced(by: .seconds(1))) }
    }
}
private func cloudReceipt(_ request: CloudAnalysisRequest) -> JSONValue {
    let formatter = ISO8601DateFormatter()
    return .object([
        "schema_version": .number(1), "request_id": .string(request.requestID.uuidString), "analysis_id": .string("an_" + UUID().uuidString), "server_elapsed_ms": .number(100),
        "verdict": .object(["schema_version": .number(1), "category": .array([.string("unsafe_action")]), "severity": .string("critical"),
            "confidence": .number(1), "suspicious": .bool(true), "rationale": .string("Advisory test response"), "evidence": .array([]),
            "recommended_action": .string("request_approval"), "session_drift": .bool(false), "limitations": .array([.string("A model cannot grant host permission")])]),
        "provenance": .object(["provider": .string("anthropic"), "transport": .string("tracerook_cloud"), "model_id": .string("claude-haiku-5-5"),
            "policy_version": .number(1), "prompt_version": .string("risk-eval-v1"), "trace_id": .string("tr_" + UUID().uuidString), "validated_at": .string(formatter.string(from: .now))]),
        "usage": .object(["input_tokens": .number(800), "output_tokens": .number(180), "billed_units": .number(1)])
    ])
}
@Test func cloudReceiptRejectsFixtureProvenanceWrongBindingAndUnknownFields() throws {
    let request = try cloudRequest()
    let value = cloudReceipt(request)
    let receipt = try WireCodec.decodePayload(LiveCloudAnalysisResponse.self, payload: value.canonicalData(), maximumBytes: 32768)
    try receipt.validate(matching: request)
    #expect(receipt.verdict.severity == .critical && receipt.verdict.recommendedAction == .requestApproval)
    #expect(throws: TraceRookError.wrongBinding) { try receipt.validate(matching: cloudRequest()) }
    guard case .object(var object) = value, case .object(var provenance) = object["provenance"] else { throw TraceRookError.malformedInput }
    provenance["provider"] = .string("fixture"); object["provenance"] = .object(provenance)
    #expect(throws: (any Error).self) { try WireCodec.decodePayload(LiveCloudAnalysisResponse.self, payload: JSONValue.object(object).canonicalData(), maximumBytes: 32768) }
    object["provenance"] = value["provenance"]; object["simulation"] = .bool(true)
    #expect(throws: (any Error).self) { try WireCodec.decodePayload(LiveCloudAnalysisResponse.self, payload: JSONValue.object(object).canonicalData(), maximumBytes: 32768) }
}
private actor DelayedCloudVault: CloudCredentialStore {
    var saved: CloudStoredEnrollment?
    var saving = false
    func load() -> CloudStoredEnrollment? { saved }
    func save(_ enrollment: CloudStoredEnrollment) async {
        saving = true
        // Intentionally ignores cancellation to model an in-progress platform write.
        try? await Task.sleep(for: .milliseconds(100))
        saved = enrollment
    }
    func clear() { saved = nil }
    func isSaving() -> Bool { saving }
}
@Test func cloudDisconnectCannotResurrectCredentialAfterDelayedSave() async throws {
    let vault = DelayedCloudVault(), http = TestCloudHTTP()
    let client = LiveCloudClient(vault: vault, transport: http)
    _ = try await client.start(LiveCloudControl(operation: .connect, invitation: "tri_" + String(repeating: "c", count: 64), consent: CloudConsent()))
    for _ in 0..<100 { if await vault.isSaving() { break }; try await Task.sleep(for: .milliseconds(5)) }
    #expect(await vault.isSaving())
    _ = try await client.start(LiveCloudControl(operation: .disconnect))
    #expect(await client.status().connected == false)
    let status = try await settled(client)
    #expect(!status.connected)
    #expect(try await vault.load() == nil)
}
