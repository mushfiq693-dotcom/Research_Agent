import Foundation
import PersonalResearchAgentCore

private struct SamplePlanOutput: Codable, Equatable {
    let subQuestions: [String]
    let queries: [String]
    let recencyDays: Int
}

public struct ServiceTests {
    
    public static func runAll() async throws {
        print("\n--- Running ServiceTests ---")
        try testTolerantJSONParsing()
        try testReasoningTagStripping()
        try testURLCanonicalization()
        try testBraveResponseParsing()
        try testHTMLExtractionAndSanitization()
        try testModelCatalogFreeLogic()
        try await testDeadURLResilience()
        try testDuckDuckGoLiteParsing()
        try await testUnifiedSearchFallback()
        try testSpeechMarkdownCleaning()
        try await testVoiceCommandTopicExtraction()
        print("✅ ServiceTests passed successfully.")
    }
    
    // MARK: - 1. Tolerant JSON Parser Tests
    public static func testTolerantJSONParsing() throws {
        // Test Case A: Markdown fenced JSON
        let fencedText = """
        Here is the plan for your research:
        ```json
        {
            "subQuestions": ["What is Swift 6 concurrency?", "What are typed throws?"],
            "queries": ["swift 6 concurrency migration", "swift typed throws examples"],
            "recencyDays": 7
        }
        ```
        Let me know if you need changes.
        """
        let parsedA: SamplePlanOutput = try OpenRouterProvider.parseTolerantJSON(from: fencedText)
        assert(parsedA.subQuestions.count == 2, "Fenced JSON subQuestions count")
        assert(parsedA.recencyDays == 7, "Fenced JSON recencyDays")
        
        // Test Case B: Deep <think> reasoning mixed with JSON
        let thinkText = """
        <think>
        I need to analyze the user's request carefully.
        Let's formulate 2 sub-questions and 2 search queries.
        </think>
        {
            "subQuestions": ["How does MenuBarExtra work in macOS 14?"],
            "queries": ["swiftui menubarextra window style"],
            "recencyDays": 30
        }
        """
        let parsedB: SamplePlanOutput = try OpenRouterProvider.parseTolerantJSON(from: thinkText)
        assert(parsedB.subQuestions.first == "How does MenuBarExtra work in macOS 14?", "Think JSON parsing")
        assert(parsedB.recencyDays == 30, "Think JSON recencyDays")
        
        // Test Case C: Conversational prefix and suffix
        let convText = """
        Certainly! I have generated the requested data below:
        {"subQuestions": ["Q1"], "queries": ["query 1"], "recencyDays": 14}
        Hope this helps!
        """
        let parsedC: SamplePlanOutput = try OpenRouterProvider.parseTolerantJSON(from: convText)
        assert(parsedC.queries.first == "query 1", "Conversational prefix JSON parsing")
        print("  ✓ testTolerantJSONParsing passed")
    }
    
    // MARK: - 2. Reasoning Tag Stripping
    public static func testReasoningTagStripping() throws {
        let textWithTags = "Hello <think>internal thoughts here</think> World <reasoning>more thoughts</reasoning>!"
        let cleaned = OpenRouterProvider.stripReasoningBlocks(from: textWithTags)
        assert(cleaned == "Hello World !", "Reasoning tags should be completely stripped: got '\(cleaned)'")
        
        let caseInsensitive = "<THINK>multi-line\nthoughts\nhere</THINK>Clean Output"
        let cleanedCase = OpenRouterProvider.stripReasoningBlocks(from: caseInsensitive)
        assert(cleanedCase == "Clean Output", "Case-insensitive think tags should be stripped")
        print("  ✓ testReasoningTagStripping passed")
    }
    
    // MARK: - 3. URL Canonicalization
    public static func testURLCanonicalization() throws {
        let rawURL = "https://EXAMPLE.COM:443/article/123?utm_source=twitter&utm_medium=social&utm_campaign=launch&fbclid=IwAR123&keep_this=true#section2"
        let canonical = BraveSearchProvider.canonicalizeURLString(rawURL)
        
        assert(canonical.contains("https://example.com"), "Host should be lowercased")
        assert(!canonical.contains("utm_source"), "utm_source should be stripped")
        assert(!canonical.contains("fbclid"), "fbclid should be stripped")
        assert(!canonical.contains("#section2"), "Fragments should be dropped")
        assert(canonical.contains("keep_this=true"), "Legitimate query parameters should be preserved")
        print("  ✓ testURLCanonicalization passed")
    }
    
