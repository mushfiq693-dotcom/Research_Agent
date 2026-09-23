import Foundation
import AppKit
import OSLog

@MainActor
public final class WakeObserver: ObservableObject {
    public static let shared = WakeObserver()
    
    private let logger = Logger(subsystem: "com.personalresearchagent.app", category: "WakeObserver")
    private var isObserving = false
    
    public var onMissedRunDetected: (@MainActor () -> Void)?
    
    private init() {}
    
    public func start() {
        guard !isObserving else { return }
        isObserving = true
        
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleWakeNotification),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        
        logger.info("WakeObserver registered for system wake notifications.")
        evaluateMissedRunOnStartup()
    }
    
    public func stop() {
        guard isObserving else { return }
        NSWorkspace.shared.notificationCenter.removeObserver(self, name: NSWorkspace.didWakeNotification, object: nil)
        isObserving = false
    }
    
    @objc private func handleWakeNotification() {
        logger.info("System wake detected. Evaluating missed run status...")
        evaluateMissedRun()
    }
    
    public func evaluateMissedRunOnStartup() {
        logger.info("Evaluating missed run on application launch...")
        evaluateMissedRun()
    }
    
    public func evaluateMissedRun() {
        let store = SettingsStore.shared
        guard store.runMissedResearch else {
            logger.info("Missed research catch-up is disabled by user.")
            SchedulerService.shared.recalculateAndArm()
            return
        }
        
        guard let scheduled = SchedulerService.shared.nextRunAt else {
            SchedulerService.shared.recalculateAndArm()
            return
        }
        
        let now = Date()
        // If scheduled time has already passed (e.g. while Mac was sleeping or app was closed)
        if now > scheduled {
            logger.info("Detected missed scheduled run (scheduled: \(scheduled.description), now: \(now.description)). Triggering single catch-up run.")
            
            // Advance schedule first to avoid duplicate triggers
            SchedulerService.shared.recalculateAndArm()
            
            if let handler = onMissedRunDetected {
                handler()
            }
        } else {
            logger.info("No missed runs. Next run is in the future: \(scheduled.description)")
            SchedulerService.shared.recalculateAndArm()
        }
    }
}
