import Foundation
import Testing
import TraceRookPrivacy
import TraceRookContracts

@Test func recognizedSecretsAreRemoved() {
    let samples = ["sk-ant-api03-FAKE-fixture-not-a-key", "ghp_abcdefghijklmnopqrstFAKE", "AKIAABCDEFGHIJKLMNOP", "Bearer sample-token", "password='fixture-value'", "api_key=sample-secret", "-----BEGIN PRIVATE KEY-----\nfixture\n-----END PRIVATE KEY-----"]
    for sample in samples {
        let result = Redactor().redact(sample)
        #expect(result.count > 0)
        #expect(!result.text.contains(sample))
        #expect(result.text.contains("REDACTED"))
    }
    #expect(Redactor().redact("/Users/sample/.ssh/id_ed25519").text == "~/.ssh/id_ed25519")
}
@Test func remotePreflightRejectsResidualSecrets() {
    #expect(throws: (any Error).self) { try Redactor().validateRemotePayload(Data("Bearer fixture-token".utf8)) }
    #expect(throws: (any Error).self) { try Redactor().validateRemotePayload(Data(repeating: 32, count: 32_769)) }
}
@Test func unicodeAndControlCharactersAreHandled() {
    let redacted = Redactor().redact("路径 \u{1B}password=fixture Ω")
    #expect(!redacted.text.contains("fixture"))
    #expect(!redacted.text.contains("\u{1B}"))
    #expect(redacted.text.contains("路径"))
}

@Test func nestedSecretFieldsAndCollidingRedactedKeysAreSafe() {
    let input: JSONValue = .object([
        "api_key": .string("fixture-value"),
        "nested": .array([.object(["password": .string("fixture-secret")])]),
        "sk-ant-FAKE-one": .string("a"), "sk-ant-FAKE-two": .string("b")
    ])
    let output = Redactor().sanitize(input)
    #expect(output["api_key"]?.string == "[REDACTED:FIELD]")
    if case .object(let fields) = output { #expect(fields.count == 4) }
}
