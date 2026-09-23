import Foundation
import OSLog

public final class UnifiedSearchProvider: SearchProvider, Sendable {
    public static let shared = UnifiedSearchProvider()
    
    private let braveProvider = BraveSearchProvider.shared
    private let ddgProvider = DuckDuckGoSearchProvider.shared
    private let logger = Logger(subsystem: "com.personalresearchagent.app", category: "UnifiedSearchProvider")
    
    public init() {}
    
    public func searchWeb(
        query: String,
        count: Int = 5,
        freshness: SearchFreshness? = nil
    ) async throws -> [SearchResult] {
        let braveKey = KeychainService.shared.getKey(.braveSearch)?.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 1. If Brave Search API Key is present, try Brave first
        if let key = braveKey, !key.isEmpty {
            do {
                logger.info("Using Brave Search API...")
                let results = try await braveProvider.searchWeb(query: query, count: count, freshness: freshness)
                if !results.isEmpty {
                    return results
                }
                logger.info("Brave Search returned 0 results, attempting Free DuckDuckGo Search fallback...")
            } catch {
                logger.warning("Brave Search failed (\(error.localizedDescription)), falling back to DuckDuckGo Free Search...")
            }
        }
        
        // 2. Default & Fallback: DuckDuckGo Free Search (zero-key required)
        logger.info("Executing Free Web Search via DuckDuckGo...")
        return try await ddgProvider.searchWeb(query: query, count: count, freshness: freshness)
    }
}
