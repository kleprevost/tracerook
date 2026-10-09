import Foundation
import Observation
import TraceRookContracts
import TraceRookCore

struct ClaudeIntegrationPreview: Identifiable {
    let id = UUID()
    let plan: ClaudeHookInstallationPlan
}

@MainActor @Observable
final class ClaudeIntegrationConnection {
    private(set) var installed = false
    private(set) var configured = false
    private(set) var hostVersion = "Not checked"
    private(set) var busy = false
    private(set) var message: String?
    var preview: ClaudeIntegrationPreview?

    func refresh() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let version = try await Self.detectVersion()
            installed = true; hostVersion = version
            let hook = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/tracerook-hook")
            let plan = try await Task.detached { try ClaudeHookConfiguration.plan(hookExecutable: hook, hostVersion: version) }.value
            configured = !plan.requiresChange; message = nil
        } catch {
            configured = false
            message = "Claude installation or settings could not be checked. No configuration was changed."
        }
    }
    func prepare() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let version = try await Self.detectVersion()
            installed = true; hostVersion = version
            let hook = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/tracerook-hook")
            let plan = try await Task.detached { try ClaudeHookConfiguration.plan(hookExecutable: hook, hostVersion: version) }.value
            preview = ClaudeIntegrationPreview(plan: plan)
        } catch { message = "Cannot prepare Claude settings safely. No file was changed." }
    }
    func confirm() async {
        guard let pending = preview, !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let plan = pending.plan
            _ = try await Task.detached { try ClaudeHookConfiguration.install(plan) }.value
            preview = nil; configured = true
            message = "Hook configured. Start a new Claude Code session and run a harmless command to check the callback."
        } catch { message = "Settings changed or could not be written safely. Cancel and review a fresh preview." }
    }
    func latestCallback(in model: DesktopModel) -> Date? {
        model.liveSnapshot?.sessions.filter { $0.provider == .claudeCode && !model.isSimulatedSession($0.id) }
            .flatMap(\.events).filter { $0.summary.hasPrefix("PreToolUse") }.map(\.at).max()
    }
    func title(in model: DesktopModel) -> String {
        guard configured else { return "Not configured" }
        guard model.serviceConnected else { return "Service disconnected" }
        if let at = latestCallback(in: model), Date().timeIntervalSince(at) < 300 { return "Connected · callback observed" }
        return "Configured · awaiting callback"
    }
    nonisolated private static func detectVersion() async throws -> String {
        try await Task.detached {
            let home = FileManager.default.homeDirectoryForCurrentUser
            let candidates = [home.appendingPathComponent(".local/bin/claude").path, "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
            guard let binary = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { throw CocoaError(.fileNoSuchFile) }
            let process = Process(); process.executableURL = URL(fileURLWithPath: binary); process.arguments = ["--version"]
            let output = Pipe(); process.standardOutput = output; process.standardError = FileHandle.nullDevice
            try process.run()
            let deadline = Date().addingTimeInterval(5)
            while process.isRunning && Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
            if process.isRunning { process.terminate(); throw CocoaError(.executableRuntimeMismatch) }
            guard process.terminationStatus == 0 else { throw CocoaError(.executableRuntimeMismatch) }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            guard data.count < 256, let text = String(data: data, encoding: .utf8), let version = text.split(whereSeparator: \.isWhitespace).first,
                  version.allSatisfy({ $0.isNumber || $0 == "." }) else { throw CocoaError(.executableRuntimeMismatch) }
            return String(version)
        }.value
    }
}
