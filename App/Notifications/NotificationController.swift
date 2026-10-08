import Foundation
import Observation
import UserNotifications

@MainActor @Observable
final class NotificationController: NSObject, UNUserNotificationCenterDelegate {
    var status = "Not requested"
    var onReview: (@MainActor (UUID) -> Void)?
    var onBlock: (@MainActor (UUID) -> Void)?
    override init() {
        super.init()
        let center = UNUserNotificationCenter.current(); center.delegate = self
        let review = UNNotificationAction(identifier: "REVIEW", title: "Review", options: [.foreground])
        let block = UNNotificationAction(identifier: "BLOCK", title: "Block", options: [])
        let category = UNNotificationCategory(identifier: "DEMO_REVIEW_REQUIRED", actions: [review, block], intentIdentifiers: [])
        center.setNotificationCategories([category])
    }
    func refreshStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        status = switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: "Allowed"
        case .denied: "Denied · use the approval queue"
        case .notDetermined: "Not requested"
        @unknown default: "Unavailable"
        }
    }
    func requestPermission() async {
        do { _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) }
        catch { status = "Unavailable · use the approval queue"; return }
        await refreshStatus()
    }
    func notifyDemoApproval(id: UUID) async {
        await refreshStatus()
        guard status == "Allowed" else { return }
        let content = UNMutableNotificationContent()
        content.title = "TraceRook Demo · Review required"
        content.body = "A simulated action needs review. No real tool call is running."
        content.categoryIdentifier = "DEMO_REVIEW_REQUIRED"
        content.userInfo = ["demo_approval_id": id.uuidString]
        do { try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id.uuidString, content: content, trigger: nil)) }
        catch { status = "Delivery unavailable · use the approval queue" }
    }
    func remove(id: UUID) {
        let center = UNUserNotificationCenter.current()
        center.removeDeliveredNotifications(withIdentifiers: [id.uuidString])
        center.removePendingNotificationRequests(withIdentifiers: [id.uuidString])
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let id = (response.notification.request.content.userInfo["demo_approval_id"] as? String).flatMap(UUID.init(uuidString:))
        let action = response.actionIdentifier
        Task { @MainActor [weak self] in
            if let id {
                if action == "BLOCK" { self?.onBlock?(id) } else { self?.onReview?(id) }
            }
        }
        completionHandler()
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
