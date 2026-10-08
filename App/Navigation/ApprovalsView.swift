import AppKit
import SwiftUI
import TraceRookCore

struct ApprovalsView: View {
    @Environment(AppEnvironment.self) private var environment
    @ViewState<UUID?> private var selectedID: UUID?
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                PageHeading(title: "Review queue", subtitle: "One decision, bound to one exact proposed action.")
                if environment.model.showingDemo {
                    Button("Simulate review") { environment.simulate() }.buttonStyle(.borderedProminent)
                }
            }.padding(24)
            if environment.model.approvals.isEmpty {
                EmptyActivity(title: "No pending actions", description: environment.model.showingDemo ? "Simulate a review to try the 45-second countdown, Block and Allow once controls. No real command executes." : "Real reviews appear only while a supported hook is waiting. Explore Demo to try the flow.", symbol: "hand.raised")
            } else {
                HStack(spacing: 0) {
                    List(selection: $selectedID) {
                        Section("Pending · Simulation") {
                            ForEach(environment.model.approvals.filter { $0.state == .pending }) { approval in ApprovalQueueRow(approval: approval).tag(approval.id) }
                        }
                        Section("Resolved · Simulation") {
                            ForEach(environment.model.approvals.filter { $0.state != .pending }) { approval in ApprovalQueueRow(approval: approval).tag(approval.id) }
                        }
                    }.listStyle(.sidebar).frame(width: 285)
                    Divider()
                    if let selectedID { ApprovalDetail(approvalID: selectedID, inPanel: false) }
                    else { EmptyActivity(title: "Select a review", description: "Inspect its evidence and exact action digest.", symbol: "hand.raised") }
                }.onAppear { selectedID = environment.model.approvals.first?.id }
                .onChange(of: environment.model.approvals.count) { _, _ in selectedID = environment.model.approvals.first?.id }
            }
        }
    }
}
struct ApprovalQueueRow: View {
    let approval: ApprovalRecord
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Unexpected package publication").font(.headline)
            Text(approval.binding.provider.title).font(.caption).foregroundStyle(.secondary)
            if approval.state == .pending {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text("\(max(0, Int(ceil(approval.expiresAt.timeIntervalSince(context.date))))) seconds remaining").font(.caption.monospacedDigit()).foregroundStyle(.orange)
                }
            } else { StatusBadge(text: approval.state.title, color: .secondary) }
        }.padding(.vertical, 8)
    }
}
struct ApprovalDetail: View {
    @Environment(AppEnvironment.self) private var environment
    let approvalID: UUID
    var inPanel: Bool
    var body: some View {
        if let approval = environment.model.demoApprovals.first(where: { $0.id == approvalID }),
           let incident = environment.model.demoIncidents.first(where: { $0.id == approval.incidentID }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack { DemoBadge(); Spacer(); SeverityBadge(severity: incident.severity) }
                    PageHeading(title: "Review proposed action", subtitle: "\(approval.binding.provider.title) · \(environment.model.demoSessions.first(where: { $0.id == approval.binding.sessionID })?.project ?? "Context unavailable")")
                    Text(incident.summary).font(.title3.weight(.medium))
                    Surface("Evidence and task relevance") {
                        Text(incident.rationale).font(.callout)
                        ForEach(incident.evidence, id: \.self) { Label($0, systemImage: "magnifyingglass").font(.callout) }
                        DetailField(name: "User task", value: environment.model.demoSessions.first(where: { $0.id == approval.binding.sessionID })?.taskAnchor ?? "Task unknown")
                    }
                    Surface("Exact action binding") {
                        DetailField(name: "Review ID", value: approval.id.uuidString)
                        DetailField(name: "Action digest", value: approval.binding.fingerprint)
                        DetailField(name: "Deadline", value: approval.expiresAt.formatted(date: .omitted, time: .standard))
                    }
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let pending = approval.isPending(at: context.date)
                        VStack(alignment: .leading, spacing: 14) {
                            Text(pending ? "\(max(0, Int(ceil(approval.expiresAt.timeIntervalSince(context.date))))) seconds to review · expiry denies" : "No longer pending · \(approval.state == .pending ? "Expired" : approval.state.title)")
                                .font(.headline.monospacedDigit()).foregroundStyle(pending ? .orange : .secondary)
                            HStack {
                                Button("Block", role: .destructive) { environment.respond(approvalID, allow: false) }.buttonStyle(.bordered)
                                Button("Allow once") { environment.respond(approvalID, allow: true) }.buttonStyle(.borderedProminent)
                                if !inPanel { Button("Open review panel") { environment.openReview(approvalID) }.buttonStyle(.bordered) }
                            }.disabled(!pending)
                        }
                    }
                    Text("Simulation only. Allow once passes TraceRook for this exact call; the agent's built-in permissions still apply. No real hook call is running here.").font(.caption).foregroundStyle(.secondary)
                }.padding(24)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else { EmptyActivity(title: "Review unavailable", description: "This simulated request is no longer present. No action can be authorized.", symbol: "hand.raised.slash") }
    }
}
@MainActor
final class ReviewPanelController {
    private var panel: NSPanel?
    func show(approvalID: UUID, environment: AppEnvironment) {
        let panel = panel ?? NSPanel(contentRect: NSRect(x: 0, y: 0, width: 680, height: 730),
                                     styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        panel.title = "TraceRook · Demo action review"
        panel.isReleasedWhenClosed = false; panel.hidesOnDeactivate = false
        panel.minSize = NSSize(width: 580, height: 580)
        panel.contentView = NSHostingView(rootView: ApprovalDetail(approvalID: approvalID, inPanel: true)
            .environment(environment).tint(RookTheme.accent).preferredColorScheme(environment.colorScheme)
            .task {
                while !Task.isCancelled {
                    environment.model.tick()
                    do { try await Task.sleep(for: .seconds(1)) } catch { return }
                }
            })
        panel.center(); panel.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        self.panel = panel
    }
}
