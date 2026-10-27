import SwiftUI
import AppKit
import AVFoundation

// MARK: - Window Manager

public final class SettingsWindowManager: NSObject, NSWindowDelegate {
    public static let shared = SettingsWindowManager()
    private var windowController: NSWindowController?

    public func showSettings() {
        if let controller = windowController, let window = controller.window, window.isVisible {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            controller.showWindow(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let contentView = SettingsRootView()
        let hostingController = NSHostingController(rootView: contentView)
        let window = NSWindow(contentViewController: hostingController)
        window.delegate = self
        window.title = "LocalFlow Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.toolbarStyle = .unified
        window.setFrameAutosaveName("LocalFlowSettingsWindow")
        window.setContentSize(NSSize(width: 900, height: 640))
        window.minSize = NSSize(width: 800, height: 560)
        window.center()
        window.isReleasedWhenClosed = false

        let controller = NSWindowController(window: window)
        self.windowController = controller
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func windowWillClose(_ notification: Notification) {
        AudioDeviceManager.shared.stopMicTest()
        self.windowController = nil
    }
}

// MARK: - Visual Effect Blur Representable

public struct VisualEffectView: NSViewRepresentable {
    public let material: NSVisualEffectView.Material
    public let blendingMode: NSVisualEffectView.BlendingMode

    public init(
        material: NSVisualEffectView.Material = .sidebar,
        blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    ) {
        self.material = material
        self.blendingMode = blendingMode
    }

    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    public func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - Navigation Tabs

public enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "General"
    case audio = "Audio Input"
    case ai = "AI Backend"
    case vocabulary = "Vocabulary & Snippets"
    case history = "History & Analytics"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .general: return "gearshape.fill"
        case .audio: return "mic.fill"
        case .ai: return "sparkles"
        case .vocabulary: return "character.book.closed.fill"
        case .history: return "clock.arrow.circlepath"
        }
    }

    public var subtitle: String {
        switch self {
        case .general: return "Hotkeys, triggers, and sensory feedback"
        case .audio: return "Microphone device and live level monitor"
        case .ai: return "Ollama models, temperature, and app styles"
        case .vocabulary: return "Custom terms, proper nouns, and snippet tags"
        case .history: return "Dictation log, analytics, and clipboard export"
        }
    }

    public var tintColor: Color {
        switch self {
        case .general: return .blue
        case .audio: return .purple
        case .ai: return .indigo
        case .vocabulary: return .orange
        case .history: return .teal
        }
    }
}

// MARK: - Settings Root View

public struct SettingsRootView: View {
    @State private var selectedTab: SettingsTab = .general

    public init() {}

    public var body: some View {
        HStack(spacing: 0) {
            // Sidebar Navigation
            SidebarView(selectedTab: $selectedTab)
                .frame(width: 240)

            Divider()

            // Main Detail Content Area
            DetailContentView(selectedTab: selectedTab)
                .frame(minWidth: 560, maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 840, minHeight: 580)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// MARK: - Sidebar View

private struct SidebarView: View {
    @Binding var selectedTab: SettingsTab
    private let configManager = ConfigManager.shared

    var body: some View {
        ZStack {
            VisualEffectView(material: .sidebar, blendingMode: .behindWindow)

            VStack(alignment: .leading, spacing: 0) {
                // Header Branding with traffic light clearance
                HStack(spacing: 12) {
                    ZStack {
                        LinearGradient(
                            colors: [Color.blue, Color.purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .frame(width: 36, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .shadow(color: Color.blue.opacity(0.3), radius: 4, x: 0, y: 2)

                        Image(systemName: "mic.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 5) {
                            Text("LocalFlow")
                                .font(.system(size: 15, weight: .bold))
                            Text("v1.0")
                                .font(.system(size: 9, weight: .semibold))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.secondary.opacity(0.18))
                                .clipShape(Capsule())
                        }
                        Text("Private Voice Dictation")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 44)
                .padding(.bottom, 16)

                // Navigation Items
                VStack(spacing: 4) {
                    ForEach(SettingsTab.allCases) { tab in
                        SidebarButton(
                            tab: tab,
                            isSelected: selectedTab == tab,
                            action: {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    selectedTab = tab
                                }
                            }
                        )
                    }
                }
                .padding(.horizontal, 10)

                Spacer()

                // Sidebar Footer: Quick Info & Config Folder
                VStack(spacing: 10) {
                    Divider()

                    // Quick status pill
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 7, height: 7)
                            .shadow(color: Color.green.opacity(0.5), radius: 3)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(configManager.config.hotkey_mode == .toggle
                                 ? "Double-Tap \(configManager.config.trigger_key.displayName)"
                                 : "Hold \(configManager.config.trigger_key.displayName)")
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                            Text(configManager.config.headless ? "Headless Mode" : "Floating HUD Active")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.primary.opacity(0.04))
                    )

                    Button {
                        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/localflow")
                        NSWorkspace.shared.open(dir)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "folder")
                                .font(.system(size: 11))
                            Text("Open Config Folder")
                                .font(.system(size: 11))
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            }
        }
    }
}

private struct SidebarButton: View {
    let tab: SettingsTab
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? Color.white.opacity(0.25) : tab.tintColor.opacity(0.14))
                        .frame(width: 26, height: 26)

                    Image(systemName: tab.iconName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(isSelected ? .white : tab.tintColor)
                }

                Text(tab.rawValue)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .white : .primary)
                    .lineLimit(1)

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Detail Content View

private struct DetailContentView: View {
    let selectedTab: SettingsTab

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 3) {
                    Text(selectedTab.rawValue)
                        .font(.system(size: 24, weight: .bold))
                    Text(selectedTab.subtitle)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 4)

                // Tab Specific Content
                switch selectedTab {
                case .general:
                    GeneralSettingsView()
                case .audio:
                    AudioInputSettingsView()
                case .ai:
                    LLMSettingsView()
                case .vocabulary:
                    VocabularyView()
                case .history:
                    HistoryView()
                }
            }
            .padding(26)
        }
        .id(selectedTab)
    }
}

