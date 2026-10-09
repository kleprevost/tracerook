import SwiftUI
import TraceRookContracts

struct OnboardingView: View {
    @Environment(AppEnvironment.self) private var environment
    @ViewState<Int> private var step = 0
    @ViewState<AnalysisMode> private var choice = AnalysisMode.traceRookCloud
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
                    Text("TraceRook inspects your coding agent's tool calls, explains risky behavior and pauses high-risk calls for your review.").font(.body)
                    Text("TraceRook reviews the tool calls Claude Code sends through its hook. Commands you run yourself stay in your hands.").foregroundStyle(.secondary)
                    StatusBadge(text: "Private beta · Claude Code supported", color: RookTheme.accent)
                case 1:
                    Text("Compatibility on this Mac").font(.title2.bold())
                    DetailField(name: "Operating system", value: ProcessInfo.processInfo.operatingSystemVersionString)
                    DetailField(name: "Architecture", value: "Apple Silicon · arm64 build")
                    DetailField(name: "Signature", value: environment.signatureDescription)
                    DetailField(name: "Helper", value: "Bundled helper · see Integrations for service status")
                    Text("Next, start the background service and connect Claude Code.").foregroundStyle(.secondary)
                case 2:
                    Text("Choose an analysis experience").font(.title2.bold())
                    Picker("Analysis experience", selection: $choice) {
                        Text("TraceRook Cloud · Claude analysis with your beta access code").tag(AnalysisMode.traceRookCloud)
                        Text("Explore with sample data · Demo").tag(AnalysisMode.traceRookCloudDemo)
                        Text("Local rules only · hooks required").tag(AnalysisMode.localRulesOnly)
                    }.pickerStyle(.radioGroup)
                    Text(choice == .traceRookCloudDemo ? "Explore account, usage and simulated findings locally. Demo never enrolls a real account or makes a purchase." : choice == .traceRookCloud ? "Connect to api.tracerook.dev with your beta access code. TraceRook Cloud runs Anthropic Claude analysis using our API key. Start the background service and approve privacy consent in Settings → AI Provider." : "Local rules only. Cloud analysis stays paused in the service.").foregroundStyle(.secondary)
                case 3:
                    Text("Keep context small and redacted").font(.title2.bold())
                    Text("With your consent, TraceRook Cloud receives a task category, an action category and local signal codes. Commands, paths, code and transcripts stay on your Mac.")
                    Text("Demo mode sends no data. Source excerpts default off. No broad disk access, transcript scraping or anonymous analytics is used.").foregroundStyle(.secondary)
                    Button("Preview example payload") { payloadPreview = true }.buttonStyle(.bordered)
                case 4:
                    Text("Connect your local agents").font(.title2.bold())
                    IntegrationSummary(provider: .claudeCode)
                    IntegrationSummary(provider: .codex)
                    Text("Add the TraceRook hook to Claude Code using the installation guide at tracerook.dev/docs/beta. Codex support is coming soon. This setup flow doesn't change any agent settings.").foregroundStyle(.secondary)
                case 5:
                    Text("Review without watching every command").font(.title2.bold())
                    Text("Pending reviews wait in the menu bar and the Approvals queue, each with a 45-second deadline.")
                    DetailField(name: "Notifications", value: environment.notifications.status)
                    Button("Request notifications") { Task { await environment.notifications.requestPermission() } }.buttonStyle(.bordered)
                    Text("Start the background service from Integrations. It asks for your consent before registering.").foregroundStyle(.secondary)
                case 6:
                    Text("Verify your connection").font(.title2.bold())
                    Text("Start a Claude Code session after adding the hook. Its tool calls appear in Sessions with each decision.")
                    Text("Integration status reflects recorded host callbacks, never a configuration file alone.").foregroundStyle(.secondary)
                default:
                    Text(choice == .traceRookCloudDemo ? "Your demo is ready" : "The dashboard is ready").font(.title.bold())
                    Text(choice == .traceRookCloud ? "Next, connect your beta access code in Settings → AI Provider. Start the background service from Integrations if it is not connected. Analysis starts only after you connect and approve consent." : choice == .traceRookCloudDemo ? "Try session timelines, evidence details and an exact-action review using sample data. No command is executed." : "Local rules run through your configured agent hooks. Cloud analysis is paused.")
                    if choice == .traceRookCloudDemo { DemoBadge() }
                    Text("Connect Claude Code from Integrations to protect real sessions.").foregroundStyle(.secondary)
                }
            }.frame(maxWidth: .infinity, minHeight: 285, alignment: .topLeading)
            Divider()
            HStack {
                Button(step == 0 ? "View dashboard" : "Back") {
                    if step == 0 { Task { await environment.finishOnboarding(exploreDemo: false) } } else { step -= 1 }
                }
                Spacer()
                if step == 7 {
                    Button(choice == .traceRookCloud ? "Connect TraceRook Cloud" : choice == .traceRookCloudDemo ? "Explore Demo" : "Open dashboard") {
                        Task {
                            if choice == .traceRookCloudDemo {
                                await environment.finishOnboarding(exploreDemo: true)
                            } else {
                                guard await environment.selectAnalysisMode(choice) else { return }
                                await environment.finishOnboarding(exploreDemo: false)
                                if choice == .traceRookCloud {
                                    environment.model.destination = .settings
                                    environment.settingsSection = "AI Provider"
                                }
                            }
                        }
                    }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                } else { Button("Continue") { step += 1 }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction) }
            }
        }.padding(32).frame(width: 710)
            .sheet(isPresented: $payloadPreview) { PrivacyPreviewView() }
    }
}
