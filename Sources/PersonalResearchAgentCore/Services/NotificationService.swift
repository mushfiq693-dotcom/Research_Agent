import Foundation
import UserNotifications
import AppKit
import OSLog

@MainActor
public final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    public static let shared = NotificationService()
    
    private let logger = Logger(subsystem: "com.personalresearchagent.app", category: "NotificationService")
    
    public static let categoryResearchCompleted = "PRA_CATEGORY_RESEARCH_COMPLETED"
    public static let actionOpenReport = "PRA_ACTION_OPEN_REPORT"
    
    private override init() {
        super.init()
    }
    
    public func setup() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        
        let openAction = UNNotificationAction(
            identifier: Self.actionOpenReport,
            title: "Open Report",
            options: [.foreground]
        )
        
        let completedCategory = UNNotificationCategory(
            identifier: Self.categoryResearchCompleted,
            actions: [openAction],
            intentIdentifiers: [],
            options: []
        )
        
        center.setNotificationCategories([completedCategory])
    }
    
    public func requestAuthorization() async -> Bool {
        do {
            let center = UNUserNotificationCenter.current()
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            logger.info("Notification authorization granted: \(granted)")
            return granted
        } catch {
            logger.warning("Failed to request notification authorization: \(error.localizedDescription)")
            return false
        }
    }
    
    public func sendCompletionNotification(topic: String, reportURL: URL) {
        guard SettingsStore.shared.notificationsEnabled else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "Daily AI Research Ready"
        content.body = "Research completed on '\(topic)'. Click to view your briefing."
        content.sound = .default
        content.categoryIdentifier = Self.categoryResearchCompleted
        content.userInfo = ["reportPath": reportURL.path]
        
        let request = UNNotificationRequest(
            identifier: "PRA_COMPLETE_\(UUID().uuidString)",
            content: content,
            trigger: nil // Immediate delivery
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                Logger(subsystem: "com.personalresearchagent.app", category: "NotificationService")
                    .warning("Failed to deliver completion notification: \(error.localizedDescription)")
            }
        }
    }
    
    public func sendFailureNotification(topic: String, reason: String) {
        guard SettingsStore.shared.notificationsEnabled else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "Research Run Failed"
        content.body = "Research for '\(topic)' could not be completed: \(reason.prefix(100))"
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: "PRA_FAIL_\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                Logger(subsystem: "com.personalresearchagent.app", category: "NotificationService")
                    .warning("Failed to deliver failure notification: \(error.localizedDescription)")
            }
        }
    }
    
    public func sendOfflineRetryExhaustedNotification(topic: String) {
        guard SettingsStore.shared.notificationsEnabled else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "Research Postponed (Offline)"
        content.body = "Could not connect to the internet after 3 retries. Will try again at the next schedule."
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: "PRA_OFFLINE_\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
    
    // MARK: - UNUserNotificationCenterDelegate
    nonisolated public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        if let path = userInfo["reportPath"] as? String {
            let url = URL(fileURLWithPath: path)
            Task { @MainActor in
                if FileManager.default.fileExists(atPath: path) {
                    NSWorkspace.shared.open(url)
                }
            }
        }
        completionHandler()
    }
    
    nonisolated public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show banner even when app is active
        completionHandler([.banner, .sound])
    }
}