// MARK: - Card Container

public struct CardContainer<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.65))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.02), radius: 4, x: 0, y: 1)
    }
}

// MARK: - Card Section Header

public struct CardSectionHeader: View {
    let title: String
    let icon: String
    let subtitle: String?

    public init(title: String, icon: String, subtitle: String? = nil) {
        self.title = title
        self.icon = icon
        self.subtitle = subtitle
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.accentColor)
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
            }
            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .padding(.leading, 22)
            }
        }
    }
}

// MARK: - 1. General Settings View

public struct GeneralSettingsView: View {
    @State private var config = ConfigManager.shared.config
    @State private var soundTestPlaying = false
    @State private var hapticTestTriggered = false

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Card 1: Dictation Activation Mode
            CardContainer {
                CardSectionHeader(
                    title: "Dictation Mode",
                    icon: "keyboard.fill",
                    subtitle: "Choose how dictation is initiated and concluded."
                )

                HStack(spacing: 12) {
                    // Push to Talk Option Card
                    ModeCard(
                        title: "Hold to Talk",
                        subtitle: "Press and hold to dictate. Release key to stop and paste.",
                        icon: "waveform.and.mic",
                        isSelected: config.hotkey_mode == .pushToTalk,
                        action: {
                            config.hotkey_mode = .pushToTalk
                            save()
                        }
                    )

                    // Double-Tap Option Card
                    ModeCard(
                        title: "Double-Tap Toggle",
                        subtitle: "Tap twice quickly to start. Tap once while recording to stop.",
                        icon: "repeat.circle.fill",
                        isSelected: config.hotkey_mode == .toggle,
                        action: {
                            config.hotkey_mode = .toggle
                            save()
                        }
                    )
                }
            }

            // Card 2: Physical Modifier Keycap Selector
            CardContainer {
                CardSectionHeader(
                    title: "Physical Trigger Key",
                    icon: "command.square.fill",
                    subtitle: "Select the physical modifier key on your Mac keyboard."
                )

                HStack(spacing: 10) {
                    ForEach(HotkeyTriggerKey.allCases, id: \.self) { key in
                        KeycapButton(
                            key: key,
                            isSelected: config.trigger_key == key,
                            action: {
                                config.trigger_key = key
                                save()
                            }
                        )
                    }
                }
                .padding(.vertical, 4)

                // Contextual guide message
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Text(config.hotkey_mode == .toggle
                         ? "Tap \(config.trigger_key.displayName) twice in quick succession to dictate. Tap once while active to finish."
                         : "Press and hold \(config.trigger_key.displayName) while speaking. Release key to transcribe and paste.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .padding(.top, 2)
            }

            // Card 3: Double-Tap Threshold Slider (Only for toggle mode)
            if config.hotkey_mode == .toggle {
                CardContainer {
                    CardSectionHeader(
                        title: "Double-Tap Speed Window",
                        icon: "timer",
                        subtitle: "Maximum interval permitted between the two taps."
                    )

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Interval Threshold:")
                                .font(.system(size: 13, weight: .medium))
                            Spacer()
                            Text("\(config.double_tap_threshold_ms) ms (\(speedLabel(for: config.double_tap_threshold_ms)))")
                                .font(.system(size: 12, weight: .semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.accentColor.opacity(0.12))
                                .foregroundColor(.accentColor)
                                .clipShape(Capsule())
                        }

                        Slider(
                            value: Binding(
                                get: { Double(config.double_tap_threshold_ms) },
                                set: { config.double_tap_threshold_ms = Int($0); save() }
                            ),
                            in: 200...650,
                            step: 25
                        )

                        HStack {
                            Text("Snappy (200 ms)")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("Balanced (400 ms)")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("Relaxed (650 ms)")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            // Card 4: Feedback & Interface Preferences
            CardContainer {
                CardSectionHeader(
                    title: "Feedback & Interface",
                    icon: "slider.horizontal.3",
                    subtitle: "Control visual overlay and sensory cues."
                )

                VStack(spacing: 12) {
                    // Headless Mode Row
                    ToggleRow(
                        title: "Headless Mode (Zero Visual UI)",
                        subtitle: "Hides the floating pill HUD. State is conveyed purely via audio chimes and haptics.",
                        isOn: $config.headless,
                        onChange: save
                    )

                    Divider()

                    // Sound Effects Row
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Audio Sound Effects")
                                .font(.system(size: 13, weight: .medium))
                            Text("Play subtle chime on start and completion.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button {
                            SoundFeedback.shared.playStart()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                SoundFeedback.shared.playStop()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "speaker.wave.2")
                                    .font(.system(size: 11))
                                Text("Test Chime")
                                    .font(.system(size: 11))
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Toggle("", isOn: $config.sound_effects)
                            .labelsHidden()
                            .onChange(of: config.sound_effects) { _ in save() }
                    }

                    Divider()

                    // Trackpad Haptics Row
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Trackpad Haptic Feedback")
                                .font(.system(size: 13, weight: .medium))
                            Text("Tactile click sensation on Force Touch trackpads when recording starts and ends.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button {
                            HapticFeedback.shared.trigger(.start)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "hand.tap")
                                    .font(.system(size: 11))
                                Text("Test Click")
                                    .font(.system(size: 11))
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Toggle("", isOn: $config.haptic_feedback)
                            .labelsHidden()
                            .onChange(of: config.haptic_feedback) { _ in save() }
                    }
                }
            }
        }
        .onAppear {
            config = ConfigManager.shared.config
        }
    }

