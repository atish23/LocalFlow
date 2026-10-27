import Cocoa
import Carbon

public final class TextPaster {
    public static let shared = TextPaster()

    private init() {}

    public static func isAccessibilityTrusted() -> Bool {
        return AXIsProcessTrusted()
    }

    public static func requestAccessibilityPermission() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options)
    }

    public func paste(text: String, targetApp: NSRunningApplication? = nil, completion: (() -> Void)? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            completion?()
            return
        }

        let isTrusted = AXIsProcessTrusted()
        print("TextPaster: AXIsProcessTrusted = \(isTrusted)")
        if !isTrusted {
            print("Warning: LocalFlow does not have Accessibility permission. Requesting...")
            Self.requestAccessibilityPermission()
        }

        // 1. Put polished text onto the pasteboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(trimmed, forType: .string)

        // 2. Reactivate target application if specified
        if let app = targetApp, app.bundleIdentifier != Bundle.main.bundleIdentifier {
            app.activate(options: .activateIgnoringOtherApps)
        }

        // 3. Pause 220ms to ensure target window (e.g. Electron/Chromium/Terminal) has active focus before Cmd+V
        DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + 0.22) {
            self.simulateCmdV()
            HapticFeedback.shared.trigger(.success)
            DispatchQueue.main.async {
                completion?()
            }
        }
    }

    private func simulateCmdV() {
        let source = CGEventSource(stateID: .hidSystemState)
        let cmdKeyCode: CGKeyCode = 55 // kVK_Command
        let vKeyCode: CGKeyCode = 9    // kVK_ANSI_V
        let ctrlKeyCode: CGKeyCode = 59 // kVK_Control

        // Release any lingering Control modifier state from the hotkey tap
        if let ctrlUp = CGEvent(keyboardEventSource: source, virtualKey: ctrlKeyCode, keyDown: false) {
            ctrlUp.flags = []
            ctrlUp.post(tap: .cghidEventTap)
            usleep(15_000)
        }

        guard let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: cmdKeyCode, keyDown: true),
              let vDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
              let vUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false),
              let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: cmdKeyCode, keyDown: false) else {
            print("Failed to create CGEvents for paste")
            return
        }

        cmdDown.flags = [.maskCommand]
        vDown.flags = [.maskCommand]
        vUp.flags = [.maskCommand]
        cmdUp.flags = []

        // Post exclusively to HID event tap so Cmd+V fires cleanly
        cmdDown.post(tap: .cghidEventTap)
        usleep(30_000)

        vDown.post(tap: .cghidEventTap)
        usleep(45_000)

        vUp.post(tap: .cghidEventTap)
        usleep(30_000)

        cmdUp.post(tap: .cghidEventTap)

        print("TextPaster: Clean Cmd+V dispatched")
    }
}
