import Foundation
import CryptoKit
import Darwin

public enum ClaudeHookConfigurationError: Error, Equatable {
    case unsafePath, invalidSettings, settingsChanged, invalidInvocation, writeFailed
}

public struct ClaudeHookInstallationPlan: Sendable {
    public let settingsURL: URL
    public let beforeText: String
    public let afterText: String
    public let command: String
    public var requiresChange: Bool { originalData != replacementData }
    fileprivate let originalData: Data?
    fileprivate let replacementData: Data
    fileprivate let originalDigest: Data?
    fileprivate let homeDirectory: URL
}

public enum ClaudeHookConfiguration {
    public static func plan(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
                            hookExecutable: URL, hostVersion: String) throws -> ClaudeHookInstallationPlan {
        guard hookExecutable.path.hasPrefix("/"), !hostVersion.isEmpty,
              !hostVersion.contains(where: { $0.isNewline || $0 == "\0" }),
              !hookExecutable.path.contains(where: { $0.isNewline || $0 == "\0" }) else {
            throw ClaudeHookConfigurationError.invalidInvocation
        }
        let directory = homeDirectory.appendingPathComponent(".claude", isDirectory: true)
        let settings = directory.appendingPathComponent("settings.json")
        try validate(homeDirectory, directory: true)
        try validate(directory, directory: true, allowMissing: true)
        let original = try readSettings(settings)
        var root: [String: Any] = [:]
        if let original {
            guard let object = try? JSONSerialization.jsonObject(with: original), let dictionary = object as? [String: Any] else {
                throw ClaudeHookConfigurationError.invalidSettings
            }
            root = dictionary
        }
        let command = quote(hookExecutable.path) + " --adapter claude_code --host-version " + quote(hostVersion) + " --timeout-ms 80000"
        var hooks: [String: Any] = [:]
        if let existing = root["hooks"] {
            guard let dictionary = existing as? [String: Any] else { throw ClaudeHookConfigurationError.invalidSettings }
            hooks = dictionary
        }
        var groups: [[String: Any]] = []
        if let existing = hooks["PreToolUse"] {
            guard let array = existing as? [[String: Any]] else { throw ClaudeHookConfigurationError.invalidSettings }
            groups = array
        }
        // Only the exact command generated for this bundled executable is owned.
        let desired: [String: Any] = ["matcher": "*", "hooks": [["type": "command", "command": command, "timeout": 85]]]
        var preserved: [[String: Any]] = []
        for var group in groups {
            guard let entries = group["hooks"] as? [[String: Any]] else { throw ClaudeHookConfigurationError.invalidSettings }
            let remaining = entries.filter { !($0["type"] as? String == "command" && $0["command"] as? String == command) }
            if remaining.count == entries.count { preserved.append(group) }
            else if !remaining.isEmpty { group["hooks"] = remaining; preserved.append(group) }
        }
        preserved.append(desired)
        hooks["PreToolUse"] = preserved
        root["hooks"] = hooks
        var replacement = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        replacement.append(10)
        // Keep existing formatting if it already expresses the exact desired configuration.
        if let original, let old = try? JSONSerialization.jsonObject(with: original) as? NSDictionary,
           old == root as NSDictionary { replacement = original }
        return ClaudeHookInstallationPlan(settingsURL: settings, beforeText: original.flatMap { String(data: $0, encoding: .utf8) } ?? "",
                                         afterText: String(decoding: replacement, as: UTF8.self), command: command,
                                         originalData: original, replacementData: replacement,
                                         originalDigest: original.map { Data(SHA256.hash(data: $0)) }, homeDirectory: homeDirectory)
    }

