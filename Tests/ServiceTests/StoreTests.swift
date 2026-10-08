import Foundation
import Testing
import TraceRookContracts
import TraceRookCore
import TraceRookIPC

private func directory() -> URL {
    FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("tracerook-store-\(UUID())")
}

@Test func singleWriterRestartAndDemoSeparation() async throws {
    let url = directory(); defer { try? FileManager.default.removeItem(at: url) }
    let store = try SessionStore(directory: url)
    #expect(throws: StoreError.self) { try SessionStore(directory: url) }
    let event = AgentEvent(agent: .claudeCode, sourceSessionID: "session", sourceToolCallID: "call", kind: .preToolUse, cwd: "[PROJECT]",
                          toolName: "Bash", actionType: .shellExec, argsSummary: "Bash · shell_exec", actionFingerprint: String(repeating: "a", count: 64))
    let session = try await store.record(event, provenance: .hostHook)
    let before = try await store.snapshot(mode: .developer)
    #expect(before.sessions.count == 1 && before.sessions[0].id == session.id)
    #expect(before.sessions[0].coverage == .notIntegrated)
    await store.close()
    let restarted = try SessionStore(directory: url)
    #expect(try await restarted.snapshot(mode: .developer).sessions.count == 1)
    try await restarted.clearHistory()
    #expect(try await restarted.snapshot(mode: .developer).sessions.isEmpty)
    await restarted.close()
    let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
    #expect(attrs[.posixPermissions] as? Int == 0o700)
}

@Test func unsafeStoreAndPrivacyBoundariesReject() async throws {
    let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let link = root.appendingPathComponent("link")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root)
    #expect(throws: StoreError.self) { try SessionStore(directory: link) }
    #expect(throws: TraceRookError.self) { try PersistedPrivacy.validate(["summary": "sk-ant-supersecretsentinel123456"]) }
    #expect(throws: TraceRookError.self) { try PersistedPrivacy.validate(["host_payload": "benign"]) }
    #expect(throws: IPCError.self) { try PeerIdentity(requirement: "not a code requirement!!") }
}

@Test func boundedSnapshotAndRetention() async throws {
    let url = directory(); defer { try? FileManager.default.removeItem(at: url) }
    let store = try SessionStore(directory: url)
    let old = Date.now.addingTimeInterval(-40 * 86_400)
    let event = AgentEvent(agent: .codex, sourceSessionID: "old", sourceToolCallID: "old-call", kind: .preToolUse, occurredAt: old,
                          cwd: "[PROJECT]", toolName: "Bash", actionType: .shellExec, argsSummary: "Shell action", actionFingerprint: String(repeating: "b", count: 64))
    _ = try await store.record(event, provenance: .serviceSimulation)
    #expect(try await store.snapshot(mode: .developer).simulatedSessionIDs.count == 1)
    await #expect(throws: TraceRookError.self) { try await store.snapshot(mode: .developer, limit: 26) }
    try await store.retain()
    #expect(try await store.snapshot(mode: .developer).sessions.isEmpty)
    await store.close()
}
