import Foundation
import TraceRookContracts
import TraceRookCore

public struct DemoSnapshot: Codable, Sendable {
    public let schemaVersion: Int
    public let origin: DataOrigin
    public let sessions: [SessionRecord]
    public let incidents: [IncidentRecord]
    public let account: CloudAccount
    public let usage: CloudUsage
    public let plans: [CloudPlan]
    public let verdict: AnalysisVerdict
    public func validate() throws {
        guard schemaVersion == 1, origin == .demo, !sessions.isEmpty,
              sessions.allSatisfy({ $0.origin == .demo && $0.coverage == .demo }),
              incidents.allSatisfy({ $0.origin == .demo && sessions.map(\.id).contains($0.sessionID) }),
              Set(sessions.map(\.id)).count == sessions.count,
              Set(incidents.map(\.id)).count == incidents.count,
              account.state == "demo", account.accountID.hasPrefix("demo-"),
              usage.quota > 0, usage.analyzedActions >= 0, usage.dailyActions.allSatisfy({ $0 >= 0 })
        else { throw TraceRookError.fixtureInvalid }
        try verdict.validate()
    }
}
public enum FixtureLoader {
    public static func loadDemo() throws -> DemoSnapshot {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(DemoSnapshot.self, from: data(named: "cloud-demo"))
        try snapshot.validate(); return snapshot
    }
    public static func data(named name: String) throws -> Data {
        // SwiftPM's generated accessor searches the app root rather than Contents/Resources.
        // Prefer the relocatable, signed app resource bundle before its development fallback.
        let executableResources = Bundle.main.executableURL?.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources")
        let locations = [Bundle.main.resourceURL, executableResources].compactMap { $0 }
        let packagedBundle = locations.compactMap { Bundle(url: $0.appendingPathComponent("TraceRook_TraceRookFixtures.bundle")) }.first
        if Bundle.main.executableURL?.path.contains(".app/Contents/MacOS/") == true, packagedBundle == nil {
            throw TraceRookError.fixtureInvalid
        }
        guard let url = (packagedBundle ?? Bundle.module).url(forResource: name, withExtension: "json") else { throw TraceRookError.fixtureInvalid }
        return try Data(contentsOf: url)
    }
}
public struct MockCloudAPIClient: CloudAPIClient {
    private let fixture: DemoSnapshot
    public init() throws { fixture = try FixtureLoader.loadDemo() }
    public func registerDevice() async throws -> CloudDeviceRegistration {
        let data = Data(#"{"device_id":"demo-device","enrollment_state":"simulated"}"#.utf8)
        return try JSONDecoder().decode(CloudDeviceRegistration.self, from: data)
    }
    public func account() async throws -> CloudAccount { fixture.account }
    public func usage(month: String) async throws -> CloudUsage { fixture.usage }
    public func plans() async throws -> [CloudPlan] { fixture.plans }
    public func acknowledgeTelemetry(origin: DataOrigin) async throws -> Bool {
        guard origin == .demo else { throw TraceRookError.notDemoData }; return true
    }
    public func analyze(_ request: AnalysisRequest) async throws -> CloudAnalysisResponse {
        guard request.origin == .demo else { throw TraceRookError.notDemoData }
        // Decode a response so that every field follows the public future API contract.
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let verdict = try JSONValue.decodeBounded(encoder.encode(fixture.verdict))
        let json: JSONValue = .object([
            "request_id": .string(request.requestID.uuidString), "verdict": verdict,
            "model_id": .string("demo-fixture-v1"), "policy_version": .number(1),
            "trace_id": .string("demo-trace"), "expires_at": .string("2026-10-08T13:00:00Z"), "billed_units": .number(0)
        ])
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(CloudAnalysisResponse.self, from: json.canonicalData())
    }
}
public struct TraceRookCloudDemoProvider: AnalysisProvider {
    public let mode = AnalysisMode.traceRookCloudDemo
    private let client: MockCloudAPIClient
    public init() throws { client = try MockCloudAPIClient() }
    public func checkAvailability() async -> ProviderHealth {
        ProviderHealth(mode: mode, available: false, explanation: "Cloud Demo uses bundled sample data. Live Cloud AI analysis is unavailable.")
    }
    public func analyze(_ request: AnalysisRequest, deadline: ContinuousClock.Instant) async throws -> AnalysisVerdict {
        guard ContinuousClock.now < deadline else { throw TraceRookError.timeout }
        return try await client.analyze(request).verdict
    }
}
