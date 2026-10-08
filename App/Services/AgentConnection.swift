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
    private(set) var cloud = LiveCloudStatus()
    private(set) var localAPI = LocalAPIDemoStatus()
    private(set) var localAPIBusy = false
    private var client: XPCClient?
    private let model: DesktopModel
    private var refreshTask: Task<Void, Never>?
    private var localAPIGeneration = 0
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
            let cloudReply = try await command(.liveCloud, payload: try JSONValue.decodeBounded(WireCodec.encodePayload(LiveCloudControl(operation: .status), maximumBytes: WireLimits.replyBytes)))
            cloud = try WireCodec.decodePayload(LiveCloudStatus.self, payload: cloudReply.payload.canonicalData(), maximumBytes: WireLimits.replyBytes)
            status = snapshot.securityMode == .developer ? "Connected · local ad-hoc signatures · non-notarized" : "Connected · Developer ID"
        } catch {
            client = nil; connected = false; status = "Service unavailable · no verified protection"
            model.disconnectService()
            cloud = LiveCloudStatus(failure: .unavailable)
            localAPI = LocalAPIDemoStatus(failure: .unavailable)
            localAPIGeneration += 1; localAPIBusy = false
        }
    }
    func localAPICommand(_ operation: LocalAPIDemoOperation, request: LocalAPIDemoRequest? = nil) async {
        guard connected, !localAPIBusy || operation == .disconnect || operation == .delete else { return }
        localAPIGeneration += 1
        let generation = localAPIGeneration
        localAPIBusy = true
        defer { if generation == localAPIGeneration { localAPIBusy = false } }
        do {
            let command = LocalAPIDemoControl(operation: operation, request: request)
            let payload = try JSONValue.decodeBounded(WireCodec.encodePayload(command, maximumBytes: WireLimits.replyBytes))
            let reply = try await self.command(.localAPIDemo, payload: payload)
            let status = try WireCodec.decodePayload(LocalAPIDemoStatus.self, payload: reply.payload.canonicalData(), maximumBytes: WireLimits.replyBytes)
            if generation == localAPIGeneration && connected { localAPI = status }
        } catch { if generation == localAPIGeneration { cloud = LiveCloudStatus(failure: .unavailable)
            localAPI = LocalAPIDemoStatus(failure: .unavailable) } }
    }
    func cloudCommand(_ operation: LiveCloudOperation, invitation: String? = nil, consent: CloudConsent? = nil) async {
        guard connected else { return }
        do {
            let control = LiveCloudControl(operation: operation, invitation: invitation, consent: consent)
            let payload = try JSONValue.decodeBounded(WireCodec.encodePayload(control, maximumBytes: WireLimits.replyBytes))
            let reply = try await command(.liveCloud, payload: payload)
            cloud = try WireCodec.decodePayload(LiveCloudStatus.self, payload: reply.payload.canonicalData(), maximumBytes: WireLimits.replyBytes)
        } catch { cloud = LiveCloudStatus(failure: .unavailable) }
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
        cloud = LiveCloudStatus()
        localAPI = LocalAPIDemoStatus()
        localAPIGeneration += 1; localAPIBusy = false
    }
}
