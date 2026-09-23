import Foundation
import SwiftUI
import OSLog

public enum TopicPreset: String, CaseIterable, Identifiable, Codable, Sendable {
    case aiNews = "Latest AI news"
    case webDev = "Web Development Trends"
    case aiAgents = "AI Agents & Multi-Agent Systems"
    case programming = "Programming Languages & Tooling"
    case cybersecurity = "Cybersecurity & Vulnerabilities"
    case custom = "Custom Topic"
    
    public var id: String { rawValue }
}

public enum ResearchDepth: String, CaseIterable, Identifiable, Codable, Sendable {
    case quick = "Quick"
    case standard = "Standard"
    case deep = "Deep"
    
    public var id: String { rawValue }
    
    public var maxIterations: Int {
        switch self {
        case .quick: return 1
        case .standard: return 2
        case .deep: return 3
        }
    }
    
    public var maxSearchQueries: Int {
        switch self {
        case .quick: return 3
        case .standard: return 6
        case .deep: return 9
        }
    }
    
    public var resultsPerQuery: Int {
        switch self {
        case .quick: return 3
        case .standard: return 5
        case .deep: return 7
        }
    }
    
    public var maxPagesFetched: Int {
        switch self {
        case .quick: return 4
        case .standard: return 8
        case .deep: return 12
        }
    }
    
    public var maxCharactersPerPage: Int {
        switch self {
        case .quick: return 8_000
        case .standard: return 12_000
        case .deep: return 16_000
        }
    }
    
    public var maxModelCalls: Int {
        switch self {
        case .quick: return 4
        case .standard: return 8
        case .deep: return 12
        }
    }
    
    public var description: String {
        switch self {
        case .quick: return "Lean & fast. Max 1 iteration, 3 queries, 4 pages."
        case .standard: return "Balanced. Max 2 iterations, 6 queries, 8 pages."
        case .deep: return "Thorough. Max 3 iterations, 9 queries, 12 pages."
        }
    }
}

public enum ScheduleFrequency: String, CaseIterable, Identifiable, Codable, Sendable {
    case daily = "Daily"
    case weekly = "Weekly"
    
    public var id: String { rawValue }
}

public enum Weekday: Int, CaseIterable, Identifiable, Codable, Sendable {
    case sunday = 1, monday = 2, tuesday = 3, wednesday = 4, thursday = 5, friday = 6, saturday = 7
    
    public var id: Int { rawValue }
    
    public var name: String {
        switch self {
        case .sunday: return "Sunday"
        case .monday: return "Monday"
        case .tuesday: return "Tuesday"
        case .wednesday: return "Wednesday"
        case .thursday: return "Thursday"
        case .friday: return "Friday"
        case .saturday: return "Saturday"
        }
    }
}

@MainActor
public final class SettingsStore: ObservableObject {
    public static let shared = SettingsStore()
    
    private let defaults = UserDefaults.standard
    private let logger = Logger(subsystem: "com.personalresearchagent.app", category: "SettingsStore")
    
    // MARK: - Keys
    private enum Keys {
        static let topicPreset = "pra_topic_preset"
        static let customTopic = "pra_custom_topic"
        static let scheduleHour = "pra_schedule_hour"
        static let scheduleMinute = "pra_schedule_minute"
        static let scheduleFrequency = "pra_schedule_frequency"
        static let scheduleWeekday = "pra_schedule_weekday"
        static let researchDepth = "pra_research_depth"
        static let fastModel = "pra_fast_model"
        static let strongModel = "pra_strong_model"
        static let fallbackModels = "pra_fallback_models"
        static let reportsDirectory = "pra_reports_directory"
        static let notificationsEnabled = "pra_notifications_enabled"
        static let runMissedResearch = "pra_run_missed_research"
        static let retryDelayMinutes = "pra_retry_delay_minutes"
        static let delayBetweenCallsSeconds = "pra_delay_between_calls_seconds"
        static let privacyNoticeAcknowledged = "pra_privacy_notice_ack"
        static let debugIntervalMode = "pra_debug_interval_mode"
        static let userName = "pra_user_name"
        static let assistantName = "pra_assistant_name"
        static let autoReadAloud = "pra_auto_read_aloud"
        static let voiceRate = "pra_voice_rate"
        static let voicePitch = "pra_voice_pitch"
        static let preferredVoiceId = "pra_preferred_voice_id"
    }
    
