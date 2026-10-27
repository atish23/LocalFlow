import SwiftUI
import AppKit
import AVFoundation

public final class SettingsWindowManager: NSObject {
    public static let shared = SettingsWindowManager()
    private var windowController: NSWindowController?

    public func showSettings() {
        if let controller = windowController {
            controller.showWindow(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let contentView = SettingsRootView()
        let hostingController = NSHostingController(rootView: contentView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "LocalFlow Settings & Preferences"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 720, height: 560))
        window.center()
        window.isReleasedWhenClosed = false

        let controller = NSWindowController(window: window)
        self.windowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

public struct SettingsRootView: View {
    @State private var selectedTab = 0

    public init() {}

    public var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
                .tag(0)

            AudioInputSettingsView()
                .tabItem {
                    Label("Audio Input", systemImage: "mic.fill")
                }
                .tag(1)

            LLMSettingsView()
                .tabItem {
                    Label("AI Backend", systemImage: "cpu")
                }
                .tag(2)

            VocabularyView()
                .tabItem {
                    Label("Vocabulary", systemImage: "character.book.closed")
                }
                .tag(3)

            HistoryView()
                .tabItem {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
                .tag(4)
        }
        .frame(minWidth: 680, minHeight: 520)
        .padding()
    }
}

// MARK: - 1. General Settings View
public struct GeneralSettingsView: View {
    @State private var config = ConfigManager.shared.config
    @State private var testSoundPlayed = false
    @State private var testHapticTriggered = false

    public init() {}

    public var body: some View {
        Form {
            Section(header: Text("Dictation & Hotkey").font(.headline)) {
                Picker("Activation Mode", selection: $config.hotkey_mode) {
                    ForEach(DictationHotkeyMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .onChange(of: config.hotkey_mode) { _ in save() }

                Picker("Trigger Key", selection: $config.trigger_key) {
                    ForEach(HotkeyTriggerKey.allCases, id: \.self) { key in
                        Text(key.displayName).tag(key)
                    }
                }
                .onChange(of: config.trigger_key) { _ in save() }

                if config.hotkey_mode == .toggle {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Double-Tap Speed Window:")
                            Spacer()
                            Text("\(config.double_tap_threshold_ms) ms")
                                .foregroundColor(.secondary)
                        }
                        Slider(
                            value: Binding(
                                get: { Double(config.double_tap_threshold_ms) },
                                set: { config.double_tap_threshold_ms = Int($0); save() }
                            ),
                            in: 200...650,
                            step: 25
                        )
                    }
                    .padding(.top, 4)
                }

                Text(config.hotkey_mode == .toggle
                     ? "Instructions: Tap \(config.trigger_key.displayName) twice quickly to start dictating. Tap once while recording to stop and paste."
                     : "Instructions: Press and hold \(config.trigger_key.displayName) to speak. Release key to stop and paste directly into your active window.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 2)
            }

            Section(header: Text("Feedback & Interface").font(.headline)) {
                Toggle("Headless Mode (Zero visual UI, audio cues only)", isOn: $config.headless)
                    .onChange(of: config.headless) { _ in save() }

                HStack {
                    Toggle("Audio Sound Effects (Tink on start, Pop on stop)", isOn: $config.sound_effects)
                        .onChange(of: config.sound_effects) { _ in save() }
                    Spacer()
                    Button("Test Sound") {
                        SoundFeedback.shared.playStart()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            SoundFeedback.shared.playStop()
                        }
                    }
                    .buttonStyle(.bordered)
                }

                HStack {
                    Toggle("Trackpad Haptic Feedback (Physical click on start/stop)", isOn: $config.haptic_feedback)
                        .onChange(of: config.haptic_feedback) { _ in save() }
                    Spacer()
                    Button("Test Haptic") {
                        HapticFeedback.shared.trigger(.start)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding()
        .onAppear {
            config = ConfigManager.shared.config
        }
    }

    private func save() {
        ConfigManager.shared.config = config
        ConfigManager.shared.save()
    }
}

// MARK: - 2. Audio Input Settings View
public struct AudioInputSettingsView: View {
    @ObservedObject private var deviceManager = AudioDeviceManager.shared
    @State private var selectedDeviceID: String = ConfigManager.shared.config.selected_audio_device_id ?? "default"
    @State private var micAuthorized = false
    @State private var speechAuthorized = false
    @State private var accessibilityTrusted = false

    public init() {}

    public var body: some View {
        Form {
            Section(header: Text("Microphone Selection").font(.headline)) {
                HStack {
                    Picker("Input Device", selection: $selectedDeviceID) {
                        ForEach(deviceManager.availableDevices) { dev in
                            Text(dev.name + (dev.isDefault ? " (Default)" : "")).tag(dev.id)
                        }
                    }
                    .onChange(of: selectedDeviceID) { newId in
                        ConfigManager.shared.config.selected_audio_device_id = (newId == "default" ? nil : newId)
                        ConfigManager.shared.save()
                    }

                    Button("Refresh") {
                        deviceManager.refreshDevices()
                    }
                }

                // Live Audio VU Meter Test
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Microphone Live Test")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                        Button(deviceManager.isMicTesting ? "Stop Test" : "Test Microphone") {
                            if deviceManager.isMicTesting {
                                deviceManager.stopMicTest()
                            } else {
                                deviceManager.startMicTest()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(deviceManager.isMicTesting ? .red : .accentColor)
                    }

                    HStack(spacing: 6) {
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.secondary.opacity(0.2))
                                    .frame(height: 14)

                                RoundedRectangle(cornerRadius: 4)
                                    .fill(levelColor(level: deviceManager.testAudioLevel))
                                    .frame(width: max(0, CGFloat(deviceManager.testAudioLevel) * geometry.size.width), height: 14)
                                    .animation(.easeOut(duration: 0.08), value: deviceManager.testAudioLevel)
                            }
                        }
                        .frame(height: 14)

                        Text("\(Int(deviceManager.testAudioLevel * 100))%")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .frame(width: 36, alignment: .trailing)
                    }
                }
                .padding(.vertical, 6)
            }

            Section(header: Text("System Permissions").font(.headline)) {
                // Microphone
                HStack {
                    Image(systemName: micAuthorized ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(micAuthorized ? .green : .red)
                    Text("Microphone Access")
                    Spacer()
                    if !micAuthorized {
                        Button("Open Settings") {
                            AudioDeviceManager.openMicrophoneSettings()
                        }
                    } else {
                        Text("Granted").font(.caption).foregroundColor(.secondary)
                    }
                }

                // Speech Recognition
                HStack {
                    Image(systemName: speechAuthorized ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(speechAuthorized ? .green : .red)
                    Text("Speech Recognition (Apple Neural Engine)")
                    Spacer()
                    if !speechAuthorized {
                        Button("Request Access") {
                            SpeechManager.requestPermissions { granted in
                                checkStatus()
                            }
                        }
                    } else {
                        Text("Granted").font(.caption).foregroundColor(.secondary)
                    }
                }

                // Accessibility
                HStack {
                    Image(systemName: accessibilityTrusted ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(accessibilityTrusted ? .green : .red)
                    Text("Accessibility (Simulated Paste into Apps)")
                    Spacer()
                    if !accessibilityTrusted {
                        Button("Request Access") {
                            TextPaster.requestAccessibilityPermission()
                        }
                    } else {
                        Text("Granted").font(.caption).foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding()
        .onAppear(perform: checkStatus)
        .onDisappear {
            if deviceManager.isMicTesting {
                deviceManager.stopMicTest()
            }
        }
    }

    private func checkStatus() {
        selectedDeviceID = ConfigManager.shared.config.selected_audio_device_id ?? "default"
        micAuthorized = (AudioDeviceManager.microphonePermissionStatus() == .authorized)
        speechAuthorized = (AudioDeviceManager.speechRecognitionPermissionStatus() == .authorized)
        accessibilityTrusted = TextPaster.isAccessibilityTrusted()
    }

    private func levelColor(level: Float) -> Color {
        if level > 0.8 { return .red }
        if level > 0.5 { return .yellow }
        return .green
    }
}

// MARK: - 3. AI & LLM Backend Settings View
public struct LLMSettingsView: View {
    @State private var config = ConfigManager.shared.config
    @State private var connectionStatus: String?
    @State private var isConnected: Bool?
    @State private var isTesting = false

    public init() {}

    public var body: some View {
        Form {
            Section(header: Text("Ollama Local LLM Endpoint").font(.headline)) {
                TextField("Server URL (e.g. http://127.0.0.1:11434)", text: $config.llm_url)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .onChange(of: config.llm_url) { _ in save() }

                TextField("Model Name (e.g. qwen2.5-coder:1.5b)", text: $config.llm_model)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .onChange(of: config.llm_model) { _ in save() }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Temperature (Lower = more deterministic):")
                        Spacer()
                        Text(String(format: "%.2f", config.llm_temperature))
                            .foregroundColor(.secondary)
                    }
                    Slider(
                        value: $config.llm_temperature,
                        in: 0.0...1.0,
                        step: 0.05
                    )
                    .onChange(of: config.llm_temperature) { _ in save() }
                }

                HStack {
                    Button(isTesting ? "Testing..." : "Test Connection") {
                        testConnection()
                    }
                    .disabled(isTesting)

                    if let connected = isConnected, let msg = connectionStatus {
                        HStack(spacing: 4) {
                            Image(systemName: connected ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundColor(connected ? .green : .red)
                            Text(msg)
                                .font(.caption)
                                .foregroundColor(connected ? .green : .red)
                        }
                        .padding(.leading, 8)
                    }
                }
                .padding(.vertical, 4)
            }

            Section(header: Text("Custom System Prompt / Style Instructions").font(.headline)) {
                Text("Customize how the local LLM polishes your speech. Leave blank to use LocalFlow's default cleanup filter.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                TextEditor(text: Binding(
                    get: { config.llm_system_prompt ?? "" },
                    set: { config.llm_system_prompt = $0.isEmpty ? nil : $0; save() }
                ))
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 120)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3), lineWidth: 1))

                HStack {
                    Spacer()
                    Button("Reset to Default Prompt") {
                        config.llm_system_prompt = nil
                        save()
                    }
                    .font(.caption)
                }
            }
        }
        .padding()
        .onAppear {
            config = ConfigManager.shared.config
        }
    }

    private func save() {
        ConfigManager.shared.config = config
        ConfigManager.shared.save()
    }

    private func testConnection() {
        isTesting = true
        connectionStatus = nil
        isConnected = nil
        OllamaClient.shared.testConnection { success, message in
            self.isTesting = false
            self.isConnected = success
            self.connectionStatus = message
        }
    }
}

// MARK: - 4. Vocabulary View
public struct VocabularyView: View {
    @State private var vocabulary: [VocabularyEntry] = []
    @State private var searchText = ""
    @State private var triggerText = ""
    @State private var replacementText = ""
    @State private var selectedCategory = "tech"
    @State private var exportMessage: String?

    let categories = ["tech", "person", "company", "acronym", "location", "speech_fix", "general"]

    public init() {}

    public var filteredVocabulary: [VocabularyEntry] {
        if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            return vocabulary
        }
        return vocabulary.filter {
            $0.triggerPhrase.localizedCaseInsensitiveContains(searchText) ||
            $0.replacement.localizedCaseInsensitiveContains(searchText) ||
            $0.category.localizedCaseInsensitiveContains(searchText)
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Vocabulary & Auto-Correct")
                        .font(.headline)
                    Text("Jargon and phrases added here will be automatically substituted with your preferred spelling.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()

                Button("Export CSV") {
                    let csv = CorrectionStore.shared.exportVocabularyCSV()
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(csv, forType: .string)
                    exportMessage = "Copied CSV to clipboard!"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { exportMessage = nil }
                }

                Button("Export JSON") {
                    let json = CorrectionStore.shared.exportVocabularyJSON()
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(json, forType: .string)
                    exportMessage = "Copied JSON to clipboard!"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { exportMessage = nil }
                }

                Button("Import CSV") {
                    if let text = NSPasteboard.general.string(forType: .string), !text.isEmpty {
                        let count = CorrectionStore.shared.importVocabulary(fromCSV: text)
                        if count > 0 {
                            loadVocabulary()
                            exportMessage = "Imported \(count) entries from clipboard CSV!"
                        } else {
                            exportMessage = "No valid CSV rows found on clipboard (format: TriggerPhrase,Replacement...)"
                        }
                    } else {
                        exportMessage = "Clipboard is empty. Copy CSV text first."
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { exportMessage = nil }
                }
            }

            if let msg = exportMessage {
                Text(msg)
                    .font(.caption)
                    .foregroundColor(.accentColor)
            }

            // Search and Add Form
            HStack(spacing: 8) {
                TextField("Search vocabulary...", text: $searchText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(maxWidth: 180)

                TextField("Spoken phrase (e.g. whisper flow)", text: $triggerText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())

                Image(systemName: "arrow.right")
                    .foregroundColor(.secondary)

                TextField("Replacement (e.g. Wispr Flow)", text: $replacementText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())

                Picker("", selection: $selectedCategory) {
                    ForEach(categories, id: \.self) { cat in
                        Text(cat.capitalized).tag(cat)
                    }
                }
                .frame(width: 105)

                Button("Add Word") {
                    addWord()
                }
                .buttonStyle(.borderedProminent)
                .disabled(triggerText.trimmingCharacters(in: .whitespaces).isEmpty || replacementText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.vertical, 4)

            Divider()

            // List of Existing Vocabulary
            List {
                ForEach(filteredVocabulary) { entry in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(entry.triggerPhrase)
                                    .fontWeight(.medium)
                                Image(systemName: "arrow.right")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text(entry.replacement)
                                    .fontWeight(.bold)
                                    .foregroundColor(.accentColor)
                            }
                            Text("Category: \(entry.category.capitalized) • Used: \(entry.useCount) times")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            deleteWord(entry.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(BorderlessButtonStyle())
                    }
                    .padding(.vertical, 2)
                }
            }
            .listStyle(InsetListStyle())
        }
        .onAppear(perform: loadVocabulary)
    }

    private func loadVocabulary() {
        vocabulary = CorrectionStore.shared.getAllVocabulary()
    }

    private func addWord() {
        let trigger = triggerText.trimmingCharacters(in: .whitespacesAndNewlines)
        let repl = replacementText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trigger.isEmpty && !repl.isEmpty else { return }

        CorrectionStore.shared.saveVocabulary(triggerPhrase: trigger, replacement: repl, category: selectedCategory)
        triggerText = ""
        replacementText = ""
        loadVocabulary()
    }

    private func deleteWord(_ id: Int64) {
        CorrectionStore.shared.deleteVocabulary(id: id)
        loadVocabulary()
    }
}

// MARK: - 5. History & Analytics View
public struct HistoryView: View {
    @State private var history: [HistoryEntry] = []
    @State private var searchText = ""
    @State private var totalCount = 0
    @State private var totalWords = 0
    @State private var showClearAlert = false
    @State private var exportMessage: String?
    @State private var copiedEntryId: Int64?

    public init() {}

    public var filteredHistory: [HistoryEntry] {
        if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            return history
        }
        return history.filter {
            $0.polishedText.localizedCaseInsensitiveContains(searchText) ||
            $0.rawTranscript.localizedCaseInsensitiveContains(searchText) ||
            $0.appName.localizedCaseInsensitiveContains(searchText)
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Stats Row
            HStack(spacing: 16) {
                StatCard(title: "Total Dictations", value: "\(totalCount)", icon: "mic.fill")
                StatCard(title: "Words Polished", value: "\(totalWords)", icon: "text.quote")
                StatCard(title: "Est. Time Saved", value: "\(estimatedMinutesSaved()) min", icon: "bolt.fill")
                Spacer()

                Button("Export CSV") {
                    let csv = CorrectionStore.shared.exportHistoryCSV()
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(csv, forType: .string)
                    exportMessage = "Copied CSV to clipboard!"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { exportMessage = nil }
                }

                Button("Clear History", role: .destructive) {
                    showClearAlert = true
                }
            }
            .alert(isPresented: $showClearAlert) {
                Alert(
                    title: Text("Clear Dictation History?"),
                    message: Text("This will permanently delete all stored dictations."),
                    primaryButton: .destructive(Text("Clear All")) {
                        CorrectionStore.shared.clearAllHistory()
                        loadHistory()
                    },
                    secondaryButton: .cancel()
                )
            }

            if let msg = exportMessage {
                Text(msg)
                    .font(.caption)
                    .foregroundColor(.accentColor)
            }

            // Search Bar
            HStack {
                TextField("Search history by text or app name...", text: $searchText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                Spacer()
            }

            // History List
            List {
                ForEach(filteredHistory) { entry in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(entry.appName)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.15))
                                .cornerRadius(4)

                            Text(entry.timestamp, style: .time)
                                .font(.caption2)
                                .foregroundColor(.secondary)

                            Spacer()

                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(entry.polishedText, forType: .string)
                                copiedEntryId = entry.id
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                    if copiedEntryId == entry.id {
                                        copiedEntryId = nil
                                    }
                                }
                            } label: {
                                Image(systemName: copiedEntryId == entry.id ? "checkmark" : "doc.on.doc")
                                    .font(.caption)
                                    .foregroundColor(copiedEntryId == entry.id ? .green : .primary)
                            }
                            .buttonStyle(BorderlessButtonStyle())
                            .help("Copy to clipboard")

                            Button {
                                deleteEntry(entry.id)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.caption)
                            }
                            .buttonStyle(BorderlessButtonStyle())
                        }

                        Text(entry.polishedText)
                            .font(.body)

                        if entry.rawTranscript != entry.polishedText {
                            Text("Raw: \(entry.rawTranscript)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .listStyle(InsetListStyle())
        }
        .onAppear(perform: loadHistory)
    }

    private func loadHistory() {
        history = CorrectionStore.shared.getAllHistory(limit: 200)
        let stats = CorrectionStore.shared.getHistoryStats()
        totalCount = stats.totalCount
        totalWords = stats.totalWords
    }

    private func deleteEntry(_ id: Int64) {
        CorrectionStore.shared.deleteHistory(id: id)
        loadHistory()
    }

    private func estimatedMinutesSaved() -> Int {
        // Assume dictating @ 130 WPM vs typing @ 40 WPM: save ~0.017 min per word
        let saved = Double(totalWords) * (1.0 / 40.0 - 1.0 / 130.0)
        return max(1, Int(saved))
    }
}

public struct StatCard: View {
    let title: String
    let value: String
    let icon: String

    public var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.headline)
                    .fontWeight(.bold)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
    }
}
