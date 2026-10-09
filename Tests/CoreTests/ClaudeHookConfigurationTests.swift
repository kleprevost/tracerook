import Foundation
import Testing
import TraceRookCore

private func hookHome() throws -> URL {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    return home
}
private func writeHookSettings(_ text: String, home: URL) throws {
    let directory = home.appendingPathComponent(".claude")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    let url = directory.appendingPathComponent("settings.json")
    try Data(text.utf8).write(to: url)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
}
private func hookPlan(_ home: URL) throws -> ClaudeHookInstallationPlan {
    try ClaudeHookConfiguration.plan(homeDirectory: home, hookExecutable: URL(fileURLWithPath: "/Applications/TraceRook.app/Contents/MacOS/tracerook-hook"), hostVersion: "2.1.0")
}

@Test func claudeHookPreservesSettingsAndUnrelatedHooks() throws {
    let home = try hookHome(); defer { try? FileManager.default.removeItem(at: home) }
    let original = #"{"unknown":{"value":42},"hooks":{"Stop":[{"hooks":[{"type":"command","command":"echo stop"}]}],"PreToolUse":[{"matcher":"Read","hooks":[{"type":"command","command":"echo unrelated"}]}]}}"#
    try writeHookSettings(original, home: home)
    let plan = try hookPlan(home)
    #expect(plan.beforeText == original)
    let installedBackup = try ClaudeHookConfiguration.install(plan)
    let backup = try #require(installedBackup)
    #expect(try String(contentsOf: backup, encoding: .utf8) == original)
    let root = try #require(JSONSerialization.jsonObject(with: Data(plan.afterText.utf8)) as? [String: Any])
    #expect((root["unknown"] as? [String: Int])?["value"] == 42)
    let hooks = try #require(root["hooks"] as? [String: Any])
    #expect(hooks["Stop"] != nil)
    #expect((hooks["PreToolUse"] as? [[String: Any]])?.count == 2)
    #expect(try hookPlan(home).requiresChange == false)
}
@Test func claudeHookRejectsChangedSettings() throws {
    let home = try hookHome(); defer { try? FileManager.default.removeItem(at: home) }
    try writeHookSettings("{}", home: home)
    let plan = try hookPlan(home)
    try Data("{\"changed\":true}".utf8).write(to: plan.settingsURL)
    #expect(throws: ClaudeHookConfigurationError.settingsChanged) { try ClaudeHookConfiguration.install(plan) }
}
@Test func claudeHookRejectsSymlinksAndWritableSettings() throws {
    let home = try hookHome(); defer { try? FileManager.default.removeItem(at: home) }
    try writeHookSettings("{}", home: home)
    let settings = home.appendingPathComponent(".claude/settings.json")
    try FileManager.default.setAttributes([.posixPermissions: 0o666], ofItemAtPath: settings.path)
    #expect(throws: ClaudeHookConfigurationError.unsafePath) { try hookPlan(home) }
    try FileManager.default.removeItem(at: settings)
    try FileManager.default.createSymbolicLink(at: settings, withDestinationURL: home.appendingPathComponent("missing"))
    #expect(throws: ClaudeHookConfigurationError.unsafePath) { try hookPlan(home) }
}
@Test func claudeHookInstallsMissingDirectoryAndKeepsOtherTraceRookCommands() throws {
    let home = try hookHome(); defer { try? FileManager.default.removeItem(at: home) }
    let plan = try hookPlan(home)
    #expect(plan.command.contains("--timeout-ms 80000"))
    #expect(try ClaudeHookConfiguration.install(plan) == nil)
    #expect(try hookPlan(home).requiresChange == false)
    let attributes = try FileManager.default.attributesOfItem(atPath: plan.settingsURL.path)
    #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
}
@Test func claudeHookOnlyReplacesExactOwnedInvocation() throws {
    let home = try hookHome(); defer { try? FileManager.default.removeItem(at: home) }
    let command = try hookPlan(home).command
    let old = ["hooks": ["PreToolUse": [["matcher": "Read", "hooks": [
        ["type": "command", "command": command, "timeout": 1],
        ["type": "command", "command": "tracerook-hook --other", "timeout": 3]
    ]]]]]
    let json = try JSONSerialization.data(withJSONObject: old)
    try writeHookSettings(String(decoding: json, as: UTF8.self), home: home)
    let plan = try hookPlan(home)
    let root = try #require(JSONSerialization.jsonObject(with: Data(plan.afterText.utf8)) as? [String: Any])
    let hooks = try #require(root["hooks"] as? [String: Any])
    let groups = try #require(hooks["PreToolUse"] as? [[String: Any]])
    #expect(groups.count == 2)
    let unrelated = try #require(groups.first?["hooks"] as? [[String: Any]])
    #expect(unrelated.first?["command"] as? String == "tracerook-hook --other")
    let installed = try #require(groups.last?["hooks"] as? [[String: Any]])
    #expect(installed.first?["timeout"] as? Int == 85)
}
@Test func claudeHookRejectsSymlinkDirectory() throws {
    let home = try hookHome(); defer { try? FileManager.default.removeItem(at: home) }
    let other = try hookHome(); defer { try? FileManager.default.removeItem(at: other) }
    try FileManager.default.createSymbolicLink(at: home.appendingPathComponent(".claude"), withDestinationURL: other)
    #expect(throws: ClaudeHookConfigurationError.unsafePath) { try hookPlan(home) }
}

@Test func claudeHookAcceptsOwnerControlledReadableSettings() throws {
    let home = try hookHome(); defer { try? FileManager.default.removeItem(at: home) }
    try writeHookSettings("{\"custom\":true}", home: home)
    let settings = home.appendingPathComponent(".claude/settings.json")
    try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: settings.path)
    let plan = try hookPlan(home)
    #expect(plan.beforeText == "{\"custom\":true}")
    let installedBackup = try ClaudeHookConfiguration.install(plan)
    let backup = try #require(installedBackup)
    #expect(try String(contentsOf: backup, encoding: .utf8) == plan.beforeText)
    #expect((try FileManager.default.attributesOfItem(atPath: settings.path)[.posixPermissions] as? NSNumber)?.intValue == 0o600)
}
