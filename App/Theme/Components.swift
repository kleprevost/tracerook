import SwiftUI
import TraceRookContracts

// The SDK 27 @State macro requires a plugin absent from Command Line Tools.
// Use Apple's macOS 26-compatible State property wrapper explicitly.
typealias ViewState<Value> = SwiftUI.State<Value>

enum RookTheme {
    static let accent = Color(red: 0.16, green: 0.64, blue: 0.59)
    static let amber = Color(red: 0.85, green: 0.49, blue: 0.13)
    static let background = Color(nsColor: .windowBackgroundColor)
    static func color(_ severity: Severity) -> Color {
        switch severity { case .critical: .red; case .high: .orange; case .medium: amber; case .low: accent; case .unknown: .secondary }
    }
}
struct RookMark: View {
    var size: CGFloat = 40
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.25).fill(RookTheme.accent.gradient)
            Image(systemName: "checkerboard.shield").font(.system(size: size * 0.58, weight: .semibold)).foregroundStyle(.white)
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
}
struct StatusBadge: View {
    let text: String
    var color: Color = .secondary
    var symbol: String? = nil
    var body: some View {
        HStack(spacing: 5) {
            if let symbol { Image(systemName: symbol) }
            Text(text).fontWeight(.medium)
        }.font(.caption).padding(.horizontal, 9).padding(.vertical, 5)
            .foregroundStyle(color).background(color.opacity(0.10), in: Capsule())
            .accessibilityElement(children: .combine)
    }
}
struct DemoBadge: View {
    var body: some View { StatusBadge(text: "DEMO · SAMPLE DATA", color: RookTheme.amber, symbol: "sparkles") }
}
struct SeverityBadge: View {
    let severity: Severity
    var body: some View { StatusBadge(text: severity.rawValue.capitalized, color: RookTheme.color(severity), symbol: severity == .critical ? "shield.slash" : "exclamationmark.circle") }
}
struct Surface<Content: View>: View {
    let title: String?
    @ViewBuilder let content: Content
    init(_ title: String? = nil, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let title { Text(title).font(.headline) }
            content
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(.background, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.primary.opacity(0.07), lineWidth: 1))
    }
}
struct PageHeading: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 30, weight: .semibold, design: .rounded))
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
struct EmptyActivity: View {
    let title: String
    let description: String
    let symbol: String
    var body: some View {
        ContentUnavailableView { Label(title, systemImage: symbol) } description: { Text(description) }
            .frame(maxWidth: .infinity, minHeight: 260)
    }
}
struct DetailField: View {
    let name: String
    let value: String
    var body: some View {
        HStack(alignment: .top) {
            Text(name).foregroundStyle(.secondary).frame(width: 130, alignment: .leading)
            Text(value).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
        }.font(.callout)
    }
}
