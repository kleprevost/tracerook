import Charts
import SwiftUI
import TraceRookContracts

struct SettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @ViewState<String> private var cloudTab = "Account"
    @ViewState<Bool> private var clearConfirmation = false
    var body: some View {
        @Bindable var env = environment
        VStack(alignment: .leading, spacing: 20) {
            PageHeading(title: "Settings", subtitle: "Protection, analysis and privacy should be understandable.")
            Picker("Settings section", selection: Binding(get: { environment.settingsSection }, set: { section in
                if section == "Local API Demo" {
                    Task { if await environment.selectAnalysisMode(.localRulesOnly) { environment.settingsSection = section } }
                } else { environment.settingsSection = section }
            })) {
                ForEach(["General", "Protection", "AI Provider", "Local API Demo", "Privacy", "About"], id: \.self) { Text($0) }
            }.pickerStyle(.segmented)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch environment.settingsSection {
                    case "General": general
                    case "Protection": protection
                    case "AI Provider": provider
                    case "Local API Demo": LocalAPIDemoView()
                    case "Privacy": privacy
                    default: about
                    }
                }.padding(.bottom, 24)
            }
        }.padding(28)
        .confirmationDialog("Clear all local history?", isPresented: $clearConfirmation) {
            Button("Clear history and abort pending reviews", role: .destructive) {
                Task { _ = try? await environment.agent.command(.clearHistory); await environment.agent.refresh() }
            }
        } message: { Text("This permanently removes live history from this Mac. Pending reviews are denied first. Keys and integrations are separate.") }
    }
    private var general: some View {
        @Bindable var env = environment
        return Group {
            Surface("Appearance") {
                Picker("Appearance", selection: $env.appearance) { ForEach(["System", "Light", "Dark"], id: \.self) { Text($0) } }.pickerStyle(.segmented)
                Text("Follows macOS appearance by default. All status labels include text as well as color.").font(.caption).foregroundStyle(.secondary)
            }
            Surface("Notifications") {
                DetailField(name: "Permission", value: environment.notifications.status)
                HStack {
                    Button("Request notification permission") { Task { await environment.notifications.requestPermission() } }.buttonStyle(.bordered)
                    Button("Refresh status") { Task { await environment.notifications.refreshStatus() } }.buttonStyle(.link)
                }
                Text("Focus and notification settings can suppress delivery. Pending actions remain in the review queue and expire safely.").font(.caption).foregroundStyle(.secondary)
            }
            Surface("Login and retention") {
                DetailField(name: "Background service", value: environment.agent.status)
                DetailField(name: "History retention", value: "Service events: 14 days; incidents and approvals: 30 days")
                Text("The service owns a private SQLite history store. Offline Cloud Demo samples remain in memory and separate from service history.").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Reset Demo") { environment.resetDemo() }
                    Button("Clear service history…", role: .destructive) { clearConfirmation = true }.disabled(!environment.agent.connected)
                }.buttonStyle(.bordered)
            }
        }
    }
    private var protection: some View {
        Group {
            Surface("Current coverage") {
                StatusBadge(text: environment.claudeIntegration.title(in: environment.model), symbol: "circle.dashed")
                Text("Supported callbacks can reach local policy and exact-action human review through the service. Coverage remains unverified until the configured host proves its pre-execution path.").foregroundStyle(.secondary)
                Text("Cloud analysis is controlled in AI Provider. This screen does not pause local hook enforcement.").font(.caption).foregroundStyle(.secondary)
            }
            Surface("Local policy defaults") {
                DetailField(name: "Critical", value: "Deterministic catastrophic evidence → deny")
                DetailField(name: "High ≥ 70", value: "Hold for exact-action human review")
                DetailField(name: "Medium ≥ 40", value: "Allow with warning")
                DetailField(name: "Low", value: "Allow and record a minimal summary")
                DetailField(name: "Review deadline", value: "45 seconds; expired high-risk requests deny")
                Text("Models cannot silently cause a critical hard block or erase local catastrophic evidence. Thresholds are routing aids, not proof of malicious intent.").font(.caption).foregroundStyle(.secondary)
            }
            Surface("Outages and exceptions") {
                Text("Local deterministic policy remains authoritative when cloud analysis is unavailable. Human review and host deadlines are bounded; scoped exceptions are not available.").font(.callout).foregroundStyle(.secondary)
                Text("A callback that never ran cannot be made fail-closed by a preference.").font(.callout.weight(.medium))
            }
        }
    }
    private var provider: some View {
        Group {
            Surface("Analysis mode") {
                Picker("Provider", selection: Binding(get: { environment.model.mode }, set: { mode in
                    Task { await environment.selectAnalysisMode(mode) }
                })) {
                    ForEach([AnalysisMode.traceRookCloud, .localRulesOnly, .traceRookCloudDemo], id: \.self) { Text($0.title).tag($0) }
                }.pickerStyle(.radioGroup).disabled(environment.analysisModeBusy)
                if let error = environment.analysisModeError { Text(error).font(.callout).foregroundStyle(.orange) }
                if environment.model.mode == .anthropicBYOK {
                    StatusBadge(text: "Not supported", color: .orange)
                    Text("Direct Anthropic API keys aren't supported. Choose TraceRook Cloud for Claude analysis. No key is requested, stored or sent.").font(.callout).foregroundStyle(.secondary)
                    Button("What leaves my Mac?") { environment.privacyPreviewPresented = true }.buttonStyle(.bordered)
                } else if environment.model.mode == .traceRookCloud {
                    Text("Connect to api.tracerook.dev using your beta access code. TraceRook Cloud provides real Claude analysis; you do not need an Anthropic API key.").font(.callout).foregroundStyle(.secondary)
                } else if environment.model.mode == .traceRookCloudDemo {
                    Text("Cloud AI analysis unavailable for real activity. The account, usage and plans below are synthetic and never enroll a real account or create billing.").font(.callout).foregroundStyle(.secondary)
                    Button("Explore Demo") { Task { await environment.exploreDemo() } }.buttonStyle(.borderedProminent)
                } else {
                    Text("Cloud analysis is paused in the service. Local policy remains separate; host coverage requires installed, verified hooks.").font(.callout).foregroundStyle(.secondary)
                }
            }
            if environment.model.mode == .traceRookCloud { CloudAlphaView() }
            if environment.model.mode == .traceRookCloudDemo {
                Surface {
                    HStack { Text("TraceRook Cloud").font(.title2.bold()); Spacer(); DemoBadge() }
                    Picker("Cloud screen", selection: $cloudTab) { ForEach(["Account", "Usage", "Plans"], id: \.self) { Text($0) } }.pickerStyle(.segmented)
                    if let snapshot = environment.snapshot {
                        switch cloudTab {
                        case "Account":
                            DetailField(name: "Sample account", value: snapshot.account.email)
                            DetailField(name: "Plan concept", value: snapshot.account.plan)
                            DetailField(name: "Enrollment", value: "Simulation · no account created")
                            Text("No login, subscription, credit balance or purchase occurs in Demo.").font(.caption).foregroundStyle(.secondary)
                        case "Usage":
                            HStack {
                                MetricCard(title: "Sample analyzed actions", value: "\(snapshot.usage.analyzedActions)", caption: snapshot.usage.period, symbol: "chart.bar")
                                MetricCard(title: "Sample tokens", value: snapshot.usage.tokensUsed.formatted(), caption: "Simulated usage · no cost incurred", symbol: "number")
                            }
                            Chart(Array(snapshot.usage.dailyActions.enumerated()), id: \.offset) { item in
                                BarMark(x: .value("October day", item.offset + 1), y: .value("Sample actions", item.element))
                                    .foregroundStyle(RookTheme.accent.gradient).cornerRadius(5)
                            }.chartXAxisLabel("October · sample days").chartYAxisLabel("Sample actions").frame(height: 180)
                                .accessibilityLabel("Sample daily Cloud usage").accessibilityValue(snapshot.usage.dailyActions.map(String.init).joined(separator: ", "))
                            ProgressView(value: Double(snapshot.usage.analyzedActions), total: Double(snapshot.usage.quota))
                            Text("\(snapshot.usage.analyzedActions) / \(snapshot.usage.quota) simulated actions · no live quota or metering").font(.caption).foregroundStyle(.secondary)
                        default:
                            ForEach(snapshot.plans) { plan in
                                VStack(alignment: .leading, spacing: 9) {
                                    HStack { Text(plan.name).font(.headline); Spacer(); StatusBadge(text: plan.monthlyPriceLabel, color: RookTheme.amber) }
                                    Text(plan.description).font(.callout).foregroundStyle(.secondary)
                                    ForEach(plan.features, id: \.self) { Label($0, systemImage: "checkmark").font(.caption) }
                                }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }
                }
            }
        }
    }
    private var privacy: some View {
        Group {
            Surface("Minimum necessary data") {
                Label("Only categories leave your Mac", systemImage: "lock.shield").font(.headline)
                Text("With your consent, TraceRook Cloud receives a task category, an action category and local signal codes. Raw commands, paths, code and transcripts stay on this Mac. Demo mode sends nothing.")
                    .font(.callout).foregroundStyle(.secondary)
                DetailField(name: "Source excerpts", value: "Off by default · selected bounded lines only")
                DetailField(name: "Logs", value: "Status codes and generated identifiers only")
                DetailField(name: "Transcripts", value: "No complete transcript archival or background scraping")
                Button("What leaves my Mac?") { environment.privacyPreviewPresented = true }.buttonStyle(.bordered)
            }
            Surface("Separate deletion controls") {
                HStack {
                    Button("Delete All Local History") { clearConfirmation = true }.disabled(!environment.agent.connected)
                    Button("Delete API Key") {}.disabled(true)
                    Button("Uninstall Integrations") {}.disabled(true)
                }.buttonStyle(.bordered)
                Text("The service owns the private history store. Clearing it aborts pending reviews first. Key and integration deletion become available when configured.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private var about: some View {
        Surface("TraceRook") {
            HStack { RookMark(size: 52); VStack(alignment: .leading) { Text("TraceRook \(TraceRookVersion.app)").font(.title2.bold()); Text("Native macOS · Swift 6 · Apple Silicon").foregroundStyle(.secondary) } }
            DetailField(name: "App signature", value: environment.signatureDescription)
            DetailField(name: "Helper service", value: environment.agent.status)
            DetailField(name: "Adapter schema", value: "\(TraceRookVersion.adapter) · host compatibility not verified")
            DetailField(name: "Fixture status", value: environment.fixtureStatus)
            Text("Non-notarized local build. The service validates exact peer signatures; host coverage requires separately verified hooks. Ad-hoc signatures do not prove publisher identity.").font(.callout).foregroundStyle(.secondary)
            Text("TraceRook is a guardrail for supported hooks, not system-wide endpoint protection. Same-user processes can bypass or disable hooks.").font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct PrivacyPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeading(title: "What leaves my Mac?", subtitle: "A synthetic example of the minimum BYOK context")
            StatusBadge(text: "EXAMPLE · NOT SENT", color: RookTheme.amber, symbol: "lock")
            Text("BYOK will send selected redacted context directly to Anthropic. Redaction cannot guarantee removal of every secret. Cloud Demo makes no network requests.").font(.callout)
            ScrollView {
                Text("""
                {
                  "schema_version": 1,
                  "untrusted": {
                    "task_anchor": "Build an accessible settings screen",
                    "current_action": "Outbound upload referencing [SENSITIVE_PATH]",
                    "recent_events": ["Read project guidelines"],
                    "privacy_redactions": 2,
                    "policy_matches": ["TR-CRED-EXFIL"]
                  }
                }
                """).font(.callout.monospaced()).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(16)
            }.frame(height: 230).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
            Text("Full transcripts, raw API keys and default source excerpts are excluded. Model output is advisory and cannot grant permissions.").font(.caption).foregroundStyle(.secondary)
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
        }.padding(28).frame(width: 650)
    }
}
