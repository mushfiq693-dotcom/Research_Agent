import Foundation
import AVFoundation
import OSLog

@MainActor
public final class SpeechService: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    public static let shared = SpeechService()
    
    private let synthesizer = AVSpeechSynthesizer()
    private let logger = Logger(subsystem: "com.personalresearchagent.app", category: "SpeechService")
    
    @Published public private(set) var isSpeaking: Bool = false
    @Published public private(set) var lastSpokenText: String = ""
    
    private override init() {
        super.init()
        synthesizer.delegate = self
    }
    
    // MARK: - Speak Methods
    public func speak(text: String, voiceIdentifier: String? = nil, rate: Float = 0.48, pitch: Float = 0.80) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        lastSpokenText = trimmed.lowercased()
        
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        
        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.rate = min(max(rate, 0.2), 0.8)
        utterance.pitchMultiplier = min(max(pitch, 0.5), 1.5)
        utterance.volume = 1.0
        
        if let id = voiceIdentifier, !id.isEmpty, let voice = AVSpeechSynthesisVoice(identifier: id) {
            utterance.voice = voice
        } else if let deepMaleVoice = Self.findBestDefaultVoice() {
            utterance.voice = deepMaleVoice
        } else if let enVoice = AVSpeechSynthesisVoice(language: "en-US") {
            utterance.voice = enVoice
        }
        
        isSpeaking = true
        synthesizer.speak(utterance)
        logger.info("Speech started for \(trimmed.count) characters with rate \(rate), pitch \(pitch).")
    }
    
    public func speakReportBriefing(markdown: String, topic: String, userName: String = "Mushfiq", assistantName: String = "Jarvis") {
        let spokenText = Self.formatSpokenBriefing(
            markdown: markdown,
            topic: topic,
            userName: userName,
            assistantName: assistantName
        )
        let rate = SettingsStore.shared.voiceRate
        let pitch = SettingsStore.shared.voicePitch
        let voiceId = SettingsStore.shared.preferredVoiceIdentifier
        speak(text: spokenText, voiceIdentifier: voiceId.isEmpty ? nil : voiceId, rate: rate, pitch: pitch)
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
            VoiceInputService.shared.onSpeechCompleted()
        }
    }
    
    nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
            self.logger.info("Speech cancelled.")
            VoiceInputService.shared.onSpeechCompleted()
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
        let noveltyNames: Set<String> = [
            "bad news", "bahh", "bells", "boing", "bubbles", "cellos",
            "deranged", "good news", "hysterical", "jester", "organ",
            "superstar", "trinoids", "whisper", "wobble", "zarvox", "albert", "fred", "junior", "ralph"
        ]
        
        let allVoices = AVSpeechSynthesisVoice.speechVoices().filter { voice in
            if voice.voiceTraits.contains(.isPersonalVoice) {
                return true
            }
            guard voice.language.hasPrefix("en") else { return false }
            let lowerName = voice.name.lowercased()
            return !noveltyNames.contains(lowerName)
        }
        
        return allVoices.sorted { v1, v2 in
            let isPersonal1 = v1.voiceTraits.contains(.isPersonalVoice)
            let isPersonal2 = v2.voiceTraits.contains(.isPersonalVoice)
            if isPersonal1 != isPersonal2 {
                return isPersonal1 && !isPersonal2
            }
            if v1.quality.rawValue != v2.quality.rawValue {
                return v1.quality.rawValue > v2.quality.rawValue
            }
            return v1.name < v2.name
        }
    }
    
    nonisolated public static func findBestDefaultVoice() -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        // Priority 1: Enhanced/Premium British/US Male Voices (Daniel, Oliver, Evan, Nathan, Alex)
        let prioritizedNames = ["Daniel", "Oliver", "Evan", "Nathan", "Alex", "Eddy", "Reed", "Rocko", "Samantha"]
        
        for name in prioritizedNames {
            if let enhanced = voices.first(where: { $0.name.contains(name) && $0.quality == .enhanced }) {
                return enhanced
            }
            if let found = voices.first(where: { $0.name.contains(name) }) {
                return found
            }
        }
        return AVSpeechSynthesisVoice(language: "en-US")
    }
}
