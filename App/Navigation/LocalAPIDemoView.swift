import SwiftUI
import TraceRookCore

/// A prepared client screen. Connection stays unavailable until the backend
/// branch and service-owned transport are integrated and tested together.
struct LocalAPIDemoView: View {
    @ViewState private var scenario: LocalAPIDemoScenario = .credentialTransfer
    @ViewState private var requestID = UUID()
    @ViewState private var previewDeviceID = UUID()
    @ViewState private var sessionID = UUID()
    private var request: LocalAPIDemoRequest {
        LocalAPIDemoRequest(scenario: scenario, deviceID: previewDeviceID, requestID: requestID, sessionPseudonym: sessionID)
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
                DetailField(name: "Connection", value: "Not connected · backend integration pending")
                DetailField(name: "Claude analysis", value: "Unavailable · fixture responses only")
                DetailField(name: "Usage & billing", value: "No inference tokens or charges")
                Text("The offline Cloud Demo remains available. This separate API demonstration will send only the sample below to a server running on this Mac.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Surface("Preview a sample request") {
                Picker("Synthetic scenario", selection: $scenario) {
                    ForEach(LocalAPIDemoScenario.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Text("No request has been sent. Preview identifiers are random placeholders; enrollment will supply the mock device identifier.")
                    .font(.caption).foregroundStyle(.secondary)
                ScrollView([.horizontal, .vertical]) {
                    Text(request.previewJSON).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                }.frame(height: 260).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
                HStack {
                    Label("Only predefined samples", systemImage: "lock.shield").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Connect local mock") {}.disabled(true).buttonStyle(.bordered)
                }
                Text("Connection becomes available after the backend branch is integrated and its contract is verified. The desktop UI will reach the API through the authenticated background service.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
