import Foundation
import Testing
import TraceRookContracts
import TraceRookAgentAdapters
import TraceRookFixtures

@Test func fixtureAdaptersValidateAndDoNotPersistRawCommand() throws {
    for (adapter, name) in [(ClaudeCodeAdapter() as any AgentAdapter, "claude-pretool"), (CodexAdapter() as any AgentAdapter, "codex-pretool")] {
        let event = try adapter.normalize(FixtureLoader.data(named: name), hookKind: .preToolUse)
        try event.validate()
        #expect(event.actionType == .shellExec)
        let persisted = String(data: try JSONEncoder().encode(event), encoding: .utf8)!
        #expect(!persisted.contains("printf harmless"))
        #expect(event.actionFingerprint.count == 64)
    }
}
@Test func nativePermissionFlowIsPreserved() throws {
    for adapter in [ClaudeCodeAdapter() as any AgentAdapter, CodexAdapter() as any AgentAdapter] {
        for outcome in [DecisionOutcome.allow, .warnAllow] {
            let result = adapter.encode(.init(outcome, reasonCode: "test", explanation: "test", severity: .low), for: .preToolUse)
            #expect(result.exitCode == 0 && result.stdout.isEmpty && result.stderr.isEmpty)
        }
        let result = adapter.encode(.init(.deny, reasonCode: "critical", explanation: "Blocked fixture", severity: .critical), for: .preToolUse)
        let json = try JSONValue.decodeBounded(result.stdout)
        #expect(json["hookSpecificOutput"]?["permissionDecision"]?.string == "deny")
        #expect(json["continue"] == nil)
        #expect(adapter.encode(.init(.deny, reasonCode: "test", explanation: "test", severity: .high), for: .postToolUse).stdout.isEmpty)
    }
}
@Test func invalidAndMismatchedInputIsRejected() throws {
    let adapter = CodexAdapter()
    #expect(throws: TraceRookError.malformedInput) { try adapter.normalize(Data("{}".utf8), hookKind: .preToolUse) }
    #expect(throws: TraceRookError.mismatchedEvent) { try adapter.normalize(FixtureLoader.data(named: "codex-pretool"), hookKind: .postToolUse) }
}
@Test func fingerprintsAreCanonicalAndBoundToOriginalAction() throws {
    func fingerprint(_ input: JSONValue, call: String = "a") throws -> String {
        try ActionFingerprint.make(provider: .codex, sessionID: "s", turnID: "t", toolCallID: call, toolName: "Bash", cwd: "/tmp", originalInput: input)
    }
    let a: JSONValue = .object(["a": .number(1), "b": .string("two")])
    let b: JSONValue = .object(["b": .string("two"), "a": .number(1)])
    #expect(try fingerprint(a) == fingerprint(b))
    #expect(try fingerprint(a) != fingerprint(a, call: "b"))
    #expect(try fingerprint(a) != fingerprint(.string("changed")))
}

@Test func simultaneousCallsWithoutSourceIDsReceiveIndependentBindings() async throws {
    let raw = Data(#"{"session_id":"s","cwd":"/tmp","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"printf harmless"}}"#.utf8)
    let fingerprints = try await withThrowingTaskGroup(of: String.self) { group in
        for _ in 0..<32 { group.addTask { try CodexAdapter().normalize(raw, hookKind: .preToolUse).actionFingerprint } }
        var results: [String] = []
        for try await result in group { results.append(result) }
        return results
    }
    #expect(Set(fingerprints).count == 32)
}
