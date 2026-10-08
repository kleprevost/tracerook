import SwiftUI
import TraceRookContracts

struct IntegrationsView: View {
    @Environment(AppEnvironment.self) private var environment
    @ViewState<AgentProvider?> private var selectedPreview: AgentProvider?
    var body: some View {
        @Bindable var agent = environment.agent
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeading(title: "Connect with confidence", subtitle: "Installation, host trust and verified execution are separate checks.")
                Surface {
                    Label("Background service", systemImage: "gearshape.2").font(.headline)
                    Text(environment.agent.status).font(.callout)
                    Text("Enable starts a per-user service and a private local history database. Agent hooks are configured separately, following the installation guide.").font(.callout).foregroundStyle(.secondary)
                    HStack {
                        Button("Enable Background Service") { environment.agent.enable() }
                        Button("Disable Service") { Task { await environment.agent.disable() } }
                        if environment.agent.connected {
                            Button("Demonstrate service ingestion") {
                                Task { _ = try? await environment.agent.command(.simulatedIngestion); await environment.agent.refresh(); environment.model.showRealActivity() }
                            }
                        }
                    }.buttonStyle(.bordered)
                    Text("Simulated ingestion tests the real local store and IPC; it does not verify host protection.").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(AgentProvider.allCases, id: \.self) { provider in
                    Surface {
                        HStack { Text(provider.title).font(.title2.bold()); Spacer(); StatusBadge(text: "Not integrated", symbol: "circle.dashed") }
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 16) {
                            fact("Installed", "Not checked")
                            fact("Configured", "No")
                            fact("Trusted", provider == .codex ? "Needs host review" : "Not verified")
                            fact("Verified", "No actual callback")
                            fact("Host version", "Compatibility unverified")
                            fact("Recent hook", "Never")
                        }
                        Divider()
                        Text("Supported events").font(.subheadline.bold())
                        Text("SessionStart · UserPromptSubmit · PreToolUse · PostToolUse · SessionEnd").font(.caption.monospaced()).foregroundStyle(.secondary)
                        Text(provider == .codex
                             ? "Codex must review and trust the exact hook definition via /hooks. Installed does not mean trusted. Hosted tools and write_stdin continuations can be outside the pre-tool path."
                             : "Local Claude Code hooks must actually execute. Remote sessions, disabled hooks and timeouts can bypass the check; post-tool events cannot prevent an action.")
                            .font(.callout).foregroundStyle(.secondary)
                        HStack {
                            Button("Install") {}.disabled(true)
                            Button("Repair") {}.disabled(true)
                            Button("Test Hook") {}.disabled(true)
                            Button("Uninstall") {}.disabled(true)
                            Button("View sample changes") { selectedPreview = provider }
                        }.buttonStyle(.bordered)
                        if provider == .codex {
                            DisclosureGroup("Codex trust instructions") {
                                Text("After a consented installation, open a local Codex session and run /hooks. Review the TraceRook command and trust the definition. Then run a harmless host smoke test. TraceRook will show Needs approval until an actual callback and compatibility test verify execution.")
                                    .font(.callout).foregroundStyle(.secondary).padding(.top, 8)
                            }
                        }
                    }
                }
                Text("Add the TraceRook hook to your agent settings using the installation guide at tracerook.dev/docs/beta. TraceRook never edits unrelated settings or hooks.").font(.caption).foregroundStyle(.secondary)
            }.padding(28)
        }
        .sheet(item: $selectedPreview) { provider in IntegrationPreview(provider: provider) }
        .sheet(item: $agent.servicePlan) { plan in
            VStack(alignment: .leading, spacing: 16) {
                PageHeading(title: "Enable the local background service", subtitle: "Non-notarized build · per-user LaunchAgent")
                Text(plan.destination.path).font(.caption.monospaced()).textSelection(.enabled)
                Text("This installs the exact configuration below, starts the bundled helper at login, and creates a private history store. The helper validates exact signatures of this installed app and CLI. Replacing an ad-hoc bundle changes that local trust boundary; it does not prove publisher identity.").font(.callout)
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Before").font(.headline)
                        Text(plan.originalContent.flatMap { String(data: $0, encoding: .utf8) } ?? "No existing file")
                        Text("After").font(.headline)
                        Text(plan.preview)
                    }.font(.caption.monospaced()).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }.frame(height: 260)
                HStack {
                    Button("Cancel") { agent.servicePlan = nil }
                    Spacer()
                    Button("Install this configuration") { agent.confirmLocalService() }.buttonStyle(.borderedProminent)
                }
            }.padding(24).frame(width: 680)
        }
    }
    private func fact(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) { Text(title).font(.caption).foregroundStyle(.secondary); Text(value).font(.callout.weight(.medium)) }
    }
}
extension AgentProvider: Identifiable { public var id: String { rawValue } }
struct IntegrationPreview: View {
    @Environment(\.dismiss) private var dismiss
    let provider: AgentProvider
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            DemoBadge()
            PageHeading(title: "Sample configuration preview", subtitle: "\(provider.title) · Illustration only; no file is read or modified")
            Text(provider == .claudeCode ? "~/.claude/settings.json" : "~/.codex/hooks.json").font(.callout.monospaced())
            GroupBox("Before · sample") { Text("Existing settings and unrelated hooks").frame(maxWidth: .infinity, alignment: .leading).padding(8) }
            GroupBox("After · sample") {
                Text("Preserve existing configuration\n+ TraceRook-owned command hook\n+ PreToolUse matcher: *\n+ timeout: 85 seconds\n+ Session/prompt/post-tool lifecycle hooks")
                    .font(.callout.monospaced()).frame(maxWidth: .infinity, alignment: .leading).padding(8).textSelection(.enabled)
            }
            Text("This sample shows the shape of the hook configuration. It does not modify any file or confer trust.")
                .font(.callout).foregroundStyle(.secondary)
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
        }.padding(28).frame(width: 620)
    }
}
