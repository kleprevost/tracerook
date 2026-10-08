import CryptoKit
import Foundation
import TraceRookContracts
import TraceRookPrivacy

public enum ActionFingerprint {
    public static func make(provider: AgentProvider, sessionID: String, turnID: String?, toolCallID: String,
                            toolName: String, cwd: String, originalInput: JSONValue) throws -> String {
        let value = JSONValue.object([
            "provider": .string(provider.rawValue), "session_id": .string(sessionID),
            "turn_id": turnID.map(JSONValue.string) ?? .null, "tool_call_id": .string(toolCallID),
            "tool_name": .string(toolName), "cwd": .string(cwd), "original_tool_input": originalInput
        ])
        return SHA256.hash(data: try value.canonicalData()).map { String(format: "%02x", $0) }.joined()
    }
}
public struct ClaudeCodeAdapter: AgentAdapter {
    public let provider = AgentProvider.claudeCode
    public init() {}
    public func detectInstallation() async -> AgentInstallationStatus { .init(provider: provider) }
    public func planHookInstall() async throws -> IntegrationChangePlan { throw TraceRookError.unsupportedOperation }
    public func installHooks(_ plan: IntegrationChangePlan) async throws { throw TraceRookError.unsupportedOperation }
    public func uninstallHooks() async throws { throw TraceRookError.unsupportedOperation }
    public func verifyHookConfiguration() async -> IntegrationHealth { .init(provider: provider) }
    public func normalize(_ raw: Data, hookKind: HookKind) throws -> AgentEvent { try AdapterParser.normalize(raw, provider: provider, hookKind: hookKind) }
    public func encode(_ decision: HookDecision, for hookKind: HookKind) -> HookProcessResult { AdapterParser.encode(decision, hookKind: hookKind) }
}
public struct CodexAdapter: AgentAdapter {
    public let provider = AgentProvider.codex
    public init() {}
    public func detectInstallation() async -> AgentInstallationStatus { .init(provider: provider) }
    public func planHookInstall() async throws -> IntegrationChangePlan { throw TraceRookError.unsupportedOperation }
    public func installHooks(_ plan: IntegrationChangePlan) async throws { throw TraceRookError.unsupportedOperation }
    public func uninstallHooks() async throws { throw TraceRookError.unsupportedOperation }
    public func verifyHookConfiguration() async -> IntegrationHealth { .init(provider: provider) }
    public func normalize(_ raw: Data, hookKind: HookKind) throws -> AgentEvent { try AdapterParser.normalize(raw, provider: provider, hookKind: hookKind) }
    public func encode(_ decision: HookDecision, for hookKind: HookKind) -> HookProcessResult { AdapterParser.encode(decision, hookKind: hookKind) }
}
private enum AdapterParser {
    static func normalize(_ raw: Data, provider: AgentProvider, hookKind: HookKind) throws -> AgentEvent {
        let json = try JSONValue.decodeBounded(raw)
        guard case .object = json, let session = json["session_id"]?.string, !session.isEmpty,
              session.utf8.count <= 256, let cwd = json["cwd"]?.string, cwd.hasPrefix("/")
        else { throw TraceRookError.malformedInput }
        guard json["hook_event_name"]?.string == hookKind.hostName else { throw TraceRookError.mismatchedEvent }
        let tool = json["tool_name"]?.string
        if [.preToolUse, .postToolUse, .postToolFailure].contains(hookKind) {
            guard let tool, !tool.isEmpty, case .object = json["tool_input"] else { throw TraceRookError.malformedInput }
        }
        let original = json["tool_input"] ?? .null
        // Missing source IDs receive a new invocation nonce; reattempts must never reuse an approval.
        let callID = json["tool_use_id"]?.string ?? UUID().uuidString
        let turnID = json["turn_id"]?.string
        let fingerprint = try ActionFingerprint.make(provider: provider, sessionID: session, turnID: turnID,
            toolCallID: callID, toolName: tool ?? "", cwd: cwd, originalInput: original)
        let action: ActionType
        switch tool?.lowercased() {
        case "bash", "shell", "exec_command", "shell_command": action = .shellExec
        case "read", "read_file": action = .fileRead
        case "write", "write_file": action = .fileWrite
        case "edit", "multiedit", "apply_patch": action = .fileEdit
        default: action = tool?.hasPrefix("mcp__") == true ? .mcp : .other
        }
        // Summaries contain shape only, never raw shell, source, prompt, or tool-output bodies.
        let summary = hookKind == .userPrompt ? "User task update observed; context not yet accumulated" : "\(tool ?? hookKind.hostName) · \(action.rawValue)"
        let redactor = Redactor()
        return AgentEvent(agent: provider, sourceSessionID: redactor.redact(session, limit: 256).text,
            sourceTurnID: turnID.map { redactor.redact($0, limit: 256).text }, sourceToolCallID: redactor.redact(callID, limit: 256).text,
            kind: hookKind, cwd: redactor.redact(cwd).text, toolName: tool.map { redactor.redact($0, limit: 256).text },
            actionType: action, argsSummary: redactor.redact(summary).text,
            redactionCount: redactor.redact(String(data: raw, encoding: .utf8) ?? "").count, actionFingerprint: fingerprint)
    }
    static func encode(_ decision: HookDecision, hookKind: HookKind) -> HookProcessResult {
        guard hookKind == .preToolUse else { return .init() }
        if [.allow, .warnAllow].contains(decision.outcome) { return .init() }
        // A pending or unavailable evaluator cannot be translated to a native permission grant.
        let explanation = Redactor().redact(decision.sanitizedExplanation, limit: 512).text
        let value: JSONValue = .object(["hookSpecificOutput": .object([
            "hookEventName": .string("PreToolUse"), "permissionDecision": .string("deny"),
            "permissionDecisionReason": .string(explanation)
        ])])
        guard let encoded = try? value.canonicalData() else { return .init(stderr: Data("TraceRook could not inspect this action.\n".utf8), exitCode: 2) }
        return .init(stdout: encoded)
    }
}
