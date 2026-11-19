import AppKit

/// 撮った画像を浮かせる、枠のない最前面のウィンドウ
final class PinPanel: OverlayPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect)
        isMovableByWindowBackground = false
        becomesKeyOnlyIfNeeded = false
        animationBehavior = .none
    }

    // 枠のないウィンドウは、既定ではキー入力を受けられないので許可する
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// 編集ツールバーを載せる、キー入力を奪わないウィンドウ
final class ToolbarPanel: OverlayPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect)
        animationBehavior = .none
    }

    // キー入力は画像のウィンドウに残したいので、こちらはキーにならない
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
