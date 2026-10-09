import AppKit
import SwiftUI
import TraceRookContracts
import TraceRookCore
import TraceRookIPC

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--local-api-smoke-test") {
            Task { @MainActor in
                do {
                    let client = XPCClient(agent: try SignedFamily(bundle: Bundle.main.bundleURL).agent)
                    func control(_ command: LocalAPIDemoControl) async throws -> LocalAPIDemoStatus {
                        let value = try JSONValue.decodeBounded(WireCodec.encodePayload(command, maximumBytes: WireLimits.replyBytes))
                        let request = ServiceControlRequest(method: .localAPIDemo, payload: value)
                        let reply = try WireCodec.decode(ServiceControlReply.self, frame: await client.call(WireCodec.encode(request)))
                        guard reply.requestID == request.requestID, reply.error == nil else { throw IPCError.transport }
                        return try WireCodec.decodePayload(LocalAPIDemoStatus.self, payload: reply.payload.canonicalData(), maximumBytes: WireLimits.replyBytes)
                    }
                    func snapshot() async throws -> ServiceSnapshot {
                        let request = ServiceControlRequest(method: .snapshot, payload: .object(["limit": .number(25)]))
                        let reply = try WireCodec.decode(ServiceControlReply.self, frame: await client.call(WireCodec.encode(request)))
                        guard reply.requestID == request.requestID, reply.error == nil else { throw IPCError.transport }
                        let result = try JSONDecoder().decode(ServiceSnapshot.self, from: reply.payload.canonicalData())
                        try result.validate(); return result
                    }
                    let before = try await snapshot()
                    let enrolled = try await control(.init(operation: .connect))
                    guard enrolled.connected, enrolled.failure == nil, let device = enrolled.deviceID else { throw TraceRookError.disconnected }
                    for scenario in [LocalAPIDemoScenario.benign, .credentialTransfer, .taskDrift] {
                        let request = LocalAPIDemoRequest(scenario: scenario, deviceID: device)
                        let status = try await control(.init(operation: .analyze, request: request))
                        guard status.failure == nil, let response = status.lastResponse else { throw TraceRookError.malformedResponse }
                        try response.validate(matching: request)
                        print("Native → authenticated service → local HTTP: \(scenario.rawValue) passed; synthetic, zero Claude tokens.")
                    }
                    let failures: [(LocalAPIDemoScenario, LocalAPIDemoFailure)] = [(.providerUnavailable, .providerUnavailable), (.quotaExhausted, .quotaExhausted), (.deadlineExceeded, .deadlineExceeded)]
                    for (scenario, expected) in failures {
                        let status = try await control(.init(operation: .analyze, request: .init(scenario: scenario, deviceID: device)))
                        guard status.failure == expected, status.lastResponse == nil else { throw TraceRookError.malformedResponse }
                        print("Typed local API failure: \(scenario.rawValue) passed; no verdict or permission.")
                    }
                    let rotated = try await control(.init(operation: .rotate))
                    guard rotated.connected, rotated.deviceID == device, rotated.failure == nil else { throw TraceRookError.notAuthenticated }
                    let usage = try await control(.init(operation: .usage))
                    guard usage.fixtureEvaluations == enrolled.fixtureEvaluations + 3 else { throw TraceRookError.malformedResponse }
                    let deleted = try await control(.init(operation: .delete))
                    guard !deleted.connected, deleted.failure == nil else { throw TraceRookError.notAuthenticated }
                    let after = try await snapshot()
                    guard before.sessions.map(\.id) == after.sessions.map(\.id), before.incidents.map(\.id) == after.incidents.map(\.id),
                          before.approvals.map(\.id) == after.approvals.map(\.id) else { throw TraceRookError.notDemoData }
                    print("Mock rotation, actual fixture usage, deletion, and unchanged live history: passed. Host protection remains unverified.")
                    exit(0)
                } catch { FileHandle.standardError.write(Data("Local API native smoke failed: \(error as? TraceRookError ?? .disconnected).\n".utf8)); exit(1) }
            }
        }
        if CommandLine.arguments.contains("--service-smoke-test") {
            Task { @MainActor in
                do {
                    let client = XPCClient(agent: try SignedFamily(bundle: Bundle.main.bundleURL).agent)
                    let request = ServiceControlRequest(method: .snapshot, payload: .object(["limit": .number(25)]))
                    let response = try WireCodec.decode(ServiceControlReply.self, frame: await client.call(WireCodec.encode(request)))
                    guard response.requestID == request.requestID, response.error == nil else { throw IPCError.transport }
                    let snapshot = try JSONDecoder().decode(ServiceSnapshot.self, from: response.payload.canonicalData())
                    try snapshot.validate()
                    print("Authenticated service snapshot: passed; sessions=\(snapshot.sessions.count); security=\(snapshot.securityMode.rawValue).")
                    if CommandLine.arguments.contains("--simulate-ingestion") {
                        let mutation = ServiceControlRequest(method: .simulatedIngestion)
                        let reply = try WireCodec.decode(ServiceControlReply.self, frame: await client.call(WireCodec.encode(mutation)))
                        guard reply.error == nil else { throw IPCError.transport }
                        print("Simulated ingestion through authenticated XPC: passed; no host tool was running.")
                    }
                    exit(0)
                } catch { FileHandle.standardError.write(Data("Authenticated service smoke test failed.\n".utf8)); exit(1) }
            }
        }
        if CommandLine.arguments.contains("--launch-smoke-test") {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                let visibleWindows = NSApp.windows.filter { $0.isVisible && !($0 is NSPanel) }
                print("Native launch: \(visibleWindows.count) dashboard windows visible.")
                exit(visibleWindows.isEmpty ? 1 : 0)
            }
        }
        if let index = CommandLine.arguments.firstIndex(of: "--ui-smoke-test"), CommandLine.arguments.indices.contains(index + 1) {
            let directory = CommandLine.arguments[index + 1]
            Task { @MainActor in
                do { try await UISmokeRenderer.run(directory: URL(fileURLWithPath: directory)); exit(0) }
                catch { FileHandle.standardError.write(Data("Native UI smoke rendering failed.\n".utf8)); exit(1) }
            }
        }
    }
}

