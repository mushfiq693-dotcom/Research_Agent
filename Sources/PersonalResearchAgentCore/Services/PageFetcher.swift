import Foundation
import OSLog

public struct ExtractedPage: Sendable {
    public let url: URL
    public let title: String
    public let text: String
    public let publishedDate: String?
    public let isTruncated: Bool
    
    public init(
        url: URL,
        title: String,
        text: String,
        publishedDate: String? = nil,
        isTruncated: Bool = false
    ) {
        self.url = url
        self.title = title
        self.text = text
        self.publishedDate = publishedDate
        self.isTruncated = isTruncated
    }
}

public protocol PageFetcherProtocol: Sendable {
    func fetchWebPage(url: URL, maxCharacters: Int) async throws -> ExtractedPage
}

public final class PageFetcher: PageFetcherProtocol, Sendable {
    public static let shared = PageFetcher()
    
    private let logger = Logger(subsystem: "com.personalresearchagent.app", category: "PageFetcher")
    
    public init() {}
    
    public func fetchWebPage(url: URL, maxCharacters: Int = 12_000) async throws -> ExtractedPage {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        
        logger.info("Fetching webpage: \(url.absoluteString)")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            logger.warning("Failed to fetch webpage \(url.absoluteString): HTTP \(code)")
            throw URLError(.badServerResponse)
        }
        
        let htmlString = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? String(data: data, encoding: .windowsCP1252)
            ?? ""
        
        return HTMLExtractor.extract(from: htmlString, url: url, maxCharacters: maxCharacters)
    }
}

public final class HTMLExtractor: Sendable {
    
    public static func extract(from html: String, url: URL, maxCharacters: Int = 12_000) -> ExtractedPage {
        var processed = html
        
        // 1. Extract title before stripping tags
        var pageTitle = ""
        if let titleRegex = try? NSRegularExpression(pattern: "<title[^>]*>([\\s\\S]*?)</title>", options: [.caseInsensitive]) {
            let range = NSRange(processed.startIndex..<processed.endIndex, in: processed)
            if let match = titleRegex.firstMatch(in: processed, options: [], range: range),
               let titleRange = Range(match.range(at: 1), in: processed) {
                pageTitle = String(processed[titleRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        if pageTitle.isEmpty {
            if let h1Regex = try? NSRegularExpression(pattern: "<h1[^>]*>([\\s\\S]*?)</h1>", options: [.caseInsensitive]) {
                let range = NSRange(processed.startIndex..<processed.endIndex, in: processed)
                if let match = h1Regex.firstMatch(in: processed, options: [], range: range),
                   let h1Range = Range(match.range(at: 1), in: processed) {
                    pageTitle = String(processed[h1Range]).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
        
        if pageTitle.isEmpty {
            pageTitle = url.host ?? url.lastPathComponent
        }
        
        // 2. Strip non-content blocks: script, style, nav, footer, header, svg, noscript, iframe, form
        let stripTags = ["script", "style", "nav", "footer", "header", "svg", "noscript", "iframe", "form"]
        for tag in stripTags {
            if let regex = try? NSRegularExpression(pattern: "<\(tag)[^>]*>[\\s\\S]*?</\(tag)>", options: [.caseInsensitive]) {
                let range = NSRange(processed.startIndex..<processed.endIndex, in: processed)
                processed = regex.stringByReplacingMatches(in: processed, options: [], range: range, withTemplate: " ")
            }
        }
        
        // 3. Strip HTML comments: <!-- ... -->
        if let commentRegex = try? NSRegularExpression(pattern: "<!--[\\s\\S]*?-->", options: []) {
            let range = NSRange(processed.startIndex..<processed.endIndex, in: processed)
            processed = commentRegex.stringByReplacingMatches(in: processed, options: [], range: range, withTemplate: " ")
        }
        
        // 4. Replace block elements (<p>, <br>, <div>, <h1>-<h6>, <li>, <tr>) with linebreaks
        if let blockRegex = try? NSRegularExpression(pattern: "<(?:/p|/div|br|/h[1-6]|/li|/tr)[^>]*>", options: [.caseInsensitive]) {
            let range = NSRange(processed.startIndex..<processed.endIndex, in: processed)
            processed = blockRegex.stringByReplacingMatches(in: processed, options: [], range: range, withTemplate: "\n")
        }
        
        // 5. Strip all remaining inline HTML tags
        if let tagRegex = try? NSRegularExpression(pattern: "<[^>]+>", options: []) {
            let range = NSRange(processed.startIndex..<processed.endIndex, in: processed)
            processed = tagRegex.stringByReplacingMatches(in: processed, options: [], range: range, withTemplate: "")
        }
        
        // 6. Decode common HTML entities
        processed = unescapeHTMLEntities(processed)
        
        // 7. Normalize whitespace per line and remove empty lines
        let rawLines = processed.components(separatedBy: .newlines)
        var cleanedLines: [String] = []
        for line in rawLines {
            let normalizedLine = line.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
            if !normalizedLine.isEmpty {
                cleanedLines.append(normalizedLine)
            }
        }
        
        let cleanedText = cleanedLines.joined(separator: "\n")
        
        // 8. Truncation to character budget
        let isTruncated = cleanedText.count > maxCharacters
        let finalText = isTruncated ? String(cleanedText.prefix(maxCharacters)) + "\n...[Content Truncated]" : cleanedText
        
        return ExtractedPage(
            url: url,
            title: unescapeHTMLEntities(pageTitle),
            text: finalText,
            publishedDate: nil,
            isTruncated: isTruncated
        )
    }
    
    public static func unescapeHTMLEntities(_ text: String) -> String {
        var str = text
        str = str.replacingOccurrences(of: "&nbsp;", with: " ")
        str = str.replacingOccurrences(of: "&amp;", with: "&")
        str = str.replacingOccurrences(of: "&lt;", with: "<")
        str = str.replacingOccurrences(of: "&gt;", with: ">")
        str = str.replacingOccurrences(of: "&quot;", with: "\"")
        str = str.replacingOccurrences(of: "&#39;", with: "'")
        str = str.replacingOccurrences(of: "&apos;", with: "'")
        str = str.replacingOccurrences(of: "&#x27;", with: "'")
        str = str.replacingOccurrences(of: "&#x2F;", with: "/")
        str = str.replacingOccurrences(of: "&mdash;", with: "—")
        str = str.replacingOccurrences(of: "&ndash;", with: "–")
        return str
    }
}
