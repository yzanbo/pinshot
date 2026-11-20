import AppKit

/// 撮っている・録画している範囲の外側に出す点線の枠（スクロールキャプチャはアクセントカラー、録画は赤）。
/// 範囲の内側には描かないので、撮る画像・録画には写らない。クリックは下に通す
enum CaptureOutline {
    static func show(around rect: NSRect, color: NSColor) -> NSWindow {
        let frame = rect.insetBy(dx: -4, dy: -4)
        let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        window.isReleasedWhenClosed = false
        let view = OutlineView(frame: NSRect(origin: .zero, size: frame.size))
        view.color = color
        window.contentView = view
        window.orderFrontRegardless()
        return window
    }

    private final class OutlineView: NSView {
        var color: NSColor = .controlAccentColor

        override func draw(_ dirtyRect: NSRect) {
            let path = NSBezierPath(rect: bounds.insetBy(dx: 1.5, dy: 1.5))
            path.lineWidth = 3
            path.setLineDash([8, 5], count: 2, phase: 0)
            color.setStroke()
            path.stroke()
        }
    }
}
