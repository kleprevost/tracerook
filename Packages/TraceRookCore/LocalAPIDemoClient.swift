import Foundation
import TraceRookContracts

public enum LocalAPIDemoOperation: String, Codable, Sendable { case status, connect, analyze, usage, rotate, disconnect, delete }
public enum LocalAPIDemoFailure: String, Error, Codable, Sendable {
    case invalidRequest = "invalid_request", invalidInvite = "invalid_invite", unauthorized, revoked, conflict
    case rateLimited = "rate_limited", quotaExhausted = "quota_exhausted", providerUnavailable = "provider_unavailable"
    case deadlineExceeded = "deadline_exceeded", upgradeRequired = "upgrade_required"
    case unavailable, malformedResponse = "malformed_response", notConnected = "not_connected", busy, cancelled
    public var title: String {
        switch self {
        case .quotaExhausted: "Simulated quota exhausted"
        case .providerUnavailable: "Simulated provider unavailable"
        case .deadlineExceeded: "Deadline exceeded · no verdict"
        case .unauthorized, .revoked: "Mock authentication expired or revoked · reconnect"
        case .malformedResponse: "Invalid API response rejected"
        case .notConnected: "Connect the local mock first"
        case .busy: "Another mock request is in progress"
        case .cancelled: "Request cancelled · no verdict"
        case .unavailable: "Local API unavailable · no verdict"
        default: "Local API rejected the request · no verdict"
        }
    }
}

public struct LocalAPIDemoControl: IPCMessage {
    public let operation: LocalAPIDemoOperation
    public let request: LocalAPIDemoRequest?
    public init(operation: LocalAPIDemoOperation, request: LocalAPIDemoRequest? = nil) { self.operation = operation; self.request = request }
    public static let wireKeys: Set<String> = ["operation", "request"]
    public static func validateWireShape(_ value: JSONValue) throws {
        try LocalAPIDemoWire.exact(value, keys: wireKeys)
        if let request = value["request"], request != .null { try LocalAPIDemoRequest.validateWireShape(request) }
    }
    public func validate() throws {
        guard (operation == .analyze) == (request != nil) else { throw TraceRookError.malformedInput }
        try request?.validate()
    }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(operation, forKey: .operation); try c.encode(request, forKey: .request)
    }
    enum Keys: String, CodingKey { case operation, request }
}

public struct LocalAPIDemoStatus: IPCMessage {
    public let schemaVersion: Int
    public let simulation: Bool
    public let connected: Bool
    public let deviceID: UUID?
    public let fixtureEvaluations: Int
    public let lastRequest: LocalAPIDemoRequest?
    public let lastResponse: LocalAPIDemoResponse?
    public let failure: LocalAPIDemoFailure?
    public init(connected: Bool = false, deviceID: UUID? = nil, fixtureEvaluations: Int = 0,
                lastRequest: LocalAPIDemoRequest? = nil, lastResponse: LocalAPIDemoResponse? = nil, failure: LocalAPIDemoFailure? = nil) {
        schemaVersion = 1; simulation = true; self.connected = connected; self.deviceID = deviceID
        self.fixtureEvaluations = fixtureEvaluations; self.lastRequest = lastRequest; self.lastResponse = lastResponse; self.failure = failure
    }
    public static let wireKeys: Set<String> = ["schemaVersion", "simulation", "connected", "deviceID", "fixtureEvaluations", "lastRequest", "lastResponse", "failure"]
    public static func validateWireShape(_ value: JSONValue) throws {
        try LocalAPIDemoWire.exact(value, keys: wireKeys)
        if let request = value["lastRequest"], request != .null { try LocalAPIDemoRequest.validateWireShape(request) }
        if let response = value["lastResponse"], response != .null { try LocalAPIDemoResponse.validateWireShape(response) }
    }
    public func validate() throws {
        guard schemaVersion == 1, simulation, connected == (deviceID != nil), (0...30).contains(fixtureEvaluations),
              (lastResponse == nil) == (lastRequest == nil) else { throw TraceRookError.malformedResponse }
        if let request = lastRequest, let response = lastResponse {
            guard failure == nil, connected, request.deviceID == deviceID else { throw TraceRookError.malformedResponse }
            try response.validate(matching: request)
        }
    }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion); try c.encode(simulation, forKey: .simulation)
        try c.encode(connected, forKey: .connected); try c.encode(deviceID, forKey: .deviceID)
        try c.encode(fixtureEvaluations, forKey: .fixtureEvaluations); try c.encode(lastRequest, forKey: .lastRequest)
        try c.encode(lastResponse, forKey: .lastResponse); try c.encode(failure, forKey: .failure)
    }
    enum Keys: String, CodingKey { case schemaVersion, simulation, connected, deviceID, fixtureEvaluations, lastRequest, lastResponse, failure }
}

