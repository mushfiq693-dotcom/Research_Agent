import SwiftUI
import AppKit

public struct SettingsView: View {
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var launchAtLogin = LaunchAtLoginService.shared
    
    @State private var openRouterKeyInput: String = ""
    @State private var braveKeyInput: String = ""
    @State private var isShowingOpenRouterKey: Bool = false
    @State private var isShowingBraveKey: Bool = false
    @State private var openRouterStatusMessage: String?
    @State private var braveStatusMessage: String?
    @State private var freeSearchStatusMessage: String?
    @State private var isTestingOpenRouter: Bool = false
    @State private var isTestingBrave: Bool = false
    @State private var isTestingFreeSearch: Bool = false
    @State private var selectedTab: Int = 0
    @State private var isRefreshingModels: Bool = false
    @State private var modelCatalogMessage: String?
    @State private var newFallbackModelInput: String = ""
    
    public init() {}
    
    public var body: some View {
        TabView(selection: $selectedTab) {
            generalTab
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
                .tag(0)
            
            aiAndSearchTab
                .tabItem {
                    Label("AI & Search", systemImage: "cpu")
                }
                .tag(1)
            
            voiceAndAudioTab
                .tabItem {
                    Label("Voice & Audio", systemImage: "waveform")
                }
                .tag(2)
            
            privacyTab
                .tabItem {
                    Label("Privacy & Notice", systemImage: "hand.raised.fill")
                }
                .tag(3)
        }
        .padding(20)
        .frame(width: 540, height: 500)
        .onAppear {
            loadKeyPlaceholders()
            launchAtLogin.refreshStatus()
        }
    }
    
