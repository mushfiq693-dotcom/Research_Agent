import Foundation
import ServiceManagement
import OSLog

@MainActor
public final class LaunchAtLoginService: ObservableObject {
    public static let shared = LaunchAtLoginService()
    
    private let logger = Logger(subsystem: "com.personalresearchagent.app", category: "LaunchAtLoginService")
    
    @Published public private(set) var status: SMAppService.Status = .notRegistered
    @Published public private(set) var isEnabled: Bool = false
    
    private init() {
        refreshStatus()
    }
    
    public func refreshStatus() {
        self.status = SMAppService.mainApp.status
        self.isEnabled = (self.status == .enabled)
    }
    
    public func setEnabled(_ enable: Bool) {
        do {
            if enable {
                if SMAppService.mainApp.status == .enabled {
                    refreshStatus()
                    return
                }
                try SMAppService.mainApp.register()
                logger.info("Successfully registered app for Launch at Login.")
            } else {
                if SMAppService.mainApp.status == .notRegistered {
                    refreshStatus()
                    return
                }
                try SMAppService.mainApp.unregister()
                logger.info("Successfully unregistered app from Launch at Login.")
            }
        } catch {
            logger.error("Failed to update Launch at Login status: \(error.localizedDescription)")
        }
        refreshStatus()
    }
    
    public var statusDescription: String {
        switch status {
        case .enabled:
            return "Enabled"
        case .notRegistered:
            return "Disabled"
        case .requiresApproval:
            return "Requires Approval in macOS System Settings"
        case .notFound:
            return "App Service Not Found"
        @unknown default:
            return "Unknown Status"
        }
    }
    
    public func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
