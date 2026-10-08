import AppKit
import Foundation
import Observation
import Security
import TraceRookContracts
import TraceRookCore
import TraceRookFixtures

@MainActor @Observable
final class AppEnvironment {
    let model = DesktopModel()
    let notifications = NotificationController()
    let reviewPanel = ReviewPanelController()
    let agent: AgentConnection
    private(set) var snapshot: DemoSnapshot?
    private(set) var fixtureError = false
    var onboardingPresented = !UserDefaults.standard.bool(forKey: "onboardingCompleted")
    var privacyPreviewPresented = false
    private(set) var analysisModeBusy = false
    private(set) var analysisModeError: String?
    var appearance = "System"
    var settingsSection = "General"
    var fixtureStatus: String { fixtureError ? "Demo fixtures unavailable" : "Bundled demo fixtures validated" }
    init() {
        agent = AgentConnection(model: model)
        do {
            let demo = try FixtureLoader.loadDemo(); snapshot = demo
            try model.loadDemo(sessions: demo.sessions, incidents: demo.incidents)
        } catch { fixtureError = true }
        notifications.onReview = { [weak self] id in self?.openReview(id) }
        notifications.onBlock = { [weak self] id in self?.respond(id, allow: false) }
        if CommandLine.arguments.contains("--demo") && CommandLine.arguments.contains("--ui-smoke-test") { model.exploreDemo(); onboardingPresented = false }
        if CommandLine.arguments.contains("--appearance-dark") { appearance = "Dark" }
        if CommandLine.arguments.contains("--appearance-light") { appearance = "Light" }
        if CommandLine.arguments.contains("--local-api-demo") { onboardingPresented = false }
        if CommandLine.arguments.contains("--cloud-beta") {
            model.selectMode(.traceRookCloud); model.destination = .settings; settingsSection = "AI Provider"; onboardingPresented = false
        }
        if !CommandLine.arguments.contains("--ui-smoke-test") {
            agent.start()
            if let index = CommandLine.arguments.firstIndex(of: "--beta-cloud-probe"), CommandLine.arguments.indices.contains(index + 1) {
                let file = URL(fileURLWithPath: CommandLine.arguments[index + 1])
                let receipt = file.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("beta-cloud-probe.json")
                model.selectMode(.traceRookCloud); onboardingPresented = false
                Task { await BetaCloudProbe.run(agent: agent, credentialFile: file, receiptFile: receipt) }
            }
            if CommandLine.arguments.contains("--demo") { Task { await exploreDemo() } }
            if CommandLine.arguments.contains("--local-api-demo") {
                Task {
                    if await selectAnalysisMode(.localRulesOnly) {
                        model.destination = .settings; settingsSection = "Local API Demo"
                    }
                }
            }
        }
    }
    var colorScheme: SwiftUI.ColorScheme? { appearance == "Dark" ? .dark : appearance == "Light" ? .light : nil }
    func finishOnboarding(exploreDemo: Bool) async {
        if exploreDemo, !(await self.exploreDemo()) { return }
        UserDefaults.standard.set(true, forKey: "onboardingCompleted"); onboardingPresented = false
    }
    @discardableResult
    func selectAnalysisMode(_ mode: AnalysisMode) async -> Bool {
        guard !analysisModeBusy else { return false }
        analysisModeBusy = true; analysisModeError = nil
        defer { analysisModeBusy = false }
        do {
            // Opening Cloud settings is allowed while paused; enrollment is explicit.
            if mode != .traceRookCloud { try await agent.setAnalysisEnabled(false) }
            model.selectMode(mode)
            return true
        } catch {
            if mode == .traceRookCloudDemo && !agent.connected {
                model.selectMode(.traceRookCloudDemo)
                analysisModeError = "Demo sends no data. Background service is unavailable; its analysis state cannot be verified."
                return true
            }
            analysisModeError = "The service did not confirm this analysis change. The current mode remains selected; remote analysis may still be active."
            return false
        }
    }
    @discardableResult
    func exploreDemo() async -> Bool {
        guard await selectAnalysisMode(.traceRookCloudDemo) else { return false }
        model.exploreDemo()
        onboardingPresented = false
        return true
    }
    func dismissAnalysisModeError() { analysisModeError = nil }
    func resetDemo() {
        guard let snapshot else { return }
        try? model.loadDemo(sessions: snapshot.sessions, incidents: snapshot.incidents)
    }
    func simulate() {
        guard let approval = try? model.simulateReview() else { return }
        Task { await notifications.notifyDemoApproval(id: approval.id) }
    }
    func openReview(_ id: UUID) {
        model.tick()
        guard model.demoApprovals.contains(where: { $0.id == id }) else { return }
        Task {
            guard await exploreDemo() else { return }
            model.destination = .approvals
            reviewPanel.show(approvalID: id, environment: self)
        }
    }
    func respond(_ id: UUID, allow: Bool) {
        guard let approval = model.demoApprovals.first(where: { $0.id == id }) else { return }
        do { try model.respond(id: id, binding: approval.binding, allow: allow) }
        catch { model.tick() }
        notifications.remove(id: id)
    }
    var signatureDescription: String {
        guard let url = Bundle.main.bundleURL as CFURL?, url as URL != URL(fileURLWithPath: "/") else { return "Development build" }
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url, [], &code) == errSecSuccess, let code else { return "Signature unavailable" }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dictionary = info as? [String: Any] else { return "Signature unavailable" }
        return dictionary[kSecCodeInfoTeamIdentifier as String] == nil ? "Ad-hoc development signature" : "Signed · release validation pending"
    }
}

import SwiftUI
