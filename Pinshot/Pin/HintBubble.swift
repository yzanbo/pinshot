import AppKit

/// ツールバーのボタンにマウスを乗せたときに出す、説明のポップアップ
@MainActor
final class HintBubble {
    private let panel: NSPanel
    private let label = NSTextField(wrappingLabelWithString: "")
    private let maxTextWidth: CGFloat = 340
    private let padding = NSSize(width: 10, height: 6)

    var isShown: Bool { panel.isVisible }

    init() {
        panel = OverlayPanel(contentRect: .zero, level: .popUpMenu, defer: true)
        panel.ignoresMouseEvents = true

        let background = NSView()
        background.wantsLayer = true
        background.layer?.cornerRadius = 7
        background.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.85).cgColor
        label.font = .systemFont(ofSize: 11)
        label.textColor = .white
        label.maximumNumberOfLines = 3
        background.addSubview(label)
        panel.contentView = background
    }

    /// anchor（マウスの位置）の横あたりで、avoiding（ツールバー）の上に出す。上に入らなければ下
    func show(_ text: String, at anchor: NSPoint, avoiding avoid: NSRect) {
        label.stringValue = text
        label.preferredMaxLayoutWidth = maxTextWidth
        let textSize = label.sizeThatFits(NSSize(width: maxTextWidth, height: 200))
        let size = NSSize(width: ceil(textSize.width) + padding.width * 2, height: ceil(textSize.height) + padding.height * 2)
        label.frame = NSRect(x: padding.width, y: padding.height, width: ceil(textSize.width), height: ceil(textSize.height))

        let screen = ScreenGeometry.screen(containing: anchor)
        let visible = screen?.visibleFrame ?? NSRect(origin: .zero, size: size)
        var origin = NSPoint(x: anchor.x - size.width / 2, y: avoid.maxY + 6)
        if origin.y + size.height > visible.maxY {
            origin.y = avoid.minY - size.height - 6
        }
        origin.x = min(max(origin.x, visible.minX + 4), visible.maxX - size.width - 4)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }
}
