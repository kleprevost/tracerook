import Foundation
import TraceRookContracts

/// Second preflight, independent from projection. A refusal disables this remote
/// request; it never weakens deterministic local policy.
public enum CloudEgress {
    public static func validateSummary(_ text: String) throws {
        guard text.utf8.count <= 2048, Redactor().redact(text).count == 0,
              text.unicodeScalars.allSatisfy({ $0.value >= 32 && $0.value != 127 }) else { throw TraceRookError.unsafePayload }
        let patterns = [
            #"(?i)(?:https?://|file://|data:|/Users/|/home/|[a-z]:\\|\.ssh|\.env|-----BEGIN|\b(?:[0-9]{1,3}\.){3}[0-9]{1,3}\b)"#,
            #"(?:^|\s)[/~][^\s]+"#,
            #"\b[A-Za-z_][A-Za-z0-9_]*=[^\s]+"#,
            #"\b[^\s@]+@[^\s@]+\.[^\s@]+\b"#
        ]
        for pattern in patterns {
            let regex = try NSRegularExpression(pattern: pattern)
            guard regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) == nil else { throw TraceRookError.unsafePayload }
        }
        // Unknown high-entropy credentials need not have a recognizable prefix.
        for token in text.components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-+/=")).inverted) where token.count >= 24 {
            var counts: [Character: Int] = [:]
            for character in token { counts[character, default: 0] += 1 }
            let length = Double(token.count)
            let entropy = counts.values.reduce(0.0) { sum, count in let p = Double(count) / length; return sum - p * log2(p) }
            guard entropy < 3.5 else { throw TraceRookError.unsafePayload }
        }
    }
}
