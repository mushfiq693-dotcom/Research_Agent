import Foundation
import OSLog

public struct ResearchPlan: Codable, Sendable {
    public let subQuestions: [String]
    public let searchQueries: [String]
    public let recencyWindowDays: Int?
    public let focusSummary: String?
    
    public init(
        subQuestions: [String],
        searchQueries: [String],
        recencyWindowDays: Int? = 7,
        focusSummary: String? = nil
    ) {
        self.subQuestions = subQuestions
        self.searchQueries = searchQueries
        self.recencyWindowDays = recencyWindowDays
        self.focusSummary = focusSummary
    }
}

public final class Planner: Sendable {
    private let logger = Logger(subsystem: "com.personalresearchagent.app", category: "Planner")
    
    public init() {}
    
    public func createPlan(
        topic: String,
        depth: ResearchDepth,
        previouslyCovered: [String],
        provider: AIProvider
    ) async throws -> (plan: ResearchPlan, callResult: GenerationResult) {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        let todayDate = formatter.string(from: Date())
        
        let systemPrompt = PromptBuilder.plannerSystemPrompt(
            todayDate: todayDate,
            topic: topic,
            previouslyCovered: previouslyCovered
        )
        
        let userMessage = ChatMessage.user("Please plan research for the topic: '\(topic)' at '\(depth.rawValue)' depth. Max allowed queries: \(depth.maxSearchQueries).")
        
        logger.info("Generating research plan for topic: '\(topic)' (depth: \(depth.rawValue))")
        
        let fastModel = await MainActor.run { SettingsStore.shared.fastModel }
        
        do {
            let (plan, result): (ResearchPlan, GenerationResult) = try await provider.generateStructured(
                system: systemPrompt,
                messages: [userMessage],
                schemaName: "ResearchPlan",
                schemaDescription: "Structured research questions and web search queries",
                schemaJson: [
                    "type": "object",
                    "properties": [
                        "subQuestions": ["type": "array", "items": ["type": "string"]],
                        "searchQueries": ["type": "array", "items": ["type": "string"]],
                        "recencyWindowDays": ["type": "integer"],
                        "focusSummary": ["type": "string"]
                    ],
                    "required": ["subQuestions", "searchQueries"]
                ],
                model: fastModel,
                options: GenerationOptions(temperature: 0.3, maxTokens: 1024, timeoutSeconds: 30)
            )
            
            // Limit queries to research depth limit
            let cappedQueries = Array(plan.searchQueries.prefix(depth.maxSearchQueries))
            let boundedPlan = ResearchPlan(
                subQuestions: plan.subQuestions,
                searchQueries: cappedQueries,
                recencyWindowDays: plan.recencyWindowDays,
                focusSummary: plan.focusSummary
            )
            
            logger.info("Generated plan with \(boundedPlan.subQuestions.count) sub-questions and \(boundedPlan.searchQueries.count) queries.")
            return (boundedPlan, result)
        } catch {
            logger.warning("AI planning call failed: \(error.localizedDescription). Falling back to heuristic planner.")
            let fallbackPlan = createHeuristicPlan(topic: topic, depth: depth)
            return (fallbackPlan, GenerationResult(text: "Heuristic Fallback", modelUsed: "local_heuristic"))
        }
    }
    
    private func createHeuristicPlan(topic: String, depth: ResearchDepth) -> ResearchPlan {
        let cleanTopic = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        let queries: [String]
        switch depth {
        case .quick:
            queries = [
                "\(cleanTopic) latest news",
                "\(cleanTopic) updates"
            ]
        case .standard:
            queries = [
                "\(cleanTopic) latest news today",
                "\(cleanTopic) breakthrough developments",
                "\(cleanTopic) key analysis",
                "\(cleanTopic) official announcements"
            ]
        case .deep:
            queries = [
                "\(cleanTopic) latest news today",
                "\(cleanTopic) breakthrough developments",
                "\(cleanTopic) technical analysis",
                "\(cleanTopic) official announcements",
                "\(cleanTopic) community reactions",
                "\(cleanTopic) industry impact"
            ]
        }
        
        return ResearchPlan(
            subQuestions: [
                "What are the most significant recent developments in \(cleanTopic)?",
                "What are the key technical or strategic implications?",
                "What are the primary sources and verifiable facts?"
            ],
            searchQueries: Array(queries.prefix(depth.maxSearchQueries)),
            recencyWindowDays: 7,
            focusSummary: "Recent developments and factual updates regarding \(cleanTopic)."
        )
    }
}
