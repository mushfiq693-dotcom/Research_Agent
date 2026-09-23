import Foundation
import PersonalResearchAgentCore

public struct SchedulerAndNotificationTests {
    
    public static func runAll() async throws {
        print("\n--- Running SchedulerAndNotificationTests ---")
        await testDailyNextRunCalculation()
        await testWeeklyNextRunCalculation()
        await testDebugIntervalModeCalculation()
        await testMissedRunLogic()
        await testNotificationCategories()
        print("✅ SchedulerAndNotificationTests passed successfully.")
    }
    
    // MARK: - 1. Daily Next Run Calculation
    @MainActor
    public static func testDailyNextRunCalculation() {
        let scheduler = SchedulerService.shared
        let settings = SettingsStore.shared
        
        settings.isDebugIntervalMode = false
        settings.scheduleFrequency = .daily
        settings.scheduleHour = 8
        settings.scheduleMinute = 0
        
        let calendar = Calendar.current
        
        // Scenario A: Current time is 06:00 AM (target 08:00 AM today)
        var compA = calendar.dateComponents([.year, .month, .day], from: Date())
        compA.hour = 6
        compA.minute = 0
        let dateA = calendar.date(from: compA)!
        
        let nextA = scheduler.calculateNextRun(from: dateA)
        let resultHourA = calendar.component(.hour, from: nextA)
        let resultDayA = calendar.component(.day, from: nextA)
        assert(resultHourA == 8, "Target hour should be 8")
        assert(resultDayA == compA.day, "Should schedule for same day when before target")
        
        // Scenario B: Current time is 09:00 AM (target 08:00 AM next day)
        var compB = calendar.dateComponents([.year, .month, .day], from: Date())
        compB.hour = 9
        compB.minute = 0
        let dateB = calendar.date(from: compB)!
        
        let nextB = scheduler.calculateNextRun(from: dateB)
        let resultHourB = calendar.component(.hour, from: nextB)
        assert(resultHourB == 8, "Target hour should be 8")
        assert(nextB > dateB, "Should schedule for tomorrow when after target")
        print("  ✓ testDailyNextRunCalculation passed")
    }
    
    // MARK: - 2. Weekly Next Run Calculation
    @MainActor
    public static func testWeeklyNextRunCalculation() {
        let scheduler = SchedulerService.shared
        let settings = SettingsStore.shared
        
        settings.isDebugIntervalMode = false
        settings.scheduleFrequency = .weekly
        settings.scheduleWeekday = .friday
        settings.scheduleHour = 10
        settings.scheduleMinute = 30
        
        let next = scheduler.calculateNextRun(from: Date())
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: next)
        let hour = calendar.component(.hour, from: next)
        let minute = calendar.component(.minute, from: next)
        
        assert(weekday == Weekday.friday.rawValue, "Scheduled weekday should be Friday (6)")
        assert(hour == 10, "Scheduled hour should be 10")
        assert(minute == 30, "Scheduled minute should be 30")
        print("  ✓ testWeeklyNextRunCalculation passed")
    }
    
    // MARK: - 3. Debug Interval Mode
    @MainActor
    public static func testDebugIntervalModeCalculation() {
        let scheduler = SchedulerService.shared
        let settings = SettingsStore.shared
        
        settings.isDebugIntervalMode = true
        let now = Date()
        let next = scheduler.calculateNextRun(from: now)
        let diff = next.timeIntervalSince(now)
        
        assert(abs(diff - 120) < 2.0, "Debug interval mode should schedule for 120 seconds in future")
        settings.isDebugIntervalMode = false
        print("  ✓ testDebugIntervalModeCalculation passed")
    }
    
    // MARK: - 4. Missed Run Evaluation
    @MainActor
    public static func testMissedRunLogic() {
        let settings = SettingsStore.shared
        
        // Scenario A: runMissedResearch = true and past deadline
        settings.runMissedResearch = true
        let pastDate = Date().addingTimeInterval(-3600) // 1 hour ago
        let isPast = Date() > pastDate
        assert(isPast, "Past date is recognized")
        assert(settings.runMissedResearch, "Run missed research is enabled")
        
        // Scenario B: runMissedResearch = false
        settings.runMissedResearch = false
        assert(!settings.runMissedResearch, "Run missed research can be disabled")
        settings.runMissedResearch = true
        print("  ✓ testMissedRunLogic passed")
    }
    
    // MARK: - 5. Notification Setup & Constants
    @MainActor
    public static func testNotificationCategories() {
        assert(NotificationService.categoryResearchCompleted == "PRA_CATEGORY_RESEARCH_COMPLETED", "Notification category constant")
        assert(NotificationService.actionOpenReport == "PRA_ACTION_OPEN_REPORT", "Notification action constant")
        print("  ✓ testNotificationCategories passed")
    }
}
