import AppKit

/// 画像の上に置く押せるボタンの土台（マウスを乗せると指のカーソル・押した見た目）
class PinButtonView: NSView {
    var onClick: (() -> Void)?
    /// マウスを乗せた（true）・離した（false）とき
    var onHoverChange: ((Bool) -> Void)?

    fileprivate(set) var isHovering = false
    fileprivate(set) var isPressed = false

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        resetTrackingArea([.mouseEnteredAndExited, .mouseMoved, .cursorUpdate])
    }

    // 下の画像もカーソルを変えようとするので、マウスが動くたびに指のカーソルにし直す
    override func cursorUpdate(with event: NSEvent) { HoverRole.pressable.cursor.set() }
    override func mouseMoved(with event: NSEvent) { HoverRole.pressable.cursor.set() }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        HoverRole.pressable.cursor.set()
        needsDisplay = true
        onHoverChange?(true)
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        needsDisplay = true
        onHoverChange?(false)
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

    /// 押した・乗せたときの背景の濃さ
    var backgroundAlpha: CGFloat { isPressed ? 0.95 : (isHovering ? 0.85 : 0.6) }
}

/// 浮かせた画像の左上に出す、閉じるボタン（×）
final class PinCloseButton: PinButtonView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        toolTip = "画像を捨てる（⌘W）：メニューの「閉じた画像を戻す」で戻せる"
        setAccessibilityRole(.button)
        setAccessibilityLabel("画像を捨てる")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func draw(_ dirtyRect: NSRect) {
        let circle = bounds.insetBy(dx: 1, dy: 1)
        NSColor.black.withAlphaComponent(backgroundAlpha).setFill()
        NSBezierPath(ovalIn: circle).fill()
        NSColor.white.withAlphaComponent(0.8).setStroke()
        let ring = NSBezierPath(ovalIn: circle.insetBy(dx: 0.5, dy: 0.5))
        ring.lineWidth = 1
        ring.stroke()

        // ゴミ箱（編集モードのツールバー・操作バーの捨てるボタンと同じ絵）
        let config = NSImage.SymbolConfiguration(pointSize: bounds.width * 0.48, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
        guard let symbol = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return }
        let size = symbol.size
        symbol.draw(in: NSRect(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2,
            width: size.width,
            height: size.height
        ))
    }
}