    private func save() {
        ConfigManager.shared.config = config
        ConfigManager.shared.save()
    }

    private func speedLabel(for ms: Int) -> String {
        if ms < 325 { return "Fast" }
        if ms <= 475 { return "Normal" }
        return "Relaxed"
    }
}

private struct ModeCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    ZStack {
                        Circle()
                            .fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.15))
                            .frame(width: 32, height: 32)
                        Image(systemName: icon)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(isSelected ? .white : .primary)
                    }
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.accentColor)
                            .font(.system(size: 16))
                    }
                }

                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)

                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.02))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct KeycapButton: View {
    let key: HotkeyTriggerKey
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(NSColor.controlBackgroundColor))
                        .frame(height: 52)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(isSelected ? Color.accentColor : Color.primary.opacity(0.15), lineWidth: isSelected ? 2 : 1)
                        )
                        .shadow(color: Color.black.opacity(isSelected ? 0.08 : 0.02), radius: 3, x: 0, y: 1)

                    VStack(spacing: 2) {
                        Text(glyph(for: key))
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(isSelected ? .accentColor : .primary)
                        Text(shortName(for: key))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private func glyph(for key: HotkeyTriggerKey) -> String {
        switch key {
        case .control: return "^"
        case .option: return "Opt"
        case .command: return "Cmd"
        case .shift: return "Shift"
        case .function: return "fn"
        }
    }

    private func shortName(for key: HotkeyTriggerKey) -> String {
        switch key {
        case .control: return "Control"
        case .option: return "Option"
        case .command: return "Command"
        case .shift: return "Shift"
        case .function: return "Globe"
        }
    }
}

private struct ToggleRow: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    let onChange: () -> Void

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .onChange(of: isOn) { _ in onChange() }
        }
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
        VStack(alignment: .leading, spacing: 20) {
            // Card 1: Microphone Selection
            CardContainer {
                CardSectionHeader(
                    title: "Input Device",
                    icon: "mic.fill",
                    subtitle: "Choose the microphone for high-fidelity local voice recording."
                )

                HStack(spacing: 12) {
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.accentColor)

                    Picker("", selection: $selectedDeviceID) {
                        Text("System Default Microphone").tag("default")
                        ForEach(deviceManager.availableDevices) { dev in
                            Text(dev.name + (dev.isDefault ? " (Default)" : "")).tag(dev.id)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 320)
                    .onChange(of: selectedDeviceID) { newId in
                        ConfigManager.shared.config.selected_audio_device_id = (newId == "default" ? nil : newId)
                        ConfigManager.shared.save()
                        if deviceManager.isMicTesting {
                            deviceManager.stopMicTest()
                            deviceManager.startMicTest()
                        }
                    }

                    Button {
                        deviceManager.refreshDevices()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.bordered)
                    .help("Refresh connected audio inputs")

                    Spacer()
                }
            }

            // Card 2: Live Animated Microphone VU Meter
            CardContainer {
                CardSectionHeader(
                    title: "Live Audio Monitor",
                    icon: "waveform",
                    subtitle: "Speak into your microphone to verify capture levels."
                )

                VStack(spacing: 12) {
                    HStack {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(deviceManager.isMicTesting ? Color.red : Color.secondary.opacity(0.3))
                                .frame(width: 8, height: 8)
                            Text(deviceManager.isMicTesting ? "Recording active" : "Monitor idle")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(deviceManager.isMicTesting ? .red : .secondary)
                        }

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
                        .controlSize(.small)
                    }

                    // Segmented Live VU Meter
                    SegmentedLevelMeter(level: deviceManager.testAudioLevel)

                    HStack {
                        Text("Low (-50 dB)")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("Nominal Target")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("Peak (-12 dB)")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
            }

            // Card 3: System Permissions Status
            CardContainer {
                CardSectionHeader(
                    title: "System Permissions",
                    icon: "lock.shield.fill",
                    subtitle: "LocalFlow operates strictly on-device. Permissions are required for local mic access and auto-paste."
                )

                VStack(spacing: 12) {
                    // Microphone Permission
                    PermissionRow(
                        title: "Microphone Access",
                        subtitle: "Required for on-device voice capture.",
                        icon: "mic.fill",
                        isGranted: micAuthorized,
                        actionLabel: "Open System Settings",
                        action: {
                            AudioDeviceManager.openMicrophoneSettings()
                        }
                    )

                    Divider()

                    // Speech Recognition Permission
                    PermissionRow(
                        title: "Speech Recognition (Apple Neural Engine)",
                        subtitle: "Processes transcription locally via Apple Speech APIs.",
                        icon: "waveform.badge.magnifyingglass",
                        isGranted: speechAuthorized,
                        actionLabel: "Request Access",
                        action: {
                            SpeechManager.requestPermissions { _ in
                                checkStatus()
                            }
                        }
                    )

                    Divider()

                    // Accessibility Permission
                    PermissionRow(
                        title: "Accessibility (Paste Emulation)",
                        subtitle: "Simulates Command-V to paste polished text into your active application.",
                        icon: "command.circle.fill",
                        isGranted: accessibilityTrusted,
                        actionLabel: "Request Access",
                        action: {
                            TextPaster.requestAccessibilityPermission()
                        }
                    )
                }
            }
        }
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
}

