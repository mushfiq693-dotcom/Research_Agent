import Foundation
import OSLog

public struct ExtractedFact: Codable, Sendable {
    public let claim: String
    public let sourceUrl: String
    public let publishedDate: String?
    public let relevance: String?
    
    public init(
        claim: String,
        sourceUrl: String,
        publishedDate: String? = nil,
        relevance: String? = nil
    ) {
        self.claim = claim
        self.sourceUrl = sourceUrl
        self.publishedDate = publishedDate
        self.relevance = relevance
    }
}

public struct ExtractionResponse: Codable, Sendable {
    public let extractedFacts: [ExtractedFact]
    public let identifiedGaps: [String]?
    
    public init(
        extractedFacts: [ExtractedFact],
        identifiedGaps: [String]? = nil
    ) {
        self.extractedFacts = extractedFacts
        self.identifiedGaps = identifiedGaps
    }
}

public final class FactExtractor: Sendable {
    private let logger = Logger(subsystem: "com.personalresearchagent.app", category: "FactExtractor")
    
    public init() {}
    
    public func extractFacts(
        pages: [ExtractedPage],
        subQuestions: [String],
        provider: AIProvider
    ) async throws -> (facts: [ExtractedFact], gaps: [String], callResults: [GenerationResult]) {
        guard !pages.isEmpty else {
            return ([], [], [])
        }
        
        var allFacts: [ExtractedFact] = []
        var allGaps: [String] = []
        var callResults: [GenerationResult] = []
        
        let systemPrompt = PromptBuilder.extractorSystemPrompt(subQuestions: subQuestions)
        let fastModel = await MainActor.run { SettingsStore.shared.fastModel }
        
        // Batch pages in groups of 3 to maximize token budget efficiency
        let batchSize = 3
        let batches = stride(from: 0, to: pages.count, by: batchSize).map {
            Array(pages[$0..<min($0 + batchSize, pages.count)])
        }
        
        for (idx, batch) in batches.enumerated() {
            var userContent = "EXTRACT FACTS FROM THE FOLLOWING WEBPAGES:\n\n"
            for page in batch {
                let wrapped = PromptBuilder.sanitizeAndWrapUntrustedWebpage(
                    url: page.url.absoluteString,
                    content: "Page Title: \(page.title)\n\n\(page.text)"
                )
                userContent += wrapped + "\n\n"
            }
            
            logger.info("Executing fact extraction for batch #\(idx + 1)/\(batches.count) (\(batch.count) pages)")
            
            do {
                let (response, result): (ExtractionResponse, GenerationResult) = try await provider.generateStructured(
                    system: systemPrompt,
                    messages: [ChatMessage.user(userContent)],
                    schemaName: "ExtractionResponse",
                    schemaDescription: "Extracted factual statements tied to source URLs",
                    schemaJson: [
                        "type": "object",
                        "properties": [
                            "extractedFacts": [
                                "type": "array",
                                "items": [
                                    "type": "object",
                                    "properties": [
                                        "claim": ["type": "string"],
                                        "sourceUrl": ["type": "string"],
                                        "publishedDate": ["type": "string"],
                                        "relevance": ["type": "string"]
                                    ],
                                    "required": ["claim", "sourceUrl"]
                                ]
                            ],
                            "identifiedGaps": ["type": "array", "items": ["type": "string"]]
                        ],
                        "required": ["extractedFacts"]
                    ],
                    model: fastModel,
                    options: GenerationOptions(temperature: 0.2, maxTokens: 2048, timeoutSeconds: 35)
                )
                
                allFacts.append(contentsOf: response.extractedFacts)
                if let gaps = response.identifiedGaps {
                    allGaps.append(contentsOf: gaps)
                }
                callResults.append(result)
            } catch {
                logger.warning("Fact extraction batch #\(idx + 1) failed: \(error.localizedDescription)")
            }
        }
        
        logger.info("Extracted total of \(allFacts.count) facts across all pages.")
        return (allFacts, allGaps, callResults)
    }
}
