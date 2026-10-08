import Foundation
import TraceRookContracts

/// Real beta credentials live only in the service's memory. Server-side token
/// digests remain authoritative. Restart requires the user's beta access code;
/// there is no Keychain, preference, disk, environment or logging fallback.
public actor SessionCloudCredentialStore: CloudCredentialStore {
    private var enrollment: CloudStoredEnrollment?
    public init() {}
    public func load() -> CloudStoredEnrollment? { enrollment }
    public func save(_ value: CloudStoredEnrollment) throws { try value.validate(); enrollment = value }
    public func clear() { enrollment = nil }
}

/// Operator-issued credential package for manual beta entry. A package is a
/// bearer secret, not proof of authentication; authenticated capabilities and
/// usage checks must pass before the service accepts it.
public enum BetaAccessCode {
    public static func encode(_ credential: CloudCredential) throws -> String {
        let bytes = try WireCodec.encodePayload(credential, maximumBytes: 2048)
        return "trb_" + bytes.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    public static func decode(_ code: String) throws -> CloudCredential {
        guard code.hasPrefix("trb_"), (64...3000).contains(code.utf8.count),
              code.dropFirst(4).allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }) else { throw LiveCloudFailure.invalidInvite }
        var encoded = String(code.dropFirst(4)).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
        guard let bytes = Data(base64Encoded: encoded), bytes.count <= 2048 else { throw LiveCloudFailure.invalidInvite }
        let credential = try WireCodec.decodePayload(CloudCredential.self, payload: bytes, maximumBytes: 2048)
        guard try encode(credential) == code else { throw LiveCloudFailure.invalidInvite }
        return credential
    }
}
