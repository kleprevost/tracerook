import Foundation
import TraceRookContracts
import TraceRookFixtures

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
} else {
    FileHandle.standardError.write(Data("TraceRookAgent live IPC is not implemented in Phase 0. No protection advertised.\n".utf8))
    exit(78)
}
