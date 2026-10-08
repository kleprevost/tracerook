import SwiftUI
import TraceRookContracts

struct IntegrationsView: View {
    @Environment(AppEnvironment.self) private var environment
    @ViewState<AgentProvider?> private var selectedPreview: AgentProvider?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeading(title: "Connect with confidence", subtitle: "Installation, host trust and verified execution are separate checks.")
                Surface {
                    Label("Live integration installation is not available in this build", systemImage: "wrench.and.screwdriver").font(.headline)
                    Text("No agent configuration or Login Item has been changed. The preview below illustrates the planned consent flow with sample paths.").font(.callout).foregroundStyle(.secondary)
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
                        Text("Planned supported events").font(.subheadline.bold())
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
                Text("A future installer will back up files, preserve unrelated hooks, detect concurrent changes, and atomically replace only TraceRook-owned entries.").font(.caption).foregroundStyle(.secondary)
            }.padding(28)
        }
        .sheet(item: $selectedPreview) { provider in IntegrationPreview(provider: provider) }
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
                Text("Preserve existing configuration\n+ TraceRook-owned command hook\n+ PreToolUse matcher: *\n+ timeout: 75 seconds\n+ Session/prompt/post-tool lifecycle hooks")
                    .font(.callout.monospaced()).frame(maxWidth: .infinity, alignment: .leading).padding(8).textSelection(.enabled)
            }
            Text("Real installation will show an exact diff and permission-preserving backup before consent. This sample cannot install hooks or confer trust.")
                .font(.callout).foregroundStyle(.secondary)
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
        }.padding(28).frame(width: 620)
    }
}
