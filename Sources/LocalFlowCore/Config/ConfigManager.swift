import Foundation

public enum DictationHotkeyMode: String, Codable, CaseIterable {
    case toggle = "toggle"
    case pushToTalk = "push_to_talk"

    public var displayName: String {
        switch self {
        case .toggle: return "Double-Tap Toggle"
        case .pushToTalk: return "Hold to Talk (Push to Talk)"
        }
    }
}

public enum HotkeyTriggerKey: String, Codable, CaseIterable {
    case control = "control"
    case option = "option"
    case command = "command"
    case shift = "shift"
    case function = "function"

    public var displayName: String {
        switch self {
        case .control: return "Control (⌃)"
        case .option: return "Option (⌥)"
        case .command: return "Command (⌘)"
        case .shift: return "Shift (⇧)"
        case .function: return "Function (fn / Globe)"
        }
    }
}

public struct LocalFlowConfig: Codable {
    public var llm_url: String
    public var llm_model: String
    public var llm_temperature: Double
    public var llm_system_prompt: String?
    public var headless: Bool
    public var sound_effects: Bool
    public var haptic_feedback: Bool
    public var hotkey_mode: DictationHotkeyMode
    public var trigger_key: HotkeyTriggerKey
    public var double_tap_threshold_ms: Int
    public var selected_audio_device_id: String?
    public var personal_dictionary: [String]
    public var tags: [String: String]
    public var style_instructions: String
    public var app_styles: [String: String]?

    public init(
        llm_url: String = "http://127.0.0.1:11434",
        llm_model: String = "qwen2.5-coder:1.5b",
        llm_temperature: Double = 0.0,
        llm_system_prompt: String? = nil,
        headless: Bool = false,
        sound_effects: Bool = true,
        haptic_feedback: Bool = true,
        hotkey_mode: DictationHotkeyMode = .toggle,
        trigger_key: HotkeyTriggerKey = .control,
        double_tap_threshold_ms: Int = 400,
        selected_audio_device_id: String? = nil,
        personal_dictionary: [String] = ["LocalFlow", "Wispr", "Kubernetes", "GraphQL", "Ollama"],
        tags: [String: String] = [":standup": "Today I am focusing on", ":email": "my.email@domain.com"],
        style_instructions: String = "Natural, direct, and conversational. Keep my personal tone, avoid unnecessary corporate filler, and format lists or numbers cleanly.",
        app_styles: [String: String]? = [
            "com.tinyspeck.slackmacgap": "casual",
            "org.whispersystems.signal-desktop": "casual",
            "com.apple.MobileSMS": "casual",
            "com.apple.mail": "formal",
            "com.google.Chrome": "standard",
            "com.apple.Terminal": "code",
            "com.microsoft.VSCode": "code"
        ]
    ) {
        self.llm_url = llm_url
        self.llm_model = llm_model
        self.llm_temperature = llm_temperature
        self.llm_system_prompt = llm_system_prompt
        self.headless = headless
        self.sound_effects = sound_effects
        self.haptic_feedback = haptic_feedback
        self.hotkey_mode = hotkey_mode
        self.trigger_key = trigger_key
        self.double_tap_threshold_ms = double_tap_threshold_ms
        self.selected_audio_device_id = selected_audio_device_id
        self.personal_dictionary = personal_dictionary
        self.tags = tags
        self.style_instructions = style_instructions
        self.app_styles = app_styles
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.llm_url = try container.decodeIfPresent(String.self, forKey: .llm_url) ?? "http://127.0.0.1:11434"
        self.llm_model = try container.decodeIfPresent(String.self, forKey: .llm_model) ?? "qwen2.5-coder:1.5b"
        self.llm_temperature = try container.decodeIfPresent(Double.self, forKey: .llm_temperature) ?? 0.0
        self.llm_system_prompt = try container.decodeIfPresent(String.self, forKey: .llm_system_prompt)
        self.headless = try container.decodeIfPresent(Bool.self, forKey: .headless) ?? false
        self.sound_effects = try container.decodeIfPresent(Bool.self, forKey: .sound_effects) ?? true
        self.haptic_feedback = try container.decodeIfPresent(Bool.self, forKey: .haptic_feedback) ?? true
        self.hotkey_mode = try container.decodeIfPresent(DictationHotkeyMode.self, forKey: .hotkey_mode) ?? .toggle
        self.trigger_key = try container.decodeIfPresent(HotkeyTriggerKey.self, forKey: .trigger_key) ?? .control
        self.double_tap_threshold_ms = try container.decodeIfPresent(Int.self, forKey: .double_tap_threshold_ms) ?? 400
        self.selected_audio_device_id = try container.decodeIfPresent(String.self, forKey: .selected_audio_device_id)
        self.personal_dictionary = try container.decodeIfPresent([String].self, forKey: .personal_dictionary) ?? ["LocalFlow", "Wispr", "Kubernetes", "GraphQL", "Ollama"]
        self.tags = try container.decodeIfPresent([String: String].self, forKey: .tags) ?? [":standup": "Today I am focusing on", ":email": "my.email@domain.com"]
        self.style_instructions = try container.decodeIfPresent(String.self, forKey: .style_instructions) ?? "Natural, direct, and conversational. Keep my personal tone, avoid unnecessary corporate filler, and format lists or numbers cleanly."
        self.app_styles = try container.decodeIfPresent([String: String]?.self, forKey: .app_styles) ?? [
            "com.tinyspeck.slackmacgap": "casual",
            "org.whispersystems.signal-desktop": "casual",
            "com.apple.MobileSMS": "casual",
            "com.apple.mail": "formal",
            "com.google.Chrome": "standard",
            "com.apple.Terminal": "code",
            "com.microsoft.VSCode": "code"
        ]
    }

