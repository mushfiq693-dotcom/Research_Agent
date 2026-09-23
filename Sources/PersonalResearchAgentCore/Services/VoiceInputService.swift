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
    @Published public private(set) var statusMessage: String = "Ready for voice command"
    @Published public private(set) var hasPermissions: Bool = false
    
    private var silenceTimer: Task<Void, Never>?
    
    private override init() {
        super.init()
        speechRecognizer?.delegate = self
    }
    
    // MARK: - Permission Request
    public func requestPermissions() async -> Bool {
        let speechAuth = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        
        let micAuth: Bool
        if #available(macOS 14.0, *) {
            micAuth = await AVAudioApplication.requestRecordPermission()
        } else {
            micAuth = true
        }
        
        let granted = speechAuth && micAuth
        self.hasPermissions = granted
        logger.info("Voice permissions status: Speech=\(speechAuth), Mic=\(micAuth)")
        return granted
    }
    
    // MARK: - Start Listening
    public func startListening() {
        guard !isListening else { return }
        
        // Stop any active speech output when user starts speaking
        if SpeechService.shared.isSpeaking {
            SpeechService.shared.stopSpeaking()
        }
        
        Task {
            let authorized = await requestPermissions()
            guard authorized else {
                self.statusMessage = "Microphone or Speech permission denied."
                logger.warning("Cannot start listening: Permissions denied.")
                return
            }
            
            do {
                try self.beginAudioSession()
                self.isListening = true
                self.liveTranscript = ""
                self.statusMessage = "Listening... (e.g. 'Hey Jarvis, research Swift 6')"
                self.logger.info("Voice recognition engine started.")
            } catch {
                self.statusMessage = "Failed to start audio engine: \(error.localizedDescription)"
                self.logger.error("Audio engine failed: \(error.localizedDescription)")
            }
        }
    }
    
    public func stopListening() {
        guard isListening else { return }
        
        silenceTimer?.cancel()
        silenceTimer = nil
        
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        
        recognitionTask?.cancel()
        recognitionTask = nil
        
        isListening = false
        statusMessage = "Voice listening stopped."
        logger.info("Voice recognition stopped.")
    }
    
    public func toggleListening() {
        if isListening {
            stopListening()
        } else {
            startListening()
        }
    }
    
    // MARK: - Audio Session & Recognition Loop
    private func beginAudioSession() throws {
        recognitionTask?.cancel()
        recognitionTask = nil
        
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.recognitionRequest = request
        
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }
        
        audioEngine.prepare()
        try audioEngine.start()
        
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            throw NSError(domain: "VoiceInputService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Speech recognizer is unavailable."])
        }
        
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                
                if let result = result {
                    let transcribedString = result.bestTranscription.formattedString
                    self.liveTranscript = transcribedString
                    self.resetSilenceTimer(for: transcribedString)
                }
                
                if let error = error {
                    self.logger.warning("Recognition error: \(error.localizedDescription)")
                    self.stopListening()
                }
            }
        }
    }
    
    private func resetSilenceTimer(for text: String) {
        silenceTimer?.cancel()
        silenceTimer = Task {
            // Wait for 1.5 seconds of silence after user finishes speaking
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            
            self.handleVoiceCommand(text)
            self.stopListening()
        }
    }
    
    // MARK: - Command Processing
    public func handleVoiceCommand(_ rawCommand: String) {
        let command = rawCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return }
        
        logger.info("Processing voice command: '\(command)'")
        let lower = command.lowercased()
        let assistant = SettingsStore.shared.assistantName.lowercased()
        let user = SettingsStore.shared.userName
        
        // 1. Stop Command
        if lower.contains("stop") || lower.contains("quiet") || lower.contains("pause") {
            SpeechService.shared.stopSpeaking()
            SpeechService.shared.speak(text: "Stopping now, \(user).")
            statusMessage = "Command executed: Stopped playback."
            return
        }
        
        // 2. Casual Greeting / Status
        if lower.contains("what's up") || lower.contains("how are you") || lower == "hey \(assistant)" || lower == assistant || lower == "hello" || lower == "hello \(assistant)" {
            SpeechService.shared.speak(
                text: "Hello \(user)! I am online and ready. What topic would you like me to research today?",
                rate: SettingsStore.shared.voiceRate,
                pitch: SettingsStore.shared.voicePitch
            )
            statusMessage = "Jarvis is ready for research topic."
            return
        }
        
        // 3. Open Reports Folder
        if lower.contains("open report") || lower.contains("open folder") || lower.contains("show report") {
            AppState.shared.openReportsFolder()
            SpeechService.shared.speak(text: "Opening your research reports folder, \(user).")
            statusMessage = "Command executed: Opened reports folder."
            return
        }
        
        // 4. Read Aloud Latest Report
        if lower.contains("read report") || lower.contains("read briefing") || lower.contains("listen to report") {
            if let reportPath = AppState.shared.lastReportPath, let md = try? String(contentsOfFile: reportPath, encoding: .utf8) {
                SpeechService.shared.speakReportBriefing(
                    markdown: md,
                    topic: SettingsStore.shared.activeTopic,
                    userName: user,
                    assistantName: SettingsStore.shared.assistantName
                )
                statusMessage = "Command executed: Reading briefing."
            } else {
                SpeechService.shared.speak(text: "No recent research report found to read, \(user).")
            }
            return
        }
        
        // 5. Research Topic Trigger
        let extractedTopic = extractResearchTopic(from: command)
        if !extractedTopic.isEmpty {
            SpeechService.shared.speak(
                text: "Starting research on \(extractedTopic) right away, \(user).",
                rate: SettingsStore.shared.voiceRate,
                pitch: SettingsStore.shared.voicePitch
            )
            statusMessage = "Researching: '\(extractedTopic)'"
            AppState.shared.manualTopicInput = extractedTopic
            AppState.shared.startManualResearch()
            return
        }
        
        // Fallback: Default to researching what the user said
        SpeechService.shared.speak(
            text: "Searching for \(command), \(user).",
            rate: SettingsStore.shared.voiceRate,
            pitch: SettingsStore.shared.voicePitch
        )
        statusMessage = "Researching: '\(command)'"
        AppState.shared.manualTopicInput = command
        AppState.shared.startManualResearch()
    }
    
    private func extractResearchTopic(from text: String) -> String {
        var clean = text
        let prefixesToRemove = [
            "hey jarvis", "jarvis", "hey assistant", "assistant",
            "please research on", "please research", "research on", "research",
            "search for", "search", "look up", "find out about", "find"
        ]
        
        for prefix in prefixesToRemove {
            if let range = clean.range(of: prefix, options: [.caseInsensitive, .anchored]) {
                clean.removeSubrange(range)
            } else if let range = clean.range(of: prefix, options: .caseInsensitive) {
                // If it starts around the beginning
                if clean.distance(from: clean.startIndex, to: range.lowerBound) < 15 {
                    clean.removeSubrange(clean.startIndex..<range.upperBound)
                }
            }
        }
        
        return clean.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ":,.-")))
    }
}
