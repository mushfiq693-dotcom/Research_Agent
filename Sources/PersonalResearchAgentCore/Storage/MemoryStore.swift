import Foundation
import OSLog

public struct RunRecord: Codable, Sendable {
    public let id: String
    public let timestamp: Date
    public let topic: String
    public let reportPath: String
    public let sourceUrls: [String]
    public let storyTitles: [String]
    public let isSuccess: Bool
    public let failureReason: String?
    
    public init(
        id: String = UUID().uuidString,
        timestamp: Date = Date(),
        topic: String,
        reportPath: String,
        sourceUrls: [String] = [],
        storyTitles: [String] = [],
        isSuccess: Bool = true,
        failureReason: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.topic = topic
        self.reportPath = reportPath
        self.sourceUrls = sourceUrls
        self.storyTitles = storyTitles
        self.isSuccess = isSuccess
        self.failureReason = failureReason
    }
}

public struct MemoryData: Codable, Sendable {
    public var lastSuccessAt: Date?
    public var lastFailureAt: Date?
    public var lastFailureReason: String?
    public var coveredUrls: Set<String>
    public var coveredStoryTitles: [String]
    public var recentRuns: [RunRecord]
    
    public init(
        lastSuccessAt: Date? = nil,
        lastFailureAt: Date? = nil,
        lastFailureReason: String? = nil,
        coveredUrls: Set<String> = [],
        coveredStoryTitles: [String] = [],
        recentRuns: [RunRecord] = []
    ) {
        self.lastSuccessAt = lastSuccessAt
        self.lastFailureAt = lastFailureAt
        self.lastFailureReason = lastFailureReason
        self.coveredUrls = coveredUrls
        self.coveredStoryTitles = coveredStoryTitles
        self.recentRuns = recentRuns
    }
}

public protocol MemoryStoreProtocol: Sendable {
    func loadMemory() async -> MemoryData
    func saveMemory(_ data: MemoryData) async throws
    func recordRun(_ record: RunRecord) async throws
}

public actor LocalMemoryStore: MemoryStoreProtocol {
    public static let shared = LocalMemoryStore()
    
    private let logger = Logger(subsystem: "com.personalresearchagent.app", category: "LocalMemoryStore")
    private var cachedData: MemoryData?
    
    private var memoryFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("PersonalResearchAgent", isDirectory: true) ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return appSupport.appendingPathComponent("memory.json")
    }
    
    public init() {}
    
    public func loadMemory() -> MemoryData {
        if let cached = cachedData {
            return cached
        }
        
        let fileURL = memoryFileURL
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            let empty = MemoryData()
            self.cachedData = empty
            return empty
        }
        
        do {
            let data = try Data(contentsOf: fileURL)
            let loaded = try JSONDecoder().decode(MemoryData.self, from: data)
            self.cachedData = loaded
            return loaded
        } catch {
            logger.warning("Failed to decode memory.json: \(error.localizedDescription). Initializing fresh memory.")
            let empty = MemoryData()
            self.cachedData = empty
            return empty
        }
    }
    
    public func saveMemory(_ data: MemoryData) throws {
        self.cachedData = data
        let fileURL = memoryFileURL
        let dir = fileURL.deletingLastPathComponent()
        
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoded = try JSONEncoder().encode(data)
        try encoded.write(to: fileURL, options: .atomic)
        logger.info("Saved agent memory state to memory.json")
    }
    
    public func recordRun(_ record: RunRecord) throws {
        var mem = loadMemory()
        
        if record.isSuccess {
            mem.lastSuccessAt = record.timestamp
            for u in record.sourceUrls {
                mem.coveredUrls.insert(u)
            }
            for t in record.storyTitles where !mem.coveredStoryTitles.contains(t) {
                mem.coveredStoryTitles.append(t)
            }
            // Keep recent story titles bounded to 150
            if mem.coveredStoryTitles.count > 150 {
                mem.coveredStoryTitles = Array(mem.coveredStoryTitles.suffix(150))
            }
        } else {
            mem.lastFailureAt = record.timestamp
            mem.lastFailureReason = record.failureReason
        }
        
        mem.recentRuns.insert(record, at: 0)
        if mem.recentRuns.count > 30 {
            mem.recentRuns = Array(mem.recentRuns.prefix(30))
        }
        
        try saveMemory(mem)
    }
}
