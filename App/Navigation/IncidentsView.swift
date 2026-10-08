import SwiftUI
import TraceRookContracts
import TraceRookCore

struct IncidentsView: View {
    @Environment(AppEnvironment.self) private var environment
    @ViewState<String> private var severity = "All severities"
    @ViewState<String> private var status = "All states"
    @ViewState<String> private var provider = "All agents"
    @ViewState<String> private var sessionFilter = "All sessions"
    var filtered: [IncidentRecord] {
        environment.model.incidents.filter { incident in
            let session = environment.model.sessions.first { $0.id == incident.sessionID }
            return (severity == "All severities" || incident.severity.rawValue.capitalized == severity)
                && (status == "All states" || (status == "Reviewed" ? incident.reviewed : !incident.reviewed))
                && (provider == "All agents" || session?.provider.title == provider)
                && (sessionFilter == "All sessions" || session?.project == sessionFilter)
        }.sorted { $0.createdAt > $1.createdAt }
    }
    var body: some View {
        if environment.model.incidents.isEmpty {
            EmptyActivity(title: "No recorded findings", description: "Real findings require observed events. Cloud Demo findings are segregated from real activity.", symbol: "exclamationmark.shield")
        } else {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Incidents").font(.title2.bold())
                    Picker("Severity", selection: $severity) {
                        Text("All severities").tag("All severities")
                        ForEach(Severity.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0.rawValue.capitalized) }
                    }
                    Picker("State", selection: $status) { ForEach(["All states", "Unreviewed", "Reviewed"], id: \.self) { Text($0) } }
                    Picker("Agent", selection: $provider) { ForEach(["All agents", "Claude Code", "Codex"], id: \.self) { Text($0) } }
                    Picker("Session", selection: $sessionFilter) {
                        Text("All sessions").tag("All sessions")
                        ForEach(environment.model.sessions) { Text($0.project).tag($0.project) }
                    }
                    List(selection: Binding(get: { environment.model.selectedIncidentID }, set: { environment.model.selectedIncidentID = $0 })) {
                        ForEach(filtered) { incident in
                            VStack(alignment: .leading, spacing: 8) {
                                SeverityBadge(severity: incident.severity)
                                Text(incident.title).font(.headline)
                                Text(incident.reviewed ? "Reviewed · Demo" : "Unreviewed · Demo").font(.caption).foregroundStyle(.secondary)
                            }.padding(.vertical, 7).tag(incident.id)
                        }
                    }.listStyle(.plain)
                }.padding(20).frame(width: 290)
                Divider()
                if let incident = filtered.first(where: { $0.id == environment.model.selectedIncidentID }) {
                    IncidentDetail(incident: incident)
                } else { EmptyActivity(title: "Select a finding", description: "Review the evidence, action and uncertainty.", symbol: "exclamationmark.shield") }
            }.onAppear { if environment.model.selectedIncidentID == nil { environment.model.selectedIncidentID = filtered.first?.id } }
        }
    }
}
struct IncidentRow: View {
    let incident: IncidentRecord
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.shield").foregroundStyle(RookTheme.color(incident.severity)).font(.title3).frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(incident.title).font(.headline)
                Text(incident.execution.title).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(); SeverityBadge(severity: incident.severity)
        }.contentShape(Rectangle())
    }
}
struct IncidentDetail: View {
    @Environment(AppEnvironment.self) private var environment
    let incident: IncidentRecord
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                DemoBadge()
                PageHeading(title: incident.title, subtitle: incident.createdAt.formatted(date: .abbreviated, time: .shortened))
                HStack { SeverityBadge(severity: incident.severity); StatusBadge(text: incident.execution.title, color: RookTheme.color(incident.severity)) }
                Surface("What was attempted") {
                    Text(incident.summary).textSelection(.enabled)
                    DetailField(name: "User task", value: environment.model.sessions.first(where: { $0.id == incident.sessionID })?.taskAnchor ?? "Context unavailable")
                    DetailField(name: "Finding type", value: incident.categories.map { $0 == .unsafeAction ? "Unsafe action" : "Agent behavior" }.joined(separator: ", "))
                    DetailField(name: "Analysis", value: incident.providerMode == .traceRookCloudDemo ? "Cloud Demo fixture · no live model" : "Local deterministic policy · sample result")
                }
                Surface("Why it raised concern") {
                    Text(incident.rationale).font(.callout).textSelection(.enabled)
                    ForEach(incident.evidence, id: \.self) { evidence in Label(evidence, systemImage: "magnifyingglass").font(.callout) }
                    Text(incident.ruleIDs.joined(separator: " · ")).font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                Surface("Limits and uncertainty") {
                    ForEach(incident.limitations, id: \.self) { Text("• " + $0).font(.callout).foregroundStyle(.secondary) }
                    Text("Redaction notice: sample evidence is sanitized. Original tool arguments are not stored.").font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Button("Go to session") { environment.model.goToSession(incident.sessionID) }
                    Button(incident.reviewed ? "Reviewed" : "Mark reviewed") { environment.model.markReviewed(incident.id) }.disabled(incident.reviewed)
                    Button(incident.falsePositive ? "Feedback saved" : "Report false positive") { environment.model.reportFalsePositive(incident.id) }.disabled(incident.falsePositive)
                }.buttonStyle(.bordered)
                if incident.severity == .critical {
                    Text("Critical local blocks have no quick allow or in-flight exception.").font(.caption).foregroundStyle(.secondary)
                }
            }.padding(24)
        }.frame(maxWidth: .infinity)
    }
}
