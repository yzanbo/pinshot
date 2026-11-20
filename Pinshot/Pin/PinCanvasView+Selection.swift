import AppKit

extension PinCanvasView {
    // MARK: - 選択・色や大きさの反映

    func select(_ index: Int) {
        let annotation = annotations[index]
        selectedID = annotation.id
        // ツールバーの色・太さ・オプションを、選んだ書き込みに合わせる
        guard !annotation.isEffect else { return }
        state.color = annotation.color.withAlpha(1)
        state.opacity = Double(annotation.color.a)
        state.setLineWidth(annotation.lineWidth, for: annotation.tool)
        switch annotation.shape {
        case .text(let runs, _, let style, _):
            setFontSizeSilently(Annotation.maxFontSize(runs))
            state.textStyle = style
        case .counter(_, _, let radius, let style):
            state.counterSize = CounterSize.closest(toRadius: radius)
            state.counterStyle = style
        case .arrow(_, _, let style):
            state.arrowStyle = style
        case .rectangle(_, let style):
            state.rectangleStyle = style
        case .ellipse(_, let style):
            state.ellipseStyle = style
        case .textMark(_, let style):
            state.textMarkStyle = style
        default:
            break
        }
    }

    /// ツールバーで色・太さ・オプションを変えたとき、入力中の文字・選んでいる書き込みにも反映する
    func applyStyleToSelection(aspects: StyleAspects = .all) {
        if let field = textField {
            textColor = state.drawColor
            let familyChanged = textStyle.fontFamily != state.textStyle.fontFamily
            textStyle = state.textStyle
            if let editor = field.currentEditor() as? NSTextView, let storage = editor.textStorage {
                let whole = NSRange(location: 0, length: storage.length)
                storage.beginEditing()
                storage.addAttribute(.foregroundColor, value: textColor.nsColor, range: whole)
                if familyChanged {
                    // フォントを変えたら、部分ごとの大きさは保ったまま、全体のフォントを入れ替える
                    storage.enumerateAttribute(.font, in: whole) { value, range, _ in
                        let size = (value as? NSFont)?.pointSize ?? textFontSize * scaleFactor
                        storage.addAttribute(.font, value: Annotation.textFont(size: size, family: textStyle.fontFamily), range: range)
                    }
                }
                storage.endEditing()
                editor.typingAttributes = typingAttributes(size: textFontSize)
            }
            if familyChanged { resizeTextField(field) }
            return
        }
        let style = state.style
        let widthTool = state.optionsTool
        updateSelected { $0.restyled(with: style, aspects: aspects, lineWidthTool: widthTool) }
    }

    /// 選んでいる書き込みを transform で作り直す（変わったものだけ）。
    /// 続けて変えているあいだ（1 秒以内）は、最初の状態だけを「元に戻す」に残す（カラーパネルで色を動かしたときなど）
    private func updateSelected(_ transform: (Annotation) -> Annotation) {
        guard state.isEditing, !selection.isEmpty else { return }
        guard document.update(ids: selection, transform) else { return }
        historyChanged()
    }

    /// 文字の大きさを変えたとき、入力中の文字・選んでいる文字に反映する
    func fontSizeDidChange() {
        let size = state.fontSize
        // 表示を合わせただけのとき（入力カーソルの位置・選んだ文字・直し始め）は、文字を変えない
        if silentFontSizeChanges > 0 {
            silentFontSizeChanges -= 1
            return
        }
        if let field = textField {
            // 入力中は、選んでいる部分（なければ、ここから先に入力する文字）の大きさだけを変える
            textFontSize = size
            if let editor = field.currentEditor() as? NSTextView {
                let range = editor.selectedRange()
                if range.length > 0 {
                    editor.textStorage?.addAttribute(.font, value: inputFont(size: size), range: range)
                }
                editor.typingAttributes = typingAttributes(size: size)
            }
            resizeTextField(field)
            return
        }
        updateSelected { $0.withFontSize(size) }
    }

    // MARK: - すべて選択・複製・重なり順

    func selectAll() {
        guard !annotations.isEmpty else { return }
        state.tool = .select
        selection = annotations.map(\.id)
        needsDisplay = true
    }

    /// 選んでいる書き込みを、少し右下にずらして複製する（番号は続きの番号にする）
    func duplicateSelected() {
        let newIDs = document.duplicate(ids: selection, offset: CGVector(dx: 12, dy: 12))
        guard !newIDs.isEmpty else { return }
        selection = newIDs
        historyChanged()
        showHUD("複製しました")
    }

    /// 選んでいる書き込みを、1 つ前面（forward）か背面へ動かす
    func reorderSelected(forward: Bool) {
        guard document.reorder(ids: selection, forward: forward) else { return }
        historyChanged()
        showHUD(forward ? "前面へ" : "背面へ")
    }
}
