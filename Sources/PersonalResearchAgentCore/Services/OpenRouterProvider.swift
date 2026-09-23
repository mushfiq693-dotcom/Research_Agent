import Foundation
import OSLog

private actor RequestRateLimiter {
    private var lastRequestTime: Date = Date.distantPast
    
    func enforceSpacing(minDelay: Double) async {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastRequestTime)
        let waitTime = max(0, minDelay - elapsed)
        lastRequestTime = now.addingTimeInterval(waitTime)
        if waitTime > 0 {
            try? await Task.sleep(nanoseconds: UInt64(waitTime * 1_000_000_000))
        }
    }
}

public final class OpenRouterProvider: AIProvider, Sendable {
    public static let shared = OpenRouterProvider()
    
    private let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
    private let logger = Logger(subsystem: "com.personalresearchagent.app", category: "OpenRouterProvider")
    private let rateLimiter = RequestRateLimiter()
    
    public init() {}
    
    // MARK: - Plain Text Generation
    public func generate(
        system: String,
        messages: [ChatMessage],
        model: String? = nil,
        options: GenerationOptions = GenerationOptions()
    ) async throws -> GenerationResult {
        let defaultModel = await MainActor.run { SettingsStore.shared.fastModel }
        let fallbackList = await MainActor.run { SettingsStore.shared.fallbackModels }
        let requestedModel = model ?? defaultModel
        
        var modelsToTry = [requestedModel]
        for fb in fallbackList where !modelsToTry.contains(fb) {
            modelsToTry.append(fb)
        }
        
        var lastError: Error = AIProviderError.emptyCompletion
        for (index, currentModel) in modelsToTry.enumerated() {
            do {
                if index > 0 {
                    logger.warning("Attempting fallback model: \(currentModel) (fallback attempt #\(index))")
                }
                return try await executeGenerate(
                    system: system,
                    messages: messages,
                    model: currentModel,
                    responseFormat: nil,
                    options: options
                )
            } catch let error as AIProviderError {
                lastError = error
                logger.warning("Model '\(currentModel)' failed with: \(error.localizedDescription)")
                
                // If it's missing key, no point in trying other models
                if case .missingApiKey = error {
                    throw error
                }
                if case .invalidApiKey = error {
                    throw error
                }
                continue
            } catch {
                lastError = error
                logger.warning("Model '\(currentModel)' failed with unexpected error: \(error.localizedDescription)")
                continue
            }
        }
        throw lastError
    }
    
    // MARK: - 3-Layer Structured Generation
    public func generateStructured<T: Decodable>(
        system: String,
        messages: [ChatMessage],
        schemaName: String? = nil,
        schemaDescription: String? = nil,
        schemaJson: [String: Any]? = nil,
        model: String? = nil,
        options: GenerationOptions = GenerationOptions()
    ) async throws -> (data: T, result: GenerationResult) {
        let defaultModel = await MainActor.run { SettingsStore.shared.fastModel }
        let fallbackList = await MainActor.run { SettingsStore.shared.fallbackModels }
        let requestedModel = model ?? defaultModel
        
        var modelsToTry = [requestedModel]
        for fb in fallbackList where !modelsToTry.contains(fb) {
            modelsToTry.append(fb)
        }
        
        // Layer 2: System prompt augmented with strict JSON instruction
        var augmentedSystem = system + "\n\nCRITICAL OUTPUT REQUIREMENT:\nYou MUST respond ONLY with a single valid JSON object. Do NOT wrap output in explanations, do NOT add conversational text before or after the JSON."
        if let schemaJson = schemaJson, let schemaData = try? JSONSerialization.data(withJSONObject: schemaJson, options: .prettyPrinted), let schemaStr = String(data: schemaData, encoding: .utf8) {
            augmentedSystem += "\nJSON Schema:\n\(schemaStr)"
        }
        
        // Layer 1: Check if native JSON response_format should be sent
        var responseFormat: [String: Any]? = nil
        if let schemaJson = schemaJson, let schemaName = schemaName {
            responseFormat = [
                "type": "json_schema",
                "json_schema": [
                    "name": schemaName,
                    "strict": true,
                    "schema": schemaJson
                ]
            ]
        } else {
            responseFormat = ["type": "json_object"]
        }
        
        var lastError: Error = AIProviderError.emptyCompletion
        for (index, currentModel) in modelsToTry.enumerated() {
            do {
                if index > 0 {
                    logger.warning("Attempting structured generation with fallback model: \(currentModel)")
                }
                
                let genResult = try await executeGenerate(
                    system: augmentedSystem,
                    messages: messages,
                    model: currentModel,
                    responseFormat: responseFormat,
                    options: options
                )
                
                // Layer 3: Tolerant parser
                do {
                    let decoded: T = try Self.parseTolerantJSON(from: genResult.text)
                    return (decoded, genResult)
                } catch let parseError {
                    logger.warning("Layer 3 initial parse failed: \(parseError.localizedDescription). Attempting 1-time repair prompt...")
                    
                    // Single-attempt auto-repair
                    let repairMessages = messages + [
                        ChatMessage.assistant(genResult.text),
                        ChatMessage.user("The previous response was invalid JSON: \(parseError.localizedDescription). Please output ONLY the corrected, valid JSON conforming to the schema.")
                    ]
                    
                    let repairResult = try await executeGenerate(
                        system: augmentedSystem,
                        messages: repairMessages,
                        model: currentModel,
                        responseFormat: responseFormat,
                        options: options
                    )
                    
                    let repairedDecoded: T = try Self.parseTolerantJSON(from: repairResult.text)
                    return (repairedDecoded, repairResult)
                }
            } catch let error as AIProviderError {
                lastError = error
                if case .missingApiKey = error { throw error }
                if case .invalidApiKey = error { throw error }
                continue
            } catch {
                lastError = error
                continue
            }
        }
        throw lastError
    }
    
