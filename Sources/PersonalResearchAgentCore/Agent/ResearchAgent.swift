import Foundation
import OSLog

public actor ResearchAgent {
    public static let shared = ResearchAgent()
    
    private let logger = Logger(subsystem: "com.personalresearchagent.app", category: "ResearchAgent")
    
    private let planner = Planner()
    private let evaluator = SourceEvaluator()
    private let extractor = FactExtractor()
    private let synthesizer = Synthesizer()
    private let writer = ReportWriter.shared
    private let memoryStore = LocalMemoryStore.shared
    
    private var isCurrentlyRunning = false
    
    public init() {}
    
    @discardableResult
    public func executeResearch(
        topicOverride: String? = nil,
        aiProvider: AIProvider = OpenRouterProvider.shared,
        searchProvider: SearchProvider = BraveSearchProvider.shared,
        pageFetcher: PageFetcherProtocol = PageFetcher.shared
    ) async throws -> URL {
        // Enforce no overlapping runs
        guard !isCurrentlyRunning else {
            logger.warning("Research run already in progress. Ignoring trigger.")
            throw AIProviderError.serverError(statusCode: 409, message: "A research run is already active.")
        }
        isCurrentlyRunning = true
        defer {
            isCurrentlyRunning = false
        }
        
        let startTime = Date()
        let depth = await MainActor.run { SettingsStore.shared.researchDepth }
        let effectiveTopic: String
        if let override = topicOverride, !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            effectiveTopic = override.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            effectiveTopic = await MainActor.run { SettingsStore.shared.activeTopic }
        }
        
        logger.info("Starting autonomous research run for: '\(effectiveTopic)' [Depth: \(depth.rawValue)]")
        
        // Track stats for JSON metadata
        var modelsUsed: Set<String> = []
        var totalPromptTokens = 0
        var totalCompletionTokens = 0
        var totalModelCalls = 0
        var limitsHit: [String] = []
        var allExecutedQueries: [String] = []
        var allFetchedSources: [SearchResult] = []
        var allExtractedFacts: [ExtractedFact] = []
        
        // Check internet connection
        let isConnected = await MainActor.run { ConnectivityMonitor.shared.checkCurrentConnection() }
        if !isConnected {
            await MainActor.run {
                AppState.shared.status = .offline
                AppState.shared.isResearching = false
            }
            throw URLError(.notConnectedToInternet)
        }
        
        do {
            // MARK: 1. Load Memory
            let memory = await memoryStore.loadMemory()
            
            // MARK: 2. Planning
            await MainActor.run {
                AppState.shared.status = .researching(step: .planning)
                AppState.shared.isResearching = true
            }
            
            let (plan, planResult) = try await planner.createPlan(
                topic: effectiveTopic,
                depth: depth,
                previouslyCovered: memory.coveredStoryTitles,
                provider: aiProvider
            )
            modelsUsed.insert(planResult.modelUsed)
            totalPromptTokens += planResult.promptTokens
            totalCompletionTokens += planResult.completionTokens
            totalModelCalls += 1
            
            // MARK: 3. Search & Ranking
            await MainActor.run {
                AppState.shared.status = .researching(step: .searching)
            }
            
            var aggregatedSearchResults: [SearchResult] = []
            for query in plan.searchQueries {
                allExecutedQueries.append(query)
                do {
                    let results = try await searchProvider.searchWeb(query: query, count: depth.resultsPerQuery, freshness: .pastWeek)
                    aggregatedSearchResults.append(contentsOf: results)
                } catch {
                    logger.warning("Search query '\(query)' failed: \(error.localizedDescription)")
                }
            }
            
            let rankedSources = SourceEvaluator.evaluateAndRank(
                results: aggregatedSearchResults,
                subQuestions: plan.subQuestions,
                alreadyCoveredUrls: memory.coveredUrls,
                maxPages: depth.maxPagesFetched
            )
            allFetchedSources = rankedSources
            
            // MARK: 4. Page Fetching
            await MainActor.run {
                AppState.shared.status = .researching(step: .fetching)
            }
            
            var fetchedPages: [ExtractedPage] = []
            for src in rankedSources {
                guard let url = URL(string: src.url) else { continue }
                do {
                    let page = try await pageFetcher.fetchWebPage(url: url, maxCharacters: depth.maxCharactersPerPage)
                    fetchedPages.append(page)
                } catch {
                    logger.warning("Failed to fetch source: \(src.url)")
                }
            }
            
            // MARK: 5. Fact Extraction
            await MainActor.run {
                AppState.shared.status = .researching(step: .analyzing)
            }
            
            let (facts, gaps, extractResults) = try await extractor.extractFacts(
                pages: fetchedPages,
                subQuestions: plan.subQuestions,
                provider: aiProvider
            )
            allExtractedFacts.append(contentsOf: facts)
            for res in extractResults {
                modelsUsed.insert(res.modelUsed)
                totalPromptTokens += res.promptTokens
                totalCompletionTokens += res.completionTokens
                totalModelCalls += 1
            }
            
            // MARK: 6. Gap Check (Iteration 2 if needed & budget allows)
            if depth.maxIterations > 1 && !gaps.isEmpty && totalModelCalls < depth.maxModelCalls {
                logger.info("Identified \(gaps.count) knowledge gaps. Executing 2nd research iteration...")
                let gapQuery = "\(effectiveTopic) \(gaps.first ?? "")"
                allExecutedQueries.append(gapQuery)
                
                if let gapResults = try? await searchProvider.searchWeb(query: gapQuery, count: 3, freshness: .pastWeek) {
                    let additionalSources = SourceEvaluator.evaluateAndRank(
                        results: gapResults,
                        subQuestions: gaps,
                        alreadyCoveredUrls: memory.coveredUrls.union(Set(rankedSources.map { $0.url })),
                        maxPages: 2
                    )
                    for src in additionalSources {
                        if let url = URL(string: src.url), let page = try? await pageFetcher.fetchWebPage(url: url, maxCharacters: depth.maxCharactersPerPage) {
                            fetchedPages.append(page)
                            allFetchedSources.append(src)
                        }
                    }
                }
            }
            
            // Check call limits
            if totalModelCalls >= depth.maxModelCalls {
                limitsHit.append("Max model call cap reached (\(depth.maxModelCalls))")
            }
            
            // MARK: 7. Synthesis
            await MainActor.run {
                AppState.shared.status = .researching(step: .writing)
            }
            
            let (markdownReport, synthResult) = try await synthesizer.synthesizeReport(
                topic: effectiveTopic,
                depth: depth,
                subQuestions: plan.subQuestions,
                facts: allExtractedFacts,
                verifiedSources: allFetchedSources,
                provider: aiProvider
            )
            modelsUsed.insert(synthResult.modelUsed)
            totalPromptTokens += synthResult.promptTokens
            totalCompletionTokens += synthResult.completionTokens
            totalModelCalls += 1
            
            // MARK: 8. Write Report & Metadata
            let endTime = Date()
            let duration = endTime.timeIntervalSince(startTime)
            
            let sourcesMetadata = allFetchedSources.map {
                ReportSourceMetadata(title: $0.title, url: $0.url, status: "fetched_and_verified")
            }
            
            let tokenMetadata = TokenUsageMetadata(
                promptTokens: totalPromptTokens,
                completionTokens: totalCompletionTokens,
                totalTokens: totalPromptTokens + totalCompletionTokens
            )
            
            let reportMetadata = ReportMetadata(
                topic: effectiveTopic,
                depth: depth.rawValue,
                startTime: startTime,
                endTime: endTime,
                durationSeconds: duration,
                queries: allExecutedQueries,
                sources: sourcesMetadata,
                modelsUsed: Array(modelsUsed),
                tokenUsage: tokenMetadata,
                modelCallCount: totalModelCalls,
                isPartial: !limitsHit.isEmpty,
                limitsHit: limitsHit
            )
            
            let reportsDirURL = await MainActor.run { SettingsStore.shared.reportsDirectoryURL }
            let (reportMarkdownURL, _) = try writer.writeReport(
                markdownContent: markdownReport,
                metadata: reportMetadata,
                baseDirectoryURL: reportsDirURL
            )
            
            // MARK: 9. Update Memory
            let runRecord = RunRecord(
                topic: effectiveTopic,
                reportPath: reportMarkdownURL.path,
                sourceUrls: allFetchedSources.map { $0.url },
                storyTitles: [effectiveTopic],
                isSuccess: true,
                failureReason: nil
            )
            try await memoryStore.recordRun(runRecord)
            
            // MARK: 10. Update App State
            await MainActor.run {
                AppState.shared.lastReportPath = reportMarkdownURL.path
                AppState.shared.status = .completed(time: endTime, reportPath: reportMarkdownURL.path)
                AppState.shared.isResearching = false
            }
            
            logger.info("Autonomous research run completed successfully in \(String(format: "%.1f", duration))s.")
            return reportMarkdownURL
            
        } catch {
            let failureReason = error.localizedDescription
            logger.error("Research run failed: \(failureReason)")
            
            // Record failure in memory
            let failRecord = RunRecord(
                topic: effectiveTopic,
                reportPath: "",
                sourceUrls: [],
                storyTitles: [],
                isSuccess: false,
                failureReason: failureReason
            )
            try? await memoryStore.recordRun(failRecord)
            
            await MainActor.run {
                AppState.shared.status = .failed(reason: failureReason)
                AppState.shared.isResearching = false
            }
            throw error
        }
    }
}
