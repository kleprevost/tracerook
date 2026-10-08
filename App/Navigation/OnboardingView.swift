import SwiftUI
import TraceRookContracts

struct OnboardingView: View {
    @Environment(AppEnvironment.self) private var environment
    @ViewState<Int> private var step = 0
    @ViewState<AnalysisMode> private var choice = AnalysisMode.traceRookCloudDemo
    @ViewState<Bool> private var payloadPreview = false
    private let steps = ["Welcome", "This Mac", "Analysis", "Privacy", "Integrations", "Notifications", "Verification", "Ready"]
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 12) { RookMark(size: 42); VStack(alignment: .leading) { Text("Welcome to TraceRook").font(.title2.bold()); Text("Understand risk. Review with context.").foregroundStyle(.secondary) }; Spacer(); Text("\(step + 1) / 8").font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
            ProgressView(value: Double(step + 1), total: 8).tint(RookTheme.accent)
            HStack(spacing: 6) { ForEach(steps.indices, id: \.self) { index in Text(steps[index]).font(.caption2).foregroundStyle(index == step ? RookTheme.accent : .secondary); if index < 7 { Image(systemName: "chevron.right").font(.system(size: 7)).foregroundStyle(.tertiary) } } }
            VStack(alignment: .leading, spacing: 18) {
                switch step {
                case 0:
                    Text("A second look before supported actions execute").font(.title.bold())
                    Text("TraceRook is designed to inspect local coding-agent tool calls, explain risky behavior and pause supported calls for review.").font(.body)
                    Text("Hooks are guardrails, not universal endpoint enforcement. A skipped or timed-out callback may permit execution.").foregroundStyle(.secondary)
                    StatusBadge(text: "Native UI milestone · live protection pending", color: .orange)
                case 1:
                    Text("Compatibility on this Mac").font(.title2.bold())
                    DetailField(name: "Operating system", value: ProcessInfo.processInfo.operatingSystemVersionString)
                    DetailField(name: "Architecture", value: "Apple Silicon · arm64 build")
                    DetailField(name: "Signature", value: environment.signatureDescription)
                    DetailField(name: "Helper", value: "Bundled helper · see Integrations for service status")
                    Text("This beta uses ad-hoc signatures and is not notarized. Service installation and host callback coverage must be verified separately.").foregroundStyle(.secondary)
                case 2:
                    Text("Choose an analysis experience").font(.title2.bold())
                    Picker("Analysis experience", selection: $choice) {
                        Text("TraceRook Cloud · Preview / Demo").tag(AnalysisMode.traceRookCloudDemo)
                        Text("Local rules only · hooks required").tag(AnalysisMode.localRulesOnly)
                        Text("Use my Anthropic API key · Coming soon").tag(AnalysisMode.anthropicBYOK)
                    }.pickerStyle(.radioGroup)
                    Text(choice == .traceRookCloudDemo ? "Explore account, usage and simulated findings locally. Demo never enrolls a real account or makes a purchase." : choice == .anthropicBYOK ? "BYOK is not operational in this milestone. No key is collected or stored." : "Selecting offline mode first pauses Cloud analysis in the service. Local coverage requires installed, verified hooks.").foregroundStyle(.secondary)
                case 3:
                    Text("Keep context small and redacted").font(.title2.bold())
                    Text("Working BYOK will send selected redacted context directly to Anthropic, with explicit consent. Redaction cannot guarantee removal of every secret.")
                    Text("Cloud Demo sends no data. Source excerpts default off. No broad disk access, transcript scraping or anonymous analytics is used.").foregroundStyle(.secondary)
                    Button("Preview example payload") { payloadPreview = true }.buttonStyle(.bordered)
                case 4:
                    Text("Connect your local agents").font(.title2.bold())
                    IntegrationSummary(provider: .claudeCode)
                    IntegrationSummary(provider: .codex)
                    Text("Live installation is not available in this development build. You will inspect an exact diff and backups, then explicitly choose integrations. Nothing has been installed by this setup flow.").foregroundStyle(.secondary)
                case 5:
                    Text("Review without watching every command").font(.title2.bold())
                    Text("Notifications are the entry point for review. The queue and bounded deadline still work when macOS suppresses delivery.")
                    DetailField(name: "Notifications", value: environment.notifications.status)
                    Button("Request notifications") { Task { await environment.notifications.requestPermission() } }.buttonStyle(.bordered)
                    Text("Login-agent registration will be offered with consent when the live service is available.").foregroundStyle(.secondary)
                case 6:
                    Text("Installed is not verified").font(.title2.bold())
                    Text("Codex requires you to review and trust the hook definition with /hooks. TraceRook will wait for an actual host callback and harmless pre-tool smoke test before claiming coverage.")
                    Text("A config check or successful fixture test alone never means Protected. This milestone reports both integrations as Not integrated.").foregroundStyle(.secondary)
                default:
                    Text(choice == .traceRookCloudDemo ? "Your safe preview is ready" : "The dashboard is ready").font(.title.bold())
                    Text("Try session timelines, evidence details and an exact-action review. Simulated approvals expire after 45 seconds, and no dangerous command is executed.")
                    if choice == .traceRookCloudDemo { DemoBadge() }
                    Text("Real protection remains unavailable until the live integration phases pass their tests.").foregroundStyle(.secondary)
                }
            }.frame(maxWidth: .infinity, minHeight: 285, alignment: .topLeading)
            Divider()
            HStack {
                Button(step == 0 ? "View dashboard" : "Back") {
                    if step == 0 { Task { await environment.finishOnboarding(exploreDemo: false) } } else { step -= 1 }
                }
                Spacer()
                if step == 7 {
                    Button(choice == .traceRookCloudDemo ? "Explore Demo" : "Open dashboard") {
                        Task {
                            if choice == .traceRookCloudDemo {
                                await environment.finishOnboarding(exploreDemo: true)
                            } else {
                                guard await environment.selectAnalysisMode(choice) else { return }
                                await environment.finishOnboarding(exploreDemo: false)
                            }
                        }
                    }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                } else { Button("Continue") { step += 1 }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction) }
            }
        }.padding(32).frame(width: 710)
            .sheet(isPresented: $payloadPreview) { PrivacyPreviewView() }
    }
}