// High-polish Segmented Audio Level Meter
private struct SegmentedLevelMeter: View {
    let level: Float
    private let barCount = 32

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<barCount, id: \.self) { index in
                let threshold = Float(index + 1) / Float(barCount)
                let isActive = level >= threshold && level > 0.01

                RoundedRectangle(cornerRadius: 2)
                    .fill(barColor(for: index, isActive: isActive))
                    .frame(height: 22)
            }

            Text("\(Int(level * 100))%")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 42, alignment: .trailing)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.04))
        )
    }

    private func barColor(for index: Int, isActive: Bool) -> Color {
        guard isActive else {
            return Color.secondary.opacity(0.12)
        }
        if index < 18 {
            return Color.green
        } else if index < 26 {
            return Color.yellow
        } else {
            return Color.red
        }
    }
}

private struct PermissionRow: View {
    let title: String
    let subtitle: String
    let icon: String
    let isGranted: Bool
    let actionLabel: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(isGranted ? Color.green.opacity(0.15) : Color.red.opacity(0.15))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(isGranted ? .green : .red)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            if isGranted {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                    Text("Granted")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(.green)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.green.opacity(0.1))
                .clipShape(Capsule())
            } else {
                Button(actionLabel, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }
}

// MARK: - 3. AI & LLM Backend Settings View

public struct LLMSettingsView: View {
    @State private var config = ConfigManager.shared.config
    @State private var connectionStatus: String?
    @State private var isConnected: Bool?
    @State private var isTesting = false
    @State private var installedModels: [String] = []

    // Quick suggestion models
    private let suggestedModels = [
        "qwen2.5-coder:1.5b",
        "llama3.2:1b",
        "llama3.2:3b",
        "mistral:7b",
        "gemma2:2b"
    ]

