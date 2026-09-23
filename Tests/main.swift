import Foundation

print("==========================================")
print(" Personal Research Agent - Test Suite ")
print("==========================================")

var totalPassed = 0
var totalFailed = 0

// Test Suite 1: Settings & Keychain
do {
    try await SettingsAndKeychainTests.runAll()
    totalPassed += 1
} catch {
    print("❌ SettingsAndKeychainTests failed with error: \(error)")
    totalFailed += 1
}

// Test Suite 2: Core Services (OpenRouter, Tolerant JSON, Reasoning Tags, Brave Search, PageFetcher, HTML)
do {
    try await ServiceTests.runAll()
    totalPassed += 1
} catch {
    print("❌ ServiceTests failed with error: \(error)")
    totalFailed += 1
}

// Test Suite 3: Agent Loop, Security, Prompt Injection, URL Whitelist, ReportWriter, Memory
do {
    try await AgentTests.runAll()
    totalPassed += 1
} catch {
    print("❌ AgentTests failed with error: \(error)")
    totalFailed += 1
}

// Test Suite 4: Scheduler, WakeObserver, Missed Runs, Notification Categories
do {
    try await SchedulerAndNotificationTests.runAll()
    totalPassed += 1
} catch {
    print("❌ SchedulerAndNotificationTests failed with error: \(error)")
    totalFailed += 1
}

// Test Suite 5: Acceptance & Edge-Case Resilience (Fallback models, offline recovery, missed run catchup, session persistence)
do {
    try await AcceptanceTests.runAll()
    totalPassed += 1
} catch {
    print("❌ AcceptanceTests failed with error: \(error)")
    totalFailed += 1
}

print("\n==========================================")
print(" Test Summary: \(totalPassed) suite(s) passed, \(totalFailed) suite(s) failed")
print("==========================================")

if totalFailed > 0 {
    exit(1)
} else {
    exit(0)
}
