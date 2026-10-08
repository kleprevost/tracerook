import Foundation
import TraceRookContracts

/// Live control-plane DTOs reuse Core's schema-v1 ApprovalBinding. They are not
/// accepted by the hook transport and do not authenticate or consume a review.
public struct ReviewRequest: IPCMessage, Equatable {
    public let protocolVersion: Int
    public let requestID: UUID
    public let approvalID: UUID
    public let incidentID: UUID
    public let origin: DataOrigin
    public let binding: ApprovalBinding
    public let invocationNonce: String
    public let severity: Severity
    public let createdAtMS: Int64
    public let expiresAtMS: Int64
    public init(requestID: UUID, approvalID: UUID, incidentID: UUID, binding: ApprovalBinding,
                invocationNonce: String, createdAtMS: Int64, expiresAtMS: Int64) {
        protocolVersion = TraceRookVersion.liveIPC; self.requestID = requestID; self.approvalID = approvalID
        self.incidentID = incidentID; origin = .live; self.binding = binding; self.invocationNonce = invocationNonce
        severity = .high; self.createdAtMS = createdAtMS; self.expiresAtMS = expiresAtMS
    }
    enum CodingKeys: String, CodingKey, CaseIterable {
        case protocolVersion = "protocol_version", requestID = "request_id", approvalID = "approval_id", incidentID = "incident_id"
        case origin, binding, invocationNonce = "invocation_nonce", severity, createdAtMS = "created_at_ms", expiresAtMS = "expires_at_ms"
    }
    public static let wireKeys = Set(CodingKeys.allCases.map(\.rawValue))
    public static func validateWireShape(_ value: JSONValue) throws { try reviewShape(value, keys: wireKeys) }
    public func validate() throws {
        guard protocolVersion == TraceRookVersion.liveIPC else { throw TraceRookError.unsupportedVersion }
        guard origin == .live else { throw TraceRookError.notDemoData }
        guard severity == .high, createdAtMS >= 0, expiresAtMS > createdAtMS,
              expiresAtMS - createdAtMS <= 45_000 else { throw TraceRookError.malformedInput }
        try binding.validateLiveWire(); try InvocationNonce.validate(invocationNonce)
    }
}

public enum ReviewChoice: String, Codable, Sendable { case allowOnce = "allow_once", block }

/// A signed app requests this transition; only a future authenticated service
/// actor may decide whether it is still pending and within its monotonic deadline.
public struct ReviewResolution: IPCMessage, Equatable {
    public let protocolVersion: Int
    public let requestID: UUID
    public let approvalID: UUID
    public let origin: DataOrigin
    public let binding: ApprovalBinding
    public let invocationNonce: String
    public let choice: ReviewChoice
    public init(requestID: UUID, approvalID: UUID, binding: ApprovalBinding, invocationNonce: String, choice: ReviewChoice) {
        protocolVersion = TraceRookVersion.liveIPC; self.requestID = requestID; self.approvalID = approvalID
        origin = .live; self.binding = binding; self.invocationNonce = invocationNonce; self.choice = choice
    }
    enum CodingKeys: String, CodingKey, CaseIterable {
        case protocolVersion = "protocol_version", requestID = "request_id", approvalID = "approval_id", origin, binding
        case invocationNonce = "invocation_nonce", choice
    }
    public static let wireKeys = Set(CodingKeys.allCases.map(\.rawValue))
    public static func validateWireShape(_ value: JSONValue) throws { try reviewShape(value, keys: wireKeys) }
    public func validate() throws {
        guard protocolVersion == TraceRookVersion.liveIPC else { throw TraceRookError.unsupportedVersion }
        guard origin == .live else { throw TraceRookError.notDemoData }
        try binding.validateLiveWire(); try InvocationNonce.validate(invocationNonce)
    }
    public func validateBinding(to request: ReviewRequest) throws {
        try validate(); try request.validate()
        guard requestID == request.requestID, approvalID == request.approvalID,
              binding == request.binding, invocationNonce == request.invocationNonce else { throw TraceRookError.wrongBinding }
    }
}

extension ApprovalBinding {
    fileprivate func validateLiveWire() throws {
        try IPCValidation.text(toolCallID, maximumBytes: 256)
        if let turnID { try IPCValidation.text(turnID, maximumBytes: 256) }
        try IPCValidation.digest(fingerprint)
    }
}

private func reviewShape(_ value: JSONValue, keys: Set<String>) throws {
    guard case .object(let object) = value, Set(object.keys) == keys,
          case .object(let binding) = object["binding"] else { throw TraceRookError.malformedInput }
    let required: Set<String> = ["provider", "sessionID", "eventID", "toolCallID", "fingerprint"]
    guard required.isSubset(of: Set(binding.keys)), Set(binding.keys).isSubset(of: required.union(["turnID"])) else {
        throw TraceRookError.malformedInput
    }
}
