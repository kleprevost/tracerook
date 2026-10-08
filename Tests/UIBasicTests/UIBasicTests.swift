import Foundation
import Testing
import TraceRookContracts
import TraceRookCore
import TraceRookFixtures

@Test func demoHasContentForEachDashboardDestination() throws {
    let demo = try FixtureLoader.loadDemo()
    #expect(demo.sessions.count == 3)
    #expect(demo.incidents.count == 3)
    #expect(demo.plans.count == 2)
    #expect(demo.usage.dailyActions.count == 8)
}

@Test @MainActor func demoNavigationNeverPopulatesRealCollections() throws {
    let fixture = try FixtureLoader.loadDemo(), model = DesktopModel()
    try model.loadDemo(sessions: fixture.sessions, incidents: fixture.incidents)
    #expect(model.sessions.isEmpty && model.incidents.isEmpty && model.approvals.isEmpty)
    model.exploreDemo()
    #expect(model.sessions.count == 3 && model.liveCoverage == .notIntegrated)
    let approval = try model.simulateReview()
    #expect(approval.origin == .demo && model.pendingCount == 1)
    model.showRealActivity()
    #expect(model.sessions.isEmpty && model.incidents.isEmpty && model.approvals.isEmpty)
    #expect(model.pendingCount == 0)
    #expect(throws: TraceRookError.notDemoData) { try model.simulateReview() }
}

@Test @MainActor func demoReviewIsExactBoundOneTimeAndExpires() throws {
    let fixture = try FixtureLoader.loadDemo(), model = DesktopModel()
    try model.loadDemo(sessions: fixture.sessions, incidents: fixture.incidents); model.exploreDemo()
    let now = Date(), a = try model.simulateReview(now: now), b = try model.simulateReview(now: now)
    #expect(a.binding.fingerprint != b.binding.fingerprint)
    #expect(throws: TraceRookError.wrongBinding) { try model.respond(id: a.id, binding: b.binding, allow: true, now: now) }
    try model.respond(id: a.id, binding: a.binding, allow: true, now: now)
    #expect(throws: TraceRookError.staleApproval) { try model.respond(id: a.id, binding: a.binding, allow: true, now: now) }
    model.tick(now: now.addingTimeInterval(45))
    #expect(model.demoApprovals.first(where: { $0.id == b.id })?.state == .expired)
    #expect(throws: TraceRookError.staleApproval) { try model.respond(id: b.id, binding: b.binding, allow: true, now: now.addingTimeInterval(46)) }
}

@Test @MainActor func pauseExpiresWithoutInventingProtection() {
    let now = Date(), model = DesktopModel()
    model.pause(now: now); #expect(model.liveCoverage == .paused)
    model.tick(now: now.addingTimeInterval(900)); #expect(model.liveCoverage == .notIntegrated)
}

@Test @MainActor func feedbackIsLocalAndDemoOnly() throws {
    let fixture = try FixtureLoader.loadDemo(), model = DesktopModel()
    try model.loadDemo(sessions: fixture.sessions, incidents: fixture.incidents)
    let id = fixture.incidents[0].id
    model.markReviewed(id); model.reportFalsePositive(id)
    #expect(model.demoIncidents[0].reviewed && model.demoIncidents[0].falsePositive)
    #expect(model.message?.contains("No report was sent") == true)
}
