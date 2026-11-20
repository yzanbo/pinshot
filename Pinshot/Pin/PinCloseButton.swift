import AppKit

/// 浮かせた画像の左上の外側に出す、閉じるボタン（×）。
/// マウスを乗せると指のカーソルになり、乗せた・押したときは背景が濃くなる
final class PinCloseButton: NSView {
    var onClick: (() -> Void)?

    private var isHovering = false
    private var isPressed = false

    /// 押した・乗せたときの背景の濃さ
    private var backgroundAlpha: CGFloat { isPressed ? 0.95 : (isHovering ? 0.85 : 0.6) }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        toolTip = "閉じる（⌘W）：書き込みごと閉じる。メニューの「閉じた画像を戻す」で戻せる"
        setAccessibilityRole(.button)
        setAccessibilityLabel("閉じる")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: - マウス

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        resetTrackingArea([.mouseEnteredAndExited, .mouseMoved, .cursorUpdate])
    }

    // ほかのカーソル処理に上書きされないよう、マウスが動くたびに指のカーソルにし直す
    override func cursorUpdate(with event: NSEvent) { HoverRole.pressable.cursor.set() }
    override func mouseMoved(with event: NSEvent) { HoverRole.pressable.cursor.set() }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        HoverRole.pressable.cursor.set()
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        isPressed = false
        needsDisplay = true
        // ボタンの上で離したときだけ押したことにする
        if bounds.contains(convert(event.locationInWindow, from: nil)) {
            onClick?()
        }
    }

    // MARK: - 描画

    override func draw(_ dirtyRect: NSRect) {
        let circle = bounds.insetBy(dx: 1, dy: 1)
        NSColor.black.withAlphaComponent(backgroundAlpha).setFill()
        NSBezierPath(ovalIn: circle).fill()
        NSColor.white.withAlphaComponent(0.8).setStroke()
        let ring = NSBezierPath(ovalIn: circle.insetBy(dx: 0.5, dy: 0.5))
        ring.lineWidth = 1
        ring.stroke()

        // ×
        let inset = bounds.width * 0.33
        let cross = NSBezierPath()
        cross.move(to: NSPoint(x: bounds.minX + inset, y: bounds.minY + inset))
        cross.line(to: NSPoint(x: bounds.maxX - inset, y: bounds.maxY - inset))
        cross.move(to: NSPoint(x: bounds.maxX - inset, y: bounds.minY + inset))
        cross.line(to: NSPoint(x: bounds.minX + inset, y: bounds.maxY - inset))
        cross.lineWidth = 1.6
        cross.lineCapStyle = .round
        NSColor.white.setStroke()
        cross.stroke()
    }
}
