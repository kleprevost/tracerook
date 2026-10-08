import SwiftUI
import TraceRookContracts
import TraceRookCore

struct SessionsView: View {
    @Environment(AppEnvironment.self) private var environment
    @ViewState<String> private var search = ""
    @ViewState<String> private var sort = "Last seen"
    private var filtered: [SessionRecord] {
        let sessions = environment.model.sessions.filter { search.isEmpty || ($0.project + $0.taskAnchor + $0.provider.title).localizedCaseInsensitiveContains(search) }
        return sessions.sorted {
            switch sort {
            case "Agent": $0.provider.title < $1.provider.title
            case "Project": $0.project < $1.project
            case "Risk": $0.risk.score > $1.risk.score
            case "Coverage": $0.coverage.title < $1.coverage.title
            default: $0.lastSeenAt > $1.lastSeenAt
            }
        }
    }
    var body: some View {
        if environment.model.sessions.isEmpty {
            EmptyActivity(title: "No observed sessions", description: "Only actual hook callbacks can create real session records. Explore Cloud Demo to browse sample timelines.", symbol: "terminal")
        } else {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Sessions").font(.title2.bold())
                    TextField("Search sanitized context", text: $search).textFieldStyle(.roundedBorder)
                    Picker("Sort", selection: $sort) { ForEach(["Last seen", "Agent", "Project", "Risk", "Coverage"], id: \.self) { Text($0) } }
                    List(selection: Binding(get: { environment.model.selectedSessionID }, set: { environment.model.selectedSessionID = $0 })) {
                        ForEach(filtered) { session in
                            VStack(alignment: .leading, spacing: 7) {
                                HStack { Text(session.project).font(.headline); Spacer(); SeverityBadge(severity: session.risk) }
                                Text(session.provider.title).font(.caption).foregroundStyle(.secondary)
                                Text(session.taskAnchor).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                Text(session.origin == .demo ? "Demo · sample session" : environment.model.isSimulatedSession(session.id) ? "Simulated ingestion · no host callback" : session.activity(at: .now)).font(.caption2).foregroundStyle(RookTheme.amber)
                            }.padding(.vertical, 8).tag(session.id)
                        }
                    }.listStyle(.plain)
                }.padding(20).frame(width: 290)
                Divider()
                if let session = environment.model.sessions.first(where: { $0.id == environment.model.selectedSessionID }) {
                    SessionDetail(session: session)
                } else { EmptyActivity(title: "Select a session", description: "Inspect its task context and sanitized timeline.", symbol: "terminal") }
            }.onAppear {
                if environment.model.selectedSessionID == nil { environment.model.selectedSessionID = filtered.first?.id }
            }
        }
    }
}
struct SessionDetail: View {
    @Environment(AppEnvironment.self) private var environment
    let session: SessionRecord
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    PageHeading(title: session.project, subtitle: session.provider.title)
                    if session.origin == .demo { DemoBadge() }
                    else if environment.model.isSimulatedSession(session.id) { StatusBadge(text: "SIMULATED INGESTION", color: RookTheme.amber) }
                }
                Surface("Session context") {
                    DetailField(name: "Coverage", value: session.origin == .demo ? "Demo data · no live protection" : environment.model.isSimulatedSession(session.id) ? "Simulated ingestion · no host protection proved" : session.coverage.title)
                    DetailField(name: "Task anchor", value: session.taskAnchor.isEmpty ? "Task unknown · context unavailable" : session.taskAnchor)
                    DetailField(name: "First observed", value: session.firstSeenAt.formatted(date: .abbreviated, time: .shortened))
                    DetailField(name: "Last observed", value: session.lastSeenAt.formatted(date: .abbreviated, time: .shortened))
                    DetailField(name: "Session ID", value: session.id.uuidString)
                }
                HStack { Text("Sanitized event timeline").font(.headline); Spacer(); SeverityBadge(severity: session.risk) }
                ForEach(session.events.sorted(by: { $0.at < $1.at })) { event in
                    Surface {
                        HStack {
                            Image(systemName: event.execution == .blockedBeforeExecution ? "shield.slash" : "terminal").foregroundStyle(RookTheme.color(event.severity))
                            Text(event.tool).font(.headline)
                            Spacer(); Text(event.at, style: .time).font(.caption).foregroundStyle(.secondary)
                        }
                        Text(event.summary).font(.callout)
                        StatusBadge(text: event.execution.title, color: RookTheme.color(event.severity))
                    }
                }
                Text("Timelines contain minimized, sanitized context. Allowing past TraceRook does not establish host execution.").font(.caption).foregroundStyle(.secondary)
            }.padding(24)
        }.frame(maxWidth: .infinity)
    }
}