    // MARK: - 4. Brave Search Response Parsing
    public static func testBraveResponseParsing() throws {
        let mockJson = """
        {
            "web": {
                "results": [
                    {
                        "title": "Apple Introduces Swift 6",
                        "url": "https://developer.apple.com/swift/?utm_source=google",
                        "description": "Swift 6 brings complete data-race safety by default.",
                        "age": "2 days ago",
                        "profile": {
                            "name": "Apple Developer"
                        }
                    }
                ]
            }
        }
        """.data(using: .utf8)!
        
        let results = try BraveSearchProvider.parseBraveResponse(mockJson)
        assert(results.count == 1, "Should parse 1 search result")
        assert(results[0].title == "Apple Introduces Swift 6", "Title match")
        assert(results[0].url == "https://developer.apple.com/swift/", "URL should be canonicalized")
        assert(results[0].sourceName == "Apple Developer", "Source name match")
        assert(results[0].publishedDate == "2 days ago", "Published date match")
        print("  ✓ testBraveResponseParsing passed")
    }
    
    // MARK: - 5. HTML Extraction & Sanitization
    public static func testHTMLExtractionAndSanitization() throws {
        let rawHTML = """
        <!DOCTYPE html>
        <html>
        <head>
            <title>Test Page &amp; Article</title>
            <style>body { font-size: 14px; }</style>
            <script>console.log('malicious injection or script');</script>
        </head>
        <body>
            <header><nav><a href="/">Home</a></nav></header>
            <article>
                <h1>Main Heading</h1>
                <p>This is the first paragraph with &quot;quoted text&quot; &amp; a <a href="/link">link</a>.</p>
                <p>Second paragraph containing <strong>important facts</strong>.</p>
            </article>
            <footer>&copy; 2026 Company Inc.</footer>
        </body>
        </html>
        """
        
        let url = URL(string: "https://example.com/test")!
        let extracted = HTMLExtractor.extract(from: rawHTML, url: url, maxCharacters: 500)
        
        assert(extracted.title == "Test Page & Article", "Title unescaped & extracted: got '\(extracted.title)'")
        assert(!extracted.text.contains("console.log"), "Scripts must be stripped")
        assert(!extracted.text.contains("font-size"), "Styles must be stripped")
        assert(!extracted.text.contains("Home"), "Navigation must be stripped")
        assert(!extracted.text.contains("Company Inc"), "Footer must be stripped")
        assert(extracted.text.contains("\"quoted text\" & a link"), "HTML entities unescaped and text cleaned")
        assert(!extracted.isTruncated, "Should not be truncated under 500 chars")
        
        // Test Truncation
        let longExtracted = HTMLExtractor.extract(from: rawHTML, url: url, maxCharacters: 20)
        assert(longExtracted.isTruncated, "Should be flagged as truncated")
        assert(longExtracted.text.contains("...[Content Truncated]"), "Truncation footer attached")
        print("  ✓ testHTMLExtractionAndSanitization passed")
    }
    
    // MARK: - 6. Model Catalog Free Logic
    public static func testModelCatalogFreeLogic() throws {
        let freeSlugModel = OpenRouterModel(
            id: "meta-llama/llama-3-8b-instruct:free",
            name: "Llama 3 8B (free)",
            description: "Test",
            context_length: 8192,
            pricing: nil,
            supported_parameters: ["tools", "structured_outputs"]
        )
        assert(freeSlugModel.isFree, "Model ending with :free is free")
        assert(freeSlugModel.supportsStructuredOutputs, "Supports structured outputs")
        assert(freeSlugModel.supportsTools, "Supports tools")
        
        let zeroPricingModel = OpenRouterModel(
            id: "custom/free-model",
            name: "Custom Free",
            description: "Test",
            context_length: 4096,
            pricing: ModelPricing(prompt: "0", completion: "0", request: nil, image: nil),
            supported_parameters: []
        )
        assert(zeroPricingModel.isFree, "Model with 0 pricing is free")
        assert(!zeroPricingModel.supportsStructuredOutputs, "Does not support structured outputs")
        
        let paidModel = OpenRouterModel(
            id: "openai/gpt-4o",
            name: "GPT-4o",
            description: "Paid model",
            context_length: 128000,
            pricing: ModelPricing(prompt: "0.000005", completion: "0.000015", request: nil, image: nil),
            supported_parameters: ["structured_outputs"]
        )
        assert(!paidModel.isFree, "Paid model should not be free")
        print("  ✓ testModelCatalogFreeLogic passed")
    }
    
    // MARK: - 7. Dead URL Resilience
    public static func testDeadURLResilience() async throws {
        let deadURL = URL(string: "http://127.0.0.1:54321/nonexistent-dead-endpoint")!
        let fetcher = PageFetcher.shared
        
        do {
            _ = try await fetcher.fetchWebPage(url: deadURL, maxCharacters: 1000)
            assert(false, "Dead URL should throw URLError")
        } catch {
            // Success: safely caught error without crashing
            assert(true)
        }
        print("  ✓ testDeadURLResilience passed")
    }
    
