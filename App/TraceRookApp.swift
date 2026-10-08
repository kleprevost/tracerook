import AppKit
import SwiftUI
import TraceRookContracts
import TraceRookCore
import TraceRookIPC

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationDidFinishLaunching(_ notification: Notification) {
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
                Button("Explore Cloud Demo") { environment.model.exploreDemo() }.keyboardShortcut("d", modifiers: [.command, .shift])
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
        Text("Protection: \(environment.model.pauseUntil == nil ? "Limited · Not integrated" : "Paused")")
        Text("Claude Code: Not integrated")
        Text("Codex: Not integrated")
        Divider()
        Text("Real observed sessions: \(environment.model.observedHostSessionCount)")
        Text("Demo pending reviews: \(environment.model.demoApprovals.filter { $0.isPending(at: .now) }.count)")
        Button("Open Dashboard") { openWindow(id: "dashboard"); NSApp.activate(ignoringOtherApps: true) }
        Button("Approvals") {
            if environment.model.demoApprovals.contains(where: { $0.isPending(at: .now) }) { environment.model.showingDemo = true }
            environment.model.destination = .approvals; openWindow(id: "dashboard")
        }
        if environment.model.pauseUntil == nil {
            Button("Pause Protection (15 minutes)") { environment.model.pause() }
        } else {
            Button("Resume Protection") { environment.model.resume() }
        }
        Button("Settings…") { environment.model.destination = .settings; openWindow(id: "dashboard") }
        Divider()
        Text(environment.agent.status)
        Button("Quit UI") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
    }
}
