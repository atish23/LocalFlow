import AppKit

public enum HapticFeedbackPattern {
    case start
    case stop
    case success
    case error
}

public final class HapticFeedback {
    public static let shared = HapticFeedback()
    private let performer = NSHapticFeedbackManager.defaultPerformer

    private init() {}

    public func trigger(_ pattern: HapticFeedbackPattern) {
        guard ConfigManager.shared.config.haptic_feedback else { return }
        DispatchQueue.main.async {
            switch pattern {
            case .start:
                self.performer.perform(.alignment, performanceTime: .default)
            case .stop:
                self.performer.perform(.levelChange, performanceTime: .default)
            case .success:
                self.performer.perform(.generic, performanceTime: .default)
            case .error:
                self.performer.perform(.generic, performanceTime: .default)
            }
        }
    }
}