    @discardableResult
    public static func install(_ plan: ClaudeHookInstallationPlan) throws -> URL? {
        let manager = FileManager.default
        let directory = plan.settingsURL.deletingLastPathComponent()
        try validate(plan.homeDirectory, directory: true)
        try validate(directory, directory: true, allowMissing: true)
        let current = try readSettings(plan.settingsURL)
        guard current.map({ Data(SHA256.hash(data: $0)) }) == plan.originalDigest else {
            throw ClaudeHookConfigurationError.settingsChanged
        }
        guard plan.requiresChange else { return nil }
        if !manager.fileExists(atPath: directory.path) {
            try manager.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        }
        try validate(directory, directory: true)
        let directoryFD = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard directoryFD >= 0 else { throw ClaudeHookConfigurationError.unsafePath }
        defer { close(directoryFD) }
        var directoryIdentity = stat()
        guard fstat(directoryFD, &directoryIdentity) == 0,
              directoryIdentity.st_uid == getuid(), directoryIdentity.st_mode & S_IFMT == S_IFDIR,
              directoryIdentity.st_mode & 0o022 == 0 else { throw ClaudeHookConfigurationError.unsafePath }
        var backup: URL?
        if let current {
            let destination = directory.appendingPathComponent("settings.json.tracerook-backup-" + UUID().uuidString)
            try writeExclusive(current, to: destination, directoryFD: directoryFD)
            backup = destination
        }
        let temporary = directory.appendingPathComponent(".tracerook-settings-" + UUID().uuidString)
        defer { _ = unlinkat(directoryFD, temporary.lastPathComponent, 0) }
        try writeExclusive(plan.replacementData, to: temporary, directoryFD: directoryFD)
        try validate(directory, directory: true)
        guard try readSettings(plan.settingsURL).map({ Data(SHA256.hash(data: $0)) }) == plan.originalDigest else {
            throw ClaudeHookConfigurationError.settingsChanged
        }
        var currentDirectoryIdentity = stat()
        guard lstat(directory.path, &currentDirectoryIdentity) == 0,
              currentDirectoryIdentity.st_dev == directoryIdentity.st_dev,
              currentDirectoryIdentity.st_ino == directoryIdentity.st_ino else {
            throw ClaudeHookConfigurationError.settingsChanged
        }
        // Anchor both sides of the rename to the validated directory descriptor.
        guard renameat(directoryFD, temporary.lastPathComponent, directoryFD, plan.settingsURL.lastPathComponent) == 0 else {
            throw ClaudeHookConfigurationError.writeFailed
        }
        guard fsync(directoryFD) == 0 else { throw ClaudeHookConfigurationError.writeFailed }
        return backup
    }

    private static func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    private static func validate(_ url: URL, directory: Bool, allowMissing: Bool = false) throws {
        var metadata = stat()
        if lstat(url.path, &metadata) != 0 {
            if allowMissing && errno == ENOENT { return }
            throw ClaudeHookConfigurationError.unsafePath
        }
        let expected = directory ? S_IFDIR : S_IFREG
        guard metadata.st_mode & S_IFMT == expected, metadata.st_uid == getuid(),
              metadata.st_mode & 0o022 == 0,
              directory || metadata.st_nlink == 1 else {
            throw ClaudeHookConfigurationError.unsafePath
        }
    }
    private static func readSettings(_ url: URL) throws -> Data? {
        try validate(url, directory: false, allowMissing: true)
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW)
        if fd < 0 {
            if errno == ENOENT { return nil }
            throw ClaudeHookConfigurationError.unsafePath
        }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        var metadata = stat()
        guard fstat(fd, &metadata) == 0, metadata.st_uid == getuid(), metadata.st_mode & S_IFMT == S_IFREG,
              metadata.st_mode & 0o022 == 0, metadata.st_nlink == 1, metadata.st_size <= 4_194_304 else {
            throw ClaudeHookConfigurationError.unsafePath
        }
        return try handle.readToEnd() ?? Data()
    }
    private static func writeExclusive(_ data: Data, to url: URL, directoryFD: Int32) throws {
        let fd = openat(directoryFD, url.lastPathComponent, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw ClaudeHookConfigurationError.writeFailed }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        do { try handle.write(contentsOf: data); try handle.synchronize(); try handle.close() }
        catch { _ = unlinkat(directoryFD, url.lastPathComponent, 0); throw error }
    }
}
