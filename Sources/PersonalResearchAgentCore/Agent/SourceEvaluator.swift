import Foundation

public final class SourceEvaluator: Sendable {
    
    public static let highAuthorityDomains: Set<String> = [
        "arxiv.org", "nature.com", "science.org", "ieee.org", "acm.org",
        "github.com", "developer.apple.com", "apple.com", "openai.com", "anthropic.com",
        "deepmind.google", "blog.google", "ai.meta.com", "microsoft.com",
        "reuters.com", "bloomberg.com", "apnews.com", "techcrunch.com", "theverge.com",
        "arstechnica.com", "wired.com", "venturebeat.com", "technologyreview.com"
    ]
    
    public init() {}
    
    public static func evaluateAndRank(
        results: [SearchResult],
        subQuestions: [String],
        alreadyCoveredUrls: Set<String>,
        maxPages: Int = 8
    ) -> [SearchResult] {
        var seenUrls = Set<String>()
        var scoredResults: [(result: SearchResult, score: Double)] = []
        
        let subQuestionKeywords = extractKeywords(from: subQuestions)
        
        for item in results {
            let canonical = BraveSearchProvider.canonicalizeURLString(item.url)
            
            // Skip already seen in this run or previously covered
            guard !seenUrls.contains(canonical) && !alreadyCoveredUrls.contains(canonical) else {
                continue
            }
            seenUrls.insert(canonical)
            
            var score: Double = 0.0
            
            // 1. Domain Authority Score
            if let host = URL(string: canonical)?.host?.lowercased() {
                if highAuthorityDomains.contains(where: { host.contains($0) }) {
                    score += 35.0
                } else if host.hasSuffix(".edu") || host.hasSuffix(".gov") || host.hasSuffix(".org") {
                    score += 25.0
                } else {
                    score += 10.0
                }
            }
            
            // 2. Recency Score
            if let dateStr = item.publishedDate?.lowercased() {
                if dateStr.contains("hour") || dateStr.contains("today") || dateStr.contains("1 day") || dateStr.contains("2 days") {
                    score += 25.0
                } else if dateStr.contains("day") || dateStr.contains("week") {
                    score += 15.0
                } else if dateStr.contains("month") {
                    score += 5.0
                }
            }
            
            // 3. Keyword Relevance Score
            let textCorpus = (item.title + " " + item.snippet).lowercased()
            var matches = 0
            for kw in subQuestionKeywords {
                if textCorpus.contains(kw) {
                    matches += 1
                }
            }
            score += Double(min(matches, 5) * 5)
            
            scoredResults.append((item, score))
        }
        
        // Sort descending by score
        let sorted = scoredResults.sorted { $0.score > $1.score }.map { $0.result }
        return Array(sorted.prefix(maxPages))
    }
    
    private static func extractKeywords(from questions: [String]) -> [String] {
        let stopWords: Set<String> = [
            "what", "is", "the", "are", "and", "in", "of", "for", "to", "how", "a", "an", "on", "with", "by", "from", "at"
        ]
        
        var words: [String] = []
        for q in questions {
            let tokens = q.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
            for token in tokens where token.count > 2 && !stopWords.contains(token) {
                if !words.contains(token) {
                    words.append(token)
                }
            }
        }
        return words
    }
}
