import Foundation
import Testing
import TraceRookContracts
import TraceRookCore

private actor DemoHTTP: LocalAPIDemoTransport {
    let device = UUID()
    var calls: [URLRequest] = []
    var badCapabilities = false
    var blockAnalysis = false
    var timeout = false
    var wrongCredentialNamespace = false
    private let started = AsyncStream<Void>.makeStream()
    func configure(badCapabilities: Bool = false, blockAnalysis: Bool = false, timeout: Bool = false, wrongCredentialNamespace: Bool = false) {
        self.badCapabilities = badCapabilities; self.blockAnalysis = blockAnalysis; self.timeout = timeout
        self.wrongCredentialNamespace = wrongCredentialNamespace
    }
    func waitForAnalysis() async { for await _ in started.stream { return } }
    func send(_ request: URLRequest, deadline: ContinuousClock.Instant) async throws -> LocalAPIDemoHTTPResponse {
        calls.append(request)
        #expect(request.url?.host == "127.0.0.1" && request.url?.port == 8787)
        #expect(request.url?.query == nil && request.url?.path.hasPrefix("/mock/v1/") == true)
        if timeout { throw TraceRookError.timeout }
        let route = request.url!.path
        let formatter = ISO8601DateFormatter()
        var result: [String: JSONValue] = ["schema_version": .number(1), "simulation": .bool(true)]
        if route.hasSuffix("alpha/enroll") || route.hasSuffix("device/rotate") {
            result.merge(["device_id": .string(device.uuidString), "device_token": .string((wrongCredentialNamespace ? "live_" : "mock_") + String(repeating: "a", count: 43)),
                          "expires_at": .string(formatter.string(from: .now.addingTimeInterval(3_600)))]) { _, new in new }
        } else if route.hasSuffix("capabilities") {
            result.merge(["provider_ready": .bool(false), "provider": .string(badCapabilities ? "anthropic" : "fixture"),
                          "transport": .string("local_mock"), "model_id": .string("synthetic-v1"), "privacy_policy_version": .number(2)]) { _, new in new }
        } else if route.hasSuffix("usage") {
            result.merge(["fixture_evaluations": .number(0), "input_tokens": .number(0), "output_tokens": .number(0), "billed_units": .number(0)]) { _, new in new }
        } else if route.hasSuffix("analysis") {
            started.continuation.yield(())
            if blockAnalysis { try await Task.sleep(for: .seconds(30)) }
            let body = try WireCodec.decodePayload(LocalAPIDemoRequest.self, payload: request.httpBody!)
            result.merge([
                "request_id": .string(body.requestID.uuidString), "analysis_id": .string("an_" + UUID().uuidString), "server_elapsed_ms": .number(1),
                "verdict": .object(["schema_version": .number(1), "category": .array([.string("unsafe_action")]),
                    "severity": .string("low"), "confidence": .number(1), "suspicious": .bool(false), "rationale": .string("Synthetic UI test"),
                    "evidence": .array([]), "recommended_action": .string("allow"), "session_drift": .bool(false), "limitations": .array([.string("No host action or inference")])]),
                "provenance": .object(["provider": .string("fixture"), "transport": .string("local_mock"), "model_id": .string("synthetic-v1"),
                    "policy_version": .number(1), "prompt_version": .string("mock-risk-eval-v1"), "trace_id": .string("tr_" + UUID().uuidString),
                    "validated_at": .string(formatter.string(from: .now))]),
                "usage": .object(["input_tokens": .number(0), "output_tokens": .number(0), "billed_units": .number(0)])
            ]) { _, new in new }
        } else if route.hasSuffix("device/revoke") { result["revoked"] = .bool(true) }
        else if route.hasSuffix("privacy/delete") { result["deleted"] = .bool(true) }
        else { throw TraceRookError.unsupportedOperation }
        return LocalAPIDemoHTTPResponse(body: try JSONValue.object(result).canonicalData(), status: 200)
    }
}

