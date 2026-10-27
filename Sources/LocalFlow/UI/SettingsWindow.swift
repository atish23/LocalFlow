import SwiftUI
import AppKit

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
        window.title = "LocalFlow Settings & Vocabulary"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 640, height: 480))
        window.center()
        window.isReleasedWhenClosed = false

        let controller = NSWindowController(window: window)
        self.windowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct SettingsRootView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            VocabularyView()
                .tabItem {
                    Label("Vocabulary", systemImage: "character.book.closed")
                }
                .tag(0)

            HistoryView()
                .tabItem {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
                .tag(1)

            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
                .tag(2)
        }
        .frame(minWidth: 600, minHeight: 440)
        .padding()
    }
}

// MARK: - Vocabulary View
struct VocabularyView: View {
    @State private var vocabulary: [VocabularyEntry] = []
    @State private var triggerText = ""
    @State private var replacementText = ""
    @State private var selectedCategory = "tech"

    let categories = ["tech", "name", "acronym", "general"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Personal Vocabulary & Auto-Correct")
                .font(.headline)
            Text("Words and technical jargon added here will be automatically substituted with your preferred spelling.")
                .font(.subheadline)
                .foregroundColor(.secondary)

            // Add New Entry Form
            HStack(spacing: 8) {
                TextField("Misheard phrase (e.g. whisper flow)", text: $triggerText)
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
                .frame(width: 100)

                Button("Add Word") {
                    addWord()
                }
                .disabled(triggerText.trimmingCharacters(in: .whitespaces).isEmpty || replacementText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.vertical, 4)

            Divider()

            // List of Existing Vocabulary
            List {
                ForEach(vocabulary, id: \.id) { entry in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(entry.triggerPhrase)
                                    .fontWeight(.medium)
                                Image(systemName: "arrow.right")
                                    .font(.caption)
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

// MARK: - History View
struct HistoryView: View {
    @State private var history: [HistoryEntry] = []
    @State private var searchText = ""

    var filteredHistory: [HistoryEntry] {
        if searchText.isEmpty { return history }
        return history.filter {
            $0.polishedText.localizedCaseInsensitiveContains(searchText) ||
            $0.rawTranscript.localizedCaseInsensitiveContains(searchText) ||
            $0.appName.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Dictation History")
                    .font(.headline)
                Spacer()
                TextField("Search past dictations...", text: $searchText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(width: 200)
            }

            List {
                ForEach(filteredHistory, id: \.id) { entry in
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
        history = CorrectionStore.shared.getAllHistory(limit: 100)
    }

    private func deleteEntry(_ id: Int64) {
        CorrectionStore.shared.deleteHistory(id: id)
        loadHistory()
    }
}

// MARK: - General Settings View
struct GeneralSettingsView: View {
    @State private var headless = ConfigManager.shared.config.headless
    @State private var soundEffects = ConfigManager.shared.config.sound_effects
    @State private var doubleTapThreshold = Double(ConfigManager.shared.config.double_tap_threshold_ms)

    var body: some View {
        Form {
            Section(header: Text("UI & Behavior").font(.headline)) {
                Toggle("Headless Mode (Zero visual UI, audio cues only)", isOn: $headless)
                    .onChange(of: headless) { newValue in
                        ConfigManager.shared.config.headless = newValue
                    }

                Toggle("Audio Sound Feedback (Tink on start, Pop on paste)", isOn: $soundEffects)
                    .onChange(of: soundEffects) { newValue in
                        ConfigManager.shared.config.sound_effects = newValue
                    }

                VStack(alignment: .leading) {
                    Text("Double-Tap Shortcut Speed: \(Int(doubleTapThreshold)) ms")
                    Slider(value: $doubleTapThreshold, in: 250...650, step: 25) {
                        Text("Double-Tap Threshold")
                    }
                    .onChange(of: doubleTapThreshold) { newValue in
                        ConfigManager.shared.config.double_tap_threshold_ms = Int(newValue)
                    }
                }
                .padding(.top, 4)
            }

            Section(header: Text("Global Shortcut").font(.headline)) {
                Text("• Start Dictation: Double-tap Control (Ctrl Ctrl)\n• Stop & Paste: Single-tap Control (Ctrl)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
    }
}
