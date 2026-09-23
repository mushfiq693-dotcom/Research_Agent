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

print("\n==========================================")
print(" Test Summary: \(totalPassed) suite(s) passed, \(totalFailed) suite(s) failed")
print("==========================================")

if totalFailed > 0 {
    exit(1)
} else {
    exit(0)
}
