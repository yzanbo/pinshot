import AppKit

// MARK: - 色のパネル

/// macOS のカラーパネルで、オリジナルの色を選ぶ
@MainActor
final class ColorPanelController: NSObject {
    static let shared = ColorPanelController()

    private weak var state: EditorState?
    /// このパネルを開いてから、最近使った色にもう入れたか（2 回目からは先頭を差し替える）
    private var addedInThisSession = false
    private weak var previousKeyWindow: NSWindow?
    private var closeObserver: Any?

    func open(for state: EditorState) {
        self.state = state
        addedInThisSession = false
        previousKeyWindow = NSApp.keyWindow
        if closeObserver == nil {
            // 閉じたら、ほかのアプリより前に残らないよう階層を戻し、画像のウィンドウにキー操作を戻す
            closeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: NSColorPanel.shared,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    NSColorPanel.shared.level = .normal
                    self?.previousKeyWindow?.makeKey()
                }
            }
        }
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.isContinuous = true
        panel.color = state.color.nsColor
        panel.setTarget(self)
        panel.setAction(#selector(colorDidChange(_:)))
        // 浮かせた画像やツールバーより前に出す
        panel.level = .popUpMenu
        NSApp.activate()
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    @objc private func colorDidChange(_ sender: NSColorPanel) {
        guard let state, let color = RGBAColor(nsColor: sender.color) else { return }
        state.color = color
        state.rememberCustomColor(color, replacingFirst: addedInThisSession)
        addedInThisSession = !RGBAColor.palette.contains(color)
    }
}

extension RGBAColor {
    /// メニューに出す、色の丸い見本
    func swatchImage(diameter: CGFloat) -> NSImage {
        let size = NSSize(width: diameter + 2, height: diameter + 2)
        let image = NSImage(size: size, flipped: false) { rect in
            let circle = NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1))
            self.nsColor.setFill()
            circle.fill()
            NSColor.black.withAlphaComponent(0.25).setStroke()
            circle.lineWidth = 1
            circle.stroke()
            return true
        }
        return image
    }
}
