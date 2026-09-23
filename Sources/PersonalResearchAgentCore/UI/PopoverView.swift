import SwiftUI
import AppKit

public struct PopoverView: View {
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var speechService = SpeechService.shared
    @ObservedObject private var voiceInput = VoiceInputService.shared
    
    public init() {}
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // MARK: - Header
            HStack(spacing: 8) {
                Image(systemName: "sparkles.rectangle.stack.fill")
                    .font(.title3)
                    .foregroundStyle(.linearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                
                VStack(alignment: .leading, spacing: 1) {
                    Text("Personal Research Agent")
                        .font(.headline)
                        .fontWeight(.semibold)
                    Text("Jarvis Voice AI • Autonomous Intelligence")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            
            Divider()
            
            // MARK: - Status Card
            VStack(alignment: .leading, spacing: 6) {
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
                    Text("Scheduled Topic:")
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
            
            // MARK: - Integrated Voiceover Control Card
            VStack(alignment: .leading, spacing: 6) {
                if speechService.isSpeaking {
                    // Jarvis is currently speaking
                    HStack(spacing: 8) {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.subheadline)
                            .foregroundStyle(.blue)
                        
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Jarvis Speaking...")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.blue)
                            Text("Say 'Stop' to interrupt")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        Button {
                            speechService.stopSpeaking()
                        } label: {
                            Image(systemName: "stop.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                        .help("Stop Voice Output")
                    }
                } else if voiceInput.isListening {
                    // Jarvis is actively listening to user voice
                    HStack(spacing: 8) {
                        Image(systemName: "waveform")
                            .font(.subheadline)
                            .foregroundStyle(.red)
                        
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Voiceover: Listening...")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.red)
                            
                            Text(voiceInput.liveTranscript.isEmpty ? "Say: 'Hey Jarvis...' or 'Research Quantum AI'" : "\"\(voiceInput.liveTranscript)\"")
                                .font(.caption2)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                        }
                        
                        Spacer()
                        
                        Button {
                            voiceInput.stopListening()
                        } label: {
                            Image(systemName: "mic.slash.fill")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Mute Voiceover")
                    }
                } else {
                    // Voiceover is idle / muted
                    HStack(spacing: 8) {
                        Image(systemName: "mic.fill")
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                        
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Voiceover Control")
                                .font(.caption)
                                .fontWeight(.semibold)
                            Text("Click to speak or listen")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        Button("Start") {
                            voiceInput.startListening()
                        }
                        .controlSize(.small)
                    }
                }
            }
            .padding(9)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(voiceInput.isListening ? Color.red.opacity(0.08) : (speechService.isSpeaking ? Color.blue.opacity(0.08) : Color(nsColor: .windowBackgroundColor)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(voiceInput.isListening ? Color.red.opacity(0.25) : (speechService.isSpeaking ? Color.blue.opacity(0.25) : Color(nsColor: .separatorColor)), lineWidth: 0.5)
            )
            
            // MARK: - Direct Topic Input Field
            HStack(spacing: 6) {
                TextField("Research a specific topic...", text: $appState.manualTopicInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .onSubmit {
                        appState.startManualResearch()
                    }
                    .disabled(appState.isResearching)
                
                Button {
                    appState.startManualResearch()
                } label: {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.body)
                        .foregroundStyle(appState.isResearching ? Color.secondary : Color.blue)
                }
                .buttonStyle(.plain)
                .disabled(appState.isResearching)
                .help("Start Research Now")
            }
            
            Divider()
            
            // MARK: - Minimal Footer Bar
            HStack {
                Button {
                    appState.openReportsFolder()
                } label: {
                    Label("Reports", systemImage: "folder")
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
                .help("Open ~/Documents/Personal Research Agent")
                
                Spacer()
                
                Button {
                    appState.openSettingsWindow()
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
                
                Text("•")
                    .foregroundStyle(.tertiary)
                    .font(.caption)
                
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
}
