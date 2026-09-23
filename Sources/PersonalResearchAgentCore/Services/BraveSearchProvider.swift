import Foundation
import OSLog

public final class BraveSearchProvider: SearchProvider, Sendable {
    public static let shared = BraveSearchProvider()
    
    private let endpoint = URL(string: "https://api.search.brave.com/res/v1/web/search")!
    private let logger = Logger(subsystem: "com.personalresearchagent.app", category: "BraveSearchProvider")
    
    public init() {}
    
    public func searchWeb(
        query: String,
        count: Int = 5,
        freshness: SearchFreshness? = nil
    ) async throws -> [SearchResult] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return [] }
        guard trimmedQuery.count <= 400 else { throw SearchProviderError.queryTooLong }
        
        guard let apiKey = KeychainService.shared.getKey(.braveSearch), !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SearchProviderError.missingApiKey
        }
        
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "q", value: trimmedQuery),
            URLQueryItem(name: "count", value: String(min(max(count, 1), 20))),
            URLQueryItem(name: "safesearch", value: "moderate")
        ]
        if let fresh = freshness {
            queryItems.append(URLQueryItem(name: "freshness", value: fresh.rawValue))
        }
        components.queryItems = queryItems
        
        guard let requestURL = components.url else {
            throw SearchProviderError.networkError("Invalid search URL construction.")
        }
        
        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "X-Subscription-Token")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        
        logger.info("Sending Brave Search query: '\(trimmedQuery)' (count: \(count))")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SearchProviderError.networkError("No HTTP response received.")
        }
        
        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw SearchProviderError.invalidApiKey(body)
        }
        if httpResponse.statusCode == 429 {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw SearchProviderError.quotaExceeded(body)
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw SearchProviderError.serverError(statusCode: httpResponse.statusCode, message: body)
        }
        
        // Parse Brave Web Search response
        return try Self.parseBraveResponse(data)
    }
    
    // MARK: - Parsing & Canonicalization
    public static func parseBraveResponse(_ data: Data) throws -> [SearchResult] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let web = json["web"] as? [String: Any],
              let results = web["results"] as? [[String: Any]] else {
            return []
        }
        
        var parsed: [SearchResult] = []
        for item in results {
            guard let rawUrl = item["url"] as? String,
                  let title = item["title"] as? String,
                  let description = item["description"] as? String else {
                continue
            }
            
            let canonicalURL = canonicalizeURLString(rawUrl)
            let age = item["age"] as? String ?? (item["page_age"] as? String)
            let profile = item["profile"] as? [String: Any]
            let sourceName = profile?["name"] as? String
            
            let result = SearchResult(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                url: canonicalURL,
                snippet: description.trimmingCharacters(in: .whitespacesAndNewlines),
                publishedDate: age,
                sourceName: sourceName
            )
            parsed.append(result)
        }
        return parsed
    }
    
    public static func canonicalizeURLString(_ urlString: String) -> String {
        guard var components = URLComponents(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return urlString
        }
        
        // Lowercase scheme and host
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        
        // Remove tracking query parameters
        let trackingKeys: Set<String> = [
            "utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content",
            "fbclid", "gclid", "ref", "source", "feature", "spm"
        ]
        
        if let queryItems = components.queryItems {
            let filtered = queryItems.filter { !trackingKeys.contains($0.name.lowercased()) }
            components.queryItems = filtered.isEmpty ? nil : filtered
        }
        
        // Remove fragment
        components.fragment = nil
        
        return components.string ?? urlString
    }
}
