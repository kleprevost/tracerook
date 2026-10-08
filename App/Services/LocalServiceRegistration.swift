import CryptoKit
import Darwin
import Foundation
import TraceRookCore
import TraceRookIPC

/// Explicit local ad-hoc distribution only. SMAppService on macOS 27 rejects
/// this helper's launch constraint; never bypass that constraint or downgrade a
/// Developer ID build. A conventional per-user LaunchAgent is shown for consent.
struct LocalServicePlan: Identifiable, Sendable {
    let id = UUID()
    let destination: URL
    let originalDigest: String?
    let originalContent: Data?
    let content: Data
    var preview: String { String(data: content, encoding: .utf8) ?? "" }
}
enum LocalServiceRegistration {
    static let label = "com.tracerook.agent.local"
    static var destination: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }
    static func plan() throws -> LocalServicePlan {
        guard try SignedFamily(bundle: Bundle.main.bundleURL).mode == .developer else { throw IPCError.identity }
        try PrivateStateDirectory.rejectUnsafeFile(destination)
        let old = try existing(destination)
        if let old {
            let value = try PropertyListSerialization.propertyList(from: old, format: nil) as? [String: Any]
            guard value?["Label"] as? String == label else { throw IPCError.unsafeEndpoint }
        }
        let agent = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/TraceRookAgent").path
        let content = try PropertyListSerialization.data(fromPropertyList: ["Label": label, "ProgramArguments": [agent],
            "MachServices": ["com.tracerook.agent.ui": true], "RunAtLoad": true, "KeepAlive": true, "ProcessType": "Background"], format: .xml, options: 0)
        return LocalServicePlan(destination: destination, originalDigest: old.map(digest), originalContent: old, content: content)
    }
    static func install(_ plan: LocalServicePlan) throws {
        guard plan.destination == destination, try existing(destination).map(digest) == plan.originalDigest else { throw StoreError.conflict }
        let parent = destination.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parent.path) { try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]) }
        var info = stat()
        guard lstat(parent.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR, info.st_uid == geteuid() else { throw StoreError.unsafePath }
        let temporary = parent.appendingPathComponent(".tracerook-\(UUID()).plist")
        let fd = open(temporary.path, O_CREAT | O_EXCL | O_NOFOLLOW | O_WRONLY | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw StoreError.unsafePath }
        defer { close(fd); unlink(temporary.path) }
        let count = plan.content.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, $0.count) }
        guard count == plan.content.count, fsync(fd) == 0,
              try existing(destination).map(digest) == plan.originalDigest else { throw StoreError.conflict }
        if let old = plan.originalContent {
            let backup = parent.appendingPathComponent("\(label).\(UUID()).backup")
            let backupFD = open(backup.path, O_CREAT | O_EXCL | O_NOFOLLOW | O_WRONLY | O_CLOEXEC, 0o600)
            guard backupFD >= 0 else { throw StoreError.unsafePath }
            defer { close(backupFD) }
            guard old.withUnsafeBytes({ Darwin.write(backupFD, $0.baseAddress, $0.count) }) == old.count,
                  fsync(backupFD) == 0 else { throw StoreError.unavailable }
        }
        guard rename(temporary.path, destination.path) == 0 else { throw StoreError.unavailable }
        _ = run(["bootout", "gui/\(geteuid())/\(label)"])
        guard run(["bootstrap", "gui/\(geteuid())", destination.path]) == 0 else { throw IPCError.transport }
    }
    static func remove() throws {
        try PrivateStateDirectory.rejectUnsafeFile(destination)
        guard let data = try existing(destination), let value = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              value["Label"] as? String == label else { throw IPCError.unsafeEndpoint }
        guard run(["bootout", "gui/\(geteuid())/\(label)"]) == 0 else { throw IPCError.transport }
        guard unlink(destination.path) == 0 else { throw StoreError.unavailable }
    }
    private static func existing(_ url: URL) throws -> Data? {
        try PrivateStateDirectory.rejectUnsafeFile(url)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw StoreError.unsafePath }; defer { close(fd) }
        var bytes = [UInt8](repeating: 0, count: 16_385)
        let count = read(fd, &bytes, bytes.count)
        guard count >= 0, count <= 16_384 else { throw StoreError.unsafePath }; return Data(bytes.prefix(count))
    }
    private static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private static func run(_ arguments: [String]) -> Int32 {
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/bin/launchctl"); process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        do { try process.run(); process.waitUntilExit(); return process.terminationStatus } catch { return -1 }
    }
}