    // Predefined style tone templates
    private let stylePresets: [(name: String, text: String)] = [
        ("Concise", "Natural, direct, and concise. Omit conversational filler, format lists cleanly, and keep sentences punchy."),
        ("Conversational", "Natural, direct, and conversational. Keep my personal voice, avoid corporate jargon, and format clearly."),
        ("Technical", "Technical and precise. Format terminal commands, code identifiers, variables in backticks, and preserve terminology."),
        ("Executive", "Polished, professional, and well-structured. Use active voice, bullet points for lists, and concise clarity.")
    ]

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Card 1: Ollama Endpoint & Connection
            CardContainer {
                CardSectionHeader(
                    title: "Ollama Endpoint",
                    icon: "server.rack",
                    subtitle: "LocalFlow connects locally to Ollama for instant grammar cleanup."
                )

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "link")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)

                        TextField("Server URL (e.g. http://127.0.0.1:11434)", text: $config.llm_url)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .onChange(of: config.llm_url) { _ in save() }

                        Button(action: testConnection) {
                            HStack(spacing: 4) {
                                if isTesting {
                                    ProgressView()
                                        .controlSize(.mini)
                                } else {
                                    Image(systemName: "bolt.fill")
                                        .font(.system(size: 11))
                                }
                                Text(isTesting ? "Testing..." : "Test Connection")
                                    .font(.system(size: 12))
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                        .disabled(isTesting)
                    }

                    // Connection Result Pill
                    if let connected = isConnected, let msg = connectionStatus {
                        HStack(spacing: 6) {
                            Image(systemName: connected ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .font(.system(size: 13))
                            Text(msg)
                                .font(.system(size: 12))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .foregroundColor(connected ? .green : .red)
                        .background((connected ? Color.green : Color.red).opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }

            // Card 2: Model Name & Parameter Tuning
            CardContainer {
                CardSectionHeader(
                    title: "Model & Sampling",
                    icon: "cpu.fill",
                    subtitle: "Select which local LLM model performs the transcript polish."
                )

                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Model Name:")
                            .font(.system(size: 12, weight: .medium))

                        TextField("Model Name (e.g. qwen2.5-coder:1.5b)", text: $config.llm_model)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .onChange(of: config.llm_model) { _ in save() }
                    }

                    // Installed models chips if discovered
                    if !installedModels.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Installed on your Mac:")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(installedModels, id: \.self) { model in
                                        Button {
                                            config.llm_model = model
                                            save()
                                        } label: {
                                            HStack(spacing: 3) {
                                                if config.llm_model == model {
                                                    Image(systemName: "checkmark")
                                                        .font(.system(size: 9, weight: .bold))
                                                }
                                                Text(model)
                                                    .font(.system(size: 11, design: .monospaced))
                                            }
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(config.llm_model == model ? Color.accentColor : Color.secondary.opacity(0.12))
                                            .foregroundColor(config.llm_model == model ? .white : .primary)
                                            .clipShape(Capsule())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }

                    // Quick model selection chips
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Suggested Local Models:")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)

                        HStack(spacing: 6) {
                            ForEach(suggestedModels, id: \.self) { model in
                                Button {
                                    config.llm_model = model
                                    save()
                                } label: {
                                    HStack(spacing: 3) {
                                        if config.llm_model == model {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 9, weight: .bold))
                                        }
                                        Text(model)
                                            .font(.system(size: 11, design: .monospaced))
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(config.llm_model == model ? Color.accentColor : Color.secondary.opacity(0.12))
                                    .foregroundColor(config.llm_model == model ? .white : .primary)
                                    .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    Divider()

                    // Temperature Slider
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Sampling Temperature:")
                                .font(.system(size: 12, weight: .medium))
                            Spacer()
                            Text(String(format: "%.2f", config.llm_temperature))
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundColor(.accentColor)
                        }

                        Slider(
                            value: $config.llm_temperature,
                            in: 0.0...1.0,
                            step: 0.05
                        )
                        .onChange(of: config.llm_temperature) { _ in save() }

                        HStack {
                            Text("0.0 (Deterministic / Clean)")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("1.0 (Creative)")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            // Card 3: Personal Tone & Style Instructions
            CardContainer {
                CardSectionHeader(
                    title: "Personal Tone & Style",
                    icon: "text.badge.star",
                    subtitle: "Define how LocalFlow structures your voice and personal phrasing."
                )

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Text("Style Presets:")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)

                        ForEach(stylePresets, id: \.name) { preset in
                            Button {
                                config.style_instructions = preset.text
                                save()
                            } label: {
                                Text(preset.name)
                                    .font(.system(size: 11, weight: .medium))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(config.style_instructions == preset.text ? Color.accentColor : Color.secondary.opacity(0.12))
                                    .foregroundColor(config.style_instructions == preset.text ? .white : .primary)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    TextEditor(text: $config.style_instructions)
                        .font(.system(size: 12))
                        .frame(minHeight: 65)
                        .padding(6)
                        .background(Color(NSColor.textBackgroundColor))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.1), lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .onChange(of: config.style_instructions) { _ in save() }
                }
            }

            // Card 4: App-Aware Formatting Rules
            CardContainer {
                CardSectionHeader(
                    title: "App-Aware Formatting Rules",
                    icon: "app.badge.checkmark",
                    subtitle: "Automatically adapt tone (casual, formal, code) depending on the active frontmost app."
                )

                VStack(alignment: .leading, spacing: 10) {
                    let styles = config.app_styles ?? [:]
                    let keys = Array(styles.keys.sorted())

                    VStack(spacing: 6) {
                        ForEach(keys, id: \.self) { bundleId in
                            HStack(spacing: 10) {
                                Image(systemName: "app.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)

                                Text(bundleId)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.primary)

                                Spacer()

                                let currentStyle = styles[bundleId] ?? "standard"
                                Picker("", selection: Binding(
                                    get: { currentStyle },
                                    set: { newStyle in
                                        var map = config.app_styles ?? [:]
                                        map[bundleId] = newStyle
                                        config.app_styles = map
                                        save()
                                    }
                                )) {
                                    Text("Casual").tag("casual")
                                    Text("Formal").tag("formal")
                                    Text("Code").tag("code")
                                    Text("Standard").tag("standard")
                                }
                                .labelsHidden()
                                .frame(width: 105)

                                Button {
                                    var map = config.app_styles ?? [:]
                                    map.removeValue(forKey: bundleId)
                                    config.app_styles = map
                                    save()
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.02)))
                        }
                    }
                }
            }

            // Card 5: Custom System Prompt
            CardContainer {
                CardSectionHeader(
                    title: "Custom System Prompt",
                    icon: "doc.text.fill",
                    subtitle: "Override the default anti-hallucination rules with your own LLM system instructions."
                )

                VStack(alignment: .leading, spacing: 8) {
                    TextEditor(text: Binding(
                        get: { config.llm_system_prompt ?? "" },
                        set: { config.llm_system_prompt = $0.isEmpty ? nil : $0; save() }
                    ))
                    .font(.system(size: 12, design: .monospaced))
                    .frame(minHeight: 90)
                    .padding(6)
                    .background(Color(NSColor.textBackgroundColor))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.1), lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                    HStack {
                        Text("Leave empty to use LocalFlow default anti-hallucination rules.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Spacer()
                        Button("Reset to Default Prompt") {
                            config.llm_system_prompt = nil
                            save()
                        }
                        .font(.system(size: 11))
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
        .onAppear {
            config = ConfigManager.shared.config
            loadInstalledModels()
        }
    }

    private func save() {
        ConfigManager.shared.config = config
        ConfigManager.shared.save()
    }

    private func loadInstalledModels() {
        OllamaClient.shared.fetchInstalledModels { models in
            self.installedModels = models
        }
    }

    private func testConnection() {
        isTesting = true
        connectionStatus = nil
        isConnected = nil
        OllamaClient.shared.testConnection { success, message in
            self.isTesting = false
            self.isConnected = success
            self.connectionStatus = message
            if success {
                loadInstalledModels()
            }
        }
    }
}

// MARK: - 4. Vocabulary & Snippets View

public struct VocabularyView: View {
    @State private var vocabulary: [VocabularyEntry] = []
    @State private var config = ConfigManager.shared.config
    @State private var searchText = ""
    @State private var triggerText = ""
    @State private var replacementText = ""
    @State private var selectedCategory = "tech"
    @State private var selectedCategoryFilter: String? = nil
    @State private var exportMessage: String?
    @State private var newTagKey = ""
    @State private var newTagValue = ""

    public init() {}

    private var availableCategories: [String] {
        var set = Set(["tech", "tool", "concept", "acronym", "finance", "speech_fix", "person", "company", "design", "general"])
        for item in vocabulary {
            let cat = item.category.lowercased().trimmingCharacters(in: .whitespaces)
            if !cat.isEmpty {
                set.insert(cat)
            }
        }
        return Array(set).sorted()
    }

    public var filteredVocabulary: [VocabularyEntry] {
        var list = vocabulary
        if let catFilter = selectedCategoryFilter {
            list = list.filter { $0.category.lowercased() == catFilter.lowercased() }
        }
        if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            return list
        }
        return list.filter {
            $0.triggerPhrase.localizedCaseInsensitiveContains(searchText) ||
            $0.replacement.localizedCaseInsensitiveContains(searchText) ||
            $0.category.localizedCaseInsensitiveContains(searchText)
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Card 1: Add New Term Form
            CardContainer {
                CardSectionHeader(
                    title: "Add Custom Term",
                    icon: "plus.circle.fill",
                    subtitle: "Map commonly misheard phrases or proper nouns to exact spellings."
                )

                HStack(spacing: 8) {
                    TextField("Spoken (e.g. whisper flow)", text: $triggerText)
                        .textFieldStyle(RoundedBorderTextFieldStyle())

                    Image(systemName: "arrow.right")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))

                    TextField("Replacement (e.g. Wispr Flow)", text: $replacementText)
                        .textFieldStyle(RoundedBorderTextFieldStyle())

                    Picker("", selection: $selectedCategory) {
                        ForEach(availableCategories, id: \.self) { cat in
                            Text(cat.capitalized).tag(cat)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 110)

                    Button("Add Term") {
                        addWord()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .disabled(triggerText.trimmingCharacters(in: .whitespaces).isEmpty || replacementText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            // Card 2: Vocabulary List with Search & Category Filters
            CardContainer {
                // Toolbar
                HStack(spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        TextField("Search \(vocabulary.count) terms...", text: $searchText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color(NSColor.textBackgroundColor))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.12), lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                    Spacer()

                    Button {
                        let csv = CorrectionStore.shared.exportVocabularyCSV()
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(csv, forType: .string)
                        showToast("Copied CSV to clipboard!")
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.doc")
                                .font(.system(size: 11))
                            Text("Export CSV")
                                .font(.system(size: 11))
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        let json = CorrectionStore.shared.exportVocabularyJSON()
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(json, forType: .string)
                        showToast("Copied JSON to clipboard!")
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "curlybraces")
                                .font(.system(size: 11))
                            Text("Export JSON")
                                .font(.system(size: 11))
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        if let text = NSPasteboard.general.string(forType: .string), !text.isEmpty {
                            let count = CorrectionStore.shared.importVocabulary(fromCSV: text)
                            if count > 0 {
                                loadVocabulary()
                                showToast("Imported \(count) entries from clipboard!")
                            } else {
                                showToast("No valid CSV rows found on clipboard.")
                            }
                        } else {
                            showToast("Clipboard is empty.")
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down.doc")
                                .font(.system(size: 11))
                            Text("Import CSV")
                                .font(.system(size: 11))
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                // Toast Message
                if let msg = exportMessage {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11))
                        Text(msg)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.accentColor)
                    .padding(.vertical, 2)
                }

                // Category Filter Badges
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        CategoryFilterPill(title: "All (\(vocabulary.count))", isSelected: selectedCategoryFilter == nil) {
                            selectedCategoryFilter = nil
                        }
                        ForEach(availableCategories, id: \.self) { cat in
                            let count = vocabulary.filter { $0.category.lowercased() == cat.lowercased() }.count
                            if count > 0 || cat == "tech" || cat == "tool" {
                                CategoryFilterPill(title: "\(cat.capitalized) (\(count))", isSelected: selectedCategoryFilter == cat) {
                                    selectedCategoryFilter = cat
                                }
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }

                Divider()

                // Vocabulary Items List
                if filteredVocabulary.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "character.book.closed")
                            .font(.system(size: 28))
                            .foregroundColor(.secondary)
                        Text(searchText.isEmpty ? "No custom terms yet" : "No vocabulary matching \"\(searchText)\"")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                } else {
                    VStack(spacing: 6) {
                        ForEach(filteredVocabulary) { entry in
                            HStack(spacing: 10) {
                                Text(entry.triggerPhrase)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.secondary)

                                Image(systemName: "arrow.right")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary.opacity(0.6))

                                Text(entry.replacement)
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.accentColor)

                                Spacer()

                                // Category Badge
                                Text(entry.category.capitalized)
                                    .font(.system(size: 10, weight: .semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(badgeColor(for: entry.category).opacity(0.12))
                                    .foregroundColor(badgeColor(for: entry.category))
                                    .clipShape(Capsule())

                                // Use count
                                Text("\(entry.useCount)x")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)

                                Button {
                                    deleteWord(entry.id)
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help("Delete term")
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.primary.opacity(0.02))
                            )
                        }
                    }
                }
            }

            // Card 3: Snippet Expansions & Tags
            CardContainer {
                CardSectionHeader(
                    title: "Snippet Tags",
                    icon: "tag.fill",
                    subtitle: "Type or speak trigger tags like :standup to automatically expand common phrases."
                )

                // Add Tag Row
                HStack(spacing: 8) {
                    TextField("Tag (e.g. :standup)", text: $newTagKey)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(width: 150)

                    Image(systemName: "arrow.right")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))

                    TextField("Expansion text (e.g. Today I am focusing on)", text: $newTagValue)
                        .textFieldStyle(RoundedBorderTextFieldStyle())

                    Button("Add Tag") {
                        addSnippetTag()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .disabled(newTagKey.trimmingCharacters(in: .whitespaces).isEmpty || newTagValue.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                Divider()

                // List of Snippet Tags
                if config.tags.isEmpty {
                    Text("No snippet tags configured.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .padding(.vertical, 8)
                } else {
                    VStack(spacing: 6) {
                        ForEach(Array(config.tags.keys.sorted()), id: \.self) { key in
                            HStack(spacing: 10) {
                                Text(key)
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .foregroundColor(.accentColor)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.accentColor.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 4))

                                Image(systemName: "arrow.right")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary.opacity(0.5))

                                Text(config.tags[key] ?? "")
                                    .font(.system(size: 12))
                                    .foregroundColor(.primary)

                                Spacer()

                                Button {
                                    deleteSnippetTag(key)
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help("Delete snippet tag")
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.02)))
                        }
                    }
                }
            }
        }
        .onAppear {
            loadVocabulary()
            config = ConfigManager.shared.config
        }
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

    private func addSnippetTag() {
        let key = newTagKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let val = newTagValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty && !val.isEmpty else { return }

        config.tags[key] = val
        ConfigManager.shared.config = config
        ConfigManager.shared.save()
        newTagKey = ""
        newTagValue = ""
    }

    private func deleteSnippetTag(_ key: String) {
        config.tags.removeValue(forKey: key)
        ConfigManager.shared.config = config
        ConfigManager.shared.save()
    }

    private func showToast(_ text: String) {
        exportMessage = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            exportMessage = nil
        }
    }

    private func badgeColor(for category: String) -> Color {
        switch category.lowercased() {
        case "tech": return .blue
        case "tool": return .teal
        case "concept": return .indigo
        case "acronym": return .green
        case "person", "name": return .purple
        case "company": return .orange
        case "finance": return .mint
        case "speech_fix": return .yellow
        case "design": return .pink
        case "vehicle": return .cyan
        case "website": return .blue
        default: return .secondary
        }
    }
}

