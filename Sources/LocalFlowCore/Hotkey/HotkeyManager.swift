import Cocoa
import Carbon

public final class HotkeyManager {
    public static let shared = HotkeyManager()

    private var globalFlagsMonitor: Any?
    private var globalKeyDownMonitor: Any?
    private var localFlagsMonitor: Any?
    private var localKeyDownMonitor: Any?

    public var isRecording = false
    public var onStartRequested: (() -> Void)?
    public var onStopRequested: (() -> Void)?

    private var lastPressTime: TimeInterval = 0
    private var isKeyDownActive = false

    private init() {}

    deinit {
        stopMonitoring()
    }

    public func startMonitoring() {
        stopMonitoring()

        // 1. Global Monitor (when another application has focus)
        globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
        }

        globalKeyDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] _ in
            self?.lastPressTime = 0
        }

        // 2. Local Monitor (when LocalFlow itself is active)
        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
            return event
        }

        localKeyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.lastPressTime = 0
            return event
        }
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        let config = ConfigManager.shared.config
        let targetKey = config.trigger_key

        guard matchesTriggerKey(event: event, key: targetKey) else { return }

        let isModifierActive = checkModifierActive(event: event, key: targetKey)
        let mode = config.hotkey_mode
        let now = Date().timeIntervalSince1970
        let threshold = Double(config.double_tap_threshold_ms) / 1000.0

        switch mode {
        case .pushToTalk:
            // Hold-to-Talk mode: start on press down, stop on release
            if isModifierActive {
                if !isKeyDownActive && !isRecording {
                    isKeyDownActive = true
                    DispatchQueue.main.async { [weak self] in
                        self?.onStartRequested?()
                    }
                }
            } else {
                if isKeyDownActive || isRecording {
                    isKeyDownActive = false
                    DispatchQueue.main.async { [weak self] in
                        self?.onStopRequested?()
                    }
                }
            }

        case .toggle:
            // Double-Tap toggle mode: double tap starts, single tap stops
            guard isModifierActive else { return } // Only react on key-down

            if isRecording {
                // Single tap while recording ends dictation
                lastPressTime = 0
                DispatchQueue.main.async { [weak self] in
                    self?.onStopRequested?()
                }
            } else {
                if (now - lastPressTime) <= threshold {
                    lastPressTime = 0
                    DispatchQueue.main.async { [weak self] in
                        self?.onStartRequested?()
                    }
                } else {
                    lastPressTime = now
                }
            }
        }
    }

    private func matchesTriggerKey(event: NSEvent, key: HotkeyTriggerKey) -> Bool {
        let code = event.keyCode
        switch key {
        case .control:
            // Left Control (59), Right Control (62)
            return code == 59 || code == 62
        case .option:
            // Left Option (58), Right Option (61)
            return code == 58 || code == 61
        case .command:
            // Left Command (55), Right Command (54)
            return code == 55 || code == 54
        case .shift:
            // Left Shift (56), Right Shift (60)
            return code == 56 || code == 60
        case .function:
            // Function / Globe (63)
            return code == 63
        }
    }

    private func checkModifierActive(event: NSEvent, key: HotkeyTriggerKey) -> Bool {
        let flags = event.modifierFlags
        switch key {
        case .control:
            return flags.contains(.control)
        case .option:
            return flags.contains(.option)
        case .command:
            return flags.contains(.command)
        case .shift:
            return flags.contains(.shift)
        case .function:
            return flags.contains(.function)
        }
    }

    public func stopMonitoring() {
        if let monitor = globalFlagsMonitor {
            NSEvent.removeMonitor(monitor)
            globalFlagsMonitor = nil
        }
        if let monitor = globalKeyDownMonitor {
            NSEvent.removeMonitor(monitor)
            globalKeyDownMonitor = nil
        }
        if let monitor = localFlagsMonitor {
            NSEvent.removeMonitor(monitor)
            localFlagsMonitor = nil
        }
        if let monitor = localKeyDownMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyDownMonitor = nil
        }
    }
}
