import AppKit

/// タイマーの残り秒数を、画面の真ん中に大きく出す
@MainActor
enum CountdownPanel {
    static func run(seconds: Int, on screen: NSScreen?) async {
        let size = NSSize(width: 120, height: 120)
        let screenFrame = (screen ?? NSScreen.main)?.frame ?? .zero
        let panel = OverlayPanel(
            contentRect: NSRect(
                x: screenFrame.midX - size.width / 2,
                y: screenFrame.midY - size.height / 2,
                width: size.width,
                height: size.height
            ),
            level: .screenSaver
        )
        panel.ignoresMouseEvents = true

        let background = NSView(frame: NSRect(origin: .zero, size: size))
        background.wantsLayer = true
        background.layer?.cornerRadius = 24
        background.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.65).cgColor
        let label = NSTextField(labelWithString: "")
        label.font = .monospacedDigitSystemFont(ofSize: 56, weight: .semibold)
        label.textColor = .white
        label.alignment = .center
        label.frame = NSRect(x: 0, y: (size.height - 68) / 2, width: size.width, height: 68)
        background.addSubview(label)
        panel.contentView = background
        panel.orderFrontRegardless()

        for remaining in stride(from: seconds, to: 0, by: -1) {
            label.stringValue = "\(remaining)"
            try? await Task.sleep(for: .seconds(1))
        }
        panel.orderOut(nil)
        // 消えたあとの画面が撮れるよう、少し待つ
        try? await Task.sleep(for: .milliseconds(150))
    }
}