private struct CategoryFilterPill: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.12))
                .foregroundColor(isSelected ? .white : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
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
    @State private var expandedEntryIds: Set<Int64> = []

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
        VStack(alignment: .leading, spacing: 20) {
            // Card 1: Analytics Bento Grid
            HStack(spacing: 12) {
                StatCard(
                    title: "Total Dictations",
                    value: "\(totalCount)",
                    icon: "mic.fill",
                    tint: .blue
                )
                StatCard(
                    title: "Words Polished",
                    value: "\(totalWords)",
                    icon: "text.quote",
                    tint: .purple
                )
                StatCard(
                    title: "Time Saved",
                    value: "\(estimatedMinutesSaved()) min",
                    icon: "bolt.fill",
                    tint: .orange
                )
            }

            // Card 2: History Search & Records
            CardContainer {
                HStack(spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        TextField("Search history by text or application...", text: $searchText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color(NSColor.textBackgroundColor))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.12), lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                    Spacer()

                    Button {
                        let csv = CorrectionStore.shared.exportHistoryCSV()
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(csv, forType: .string)
                        showToast("Copied CSV history to clipboard!")
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.doc")
                                .font(.system(size: 11))
                            Text("Export CSV")
                                .font(.system(size: 11))
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button("Clear History", role: .destructive) {
                        showClearAlert = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .alert(isPresented: $showClearAlert) {
                    Alert(
                        title: Text("Clear Dictation History?"),
                        message: Text("This will permanently remove all stored speech history."),
                        primaryButton: .destructive(Text("Clear All")) {
                            CorrectionStore.shared.clearAllHistory()
                            loadHistory()
                        },
                        secondaryButton: .cancel()
                    )
                }

                if let msg = exportMessage {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11))
                        Text(msg)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.accentColor)
                    .padding(.vertical, 2)
                }

                Divider()

                // History Records
                if filteredHistory.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "clock")
                            .font(.system(size: 28))
                            .foregroundColor(.secondary)
                        Text(searchText.isEmpty ? "No dictation history recorded yet" : "No results for \"\(searchText)\"")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                } else {
                    VStack(spacing: 10) {
                        ForEach(filteredHistory) { entry in
                            HistoryCard(
                                entry: entry,
                                isCopied: copiedEntryId == entry.id,
                                isExpanded: expandedEntryIds.contains(entry.id),
                                onCopy: {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(entry.polishedText, forType: .string)
                                    copiedEntryId = entry.id
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                        if copiedEntryId == entry.id {
                                            copiedEntryId = nil
                                        }
                                    }
                                },
                                onDelete: {
                                    deleteEntry(entry.id)
                                },
                                onToggleExpand: {
                                    if expandedEntryIds.contains(entry.id) {
                                        expandedEntryIds.remove(entry.id)
                                    } else {
                                        expandedEntryIds.insert(entry.id)
                                    }
                                }
                            )
                        }
                    }
                }
            }
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

    private func showToast(_ text: String) {
        exportMessage = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            exportMessage = nil
        }
    }

    private func estimatedMinutesSaved() -> Int {
        let saved = Double(totalWords) * (1.0 / 40.0 - 1.0 / 130.0)
        return max(1, Int(saved))
    }
}

