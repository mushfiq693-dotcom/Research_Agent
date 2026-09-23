import Foundation
import OSLog

public struct ReportSourceMetadata: Codable, Sendable {
    public let title: String
    public let url: String
    public let status: String
    
    public init(title: String, url: String, status: String) {
        self.title = title
        self.url = url
        self.status = status
    }
}

public struct TokenUsageMetadata: Codable, Sendable {
    public let promptTokens: Int
    public let completionTokens: Int
    public let totalTokens: Int
    
    public init(promptTokens: Int, completionTokens: Int, totalTokens: Int) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = totalTokens
    }
}

public struct ReportMetadata: Codable, Sendable {
    public let topic: String
    public let depth: String
    public let startTime: Date
    public let endTime: Date
    public let durationSeconds: Double
    public let queries: [String]
    public let sources: [ReportSourceMetadata]
    public let modelsUsed: [String]
    public let tokenUsage: TokenUsageMetadata
    public let modelCallCount: Int
    public let isPartial: Bool
    public let limitsHit: [String]
    
    public init(
        topic: String,
        depth: String,
        startTime: Date,
        endTime: Date,
        durationSeconds: Double,
        queries: [String],
        sources: [ReportSourceMetadata],
        modelsUsed: [String],
        tokenUsage: TokenUsageMetadata,
        modelCallCount: Int,
        isPartial: Bool,
        limitsHit: [String]
    ) {
        self.topic = topic
        self.depth = depth
        self.startTime = startTime
        self.endTime = endTime
        self.durationSeconds = durationSeconds
        self.queries = queries
        self.sources = sources
        self.modelsUsed = modelsUsed
        self.tokenUsage = tokenUsage
        self.modelCallCount = modelCallCount
        self.isPartial = isPartial
        self.limitsHit = limitsHit
    }
}

public final class ReportWriter: Sendable {
    public static let shared = ReportWriter()
    private let logger = Logger(subsystem: "com.personalresearchagent.app", category: "ReportWriter")
    
    public init() {}
    
    public func writeReport(
        markdownContent: String,
        metadata: ReportMetadata,
        baseDirectoryURL: URL
    ) throws -> (markdownURL: URL, jsonURL: URL) {
        let calendar = Calendar.current
        let date = metadata.endTime
        let yearStr = String(calendar.component(.year, from: date))
        let monthStr = String(format: "%02d", calendar.component(.month, from: date))
        let dayStr = String(format: "%02d", calendar.component(.day, from: date))
        
        let targetDirectory = baseDirectoryURL
            .appendingPathComponent(yearStr, isDirectory: true)
            .appendingPathComponent(monthStr, isDirectory: true)
        
        try FileManager.default.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
        
        let slug = Self.slugify(metadata.topic)
        let baseFilename = "\(yearStr)-\(monthStr)-\(dayStr)-\(slug)"
        
        var markdownURL = targetDirectory.appendingPathComponent("\(baseFilename).md")
        var jsonURL = targetDirectory.appendingPathComponent("\(baseFilename).json")
        
        // If file already exists, add time suffix
        if FileManager.default.fileExists(atPath: markdownURL.path) {
            let timeFormatter = DateFormatter()
            timeFormatter.dateFormat = "HHmm"
            let timeSuffix = timeFormatter.string(from: date)
            markdownURL = targetDirectory.appendingPathComponent("\(baseFilename)-\(timeSuffix).md")
            jsonURL = targetDirectory.appendingPathComponent("\(baseFilename)-\(timeSuffix).json")
        }
        
        // Write Markdown report
        try markdownContent.write(to: markdownURL, atomically: true, encoding: .utf8)
        
        // Write JSON metadata
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let jsonData = try encoder.encode(metadata)
        try jsonData.write(to: jsonURL, options: .atomic)
        
        logger.info("Saved report to \(markdownURL.path) with sibling JSON metadata.")
        return (markdownURL, jsonURL)
    }
    
    public static func slugify(_ text: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let lower = text.lowercased()
        let converted = lower.components(separatedBy: allowed.inverted).filter { !$0.isEmpty }.joined(separator: "-")
        return converted.isEmpty ? "research-report" : String(converted.prefix(40))
    }
}
