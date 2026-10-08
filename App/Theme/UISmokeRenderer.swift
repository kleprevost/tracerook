import AppKit
import Foundation
import SwiftUI
import TraceRookContracts
import TraceRookCore

/// Explicit development test entry point. Renders the actual native views, not HTML mockups.
@MainActor enum UISmokeRenderer {
    static func run(directory: URL) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var report: [String] = []
        for appearance in ["Light", "Dark"] {
            let environment = AppEnvironment(); environment.onboardingPresented = false
            environment.appearance = appearance; environment.model.exploreDemo()
            environment.notifications.status = "Denied · use the approval queue"
            guard !environment.fixtureError else { throw TraceRookError.fixtureInvalid }
            for destination in DashboardDestination.allCases {
                environment.model.destination = destination
                environment.model.selectedSessionID = environment.model.demoSessions.first?.id
                environment.model.selectedIncidentID = environment.model.demoIncidents.first?.id
                if destination == .settings { environment.settingsSection = "AI Provider" }
                let name = "\(appearance.lowercased())-\(destination.rawValue)-demo"
                try await render(AnyView(DashboardView().environment(environment).tint(RookTheme.accent).preferredColorScheme(environment.colorScheme)), name: name, directory: directory)
                report.append(name)
            }
            let approval = try environment.model.simulateReview()
            environment.model.dismissMessage()
            let activeName = "\(appearance.lowercased())-review-pending"
            try await render(AnyView(ApprovalDetail(approvalID: approval.id, inPanel: true).environment(environment).tint(RookTheme.accent).preferredColorScheme(environment.colorScheme)), name: activeName, directory: directory, width: 680, height: 780)
            environment.model.tick(now: approval.expiresAt)
            guard environment.model.demoApprovals.first?.state == .expired else { throw TraceRookError.staleApproval }
            let expiredName = "\(appearance.lowercased())-review-expired"
            try await render(AnyView(ApprovalDetail(approvalID: approval.id, inPanel: true).environment(environment).tint(RookTheme.accent).preferredColorScheme(environment.colorScheme)), name: expiredName, directory: directory, width: 680, height: 780)
            report += [activeName, expiredName]
            environment.model.showRealActivity(); environment.model.destination = .overview
            guard environment.model.sessions.isEmpty, environment.model.liveCoverage == .notIntegrated else { throw TraceRookError.notDemoData }
            let realName = "\(appearance.lowercased())-overview-real"
            try await render(AnyView(DashboardView().environment(environment).tint(RookTheme.accent).preferredColorScheme(environment.colorScheme)), name: realName, directory: directory)
            report.append(realName)
            environment.model.destination = .settings; environment.settingsSection = "General"
            let deniedName = "\(appearance.lowercased())-notifications-denied"
            try await render(AnyView(SettingsView().environment(environment).tint(RookTheme.accent).preferredColorScheme(environment.colorScheme)), name: deniedName, directory: directory)
            report.append(deniedName)
        }
        try report.joined(separator: "\n").write(to: directory.appendingPathComponent("rendered-cases.txt"), atomically: true, encoding: .utf8)
        print("Native UI smoke: \(report.count) light/dark cases rendered. No live hooks or remote analysis used.")
    }
    private static func render(_ root: AnyView, name: String, directory: URL, width: CGFloat = 1220, height: CGFloat = 830) async throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: name.hasPrefix("dark-") ? .darkAqua : .aqua)
        let view = NSHostingView(rootView: root.frame(width: width, height: height).background(RookTheme.background))
        window.contentView = view; window.makeKeyAndOrderFront(nil)
        window.setContentSize(NSSize(width: width, height: height))
        view.frame = NSRect(x: 0, y: 0, width: width, height: height)
        // Permit one native layout/display cycle; this is bounded test rendering, not a security deadline.
        try await Task.sleep(for: .milliseconds(150))
        view.layoutSubtreeIfNeeded(); window.displayIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw TraceRookError.malformedResponse }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]), png.count > 1000 else { throw TraceRookError.malformedResponse }
        try png.write(to: directory.appendingPathComponent(name + ".png"), options: .atomic)
        window.orderOut(nil)
    }
}
