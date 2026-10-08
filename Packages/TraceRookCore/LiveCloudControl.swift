import Foundation
import TraceRookContracts

public enum LiveCloudOperation: String, Codable, Sendable { case status, connect, refresh, rotate, disconnect, delete, pause, resume }
/// Only the authenticated native UI can enroll. Analysis is deliberately absent:
/// a UI control command cannot submit Demo events to the production provider.
public struct LiveCloudControl: IPCMessage, CustomStringConvertible, CustomDebugStringConvertible {
    public let operation: LiveCloudOperation
    public let invitation: String?
    public let consent: CloudConsent?
    public init(operation: LiveCloudOperation, invitation: String? = nil, consent: CloudConsent? = nil) {
        self.operation = operation; self.invitation = invitation; self.consent = consent
    }
    public var description: String { "<cloud control redacted>" }
    public var debugDescription: String { description }
    public static let wireKeys: Set<String> = ["operation", "invitation", "consent"]
    public static func validateWireShape(_ value: JSONValue) throws {
        try CloudWire.exact(value, keys: wireKeys)
        if let consent = value["consent"], consent != .null { try CloudWire.exact(consent, keys: ["version", "acceptedAt", "provider", "categories", "containsCodeExcerpts"]) }
    }
    public func validate() throws {
        guard (operation == .connect) == (invitation != nil), (operation == .connect) == (consent != nil) else { throw TraceRookError.malformedInput }
        if let invitation {
            if invitation.hasPrefix("trb_") { _ = try BetaAccessCode.decode(invitation); try consent?.validate(); return }
            guard invitation.hasPrefix("tri_"), invitation.count == 68, invitation.dropFirst(4).allSatisfy({ $0.isASCII && ($0.isNumber || ("a"..."f").contains(String($0))) }) else { throw LiveCloudFailure.invalidInvite }
            try consent?.validate()
        }
    }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(operation, forKey: .operation); try c.encode(invitation, forKey: .invitation); try c.encode(consent, forKey: .consent)
    }
    enum Keys: String, CodingKey { case operation, invitation, consent }
}
public struct LiveCloudStatus: IPCMessage {
    public let connected: Bool
    public let analysisEnabledLocally: Bool
    public let busy: Bool
    public let deviceID: UUID?
    public let capabilities: CloudCapabilities?
    public let usage: LiveCloudUsage?
    public let realAnalysisValidatedAt: String?
    public let failure: LiveCloudFailure?
    public init(connected: Bool = false, analysisEnabledLocally: Bool = false, busy: Bool = false, deviceID: UUID? = nil, capabilities: CloudCapabilities? = nil,
                usage: LiveCloudUsage? = nil, realAnalysisValidatedAt: String? = nil, failure: LiveCloudFailure? = nil) {
        self.connected = connected; self.analysisEnabledLocally = analysisEnabledLocally; self.busy = busy; self.deviceID = deviceID; self.capabilities = capabilities
        self.usage = usage; self.realAnalysisValidatedAt = realAnalysisValidatedAt; self.failure = failure
    }
    public static let wireKeys: Set<String> = ["connected", "analysisEnabledLocally", "busy", "deviceID", "capabilities", "usage", "realAnalysisValidatedAt", "failure"]
    public static func validateWireShape(_ value: JSONValue) throws {
        try CloudWire.exact(value, keys: wireKeys)
        if let cap = value["capabilities"], cap != .null { try CloudCapabilities.validateWireShape(cap) }
        if let usage = value["usage"], usage != .null { try LiveCloudUsage.validateWireShape(usage) }
    }
    public func validate() throws {
        guard connected == (deviceID != nil), connected || !analysisEnabledLocally, connected || (capabilities == nil && usage == nil && realAnalysisValidatedAt == nil) else { throw TraceRookError.malformedResponse }
        try capabilities?.validate(); try usage?.validate()
        if let date = realAnalysisValidatedAt { guard CloudWire.timestamp(date) != nil else { throw TraceRookError.malformedResponse } }
    }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(connected, forKey: .connected); try c.encode(analysisEnabledLocally, forKey: .analysisEnabledLocally); try c.encode(busy, forKey: .busy); try c.encode(deviceID, forKey: .deviceID)
        try c.encode(capabilities, forKey: .capabilities); try c.encode(usage, forKey: .usage)
        try c.encode(realAnalysisValidatedAt, forKey: .realAnalysisValidatedAt); try c.encode(failure, forKey: .failure)
    }
    enum Keys: String, CodingKey { case connected, analysisEnabledLocally, busy, deviceID, capabilities, usage, realAnalysisValidatedAt, failure }
}