    // MARK: - Core Request Execution
    private func executeGenerate(
        system: String,
        messages: [ChatMessage],
        model: String,
        responseFormat: [String: Any]?,
        options: GenerationOptions
    ) async throws -> GenerationResult {
        guard let apiKey = KeychainService.shared.getKey(.openRouter), !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIProviderError.missingApiKey
        }
        
        // Rate-limit spacing enforcement
        let minDelay = await MainActor.run { SettingsStore.shared.delayBetweenCallsSeconds }
        await rateLimiter.enforceSpacing(minDelay: minDelay)
        
        var allMessages: [[String: String]] = [
            ["role": "system", "content": system]
        ]
        for m in messages {
            allMessages.append(["role": m.role, "content": m.content])
        }
        
        var payload: [String: Any] = [
            "model": model,
            "messages": allMessages
        ]
        if let temp = options.temperature {
            payload["temperature"] = temp
        }
        if let maxTokens = options.maxTokens {
            payload["max_tokens"] = maxTokens
        }
        if let format = responseFormat {
            payload["response_format"] = format
        }
        
        let jsonData = try JSONSerialization.data(withJSONObject: payload)
        
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = options.timeoutSeconds
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("https://github.com/mushfiq/Research_Agent", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("Personal Research Agent (macOS Native)", forHTTPHeaderField: "X-Title")
        request.httpBody = jsonData
        
        logger.info("Sending request to OpenRouter for model: \(model) (Auth: \(KeychainService.redact(apiKey)))")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIProviderError.timeout
        }
        
        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AIProviderError.invalidApiKey(body)
        }
        if httpResponse.statusCode == 402 {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AIProviderError.insufficientCredits(body)
        }
        if httpResponse.statusCode == 404 {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AIProviderError.modelUnavailable(model: model, reason: body)
        }
        if httpResponse.statusCode == 429 {
            var retrySeconds: Int? = nil
            if let retryAfterHeader = httpResponse.value(forHTTPHeaderField: "Retry-After"), let sec = Int(retryAfterHeader) {
                retrySeconds = sec
            }
            let body = String(data: data, encoding: .utf8) ?? ""
            if body.lowercased().contains("quota") || body.lowercased().contains("daily") {
                throw AIProviderError.dailyQuotaExhausted(body)
            }
            throw AIProviderError.rateLimited(retryAfterSeconds: retrySeconds)
        }
        if httpResponse.statusCode >= 500 {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AIProviderError.serverError(statusCode: httpResponse.statusCode, message: body)
        }
        
        // Parse JSON response
        guard let responseJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIProviderError.serverError(statusCode: httpResponse.statusCode, message: "Non-JSON response received.")
        }
        
        // Check for provider-side error object even on HTTP 200
        if let errorObj = responseJson["error"] as? [String: Any] {
            let msg = errorObj["message"] as? String ?? "Unknown provider error"
            let code = errorObj["code"] as? Int ?? httpResponse.statusCode
            if code == 429 || msg.lowercased().contains("rate") {
                throw AIProviderError.rateLimited(retryAfterSeconds: nil)
            }
            throw AIProviderError.serverError(statusCode: code, message: msg)
        }
        
        guard let choices = responseJson["choices"] as? [[String: Any]], let firstChoice = choices.first,
              let messageObj = firstChoice["message"] as? [String: Any],
              let content = messageObj["content"] as? String else {
            throw AIProviderError.emptyCompletion
        }
        
        let finishReason = firstChoice["finish_reason"] as? String
        let modelUsed = responseJson["model"] as? String ?? model
        
        var promptTokens = 0
        var completionTokens = 0
        var totalTokens = 0
        if let usage = responseJson["usage"] as? [String: Any] {
            promptTokens = usage["prompt_tokens"] as? Int ?? 0
            completionTokens = usage["completion_tokens"] as? Int ?? 0
            totalTokens = usage["total_tokens"] as? Int ?? (promptTokens + completionTokens)
        }
        
        // Clean thinking/reasoning tags
        let cleanedText = Self.stripReasoningBlocks(from: content)
        
        return GenerationResult(
            text: cleanedText,
            modelUsed: modelUsed,
            promptTokens: promptTokens,
            completionTokens: completionTokens,
            totalTokens: totalTokens,
            finishReason: finishReason
        )
    }
    
    // MARK: - Tolerant JSON Parser (Layer 3)
    public static func parseTolerantJSON<T: Decodable>(from rawText: String) throws -> T {
        let cleaned = stripReasoningBlocks(from: rawText).trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 1. Try direct decoding
        if let data = cleaned.data(using: .utf8), let decoded = try? JSONDecoder().decode(T.self, from: data) {
            return decoded
        }
        
        // 2. Strip Markdown code fences: ```json ... ``` or ``` ... ```
        var unfenced = cleaned
        if let fenceRegex = try? NSRegularExpression(pattern: "```(?:json)?\\s*([\\s\\S]*?)\\s*```", options: [.caseInsensitive]) {
            let range = NSRange(cleaned.startIndex..<cleaned.endIndex, in: cleaned)
            if let match = fenceRegex.firstMatch(in: cleaned, options: [], range: range),
               let matchRange = Range(match.range(at: 1), in: cleaned) {
                unfenced = String(cleaned[matchRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                if let data = unfenced.data(using: .utf8), let decoded = try? JSONDecoder().decode(T.self, from: data) {
                    return decoded
                }
            }
        }
        
        // 3. Extract outermost balanced JSON object {...} or array [...]
        if let extracted = extractOutermostJSON(from: unfenced) {
            if let data = extracted.data(using: .utf8) {
                do {
                    return try JSONDecoder().decode(T.self, from: data)
                } catch {
                    throw AIProviderError.parsingFailed("JSON decoding failed: \(error.localizedDescription)")
                }
            }
        }
        
        throw AIProviderError.parsingFailed("No valid JSON object or array could be extracted from model output.")
    }
    
    public static func stripReasoningBlocks(from text: String) -> String {
        var output = text
        
        // Strip <think>...</think>
        if let thinkRegex = try? NSRegularExpression(pattern: "<think>[\\s\\S]*?</think>", options: [.caseInsensitive]) {
            let range = NSRange(output.startIndex..<output.endIndex, in: output)
            output = thinkRegex.stringByReplacingMatches(in: output, options: [], range: range, withTemplate: "")
        }
        // Strip <reasoning>...</reasoning>
        if let reasonRegex = try? NSRegularExpression(pattern: "<reasoning>[\\s\\S]*?</reasoning>", options: [.caseInsensitive]) {
            let range = NSRange(output.startIndex..<output.endIndex, in: output)
            output = reasonRegex.stringByReplacingMatches(in: output, options: [], range: range, withTemplate: "")
        }
        // Strip [THINK]...[/THINK]
        if let bracketRegex = try? NSRegularExpression(pattern: "\\[THINK\\][\\s\\S]*?\\[/THINK\\]", options: [.caseInsensitive]) {
            let range = NSRange(output.startIndex..<output.endIndex, in: output)
            output = bracketRegex.stringByReplacingMatches(in: output, options: [], range: range, withTemplate: "")
        }
        
        // Normalize multiple horizontal whitespace characters
        if let spaceRegex = try? NSRegularExpression(pattern: "[ \\t]+", options: []) {
            let range = NSRange(output.startIndex..<output.endIndex, in: output)
            output = spaceRegex.stringByReplacingMatches(in: output, options: [], range: range, withTemplate: " ")
        }
        
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private static func extractOutermostJSON(from text: String) -> String? {
        guard let firstBrace = text.firstIndex(where: { $0 == "{" || $0 == "[" }) else {
            return nil
        }
        
        let startChar = text[firstBrace]
        let endChar: Character = (startChar == "{") ? "}" : "]"
        
        var depth = 0
        var inString = false
        var isEscaped = false
        
        var startIndex: String.Index? = nil
        var endIndex: String.Index? = nil
        
        let substring = text[firstBrace...]
        for (idx, char) in zip(substring.indices, substring) {
            if isEscaped {
                isEscaped = false
                continue
            }
            if char == "\\" {
                isEscaped = true
                continue
            }
            if char == "\"" {
                inString.toggle()
                continue
            }
            if !inString {
                if char == startChar {
                    if depth == 0 {
                        startIndex = idx
                    }
                    depth += 1
                } else if char == endChar {
                    depth -= 1
                    if depth == 0 {
                        endIndex = idx
                        break
                    }
                }
            }
        }
        
        if let start = startIndex, let end = endIndex {
            return String(text[start...end])
        }
        return nil
    }
}
