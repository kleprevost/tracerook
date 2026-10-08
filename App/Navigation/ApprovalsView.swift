import AppKit
import SwiftUI
import TraceRookCore
import TraceRookContracts

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
                        Section(environment.model.showingDemo ? "Pending · Simulation" : "Pending · Live") {
                            ForEach(environment.model.approvals.filter { $0.state == .pending }) { approval in ApprovalQueueRow(approval: approval, title: environment.model.incidents.first(where: { $0.id == approval.incidentID })?.title ?? "Proposed action").tag(approval.id) }
                        }
                        Section(environment.model.showingDemo ? "Resolved · Simulation" : "Resolved · Live") {
                            ForEach(environment.model.approvals.filter { $0.state != .pending }) { approval in ApprovalQueueRow(approval: approval, title: environment.model.incidents.first(where: { $0.id == approval.incidentID })?.title ?? "Proposed action").tag(approval.id) }
                        }
                    }.listStyle(.sidebar).frame(width: 285)
                    Divider()
                    if let selectedID {
                        if environment.model.showingDemo { ApprovalDetail(approvalID: selectedID, inPanel: false) }
                        else { LiveApprovalDetail(approvalID: selectedID).id(selectedID) }
                    }
                    else { EmptyActivity(title: "Select a review", description: "Inspect its evidence and exact action digest.", symbol: "hand.raised") }
                }.onAppear { selectedID = environment.model.approvals.first?.id }
                .onChange(of: environment.model.approvals.map(\.id)) { _, ids in
                    if let selectedID, ids.contains(selectedID) { return }
                    selectedID = ids.first
                }
            }
        }
    }
}
struct ApprovalQueueRow: View {
    let approval: ApprovalRecord
    var title: String = "Unexpected package publication"
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
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


/// A live decision is built only from the current authenticated snapshot request.
struct LiveApprovalDetail: View {
    @Environment(AppEnvironment.self) private var environment
    let approvalID: UUID
    @ViewState private var submitting = false
    @ViewState private var resolutionMessage: String?

    private var approval: ApprovalRecord? {
        environment.model.liveSnapshot?.approvals.first { $0.id == approvalID && $0.origin == .live }
    }
    private func activeRequest(for approval: ApprovalRecord, at now: Date) -> ReviewRequest? {
        guard !environment.model.showingDemo, environment.agent.connected,
              !environment.model.isSimulatedSession(approval.binding.sessionID), approval.isPending(at: now),
              let request = environment.model.liveSnapshot?.reviewRequests.first(where: { $0.approvalID == approval.id }),
              request.origin == .live, request.binding == approval.binding,
              request.incidentID == approval.incidentID,
              request.expiresAtMS > Int64(now.timeIntervalSince1970 * 1000),
              abs(Double(request.expiresAtMS) / 1000 - approval.expiresAt.timeIntervalSince1970) < 0.001,
              (try? request.validate()) != nil else { return nil }
        return request
    }
    var body: some View {
        if let approval, let incident = environment.model.liveSnapshot?.incidents.first(where: {
            $0.id == approval.incidentID && $0.origin == .live && $0.sessionID == approval.binding.sessionID
        }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack { Text("Live action review").font(.caption.weight(.semibold)); Spacer(); SeverityBadge(severity: incident.severity) }
                    PageHeading(title: incident.title, subtitle: approval.binding.provider.title)
                    Text(incident.summary).font(.title3.weight(.medium))
                    Surface("Evidence and task relevance") {
                        Text(incident.rationale).font(.callout)
                        ForEach(incident.evidence, id: \.self) { Label($0, systemImage: "magnifyingglass").font(.callout) }
                        DetailField(name: "User task", value: environment.model.liveSnapshot?.sessions.first(where: { $0.id == approval.binding.sessionID })?.taskAnchor ?? "Task unknown")
                        ForEach(incident.limitations, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                    }
                    Surface("Exact action binding") {
                        DetailField(name: "Review ID", value: approval.id.uuidString)
                        DetailField(name: "Action digest", value: approval.binding.fingerprint)
                        DetailField(name: "Tool call", value: approval.binding.toolCallID)
                        DetailField(name: "Deadline", value: approval.expiresAt.formatted(date: .omitted, time: .standard))
                    }
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let pending = activeRequest(for: approval, at: context.date) != nil
                        VStack(alignment: .leading, spacing: 14) {
                            Text(pending ? "\(max(0, Int(ceil(approval.expiresAt.timeIntervalSince(context.date))))) seconds to review · expiry denies" : "No active review · \(approval.state == .pending ? "Expired or unavailable" : approval.state.title)")
                                .font(.headline.monospacedDigit()).foregroundStyle(pending ? .orange : .secondary)
                            HStack {
                                Button("Block", role: .destructive) { resolve(.block) }.buttonStyle(.bordered)
                                Button("Allow once") { resolve(.allowOnce) }.buttonStyle(.borderedProminent)
                            }.disabled(!pending || submitting)
                        }
                    }
                    if let resolutionMessage { Text(resolutionMessage).font(.callout).accessibilityLabel(resolutionMessage) }
                    Text("Allow once releases only TraceRook's gate for this exact invocation. The agent's native permissions still apply. It does not prove the action executed.").font(.caption).foregroundStyle(.secondary)
                }.padding(24)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            EmptyActivity(title: "Review unavailable", description: "This live request is no longer present. No action can be authorized.", symbol: "hand.raised.slash")
        }
    }
    private func resolve(_ choice: ReviewChoice) {
        guard !submitting, let approval, let request = activeRequest(for: approval, at: .now) else {
            resolutionMessage = "This review expired or is no longer available."
            return
        }
        submitting = true
        resolutionMessage = nil
        Task { @MainActor in
            defer { submitting = false }
            do {
                let resolution = ReviewResolution(requestID: request.requestID, approvalID: request.approvalID,
                    binding: request.binding, invocationNonce: request.invocationNonce, choice: choice)
                try resolution.validateBinding(to: request)
                let payload = try JSONValue.decodeBounded(WireCodec.encodePayload(resolution, maximumBytes: WireLimits.replyBytes))
                _ = try await environment.agent.command(.resolveReview, payload: payload)
                resolutionMessage = choice == .block ? "Block recorded for this invocation." : "Allow once recorded; native agent permissions still apply."
            } catch {
                resolutionMessage = "The service did not confirm this decision. Refresh the review; it may have expired."
            }
            await environment.agent.refresh()
        }
    }
}
