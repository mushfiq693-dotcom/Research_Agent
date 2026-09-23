import Foundation
import OSLog

@MainActor
public final class SchedulerService: ObservableObject {
    public static let shared = SchedulerService()
    
    private let logger = Logger(subsystem: "com.personalresearchagent.app", category: "SchedulerService")
    private let defaults = UserDefaults.standard
    
    private enum Keys {
        static let nextRunAt = "pra_persisted_next_run_at"
        static let lastRunAt = "pra_persisted_last_run_at"
    }
    
    @Published public private(set) var nextRunAt: Date?
    @Published public private(set) var lastRunAt: Date?
    
    private var timer: Timer?
    public var onScheduleTriggered: (@MainActor () -> Void)?
    
    private init() {
        if let next = defaults.object(forKey: Keys.nextRunAt) as? Date {
            self.nextRunAt = next
        }
        if let last = defaults.object(forKey: Keys.lastRunAt) as? Date {
            self.lastRunAt = last
        }
    }
    
    public func start() {
        recalculateAndArm()
    }
    
    public func recalculateAndArm() {
        let next = calculateNextRun(from: Date())
        self.nextRunAt = next
        defaults.set(next, forKey: Keys.nextRunAt)
        
        let formatted = formatNextRunText(next)
        AppState.shared.status = .idle(nextRunText: formatted)
        
        armTimer(for: next)
        logger.info("Scheduler armed for next run at: \(next.description) (\(formatted))")
    }
    
    public func recordRunCompleted(at date: Date = Date()) {
        self.lastRunAt = date
        defaults.set(date, forKey: Keys.lastRunAt)
        recalculateAndArm()
    }
    
    private func armTimer(for targetDate: Date) {
        timer?.invalidate()
        let interval = max(1.0, targetDate.timeIntervalSince(Date()))
        
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleTimerFired()
            }
        }
    }
    
    private func handleTimerFired() {
        logger.info("Scheduled trigger fired.")
        if let handler = onScheduleTriggered {
            handler()
        }
    }
    
    // MARK: - Calculation Engine
    public func calculateNextRun(from now: Date) -> Date {
        let store = SettingsStore.shared
        
        #if DEBUG
        if store.isDebugIntervalMode {
            return now.addingTimeInterval(120) // 2 minutes in debug mode
        }
        #endif
        
        let calendar = Calendar.current
        var targetComponents = DateComponents()
        targetComponents.hour = store.scheduleHour
        targetComponents.minute = store.scheduleMinute
        targetComponents.second = 0
        
        if store.scheduleFrequency == .daily {
            // Check if today's time is in the future
            if let todayTarget = calendar.nextDate(
                after: now,
                matching: targetComponents,
                matchingPolicy: .nextTime,
                repeatedTimePolicy: .first,
                direction: .forward
            ) {
                return todayTarget
            }
        } else if store.scheduleFrequency == .weekly {
            targetComponents.weekday = store.scheduleWeekday.rawValue
            if let weeklyTarget = calendar.nextDate(
                after: now,
                matching: targetComponents,
                matchingPolicy: .nextTime,
                repeatedTimePolicy: .first,
                direction: .forward
            ) {
                return weeklyTarget
            }
        }
        
        // Fallback default: tomorrow at 8:00 AM
        return now.addingTimeInterval(86400)
    }
    
    // MARK: - Human-Readable UI Formatter
    public func formatNextRunText(_ date: Date) -> String {
        let store = SettingsStore.shared
        #if DEBUG
        if store.isDebugIntervalMode {
            let diffSec = max(0, Int(date.timeIntervalSince(Date())))
            return "In \(diffSec)s (Debug 2m)"
        }
        #endif
        
        let calendar = Calendar.current
        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short
        
        if calendar.isDateInToday(date) {
            return timeFormatter.string(from: date)
        } else if calendar.isDateInTomorrow(date) {
            return "Tomorrow at \(timeFormatter.string(from: date))"
        } else {
            let dayFormatter = DateFormatter()
            dayFormatter.dateFormat = "EEEE 'at' h:mm a"
            return dayFormatter.string(from: date)
        }
    }
}
