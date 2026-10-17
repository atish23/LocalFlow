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

    private var lastControlPressTime: TimeInterval = 0
    private var doubleTapThreshold: TimeInterval {
        return Double(ConfigManager.shared.config.double_tap_threshold_ms) / 1000.0
    }

    private init() {}

    public func startMonitoring() {
        // 1. Global Monitor (when another application has focus)
        globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
        }

        globalKeyDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] _ in
            // Reset double-tap timer if any other key is pressed
            self?.lastControlPressTime = 0
        }

        // 2. Local Monitor (when LocalFlow itself is active)
        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
            return event
        }

        localKeyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.lastControlPressTime = 0
            return event
        }
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        // Control key codes: 59 (Left Control), 62 (Right Control)
        guard event.keyCode == 59 || event.keyCode == 62 else { return }

        let isControlPressed = event.modifierFlags.contains(.control)
        guard isControlPressed else { return } // Only react on key-down

        let now = Date().timeIntervalSince1970

        if isRecording {
            // Single tap on Control while recording ends dictation
            lastControlPressTime = 0
            DispatchQueue.main.async { [weak self] in
                self?.onStopRequested?()
            }
        } else {
            // Check for double tap to start
            if (now - lastControlPressTime) <= doubleTapThreshold {
                lastControlPressTime = 0
                DispatchQueue.main.async { [weak self] in
                    self?.onStartRequested?()
                }
            } else {
                lastControlPressTime = now
            }
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
