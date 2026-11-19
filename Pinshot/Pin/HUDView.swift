import AppKit

/// HUD のゲージ（角丸の棒）
private final class HUDGaugeView: NSView {
    var progress: Double = 0 {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        let radius = bounds.height / 2
        NSColor.white.withAlphaComponent(0.25).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
        let filled = NSRect(x: 0, y: 0, width: bounds.width * CGFloat(min(max(progress, 0), 1)), height: bounds.height)
        NSColor.white.setFill()
        NSBezierPath(roundedRect: filled, xRadius: radius, yRadius: radius).fill()
    }
}

/// 拡大率・不透明度・「コピーしました」などを、画像の真ん中に少しだけ出す
final class HUDView: NSView {
    private let label = NSTextField(labelWithString: "")
    private let gauge = HUDGaugeView(frame: .zero)
    private var generation = 0
    /// 消え終わったとき（画像の外に出しているときに、その窓を片付けるのに使う）
    var onFadeOut: (() -> Void)?

    /// text と progress を出すときの大きさ
    static func size(for text: String, progress: Double?) -> NSSize {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.sizeToFit()
        let gaugeHeight: CGFloat = progress == nil ? 0 : 10
        let width = max(label.frame.width + 20, progress == nil ? 0 : 140)
        return NSSize(width: width, height: label.frame.height + 10 + gaugeHeight)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.7).cgColor
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .white
        label.alignment = .center
        addSubview(label)
        addSubview(gauge)
        alphaValue = 0
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // クリックは下の画像に通す
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// progress を渡すと、文字の下にゲージ（0〜1）も出す（透過度など）
    func show(_ text: String, progress: Double? = nil, in container: NSView) {
        label.stringValue = text
        label.sizeToFit()
        let gaugeHeight: CGFloat = progress == nil ? 0 : 10
        let width = max(label.frame.width + 20, progress == nil ? 0 : 140)
        let size = NSSize(width: width, height: label.frame.height + 10 + gaugeHeight)
        frame = NSRect(
            x: ((container.bounds.width - size.width) / 2).rounded(),
            y: ((container.bounds.height - size.height) / 2).rounded(),
            width: size.width,
            height: size.height
        )
        // HUD は flipped ではないので、ゲージを下、文字を上に置く
        label.frame.origin = NSPoint(x: (size.width - label.frame.width) / 2, y: 5 + gaugeHeight)
        gauge.isHidden = progress == nil
        if let progress {
            gauge.frame = NSRect(x: 12, y: 7, width: size.width - 24, height: 5)
            gauge.progress = progress
        }

        generation += 1
        let current = generation
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.1
            animator().alphaValue = 1
        }, completionHandler: nil)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(0.9))
            guard let self, self.generation == current else { return }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.3
                self.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.generation == current else { return }
                    self.onFadeOut?()
                }
            })
        }
    }
}