    // MARK: - Published Properties
    @Published public var topicPreset: TopicPreset {
        didSet { defaults.set(topicPreset.rawValue, forKey: Keys.topicPreset) }
    }
    
    @Published public var customTopic: String {
        didSet { defaults.set(customTopic, forKey: Keys.customTopic) }
    }
    
    @Published public var scheduleHour: Int {
        didSet { defaults.set(scheduleHour, forKey: Keys.scheduleHour) }
    }
    
    @Published public var scheduleMinute: Int {
        didSet { defaults.set(scheduleMinute, forKey: Keys.scheduleMinute) }
    }
    
    @Published public var scheduleFrequency: ScheduleFrequency {
        didSet { defaults.set(scheduleFrequency.rawValue, forKey: Keys.scheduleFrequency) }
    }
    
    @Published public var scheduleWeekday: Weekday {
        didSet { defaults.set(scheduleWeekday.rawValue, forKey: Keys.scheduleWeekday) }
    }
    
    @Published public var researchDepth: ResearchDepth {
        didSet { defaults.set(researchDepth.rawValue, forKey: Keys.researchDepth) }
    }
    
    @Published public var fastModel: String {
        didSet { defaults.set(fastModel, forKey: Keys.fastModel) }
    }
    
    @Published public var strongModel: String {
        didSet { defaults.set(strongModel, forKey: Keys.strongModel) }
    }
    
    @Published public var fallbackModels: [String] {
        didSet { defaults.set(fallbackModels, forKey: Keys.fallbackModels) }
    }
    
    @Published public var reportsDirectoryPath: String {
        didSet { defaults.set(reportsDirectoryPath, forKey: Keys.reportsDirectory) }
    }
    
    @Published public var notificationsEnabled: Bool {
        didSet { defaults.set(notificationsEnabled, forKey: Keys.notificationsEnabled) }
    }
    
    @Published public var runMissedResearch: Bool {
        didSet { defaults.set(runMissedResearch, forKey: Keys.runMissedResearch) }
    }
    
    @Published public var retryDelayMinutes: Int {
        didSet { defaults.set(retryDelayMinutes, forKey: Keys.retryDelayMinutes) }
    }
    
    @Published public var delayBetweenCallsSeconds: Double {
        didSet { defaults.set(delayBetweenCallsSeconds, forKey: Keys.delayBetweenCallsSeconds) }
    }
    
    @Published public var privacyNoticeAcknowledged: Bool {
        didSet { defaults.set(privacyNoticeAcknowledged, forKey: Keys.privacyNoticeAcknowledged) }
    }
    
    @Published public var isDebugIntervalMode: Bool {
        didSet { defaults.set(isDebugIntervalMode, forKey: Keys.debugIntervalMode) }
    }
    
    @Published public var userName: String {
        didSet { defaults.set(userName, forKey: Keys.userName) }
    }
    
    @Published public var assistantName: String {
        didSet { defaults.set(assistantName, forKey: Keys.assistantName) }
    }
    
    @Published public var autoReadAloudOnCompletion: Bool {
        didSet { defaults.set(autoReadAloudOnCompletion, forKey: Keys.autoReadAloud) }
    }
    
    @Published public var voiceRate: Float {
        didSet { defaults.set(voiceRate, forKey: Keys.voiceRate) }
    }
    
    @Published public var voicePitch: Float {
        didSet { defaults.set(voicePitch, forKey: Keys.voicePitch) }
    }
    
    @Published public var preferredVoiceIdentifier: String {
        didSet { defaults.set(preferredVoiceIdentifier, forKey: Keys.preferredVoiceId) }
    }
    
