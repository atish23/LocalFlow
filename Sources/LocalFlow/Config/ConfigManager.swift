import Foundation

public struct LocalFlowConfig: Codable {
    public var llm_model: String
    public var headless: Bool
    public var sound_effects: Bool
    public var personal_dictionary: [String]
    public var tags: [String: String]
    public var style_instructions: String
    public var double_tap_threshold_ms: Int

    public static var `default`: LocalFlowConfig {
        LocalFlowConfig(
            llm_model: "qwen2.5-coder:1.5b",
            headless: false,
            sound_effects: true,
            personal_dictionary: [
                "LocalFlow",
                "Wispr",
                "Kubernetes",
                "GraphQL",
                "Ollama"
            ],
            tags: [
                ":standup": "Today I am focusing on",
                ":email": "my.email@domain.com"
            ],
            style_instructions: "Natural, direct, and conversational. Keep my personal tone, avoid unnecessary corporate filler, and format lists or numbers cleanly.",
            double_tap_threshold_ms: 400
        )
    }
}

public final class ConfigManager {
    public static let shared = ConfigManager()
    
    public var config: LocalFlowConfig
    public var onConfigUpdated: ((LocalFlowConfig) -> Void)?

    private let configDirectory: URL
    private let configFileURL: URL
    private var fileWatcherSource: DispatchSourceFileSystemObject?

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        configDirectory = home.appendingPathComponent(".config/localflow")
        configFileURL = configDirectory.appendingPathComponent("config.json")

        self.config = ConfigManager.loadOrCreateConfig(at: configFileURL, in: configDirectory)
        setupFileWatcher()
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

        // Create default config file
        let defaultConfig = LocalFlowConfig.default
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let encoded = try? encoder.encode(defaultConfig) {
            try? encoded.write(to: fileURL)
        }

        // Also create a sample my_style.txt if not present
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

    public func reload() {
        if let data = try? Data(contentsOf: configFileURL),
           let decoded = try? JSONDecoder().decode(LocalFlowConfig.self, from: data) {
            self.config = decoded
            print("LocalFlow configuration reloaded.")
            DispatchQueue.main.async {
                self.onConfigUpdated?(decoded)
            }
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
