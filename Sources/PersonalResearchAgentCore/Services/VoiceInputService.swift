import Foundation
import Speech
import AVFoundation
import AppKit
import OSLog

// MARK: - Non-Actor Audio Engine Worker
/// Encapsulates AVAudioEngine so real-time audio tap callbacks run on background audio queues
/// without triggering Swift 6 @MainActor executor assertions.
final class AudioEngineManager: @unchecked Sendable {
    private let audioEngine = AVAudioEngine()
    private var isTapInstalled = false
    private weak var currentRequest: SFSpeechAudioBufferRecognitionRequest?
    
    func start(request: SFSpeechAudioBufferRecognitionRequest) throws {
        self.currentRequest = request
        let inputNode = audioEngine.inputNode
        
        if isTapInstalled {
            inputNode.removeTap(onBus: 0)
            isTapInstalled = false
        }
        
        audioEngine.reset()
        
        let inputFormat = inputNode.inputFormat(forBus: 0)
        let formatToUse: AVAudioFormat? = (inputFormat.sampleRate > 0 && inputFormat.channelCount > 0) ? inputFormat : nil
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: formatToUse) { [weak self] (buffer: AVAudioPCMBuffer, _: AVAudioTime) in
            self?.currentRequest?.append(buffer)
        }
        isTapInstalled = true
        
        audioEngine.prepare()
        try audioEngine.start()
    }
    
    func stop() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        if isTapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            isTapInstalled = false
        }
        audioEngine.reset()
        currentRequest = nil
    }
}

// MARK: - Conversation State
public enum VoiceConversationState: Equatable, Sendable {
    case idle
    case awaitingTopic
}

// MARK: - VoiceInputService
@MainActor
public final class VoiceInputService: NSObject, ObservableObject, SFSpeechRecognizerDelegate {
    public static let shared = VoiceInputService()
    
    private let logger = Logger(subsystem: "com.personalresearchagent.app", category: "VoiceInputService")
    
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioManager = AudioEngineManager()
    
    @Published public private(set) var isListening: Bool = false
    @Published public private(set) var liveTranscript: String = ""
    @Published public private(set) var statusMessage: String = "Voiceover ready"
    @Published public private(set) var hasPermissions: Bool = false
    @Published public private(set) var conversationState: VoiceConversationState = .idle
    
    private var silenceTimer: Task<Void, Never>?
    private var restartTask: Task<Void, Never>?
    private var isProcessingCommand: Bool = false
    
    private override init() {
        super.init()
        speechRecognizer?.delegate = self
    }
    