    // MARK: - Initializer
    private init() {
        let presetStr = defaults.string(forKey: Keys.topicPreset) ?? TopicPreset.aiNews.rawValue
        self.topicPreset = TopicPreset(rawValue: presetStr) ?? .aiNews
        self.customTopic = defaults.string(forKey: Keys.customTopic) ?? ""
        
        self.scheduleHour = defaults.object(forKey: Keys.scheduleHour) != nil ? defaults.integer(forKey: Keys.scheduleHour) : 8
        self.scheduleMinute = defaults.object(forKey: Keys.scheduleMinute) != nil ? defaults.integer(forKey: Keys.scheduleMinute) : 0
        
        let freqStr = defaults.string(forKey: Keys.scheduleFrequency) ?? ScheduleFrequency.daily.rawValue
        self.scheduleFrequency = ScheduleFrequency(rawValue: freqStr) ?? .daily
        
        let weekdayRaw = defaults.integer(forKey: Keys.scheduleWeekday)
        self.scheduleWeekday = Weekday(rawValue: weekdayRaw == 0 ? 2 : weekdayRaw) ?? .monday
        
        let depthStr = defaults.string(forKey: Keys.researchDepth) ?? ResearchDepth.standard.rawValue
        self.researchDepth = ResearchDepth(rawValue: depthStr) ?? .standard
        
        self.fastModel = defaults.string(forKey: Keys.fastModel) ?? "openrouter/free"
        self.strongModel = defaults.string(forKey: Keys.strongModel) ?? "openrouter/free"
        
        let savedFallbacks = defaults.stringArray(forKey: Keys.fallbackModels)
        self.fallbackModels = savedFallbacks ?? [
            "openrouter/free",
            "qwen/qwen3.8-27b:free",
            "nex-agi/nex-n2.5-pro:free"
        ]
        
        let defaultDocsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Personal Research Agent").path ?? "~/Documents/Personal Research Agent"
        self.reportsDirectoryPath = defaults.string(forKey: Keys.reportsDirectory) ?? defaultDocsURL
        
        self.notificationsEnabled = defaults.object(forKey: Keys.notificationsEnabled) != nil ? defaults.bool(forKey: Keys.notificationsEnabled) : true
        self.runMissedResearch = defaults.object(forKey: Keys.runMissedResearch) != nil ? defaults.bool(forKey: Keys.runMissedResearch) : true
        self.retryDelayMinutes = defaults.object(forKey: Keys.retryDelayMinutes) != nil ? defaults.integer(forKey: Keys.retryDelayMinutes) : 10
        self.delayBetweenCallsSeconds = defaults.object(forKey: Keys.delayBetweenCallsSeconds) != nil ? defaults.double(forKey: Keys.delayBetweenCallsSeconds) : 2.0
        self.privacyNoticeAcknowledged = defaults.bool(forKey: Keys.privacyNoticeAcknowledged)
        self.isDebugIntervalMode = defaults.bool(forKey: Keys.debugIntervalMode)
        
        self.userName = defaults.string(forKey: Keys.userName) ?? "Mushfiq"
        self.assistantName = defaults.string(forKey: Keys.assistantName) ?? "Jarvis"
        self.autoReadAloudOnCompletion = defaults.bool(forKey: Keys.autoReadAloud)
        self.voiceRate = defaults.object(forKey: Keys.voiceRate) != nil ? defaults.float(forKey: Keys.voiceRate) : 0.48
        self.voicePitch = defaults.object(forKey: Keys.voicePitch) != nil ? defaults.float(forKey: Keys.voicePitch) : 0.80
        self.preferredVoiceIdentifier = defaults.string(forKey: Keys.preferredVoiceId) ?? ""
    }
    
    // MARK: - Effective Active Topic
    public var activeTopic: String {
        if topicPreset == .custom {
            let trimmed = customTopic.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Latest AI news" : trimmed
        }
        return topicPreset.rawValue
    }
    
    // MARK: - Reports URL
    public var reportsDirectoryURL: URL {
        if reportsDirectoryPath.hasPrefix("~") {
            let expanded = NSString(string: reportsDirectoryPath).expandingTildeInPath
            return URL(fileURLWithPath: expanded, isDirectory: true)
        }
        return URL(fileURLWithPath: reportsDirectoryPath, isDirectory: true)
    }
}
