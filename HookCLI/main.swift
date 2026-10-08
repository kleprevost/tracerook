import Foundation
import TraceRookContracts
import TraceRookAgentAdapters

if CommandLine.arguments.contains("--version") {
    print("tracerook-hook \(TraceRookVersion.app)")
} else if CommandLine.arguments.contains("--self-test") {
    let raw = Data(#"{"session_id":"fixture-session","cwd":"/tmp/tracerook-demo","hook_event_name":"PreToolUse","tool_name":"Bash","tool_use_id":"fixture-call","tool_input":{"command":"printf harmless"}}"#.utf8)
    do {
        let adapter = ClaudeCodeAdapter()
        let event = try adapter.normalize(raw, hookKind: .preToolUse)
        try event.validate()
        let result = adapter.encode(.init(.allow, reasonCode: "fixture", explanation: "Harmless fixture", severity: .low), for: .preToolUse)
        guard result.stdout.isEmpty && result.exitCode == 0 else { exit(1) }
        print("Hook adapter schema and native-permission-preserving allow: passed.")
    } catch {
        FileHandle.standardError.write(Data("Hook self-test failed.\n".utf8)); exit(1)
    }
} else {
    // Foundation builds must never be installed as an operational hook.
    FileHandle.standardError.write(Data("TraceRook hook is not operational in this foundation build; action denied.\n".utf8))
    exit(2)
}
