import AppKit

extension PinCanvasView {
    // MARK: - 文字の入力

    func beginTextInput(at point: CGPoint, runs: [TextRun], color: RGBAColor, style: TextStyle) {
        textOrigin = point
        textColor = color
        textStyle = style
        textFontSize = state.fontSize
        textCancelled = false
        state.isEditingText = true

        let field = NSTextField(string: "")
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        // 1 つの文字の中で、部分ごとに大きさを変えられるようにする
        field.allowsEditingTextAttributes = true
        field.font = Annotation.textFont(size: textFontSize * scaleFactor)
        field.textColor = color.nsColor
        field.placeholderString = "文字を入力"
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.delegate = self
        if !runs.isEmpty {
            field.attributedStringValue = Annotation.attributedText(runs, color: color.nsColor, scale: scaleFactor)
        }
        let origin = viewRect(CGRect(origin: point, size: .zero)).origin
        // テキストフィールドは文字の左に約 2pt の余白があるので、そのぶん左にずらす
        field.frame.origin = NSPoint(x: origin.x - 2, y: origin.y)

        addSubview(field, positioned: .below, relativeTo: closeButton)
        textField = field
        updateSelectionBar()
        resizeTextField(field)
        window?.makeFirstResponder(field)
        if let editor = field.currentEditor() as? NSTextView {
            if runs.isEmpty {
                editor.typingAttributes = typingAttributes(size: textFontSize)
            } else {
                editor.selectAll(nil)
            }
            // 入力カーソルが動いたら、ツールバーの文字の大きさをその位置の大きさにする
            selectionObserver = NotificationCenter.default.addObserver(
                forName: NSTextView.didChangeSelectionNotification,
                object: editor,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.syncFontSizeWithCursor() }
            }
            syncFontSizeWithCursor()
        }
    }

    /// 入力カーソルの位置の文字の大きさ（範囲を選んでいるときは、その中でいちばん大きい大きさ）を、ツールバーに出す
    private func syncFontSizeWithCursor() {
        guard let field = textField, let editor = field.currentEditor() as? NSTextView else { return }
        let range = editor.selectedRange()
        var pixelSize: CGFloat?
        if range.length > 0, let storage = editor.textStorage {
            storage.enumerateAttribute(.font, in: range) { value, _, _ in
                if let font = value as? NSFont { pixelSize = max(pixelSize ?? 0, font.pointSize) }
            }
        } else {
            pixelSize = (editor.typingAttributes[.font] as? NSFont)?.pointSize
        }
        guard let pixelSize else { return }
        let size = ((pixelSize / max(scaleFactor, 0.01)) * 2).rounded() / 2
        textFontSize = size
        setFontSizeSilently(size)
    }

    /// 文字は変えずに、ツールバーの文字の大きさの表示だけを合わせる
    func setFontSizeSilently(_ size: CGFloat) {
        guard abs(size - state.fontSize) > 0.01 else { return }
        silentFontSizeChanges += 1
        state.fontSize = size
    }

    func typingAttributes(size: CGFloat) -> [NSAttributedString.Key: Any] {
        [.font: Annotation.textFont(size: size * scaleFactor), .foregroundColor: textColor.nsColor]
    }

    /// 入力中の文字に合わせて、テキストフィールドの大きさを変える
    func resizeTextField(_ field: NSTextField) {
        let content: NSAttributedString
        if let editor = field.currentEditor() as? NSTextView {
            content = editor.attributedString()
        } else {
            content = field.attributedStringValue
        }
        let typingFont = Annotation.textFont(size: textFontSize * scaleFactor)
        var size = content.size()
        size.height = max(size.height, NSLayoutManager().defaultLineHeight(for: typingFont))
        // 空のときは、案内の文字が入る幅にする
        let minWidth = content.length == 0
            ? ("文字を入力" as NSString).size(withAttributes: [.font: typingFont]).width
            : 20
        field.frame.size = NSSize(width: ceil(max(size.width, minWidth)) + 14, height: ceil(size.height) + 4)
    }

    /// 書いた文字を直す
    func beginReEdit(at index: Int) {
        guard case .text(let runs, let origin, let style) = annotations[index].shape else { return }
        let original = annotations[index]
        reEditSnapshot = snapshot
        reEditIndex = index
        reEditOriginal = original
        annotations.remove(at: index)
        selectedID = nil
        setFontSizeSilently(Annotation.maxFontSize(runs))
        state.color = original.color.withAlpha(1)
        state.opacity = Double(original.color.a)
        state.textStyle = style
        needsDisplay = true
        beginTextInput(at: origin, runs: runs, color: original.color, style: style)
    }

    /// 入力中の文字があれば確定する
    func commitPendingText() {
        guard textField != nil else { return }
        window?.makeFirstResponder(self)
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let field = textField else { return }
        resizeTextField(field)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            window?.makeFirstResponder(self)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            textCancelled = true
            window?.makeFirstResponder(self)
            return true
        default:
            return false
        }
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = textField else { return }
        let runs = Self.runs(from: field.attributedStringValue, scale: scaleFactor, fallbackSize: textFontSize)
        if let selectionObserver {
            NotificationCenter.default.removeObserver(selectionObserver)
        }
        selectionObserver = nil
        textField = nil
        field.removeFromSuperview()
        state.isEditingText = false

        let newAnnotation = Annotation(
            shape: .text(runs: runs, origin: textOrigin, style: textStyle),
            color: textColor,
            lineWidth: 0
        )
        let isEmpty = Annotation.plainText(runs).isEmpty

        if let before = reEditSnapshot, let index = reEditIndex, let original = reEditOriginal {
            // 直していたとき
            var updated = newAnnotation
            updated.id = original.id
            if textCancelled || updated == original {
                annotations = before.annotations
            } else {
                pushUndo(before)
                if !isEmpty {
                    annotations.insert(updated, at: min(index, annotations.count))
                }
                historyChanged()
            }
            reEditSnapshot = nil
            reEditIndex = nil
            reEditOriginal = nil
        } else if !textCancelled, !isEmpty {
            commit(newAnnotation)
        }

        textCancelled = false
        window?.makeFirstResponder(self)
        updateSelectionBar()
        needsDisplay = true
    }

    /// テキストフィールドの中身を、大きさごとの部分に分ける（画面の拡大率を戻し、前後の空白は除く）
    static func runs(from attributed: NSAttributedString, scale: CGFloat, fallbackSize: CGFloat) -> [TextRun] {
        var runs: [TextRun] = []
        let string = attributed.string as NSString
        attributed.enumerateAttribute(.font, in: NSRange(location: 0, length: attributed.length)) { value, range, _ in
            let pointSize = (value as? NSFont)?.pointSize ?? fallbackSize * scale
            // 0.5pt 単位にそろえる
            let size = ((pointSize / max(scale, 0.01)) * 2).rounded() / 2
            let text = string.substring(with: range)
            if let last = runs.last, abs(last.fontSize - size) < 0.01 {
                runs[runs.count - 1].text += text
            } else {
                runs.append(TextRun(text: text, fontSize: size))
            }
        }
        // 前後の空白を除く
        while let first = runs.first {
            let trimmed = String(first.text.drop(while: \.isWhitespace))
            if trimmed.isEmpty { runs.removeFirst() } else { runs[0].text = trimmed; break }
        }
        while let last = runs.last {
            let trimmed = String(last.text.reversed().drop(while: \.isWhitespace).reversed())
            if trimmed.isEmpty { runs.removeLast() } else { runs[runs.count - 1].text = trimmed; break }
        }
        return runs
    }
}
