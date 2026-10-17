import Cocoa

public final class SoundFeedback {
    public static let shared = SoundFeedback()
    private let startSound = NSSound(named: "Tink")
    private let stopSound = NSSound(named: "Pop")

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
}