@Test func demoHTTPRequiresVerifiedCapabilitiesAndKeepsTokensOutOfUI() async throws {
    let transport = DemoHTTP()
    let accepted = LocalAPIDemoClient(transport: transport)
    let status = await accepted.control(.init(operation: .connect))
    try status.validate(); #expect(status.connected && status.failure == nil)
    let bytes = String(decoding: try WireCodec.encodePayload(status), as: UTF8.self)
    #expect(!bytes.contains("device_token") && !bytes.contains("mock_aaa"))
    let calls = await transport.calls
    #expect(calls.count == 3)
    #expect(calls[0].value(forHTTPHeaderField: "Authorization") == nil)
    #expect(calls[1].value(forHTTPHeaderField: "Authorization")?.hasPrefix("Bearer mock_") == true)
    let hostile = DemoHTTP(); await hostile.configure(badCapabilities: true)
    let rejected = await LocalAPIDemoClient(transport: hostile).control(.init(operation: .connect))
    #expect(!rejected.connected && rejected.failure == .malformedResponse)
    let liveCredential = DemoHTTP(); await liveCredential.configure(wrongCredentialNamespace: true)
    let wrongNamespace = await LocalAPIDemoClient(transport: liveCredential).control(.init(operation: .connect))
    #expect(!wrongNamespace.connected && wrongNamespace.failure == .malformedResponse)
    #expect(await liveCredential.calls.count == 1) // reject before forwarding a non-mock bearer
}

@Test func demoClientBindsEnrolledDeviceBeforeNetworkAndNeverRetries() async throws {
    let transport = DemoHTTP()
    let tested = LocalAPIDemoClient(transport: transport)
    let enrolled = await tested.control(.init(operation: .connect))
    let wrongDevice = LocalAPIDemoRequest(scenario: .benign, deviceID: UUID())
    let rejected = await tested.control(.init(operation: .analyze, request: wrongDevice))
    #expect(rejected.lastResponse == nil && rejected.failure == .malformedResponse)
    #expect(await transport.calls.count == 3)
    await transport.configure(timeout: true)
    let timeout = await tested.control(.init(operation: .analyze, request: .init(scenario: .benign, deviceID: enrolled.deviceID!)))
    #expect(timeout.failure == .deadlineExceeded && timeout.lastResponse == nil)
    #expect(await transport.calls.count == 4)
}

@Test func disconnectCancelsInFlightDemoAndPreventsLateReceipt() async throws {
    let transport = DemoHTTP(), client = LocalAPIDemoClient(transport: transport)
    let enrolled = await client.control(.init(operation: .connect))
    await transport.configure(blockAnalysis: true)
    let waiting = Task { await client.control(.init(operation: .analyze, request: .init(scenario: .benign, deviceID: enrolled.deviceID!))) }
    await transport.waitForAnalysis()
    let disconnected = await client.control(.init(operation: .disconnect))
    let late = await waiting.value
    #expect(!disconnected.connected && disconnected.failure == nil)
    #expect(!late.connected && late.lastResponse == nil)
    let status = await client.control(.init(operation: .status))
    try status.validate(); #expect(!status.connected && status.lastRequest == nil)
}

@Test func demoControlIsDeveloperOnlyAndCannotChangeLiveHistory() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("tracerook-api-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try SessionStore(directory: directory)
    let transport = DemoHTTP(), client = LocalAPIDemoClient(transport: transport)
    let payload = try JSONValue.decodeBounded(WireCodec.encodePayload(LocalAPIDemoControl(operation: .connect)))
    let request = ServiceControlRequest(method: .localAPIDemo, payload: payload)
    try request.validate()
    let production = EventBroker(store: store, securityMode: .developerID, localAPIDemo: client)
    #expect(await production.control(request).error == .forbidden)
    #expect(await transport.calls.isEmpty)
    let developer = EventBroker(store: store, securityMode: .developer, localAPIDemo: client)
    let reply = await developer.control(request)
    #expect(reply.error == nil)
    let status = try WireCodec.decodePayload(LocalAPIDemoStatus.self, payload: reply.payload.canonicalData())
    #expect(status.connected)
    let snapshot = try await store.snapshot(mode: .developer, limit: 25)
    #expect(snapshot.sessions.isEmpty && snapshot.approvals.isEmpty && snapshot.incidents.isEmpty)
    #expect(await developer.control(request).error == .invalidRequest) // mutation replay does not enroll again
}
