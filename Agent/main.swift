import Foundation
import TraceRookContracts
import TraceRookCore
import TraceRookFixtures
import TraceRookIPC

if CommandLine.arguments.contains("--version") {
    print("TraceRookAgent \(TraceRookVersion.app)")
} else if CommandLine.arguments.contains("--protocol-version") {
    print(TraceRookVersion.liveIPC)
} else if CommandLine.arguments.contains("--self-test") {
    do {
        let fixture = try FixtureLoader.loadDemo()
        let frame = try WireCodec.encode(RequestBudget())
        _ = try WireCodec.decode(RequestBudget.self, frame: frame)
        print("Fixture schema v\(fixture.schemaVersion) and IPC v2 budget codec: passed; live service is not registered.")
    } catch {
        FileHandle.standardError.write(Data("Fixture validation failed.\n".utf8)); exit(1)
    }
} else if CommandLine.arguments.contains("--identity-self-test") {
    do {
        let bundle = try SignedFamily.currentBundle()
        print("Bundle discovery: passed")
        let family = try SignedFamily(bundle: bundle)
        print("Signed family: passed; mode=\(family.mode.rawValue)")
    } catch { print("Signed family: failed"); exit(1) }
} else {
    do {
        let bundle = try SignedFamily.currentBundle()
        let runtime = try AgentRuntime(bundle: bundle)
        withExtendedLifetime(runtime) { RunLoop.current.run() }
    } catch {
        let code = error is IPCError ? "identity_or_endpoint" : error is StoreError ? "storage" : "startup"
        FileHandle.standardError.write(Data("TraceRook service startup failed: \(code); protection unavailable.\n".utf8)); exit(78)
    }
}
