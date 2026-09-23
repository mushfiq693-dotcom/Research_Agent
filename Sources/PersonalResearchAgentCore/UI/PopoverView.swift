import SwiftUI
import AppKit

public struct PopoverView: View {
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var speechService = SpeechService.shared
    @ObservedObject private var voiceInput = VoiceInputService.shared
    
    public init() {}
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // MARK: - Header
            HStack(spacing: 8) {
                Image(systemName: "sparkles.rectangle.stack.fill")
                    .font(.title3)
                    .foregroundStyle(.linearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                
                VStack(alignment: .leading, spacing: 1) {
                    Text("Personal Research Agent")
                        .font(.headline)
                        .fontWeight(.semibold)
                    Text("Autonomous Web Intelligence")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.bottom, 2)
            
            Divider()
            
            // MARK: - Status Card
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    if case .researching = appState.status {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: appState.status.iconName)
                            .font(.subheadline)
                            .foregroundStyle(appState.status.statusColor)
                    }
                    
                    Text(appState.status.displayText)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                HStack(spacing: 6) {
                    Text("Topic:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(settings.activeTopic)
                        .font(.caption)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
            )
            
            // MARK: - Missing API Key Notice
            if !KeychainService.shared.hasKey(.openRouter) {
                HStack(spacing: 6) {
                    Image(systemName: "key.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Text("OpenRouter API Key not set.")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                    Spacer()
                    Button("Set Key") {
                        appState.openSettingsWindow()
                    }
                    .controlSize(.mini)
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.orange.opacity(0.12))
                )
            }
            
            // MARK: - Research Now Inline Section
            if appState.isShowingManualInput {
                VStack(spacing: 8) {
                    TextField("Research something specific...", text: $appState.manualTopicInput)
                        .textFieldStyle(.roundedBorder)
                        .font(.subheadline)
                        .onSubmit {
                            appState.startManualResearch()
                        }
                    
                    HStack {
                        Button("Cancel") {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                appState.isShowingManualInput = false
                                appState.manualTopicInput = ""
                            }
                        }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        
                        Spacer()
                        
                        Button {
                            appState.startManualResearch()
                        } label: {
                            Label("Start Research", systemImage: "arrow.right.circle.fill")
                                .font(.caption)
                                .fontWeight(.semibold)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .windowBackgroundColor))
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            
            // MARK: - Voice Command Live Card
            if voiceInput.isListening {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: "waveform.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.red)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(settings.assistantName) is Listening...")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.red)
                            Text(voiceInput.liveTranscript.isEmpty ? "Say: 'Hey \(settings.assistantName), research Swift 6'" : "\"\(voiceInput.liveTranscript)\"")
                                .font(.caption2)
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                        }
                        
                        Spacer()
                        
                        Button("Done") {
                            voiceInput.stopListening()
                        }
                        .controlSize(.mini)
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.red.opacity(0.08)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.red.opacity(0.3), lineWidth: 1))
            }
            
            // MARK: - Primary Action Buttons
            HStack(spacing: 8) {
                if voiceInput.isListening {
                    Button {
                        voiceInput.toggleListening()
                    } label: {
                        Label("Listening...", systemImage: "waveform")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .controlSize(.regular)
                } else {
                    Button {
                        voiceInput.toggleListening()
                    } label: {
                        Label("Talk to \(settings.assistantName)", systemImage: "mic.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .disabled(appState.isResearching)
                }
                
                if !appState.isShowingManualInput {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            appState.isShowingManualInput = true
                        }
                    } label: {
                        Label("Type", systemImage: "keyboard")
                            .frame(maxWidth: 80)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .disabled(appState.isResearching)
                }
                
                Button {
                    appState.openReportsFolder()
                } label: {
                    Image(systemName: "folder")
                        .frame(width: 24)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .help("Open Reports Directory")
            }
            
            // MARK: - Audio Briefing (Read Aloud) Control
            if let reportPath = appState.lastReportPath ?? findLatestReportPath(), FileManager.default.fileExists(atPath: reportPath) {
                Button {
                    if speechService.isSpeaking {
                        speechService.stopSpeaking()
                    } else {
                        if let md = try? String(contentsOfFile: reportPath, encoding: .utf8) {
                            speechService.speakReportBriefing(
                                markdown: md,
                                topic: settings.activeTopic,
                                userName: settings.userName,
                                assistantName: settings.assistantName
                            )
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: speechService.isSpeaking ? "stop.circle.fill" : "speaker.wave.2.fill")
                            .foregroundStyle(speechService.isSpeaking ? .red : .blue)
                        Text(speechService.isSpeaking ? "Stop Voice Briefing" : "🔊 Listen to Briefing")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 2)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
            
            Divider()
            
            // MARK: - Footer Controls
            HStack {
                Button {
                    appState.openSettingsWindow()
                } label: {
                    Label("Settings...", systemImage: "gearshape")
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
                
                Spacer()
                
                Button {
                    appState.quit()
                } label: {
                    Text("Quit")
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(width: 320)
    }
    
    private func findLatestReportPath() -> String? {
        let dirURL = settings.reportsDirectoryURL
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
