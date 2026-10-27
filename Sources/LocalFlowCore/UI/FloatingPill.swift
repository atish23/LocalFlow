import Cocoa

public enum DictationState {
    case listening
    case processing
    case done
    case error
}

public final class AudioWaveformView: NSView {
    private var bars: [CALayer] = []
    private let barCount = 4
    private let barWidth: CGFloat = 3.0
    private let barSpacing: CGFloat = 3.0
    private let minHeight: CGFloat = 4.0
    private let maxHeight: CGFloat = 18.0

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.wantsLayer = true
        setupBars()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupBars() {
        let totalWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * barSpacing
        let startX = (bounds.width - totalWidth) / 2.0
        let centerY = bounds.height / 2.0

        for i in 0..<barCount {
            let bar = CALayer()
            let x = startX + CGFloat(i) * (barWidth + barSpacing)
            bar.frame = CGRect(x: x, y: centerY - (minHeight / 2.0), width: barWidth, height: minHeight)
            bar.cornerRadius = barWidth / 2.0
            bar.backgroundColor = NSColor.systemRed.cgColor
            layer?.addSublayer(bar)
            bars.append(bar)
        }
    }

    public func updateLevel(_ level: Float) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.08)
        let centerY = bounds.height / 2.0

        let multipliers: [Float] = [0.65, 1.0, 0.85, 0.55]

        for (i, bar) in bars.enumerated() {
            let mult = multipliers[i % multipliers.count]
            let scaledLevel = min(1.0, max(0.0, level * mult))
            let h = minHeight + CGFloat(scaledLevel) * (maxHeight - minHeight)
            bar.frame = CGRect(
                x: bar.frame.origin.x,
                y: centerY - (h / 2.0),
                width: barWidth,
                height: h
            )
        }
        CATransaction.commit()
    }

    public func setColor(_ color: NSColor) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.2)
        for bar in bars {
            bar.backgroundColor = color.cgColor
        }
        CATransaction.commit()
    }
}

public final class FloatingPillPanel: NSPanel {
    private let waveformView = AudioWaveformView(frame: NSRect(x: 14, y: 11, width: 24, height: 24))
    private let statusLabel = NSTextField(labelWithString: "Listening...")
    private let transcriptLabel = NSTextField(labelWithString: "")
    private var hideWorkItem: DispatchWorkItem?

    public init() {
        let width: CGFloat = 360
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

        // Live Audio Waveform View
        visualEffect.addSubview(waveformView)

        // Status text label
        statusLabel.frame = NSRect(x: 44, y: 13, width: 110, height: 20)
        statusLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        statusLabel.textColor = .white
        visualEffect.addSubview(statusLabel)

        // Live preview of spoken text
        transcriptLabel.frame = NSRect(x: 156, y: 13, width: 190, height: 20)
        transcriptLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        transcriptLabel.textColor = NSColor.white.withAlphaComponent(0.7)
        transcriptLabel.lineBreakMode = .byTruncatingHead
        visualEffect.addSubview(transcriptLabel)

        self.contentView = visualEffect
    }

    public func updateAudioLevel(_ level: Float) {
        DispatchQueue.main.async {
            self.waveformView.updateLevel(level)
        }
    }

    public func updateState(_ state: DictationState, partialText: String = "") {
        DispatchQueue.main.async {
            switch state {
            case .listening:
                self.waveformView.setColor(NSColor.systemRed)
                self.statusLabel.stringValue = "Listening..."
                self.transcriptLabel.stringValue = partialText
            case .processing:
                self.waveformView.setColor(NSColor.systemOrange)
                self.waveformView.updateLevel(0.4)
                self.statusLabel.stringValue = "Polishing..."
                self.transcriptLabel.stringValue = partialText
            case .done:
                self.waveformView.setColor(NSColor.systemGreen)
                self.waveformView.updateLevel(0.1)
                self.statusLabel.stringValue = "Pasted!"
                self.transcriptLabel.stringValue = ""
            case .error:
                self.waveformView.setColor(NSColor.systemRed)
                self.waveformView.updateLevel(0.0)
                self.statusLabel.stringValue = "Error"
                self.transcriptLabel.stringValue = partialText
            }
        }
    }

    public func showPill() {
        DispatchQueue.main.async {
            self.hideWorkItem?.cancel()
            self.hideWorkItem = nil

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
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.hideWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.18
                    self.animator().alphaValue = 0.0
                }, completionHandler: {
                    self.orderOut(nil)
                })
            }
            self.hideWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        }
    }
}
