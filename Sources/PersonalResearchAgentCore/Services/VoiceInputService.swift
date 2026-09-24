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
    case thinking
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
    private var activeLLMTask: Task<Void, Never>?
    private var isProcessingCommand: Bool = false
    
    // Short-term conversational history for natural back-and-forth dialogue
    private var chatHistory: [ChatMessage] = []
    
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
            // Wait for 1.3 seconds of natural silence after speech
            try? await Task.sleep(nanoseconds: 1_300_000_000)
            guard !Task.isCancelled, !SpeechService.shared.isSpeaking else { return }
            
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            
            self.handleVoiceCommand(trimmed)
        }
    }
    
    // MARK: - Command Parser & Smart Conversational Handler
    public func handleVoiceCommand(_ rawCommand: String) {
        guard !isProcessingCommand else { return }
        let command = rawCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard command.count >= 2 else { return }
        
        let lower = command.lowercased()
        let user = SettingsStore.shared.userName
        let assistant = SettingsStore.shared.assistantName
        
        // 0. Acoustic Echo Filter: Discard if recognizer simply picked up Jarvis's own last utterance
        let lastSpoken = SpeechService.shared.lastSpokenText
        if !lastSpoken.isEmpty && (lower == lastSpoken || (lastSpoken.count > 15 && lower.contains(lastSpoken.prefix(20)))) {
            logger.info("Discarding acoustic echo from assistant's own voice: '\(command)'")
            liveTranscript = ""
            return
        }
        
        logger.info("Processing voice command: '\(command)' (state: \(String(describing: self.conversationState)))")
        isProcessingCommand = true
        defer { isProcessingCommand = false }
        
        // 1. Stop / Quiet / Cancel Command
        if lower.contains("stop") || lower.contains("quiet") || lower.contains("shut up") || lower.contains("pause") || lower == "cancel" {
            activeLLMTask?.cancel()
            activeLLMTask = nil
            SpeechService.shared.stopSpeaking()
            if AppState.shared.isResearching {
                AppState.shared.cancelResearch()
                SpeechService.shared.speak(
                    text: "Cancelled research run, \(user).",
                    rate: SettingsStore.shared.voiceRate,
                    pitch: SettingsStore.shared.voicePitch
                )
            }
            conversationState = .idle
            statusMessage = "Voice output stopped."
            liveTranscript = ""
            return
        }
        
        // 2. In-Progress Research Inquiries & Busy Responses
        if AppState.shared.isResearching {
            let runningTopic = AppState.shared.activeResearchTopic ?? SettingsStore.shared.activeTopic
            
            if lower.contains("what's up") || lower.contains("how are you") || lower.contains("status") || lower.contains("done") || lower.contains("ready") || lower.contains("update") || lower == "hey \(assistant.lowercased())" || lower == assistant.lowercased() || lower == "hello" || lower.contains("how is it going") {
                SpeechService.shared.speak(
                    text: "I am currently researching \(runningTopic), \(user). Current step: \(AppState.shared.status.displayText). I will brief you as soon as the report is ready.",
                    rate: SettingsStore.shared.voiceRate,
                    pitch: SettingsStore.shared.voicePitch
                )
                statusMessage = "Researching: \(runningTopic)"
                liveTranscript = ""
                return
            }
            
            let explicitTopic = extractExplicitResearchTopic(from: command)
            if !explicitTopic.isEmpty {
                SpeechService.shared.speak(
                    text: "I am currently researching \(runningTopic), \(user). Say 'Stop' if you would like me to cancel this and start \(explicitTopic) instead.",
                    rate: SettingsStore.shared.voiceRate,
                    pitch: SettingsStore.shared.voicePitch
                )
                statusMessage = "Busy researching: \(runningTopic)"
                liveTranscript = ""
                return
            }
        }
        
        // 3. Open Reports Folder
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
        
        // 4. Read Latest Research Briefing
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
        
        // 5. Explicit Autonomous Multi-Step Research Command ("Jarvis research X", "Search for X and create report")
        let explicitTopic = extractExplicitResearchTopic(from: command)
        if !explicitTopic.isEmpty {
            conversationState = .idle
            triggerResearch(for: explicitTopic, user: user)
            liveTranscript = ""
            return
        }
        
        // 6. If we were awaiting a research topic after a specific prompt, treat this input as the topic
        if conversationState == .awaitingTopic {
            let topic = cleanTopic(command)
            if !topic.isEmpty && topic.count > 2 {
                conversationState = .idle
                triggerResearch(for: topic, user: user)
                liveTranscript = ""
                return
            }
        }
        
        // 7. Conversational AI Intelligence (LLM Fast-Path for any question, chat, or talk)
        respondConversationallyWithLLM(query: command, user: user, assistant: assistant)
    }
    
    // MARK: - Conversational AI Fast-Path
    private func respondConversationallyWithLLM(query: String, user: String, assistant: String) {
        conversationState = .thinking
        statusMessage = "\(assistant) is thinking..."
        liveTranscript = ""
        
        // Check if API key is present
        guard KeychainService.shared.hasKey(.openRouter) else {
            conversationState = .idle
            SpeechService.shared.speak(
                text: "Hello \(user), I heard you say: \(query). To enable conversational AI intelligence and deep research, please set your OpenRouter API key in Settings.",
                rate: SettingsStore.shared.voiceRate,
                pitch: SettingsStore.shared.voicePitch
            )
            statusMessage = "API Key not configured."
            return
        }
        
        activeLLMTask?.cancel()
        activeLLMTask = Task {
            let systemPrompt = """
            You are \(assistant), an elite, intelligent, and articulate personal AI voice assistant created for \(user).
            You speak in a natural, confident, calm, and concise tone.
            Respond directly to the user's question or greeting in 1 to 3 natural conversational sentences suitable for voice synthesis.
            Do NOT use markdown headers, asterisks, bullet points, emojis, code blocks, or URLs since your output is spoken directly aloud.
            If the user asks you to do a full deep research report on a topic, suggest saying: "Research [topic]".
            """
            
            // Append user query to history
            var messages = self.chatHistory
            messages.append(ChatMessage.user(query))
            
            do {
                let options = GenerationOptions(temperature: 0.7, maxTokens: 160, timeoutSeconds: 20)
                let result = try await OpenRouterProvider.shared.generate(
                    system: systemPrompt,
                    messages: messages,
                    options: options
                )
                
                guard !Task.isCancelled else { return }
                
                let reply = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !reply.isEmpty else { return }
                
                // Update short-term history (keep last 10 messages)
                self.chatHistory.append(ChatMessage.user(query))
                self.chatHistory.append(ChatMessage.assistant(reply))
                if self.chatHistory.count > 10 {
                    self.chatHistory.removeFirst(self.chatHistory.count - 10)
                }
                
                self.conversationState = .idle
                self.statusMessage = "\(assistant): \(reply.prefix(40))..."
                
                SpeechService.shared.speak(
                    text: reply,
                    rate: SettingsStore.shared.voiceRate,
                    pitch: SettingsStore.shared.voicePitch
                )
            } catch {
                guard !Task.isCancelled else { return }
                self.conversationState = .idle
                self.logger.error("Conversational LLM failed: \(error.localizedDescription)")
                
                // Natural fallback
                SpeechService.shared.speak(
                    text: "I heard your request, \(user), but encountered a temporary connection issue. Please try again in a moment.",
                    rate: SettingsStore.shared.voiceRate,
                    pitch: SettingsStore.shared.voicePitch
                )
                self.statusMessage = "Connection error: \(error.localizedDescription)"
            }
        }
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
        var clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        let prefixesToRemove = [
            "search for and make a report on", "create a research report on",
            "do a deep research on", "do a deep research about",
            "deep research on", "deep research about",
            "hey jarvis, please research on", "hey jarvis please research on",
            "hey jarvis, research on", "hey jarvis research on",
            "hey jarvis, research", "hey jarvis research",
            "jarvis, please research on", "jarvis please research on",
            "jarvis, research on", "jarvis research on",
            "jarvis, research", "jarvis research",
            "jarvis, search for", "jarvis search for",
            "jarvis, search on", "jarvis search on",
            "jarvis, search about", "jarvis search about",
            "jarvis, find out about", "jarvis find out about",
            "jarvis, look up", "jarvis look up",
            "please research on", "please research",
            "research on", "research about", "research",
            "search for", "search about", "search on",
            "find out about", "find out on",
            "look up"
        ]
        
        // Remove leading assistant address if present
        for address in ["hey jarvis,", "hey jarvis", "jarvis,", "jarvis", "hey,"] {
            if clean.lowercased().hasPrefix(address) {
                clean.removeFirst(address.count)
                clean = clean.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",:;-")))
                break
            }
        }
        
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
        let noiseWords = ["hey jarvis", "jarvis", "please", "assistant", "hey", "about", "for", "on"]
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
