import Foundation
import TraceRookContracts

public enum LiveCloudFailure: String, Error, Codable, Sendable {
    case invalidRequest = "invalid_request", invalidInvite = "invalid_invite", unauthorized, revoked, conflict
    case consentRequired = "consent_required", inProgress = "in_progress", replayUnavailable = "replay_unavailable"
    case upgradeRequired = "upgrade_required", rateLimited = "rate_limited", quotaExhausted = "quota_exhausted"
    case providerUnavailable = "provider_unavailable", deadlineExceeded = "deadline_exceeded"
    case unavailable, malformedResponse = "malformed_response", notConnected = "not_connected", busy, credentialStorage = "credential_storage"
}
public struct CloudConsent: Codable, Sendable, Equatable {
    public let version: Int
    public let acceptedAt: Date
    public let provider: String
    public let categories: [String]
    public let containsCodeExcerpts: Bool
    public init(acceptedAt: Date = .now) {
        version = 2; self.acceptedAt = acceptedAt; provider = "anthropic"
        categories = ["coarse_task_class", "coarse_action_class", "local_signal_codes"]
        containsCodeExcerpts = false
    }
    public func validate() throws {
        guard version == 2, acceptedAt <= .now, provider == "anthropic", !containsCodeExcerpts,
              categories == ["coarse_task_class", "coarse_action_class", "local_signal_codes"] else { throw LiveCloudFailure.consentRequired }
    }
}
public struct CloudStoredEnrollment: Codable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let credential: CloudCredential
    public let consent: CloudConsent
    public init(credential: CloudCredential, consent: CloudConsent) { self.credential = credential; self.consent = consent }
    public var description: String { "<cloud enrollment redacted>" }
    public var debugDescription: String { description }
    public func validate() throws { try credential.validate(); try consent.validate() }
}
public protocol CloudCredentialStore: Sendable {
    func load() async throws -> CloudStoredEnrollment?
    func save(_ enrollment: CloudStoredEnrollment) async throws
    func clear() async throws
}
public protocol CloudHTTPTransport: Sendable {
    func send(_ request: URLRequest, deadline: ContinuousClock.Instant) async throws -> LocalAPIDemoHTTPResponse
}
/// Service-owned HTTPS transport. Redirects, cookies, cache, URL credentials,
/// arbitrary endpoints and automatic retries are disabled.
public struct CloudHTTPSTransport: CloudHTTPTransport {
    private let session: URLSession
    public init() {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil; config.httpCookieStorage = nil; config.urlCredentialStorage = nil
        config.httpShouldSetCookies = false; config.waitsForConnectivity = false
        config.timeoutIntervalForRequest = 12; config.timeoutIntervalForResource = 12
        session = URLSession(configuration: config, delegate: CloudNoRedirect(), delegateQueue: nil)
    }
    public func send(_ request: URLRequest, deadline: ContinuousClock.Instant) async throws -> LocalAPIDemoHTTPResponse {
        guard let url = request.url, url.scheme == "https", url.host == "api.tracerook.dev", url.port == nil,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              ["/v1/alpha/enroll", "/v1/capabilities", "/v1/usage", "/v1/device/rotate", "/v1/device/revoke", "/v1/privacy/delete", "/v1/analysis"].contains(url.path),
              ContinuousClock().now < deadline else { throw TraceRookError.unsafePayload }
        return try await withThrowingTaskGroup(of: LocalAPIDemoHTTPResponse.self) { group in
            group.addTask {
                let (stream, reply) = try await session.bytes(for: request)
                guard let reply = reply as? HTTPURLResponse, reply.url == url, reply.expectedContentLength <= 32768 else { throw TraceRookError.malformedResponse }
                var bytes = Data()
                for try await byte in stream {
                    try Task.checkCancellation()
                    guard bytes.count < 32768, ContinuousClock().now < deadline else { throw TraceRookError.timeout }
                    bytes.append(byte)
                }
                return LocalAPIDemoHTTPResponse(body: bytes, status: reply.statusCode,
                    contentType: reply.value(forHTTPHeaderField: "Content-Type") ?? "", cacheControl: reply.value(forHTTPHeaderField: "Cache-Control") ?? "")
            }
            group.addTask { try await Task.sleep(until: deadline, clock: .continuous); throw TraceRookError.timeout }
            defer { group.cancelAll() }
            guard let reply = try await group.next() else { throw TraceRookError.disconnected }; return reply
        }
    }
}
private final class CloudNoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

