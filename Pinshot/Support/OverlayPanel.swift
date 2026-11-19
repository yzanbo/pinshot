import AppKit

/// 枠のない、透明な背景のパネル。クリックしても、いま使っているアプリから前面を奪わない。
/// すべてのデスクトップ（Spaces）と、フルスクリーンのアプリの上に出て、アプリが前に出ていなくても隠れない。
///
/// 浮かせた画像・ツールバー・説明のポップアップ・入力欄など、画面に重ねて出すものの土台にする
class OverlayPanel: NSPanel {
    init(contentRect: NSRect, level: NSWindow.Level = .floating, hasShadow: Bool = true, defer flag: Bool = false) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: flag
        )
        self.level = level
        self.hasShadow = hasShadow
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
    }
}

/// キー入力を受けられる OverlayPanel（アプリを前に出さずに、入力欄・esc などのキーを受ける）
final class KeyableOverlayPanel: OverlayPanel {
    override var canBecomeKey: Bool { true }
}