    // MARK: - General Tab
    private var generalTab: some View {
        Form {
            Section("Research Topic") {
                Picker("Preset Topic:", selection: $settings.topicPreset) {
                    ForEach(TopicPreset.allCases) { preset in
                        Text(preset.rawValue).tag(preset)
                    }
                }
                
                if settings.topicPreset == .custom {
                    TextField("Custom Research Topic:", text: $settings.customTopic)
                        .textFieldStyle(.roundedBorder)
                }
            }
            
            Section("Schedule & Frequency") {
                HStack {
                    Text("Time:")
                    Picker("", selection: $settings.scheduleHour) {
                        ForEach(0..<24) { h in
                            Text(String(format: "%02d", h)).tag(h)
                        }
                    }
                    .frame(width: 65)
                    
                    Text(":")
                    
                    Picker("", selection: $settings.scheduleMinute) {
                        ForEach([0, 15, 30, 45], id: \.self) { m in
                            Text(String(format: "%02d", m)).tag(m)
                        }
                    }
                    .frame(width: 65)
                }
                
                Picker("Frequency:", selection: $settings.scheduleFrequency) {
                    ForEach(ScheduleFrequency.allCases) { freq in
                        Text(freq.rawValue).tag(freq)
                    }
                }
                
                if settings.scheduleFrequency == .weekly {
                    Picker("Day of Week:", selection: $settings.scheduleWeekday) {
                        ForEach(Weekday.allCases) { w in
                            Text(w.name).tag(w)
                        }
                    }
                }
            }
            
            Section("Research Depth") {
                Picker("Depth:", selection: $settings.researchDepth) {
                    ForEach(ResearchDepth.allCases) { depth in
                        Text(depth.rawValue).tag(depth)
                    }
                }
                .pickerStyle(.segmented)
                
                Text(settings.researchDepth.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Section("System & Storage") {
                Toggle("Launch at Login", isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.setEnabled($0) }
                ))
                
                if launchAtLogin.status == .requiresApproval {
                    HStack {
                        Text("Approval required in System Settings")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Button("Open Settings") {
                            launchAtLogin.openSystemSettings()
                        }
                        .controlSize(.small)
                    }
                }
                
                Toggle("Run Missed Research on Wake/Launch", isOn: $settings.runMissedResearch)
                Toggle("Enable Native macOS Notifications", isOn: $settings.notificationsEnabled)
                
                HStack {
                    TextField("Reports Directory:", text: $settings.reportsDirectoryPath)
                        .textFieldStyle(.roundedBorder)
                    Button("Choose...") {
                        selectReportsDirectory()
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
    
    // MARK: - AI & Search Tab
    private var aiAndSearchTab: some View {
        Form {
            Section("OpenRouter AI Provider") {
                HStack {
                    if isShowingOpenRouterKey {
                        TextField("sk-or-v1-...", text: $openRouterKeyInput)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        SecureField("••••••••••••••••••••••••", text: $openRouterKeyInput)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    Button {
                        isShowingOpenRouterKey.toggle()
                    } label: {
                        Image(systemName: isShowingOpenRouterKey ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.plain)
                    
                    Button("Save") {
                        saveOpenRouterKey()
                    }
                    .controlSize(.small)
                    
                    Button("Test") {
                        testOpenRouterKey()
                    }
                    .controlSize(.small)
                    .disabled(isTestingOpenRouter)
                }
                
                if let msg = openRouterStatusMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(msg.contains("Success") ? .green : .red)
                }
                
                TextField("Fast Model Slug:", text: $settings.fastModel)
                    .textFieldStyle(.roundedBorder)
                TextField("Strong Model Slug:", text: $settings.strongModel)
                    .textFieldStyle(.roundedBorder)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Fallback Models:")
                        .font(.subheadline)
                    ForEach(settings.fallbackModels, id: \.self) { model in
                        HStack {
                            Text(model)
                                .font(.caption)
                                .monospaced()
                            Spacer()
                            Button {
                                settings.fallbackModels.removeAll { $0 == model }
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    
                    HStack {
                        TextField("Add model slug (e.g. qwen/qwen3.8-27b:free)", text: $newFallbackModelInput)
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)
                        Button("Add") {
                            let trimmed = newFallbackModelInput.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !trimmed.isEmpty && !settings.fallbackModels.contains(trimmed) {
                                settings.fallbackModels.append(trimmed)
                                newFallbackModelInput = ""
                            }
                        }
                        .controlSize(.small)
                    }
                }
            }
            
            Section("Web Search Engine") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                        Text("Built-in Free Search (DuckDuckGo)")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                        Button("Test Free Search") {
                            testFreeSearch()
                        }
                        .controlSize(.small)
                        .disabled(isTestingFreeSearch)
                    }
                    Text("Zero-configuration: No API key or credit card needed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    if let msg = freeSearchStatusMessage {
                        Text(msg)
                            .font(.caption)
                            .foregroundStyle(msg.contains("Success") ? .green : .red)
                    }
                }
                .padding(.vertical, 2)
                
                Divider()
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Optional: Brave Search API Key")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    HStack {
                        if isShowingBraveKey {
                            TextField("BSA...", text: $braveKeyInput)
                                .textFieldStyle(.roundedBorder)
                        } else {
                            SecureField("••••••••••••••••••••••••", text: $braveKeyInput)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        Button {
                            isShowingBraveKey.toggle()
                        } label: {
                            Image(systemName: isShowingBraveKey ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.plain)
                        
                        Button("Save") {
                            saveBraveKey()
                        }
                        .controlSize(.small)
                        
                        Button("Test") {
                            testBraveKey()
                        }
                        .controlSize(.small)
                        .disabled(isTestingBrave)
                    }
                    
                    if let msg = braveStatusMessage {
                        Text(msg)
                            .font(.caption)
                            .foregroundStyle(msg.contains("Success") ? .green : .red)
                    }
                }
            }
            
            Section("Agent Timing Limits") {
                Stepper("Retry Delay: \(settings.retryDelayMinutes) min", value: $settings.retryDelayMinutes, in: 1...60)
                Stepper("Delay Between Model Calls: \(String(format: "%.1f", settings.delayBetweenCallsSeconds)) s", value: $settings.delayBetweenCallsSeconds, in: 0.5...10.0, step: 0.5)
            }
        }
        .formStyle(.grouped)
    }
    
    // MARK: - Voice & Audio Tab
    private var voiceAndAudioTab: some View {
        Form {
            Section("Assistant & User Identity") {
                TextField("Your Name:", text: $settings.userName)
                    .textFieldStyle(.roundedBorder)
                TextField("Assistant Wake/Display Name:", text: $settings.assistantName)
                    .textFieldStyle(.roundedBorder)
            }
            
            Section("Audio Briefing (Voice Read-Aloud)") {
                Toggle("Auto Read-Aloud on Research Completion", isOn: $settings.autoReadAloudOnCompletion)
                
                Picker("Voice:", selection: $settings.preferredVoiceIdentifier) {
                    Text("Default Natural Voice").tag("")
                    ForEach(SpeechService.availableVoices(), id: \.identifier) { voice in
                        Text("\(voice.name) (\(voice.language))").tag(voice.identifier)
                    }
                }
                
                HStack {
                    Text("Speech Speed:")
                    Slider(value: $settings.voiceRate, in: 0.3...0.7, step: 0.05)
                    Text(String(format: "%.2fx", settings.voiceRate / 0.5))
                        .monospacedDigit()
                        .frame(width: 45)
                }
                
                Button {
                    SpeechService.shared.speak(
                        text: "Hello \(settings.userName), I am \(settings.assistantName). I am your personal AI research assistant.",
                        voiceIdentifier: settings.preferredVoiceIdentifier.isEmpty ? nil : settings.preferredVoiceIdentifier,
                        rate: settings.voiceRate
                    )
                } label: {
                    Label("Test Voice Greeting", systemImage: "speaker.wave.2.fill")
                }
                .controlSize(.small)
            }
        }
        .formStyle(.grouped)
    }
    
    // MARK: - Privacy Tab
    private var privacyTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Free-Tier Cloud Privacy Notice", systemImage: "lock.shield.fill")
                .font(.headline)
                .foregroundStyle(.blue)
            
            Text("This application uses cloud AI models through the OpenRouter API. Free-tier models are provided by various third-party inference hosts that may retain prompts and completions for logging or training purposes.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Divider()
            
            VStack(alignment: .leading, spacing: 6) {
                Text("Built-in Privacy Safeguards:")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Text("• Zero personal files, documents, or secrets are ever sent in prompts.")
                    .font(.caption)
                Text("• Prompts contain ONLY the research topic and sanitized public web page extracts.")
                    .font(.caption)
                Text("• API keys live exclusively in your local macOS Keychain.")
                    .font(.caption)
                Text("• App Sandbox is disabled solely to save Markdown reports directly in ~/Documents.")
                    .font(.caption)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
            
            Spacer()
            
            HStack {
                Spacer()
                Button("Acknowledge Notice") {
                    settings.privacyNoticeAcknowledged = true
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(14)
    }
    
    // MARK: - Helper Methods
    private func loadKeyPlaceholders() {
        if let key = KeychainService.shared.getKey(.openRouter), !key.isEmpty {
            openRouterKeyInput = key
        }
        if let key = KeychainService.shared.getKey(.braveSearch), !key.isEmpty {
            braveKeyInput = key
        }
    }
    
    private func saveOpenRouterKey() {
        do {
            try KeychainService.shared.saveKey(.openRouter, value: openRouterKeyInput)
            openRouterStatusMessage = "OpenRouter API Key saved to Keychain."
        } catch {
            openRouterStatusMessage = "Failed to save: \(error.localizedDescription)"
        }
    }
    
    private func saveBraveKey() {
        do {
            try KeychainService.shared.saveKey(.braveSearch, value: braveKeyInput)
            braveStatusMessage = "Brave Search API Key saved to Keychain."
        } catch {
            braveStatusMessage = "Failed to save: \(error.localizedDescription)"
        }
    }
    
    private func testOpenRouterKey() {
        isTestingOpenRouter = true
        openRouterStatusMessage = "Testing connection..."
        
        let key = openRouterKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            openRouterStatusMessage = "API Key is empty."
            isTestingOpenRouter = false
            return
        }
        
        Task {
            guard let url = URL(string: "https://openrouter.ai/api/v1/auth/key") else { return }
            var req = URLRequest(url: url)
            req.addValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            
            do {
                let (data, response) = try await URLSession.shared.data(for: req)
                if let http = response as? HTTPURLResponse {
                    if http.statusCode == 200 {
                        openRouterStatusMessage = "Success: Valid OpenRouter Key!"
                    } else {
                        let text = String(data: data, encoding: .utf8) ?? ""
                        openRouterStatusMessage = "Error (\(http.statusCode)): \(text.prefix(60))"
                    }
                }
            } catch {
                openRouterStatusMessage = "Connection failed: \(error.localizedDescription)"
            }
            isTestingOpenRouter = false
        }
    }
    
    private func testBraveKey() {
        isTestingBrave = true
        braveStatusMessage = "Testing connection..."
        
        let key = braveKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            braveStatusMessage = "API Key is empty."
            isTestingBrave = false
            return
        }
        
        Task {
            guard let url = URL(string: "https://api.search.brave.com/res/v1/web/search?q=test&count=1") else { return }
            var req = URLRequest(url: url)
            req.addValue(key, forHTTPHeaderField: "X-Subscription-Token")
            
            do {
                let (data, response) = try await URLSession.shared.data(for: req)
                if let http = response as? HTTPURLResponse {
                    if http.statusCode == 200 {
                        braveStatusMessage = "Success: Valid Brave Search Key!"
                    } else {
                        let text = String(data: data, encoding: .utf8) ?? ""
                        braveStatusMessage = "Error (\(http.statusCode)): \(text.prefix(60))"
                    }
                }
            } catch {
                braveStatusMessage = "Connection failed: \(error.localizedDescription)"
            }
            isTestingBrave = false
        }
    }
    
    private func testFreeSearch() {
        isTestingFreeSearch = true
        freeSearchStatusMessage = "Testing DuckDuckGo free search..."
        
        Task {
            do {
                let results = try await DuckDuckGoSearchProvider.shared.searchWeb(query: "Apple Silicon Mac", count: 2)
                if !results.isEmpty {
                    freeSearchStatusMessage = "Success: Found \(results.count) live results from Free Search!"
                } else {
                    freeSearchStatusMessage = "Warning: 0 results returned."
                }
            } catch {
                freeSearchStatusMessage = "Search error: \(error.localizedDescription)"
            }
            isTestingFreeSearch = false
        }
    }
    
    private func selectReportsDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Select"
        
        if panel.runModal() == .OK, let url = panel.url {
            settings.reportsDirectoryPath = url.path
        }
    }
}
