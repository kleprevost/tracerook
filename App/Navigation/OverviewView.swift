import SwiftUI
import TraceRookContracts
import TraceRookCore

struct OverviewView: View {
    @Environment(AppEnvironment.self) private var environment
    private var visibleSessions: [SessionRecord] {
        environment.model.sessions.filter { environment.model.showingDemo || !environment.model.isSimulatedSession($0.id) }
    }
    private var visibleIncidents: [IncidentRecord] {
        environment.model.incidents.filter { environment.model.showingDemo || !environment.model.isSimulatedSession($0.sessionID) }
    }
    private var realPendingCount: Int {
        environment.model.approvals.filter { $0.origin == .live && $0.isPending(at: .now) && !environment.model.isSimulatedSession($0.binding.sessionID) }.count
    }
    private var providerStatus: String {
        if environment.model.showingDemo { return "Sample findings only; no Demo analysis requests" }
        guard environment.agent.connected else { return "Background analysis state unavailable" }
        if environment.agent.cloud.analysisEnabledLocally { return "Cloud selected for host analysis; see validated receipts" }
        if environment.model.mode == .anthropicBYOK { return "Direct API keys aren't supported; choose TraceRook Cloud" }
        return "Cloud analysis paused in the service"
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top) {
                    PageHeading(title: "A clear view of your agents", subtitle: environment.model.showingDemo ? "Explore how TraceRook explains risk and puts review in your hands." : "Connect local agent hooks to see observed actions and verified coverage.")
                    if environment.model.showingDemo {
                        Button { environment.simulate() } label: { Label("Simulate review", systemImage: "play.circle") }
                            .buttonStyle(.borderedProminent).controlSize(.large)
                    } else {
                        Button("Set up TraceRook") { environment.onboardingPresented = true }.buttonStyle(.borderedProminent)
                    }
                }
                coverageBanner
                HStack(spacing: 14) {
                    MetricCard(title: "Verified integrations", value: "0 / 2", caption: "Actual local coverage", symbol: "link")
                    MetricCard(title: environment.model.showingDemo ? "Sample sessions" : "Observed sessions", value: "\(environment.model.showingDemo ? environment.model.sessions.count : environment.model.observedHostSessionCount)", caption: environment.model.showingDemo ? "Bundled fixtures" : "Actual host callbacks only", symbol: "terminal")
                    MetricCard(title: environment.model.showingDemo ? "Sample findings" : "Observed findings", value: "\(visibleIncidents.count)", caption: environment.model.showingDemo ? "Synthetic risk scenarios" : (visibleIncidents.isEmpty ? "No observed findings" : "Retained host findings"), symbol: "exclamationmark.shield")
                    MetricCard(title: "Pending reviews", value: "\(environment.model.showingDemo ? environment.model.pendingCount : realPendingCount)", caption: environment.model.showingDemo ? "Simulation only" : (realPendingCount == 0 ? "No waiting hook calls" : "Exact-action reviews awaiting a decision"), symbol: "hand.raised")
                }
                HStack(alignment: .top, spacing: 20) {
                    Surface("Actual integration coverage") {
                        IntegrationSummary(provider: .claudeCode)
                        Divider()
                        IntegrationSummary(provider: .codex)
                        Button("View integrations") { environment.model.destination = .integrations }.buttonStyle(.link)
                    }
                    Surface("Analysis provider") {
                        HStack {
                            Image(systemName: environment.model.mode == .traceRookCloudDemo ? "cloud" : "cpu").font(.title2).foregroundStyle(RookTheme.accent)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(environment.model.mode.title).font(.headline)
                                Text(providerStatus).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Text("Local rules decide inside each connected hook. Integration coverage shows each agent's current status.").font(.callout).foregroundStyle(.secondary)
                        Button("Provider & privacy settings") { environment.settingsSection = "AI Provider"; environment.model.destination = .settings }.buttonStyle(.link)
                    }
                }
                if environment.model.showingDemo || !visibleSessions.isEmpty || !visibleIncidents.isEmpty {
                    Surface(environment.model.showingDemo ? "Sample agent activity" : "Observed agent activity") {
                        ForEach(visibleSessions) { session in
                            Button { environment.model.goToSession(session.id) } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "terminal").foregroundStyle(RookTheme.accent).frame(width: 28)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(session.project).font(.headline)
                                        Text("\(session.provider.title) · \(session.taskAnchor)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer(); SeverityBadge(severity: session.risk); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                                }.contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            if session.id != visibleSessions.last?.id { Divider() }
                        }
                    }
                    Surface(environment.model.showingDemo ? "Recent sample findings" : "Recent observed findings") {
                        ForEach(visibleIncidents.prefix(3)) { incident in
                            Button { environment.model.goToIncident(incident.id) } label: { IncidentRow(incident: incident) }.buttonStyle(.plain)
                            if incident.id != visibleIncidents.last?.id { Divider() }
                        }
                    }
                } else {
                    Surface {
                        EmptyActivity(title: "No real activity observed", description: "Enable the background service in Integrations. Host protection requires separately installed and verified hooks.", symbol: "terminal")
                        if environment.model.liveSnapshot?.simulatedSessionIDs.isEmpty == false {
                            Button("Inspect simulated service ingestion") { environment.model.destination = .sessions }.buttonStyle(.link)
                        }
                    }
                }
                Text("TraceRook watches supported local hook paths. Hosted tools, skipped callbacks and nested processes may be outside coverage.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(28).frame(maxWidth: 1400)
        }
    }
    private var coverageBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: environment.model.showingDemo ? "sparkles" : "exclamationmark.circle").font(.title3)
            VStack(alignment: .leading, spacing: 5) {
                Text(environment.model.showingDemo ? "Cloud Demo uses sample data" : "Protection has not been verified").font(.headline)
                Text(environment.model.showingDemo ? "Account, usage, findings and review actions are simulated locally. Background analysis state is shown separately in provider settings." : (visibleSessions.isEmpty ? "No actual host callbacks appear in this snapshot. A configuration file alone never establishes protected coverage." : "Actual host callbacks have been observed. Exact host versions and tool paths still require coverage verification; observed activity alone does not establish protection."))
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }.padding(17).background(RookTheme.amber.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }
}
struct MetricCard: View {
    let title: String; let value: String; let caption: String; let symbol: String
    var body: some View {
        Surface {
            HStack { Text(title).font(.caption).foregroundStyle(.secondary); Spacer(); Image(systemName: symbol).foregroundStyle(.secondary) }
            Text(value).font(.system(size: 30, weight: .semibold, design: .rounded)).monospacedDigit()
            Text(caption).font(.caption).foregroundStyle(.secondary)
        }.accessibilityElement(children: .combine)
    }
}
struct IntegrationSummary: View {
    let provider: AgentProvider
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text(provider.title).font(.headline)
                Text("Last verified hook: Never").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(); StatusBadge(text: "Not integrated", symbol: "circle.dashed")
        }
    }
}
