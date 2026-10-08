import SwiftUI
import TraceRookCore

struct CloudAlphaView: View {
    @Environment(AppEnvironment.self) private var environment
    @ViewState<String> private var invitation = ""
    @ViewState<Bool> private var consent = false
    @ViewState<Bool> private var deleteConfirmation = false
    var body: some View {
        let cloud = environment.agent.cloud
        Surface("TraceRook Cloud · Invited alpha") {
            DetailField(name: "Endpoint", value: "api.tracerook.dev · HTTPS")
            DetailField(name: "Reasoning engine", value: "Anthropic Claude Haiku 5.5")
            DetailField(name: "Enrollment", value: cloud.connected ? "Device enrolled" : "Not enrolled")
            DetailField(name: "Cloud analysis", value: cloud.capabilities?.analysisEnabled == true ? "Enabled by service operator" : "Unavailable or disabled")
            DetailField(name: "Validated Claude response", value: cloud.realAnalysisValidatedAt ?? "No real analysis validated this session")
            Text("Cloud connectivity does not establish agent coverage. Claude Code and Codex callbacks must be installed and verified separately.").font(.caption).foregroundStyle(.secondary)
            if cloud.failure == .credentialStorage {
                Text("Enrollment is disabled while credential storage is being fixed. No Keychain access or remote enrollment will run in this build.").font(.callout).foregroundStyle(.orange)
            }
            if cloud.busy { ProgressView("Contacting TraceRook Cloud…") }
            if let failure = cloud.failure {
                Text("Cloud request failed: \(failure.rawValue). No new protection was verified. If disconnect or deletion failed, server-side revocation or deletion is not confirmed.").font(.caption).foregroundStyle(.orange)
            }
            if !cloud.connected {
                SecureField("Invitation code", text: $invitation).textFieldStyle(.roundedBorder)
                Text("TraceRook processes coarse task and action categories plus local signal codes, then sends them to Anthropic. Raw commands, code, paths, file contents and transcripts are excluded. Analysis receipts: 30 days; account and device metadata until account deletion; usage aggregates: 90 days; temporary verdict cache: up to 10 minutes. Anthropic retention follows its API terms. Questions: kyle@tracerook.dev.").font(.callout).foregroundStyle(.secondary)
                Toggle("I consent to this remote analysis (privacy policy version 2)", isOn: $consent)
                Button("Enroll this Mac") {
                    let code = invitation; invitation = ""
                    Task { await environment.agent.cloudCommand(.connect, invitation: code, consent: CloudConsent()) }
                }.buttonStyle(.borderedProminent).disabled(!consent || invitation.isEmpty || cloud.busy || !environment.agent.connected || cloud.failure == .credentialStorage)
            } else {
                if let usage = cloud.usage {
                    DetailField(name: "UTC day", value: usage.dateUTC)
                    DetailField(name: "Analyzed actions today", value: usage.evaluationsToday.formatted())
                    DetailField(name: "Actual tokens", value: "\(usage.inputTokens.formatted()) input · \(usage.outputTokens.formatted()) output")
                    DetailField(name: "Unresolved reservations", value: "\(usage.reservedInputTokens.formatted()) input · \(usage.reservedOutputTokens.formatted()) output")
                }
                Text(cloud.usage?.limits.evaluationsPerDay == nil && cloud.usage?.limits.inputTokensPerDay == nil && cloud.usage?.limits.outputTokensPerDay == nil ? "Usage reports actual activity. No customer inference quota is configured. Request and concurrency limits protect service availability." : "The operator has configured usage limits. Refresh capabilities and usage for the current account settings.").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Refresh connection and usage") { Task { await environment.agent.cloudCommand(.refresh) } }.disabled(cloud.busy)
                    Button("Rotate device credential") { Task { await environment.agent.cloudCommand(.rotate) } }.disabled(cloud.busy)
                    Button("Disconnect") { Task { await environment.agent.cloudCommand(.disconnect) } }
                }.buttonStyle(.bordered)
                Button("Delete cloud account data…", role: .destructive) { deleteConfirmation = true }
            }
        }.confirmationDialog("Delete this alpha account and revoke all its devices?", isPresented: $deleteConfirmation) {
            Button("Delete cloud account data", role: .destructive) { Task { await environment.agent.cloudCommand(.delete) } }
        } message: { Text("This removes account metadata and revokes all enrolled devices. Anonymous company cost totals remain. If the server is unavailable, deletion cannot be confirmed.") }
    }
}
