import Darwin
import Foundation
import TraceRookContracts
import TraceRookCore

/// Explicit operator test entry point. Uses the signed native UI's existing XPC
/// client and the real cloud control path. The caller keeps the app alive so a
/// subsequent genuine host hook can use this memory-only enrollment.
@MainActor
enum BetaCloudProbe {
    enum Failure: String, Error {
        case unsafeCredentialFile = "unsafe_credential_file"
        case invalidCredential = "invalid_credential"
        case serviceUnavailable = "service_unavailable"
        case connectionFailed = "connection_failed"
        case cloudUnavailable = "cloud_unavailable"
        case unexpectedProvider = "unexpected_provider"
        case deadlineExceeded = "deadline_exceeded"
        case receiptWriteFailed = "receipt_write_failed"
    }
    private struct Receipt: Encodable {
        let schemaVersion = 1
        let purpose = "native_signed_cloud_connection_probe"
        let recordedAt: String
        let success: Bool
        let failure: String?
        let serviceConnected: Bool
        let cloudConnected: Bool
        let analysisEnabledLocally: Bool
        let deviceID: UUID?
        let provider: String?
        let transport: String?
        let modelID: String?
        let privacyPolicyVersion: Int?
        let evaluationsToday: Int?
        let inputTokens: Int?
        let outputTokens: Int?
        let reservedInputTokens: Int?
        let reservedOutputTokens: Int?
        let realAnalysisValidatedAt: String?
        let consentVersion = 2
        let consentCategories = ["coarse_task_class", "coarse_action_class", "local_signal_codes"]
        let containsCodeExcerpts = false
        let connectionProvesHostEnforcement = false
    }

    /// Pass absolute paths: application launch does not preserve a shell's cwd.
    /// Calling this probe explicitly opts this operator test into CloudConsent v2
    /// (coarse task/action classes and local signals, with no code excerpts).
    @discardableResult
    static func run(agent: AgentConnection, credentialFile: URL, receiptFile: URL) async -> Bool {
        var cloud = LiveCloudStatus()
        var failure: Failure?
        var success = false
        do {
            guard credentialFile.isFileURL, credentialFile.path.hasPrefix("/"),
                  receiptFile.isFileURL, receiptFile.path.hasPrefix("/") else { throw Failure.unsafeCredentialFile }
            let code = try accessCode(from: credentialFile)
            agent.start()
            await agent.refresh()
            guard agent.connected else { throw Failure.serviceUnavailable }
            let consent = CloudConsent()
            try consent.validate()
            let connect = LiveCloudControl(operation: .connect, invitation: code, consent: consent)
            cloud = try await command(connect, agent: agent)
            let deadline = ContinuousClock().now.advanced(by: .seconds(18))
            while cloud.busy {
                guard !Task.isCancelled, ContinuousClock().now < deadline else { throw Failure.deadlineExceeded }
                try await Task.sleep(for: .milliseconds(250))
                cloud = try await command(LiveCloudControl(operation: .status), agent: agent)
            }
            guard cloud.connected, cloud.analysisEnabledLocally, cloud.failure == nil,
                  let capabilities = cloud.capabilities, let usage = cloud.usage else { throw Failure.cloudUnavailable }
            guard capabilities.analysisEnabled, capabilities.provider == "anthropic",
                  capabilities.transport == "tracerook_cloud", capabilities.modelID == "claude-haiku-5-5",
                  capabilities.privacyPolicyVersion == 2 else { throw Failure.unexpectedProvider }
            try capabilities.validate(); try usage.validate()
            await agent.refresh()
            guard agent.connected else { throw Failure.serviceUnavailable }
            success = true
        } catch let safe as Failure { failure = safe }
        catch { failure = .connectionFailed }
        // Serialize only this whitelist. Never encode the input credential,
        // access code, control command, request body, or arbitrary error text.
        let receipt = Receipt(recordedAt: ISO8601DateFormatter().string(from: .now), success: success,
            failure: failure?.rawValue, serviceConnected: agent.connected,
            cloudConnected: cloud.connected, analysisEnabledLocally: cloud.analysisEnabledLocally,
            deviceID: cloud.deviceID,
            provider: cloud.capabilities?.provider == "anthropic" ? "anthropic" : nil,
            transport: cloud.capabilities?.transport == "tracerook_cloud" ? "tracerook_cloud" : nil,
            modelID: cloud.capabilities?.modelID == "claude-haiku-5-5" ? "claude-haiku-5-5" : nil,
            privacyPolicyVersion: cloud.capabilities?.privacyPolicyVersion,
            evaluationsToday: cloud.usage?.evaluationsToday, inputTokens: cloud.usage?.inputTokens,
            outputTokens: cloud.usage?.outputTokens, reservedInputTokens: cloud.usage?.reservedInputTokens,
            reservedOutputTokens: cloud.usage?.reservedOutputTokens, realAnalysisValidatedAt: cloud.realAnalysisValidatedAt)
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(receipt)
            guard data.count <= 4096 else { return false }
            try FileManager.default.createDirectory(at: receiptFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: receiptFile, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: receiptFile.path)
        } catch { return false }
        return success
    }

    private static func command(_ control: LiveCloudControl, agent: AgentConnection) async throws -> LiveCloudStatus {
        let payload = try JSONValue.decodeBounded(WireCodec.encodePayload(control, maximumBytes: WireLimits.replyBytes))
        let reply = try await agent.command(.liveCloud, payload: payload)
        return try WireCodec.decodePayload(LiveCloudStatus.self, payload: reply.payload.canonicalData(), maximumBytes: WireLimits.replyBytes)
    }

    private static func accessCode(from file: URL) throws -> String {
        // Authenticate the opened inode, preventing last-component symlink races
        // and unbounded FileHandle allocations. File contents are never logged.
        let descriptor = open(file.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard descriptor >= 0 else { throw Failure.unsafeCredentialFile }
        defer { Darwin.close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_uid == geteuid(), info.st_nlink == 1, info.st_mode & 0o7777 == 0o600,
              (1...4096).contains(info.st_size) else { throw Failure.unsafeCredentialFile }
        var bytes = Data(), buffer = [UInt8](repeating: 0, count: 1024)
        while true {
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            if count == 0 { break }
            if count < 0 { if errno == EINTR { continue }; throw Failure.unsafeCredentialFile }
            guard bytes.count + count <= 4096 else { throw Failure.unsafeCredentialFile }
            bytes.append(contentsOf: buffer.prefix(count))
        }
        guard !bytes.isEmpty else { throw Failure.invalidCredential }
        do {
            if let text = String(data: bytes, encoding: .utf8), text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("trb_") {
                let code = text.trimmingCharacters(in: .whitespacesAndNewlines)
                _ = try BetaAccessCode.decode(code)
                return code
            }
            let credential = try WireCodec.decodePayload(CloudCredential.self, payload: bytes, maximumBytes: 4096)
            return try BetaAccessCode.encode(credential)
        } catch { throw Failure.invalidCredential }
    }
}
