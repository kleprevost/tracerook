import Foundation
import TraceRookContracts

/// Every review belongs to one still-waiting invocation. Terminal state is set
/// before suspension, preventing actor reentrancy from approving twice.
public actor ApprovalCoordinator {
    private struct Pending {
        let request: ReviewRequest
        var record: ApprovalRecord
        let deadline: ContinuousClock.Instant
        var committing: Bool = false
    }
    private var pending: [UUID: Pending] = [:]
    private let store: SessionStore
    public init(store: SessionStore) { self.store = store }
    public func create(requestID: UUID, incidentID: UUID, binding: ApprovalBinding, nonce: String,
                       deadline: ContinuousClock.Instant) async throws -> ReviewRequest {
        guard pending.count < 25, pending[requestID] == nil else { throw TraceRookError.quotaExhausted }
        let now = Date.now, clock = ContinuousClock()
        let end = min(deadline, clock.now.advanced(by: .seconds(45)))
        let duration = clock.now.duration(to: end).components
        let milliseconds = duration.seconds * 1_000 + duration.attoseconds / 1_000_000_000_000_000
        guard milliseconds > 0 else { throw TraceRookError.timeout }
        let record = ApprovalRecord(incidentID: incidentID, origin: .live, binding: binding,
                                    requestedAt: now, expiresAt: now.addingTimeInterval(Double(milliseconds) / 1_000))
        let request = ReviewRequest(requestID: requestID, approvalID: record.id, incidentID: incidentID,
            binding: binding, invocationNonce: nonce, createdAtMS: Int64(now.timeIntervalSince1970 * 1_000),
            expiresAtMS: Int64(now.timeIntervalSince1970 * 1_000) + milliseconds)
        // Reserve the binding before crossing the store actor.
        pending[requestID] = Pending(request: request, record: record, deadline: end, committing: true)
        do { try await store.saveApproval(request, record: record) }
        catch { pending.removeValue(forKey: requestID); throw error }
        pending[requestID]?.committing = false
        return request
    }
    public func resolve(_ resolution: ReviewResolution) async throws {
        guard let item = pending[resolution.requestID] else { throw TraceRookError.staleApproval }
        try resolution.validateBinding(to: item.request)
        guard item.record.state == .pending, !item.committing else { throw TraceRookError.staleApproval }
        if ContinuousClock().now >= item.deadline {
            try await transition(resolution.requestID, state: .expired); throw TraceRookError.staleApproval
        }
        try await transition(resolution.requestID, state: resolution.choice == .allowOnce ? .approvedOnce : .denied)
    }
    private func transition(_ id: UUID, state: ApprovalState) async throws {
        guard var item = pending[id], item.record.state == .pending, !item.committing else { throw TraceRookError.staleApproval }
        item.record.state = state; item.record.respondedAt = .now
        item.committing = true
        pending[id] = item
        do { try await store.resolveApproval(item.request, record: item.record); pending[id]?.committing = false }
        catch {
            // A failed durable commit cannot authorize execution.
            item.record.state = .aborted; item.committing = false; pending[id] = item; throw error
        }
    }
    public func wait(requestID: UUID) async -> ApprovalState {
        while let item = pending[requestID] {
            if Task.isCancelled { try? await transition(requestID, state: .aborted) }
            else if item.record.state == .pending && ContinuousClock().now >= item.deadline { try? await transition(requestID, state: .expired) }
            if let result = pending[requestID], result.record.state != .pending, !result.committing {
                pending.removeValue(forKey: requestID)
                if result.record.state == .approvedOnce && ContinuousClock().now >= result.deadline { return .expired }
                return result.record.state
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return .aborted
    }
    public func activeRequests() -> [ReviewRequest] {
        pending.values.filter { $0.record.state == .pending && !$0.committing && ContinuousClock().now < $0.deadline }.map(\.request)
    }
    public func abortAll() async {
        while pending.values.contains(where: \.committing) { try? await Task.sleep(for: .milliseconds(10)) }
        for id in Array(pending.keys) where pending[id]?.record.state == .pending { try? await transition(id, state: .aborted) }
        for id in Array(pending.keys) {
            guard var item = pending[id], item.record.state == .approvedOnce else { continue }
            item.record.state = .aborted; item.record.respondedAt = .now; item.committing = true; pending[id] = item
            try? await store.abortApproved(item.request, record: item.record)
            pending[id]?.committing = false
        }
    }
}
