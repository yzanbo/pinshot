import AppKit

extension PinCanvasView {
    // MARK: - キー

    override func keyDown(with event: NSEvent) {
        let shift = event.modifierFlags.contains(.shift)
        switch Int(event.keyCode) {
        case 53: // esc: 選択を外す → 編集を終える
            if !selection.isEmpty {
                selection = []
                needsDisplay = true
            } else if state.isEditing {
                controller?.setEditing(false)
            }
            return
        case 51, 117: // delete / forward delete
            if state.isEditing, deleteSelected() { return }
        case 49: // space: 押している間はドラッグで画像を動かす
            if state.isEditing {
                if !event.isARepeat {
                    isSpaceHeld = true
                    refreshCursor()
                }
                return
            }
        case 123, 124, 125, 126: // 矢印キー
            let step: CGFloat = shift ? 10 : 1
            let (dx, dy): (CGFloat, CGFloat) = switch Int(event.keyCode) {
            case 123: (-step, 0)
            case 124: (step, 0)
            case 125: (0, step) // 下（画像の座標は下が +）
            default: (0, -step)
            }
            if state.isEditing, !selection.isEmpty {
                // 選んでいる書き込みを動かす
                document.translate(ids: selection, by: CGVector(dx: dx, dy: dy))
                historyChanged()
            } else {
                // 画像（ウィンドウ）を動かす（画面の座標は上が +）
                controller?.moveBy(dx: dx, dy: -dy)
            }
            return
        default:
            break
        }

        let modifiers = event.modifierFlags.intersection([.command, .control, .option])
        if state.isEditing, modifiers.isEmpty, let key = event.charactersIgnoringModifiers?.lowercased() {
            // 1〜6 で色
            if let digit = Int(key), (1...RGBAColor.palette.count).contains(digit) {
                state.color = RGBAColor.palette[digit - 1]
                return
            }
            // [ ] で太さ（文字なら文字の大きさ）
            if key == "[" || key == "]" {
                state.stepLineWidth(up: key == "]")
                return
            }
            if let tool = Tool.allCases.first(where: { $0.shortcut == key }) {
                state.tool = tool
                return
            }
        }
        super.keyDown(with: event)
    }

    override func keyUp(with event: NSEvent) {
        if event.keyCode == 49, isSpaceHeld {
            isSpaceHeld = false
            refreshCursor()
            return
        }
        super.keyUp(with: event)
    }

    /// 押している状態のキーを、押していない状態に戻す。
    /// space を押したまま、ほかのウィンドウ・アプリに移ると keyUp が届かないため
    func releaseHeldKeys() {
        guard isSpaceHeld else { return }
        isSpaceHeld = false
        refreshCursor()
    }

    override func resignFirstResponder() -> Bool {
        releaseHeldKeys()
        return super.resignFirstResponder()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.window === window, event.modifierFlags.contains(.command) else {
            return super.performKeyEquivalent(with: event)
        }
        let key = event.charactersIgnoringModifiers?.lowercased()

        // 文字の大きさは、入力中でも ⌘+ / ⌘- で変えられる（文字を扱っているときだけ）
        if state.isEditing, state.optionsTool == .text {
            switch key {
            case "=", "+", ";":
                state.stepFontSize(up: true)
                return true
            case "-":
                state.stepFontSize(up: false)
                return true
            default:
                break
            }
        }

        guard textField == nil else { return super.performKeyEquivalent(with: event) }
        let shift = event.modifierFlags.contains(.shift)
        switch key {
        case "z":
            if shift { redo() } else { undo() }
        case "c":
            if shift { controller?.copyAndClose() } else { controller?.copyToPasteboard() }
        case "s":
            controller?.save()
        case "w":
            controller?.close()
        case "e":
            controller?.toggleEditing()
        case "0":
            controller?.resetZoom()
        case "a" where state.isEditing:
            selectAll()
        case "d" where state.isEditing:
            duplicateSelected()
        case "]" where state.isEditing:
            reorderSelected(forward: true)
        case "[" where state.isEditing:
            reorderSelected(forward: false)
        default:
            return super.performKeyEquivalent(with: event)
        }
        return true
    }
}
