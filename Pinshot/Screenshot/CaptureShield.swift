import AppKit

/// ショートカットを押した瞬間に、すべての画面に透明なウィンドウ（範囲を選ぶ画面になるもの）をかぶせる。
///
/// - 画面を撮っている間に押したクリックが、下のアプリに届かないようにする
/// - 画面を撮り終えたら、このウィンドウをそのまま範囲を選ぶ画面として使う（handOver）。
///   準備ができた瞬間に新しいウィンドウをマウスの下に出すと、macOS がカーソルを一瞬矢印に戻すため
/// - カーソルは変えない。まだ範囲を選べないうちに ✙ にすると、準備ができた瞬間に一度矢印へ戻されて、ちらついて見える
/// - 撮る画像に写らないよう、撮るときはこのウィンドウを除く（windowIDs）
@MainActor
final class CaptureShield {
    private var windows: [SelectionWindow] = []

    /// かぶせているウィンドウの番号（撮るときに除く）
    var windowIDs: Set<CGWindowID> {
        Set(windows.map { CGWindowID($0.windowNumber) })
    }

    func show() {
        guard windows.isEmpty else { return }
        for screen in NSScreen.screens {
            let window = SelectionWindow(screen: screen)
            // 中身が入るまでは、ほぼ透明にして、透明な所でもマウスを受けるようにする（完全に透明だと、マウスが下へ抜けてしまう）
            window.backgroundColor = NSColor.black.withAlphaComponent(0.001)
            window.ignoresMouseEvents = false
            window.contentView = ShieldView(frame: NSRect(origin: .zero, size: screen.frame.size))
            window.orderFrontRegardless()
            windows.append(window)
        }
    }

    /// かぶせているウィンドウを、範囲を選ぶ画面に渡す（渡したものは、ここでは閉じない）
    func handOver() -> [SelectionWindow] {
        let handed = windows
        windows.removeAll()
        return handed
    }

    /// 渡さなかったウィンドウを閉じる（撮るのをやめたとき・失敗したとき）
    func close() {
        for window in windows {
            window.orderOut(nil)
        }
        windows.removeAll()
    }
}

/// 中身が入るまでのウィンドウの中身（クリックを受けて、何もしない）
private final class ShieldView: NSView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {}
}