@main
struct TraceRookApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @ViewState<AppEnvironment> private var environment = AppEnvironment()
    var body: some Scene {
        WindowGroup("TraceRook", id: "dashboard") {
            DashboardView().environment(environment).tint(RookTheme.accent)
                .preferredColorScheme(environment.colorScheme)
                .frame(minWidth: 1040, minHeight: 700)
        }
        .defaultSize(width: 1220, height: 830)
        .defaultLaunchBehavior(.presented)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { environment.model.destination = .settings }.keyboardShortcut(",")
            }
            CommandMenu("TraceRook") {
                Button("Explore Cloud Demo") { Task { await environment.exploreDemo() } }.keyboardShortcut("d", modifiers: [.command, .shift])
                Button("Simulate review") { environment.simulate() }.disabled(!environment.model.showingDemo)
                Button("Show real activity") { environment.model.showRealActivity() }
            }
        }
        MenuBarExtra {
            MenuBarView().environment(environment)
        } label: {
            Image(systemName: environment.model.pauseUntil == nil ? "shield.lefthalf.filled" : "pause.circle")
                .accessibilityLabel("TraceRook · \(environment.model.liveCoverage.title)")
        }
    }
}

struct MenuBarView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Text("Protection: \(environment.model.liveCoverage.title)")
        Text("Claude Code: \(environment.claudeIntegration.title(in: environment.model))")
        Text("Codex: Coming soon")
        Divider()
        Text("Real observed sessions: \(environment.model.observedHostSessionCount)")
        Text("Demo pending reviews: \(environment.model.demoApprovals.filter { $0.isPending(at: .now) }.count)")
        Button("Open Dashboard") { openWindow(id: "dashboard"); NSApp.activate(ignoringOtherApps: true) }
        Button("Approvals") {
            environment.model.destination = .approvals; openWindow(id: "dashboard")
        }
        Text(environment.agent.cloud.analysisEnabledLocally ? "Cloud analysis: enabled" : "Cloud analysis: paused or unavailable")
        Button("Settings…") { environment.model.destination = .settings; openWindow(id: "dashboard") }
        Divider()
        Text(environment.agent.status)
        Button("Quit UI") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
    }
}
