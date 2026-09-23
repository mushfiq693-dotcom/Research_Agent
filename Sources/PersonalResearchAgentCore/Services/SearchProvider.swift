import Foundation

public struct SearchResult: Codable, Identifiable, Sendable {
    public var id: String { url }
    public let title: String
    public let url: String
    public let snippet: String
    public let publishedDate: String?
    public let sourceName: String?
    
    public init(
        title: String,
        url: String,
        snippet: String,
        publishedDate: String? = nil,
        sourceName: String? = nil
    ) {
        self.title = title
        self.url = url
        self.snippet = snippet
        self.publishedDate = publishedDate
        self.sourceName = sourceName
    }
}

public enum SearchFreshness: String, Sendable {
    case pastDay = "pd"
    case pastWeek = "pw"
    case pastMonth = "pm"
    case pastYear = "py"
}

public enum SearchProviderError: LocalizedError, Sendable {
    case missingApiKey
    case invalidApiKey(String)
    case quotaExceeded(String)
    case queryTooLong
    case networkError(String)
    case serverError(statusCode: Int, message: String)
    
    public var errorDescription: String? {
        switch self {
        case .missingApiKey:
            return "Brave Search API key is missing. Please configure it in Settings."
        case .invalidApiKey(let msg):
            return "Invalid Brave Search API key (401/403): \(msg)"
        case .quotaExceeded(let msg):
            return "Brave Search quota or rate limit exceeded: \(msg)"
        case .queryTooLong:
            return "Search query exceeds maximum allowed length (400 characters)."
        case .networkError(let msg):
            return "Search network error: \(msg)"
        case .serverError(let code, let msg):
            return "Search provider error (HTTP \(code)): \(msg)"
        }
    }
}

public protocol SearchProvider: Sendable {
    func searchWeb(
        query: String,
        count: Int,
        freshness: SearchFreshness?
    ) async throws -> [SearchResult]
}
