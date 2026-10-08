import Foundation
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
        print("Synthetic adapter and IPC v2 round trip: passed; no host permissions granted; bridge remains nonoperational.")
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
    // Foundation builds must never be installed as an operational hook.
    FileHandle.standardError.write(Data("TraceRook hook is not operational in this foundation build; action denied.\n".utf8))
    exit(2)
}
