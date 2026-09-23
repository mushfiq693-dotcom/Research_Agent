import Foundation
import Speech
import AVFoundation
import AppKit
import OSLog

@MainActor
public final class VoiceInputService: NSObject, ObservableObject, SFSpeechRecognizerDelegate {
    public static let shared = VoiceInputService()
    
    private let logger = Logger(subsystem: "com.personalresearchagent.app", category: "VoiceInputService")
    
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    
    @Published public private(set) var isListening: Bool = false
    @Published public private(set) var liveTranscript: String = ""
    @Published public private(set) var statusMessage: String = "Voiceover ready"
    @Published public private(set) var hasPermissions: Bool = false
    
    private var isTapInstalled: Bool = false
    private var silenceTimer: Task<Void, Never>?
    private var restartTask: Task<Void, Never>?
    
    private override init() {
        super.init()
        speechRecognizer?.delegate = self
    }
    
    // MARK: - Permission Request
    public func requestPermissions() async -> Bool {
        // 1. Check & Request Speech Recognition Permission
        let speechStatus = SFSpeechRecognizer.authorizationStatus()
        let speechGranted: Bool
        switch speechStatus {
        case .authorized:
            speechGranted = true
        case .notDetermined:
            speechGranted = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { auth in
                    continuation.resume(returning: auth == .authorized)
                }
            }
        case .denied, .restricted:
            speechGranted = false
        @unknown default:
            speechGranted = false
        }
        
        // 2. Check & Request Microphone Permission
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        let micGranted: Bool
        switch micStatus {
        case .authorized:
            micGranted = true
        case .notDetermined:
            micGranted = await AVCaptureDevice.requestAccess(for: .audio)
        case .denied, .restricted:
            micGranted = false
        @unknown default:
            micGranted = false
        }
        
