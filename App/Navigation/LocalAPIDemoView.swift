import SwiftUI
import TraceRookCore

struct LocalAPIDemoView: View {
    @Environment(AppEnvironment.self) private var environment
    @ViewState private var scenario: LocalAPIDemoScenario = .credentialTransfer
    @ViewState private var requestID = UUID()
    @ViewState private var previewDeviceID = UUID()
    @ViewState private var sessionID = UUID()
    @ViewState private var consent = false
    @ViewState private var deleteConfirmation = false
    private var request: LocalAPIDemoRequest {
        LocalAPIDemoRequest(scenario: scenario, deviceID: environment.agent.localAPI.deviceID ?? previewDeviceID,
            requestID: requestID, sessionPseudonym: sessionID)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Surface {
                HStack {
                    Text("Local API Demo").font(.title2.bold())
                    Spacer()
                    StatusBadge(text: "SYNTHETIC · NO CLAUDE CALL", color: RookTheme.amber, symbol: "testtube.2")
                }
                Text("A development demonstration of the client and backend API. It uses fixed sample actions and never changes protection or grants host permissions.")
                    .font(.callout).foregroundStyle(.secondary)
                DetailField(name: "Local service", value: environment.agent.status)
                DetailField(name: "Mock device", value: environment.agent.localAPI.connected ? "Enrolled · credential held only in service memory" : "Not enrolled")
                DetailField(name: "Endpoint", value: "127.0.0.1:8787 · this Mac only")
                DetailField(name: "Claude analysis", value: "Unavailable · fixture responses only")
                DetailField(name: "Fixture usage", value: "\(environment.agent.localAPI.fixtureEvaluations) / 30 sample evaluations today · zero inference tokens or charges")
                Text("Start the local server using backend/LOCAL_MOCK.md. Enable the local service in Integrations after reviewing its configuration. The offline Cloud Demo remains available.")
                    .font(.caption).foregroundStyle(.secondary)
                if let failure = environment.agent.localAPI.failure {
                    Label(failure.title, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange)
                }
                if environment.agent.localAPIBusy { ProgressView("Waiting for local API…").controlSize(.small) }
                if environment.agent.localAPI.connected {
                    HStack {
                        Button("Refresh fixture usage") { Task { await environment.agent.localAPICommand(.usage) } }
                            .disabled(environment.agent.localAPIBusy)
                        Button("Rotate mock credential") { Task { await environment.agent.localAPICommand(.rotate) } }
                            .disabled(environment.agent.localAPIBusy)
                        Button("Disconnect") { Task { await environment.agent.localAPICommand(.disconnect) } }
                        Button("Delete mock metadata…", role: .destructive) { deleteConfirmation = true }
                            .disabled(environment.agent.localAPIBusy)
                    }.buttonStyle(.bordered)
                } else {
                    Toggle("Use this local API with synthetic examples only", isOn: $consent)
                    Button("Connect local mock") { Task { await environment.agent.localAPICommand(.connect) } }
                        .buttonStyle(.borderedProminent)
                        .disabled(!consent || !environment.agent.connected || environment.agent.localAPIBusy || environment.model.liveSnapshot?.securityMode != .developer)
                }
            }
            Surface("Preview a sample request") {
                Picker("Synthetic scenario", selection: $scenario) {
                    ForEach(LocalAPIDemoScenario.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Text(environment.agent.localAPI.connected ? "This is the exact synthetic JSON sent on Run sample. No host input or private file is included." : "This preview has not been sent. Enrollment supplies a mock device identifier before analysis.")
                    .font(.caption).foregroundStyle(.secondary)
                ScrollView([.horizontal, .vertical]) {
                    Text(request.previewJSON).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                }.frame(height: 260).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
                HStack {
                    Label("Only predefined samples", systemImage: "lock.shield").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Run sample") {
                        let approved = request
                        Task {
                            await environment.agent.localAPICommand(.analyze, request: approved)
                            if environment.agent.localAPI.lastResponse != nil { await environment.agent.localAPICommand(.usage) }
                            requestID = UUID()
                        }
                    }.disabled(!environment.agent.localAPI.connected || environment.agent.localAPIBusy).buttonStyle(.borderedProminent)
                }
                Text("Requests go through the authenticated background service. Fixture recommendations do not create live reviews, authorize tools, or change coverage.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let result = environment.agent.localAPI.lastResponse {
                Surface("Synthetic API result") {
                    HStack { SeverityBadge(severity: result.verdict.severity); StatusBadge(text: "FIXTURE · ZERO CLAUDE TOKENS", color: RookTheme.amber) }
                    Text(result.verdict.rationale).font(.callout).textSelection(.enabled)
                    ForEach(result.verdict.evidence, id: \.self) { Text("• " + $0).font(.caption) }
                    DetailField(name: "Recommendation", value: result.verdict.recommendedAction.rawValue + " · advisory sample only")
                    DetailField(name: "Provenance", value: "fixture / local_mock / synthetic-v1")
                    DetailField(name: "Elapsed time", value: "\(result.serverElapsedMS) ms · local fixture evaluation")
                    DetailField(name: "Analysis ID", value: result.analysisID)
                    Text(result.verdict.limitations.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .task { if environment.agent.connected { await environment.agent.localAPICommand(.status) } }
        .onChange(of: scenario) { requestID = UUID() }
        .confirmationDialog("Delete this device’s mock metadata?", isPresented: $deleteConfirmation) {
            Button("Delete mock data and revoke token", role: .destructive) { Task { await environment.agent.localAPICommand(.delete) } }
        } message: { Text("Only this ephemeral mock device is affected. Real history, keys, integrations, and offline Demo data remain separate.") }
    }
}