public actor LiveCloudClient {
    private let transport: any CloudHTTPTransport
    private let vault: any CloudCredentialStore
    private var enrollment: CloudStoredEnrollment?
    private var capabilities: CloudCapabilities?
    private var usage: LiveCloudUsage?
    private var validatedAt: String?
    private var failure: LiveCloudFailure?
    private var generation: UInt64 = 0
    private var busy = false
    private var network: Task<LocalAPIDemoHTTPResponse, any Error>?
    private var job: Task<Void, Never>?
    public init(vault: any CloudCredentialStore, transport: any CloudHTTPTransport = CloudHTTPSTransport()) { self.vault = vault; self.transport = transport }
    public func restore() async {
        let epoch = generation
        do { let saved = try await vault.load(); try saved?.validate(); guard epoch == generation, !busy else { return }; enrollment = saved }
        catch { guard epoch == generation, !busy else { return }; enrollment = nil; failure = .credentialStorage }
    }
    public func status() -> LiveCloudStatus {
        if let enrollment, (try? enrollment.validate()) == nil { self.enrollment = nil; capabilities = nil; usage = nil; validatedAt = nil; failure = .unauthorized }
        return LiveCloudStatus(connected: enrollment != nil, busy: busy, deviceID: enrollment?.credential.deviceID,
            capabilities: capabilities, usage: usage, realAnalysisValidatedAt: validatedAt, failure: failure)
    }
    /// Returns promptly to XPC. Long-running requests are polled through status;
    /// they cannot exceed the control channel's five-second deadline.
    public func start(_ command: LiveCloudControl) throws -> LiveCloudStatus {
        try command.validate()
        if command.operation == .status { return status() }
        guard !busy || command.operation == .disconnect || command.operation == .delete else { throw LiveCloudFailure.busy }
        generation &+= 1; let epoch = generation
        let previous = job
        let old = enrollment
        if command.operation == .disconnect || command.operation == .delete {
            network?.cancel(); previous?.cancel()
            enrollment = nil; capabilities = nil; usage = nil; validatedAt = nil
        }
        busy = true; failure = nil
        job = Task {
            // Wait for an earlier vault write to finish before clearing it. A
            // cancelled enrollment cannot resurrect a token after disconnect.
            if command.operation == .disconnect || command.operation == .delete { await previous?.value }
            await self.perform(command, epoch: epoch, oldEnrollment: old)
        }
        return status()
    }
    private func perform(_ command: LiveCloudControl, epoch: UInt64, oldEnrollment: CloudStoredEnrollment?) async {
        let deadline = ContinuousClock().now.advanced(by: .seconds(12))
        defer { if epoch == generation { busy = false } }
        do {
            switch command.operation {
            case .connect:
                guard let invitation = command.invitation, let consent = command.consent else { throw LiveCloudFailure.consentRequired }
                try consent.validate()
                let device = enrollment?.credential.deviceID ?? UUID()
                let bytes = try await send("POST", "alpha/enroll", body: .object([
                    "schema_version": .number(1), "invitation": .string(invitation), "device_id": .string(device.uuidString),
                    "app_version": .string("0.3.0"), "privacy_policy_version": .number(2)
                ]), deadline: deadline)
                let credential = try WireCodec.decodePayload(CloudCredential.self, payload: bytes, maximumBytes: 32768)
                guard epoch == generation, credential.deviceID == device else { throw TraceRookError.wrongBinding }
                let saved = CloudStoredEnrollment(credential: credential, consent: consent)
                try await vault.save(saved)
                guard epoch == generation else { throw CancellationError() }
                enrollment = saved; validatedAt = nil
                try await refresh(deadline: deadline, epoch: epoch)
            case .refresh: try await refresh(deadline: deadline, epoch: epoch)
            case .rotate:
                guard let old = enrollment else { throw LiveCloudFailure.notConnected }
                let bytes = try await send("POST", "device/rotate", body: deviceBody(old), token: old.credential.deviceToken, deadline: deadline)
                let credential = try WireCodec.decodePayload(CloudCredential.self, payload: bytes, maximumBytes: 32768)
                guard credential.deviceID == old.credential.deviceID, epoch == generation else { throw TraceRookError.wrongBinding }
                let saved = CloudStoredEnrollment(credential: credential, consent: old.consent)
                try await vault.save(saved); guard epoch == generation else { throw CancellationError() }; enrollment = saved
            case .disconnect, .delete:
                let old = oldEnrollment
                enrollment = nil; capabilities = nil; usage = nil; validatedAt = nil
                try await vault.clear()
                if let old {
                    var body = deviceBody(old)
                    if command.operation == .delete, case .object(var object) = body { object["confirm"] = .bool(true); body = .object(object) }
                    let bytes = try await send("POST", command.operation == .delete ? "privacy/delete" : "device/revoke", body: body, token: old.credential.deviceToken, deadline: deadline)
                    let key = command.operation == .delete ? "deleted" : "revoked"
                    let value = try JSONValue.decodeBounded(bytes)
                    try CloudWire.exact(value, keys: ["schema_version", key])
                    guard value["schema_version"] == .number(1), value[key] == .bool(true) else { throw TraceRookError.malformedResponse }
                }
            case .status: break
            }
        } catch {
            guard epoch == generation else { return }
            failure = classify(error)
            if command.operation == .rotate || failure == .unauthorized || failure == .revoked {
                enrollment = nil; capabilities = nil; usage = nil; validatedAt = nil
                try? await vault.clear()
            }
        }
    }
    public func analyze(_ request: CloudAnalysisRequest, deadline: ContinuousClock.Instant) async throws -> LiveCloudAnalysisResponse {
        guard !busy, let enrollment, let capabilities, capabilities.analysisEnabled else { throw LiveCloudFailure.notConnected }
        try enrollment.validate(); try request.validate()
        guard request.deviceID == enrollment.credential.deviceID else { throw TraceRookError.wrongBinding }
        busy = true; let epoch = generation; defer { if epoch == generation { busy = false } }
        let response = try await send("POST", "analysis", bytes: WireCodec.encodePayload(request, maximumBytes: 32768),
            token: enrollment.credential.deviceToken, deadline: min(deadline, ContinuousClock().now.advanced(by: .milliseconds(request.deadlineMS))))
        let receipt = try WireCodec.decodePayload(LiveCloudAnalysisResponse.self, payload: response, maximumBytes: 32768)
        try receipt.validate(matching: request)
        guard epoch == generation else { throw CancellationError() }
        validatedAt = receipt.provenance.validatedAt; failure = nil
        return receipt
    }
    private func refresh(deadline: ContinuousClock.Instant, epoch: UInt64) async throws {
        guard let saved = enrollment else { throw LiveCloudFailure.notConnected }; try saved.validate()
        let cap = try WireCodec.decodePayload(CloudCapabilities.self, payload: await send("GET", "capabilities", token: saved.credential.deviceToken, deadline: deadline), maximumBytes: 32768)
        let count = try WireCodec.decodePayload(LiveCloudUsage.self, payload: await send("GET", "usage", token: saved.credential.deviceToken, deadline: deadline), maximumBytes: 32768)
        guard epoch == generation else { throw CancellationError() }; capabilities = cap; usage = count
    }
    private func deviceBody(_ saved: CloudStoredEnrollment) -> JSONValue { .object(["schema_version": .number(1), "device_id": .string(saved.credential.deviceID.uuidString)]) }
    private func send(_ method: String, _ path: String, body: JSONValue? = nil, bytes: Data? = nil, token: String? = nil, deadline: ContinuousClock.Instant) async throws -> Data {
        guard ContinuousClock().now < deadline else { throw TraceRookError.timeout }
        var request = URLRequest(url: URL(string: "https://api.tracerook.dev/v1/" + path)!)
        request.httpMethod = method; request.httpBody = try bytes ?? body?.canonicalData()
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData; request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if request.httpBody != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let token { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        let task = Task { [transport] in try await transport.send(request, deadline: deadline) }; network = task
        let response = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
        guard response.body.count <= 32768, response.contentType.lowercased().split(separator: ";").first == "application/json",
              response.cacheControl.lowercased().split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }).contains("no-store") else { throw TraceRookError.malformedResponse }
        guard response.status == 200 || response.status == 201 else {
            let error = try WireCodec.decodePayload(CloudAPIError.self, payload: response.body, maximumBytes: 32768)
            guard error.matches(response.status) else { throw TraceRookError.malformedResponse }; throw error.error.code
        }
        return response.body
    }
    private func classify(_ error: any Error) -> LiveCloudFailure {
        if let error = error as? LiveCloudFailure { return error }
        if error as? TraceRookError == .timeout { return .deadlineExceeded }
        if error is TraceRookError { return .malformedResponse }
        return .unavailable
    }
}
private struct CloudAPIError: IPCMessage {
    struct Detail: Codable, Sendable { let code: LiveCloudFailure; let message: String; let retryable: Bool }
    let schemaVersion: Int; let error: Detail; let traceID: String
    enum CodingKeys: String, CodingKey { case schemaVersion = "schema_version", error, traceID = "trace_id" }
    static let wireKeys: Set<String> = ["schema_version", "error", "trace_id"]
    static func validateWireShape(_ value: JSONValue) throws { try CloudWire.exact(value, keys: wireKeys); try CloudWire.exact(value["error"], keys: ["code", "message", "retryable"]) }
    func validate() throws { guard schemaVersion == 1, error.message.utf8.count <= 512, CloudWire.identifier(traceID, prefix: "tr_") else { throw TraceRookError.malformedResponse } }
    func matches(_ status: Int) -> Bool {
        switch error.code {
        case .invalidRequest: status == 400 || status == 413
        case .invalidInvite, .revoked, .consentRequired: status == 403
        case .unauthorized: status == 401
        case .conflict, .inProgress, .replayUnavailable: status == 409
        case .upgradeRequired: status == 426
        case .rateLimited, .quotaExhausted: status == 429
        case .providerUnavailable: status == 503
        case .deadlineExceeded: status == 504
        default: false
        }
    }
}
