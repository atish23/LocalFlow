import Cocoa
import Speech
import LocalFlowCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let speechManager = SpeechManager()
    private let pill = FloatingPillPanel()
    private let hotkeyManager = HotkeyManager.shared
    private let configManager = ConfigManager.shared
    private let correctionStore = CorrectionStore.shared
    private let soundFeedback = SoundFeedback.shared
    private let hapticFeedback = HapticFeedback.shared

    private var isRecording = false
    private var targetApp: NSRunningApplication?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupSpeechManager()
        setupHotkey()

        configManager.onConfigUpdated = { [weak self] _ in
            self?.buildMenu()
        }

        print("LocalFlow started successfully.")
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "LocalFlow")
            button.action = #selector(statusBarButtonClicked)
            button.target = self
        }
        buildMenu()
    }

    private func buildMenu() {
        let config = configManager.config
        let menu = NSMenu()

        let shortcutDesc: String
        if config.hotkey_mode == .toggle {
            shortcutDesc = "Toggle Dictation (Double-tap \(config.trigger_key.displayName))"
        } else {
            shortcutDesc = "Push-to-Talk (Hold \(config.trigger_key.displayName))"
        }

        menu.addItem(NSMenuItem(title: shortcutDesc, action: #selector(toggleDictation), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Settings & Preferences...", action: #selector(openSettingsWindow), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Mode: \(config.headless ? "Headless (Zero UI)" : "Floating Pill HUD")", action: #selector(toggleHeadlessMode), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Open Config Folder (~/.config/localflow)", action: #selector(openConfigFolder), keyEquivalent: "o"))
        menu.addItem(NSMenuItem(title: "Check System Permissions", action: #selector(checkPermissions), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit LocalFlow", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    @objc private func statusBarButtonClicked() {
        toggleDictation()
    }

    private func setupSpeechManager() {
        speechManager.onPartialTranscript = { [weak self] partial in
            guard let self = self else { return }
            if !self.configManager.config.headless {
                self.pill.updateState(.listening, partialText: partial)
            }
        }

        speechManager.onAudioLevel = { [weak self] level in
            guard let self = self else { return }
            if !self.configManager.config.headless {
                self.pill.updateAudioLevel(level)
            }
        }

        speechManager.onError = { [weak self] errorMsg in
            guard let self = self else { return }
            print("SpeechManager error: \(errorMsg)")
            self.soundFeedback.playError()
            self.hapticFeedback.trigger(.error)
            if !self.configManager.config.headless {
                self.pill.updateState(.error, partialText: errorMsg)
                self.pill.hidePill(delay: 2.0)
            }
            self.isRecording = false
            self.hotkeyManager.isRecording = false
        }
    }

    private func setupHotkey() {
        hotkeyManager.onStartRequested = { [weak self] in
            self?.startDictation()
        }
        hotkeyManager.onStopRequested = { [weak self] in
            self?.stopDictation()
        }
        hotkeyManager.startMonitoring()
    }

    @objc private func toggleDictation() {
        if isRecording {
            stopDictation()
        } else {
            startDictation()
        }
    }

    private func startDictation() {
        guard !isRecording else { return }

        // Capture active application before taking focus
        self.targetApp = NSWorkspace.shared.frontmostApplication

        SpeechManager.requestPermissions { [weak self] granted in
            guard let self = self else { return }
            guard granted else {
                print("Microphone or Speech Recognition permission not granted.")
                self.soundFeedback.playError()
                self.hapticFeedback.trigger(.error)
                if !self.configManager.config.headless {
                    self.pill.showPill()
                    self.pill.updateState(.error, partialText: "Mic or Speech permission denied.")
                    self.pill.hidePill(delay: 2.5)
                }
                return
            }

            self.isRecording = true
            self.hotkeyManager.isRecording = true

            self.soundFeedback.playStart()
            self.hapticFeedback.trigger(.start)

            if !self.configManager.config.headless {
                self.pill.showPill()
                self.pill.updateState(.listening, partialText: "")
            }

            self.speechManager.startRecording { result in
                switch result {
                case .success:
                    print("Recording started...")
                case .failure(let error):
                    print("Failed to start recording: \(error.localizedDescription)")
                    self.soundFeedback.playError()
                    self.hapticFeedback.trigger(.error)
                    self.isRecording = false
                    self.hotkeyManager.isRecording = false
                    if !self.configManager.config.headless {
                        self.pill.updateState(.error, partialText: error.localizedDescription)
                        self.pill.hidePill(delay: 2.0)
                    }
                }
            }
        }
    }

    private func stopDictation() {
        guard isRecording else { return }
        isRecording = false
        hotkeyManager.isRecording = false

        soundFeedback.playStop()
        hapticFeedback.trigger(.stop)

        if !configManager.config.headless {
            pill.updateState(.processing, partialText: "Transcribing...")
        }

        speechManager.stopRecording { [weak self] rawTranscript in
            guard let self = self else { return }
            let trimmed = rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                print("No speech detected.")
                self.pill.hidePill()
                return
            }

            let appName = self.targetApp?.localizedName ?? "Unknown"
            let bundleId = self.targetApp?.bundleIdentifier
            let appStyle = self.configManager.config.styleForApp(bundleId: bundleId)
            print("Direct Transcript: \"\(trimmed)\" (App: \(appName), Style: \(appStyle))")

            // 1. Instant deterministic pipeline
            let formatted = TextPolisher.shared.polish(
                text: trimmed,
                style: appStyle,
                tags: self.configManager.config.tags
            )

            if !self.configManager.config.headless {
                self.pill.updateState(.processing, partialText: "Polishing with Ollama...")
            }

            // 2. High-speed local LLM grammar and factual correction
            OllamaClient.shared.refineTranscript(formatted) { [weak self] polished in
                guard let self = self else { return }

                // Post-cleanup: ensure no duplicate loops or stutter phrases survive the LLM
                let finalPolished = TextPolisher.shared.deduplicateSentences(polished)

                // Save to SQLite history store
                self.correctionStore.saveHistory(
                    rawTranscript: trimmed,
                    polishedText: finalPolished,
                    appName: appName
                )

                if !self.configManager.config.headless {
                    self.pill.updateState(.done, partialText: finalPolished)
                }

                TextPaster.shared.paste(text: finalPolished, targetApp: self.targetApp) {
                    if !self.configManager.config.headless {
                        self.pill.hidePill(delay: 0.6)
                    }
                }
            }
        }
    }

    @objc private func toggleHeadlessMode() {
        configManager.config.headless.toggle()
        configManager.save()
        buildMenu()
    }

    @objc private func openConfigFolder() {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/localflow")
        NSWorkspace.shared.open(dir)
    }

    @objc private func checkPermissions() {
        SpeechManager.requestPermissions { granted in
            print("Speech and Mic permission status: \(granted)")
        }
        if !TextPaster.isAccessibilityTrusted() {
            print("Accessibility not granted. Requesting...")
            TextPaster.requestAccessibilityPermission()
        } else {
            print("Accessibility permission is active.")
        }
    }

    @objc private func openSettingsWindow() {
        SettingsWindowManager.shared.showSettings()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}

// Start Application
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
