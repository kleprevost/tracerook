import Darwin
import Foundation
import MachO
import Security
import TraceRookCore

public enum IPCError: Error, Sendable { case identity, untrustedPeer, auditToken(Int32), codeLookup(Int32), codeValidation(Int32), transport, timeout, unsafeEndpoint }

/// Exact code hashes are an explicitly selected local build policy. They do not
/// prove a Developer ID chain or authenticate a replacement application bundle.
public struct PeerIdentity: Sendable {
    public let requirement: String
    public init(requirement: String) throws {
        var parsed: SecRequirement?
        guard SecRequirementCreateWithString(requirement as CFString, [], &parsed) == errSecSuccess else { throw IPCError.identity }
        self.requirement = requirement
    }
    public static func exactExecutable(_ url: URL, identifier: String) throws -> PeerIdentity {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate), nil) == errSecSuccess else { throw IPCError.identity }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dictionary = info as? [String: Any], dictionary[kSecCodeInfoIdentifier as String] as? String == identifier,
              let hash = dictionary[kSecCodeInfoUnique as String] as? Data else { throw IPCError.identity }
        let hex = hash.map { String(format: "%02x", $0) }.joined()
        return try PeerIdentity(requirement: "identifier \"\(identifier)\" and cdhash H\"\(hex)\"")
    }
    public func verifySocket(_ socket: Int32) throws {
        var user: uid_t = 0, group: gid_t = 0
        guard getpeereid(socket, &user, &group) == 0, user == geteuid() else { throw IPCError.untrustedPeer }
        var audit = [UInt8](repeating: 0, count: 32)
        var length = socklen_t(audit.count)
        let result = audit.withUnsafeMutableBytes { getsockopt(socket, SOL_LOCAL, LOCAL_PEERTOKEN, $0.baseAddress, &length) }
        guard result == 0, length == 32 else { throw IPCError.auditToken(result == 0 ? -1 : errno) }
        var guest: SecCode?, parsed: SecRequirement?
        let attributes = [kSecGuestAttributeAudit as String: Data(audit)] as CFDictionary
        let lookup = SecCodeCopyGuestWithAttributes(nil, attributes, [], &guest)
        guard lookup == errSecSuccess, let guest else { throw IPCError.codeLookup(lookup) }
        guard SecRequirementCreateWithString(requirement as CFString, [], &parsed) == errSecSuccess else { throw IPCError.identity }
        let validation = SecCodeCheckValidity(guest, SecCSFlags(rawValue: kSecCSStrictValidate), parsed)
        guard validation == errSecSuccess else { throw IPCError.codeValidation(validation) }
    }
}

public struct SignedFamily: Sendable {
    public let app: PeerIdentity
    public let agent: PeerIdentity
    public let hook: PeerIdentity
    public let mode: ServiceSecurityMode
    public init(bundle: URL) throws {
        let infoURL = bundle.appendingPathComponent("Contents/Info.plist")
        let info = try PropertyListSerialization.propertyList(from: Data(contentsOf: infoURL), format: nil) as? [String: Any]
        let folder = bundle.appendingPathComponent("Contents/MacOS")
        if info?["TraceRookSecurityMode"] as? String == "local-adhoc" {
            mode = .developer
            app = try .exactExecutable(bundle, identifier: "com.tracerook.app")
            agent = try .exactExecutable(folder.appendingPathComponent("TraceRookAgent"), identifier: "com.tracerook.agent")
            hook = try .exactExecutable(folder.appendingPathComponent("tracerook-hook"), identifier: "com.tracerook.hook")
        } else {
            var code: SecStaticCode?, information: CFDictionary?
            guard SecStaticCodeCreateWithPath(bundle as CFURL, [], &code) == errSecSuccess, let code,
                  SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
                  let values = information as? [String: Any], let team = values[kSecCodeInfoTeamIdentifier as String] as? String,
                  team.count == 10, team.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { throw IPCError.identity }
            mode = .developerID
            func identity(_ id: String) throws -> PeerIdentity {
                try PeerIdentity(requirement: "anchor apple generic and identifier \"\(id)\" and certificate 1[field.1.2.840.113635.100.6.2.6] exists and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and certificate leaf[subject.OU] = \"\(team)\"")
            }
            app = try identity("com.tracerook.app"); agent = try identity("com.tracerook.agent"); hook = try identity("com.tracerook.hook")
        }
    }
    public static func containingBundle(executable: URL) throws -> URL {
        let bundle = executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        guard bundle.pathExtension == "app" else { throw IPCError.identity }; return bundle
    }
    public static func currentBundle() throws -> URL {
        var buffer = [CChar](repeating: 0, count: 4_096)
        guard proc_pidpath(getpid(), &buffer, UInt32(buffer.count)) > 0 else { throw IPCError.identity }
        return try containingBundle(executable: URL(fileURLWithPath: String(cString: buffer)).standardizedFileURL)
    }
}
