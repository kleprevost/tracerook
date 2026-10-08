import TraceRookContracts

public struct RuleEvidence: Codable, Sendable, Equatable {
    public let ruleID: String
    public let severity: Severity
    public let summary: String
    public let catastrophic: Bool
    public init(ruleID: String, severity: Severity, summary: String, catastrophic: Bool = false) {
        self.ruleID = ruleID; self.severity = severity; self.summary = summary; self.catastrophic = catastrophic
    }
}
