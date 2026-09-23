import Foundation
import OSLog

public final class Synthesizer: Sendable {
    private let logger = Logger(subsystem: "com.personalresearchagent.app", category: "Synthesizer")
    
    public init() {}
    
    public func synthesizeReport(
        topic: String,
        depth: ResearchDepth,
        subQuestions: [String],
        facts: [ExtractedFact],
        verifiedSources: [SearchResult],
        provider: AIProvider
    ) async throws -> (reportMarkdown: String, callResult: GenerationResult) {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        let todayDate = formatter.string(from: Date())
        
        let systemPrompt = PromptBuilder.synthesizerSystemPrompt(
            topic: topic,
            todayDate: todayDate,
            depth: depth.rawValue
        )
        
        // Build facts payload
        var factsText = "VERIFIED EXTRACTED FACTS:\n"
        for (i, fact) in facts.enumerated() {
            factsText += "\(i + 1). [\(fact.sourceUrl)] \(fact.claim)\n"
        }
        
        factsText += "\nVERIFIED SOURCE CATALOG:\n"
        for src in verifiedSources {
            let publisher = src.sourceName ?? (URL(string: src.url)?.host ?? "Web")
            let date = src.publishedDate ?? "Recent"
            factsText += "- Title: \(src.title) | Publisher: \(publisher) | Date: \(date) | URL: \(src.url)\n"
        }
        
        let userMessage = ChatMessage.user("""
        Please synthesize the final intelligence report for topic: "\(topic)".
        Use the verified facts and sources below to construct all sections according to the required structure.
        
        \(factsText)
        """)
        
        let strongModel = await MainActor.run { SettingsStore.shared.strongModel }
        
        logger.info("Executing final report synthesis using model: \(strongModel)")
        
        let result = try await provider.generate(
            system: systemPrompt,
            messages: [userMessage],
            model: strongModel,
            options: GenerationOptions(temperature: 0.2, maxTokens: 4096, timeoutSeconds: 60)
        )
        
        // Strict URL Whitelist validation
        let validUrlSet = Set(verifiedSources.map { BraveSearchProvider.canonicalizeURLString($0.url) } + facts.map { BraveSearchProvider.canonicalizeURLString($0.sourceUrl) })
        let validatedMarkdown = Self.validateAndSanitizeURLs(in: result.text, against: validUrlSet)
        
        return (validatedMarkdown, result)
    }
    
    // MARK: - Code-Level URL Whitelist Validator
    public static func validateAndSanitizeURLs(in markdown: String, against allowedUrls: Set<String>) -> String {
        // Find markdown links [Title](URL)
        guard let linkRegex = try? NSRegularExpression(pattern: "\\[([^\\]]+)\\]\\((https?://[^\\)]+)\\)", options: []) else {
            return markdown
        }
        
        var sanitized = markdown
        let matches = linkRegex.matches(in: markdown, options: [], range: NSRange(markdown.startIndex..<markdown.endIndex, in: markdown))
        
        // Iterate backwards to replace safely
        for match in matches.reversed() {
            guard let titleRange = Range(match.range(at: 1), in: sanitized),
                  let urlRange = Range(match.range(at: 2), in: sanitized),
                  let fullRange = Range(match.range(at: 0), in: sanitized) else {
                continue
            }
            
            let title = String(sanitized[titleRange])
            let rawUrl = String(sanitized[urlRange])
            let canonical = BraveSearchProvider.canonicalizeURLString(rawUrl)
            
            let isAllowed = allowedUrls.contains(canonical) || allowedUrls.contains(where: {
                canonical.hasPrefix($0) || $0.hasPrefix(canonical)
            })
            
            if !isAllowed {
                // Drop hallucinated URL
                let replacement = "\(title) *(unverified source removed)*"
                sanitized.replaceSubrange(fullRange, with: replacement)
            }
        }
        
        return sanitized
    }
}
