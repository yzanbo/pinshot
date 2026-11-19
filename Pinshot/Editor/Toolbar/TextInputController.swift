import AppKit
import SwiftUI

/// マウスの位置に出す、1 行の小さな入力欄（文字の大きさ・スタイルの名前などに使う）。
/// return で決定、esc か外をクリックでやめる。onCommit が false を返したら閉じずに入力し直してもらう
@MainActor
final class TextInputController: NSObject, NSTextFieldDelegate, NSWindowDelegate {
    static let shared = TextInputController()

    private var panel: NSPanel?
    private var field: NSTextField?
    private var onCommit: ((String) -> Bool)?
    private weak var previousKeyWindow: NSWindow?

    func show(
        initial: String,
        width: CGFloat,
        placeholder: String = "",
        unit: String? = nil,
        monospaced: Bool = false,
        onCommit: @escaping (String) -> Bool
    ) {
        close()
        self.onCommit = onCommit
        previousKeyWindow = NSApp.keyWindow

        let size = NSSize(width: width, height: 30)
        let mouse = NSEvent.mouseLocation
        var origin = NSPoint(x: mouse.x - size.width / 2, y: mouse.y - size.height - 6)
        if let visible = ScreenGeometry.screen(containing: mouse)?.visibleFrame {
            if origin.y < visible.minY { origin.y = mouse.y + 10 }
            origin.x = min(max(origin.x, visible.minX + 4), visible.maxX - size.width - 4)
        }
        let panel = KeyableOverlayPanel(contentRect: NSRect(origin: origin, size: size), level: .popUpMenu)
        panel.delegate = self

        let background = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        background.material = .popover
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 8

        let unitWidth: CGFloat = unit == nil ? 0 : 28
        let field = NSTextField(string: initial)
        field.font = monospaced
            ? .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
            : .systemFont(ofSize: 13)
        field.alignment = monospaced ? .center : .left
        field.placeholderString = placeholder
        field.bezelStyle = .roundedBezel
        field.delegate = self
        field.frame = NSRect(x: 6, y: 4, width: size.width - 12 - unitWidth, height: 22)
        background.addSubview(field)

        if let unit {
            let label = NSTextField(labelWithString: unit)
            label.font = .systemFont(ofSize: 11)
            label.textColor = .secondaryLabelColor
            label.frame = NSRect(x: size.width - unitWidth, y: 8, width: unitWidth - 4, height: 14)
            background.addSubview(label)
        }

        panel.contentView = background
        self.panel = panel
        self.field = field
        // アプリ全体は前に出さず、入力欄だけをキーにする
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            commit()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            close()
            return true
        default:
            return false
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        // 外をクリックしたら、決めずに閉じる
        close(restoreKey: false)
    }

    private func commit() {
        guard let text = field?.stringValue, let onCommit else { return close() }
        if onCommit(text) {
            close()
        } else {
            NSSound.beep()
        }
    }

    private func close(restoreKey: Bool = true) {
        guard let panel else { return }
        self.panel = nil
        field = nil
        onCommit = nil
        panel.delegate = nil
        panel.orderOut(nil)
        if restoreKey {
            // 入力中の文字があれば、そのまま続けられるよう元のウィンドウに戻す
            previousKeyWindow?.makeKey()
        }
    }
}

/// 文字の大きさを手で入力する（全角の数字でも受け付ける）
@MainActor
enum FontSizeInputController {
    static func show(current: CGFloat, onCommit: @escaping (CGFloat) -> Void) {
        TextInputController.shared.show(initial: FontSizes.format(current), width: 84, unit: "pt", monospaced: true) { text in
            let normalized = (text.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? text)
                .trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: "pt", with: "")
            guard let value = Double(normalized) else { return false }
            let size = min(max(CGFloat(value), FontSizes.range.lowerBound), FontSizes.range.upperBound)
            onCommit((size * 2).rounded() / 2)
            return true
        }
    }
}
