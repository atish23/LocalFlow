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
            print("⚠️ LocalFlow does not have Accessibility permission! Requesting...")
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

        // 3. Pause briefly to ensure the target window is active, then simulate Cmd+V sequence
        DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + 0.15) {
            self.simulateCmdV()
            DispatchQueue.main.async {
                completion?()
            }
        }
    }

    private func simulateCmdV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let cmdKeyCode: CGKeyCode = 55 // kVK_Command
        let vKeyCode: CGKeyCode = 9    // kVK_ANSI_V

        guard let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: cmdKeyCode, keyDown: true),
              let vDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
              let vUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false),
              let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: cmdKeyCode, keyDown: false) else {
            print("Failed to create CGEvents for paste")
            return
        }

        cmdDown.flags = .maskCommand
        vDown.flags = .maskCommand
        vUp.flags = .maskCommand
        cmdUp.flags = []

        // Post exclusively to HID event tap so Cmd+V fires exactly once
        cmdDown.post(tap: .cghidEventTap)
        usleep(25_000)

        vDown.post(tap: .cghidEventTap)
        usleep(40_000)

        vUp.post(tap: .cghidEventTap)
        usleep(25_000)

        cmdUp.post(tap: .cghidEventTap)

        print("TextPaster: Single Cmd+V dispatched")
    }
}
