import Foundation
import OSLog

@MainActor
public final class RunCoordinator: ObservableObject {
    public static let shared = RunCoordinator()
    
    private let logger = Logger(subsystem: "com.personalresearchagent.app", category: "RunCoordinator")
    
    private let scheduler = SchedulerService.shared
    private let wakeObserver = WakeObserver.shared
    private let agent = ResearchAgent.shared
    private let notifications = NotificationService.shared
    private let connectivity = ConnectivityMonitor.shared
    
    private var activeTask: Task<Void, Never>?
    private var isStarted = false
    
    private init() {}
    
    public func start() {
        guard !isStarted else { return }
        isStarted = true
        
        logger.info("Initializing RunCoordinator and subsystems...")
        
        notifications.setup()
        
        Task {
            _ = await notifications.requestAuthorization()
        }
        
        // Wire scheduler trigger
        scheduler.onScheduleTriggered = { [weak self] in
            self?.handleTrigger(isScheduled: true)
        }
        
        // Wire wake / missed-run trigger
        wakeObserver.onMissedRunDetected = { [weak self] in
            self?.handleTrigger(isScheduled: true)
        }
        
        // Wire manual research trigger from AppState
        AppState.shared.onManualResearchRequested = { [weak self] topic in
            self?.handleManualTrigger(topic: topic)
        }
        
        // Wire cancel research trigger from AppState
        AppState.shared.onCancelResearchRequested = { [weak self] in
            self?.cancelCurrentResearch()
        }
        
        scheduler.start()
        wakeObserver.start()
        
        logger.info("RunCoordinator initialized and active.")
    }
    
    public func cancelCurrentResearch() {
        if let task = activeTask {
            task.cancel()
            activeTask = nil
            AppState.shared.isResearching = false
            AppState.shared.activeResearchTopic = nil
            scheduler.recalculateAndArm()
            logger.info("Research run cancelled by user.")
        }
    }
    
    // MARK: - Trigger Handlers
    public func handleTrigger(isScheduled: Bool, topicOverride: String? = nil) {
        guard activeTask == nil else {
            logger.warning("Research task is already running. Ignoring duplicate trigger.")
            return
        }
        
        activeTask = Task {
            await executeResearchWithResilience(topicOverride: topicOverride, isScheduled: isScheduled)
            self.activeTask = nil
        }
    }
    
    public func handleManualTrigger(topic: String) {
        handleTrigger(isScheduled: false, topicOverride: topic)
    }
    
    // MARK: - Resilient Execution Engine
    private func executeResearchWithResilience(topicOverride: String?, isScheduled: Bool) async {
        let topic = topicOverride ?? SettingsStore.shared.activeTopic
        let maxRetries = 3
        var retryCount = 0
        
        // Check internet with retry loop
        while !connectivity.checkCurrentConnection() && retryCount < maxRetries {
            retryCount += 1
            let retryDelayMin = SettingsStore.shared.retryDelayMinutes
            logger.warning("No internet connection at trigger time. Attempt \(retryCount)/\(maxRetries). Retrying in \(retryDelayMin) minutes...")
            
            AppState.shared.status = .offline
            AppState.shared.isResearching = false
            
            let delayNanoseconds = UInt64(retryDelayMin) * 60 * 1_000_000_000
            try? await Task.sleep(nanoseconds: delayNanoseconds)
        }
        
        if !connectivity.checkCurrentConnection() {
            logger.error("Internet connection still unavailable after \(maxRetries) retries. Aborting run.")
            notifications.sendOfflineRetryExhaustedNotification(topic: topic)
            AppState.shared.status = .failed(reason: "Internet unavailable after \(maxRetries) retries")
            scheduler.recalculateAndArm()
            return
        }
        
        // Execute Research Agent
        do {
            logger.info("Executing research for topic: '\(topic)'...")
            let reportURL = try await agent.executeResearch(topicOverride: topicOverride)
            
            logger.info("Research completed successfully. Report written to: \(reportURL.path)")
            notifications.sendCompletionNotification(topic: topic, reportURL: reportURL)
            
            // Auto Read-Aloud Voice Briefing if enabled
            if SettingsStore.shared.autoReadAloudOnCompletion {
                if let markdown = try? String(contentsOf: reportURL, encoding: .utf8) {
                    SpeechService.shared.speakReportBriefing(
                        markdown: markdown,
                        topic: topic,
                        userName: SettingsStore.shared.userName,
                        assistantName: SettingsStore.shared.assistantName
                    )
                }
            }
            
            if isScheduled {
                scheduler.recordRunCompleted(at: Date())
            } else {
                scheduler.recalculateAndArm()
            }
        } catch {
            let errorMsg = error.localizedDescription
            logger.error("Research execution failed: \(errorMsg)")
            notifications.sendFailureNotification(topic: topic, reason: errorMsg)
            
            if isScheduled {
                scheduler.recalculateAndArm()
            }
        }
    }
}
