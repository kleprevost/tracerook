import Foundation
import Darwin
import TraceRookRules
import TraceRookContracts
import TraceRookIPC
import TraceRookCore
import TraceRookAgentAdapters

if CommandLine.arguments.contains("--version") {
    print("tracerook-hook \(TraceRookVersion.app)")
} else if CommandLine.arguments.contains("--protocol-version") {
    print(TraceRookVersion.liveIPC)
} else if CommandLine.arguments.contains("--self-test") {
    let raw = Data(#"{"session_id":"fixture-session","cwd":"/tmp/tracerook-demo","hook_event_name":"PreToolUse","tool_name":"Bash","tool_use_id":"fixture-call","tool_input":{"command":"printf harmless"}}"#.utf8)
    do {
        let adapter = ClaudeCodeAdapter()
        let event = try adapter.normalize(raw, hookKind: .preToolUse)
        try event.validate()
        let result = adapter.encode(.init(.allow, reasonCode: "fixture", explanation: "Harmless fixture", severity: .low), for: .preToolUse)
        guard result.stdout.isEmpty && result.exitCode == 0 else { exit(1) }
        let envelope = HookEnvelopeV2(requestKind: .preToolUse, adapter: .claudeCode,
            receivedAtMS: 1, hardDeadlineMS: 80_001, hostVersion: "synthetic",
            invocationNonce: try InvocationNonce.generate(), hostPayload: try JSONValue.decodeBounded(raw))
        let decoded = try WireCodec.decode(HookEnvelopeV2.self, frame: WireCodec.encode(envelope))
        guard decoded == envelope else { exit(1) }
        let reply = HookReplyV2(requestID: envelope.requestID, decision: .noOverride,
            reasonCode: "fixture", explanation: "Synthetic codec test", decisionSource: .fallback, coverageClass: .shellExec)
        _ = try WireCodec.decodeReply(frame: WireCodec.encode(reply, maximumBytes: WireLimits.replyBytes), matching: envelope.requestID)
        print("Synthetic adapter and IPC v2 round trip: passed; no host permissions granted; host configuration requires manual setup and actual-host verification.")
    } catch {
        FileHandle.standardError.write(Data("Hook self-test failed.\n".utf8)); exit(1)
    }
} else if CommandLine.arguments.contains("--ipc-self-test") || CommandLine.arguments.contains("--ipc-route-self-test") {
    do {
        let family = try SignedFamily(bundle: SignedFamily.currentBundle())
        let now = Int64(Date.now.timeIntervalSince1970 * 1_000)
        let request = HookEnvelopeV2(requestKind: .preToolUse, adapter: .claudeCode, receivedAtMS: now,
            hardDeadlineMS: now + 5_000, hostVersion: "synthetic-transport-test", invocationNonce: try InvocationNonce.generate(),
            hostPayload: .object(["session_id": .string("synthetic-ipc"), "cwd": .string("/tmp"), "hook_event_name": .string("PreToolUse"),
                "tool_name": .string("Bash"), "tool_input": .object(["command": .string("echo benign")])]))
        let frame = try SocketTransport.exchange(path: PrivateStateDirectory.standard.appendingPathComponent("hook.sock").path,
            frame: WireCodec.encode(request), peer: family.agent, deadline: ContinuousClock().now.advanced(by: .seconds(5)))
        _ = try WireCodec.decodeReply(frame: frame, matching: request.requestID)
        if CommandLine.arguments.contains("--ipc-route-self-test") {
            var rejected = false
            do {
                let mutation = ServiceControlRequest(method: .clearHistory)
                _ = try SocketTransport.exchange(path: PrivateStateDirectory.standard.appendingPathComponent("hook.sock").path,
                    frame: WireCodec.encode(mutation), peer: family.agent, deadline: ContinuousClock().now.advanced(by: .seconds(3)))
            } catch { rejected = true }
            guard rejected else { exit(1) }
            print("Hook-socket control mutation rejected: passed.")
        }
        print("Bidirectional audit-backed hook authentication: passed; synthetic transport only.")
    } catch {
        if let error = error as? IPCError { print("IPC self-test error: \(error)") }
        FileHandle.standardError.write(Data("Hook authentication self-test failed.\n".utf8)); exit(1)
    }
} else {
    runHostHook()
}

private func runHostHook() {
    // The deadline starts before stdin, signature verification, and socket setup.
    let clock = ContinuousClock(), start = clock.now
    let nowMS = Int64(Date.now.timeIntervalSince1970 * 1000)
    var kind = HookKind.preToolUse
    var adapter: any AgentAdapter = ClaudeCodeAdapter()
    func emit(_ result: HookProcessResult) -> Never {
        if !result.stdout.isEmpty { FileHandle.standardOutput.write(result.stdout); FileHandle.standardOutput.write(Data("\n".utf8)) }
        if !result.stderr.isEmpty { FileHandle.standardError.write(result.stderr) }
        exit(result.exitCode)
    }
    do {
        let args = Array(CommandLine.arguments.dropFirst())
        func option(_ name: String) -> String? {
            guard let index = args.firstIndex(of: name), index + 1 < args.count else { return nil }; return args[index + 1]
        }
        guard let source = option("--adapter"), let provider = AgentProvider(rawValue: source),
              let version = option("--host-version"), !version.isEmpty,
              let timeout = Int64(option("--timeout-ms") ?? "80000"), (2000...80000).contains(timeout),
              args.count == (option("--timeout-ms") == nil ? 4 : 6),
              Set(args.enumerated().filter { $0.offset % 2 == 0 }.map(\.element)).isSubset(of: ["--adapter", "--host-version", "--timeout-ms"])
        else { throw TraceRookError.malformedInput }
        adapter = provider == .claudeCode ? ClaudeCodeAdapter() : CodexAdapter()
        let deadline = start.advanced(by: .milliseconds(timeout - 1000))
        let raw = try readHostInput(deadline: min(deadline, start.advanced(by: .seconds(3))))
        let payload = try HostPayloadDocument.decode(raw)
        guard let hostKind = payload["hook_event_name"]?.string,
              let matched = HookKind.allCases.first(where: { $0.hostName == hostKind }) else { throw TraceRookError.mismatchedEvent }
        kind = matched
        let event = try adapter.normalize(raw, hookKind: kind)
        let envelope = HookEnvelopeV2(requestKind: kind, adapter: provider, receivedAtMS: nowMS,
            hardDeadlineMS: nowMS + timeout, hostVersion: version, invocationNonce: try InvocationNonce.generate(), hostPayload: payload)
        do {
            let family = try SignedFamily(bundle: SignedFamily.currentBundle())
            let frame = try SocketTransport.exchange(path: PrivateStateDirectory.standard.appendingPathComponent("hook.sock").path,
                frame: WireCodec.encode(envelope), peer: family.agent, deadline: deadline)
            let reply = try WireCodec.decodeReply(frame: frame, matching: envelope.requestID)
            guard clock.now < deadline else { throw TraceRookError.timeout }
            emit(adapter.encode(.init(reply.decision == .deny ? .deny : .allow, reasonCode: reply.reasonCode,
                explanation: reply.explanation, severity: .unknown), for: kind))
        } catch {
            // Emergency parity uses the same local rules, and never converts a
            // socket/signature failure into a native permission grant.
            if kind != .preToolUse { emit(.init()) }
            let assessment = LocalPolicy.evaluate(tool: payload["tool_name"]?.string ?? "", input: payload["tool_input"] ?? .null,
                context: PolicyContext(cwd: payload["cwd"]?.string ?? "/"))
            let deny = assessment.catastrophic || assessment.severity.score >= Severity.high.score || (!assessment.inspectionComplete && event.actionType.isMutableOrExec)
            emit(adapter.encode(.init(deny ? .deny : .allow, reasonCode: "emergency_fallback",
                explanation: deny ? "TraceRook service unavailable; conservative local fallback denied this action." : "Local fallback completed; native host permissions apply.", severity: assessment.severity), for: kind))
        }
    } catch {
        // Even malformed lifecycle input gets a pre-tool denial shape: never trust
        // an unvalidated event name to suppress fail-closed output.
        emit(adapter.encode(.init(.deny, reasonCode: "invalid_host_input", explanation: "TraceRook could not inspect the host input; action denied.", severity: .high), for: .preToolUse))
    }
}

private func readHostInput(deadline: ContinuousClock.Instant) throws -> Data {
    var data = Data(), buffer = [UInt8](repeating: 0, count: 8192)
    while ContinuousClock().now < deadline {
        var descriptor = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
        let polled = poll(&descriptor, 1, 50)
        if polled < 0 { if errno == EINTR { continue }; throw TraceRookError.malformedInput }
        if polled == 0 { continue }
        guard descriptor.revents & (Int16(POLLIN) | Int16(POLLHUP)) != 0 else { throw TraceRookError.malformedInput }
        let count = Darwin.read(STDIN_FILENO, &buffer, buffer.count)
        if count == 0 { guard !data.isEmpty else { throw TraceRookError.malformedInput }; return data }
        if count < 0 { if errno == EINTR { continue }; throw TraceRookError.malformedInput }
        guard data.count + count <= WireLimits.packetBytes else { throw TraceRookError.oversizedInput }
        data.append(contentsOf: buffer.prefix(count))
    }
    throw TraceRookError.timeout
}