    public func styleForApp(bundleId: String?) -> AppStyle {
        guard let bundleId = bundleId, let map = app_styles, let styleStr = map[bundleId] else {
            return .standard
        }
        return AppStyle(rawValue: styleStr) ?? .standard
    }

    public static var `default`: LocalFlowConfig {
        LocalFlowConfig()
    }
}

public final class ConfigManager {
    public static let shared = ConfigManager()

    public var config: LocalFlowConfig {
        didSet {
            DispatchQueue.main.async {
                self.onConfigUpdated?(self.config)
            }
        }
    }
    public var onConfigUpdated: ((LocalFlowConfig) -> Void)?

    private let configDirectory: URL
    private let configFileURL: URL
    private var fileWatcherSource: DispatchSourceFileSystemObject?
    private var isWritingInternally = false

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        configDirectory = home.appendingPathComponent(".config/localflow")
        configFileURL = configDirectory.appendingPathComponent("config.json")

        self.config = ConfigManager.loadOrCreateConfig(at: configFileURL, in: configDirectory)
        setupFileWatcher()
    }

    deinit {
        fileWatcherSource?.cancel()
    }

    private static func loadOrCreateConfig(at fileURL: URL, in dirURL: URL) -> LocalFlowConfig {
        let fm = FileManager.default
        if !fm.fileExists(atPath: dirURL.path) {
            try? fm.createDirectory(at: dirURL, withIntermediateDirectories: true)
        }

        if fm.fileExists(atPath: fileURL.path),
           let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(LocalFlowConfig.self, from: data) {
            return decoded
        }

        let defaultConfig = LocalFlowConfig.default
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let encoded = try? encoder.encode(defaultConfig) {
            try? encoded.write(to: fileURL)
        }

        let styleFileURL = dirURL.appendingPathComponent("my_style.txt")
        if !fm.fileExists(atPath: styleFileURL.path) {
            let sampleStyle = """
# Paste sample messages or emails you have sent here.
# LocalFlow will read this to learn your personal writing style, punctuation habits, and phrasing.

Hey team, quick update on the PR. Everything looks good to merge now.
Let's catch up on this tomorrow morning.
Thanks!
"""
            try? sampleStyle.write(to: styleFileURL, atomically: true, encoding: .utf8)
        }

        return defaultConfig
    }

    public func save() {
        isWritingInternally = true
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let encoded = try? encoder.encode(config) {
            try? encoded.write(to: configFileURL, options: .atomic)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.isWritingInternally = false
        }
    }

    public func reload() {
        guard !isWritingInternally else { return }
        if let data = try? Data(contentsOf: configFileURL),
           let decoded = try? JSONDecoder().decode(LocalFlowConfig.self, from: data) {
            self.config = decoded
            print("LocalFlow configuration reloaded.")
        }
    }

    private func setupFileWatcher() {
        let fd = open(configFileURL.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: DispatchQueue.global()
        )

        source.setEventHandler { [weak self] in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self?.reload()
            }
        }

        source.setCancelHandler {
            close(fd)
        }

        source.resume()
        self.fileWatcherSource = source
    }
}
