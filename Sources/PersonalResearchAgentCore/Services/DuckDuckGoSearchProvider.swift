import Foundation
import OSLog

public final class DuckDuckGoSearchProvider: SearchProvider, Sendable {
    public static let shared = DuckDuckGoSearchProvider()
    
    private let endpoint = URL(string: "https://lite.duckduckgo.com/lite/")!
    private let logger = Logger(subsystem: "com.personalresearchagent.app", category: "DuckDuckGoSearchProvider")
    
    public init() {}
    
    public func searchWeb(
        query: String,
        count: Int = 5,
        freshness: SearchFreshness? = nil
    ) async throws -> [SearchResult] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return [] }
        guard trimmedQuery.count <= 400 else { throw SearchProviderError.queryTooLong }
        
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.timeoutInterval = 15
        
        let postBodyString = "q=" + (trimmedQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmedQuery)
        request.httpBody = postBodyString.data(using: .utf8)
        
        logger.info("Executing DuckDuckGo Free Search for: '\(trimmedQuery)' (target count: \(count))")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                logger.warning("DuckDuckGo Lite returned non-200, trying Google News RSS fallback...")
                return try await searchGoogleNewsRSS(query: trimmedQuery, count: count)
            }
            
            let htmlString = String(data: data, encoding: .utf8) ?? ""
            let results = Self.parseDuckDuckGoLiteHTML(htmlString)
            
            if !results.isEmpty {
                return Array(results.prefix(count))
            } else {
                logger.info("DuckDuckGo Lite returned 0 results, falling back to Google News RSS...")
                return try await searchGoogleNewsRSS(query: trimmedQuery, count: count)
            }
        } catch {
            logger.warning("DuckDuckGo request failed (\(error.localizedDescription)), falling back to Google News RSS...")
            return try await searchGoogleNewsRSS(query: trimmedQuery, count: count)
        }
    }
    
    // MARK: - DuckDuckGo Lite HTML Parser
    public static func parseDuckDuckGoLiteHTML(_ html: String) -> [SearchResult] {
        var results: [SearchResult] = []
        
        // Pattern 1: Link & Title -> <a rel="nofollow" href="(url)" class='result-link'>(title)</a>
        // Pattern 2: Snippet -> <td class='result-snippet'>(snippet)</td>
        
        let linkPattern = #"<a[^>]*href=["']([^"']+)["'][^>]*class=['"]result-link['"][^>]*>([\s\S]*?)<\/a>"#
        let snippetPattern = #"<td[^>]*class=['"]result-snippet['"][^>]*>([\s\S]*?)<\/td>"#
        
        guard let linkRegex = try? NSRegularExpression(pattern: linkPattern, options: .caseInsensitive),
              let snippetRegex = try? NSRegularExpression(pattern: snippetPattern, options: .caseInsensitive) else {
            return []
        }
        
        let nsHtml = html as NSString
        let linkMatches = linkRegex.matches(in: html, options: [], range: NSRange(location: 0, length: nsHtml.length))
        let snippetMatches = snippetRegex.matches(in: html, options: [], range: NSRange(location: 0, length: nsHtml.length))
        
        for (index, match) in linkMatches.enumerated() {
            guard match.numberOfRanges >= 3 else { continue }
            let rawUrl = nsHtml.substring(with: match.range(at: 1))
            let rawTitle = nsHtml.substring(with: match.range(at: 2))
            
            var snippet = ""
            if index < snippetMatches.count && snippetMatches[index].numberOfRanges >= 2 {
                snippet = nsHtml.substring(with: snippetMatches[index].range(at: 1))
            }
            
            let cleanTitle = stripHTMLAndDecode(rawTitle)
            let cleanSnippet = stripHTMLAndDecode(snippet)
            let cleanURL = unwrapDuckDuckGoURL(rawUrl)
            
            guard !cleanURL.isEmpty, cleanURL.hasPrefix("http") else { continue }
            
            let canonicalURL = BraveSearchProvider.canonicalizeURLString(cleanURL)
            let result = SearchResult(
                title: cleanTitle.isEmpty ? canonicalURL : cleanTitle,
                url: canonicalURL,
                snippet: cleanSnippet.isEmpty ? cleanTitle : cleanSnippet,
                publishedDate: nil,
                sourceName: URL(string: canonicalURL)?.host
            )
            results.append(result)
        }
        
        return results
    }
    
    // MARK: - Google News RSS Fallback (Zero-Key)
    public func searchGoogleNewsRSS(query: String, count: Int) async throws -> [SearchResult] {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://news.google.com/rss/search?q=\(encoded)&hl=en-US&gl=US&ceid=US:en") else {
            return []
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            return []
        }
        
        let xmlString = String(data: data, encoding: .utf8) ?? ""
        return Array(Self.parseRSSItems(xmlString).prefix(count))
    }
    
    public static func parseRSSItems(_ xml: String) -> [SearchResult] {
        var results: [SearchResult] = []
        let itemPattern = #"<item>([\s\S]*?)<\/item>"#
        guard let itemRegex = try? NSRegularExpression(pattern: itemPattern, options: .caseInsensitive) else {
            return []
        }
        
        let nsXml = xml as NSString
        let matches = itemRegex.matches(in: xml, options: [], range: NSRange(location: 0, length: nsXml.length))
        
        for match in matches {
            guard match.numberOfRanges >= 2 else { continue }
            let itemContent = nsXml.substring(with: match.range(at: 1))
            
            let title = extractTag("title", from: itemContent)
            let link = extractTag("link", from: itemContent)
            let pubDate = extractTag("pubDate", from: itemContent)
            let description = extractTag("description", from: itemContent)
            let source = extractTag("source", from: itemContent)
            
            guard !link.isEmpty else { continue }
            
            let cleanTitle = stripHTMLAndDecode(title)
            let cleanSnippet = stripHTMLAndDecode(description)
            let canonicalURL = BraveSearchProvider.canonicalizeURLString(link)
            
            results.append(SearchResult(
                title: cleanTitle.isEmpty ? canonicalURL : cleanTitle,
                url: canonicalURL,
                snippet: cleanSnippet.isEmpty ? cleanTitle : cleanSnippet,
                publishedDate: pubDate.isEmpty ? nil : pubDate,
                sourceName: source.isEmpty ? URL(string: canonicalURL)?.host : source
            ))
        }
        return results
    }
    
    private static func extractTag(_ tag: String, from text: String) -> String {
        let pattern = "<\(tag)[^>]*>([\\s\\S]*?)<\\/\(tag)>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return "" }
        let nsText = text as NSString
        if let match = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: nsText.length)),
           match.numberOfRanges >= 2 {
            return nsText.substring(with: match.range(at: 1))
        }
        return ""
    }
    
    private static func stripHTMLAndDecode(_ text: String) -> String {
        var result = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        result = result.replacingOccurrences(of: "&amp;", with: "&")
        result = result.replacingOccurrences(of: "&lt;", with: "<")
        result = result.replacingOccurrences(of: "&gt;", with: ">")
        result = result.replacingOccurrences(of: "&quot;", with: "\"")
        result = result.replacingOccurrences(of: "&#x27;", with: "'")
        result = result.replacingOccurrences(of: "&#39;", with: "'")
        result = result.replacingOccurrences(of: "&nbsp;", with: " ")
        result = result.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private static func unwrapDuckDuckGoURL(_ rawUrl: String) -> String {
        // DDG Lite URLs often have /l/?uddg=<encoded_actual_url>&rut=...
        if rawUrl.contains("uddg=") {
            if let components = URLComponents(string: rawUrl.hasPrefix("//") ? "https:" + rawUrl : rawUrl),
               let queryItems = components.queryItems,
               let actual = queryItems.first(where: { $0.name == "uddg" })?.value {
                return actual
            }
        }
        if rawUrl.hasPrefix("//") {
            return "https:" + rawUrl
        }
        return rawUrl
    }
}
