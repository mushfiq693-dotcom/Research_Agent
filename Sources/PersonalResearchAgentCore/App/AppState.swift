import Foundation
import SwiftUI
import AppKit
import OSLog

public enum ResearchStep: String, Sendable {
    case planning = "Planning"
    case searching = "Searching web"
    case fetching = "Reading sources"
    case analyzing = "Analysing"
    case writing = "Writing report"
}

public enum AgentStatus: Equatable, Sendable {
    case idle(nextRunText: String)
    case researching(step: ResearchStep)
    case completed(time: Date, reportPath: String?)
    case failed(reason: String)
    case offline
    case rateLimited(retryInSeconds: Int?)
    
    public var displayText: String {
        switch self {
        case .idle(let nextRunText):
            return "Agent is active. Next research: \(nextRunText)"
        case .researching(let step):
            return "Researching... Current step: \(step.rawValue)"
        case .completed(let time, _):
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return "Research completed. Last run: \(formatter.string(from: time))"
        case .failed(let reason):
            return "Research failed. Reason: \(reason)"
        case .offline:
            return "Waiting for internet connection"
        case .rateLimited(let sec):
            if let sec = sec, sec > 0 {
                return "Waiting for free-tier rate limit (\(sec)s)"
            }
            return "Waiting for free-tier rate limit"
        }
    }
    
    public var iconName: String {
        switch self {
        case .idle:
            return "sparkles"
        case .researching:
            return "arrow.triangle.2.circlepath"
        case .completed:
            return "checkmark.circle.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        case .offline:
            return "wifi.slash"
        case .rateLimited:
            return "clock.badge.exclamationmark"
        }
    }
    
    public var statusColor: Color {
        switch self {
        case .idle:
            return .accentColor
        case .researching:
            return .blue
        case .completed:
            return .green
        case .failed:
            return .red
        case .offline:
            return .orange
        case .rateLimited:
            return .purple
        }
    }
}

@MainActor
public final class AppState: ObservableObject {
    public static let shared = AppState()
    
    private let logger = Logger(subsystem: "com.personalresearchagent.app", category: "AppState")
    
    @Published public var status: AgentStatus = .idle(nextRunText: "08:00 AM")
    @Published public var isResearching: Bool = false
    @Published public var isShowingSettings: Bool = false
    @Published public var isShowingManualInput: Bool = false
    @Published public var manualTopicInput: String = ""
    @Published public var lastReportPath: String?
    
    public var onManualResearchRequested: (@MainActor (String) -> Void)?
    
    private init() {}
    
    // MARK: - Actions
    public func startManualResearch() {
        let topicToRun: String
        let trimmed = manualTopicInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            topicToRun = trimmed
        } else {
            topicToRun = SettingsStore.shared.activeTopic
        }
        
        logger.info("Manual research triggered with topic: \(topicToRun)")
        isShowingManualInput = false
        manualTopicInput = ""
        
        if let handler = onManualResearchRequested {
            handler(topicToRun)
        } else {
            Task {
                do {
                    _ = try await ResearchAgent.shared.executeResearch(topicOverride: topicToRun)
                } catch {
                    logger.error("Manual research execution failed: \(error.localizedDescription)")
                }
            }
        }
    }
    
    public func openReportsFolder() {
        let folderURL = SettingsStore.shared.reportsDirectoryURL
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: folderURL.path) {
            try? fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
        }
        NSWorkspace.shared.open(folderURL)
    }
    
    public func openLastReport() {
        guard let path = lastReportPath else {
            openReportsFolder()
            return
        }
        let url = URL(fileURLWithPath: path)
        if FileManager.default.fileExists(atPath: path) {
            NSWorkspace.shared.open(url)
        } else {
            openReportsFolder()
        }
    }
    
    public func openSettingsWindow() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        self.isShowingSettings = true
    }
    
    public func quit() {
        logger.info("User requested application quit.")
        NSApplication.shared.terminate(nil)
    }
}