    // MARK: - Permission Request
    public func requestPermissions() async -> Bool {
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
        
        // Never start listening while Jarvis is actively speaking
        if SpeechService.shared.isSpeaking {
            logger.info("Speech is active. Voice listening will resume after speech completes.")
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
                self.statusMessage = self.conversationState == .awaitingTopic ? "Listening for topic..." : "Listening for commands..."
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
        
        try audioManager.start(request: request)
        
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                
                // If speech output started while buffer arrived, ignore
                if SpeechService.shared.isSpeaking {
                    return
                }
                
                if let result = result {
                    let transcribedString = result.bestTranscription.formattedString
                    self.liveTranscript = transcribedString
                    self.resetSilenceTimer(for: transcribedString)
                }
                
                if let error = error {
                    let nsError = error as NSError
                    if nsError.domain != "kAFAssistantErrorDomain" || (nsError.code != 216 && nsError.code != 1110) {
                        self.logger.warning("Recognition error: \(error.localizedDescription)")
                    }
                    
                    if self.isListening && !SpeechService.shared.isSpeaking {
                        self.restartListeningAfterDelay()
                    }
                }
            }
        }
    }
    
    private func cleanupAudioSession() {
        audioManager.stop()
        
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
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled, SettingsStore.shared.isVoiceControlEnabled, !SpeechService.shared.isSpeaking else { return }
            self.startListening()
        }
    }
    
    private func resetSilenceTimer(for text: String) {
        silenceTimer?.cancel()
        silenceTimer = Task {
            // Wait for 1.3 seconds of silence
            try? await Task.sleep(nanoseconds: 1_300_000_000)
            guard !Task.isCancelled, !SpeechService.shared.isSpeaking else { return }
            
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            
            self.handleVoiceCommand(trimmed)
        }
    }
    
    // MARK: - Command Parser & Conversational Handler
    public func handleVoiceCommand(_ rawCommand: String) {
        guard !isProcessingCommand else { return }
        let command = rawCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard command.count >= 2 else { return }
        
        let lower = command.lowercased()
        let user = SettingsStore.shared.userName
        let assistant = SettingsStore.shared.assistantName
        
        // 0. Acoustic Echo Filter: Discard if recognizer simply picked up Jarvis's own last utterance
        let lastSpoken = SpeechService.shared.lastSpokenText
        if !lastSpoken.isEmpty && (lower.contains("what topic would you like") || lower.contains("research briefing") || lower == lastSpoken || (lastSpoken.count > 15 && lower.contains(lastSpoken.prefix(20)))) {
            logger.info("Discarding acoustic echo from assistant's own voice: '\(command)'")
            liveTranscript = ""
            return
        }
        
        logger.info("Processing voice command: '\(command)' (state: \(String(describing: self.conversationState)))")
        isProcessingCommand = true
        defer { isProcessingCommand = false }
        
        // 1. Stop / Quiet / Cancel Command
        if lower.contains("stop") || lower.contains("quiet") || lower.contains("shut up") || lower.contains("pause") || lower == "cancel" {
            SpeechService.shared.stopSpeaking()
            conversationState = .idle
            statusMessage = "Voice output stopped."
            liveTranscript = ""
            return
        }
        
        // 2. Open Reports Folder
        if lower.contains("open report") || lower.contains("open folder") || lower.contains("show report") || lower.contains("open directory") {
            AppState.shared.openReportsFolder()
            conversationState = .idle
            SpeechService.shared.speak(
                text: "Opening your research reports folder, \(user).",
                rate: SettingsStore.shared.voiceRate,
                pitch: SettingsStore.shared.voicePitch
            )
            statusMessage = "Opened reports folder."
            liveTranscript = ""
            return
        }
        
        // 3. Read Latest Research Briefing
        if lower.contains("read report") || lower.contains("read briefing") || lower.contains("summarize report") || lower.contains("listen to report") || lower.contains("brief me") {
            conversationState = .idle
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
            liveTranscript = ""
            return
        }
        
        // 4. Greeting / Conversational Status Inquiry (DO NOT START RESEARCH)
        if lower.contains("what's up") || lower.contains("how are you") || lower == "hey \(assistant.lowercased())" || lower == assistant.lowercased() || lower == "hello" || lower.contains("hello \(assistant.lowercased())") || lower.contains("status") || lower.contains("who are you") || lower.contains("good morning") {
            conversationState = .awaitingTopic
            SpeechService.shared.speak(
                text: "Hello \(user)! I am \(assistant), your personal research agent. What topic would you like me to research today?",
                rate: SettingsStore.shared.voiceRate,
                pitch: SettingsStore.shared.voicePitch
            )
            statusMessage = "Waiting for your research topic..."
            liveTranscript = ""
            return
        }
        
        // 5. Explicit Research Request ("Jarvis research X", "Search for X", "Find X")
        let explicitTopic = extractExplicitResearchTopic(from: command)
        if !explicitTopic.isEmpty {
            conversationState = .idle
            triggerResearch(for: explicitTopic, user: user)
            liveTranscript = ""
            return
        }
        
        // 6. If we were awaiting a research topic after a greeting, treat this input as the topic!
        if conversationState == .awaitingTopic {
            let topic = cleanTopic(command)
            if !topic.isEmpty && topic.count > 2 {
                conversationState = .idle
                triggerResearch(for: topic, user: user)
                liveTranscript = ""
                return
            }
        }
        
        // 7. General Assistant query with assistant's name (e.g. "Jarvis ...")
        if lower.contains(assistant.lowercased()) {
            SpeechService.shared.speak(
                text: "I am ready, \(user). You can say 'Research' followed by a topic, or say 'Read briefing'.",
                rate: SettingsStore.shared.voiceRate,
                pitch: SettingsStore.shared.voicePitch
            )
            statusMessage = "Say 'Research [topic]' or 'Read briefing'."
            liveTranscript = ""
            return
        }
        
        // Ambient room noise / unrecognized speech: do nothing and stay idle peacefully
        logger.info("Ignoring ambient / non-command speech: '\(command)'")
        liveTranscript = ""
    }
    
    private func triggerResearch(for topic: String, user: String) {
        SpeechService.shared.speak(
            text: "Starting research on \(topic) right away, \(user).",
            rate: SettingsStore.shared.voiceRate,
            pitch: SettingsStore.shared.voicePitch
        )
        statusMessage = "Researching: '\(topic)'"
        AppState.shared.manualTopicInput = topic
        AppState.shared.startManualResearch()
    }
    
    public func extractExplicitResearchTopic(from text: String) -> String {
        var clean = text
        let prefixesToRemove = [
            "hey jarvis, please research on", "hey jarvis please research on",
            "hey jarvis, research on", "hey jarvis research on",
            "hey jarvis, research", "hey jarvis research",
            "jarvis, please research on", "jarvis please research on",
            "jarvis, research on", "jarvis research on",
            "jarvis, research", "jarvis research",
            "please research on", "please research", "research on", "research",
            "search for", "search", "look up", "find out about", "find me information about",
            "can you research on", "can you research", "tell me about"
        ]
        
        var matched = false
        for prefix in prefixesToRemove {
            if let range = clean.range(of: prefix, options: [.caseInsensitive, .anchored]) {
                clean.removeSubrange(range)
                matched = true
                break
            } else if let range = clean.range(of: prefix, options: .caseInsensitive) {
                if clean.distance(from: clean.startIndex, to: range.lowerBound) < 15 {
                    clean.removeSubrange(clean.startIndex..<range.upperBound)
                    matched = true
                    break
                }
            }
        }
        
        guard matched else { return "" }
        return cleanTopic(clean)
    }
    
    private func cleanTopic(_ text: String) -> String {
        var clean = text
        let noiseWords = ["hey jarvis", "jarvis", "please", "assistant", "hey"]
        for word in noiseWords {
            if let range = clean.range(of: word, options: [.caseInsensitive, .anchored]) {
                clean.removeSubrange(range)
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