        let granted = speechGranted && micGranted
        self.hasPermissions = granted
        logger.info("Voice permissions checked: Speech=\(speechGranted), Mic=\(micGranted)")
        return granted
    }
    
    // MARK: - Start / Stop Listening
    public func startListening() {
        guard !isListening else { return }
        
        // If Jarvis is currently speaking, do not listen to himself
        if SpeechService.shared.isSpeaking {
            logger.info("Speech is active. Deferring voice listening until speech completes.")
            return
        }
        
        Task {
            let authorized = await requestPermissions()
            guard authorized else {
                self.statusMessage = "Microphone or Speech permission not granted."
                self.logger.warning("Cannot start listening: Permissions denied.")
                return
            }
            
            do {
                try self.beginAudioSession()
                self.isListening = true
                self.liveTranscript = ""
                self.statusMessage = "Listening for commands..."
                self.logger.info("Voice recognition engine started.")
            } catch {
                self.statusMessage = "Audio session error: \(error.localizedDescription)"
                self.logger.error("Failed to start audio session: \(error.localizedDescription)")
                self.cleanupAudioSession()
            }
        }
    }
    
    public func stopListening() {
        silenceTimer?.cancel()
        silenceTimer = nil
        restartTask?.cancel()
        restartTask = nil
        
        cleanupAudioSession()
        
        isListening = false
        liveTranscript = ""
        statusMessage = "Voiceover paused."
        logger.info("Voice recognition stopped.")
    }
    
    public func toggleListening() {
        if isListening {
            stopListening()
        } else {
            startListening()
        }
    }
    
    // MARK: - Safe Audio Session Setup
    private func beginAudioSession() throws {
        cleanupAudioSession()
        
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            throw NSError(
                domain: "VoiceInputService",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Speech recognizer is currently unavailable."]
            )
        }
        
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.recognitionRequest = request
        
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)
        
        // Safety check on sample rate to prevent CoreAudio assert crashes
        let formatToUse: AVAudioFormat?
        if inputFormat.sampleRate > 0 && inputFormat.channelCount > 0 {
            formatToUse = inputFormat
        } else {
            formatToUse = nil
        }
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: formatToUse) { [weak self] (buffer: AVAudioPCMBuffer, _: AVAudioTime) in
            self?.recognitionRequest?.append(buffer)
        }
        isTapInstalled = true
        
        audioEngine.prepare()
        try audioEngine.start()
        
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                
                if let result = result {
                    let transcribedString = result.bestTranscription.formattedString
                    self.liveTranscript = transcribedString
                    self.resetSilenceTimer(for: transcribedString)
                }
                
                if let error = error {
                    let nsError = error as NSError
                    // Domain=kAFAssistantErrorDomain Code=216: Request canceled; Code=1110: No speech detected
                    if nsError.domain != "kAFAssistantErrorDomain" || (nsError.code != 216 && nsError.code != 1110) {
                        self.logger.warning("Recognition error: \(error.localizedDescription)")
                    }
                    
                    if self.isListening {
                        self.restartListeningAfterDelay()
                    }
                }
            }
        }
    }
    
    private func cleanupAudioSession() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        
        if isTapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            isTapInstalled = false
        }
        
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        
        recognitionTask?.cancel()
        recognitionTask = nil
    }
    
    private func restartListeningAfterDelay() {
        guard SettingsStore.shared.isVoiceControlEnabled else {
            stopListening()
            return
        }
        
        restartTask?.cancel()
        restartTask = Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled, SettingsStore.shared.isVoiceControlEnabled, !SpeechService.shared.isSpeaking else { return }
            self.startListening()
        }
    }
    
    private func resetSilenceTimer(for text: String) {
        silenceTimer?.cancel()
        silenceTimer = Task {
            // Wait for 1.4 seconds of silence after speech before executing
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            guard !Task.isCancelled else { return }
            
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            
            self.handleVoiceCommand(trimmed)
        }
    }
    
    // MARK: - Command Parser & Handler
    public func handleVoiceCommand(_ rawCommand: String) {
        let command = rawCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return }
        
        logger.info("Processing voice command: '\(command)'")
        let lower = command.lowercased()
        let user = SettingsStore.shared.userName
        let assistant = SettingsStore.shared.assistantName
        
        // 1. Stop / Quiet Command
        if lower.contains("stop") || lower.contains("quiet") || lower.contains("shut up") || lower.contains("pause") {
            SpeechService.shared.stopSpeaking()
            SpeechService.shared.speak(text: "Stopping now, \(user).")
            statusMessage = "Stopped voice output."
            restartListeningAfterDelay()
            return
        }
        
        // 2. Greeting / Status Inquiry
        if lower.contains("what's up") || lower.contains("how are you") || lower == "hey \(assistant.lowercased())" || lower == assistant.lowercased() || lower == "hello" || lower.contains("status") || lower.contains("who are you") {
            SpeechService.shared.speak(
                text: "Hello \(user)! I am \(assistant), your personal research agent. What topic would you like me to research today?",
                rate: SettingsStore.shared.voiceRate,
                pitch: SettingsStore.shared.voicePitch
            )
            statusMessage = "Jarvis ready for research topic."
            restartListeningAfterDelay()
            return
        }
        
        // 3. Open Reports Folder
        if lower.contains("open report") || lower.contains("open folder") || lower.contains("show report") || lower.contains("open directory") {
            AppState.shared.openReportsFolder()
            SpeechService.shared.speak(
                text: "Opening your research reports folder, \(user).",
                rate: SettingsStore.shared.voiceRate,
                pitch: SettingsStore.shared.voicePitch
            )
            statusMessage = "Opened reports folder."
            restartListeningAfterDelay()
            return
        }
        
        // 4. Read Latest Research Briefing
        if lower.contains("read report") || lower.contains("read briefing") || lower.contains("summarize report") || lower.contains("listen to report") || lower.contains("brief me") {
            if let reportPath = AppState.shared.lastReportPath ?? findLatestReportPath(),
               let md = try? String(contentsOfFile: reportPath, encoding: .utf8) {
                SpeechService.shared.speakReportBriefing(
                    markdown: md,
                    topic: SettingsStore.shared.activeTopic,
                    userName: user,
                    assistantName: assistant
                )
                statusMessage = "Reading briefing aloud..."
            } else {
                SpeechService.shared.speak(
                    text: "No recent research report found to read, \(user).",
                    rate: SettingsStore.shared.voiceRate,
                    pitch: SettingsStore.shared.voicePitch
                )
                statusMessage = "No report available."
            }
            restartListeningAfterDelay()
            return
        }
        
        // 5. Research Topic Command
        let extractedTopic = extractResearchTopic(from: command)
        let topicToRun = extractedTopic.isEmpty ? command : extractedTopic
        
        SpeechService.shared.speak(
            text: "Starting research on \(topicToRun) right away, \(user).",
            rate: SettingsStore.shared.voiceRate,
            pitch: SettingsStore.shared.voicePitch
        )
        statusMessage = "Researching: '\(topicToRun)'"
        AppState.shared.manualTopicInput = topicToRun
        AppState.shared.startManualResearch()
        
        restartListeningAfterDelay()
    }
    
    public func extractResearchTopic(from text: String) -> String {
        var clean = text
        let prefixesToRemove = [
            "hey jarvis", "jarvis", "hey assistant", "assistant",
            "please research on", "please research", "research on", "research",
            "search for", "search", "look up", "find out about", "find me information about", "find",
            "can you research", "tell me about"
        ]
        
        for prefix in prefixesToRemove {
            if let range = clean.range(of: prefix, options: [.caseInsensitive, .anchored]) {
                clean.removeSubrange(range)
            } else if let range = clean.range(of: prefix, options: .caseInsensitive) {
                if clean.distance(from: clean.startIndex, to: range.lowerBound) < 15 {
                    clean.removeSubrange(clean.startIndex..<range.upperBound)
                }
            }
        }
        
        return clean.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ":,.-")))
    }
    
    private func findLatestReportPath() -> String? {
        let dirURL = SettingsStore.shared.reportsDirectoryURL
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(at: dirURL, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else {
            return nil
        }
        
        var latestURL: URL?
        var latestDate: Date = .distantPast
        
        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "md" else { continue }
            if let attrs = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]),
               let date = attrs.contentModificationDate, date > latestDate {
                latestDate = date
                latestURL = fileURL
            }
        }
        return latestURL?.path
    }
}
