import Cocoa

public final class SoundFeedback {
    public static let shared = SoundFeedback()
    private let startSound = NSSound(named: "Tink")
    private let stopSound = NSSound(named: "Pop")
    private let errorSound = NSSound(named: "Basso")
    private let successSound = NSSound(named: "Ping")

    private init() {}

    public func playStart() {
        guard ConfigManager.shared.config.sound_effects else { return }
        DispatchQueue.main.async {
            self.startSound?.play()
        }
    }

    public func playStop() {
        guard ConfigManager.shared.config.sound_effects else { return }
        DispatchQueue.main.async {
            self.stopSound?.play()
        }
    }

    public func playError() {
        guard ConfigManager.shared.config.sound_effects else { return }
        DispatchQueue.main.async {
            self.errorSound?.play()
        }
    }

    public func playSuccess() {
        guard ConfigManager.shared.config.sound_effects else { return }
        DispatchQueue.main.async {
            self.successSound?.play()
        }
    }
}