// Modern History Item Card with One-Click Copy & Raw Disclosure
private struct HistoryCard: View {
    let entry: HistoryEntry
    let isCopied: Bool
    let isExpanded: Bool
    let onCopy: () -> Void
    let onDelete: () -> Void
    let onToggleExpand: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Top Row: App, Timestamp, Actions
            HStack(spacing: 8) {
                // App badge
                HStack(spacing: 4) {
                    Image(systemName: "app.fill")
                        .font(.system(size: 9))
                    Text(entry.appName.isEmpty ? "Active App" : entry.appName)
                        .font(.system(size: 11, weight: .semibold))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 4))

                Text(entry.timestamp, style: .time)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                Spacer()

                // One-click Copy Button
                Button(action: onCopy) {
                    HStack(spacing: 4) {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11))
                        Text(isCopied ? "Copied" : "Copy")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(isCopied ? .green : .secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(isCopied ? Color.green.opacity(0.1) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
                .help("Copy polished text to clipboard")

                // Delete Button
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .padding(4)
                }
                .buttonStyle(.plain)
                .help("Delete entry")
            }

            // Polished Text Body
            Text(entry.polishedText)
                .font(.system(size: 13))
                .foregroundColor(.primary)
                .lineSpacing(3)
                .textSelection(.enabled)

            // Raw Transcript Disclosure
            if entry.rawTranscript != entry.polishedText {
                Button(action: onToggleExpand) {
                    HStack(spacing: 4) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                        Text(isExpanded ? "Hide raw transcript" : "Show raw transcript")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)

                if isExpanded {
                    Text(entry.rawTranscript)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.03))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

// MARK: - Bento Stat Card

public struct StatCard: View {
    public let title: String
    public let value: String
    public let icon: String
    public var tint: Color = .accentColor

    public init(title: String, value: String, icon: String, tint: Color = .accentColor) {
        self.title = title
        self.value = value
        self.icon = icon
        self.tint = tint
    }

    public var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(tint)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
            }
            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.65))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.02), radius: 3, x: 0, y: 1)
    }
}
