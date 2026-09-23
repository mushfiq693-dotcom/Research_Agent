import Foundation
import OSLog

public struct ModelPricing: Codable, Sendable {
    public let prompt: String?
    public let completion: String?
    public let request: String?
    public let image: String?
    
    public init(
        prompt: String? = nil,
        completion: String? = nil,
        request: String? = nil,
        image: String? = nil
    ) {
        self.prompt = prompt
        self.completion = completion
        self.request = request
        self.image = image
    }
}

public struct OpenRouterModel: Codable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let description: String?
    public let context_length: Int?
    public let pricing: ModelPricing?
    public let supported_parameters: [String]?
    
    public init(
        id: String,
        name: String,
        description: String? = nil,
        context_length: Int? = nil,
        pricing: ModelPricing? = nil,
        supported_parameters: [String]? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.context_length = context_length
        self.pricing = pricing
        self.supported_parameters = supported_parameters
    }
    
    public var isFree: Bool {
        if id.hasSuffix(":free") {
            return true
        }
        if let pricing = pricing {
            let promptZero = pricing.prompt == "0" || pricing.prompt == "0.0"
            let completionZero = pricing.completion == "0" || pricing.completion == "0.0"
            if promptZero && completionZero {
                return true
            }
        }
        return false
    }
    
    public var supportsStructuredOutputs: Bool {
        guard let params = supported_parameters else { return false }
        return params.contains("structured_outputs") || params.contains("response_format")
    }
    
    public var supportsTools: Bool {
        guard let params = supported_parameters else { return false }
        return params.contains("tools") || params.contains("tool_choice")
    }
}

private struct ModelsApiResponse: Codable {
    let data: [OpenRouterModel]
}

private struct CachedCatalogData: Codable {
    let timestamp: Date
    let models: [OpenRouterModel]
}

public final class ModelCatalog: @unchecked Sendable {
    public static let shared = ModelCatalog()
    
    private let logger = Logger(subsystem: "com.personalresearchagent.app", category: "ModelCatalog")
    private let cacheTTL: TimeInterval = 24 * 60 * 60 // 24 hours
    
    private var cacheFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("PersonalResearchAgent", isDirectory: true) ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return appSupport.appendingPathComponent("model_catalog_cache.json")
    }
    
    private init() {}
    
    public func fetchModels(forceRefresh: Bool = false) async throws -> [OpenRouterModel] {
        if !forceRefresh, let cached = loadFromDiskCache() {
            logger.info("Loaded \(cached.count) models from disk cache.")
            return cached
        }
        
        logger.info("Fetching live models from OpenRouter API...")
        guard let url = URL(string: "https://openrouter.ai/api/v1/models") else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Personal Research Agent (macOS Native)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            logger.error("Failed to fetch models from OpenRouter: HTTP \(status)")
            throw URLError(.badServerResponse)
        }
        
        let decoded = try JSONDecoder().decode(ModelsApiResponse.self, from: data)
        saveToDiskCache(models: decoded.data)
        return decoded.data
    }
    
    public func getFreeModels(forceRefresh: Bool = false) async throws -> [OpenRouterModel] {
        let allModels = try await fetchModels(forceRefresh: forceRefresh)
        return allModels.filter { $0.isFree }
    }
    
    // MARK: - Disk Caching
    private func loadFromDiskCache() -> [OpenRouterModel]? {
        let fileURL = cacheFileURL
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        
        do {
            let data = try Data(contentsOf: fileURL)
            let cached = try JSONDecoder().decode(CachedCatalogData.self, from: data)
            if Date().timeIntervalSince(cached.timestamp) < cacheTTL {
                return cached.models
            } else {
                logger.info("Model catalog disk cache expired.")
            }
        } catch {
            logger.warning("Failed to decode model catalog disk cache: \(error.localizedDescription)")
        }
        return nil
    }
    
    private func saveToDiskCache(models: [OpenRouterModel]) {
        let fileURL = cacheFileURL
        let dir = fileURL.deletingLastPathComponent()
        
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let cacheObj = CachedCatalogData(timestamp: Date(), models: models)
            let data = try JSONEncoder().encode(cacheObj)
            try data.write(to: fileURL, options: .atomic)
            logger.info("Saved \(models.count) models to disk cache.")
        } catch {
            logger.warning("Failed to save model catalog to disk cache: \(error.localizedDescription)")
        }
    }
}
