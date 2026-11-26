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

extension View {
    /// 角の丸い枠に入れる（薄い塗りと細い線。文字の欄・画像の見本などで同じ見た目にする）
    func framedBox(cornerRadius: CGFloat = 8, fill: Color = Color.primary.opacity(0.05)) -> some View {
        background(RoundedRectangle(cornerRadius: cornerRadius).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(Color.primary.opacity(0.12)))
    }
}

/// ドラッグすると、置いたウィンドウごと動かせる所（SwiftUI の部品の上では、ウィンドウの背景のドラッグで動かす設定が効かないため）。
/// 乗せると手のカーソル、動かしている間はつかんだ手にする
struct WindowDragArea: NSViewRepresentable {
    /// 右クリックで出すメニュー（nil なら出さない）
    var menu: (@MainActor () -> NSMenu?)?

    func makeNSView(context: Context) -> NSView {
        let view = DragView()
        view.makeMenu = menu
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? DragView)?.makeMenu = menu
    }

    private final class DragView: NSView {
        var makeMenu: (@MainActor () -> NSMenu?)?

        // 前に出ていない窓でも、1 回のドラッグで動かせるようにする
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        // 右クリック（control + クリック）で出すメニュー。NSView の rightMouseDown がこれを開く
        override func menu(for event: NSEvent) -> NSMenu? {
            MainActor.assumeIsolated { makeMenu?() }
        }

        override func mouseDown(with event: NSEvent) {
            HoverRole.movable.draggingCursor.set()
            window?.performDrag(with: event)
            HoverRole.movable.cursor.set()
        }
    }
}
