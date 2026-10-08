import Foundation
import OSLog
import TraceRookContracts

public struct RedactionResult: Sendable { public let text: String; public let count: Int }

/// Stable placeholders are categories, never a recoverable hash of a secret.
public struct Redactor: Sendable {
    public init() {}
    private static let patterns: [(String, String)] = [
        (#"(?s)-----BEGIN (?:[A-Z ]*PRIVATE KEY)-----.*?(?:-----END [A-Z ]*PRIVATE KEY-----|$)"#, "[REDACTED:PRIVATE_KEY]"),
        (#"(?i)\b(?:sk-ant-[a-z0-9_-]+|sk-[a-z0-9_-]{16,}|gh[pousr]_[a-z0-9_]{16,}|github_pat_[a-z0-9_]+|AKIA[A-Z0-9]{16}|ASIA[A-Z0-9]{16})\b"#, "[REDACTED:TOKEN]"),
        (#"(?i)\bBearer\s+[a-z0-9._~+/=-]+"#, "Bearer [REDACTED:TOKEN]"),
        (#"(?i)\b(?:password|passwd|secret|api[_-]?key|access[_-]?token|auth[_-]?token|aws_secret_access_key)\s*[=:]\s*(?:\"[^\"]*\"|'[^']*'|[^\s,;}&]+)"#, "[REDACTED:ASSIGNMENT]"),
        (#"/Users/[^/\s\"']+"#, "~"),
        (#"(?i)(https?://)[^/\s:@]+:[^/\s@]+@"#, "$1[REDACTED:AUTH]@")
    ]
    public func redact(_ input: String, limit: Int = 4096) -> RedactionResult {
        var result = input, count = 0
        for (pattern, replacement) in Self.patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(result.startIndex..., in: result)
            count += regex.numberOfMatches(in: result, range: range)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: replacement)
        }
        // Remove control characters that can forge log lines or UI content.
        result = result.unicodeScalars.filter { $0.value >= 32 || $0 == "\n" || $0 == "\t" }.map(String.init).joined()
        if result.utf8.count > limit {
            result = String(result.prefix(limit / 4)) + " [TRUNCATED]"
        }
        return RedactionResult(text: result, count: count)
    }
    public func sanitize(_ value: JSONValue) -> JSONValue {
        switch value {
        case .string(let text): return .string(redact(text).text)
        case .array(let values): return .array(values.map(sanitize))
        case .object(let values):
            var output: [String: JSONValue] = [:]
            for (index, pair) in values.sorted(by: { $0.key < $1.key }).enumerated() {
                let (key, value) = pair
                let secretKey = key.lowercased().contains("password") || key.lowercased().contains("secret") || key.lowercased().contains("api_key") || key.lowercased().contains("token")
                let sanitizedKey = redact(key)
                // Keys can themselves contain secrets; category placeholders may collide.
                let safeKey = sanitizedKey.count > 0 ? "redacted_field_\(index)" : key
                output[safeKey] = secretKey ? .string("[REDACTED:FIELD]") : sanitize(value)
            }
            return .object(output)
        default: return value
        }
    }
    public func validateRemotePayload(_ data: Data) throws {
        guard data.count <= 32_768, let string = String(data: data, encoding: .utf8) else { throw TraceRookError.unsafePayload }
        let redacted = redact(string, limit: 40_000)
        guard redacted.count == 0 else { throw TraceRookError.unsafePayload }
    }
}

/// Logs accept only enumerated codes and generated identifiers, never free-form input/error descriptions.
public struct SafeLogger: Sendable {
    public enum Code: String, Sendable { case started, stopped, malformedInput, unavailable, fixtureLoaded, decision, timeout }
    private let logger: Logger
    public init(component: String) { logger = Logger(subsystem: "com.tracerook", category: component) }
    public func record(_ code: Code, id: UUID = UUID()) {
        logger.info("status=\(code.rawValue, privacy: .public) id=\(id.uuidString, privacy: .public)")
    }
}