public struct LocalAPIDemoHTTPResponse: Sendable {
    public let body: Data
    public let status: Int
    public let contentType: String
    public let cacheControl: String
    public init(body: Data, status: Int, contentType: String = "application/json", cacheControl: String = "no-store") {
        self.body = body; self.status = status; self.contentType = contentType; self.cacheControl = cacheControl
    }
}
public protocol LocalAPIDemoTransport: Sendable {
    func send(_ request: URLRequest, deadline: ContinuousClock.Instant) async throws -> LocalAPIDemoHTTPResponse
}

/// Only instantiated by TraceRookAgent. Fixed loopback target, ephemeral session,
/// no cookies/cache/proxy/redirects, and bounded streamed response bytes.
public struct LoopbackDemoTransport: LocalAPIDemoTransport {
    private let session: URLSession
    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil; configuration.httpCookieStorage = nil; configuration.urlCredentialStorage = nil
        configuration.httpShouldSetCookies = false; configuration.waitsForConnectivity = false
        configuration.connectionProxyDictionary = ["HTTPEnable": 0, "HTTPSEnable": 0, "SOCKSEnable": 0]
        configuration.timeoutIntervalForRequest = 4; configuration.timeoutIntervalForResource = 4
        session = URLSession(configuration: configuration, delegate: RejectDemoRedirects(), delegateQueue: nil)
    }
    public func send(_ request: URLRequest, deadline: ContinuousClock.Instant) async throws -> LocalAPIDemoHTTPResponse {
        guard let url = request.url, url.scheme == "http", url.host == "127.0.0.1", url.port == 8787,
              url.path.hasPrefix("/mock/v1/"), url.query == nil, url.user == nil, url.password == nil,
              ContinuousClock().now < deadline else { throw TraceRookError.unsafePayload }
        return try await withThrowingTaskGroup(of: LocalAPIDemoHTTPResponse.self) { group in
            group.addTask {
                let (stream, response) = try await session.bytes(for: request)
                guard let response = response as? HTTPURLResponse, response.url == url,
                      response.expectedContentLength <= 32_768 else { throw TraceRookError.malformedResponse }
                var bytes = Data()
                for try await byte in stream {
                    try Task.checkCancellation()
                    guard bytes.count < 32_768, ContinuousClock().now < deadline else { throw TraceRookError.oversizedInput }
                    bytes.append(byte)
                }
                return LocalAPIDemoHTTPResponse(body: bytes, status: response.statusCode,
                    contentType: response.value(forHTTPHeaderField: "Content-Type") ?? "",
                    cacheControl: response.value(forHTTPHeaderField: "Cache-Control") ?? "")
            }
            group.addTask { try await Task.sleep(until: deadline, clock: .continuous); throw TraceRookError.timeout }
            defer { group.cancelAll() }
            guard let result = try await group.next() else { throw TraceRookError.disconnected }; return result
        }
    }
}
private final class RejectDemoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

