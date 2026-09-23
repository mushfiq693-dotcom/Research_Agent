import Foundation

public struct ChatMessage: Codable, Sendable {
    public let role: String
    public let content: String
    
    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }
    
    public static func system(_ content: String) -> ChatMessage {
        ChatMessage(role: "system", content: content)
    }
    
    public static func user(_ content: String) -> ChatMessage {
        ChatMessage(role: "user", content: content)
    }
    
    public static func assistant(_ content: String) -> ChatMessage {
        ChatMessage(role: "assistant", content: content)
    }
}

public struct GenerationOptions: Sendable {
    public var temperature: Double?
    public var maxTokens: Int?
    public var timeoutSeconds: Double
    
    public init(
        temperature: Double? = 0.2,
        maxTokens: Int? = 4096,
        timeoutSeconds: Double = 35.0
    ) {
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.timeoutSeconds = timeoutSeconds
    }
}

public struct GenerationResult: Sendable {
    public let text: String
    public let modelUsed: String
    public let promptTokens: Int
    public let completionTokens: Int
    public let totalTokens: Int
    public let finishReason: String?
    
    public init(
        text: String,
        modelUsed: String,
        promptTokens: Int = 0,
        completionTokens: Int = 0,
        totalTokens: Int = 0,
        finishReason: String? = nil
    ) {
        self.text = text
        self.modelUsed = modelUsed
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = totalTokens
        self.finishReason = finishReason
    }
}

public enum AIProviderError: LocalizedError, Sendable {
    case missingApiKey
    case invalidApiKey(String)
    case insufficientCredits(String)
    case rateLimited(retryAfterSeconds: Int?)
    case dailyQuotaExhausted(String)
    case modelUnavailable(model: String, reason: String)
    case emptyCompletion
    case parsingFailed(String)
    case timeout
    case serverError(statusCode: Int, message: String)
    
    public var errorDescription: String? {
        switch self {
        case .missingApiKey:
            return "OpenRouter API key is missing. Please add your key in Settings."
        case .invalidApiKey(let msg):
            return "Invalid OpenRouter API Key (401/403): \(msg)"
        case .insufficientCredits(let msg):
            return "Insufficient OpenRouter account credits (402): \(msg)"
        case .rateLimited(let sec):
            if let sec = sec {
                return "Rate limited (429). Please retry after \(sec)s."
            }
            return "Rate limited (429) by OpenRouter / upstream model provider."
        case .dailyQuotaExhausted(let msg):
            return "Free tier daily request quota exhausted: \(msg)"
        case .modelUnavailable(let model, let reason):
            return "Model '\(model)' is unavailable (404/Offline): \(reason)"
        case .emptyCompletion:
            return "AI model returned an empty completion choice."
        case .parsingFailed(let details):
            return "Structured JSON parsing failed: \(details)"
        case .timeout:
            return "The AI request timed out."
        case .serverError(let code, let msg):
            return "OpenRouter server error (HTTP \(code)): \(msg)"
        }
    }
}

public protocol AIProvider: Sendable {
    func generate(
        system: String,
        messages: [ChatMessage],
        model: String?,
        options: GenerationOptions
    ) async throws -> GenerationResult
    
    func generateStructured<T: Decodable>(
        system: String,
        messages: [ChatMessage],
        schemaName: String?,
        schemaDescription: String?,
        schemaJson: [String: Any]?,
        model: String?,
        options: GenerationOptions
    ) async throws -> (data: T, result: GenerationResult)
}
