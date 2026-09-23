import Foundation
import AVFoundation
import OSLog

@MainActor
public final class SpeechService: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    public static let shared = SpeechService()
    
    private let synthesizer = AVSpeechSynthesizer()
    private let logger = Logger(subsystem: "com.personalresearchagent.app", category: "SpeechService")
    
    @Published public private(set) var isSpeaking: Bool = false
    
    private override init() {
        super.init()
        synthesizer.delegate = self
    }
    
    // MARK: - Speak Methods
    public func speak(text: String, voiceIdentifier: String? = nil, rate: Float = 0.5) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        
        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.rate = min(max(rate, 0.2), 0.8)
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        
        if let id = voiceIdentifier, let voice = AVSpeechSynthesisVoice(identifier: id) {
            utterance.voice = voice
        } else if let enVoice = AVSpeechSynthesisVoice(language: "en-US") {
            utterance.voice = enVoice
        }
        
        isSpeaking = true
        synthesizer.speak(utterance)
        logger.info("Speech started for \(trimmed.count) characters.")
    }
    
    public func speakReportBriefing(markdown: String, topic: String, userName: String = "Mushfiq", assistantName: String = "Jarvis") {
        let spokenText = Self.formatSpokenBriefing(
            markdown: markdown,
            topic: topic,
            userName: userName,
            assistantName: assistantName
        )
        let rate = SettingsStore.shared.voiceRate
        let voiceId = SettingsStore.shared.preferredVoiceIdentifier
        speak(text: spokenText, voiceIdentifier: voiceId.isEmpty ? nil : voiceId, rate: rate)
    }
    
    public func stopSpeaking() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isSpeaking = false
        logger.info("Speech stopped.")
    }
    
    // MARK: - Speech Synthesis Delegate
    nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
            self.logger.info("Speech finished.")
        }
    }
    
    nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
            self.logger.info("Speech cancelled.")
        }
    }
    
    // MARK: - Markdown Cleaner & Spoken Briefing Formatter
    nonisolated public static func formatSpokenBriefing(
        markdown: String,
        topic: String,
        userName: String,
        assistantName: String
    ) -> String {
        let cleanText = cleanMarkdownForSpeech(markdown)
        let greeting = "Hello \(userName), this is \(assistantName). Here is your research briefing on \(topic)."
        
        if cleanText.isEmpty {
            return "\(greeting) The report has been saved to your documents folder."
        }
        
        return "\(greeting)\n\n\(cleanText)"
    }
    
    nonisolated public static func cleanMarkdownForSpeech(_ markdown: String) -> String {
        var text = markdown
        
        // Remove code blocks
        text = text.replacingOccurrences(of: "```[\\s\\S]*?```", with: "", options: .regularExpression)
        
        // Remove markdown headers (#, ##, ###)
        text = text.replacingOccurrences(of: "(?m)^#{1,6}\\s*", with: "", options: .regularExpression)
        
        // Remove markdown links [title](url) -> title
        text = text.replacingOccurrences(of: "\\[([^\\]]+)\\]\\([^\\)]+\\)", with: "$1", options: .regularExpression)
        
        // Remove bold/italic markers (*, _, ~~)
        text = text.replacingOccurrences(of: "[\\*_~`]", with: "", options: .regularExpression)
        
        // Replace bullet points with pause
        text = text.replacingOccurrences(of: "(?m)^[\\*\\-\\+]\\s+", with: "Point: ", options: .regularExpression)
        
        // Remove blockquotes >
        text = text.replacingOccurrences(of: "(?m)^>\\s*", with: "", options: .regularExpression)
        
        // Clean excessive whitespace
        text = text.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
        
        // Truncate to reasonable spoken length if extremely long (~1,500 chars / ~2 minutes)
        if text.count > 1500 {
            text = String(text.prefix(1500)) + "... For further details, please review your written report."
        }
        
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    nonisolated public static func availableVoices() -> [AVSpeechSynthesisVoice] {
        return AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("en") }
    }
}
