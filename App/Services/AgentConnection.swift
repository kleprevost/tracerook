import Foundation
import Observation
import ServiceManagement
import TraceRookContracts
import TraceRookCore
import TraceRookIPC

@MainActor @Observable
final class AgentConnection {
    private(set) var status = "Service not connected"
    private(set) var connected = false
    private var client: XPCClient?
    private let model: DesktopModel
    private var refreshTask: Task<Void, Never>?
    var servicePlan: LocalServicePlan?
    init(model: DesktopModel) { self.model = model }
    func start() {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
    func command(_ method: ControlMethod, payload: JSONValue = .object([:])) async throws -> ServiceControlReply {
        if client == nil {
            client = XPCClient(agent: try SignedFamily(bundle: Bundle.main.bundleURL).agent) { [weak self] in
                Task { @MainActor in await self?.refresh() }
            }
        }
        let request = ServiceControlRequest(method: method, payload: payload)
        guard let client else { throw IPCError.transport }
        let reply = try WireCodec.decode(ServiceControlReply.self, frame: await client.call(WireCodec.encode(request, maximumBytes: 16_384)))
        guard reply.requestID == request.requestID, reply.error == nil else { throw IPCError.transport }; return reply
    }
    func refresh() async {
        do {
            let reply = try await command(.snapshot, payload: .object(["limit": .number(25)]))
            let snapshot = try JSONDecoder().decode(ServiceSnapshot.self, from: reply.payload.canonicalData())
            try model.apply(snapshot)
            connected = true
            status = snapshot.securityMode == .developer ? "Connected · local ad-hoc signatures · non-notarized" : "Connected · Developer ID"
        } catch {
            client = nil; connected = false; status = "Service unavailable · no verified protection"
            model.disconnectService()
        }
    }
    func enable() {
        do {
            if try SignedFamily(bundle: Bundle.main.bundleURL).mode == .developer {
                servicePlan = try LocalServiceRegistration.plan(); return
            }
            try SMAppService.agent(plistName: "com.tracerook.agent.plist").register()
            status = "Service registered · waiting for connection"
            if SMAppService.agent(plistName: "com.tracerook.agent.plist").status == .requiresApproval {
                status = "Approve TraceRook in Login Items to start the service"
                SMAppService.openSystemSettingsLoginItems()
            }
            start(); Task { await refresh() }
        } catch { status = "Service registration failed · no verified protection" }
    }
    func confirmLocalService() {
        guard let plan = servicePlan else { return }
        Task {
            do {
                try await Task.detached { try LocalServiceRegistration.install(plan) }.value
                servicePlan = nil; status = "Local service installed · checking connection"; await refresh()
            } catch { status = "Service installation failed or configuration changed · no verified protection" }
        }
    }
    func disable() async {
        do {
            if try SignedFamily(bundle: Bundle.main.bundleURL).mode == .developer { try await Task.detached { try LocalServiceRegistration.remove() }.value }
            else { try await SMAppService.agent(plistName: "com.tracerook.agent.plist").unregister() }
            status = "Service disabled"
        }
        catch { status = "Service removal failed · check Login Items" }
        client = nil; connected = false; model.disconnectService()
    }
}
