import AppKit
import SwiftUI

/// 前に出ていないウィンドウでも、1 回のクリックでボタンが押せるようにする
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

extension NSView {
    /// 自分のトラッキングエリアを作り直す（updateTrackingAreas から呼ぶ）。
    /// 見えている範囲の全体を、アプリが前に出ていなくても追う
    func resetTrackingArea(_ options: NSTrackingArea.Options) {
        for area in trackingAreas where area.owner === self {
            removeTrackingArea(area)
        }
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: options.union([.activeAlways, .inVisibleRect]),
            owner: self
        ))
    }
}
