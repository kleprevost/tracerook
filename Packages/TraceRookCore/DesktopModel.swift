import CryptoKit
import Foundation
import Observation
import TraceRookContracts

public enum DashboardDestination: String, CaseIterable, Identifiable, Sendable {
    case overview, sessions, incidents, approvals, integrations, settings
    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
    public var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .sessions: "terminal"
        case .incidents: "exclamationmark.shield"
        case .approvals: "hand.raised"
        case .integrations: "point.3.connected.trianglepath.dotted"
        case .settings: "slider.horizontal.3"
        }
    }
}

/// Phase 1 has no live-event transport. Its real-activity collections stay empty.
@MainActor @Observable
public final class DesktopModel {
    public var destination: DashboardDestination = .overview
    public var showingDemo = false
    public var mode: AnalysisMode = .localRulesOnly
    public var selectedSessionID: UUID?
    public var selectedIncidentID: UUID?
    public private(set) var demoSessions: [SessionRecord] = []
    public private(set) var demoIncidents: [IncidentRecord] = []
    public private(set) var demoApprovals: [ApprovalRecord] = []
    public private(set) var message: String?
    public private(set) var pauseUntil: Date?
    public private(set) var liveSnapshot: ServiceSnapshot?
    public private(set) var serviceConnected = false
    public var sessions: [SessionRecord] { showingDemo ? demoSessions : liveSnapshot?.sessions ?? [] }
    public var incidents: [IncidentRecord] { showingDemo ? demoIncidents : liveSnapshot?.incidents ?? [] }
    public var approvals: [ApprovalRecord] { showingDemo ? demoApprovals : liveSnapshot?.approvals ?? [] }
    public var observedHostSessionCount: Int { liveSnapshot?.sessions.filter { !isSimulatedSession($0.id) }.count ?? 0 }
    public func isSimulatedSession(_ id: UUID) -> Bool { liveSnapshot?.simulatedSessionIDs.contains(id) ?? false }
    public var liveCoverage: CoverageStatus { pauseUntil == nil ? .notIntegrated : .paused }
    public var pendingCount: Int { approvals.filter { $0.isPending(at: .now) }.count }
    public init() {}
    public func apply(_ snapshot: ServiceSnapshot) throws {
        try snapshot.validate(); liveSnapshot = snapshot; serviceConnected = true
    }
    public func disconnectService() { serviceConnected = false; liveSnapshot = nil }
    public func loadDemo(sessions: [SessionRecord], incidents: [IncidentRecord]) throws {
        guard sessions.allSatisfy({ $0.origin == .demo && $0.coverage == .demo }),
              incidents.allSatisfy({ $0.origin == .demo }) else { throw TraceRookError.notDemoData }
        demoSessions = sessions; demoIncidents = incidents; demoApprovals = []
    }
    public func exploreDemo() { showingDemo = true; mode = .traceRookCloudDemo; destination = .overview }
    public func showRealActivity() { showingDemo = false; selectedSessionID = nil; selectedIncidentID = nil }
    public func selectMode(_ newMode: AnalysisMode) {
        mode = newMode
        if newMode != .traceRookCloudDemo { showRealActivity() }
    }
    @discardableResult
    public func simulateReview(now: Date = .now) throws -> ApprovalRecord {
        guard showingDemo, let incident = demoIncidents.first(where: { $0.severity == .high }),
              let session = demoSessions.first(where: { $0.id == incident.sessionID }) else { throw TraceRookError.notDemoData }
        tick(now: now)
        guard demoApprovals.filter({ $0.state == .pending }).count < 3 else { throw TraceRookError.quotaExhausted }
        let eventID = UUID(), callID = "demo-\(UUID().uuidString)"
        let digest = SHA256.hash(data: Data("\(session.id):\(eventID):\(callID)".utf8)).map { String(format: "%02x", $0) }.joined()
        let binding = ApprovalBinding(provider: session.provider, sessionID: session.id, turnID: "demo-turn",
            eventID: eventID, toolCallID: callID, fingerprint: digest)
        let approval = ApprovalRecord(incidentID: incident.id, origin: .demo, binding: binding,
            requestedAt: now, expiresAt: now.addingTimeInterval(45))
        demoApprovals.insert(approval, at: 0)
        message = "Simulation created. No tool call is running."
        return approval
    }
    public func respond(id: UUID, binding: ApprovalBinding, allow: Bool, now: Date = .now) throws {
        guard let index = demoApprovals.firstIndex(where: { $0.id == id }), demoApprovals[index].origin == .demo else { throw TraceRookError.staleApproval }
        tick(now: now)
        let resolved = try ApprovalTransition.respond(demoApprovals[index], binding: binding, allow: allow, now: now)
        demoApprovals[index] = resolved
        message = allow ? "Demo action allowed once. No real tool was authorized." : "Demo action blocked. No real tool was running."
    }
    public func tick(now: Date = .now) {
        demoApprovals = demoApprovals.map { ApprovalTransition.expire($0, now: now) }
        if let pauseUntil, now >= pauseUntil { self.pauseUntil = nil }
    }
    public func markReviewed(_ id: UUID) {
        guard let index = demoIncidents.firstIndex(where: { $0.id == id }) else { return }
        demoIncidents[index].reviewed = true; message = "Sample finding marked reviewed."
    }
    public func reportFalsePositive(_ id: UUID) {
        guard let index = demoIncidents.firstIndex(where: { $0.id == id }) else { return }
        demoIncidents[index].falsePositive = true; message = "Feedback saved for this demo only. No report was sent."
    }
    public func pause(now: Date = .now) { pauseUntil = now.addingTimeInterval(900) }
    public func resume() { pauseUntil = nil }
    public func clearDemoHistory() { demoApprovals = []; demoIncidents = []; message = "Sample history cleared for this run." }
    public func dismissMessage() { message = nil }
    public func goToSession(_ id: UUID) { selectedSessionID = id; destination = .sessions }
    public func goToIncident(_ id: UUID) { selectedIncidentID = id; destination = .incidents }
}