public actor LocalAPIDemoClient {
    private let transport: any LocalAPIDemoTransport
    private var credential: MockCredential?
    private var evaluations = 0
    private var lastRequest: LocalAPIDemoRequest?
    private var lastResponse: LocalAPIDemoResponse?
    private var failure: LocalAPIDemoFailure?
    private var generation: UInt64 = 0
    private var busy = false
    private var network: Task<LocalAPIDemoHTTPResponse, any Error>?
    public init(transport: any LocalAPIDemoTransport = LoopbackDemoTransport()) { self.transport = transport }
    public func control(_ command: LocalAPIDemoControl) async -> LocalAPIDemoStatus {
        do { try command.validate() } catch { return status(failure: .invalidRequest) }
        if command.operation == .status { return status() }
        if command.operation == .disconnect || command.operation == .delete {
            let old = credential
            generation &+= 1; network?.cancel(); credential = nil
            lastRequest = nil; lastResponse = nil; evaluations = 0; failure = nil
            if let old {
                // Clear local authority immediately, even when remote revocation fails.
                let path = command.operation == .delete ? "privacy/delete" : "device/revoke"
                var body: [String: JSONValue] = ["device_id": .string(old.deviceID.uuidString)]
                if command.operation == .delete { body["confirm"] = .bool(true) }
                do {
                    let bytes = try await send("POST", path, body: .object(body), token: old.token, deadline: ContinuousClock().now.advanced(by: .seconds(2)))
                    let reply = try WireCodec.decodePayload(MockTerminal.self, payload: bytes, maximumBytes: 32_768)
                    guard (command.operation == .delete ? reply.deleted : reply.revoked) == true else { throw TraceRookError.malformedResponse }
                } catch { failure = .unavailable }
            }
            return status()
        }
        guard !busy else { return status(failure: .busy) }
        busy = true; let epoch = generation
        defer { busy = false }
        failure = nil
        if command.operation != .usage { lastRequest = nil; lastResponse = nil }
        let deadline = ContinuousClock().now.advanced(by: .seconds(4))
        do {
            switch command.operation {
            case .connect:
                if credential == nil {
                    let bytes = try await send("POST", "alpha/enroll", body: .object([
                        "invitation_id": .string("local-demo"), "consent": .bool(true), "privacy_policy_version": .number(2)
                    ]), deadline: deadline)
                    let candidate = try WireCodec.decodePayload(MockCredential.self, payload: bytes, maximumBytes: 32_768)
                    guard epoch == generation else { throw CancellationError() }
                    let capabilities = try await send("GET", "capabilities", token: candidate.token, deadline: deadline)
                    _ = try WireCodec.decodePayload(MockCapabilities.self, payload: capabilities, maximumBytes: 32_768)
                    guard epoch == generation else { throw CancellationError() }
                    credential = candidate
                }
                try await loadUsage(deadline: deadline, epoch: epoch)
            case .analyze:
                guard let credential = validCredential(), let request = command.request else { throw LocalAPIDemoFailure.notConnected }
                guard request.deviceID == credential.deviceID else { throw TraceRookError.wrongBinding }
                let body = try WireCodec.encodePayload(request, maximumBytes: 32_768)
                let result = try await send("POST", "analysis", bytes: body, token: credential.token,
                    deadline: min(deadline, ContinuousClock().now.advanced(by: .milliseconds(request.deadlineMS))))
                let response = try WireCodec.decodePayload(LocalAPIDemoResponse.self, payload: result, maximumBytes: 32_768)
                try response.validate(matching: request)
                guard epoch == generation else { throw CancellationError() }
                lastRequest = request; lastResponse = response
                // Usage is fetched explicitly; an advisory verdict is not accounting.
            case .usage: try await loadUsage(deadline: deadline, epoch: epoch)
            case .rotate:
                guard let old = validCredential() else { throw LocalAPIDemoFailure.notConnected }
                let bytes = try await send("POST", "device/rotate", body: .object(["device_id": .string(old.deviceID.uuidString)]), token: old.token, deadline: deadline)
                let replacement = try WireCodec.decodePayload(MockCredential.self, payload: bytes, maximumBytes: 32_768)
                guard epoch == generation, replacement.deviceID == old.deviceID else { throw TraceRookError.wrongBinding }
                credential = replacement
            default: break
            }
        } catch {
            if epoch == generation {
                lastRequest = nil; lastResponse = nil
                if let code = error as? LocalAPIDemoFailure { failure = code }
                else if error is CancellationError { failure = .cancelled }
                else if error as? TraceRookError == .timeout { failure = .deadlineExceeded }
                else if error is TraceRookError { failure = .malformedResponse }
                else { failure = .unavailable }
                if let failure, [.unauthorized, .revoked, .notConnected].contains(failure) { credential = nil; evaluations = 0 }
                if command.operation == .rotate { credential = nil } // server may have invalidated old token
            }
        }
        return status()
    }
    private func validCredential() -> MockCredential? {
        guard let credential, let expiry = LocalAPIDemoWire.timestamp(credential.expiresAt), expiry > .now else {
            self.credential = nil; return nil
        }
        return credential
    }
    private func status(failure override: LocalAPIDemoFailure? = nil) -> LocalAPIDemoStatus {
        let current = validCredential()
        if let request = lastRequest, let response = lastResponse,
           (try? response.validate(matching: request)) == nil { lastRequest = nil; lastResponse = nil }
        return LocalAPIDemoStatus(connected: current != nil, deviceID: current?.deviceID, fixtureEvaluations: current == nil ? 0 : evaluations,
            lastRequest: current == nil || override != nil ? nil : lastRequest,
            lastResponse: current == nil || override != nil ? nil : lastResponse, failure: override ?? failure)
    }
    private func loadUsage(deadline: ContinuousClock.Instant, epoch: UInt64) async throws {
        guard let credential = validCredential() else { throw LocalAPIDemoFailure.notConnected }
        let bytes = try await send("GET", "usage", token: credential.token, deadline: deadline)
        let value = try WireCodec.decodePayload(MockUsage.self, payload: bytes, maximumBytes: 32_768)
        guard epoch == generation else { throw CancellationError() }; evaluations = value.fixtureEvaluations
    }
    private func send(_ method: String, _ path: String, body: JSONValue? = nil, bytes: Data? = nil, token: String? = nil,
                      deadline: ContinuousClock.Instant) async throws -> Data {
        guard ContinuousClock().now < deadline else { throw TraceRookError.timeout }
        var request = URLRequest(url: URL(string: "http://127.0.0.1:8787/mock/v1/" + path)!)
        request.httpMethod = method; request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.httpBody = try bytes ?? body?.canonicalData()
        request.timeoutInterval = 4; request.setValue("application/json", forHTTPHeaderField: "Accept")
        if request.httpBody != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let token { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        let task = Task { [transport] in try await transport.send(request, deadline: deadline) }
        network = task
        let response = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
        guard response.body.count <= 32_768, response.contentType.lowercased().split(separator: ";").first == "application/json",
              response.cacheControl.lowercased() == "no-store" else { throw TraceRookError.malformedResponse }
        guard response.status == 200 || response.status == 201 else {
            let error = try WireCodec.decodePayload(MockError.self, payload: response.body, maximumBytes: 32_768)
            guard error.error.code.httpStatus == response.status else { throw TraceRookError.malformedResponse }; throw error.error.code
        }
        return response.body
    }
}

private struct MockCredential: IPCMessage, CustomStringConvertible, CustomDebugStringConvertible {
    let schemaVersion: Int; let simulation: Bool; let deviceID: UUID; let token: String; let expiresAt: String
    enum CodingKeys: String, CodingKey { case schemaVersion = "schema_version", simulation, deviceID = "device_id", token = "device_token", expiresAt = "expires_at" }
    static let wireKeys: Set<String> = ["schema_version", "simulation", "device_id", "device_token", "expires_at"]
    var description: String { "<mock credential redacted>" }; var debugDescription: String { description }
    func validate() throws {
        guard schemaVersion == 1, simulation, token.hasPrefix("mock_"), (48...256).contains(token.utf8.count), token.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-").contains($0) }),
              let expiry = LocalAPIDemoWire.timestamp(expiresAt), expiry.timeIntervalSinceNow > 0, expiry.timeIntervalSinceNow <= 3_605 else { throw TraceRookError.malformedResponse }
    }
}
private struct MockCapabilities: IPCMessage {
    let schemaVersion: Int; let simulation: Bool; let providerReady: Bool; let provider: String; let transport: String; let modelID: String; let privacyPolicyVersion: Int
    enum CodingKeys: String, CodingKey { case schemaVersion = "schema_version", simulation, providerReady = "provider_ready", provider, transport, modelID = "model_id", privacyPolicyVersion = "privacy_policy_version" }
    static let wireKeys: Set<String> = ["schema_version", "simulation", "provider_ready", "provider", "transport", "model_id", "privacy_policy_version"]
    func validate() throws { guard schemaVersion == 1, simulation, !providerReady, provider == "fixture", transport == "local_mock", modelID == "synthetic-v1", privacyPolicyVersion == 2 else { throw TraceRookError.malformedResponse } }
}
private struct MockUsage: IPCMessage {
    let schemaVersion: Int; let simulation: Bool; let fixtureEvaluations: Int; let inputTokens: Int; let outputTokens: Int; let billedUnits: Int
    enum CodingKeys: String, CodingKey { case schemaVersion = "schema_version", simulation, fixtureEvaluations = "fixture_evaluations", inputTokens = "input_tokens", outputTokens = "output_tokens", billedUnits = "billed_units" }
    static let wireKeys: Set<String> = ["schema_version", "simulation", "fixture_evaluations", "input_tokens", "output_tokens", "billed_units"]
    func validate() throws { guard schemaVersion == 1, simulation, (0...30).contains(fixtureEvaluations), inputTokens == 0, outputTokens == 0, billedUnits == 0 else { throw TraceRookError.malformedResponse } }
}
private struct MockTerminal: IPCMessage {
    let schemaVersion: Int; let simulation: Bool; let revoked: Bool?; let deleted: Bool?
    enum CodingKeys: String, CodingKey { case schemaVersion = "schema_version", simulation, revoked, deleted }
    static let wireKeys: Set<String> = ["schema_version", "simulation", "revoked"]
    static func validateWireShape(_ value: JSONValue) throws {
        guard case .object(let object) = value, Set(object.keys) == wireKeys || Set(object.keys) == ["schema_version", "simulation", "deleted"] else { throw TraceRookError.malformedInput }
    }
    func validate() throws { guard schemaVersion == 1, simulation, (revoked == true) != (deleted == true) else { throw TraceRookError.malformedResponse } }
}
private struct MockError: IPCMessage {
    struct Detail: Codable, Sendable { let code: LocalAPIDemoFailure; let message: String; let retryable: Bool }
    let schemaVersion: Int; let simulation: Bool; let error: Detail; let traceID: String
    enum CodingKeys: String, CodingKey { case schemaVersion = "schema_version", simulation, error, traceID = "trace_id" }
    static let wireKeys: Set<String> = ["schema_version", "simulation", "error", "trace_id"]
    static func validateWireShape(_ value: JSONValue) throws {
        try LocalAPIDemoWire.exact(value, keys: wireKeys); try LocalAPIDemoWire.exact(value["error"], keys: ["code", "message", "retryable"])
    }
    func validate() throws {
        guard schemaVersion == 1, simulation, error.message.utf8.count <= 512, error.code.httpStatus != 0,
              LocalAPIDemoWire.identifier(traceID, prefix: "tr_") else { throw TraceRookError.malformedResponse }
        try PersistedPrivacy.validate(self)
    }
}
private extension LocalAPIDemoFailure {
    var httpStatus: Int {
        switch self {
        case .invalidRequest, .invalidInvite: 400
        case .unauthorized: 401
        case .revoked: 403
        case .conflict: 409
        case .upgradeRequired: 426
        case .rateLimited, .quotaExhausted: 429
        case .providerUnavailable: 503
        case .deadlineExceeded: 504
        default: 0
        }
    }
}
