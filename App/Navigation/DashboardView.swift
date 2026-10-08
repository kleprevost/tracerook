import SwiftUI
import TraceRookCore

struct DashboardView: View {
    @Environment(AppEnvironment.self) private var environment
    var body: some View {
        @Bindable var env = environment
        HSplitView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 11) {
                    RookMark(size: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("TraceRook").font(.system(size: 19, weight: .semibold, design: .rounded))
                        Text("Agent guardrails").font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(20).padding(.top, 8)
                VStack(alignment: .leading, spacing: 4) {
                    Text("WORKSPACE").font(.caption2.weight(.semibold)).foregroundStyle(.secondary).padding(.horizontal, 12).padding(.bottom, 8)
                    ForEach(DashboardDestination.allCases) { destination in
                        Button { environment.model.destination = destination } label: {
                            HStack {
                                Image(systemName: destination.symbol).frame(width: 22)
                                Text(destination.title)
                                Spacer()
                                if destination == .approvals && environment.model.pendingCount > 0 {
                                    Text("\(environment.model.pendingCount)").font(.caption.bold()).foregroundStyle(.orange)
                                }
                            }.font(.callout.weight(environment.model.destination == destination ? .semibold : .regular))
                                .foregroundStyle(environment.model.destination == destination ? RookTheme.accent : .primary)
                                .padding(.horizontal, 12).padding(.vertical, 11).contentShape(Rectangle())
                                .background(environment.model.destination == destination ? RookTheme.accent.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain).accessibilityLabel(destination.title)
                        .accessibilityAddTraits(environment.model.destination == destination ? .isSelected : [])
                    }
                }.padding(.horizontal, 12).padding(.top, 18)
                Spacer()
                VStack(alignment: .leading, spacing: 9) {
                    StatusBadge(text: "Not integrated", color: .secondary, symbol: "circle.dashed")
                    Text("Hook coverage must be verified before protection is claimed.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Button("Setup guide") { environment.onboardingPresented = true }.buttonStyle(.link)
                }.padding(20)
            }.frame(minWidth: 205, idealWidth: 225, maxWidth: 270).frame(maxHeight: .infinity)
            VStack(spacing: 0) {
                HStack {
                    if environment.model.showingDemo {
                        DemoBadge()
                        Text("A safe, interactive preview. No commands execute.").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Real activity") { environment.model.showRealActivity() }.buttonStyle(.bordered)
                    } else {
                        StatusBadge(text: environment.model.liveCoverage.title, symbol: "circle.dashed")
                        Spacer()
                        Button("Explore Demo") { Task { await environment.exploreDemo() } }.buttonStyle(.bordered)
                    }
                }.padding(.horizontal, 28).padding(.vertical, 14).background(.bar)
                Divider()
                Group {
                    switch environment.model.destination {
                    case .overview: OverviewView()
                    case .sessions: SessionsView()
                    case .incidents: IncidentsView()
                    case .approvals: ApprovalsView()
                    case .integrations: IntegrationsView()
                    case .settings: SettingsView()
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }.background(RookTheme.background)
        }
        .sheet(isPresented: $env.onboardingPresented) { OnboardingView().environment(environment) }
        .sheet(isPresented: $env.privacyPreviewPresented) { PrivacyPreviewView() }
        .overlay(alignment: .bottom) {
            if let message = environment.analysisModeError ?? environment.model.message {
                HStack {
                    Image(systemName: "info.circle")
                    Text(message).font(.callout)
                    if environment.analysisModeError == nil {
                        Button { environment.model.dismissMessage() } label: { Image(systemName: "xmark") }
                            .buttonStyle(.plain).accessibilityLabel("Dismiss message")
                    }
                }.padding(14).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .shadow(radius: 8, y: 3).padding(20)
            }
        }
        .task {
            await environment.notifications.refreshStatus()
            while !Task.isCancelled {
                environment.model.tick()
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
        }
    }
}
