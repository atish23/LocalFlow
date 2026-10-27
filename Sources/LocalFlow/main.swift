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
    private var isStarting = false
    private var stopRequestedWhileStarting = false
    private var targetApp: NSRunningApplication?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
        setupStatusItem()
        setupSpeechManager()
        setupHotkey()

        configManager.onConfigUpdated = { [weak self] _ in
            self?.buildMenu()
        }

        print("LocalFlow started successfully.")

        let args = ProcessInfo.processInfo.arguments
        let isSilent = args.contains("--background") || args.contains("--silent") || args.contains("--headless-startup")
        if !isSilent {
            openSettingsWindow()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettingsWindow()
        return true
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // 1. App Menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        let appName = "LocalFlow"
        appMenu.addItem(NSMenuItem(title: "About \(appName)", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""))
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettingsWindow), keyEquivalent: ","))
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(NSMenuItem(title: "Hide \(appName)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        let hideOthersItem = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthersItem)
        appMenu.addItem(NSMenuItem(title: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: ""))
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(NSMenuItem(title: "Quit \(appName)", action: #selector(quitApp), keyEquivalent: "q"))
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // 2. Edit Menu (Enables ⌘C, ⌘V, ⌘X, ⌘A, ⌘Z in TextFields and TextEditors)
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        let redoItem = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(redoItem)
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        // 3. Window Menu (Enables ⌘W, ⌘M)
        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(NSMenuItem(title: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        windowMenu.addItem(NSMenuItem(title: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        NSApplication.shared.mainMenu = mainMenu
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
            self.isStarting = false
            self.stopRequestedWhileStarting = false
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
        if isRecording || isStarting {
            stopDictation()
        } else {
            startDictation()
        }
    }

    private func startDictation() {
        guard !isRecording && !isStarting else { return }

        // Capture active application before taking focus
        self.targetApp = NSWorkspace.shared.frontmostApplication
        self.isStarting = true
        self.stopRequestedWhileStarting = false

        if SpeechManager.hasPermissions() {
            beginRecordingPipeline()
        } else {
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
                    self.isStarting = false
                    self.stopRequestedWhileStarting = false
                    return
                }

                if self.stopRequestedWhileStarting {
                    print("Dictation cancelled before permissions completed.")
                    self.isStarting = false
                    self.stopRequestedWhileStarting = false
                    return
                }

                self.beginRecordingPipeline()
            }
        }
    }

    private func beginRecordingPipeline() {
        if self.stopRequestedWhileStarting {
            print("Dictation stopped while starting.")
            self.isStarting = false
            self.stopRequestedWhileStarting = false
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

        self.speechManager.startRecording { [weak self] result in
            guard let self = self else { return }
            self.isStarting = false

            switch result {
            case .success:
                print("Recording started...")
                if self.stopRequestedWhileStarting {
                    print("Executing deferred stop requested during audio engine startup.")
                    self.stopRequestedWhileStarting = false
                    self.stopDictation()
                }
            case .failure(let error):
                print("Failed to start recording: \(error.localizedDescription)")
                self.soundFeedback.playError()
                self.hapticFeedback.trigger(.error)
                self.isRecording = false
                self.hotkeyManager.isRecording = false
                self.stopRequestedWhileStarting = false
                if !self.configManager.config.headless {
                    self.pill.updateState(.error, partialText: error.localizedDescription)
                    self.pill.hidePill(delay: 2.0)
                }
            }
        }
    }

    private func stopDictation() {
        if isStarting {
            stopRequestedWhileStarting = true
        }

        guard isRecording else { return }
        isRecording = false
        isStarting = false
        stopRequestedWhileStarting = false
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