    // MARK: - 8. DuckDuckGo Lite Parsing
    public static func testDuckDuckGoLiteParsing() throws {
        let mockDDGHTML = """
        <html>
        <body>
        <table>
        <tr>
            <td>
                <a rel="nofollow" href="https://example.com/swift6" class='result-link'>Swift 6 Concurrency Guide</a>
            </td>
        </tr>
        <tr>
            <td class='result-snippet'>
                Learn all about <b>Swift 6</b> concurrency &amp; data race safety.
            </td>
        </tr>
        <tr>
            <td>
                <a rel="nofollow" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fapple.com%2Fmacos&rut=123" class='result-link'>macOS Sequoia - Apple</a>
            </td>
        </tr>
        <tr>
            <td class='result-snippet'>
                Explore all new features in <b>macOS</b> Sequoia.
            </td>
        </tr>
        </table>
        </body>
        </html>
        """
        
        let results = DuckDuckGoSearchProvider.parseDuckDuckGoLiteHTML(mockDDGHTML)
        assert(results.count == 2, "Should parse 2 search results from DDG HTML")
        assert(results[0].title == "Swift 6 Concurrency Guide", "Result 1 title match")
        assert(results[0].url == "https://example.com/swift6", "Result 1 URL match")
        assert(results[0].snippet.contains("Swift 6 concurrency & data race safety"), "Result 1 snippet cleaned")
        assert(results[1].url == "https://apple.com/macos", "Result 2 unwrapped URL match")
        print("  ✓ testDuckDuckGoLiteParsing passed")
    }
    
    // MARK: - 9. Unified Search Fallback
    public static func testUnifiedSearchFallback() async throws {
        let results = try await DuckDuckGoSearchProvider.shared.searchGoogleNewsRSS(query: "Apple", count: 2)
        assert(!results.isEmpty, "Google News RSS fallback should return results")
        assert(results[0].url.hasPrefix("http"), "Valid URL returned")
        print("  ✓ testUnifiedSearchFallback passed")
    }
    
    // MARK: - 10. Speech Markdown Cleaning & Spoken Formatter
    public static func testSpeechMarkdownCleaning() throws {
        let rawMarkdown = """
        # Today's Brief: Quantum Computing Breakthrough
        *Date: 24 September 2026*
        
        ## Summary
        Scientists have achieved **major milestones** in [qubit coherence](https://example.com/quantum).
        
        * New superconducting chips
        * Error correction rates improved
        
        ```python
        print("quantum simulation")
        ```
        """
        
        let cleaned = SpeechService.cleanMarkdownForSpeech(rawMarkdown)
        assert(!cleaned.contains("#"), "Headers removed")
        assert(!cleaned.contains("**"), "Bold markers stripped")
        assert(!cleaned.contains("print(\"quantum"), "Code blocks stripped")
        assert(cleaned.contains("Scientists have achieved major milestones in qubit coherence"), "Link syntax converted to plain text")
        
        let formatted = SpeechService.formatSpokenBriefing(
            markdown: rawMarkdown,
            topic: "Quantum Computing",
            userName: "Mushfiq",
            assistantName: "Jarvis"
        )
        assert(formatted.contains("Hello Mushfiq, this is Jarvis."), "Personalized greeting inserted")
        print("  ✓ testSpeechMarkdownCleaning passed")
    }
    
    // MARK: - 11. Voice Command Topic Extraction
    @MainActor
    public static func testVoiceCommandTopicExtraction() throws {
        let voiceInput = VoiceInputService.shared
        
        let t1 = voiceInput.extractResearchTopic(from: "Hey Jarvis please research on Swift 6 concurrency")
        assert(t1.lowercased() == "swift 6 concurrency", "Extracted topic match 1: '\(t1)'")
        
        let t2 = voiceInput.extractResearchTopic(from: "Jarvis, search for latest Apple M4 benchmarks")
        assert(t2.lowercased() == "latest apple m4 benchmarks", "Extracted topic match 2: '\(t2)'")
        
        let t3 = voiceInput.extractResearchTopic(from: "Find out about deepseek v3 architecture")
        assert(t3.lowercased() == "deepseek v3 architecture", "Extracted topic match 3: '\(t3)'")
        
        let t4 = voiceInput.extractResearchTopic(from: "Quantum Computing Algorithms")
        assert(t4 == "Quantum Computing Algorithms", "Raw query preserved: '\(t4)'")
        
        print("  ✓ testVoiceCommandTopicExtraction passed")
    }
}
