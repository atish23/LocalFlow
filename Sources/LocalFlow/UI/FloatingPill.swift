import Cocoa

public enum DictationState {
    case listening
    case processing
    case done
}

public final class FloatingPillPanel: NSPanel {
    private let statusDot = NSView()
    private let statusLabel = NSTextField(labelWithString: "Listening...")
    private let transcriptLabel = NSTextField(labelWithString: "")

    public init() {
        let width: CGFloat = 340
        let height: CGFloat = 46
        let screenRect = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let rect = NSRect(
            x: screenRect.midX - (width / 2),
            y: screenRect.minY + 60,
            width: width,
            height: height
        )

        super.init(
            contentRect: rect,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )

        self.level = .floating
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.isMovableByWindowBackground = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        setupContentView()
    }

    public override var canBecomeKey: Bool { return false }
    public override var canBecomeMain: Bool { return false }

    private func setupContentView() {
        let visualEffect = NSVisualEffectView(frame: self.contentView!.bounds)
        visualEffect.autoresizingMask = [.width, .height]
        visualEffect.material = .hudWindow
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 23
        visualEffect.layer?.masksToBounds = true
        visualEffect.layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
        visualEffect.layer?.borderWidth = 1.0

        // Status indicator dot
        statusDot.frame = NSRect(x: 16, y: 17, width: 12, height: 12)
        statusDot.wantsLayer = true
        statusDot.layer?.cornerRadius = 6
        statusDot.layer?.backgroundColor = NSColor.systemRed.cgColor
        visualEffect.addSubview(statusDot)

        // Status text label
        statusLabel.frame = NSRect(x: 36, y: 13, width: 120, height: 20)
        statusLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        statusLabel.textColor = .white
        visualEffect.addSubview(statusLabel)

        // Live preview of spoken text
        transcriptLabel.frame = NSRect(x: 160, y: 13, width: 165, height: 20)
        transcriptLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        transcriptLabel.textColor = NSColor.white.withAlphaComponent(0.7)
        transcriptLabel.lineBreakMode = .byTruncatingHead
        visualEffect.addSubview(transcriptLabel)

        self.contentView = visualEffect
    }

    public func updateState(_ state: DictationState, partialText: String = "") {
        DispatchQueue.main.async {
            switch state {
            case .listening:
                self.statusDot.layer?.backgroundColor = NSColor.systemRed.cgColor
                self.statusLabel.stringValue = "Listening..."
                self.transcriptLabel.stringValue = partialText
            case .processing:
                self.statusDot.layer?.backgroundColor = NSColor.systemOrange.cgColor
                self.statusLabel.stringValue = "Polishing..."
                self.transcriptLabel.stringValue = partialText
            case .done:
                self.statusDot.layer?.backgroundColor = NSColor.systemGreen.cgColor
                self.statusLabel.stringValue = "Pasted!"
                self.transcriptLabel.stringValue = ""
            }
        }
    }

    public func showPill() {
        DispatchQueue.main.async {
            if let screen = NSScreen.main {
                let screenRect = screen.visibleFrame
                let width = self.frame.width
                self.setFrameOrigin(NSPoint(
                    x: screenRect.midX - (width / 2),
                    y: screenRect.minY + 60
                ))
            }
            self.alphaValue = 0.0
            self.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                self.animator().alphaValue = 1.0
            }
        }
    }

    public func hidePill(delay: Double = 0.0) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.18
                self.animator().alphaValue = 0.0
            }, completionHandler: {
                self.orderOut(nil)
            })
        }
    }
}
