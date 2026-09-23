import Foundation
import PersonalResearchAgentCore

public struct SettingsAndKeychainTests {
    
    public static func runAll() async throws {
        print("\n--- Running SettingsAndKeychainTests ---")
        try testKeychainRedaction()
        await testSettingsStoreDefaultsAndCustomTopic()
        await testAppStateStatusTransitions()
        print("✅ SettingsAndKeychainTests passed successfully.")
    }
    
    public static func testKeychainRedaction() throws {
        let secret = "sk-or-v1-abcdef1234567890ghijkl"
        let redacted = KeychainService.redact(secret)
        assert(redacted.hasPrefix("sk-o"), "Redacted secret should retain prefix")
        assert(redacted.hasSuffix("jkl"), "Redacted secret should retain suffix")
        assert(redacted.contains("..."), "Redacted secret should contain dots")
        assert(!redacted.contains("1234567890"), "Redacted secret must not reveal sensitive content")
        
        let shortSecret = "short"
        assert(KeychainService.redact(shortSecret) == "******", "Short secret should be fully masked")
        print("  ✓ testKeychainRedaction passed")
    }
    
    @MainActor
    public static func testSettingsStoreDefaultsAndCustomTopic() {
        let store = SettingsStore.shared
        
        // Test depth limits
        assert(ResearchDepth.quick.maxIterations == 1, "Quick depth iterations")
        assert(ResearchDepth.standard.maxIterations == 2, "Standard depth iterations")
        assert(ResearchDepth.deep.maxIterations == 3, "Deep depth iterations")
        
        assert(ResearchDepth.standard.maxSearchQueries == 6, "Standard depth queries")
        assert(ResearchDepth.standard.maxPagesFetched == 8, "Standard depth pages")
        assert(ResearchDepth.standard.maxModelCalls == 8, "Standard depth model calls")
        
        // Preset topic
        store.topicPreset = .aiNews
        assert(store.activeTopic == "Latest AI news", "Preset topic matches")
        
        // Custom topic
        store.topicPreset = .custom
        store.customTopic = "Quantum Computing Advancements"
        assert(store.activeTopic == "Quantum Computing Advancements", "Custom topic matches")
        print("  ✓ testSettingsStoreDefaultsAndCustomTopic passed")
    }
    
    @MainActor
    public static func testAppStateStatusTransitions() {
        let state = AppState.shared
        
        state.status = .idle(nextRunText: "08:00 AM")
        assert(state.status.displayText == "Agent is active. Next research: 08:00 AM")
        assert(state.status.iconName == "sparkles")
        
        state.status = .researching(step: .planning)
        assert(state.status.displayText == "Researching... Current step: Planning")
        
        state.status = .researching(step: .searching)
        assert(state.status.displayText == "Researching... Current step: Searching web")
        
        state.status = .offline
        assert(state.status.displayText == "Waiting for internet connection")
        assert(state.status.iconName == "wifi.slash")
        
        state.status = .rateLimited(retryInSeconds: 45)
        assert(state.status.displayText == "Waiting for free-tier rate limit (45s)")
        
        state.status = .failed(reason: "Invalid API Key")
        assert(state.status.displayText == "Research failed. Reason: Invalid API Key")
        print("  ✓ testAppStateStatusTransitions passed")
    }
}
