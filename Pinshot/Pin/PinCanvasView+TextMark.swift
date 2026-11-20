import AppKit

extension PinCanvasView {
    // MARK: - 文字マーカー（文字の位置に合わせて引く）

    /// 画像の文字の位置を調べておく（画像 1 枚につき 1 回。書き込みは見ず、元の画像で読む）。
    /// 文字マーカーを選んだときに始め、ドラッグする前に終えておく
    func prepareTextMarkLines() {
        guard textMarkLines == nil, !isFindingTextMarkLines else { return }
        isFindingTextMarkLines = true
        let image = baseImage
        let size = imageSize
        Task { @MainActor [weak self] in
            let recognized = await TextRecognizer.recognizeLines(image)
            // 画素を見て、文字の線がある高さに合わせる（Vision の範囲のままだと下にずれる）。重いので裏で行う
            let lines = await Task.detached(priority: .userInitiated) {
                TextInk.fitted(TextMarkLayout.lines(from: recognized, imageSize: size), image: image, imageSize: size)
            }.value
            guard let self else { return }
            self.isFindingTextMarkLines = false
            self.textMarkLines = lines
            if lines.isEmpty, self.state.isEditing, self.state.tool == .textMark {
                self.showHUD("文字が見つかりませんでした（まっすぐ引きます）")
            }
            // 調べている間にドラッグを始めていたら、文字に合わせ直す
            self.updateTextMarkDraft()
        }
    }

    func beginTextMark(at point: CGPoint) {
        prepareTextMarkLines()
        if isFindingTextMarkLines { showHUD("文字の場所を調べています…") }
        selectedID = nil
        dragStart = point
        textMarkDragEnd = point
        drafting = Annotation(
            shape: .textMark([], style: state.textMarkStyle),
            color: state.drawColor,
            lineWidth: state.lineWidth(for: .textMark)
        )
    }

    func dragTextMark(to point: CGPoint) {
        textMarkDragEnd = point
        updateTextMarkDraft()
    }

    /// 引いている途中の文字マーカーを、いまの文字の位置に合わせて作り直す
    func updateTextMarkDraft() {
        guard let start = dragStart, let end = textMarkDragEnd, case .textMark(_, let style)? = drafting?.shape else { return }
        let lines = textMarkLines ?? []
        drafting?.shape = .textMark(
            TextMarkLayout.rects(from: start, to: end, lines: lines, fallbackHeight: typicalLineHeight(lines)),
            style: style
        )
        needsDisplay = true
    }

    /// 線の位置を、この画像のすべての文字マーカーでそろえる（1 回で元に戻せる）。
    /// 線の位置は 1 枚の中でばらばらだと見苦しいので、選んでいるものだけでなく全体を変える
    func unifyTextMarkLinePosition(_ position: TextMarkLinePosition) {
        let targets = annotations.compactMap { annotation -> Annotation? in
            guard case .textMark(let rects, var style) = annotation.shape, style.linePosition != position else { return nil }
            style.linePosition = position
            var changed = annotation
            changed.shape = .textMark(rects, style: style)
            return changed
        }
        guard !targets.isEmpty else { return }
        document.beginChange()
        targets.forEach { document.replace($0) }
        document.endChange(keep: true)
        historyChanged()
        needsDisplay = true
        showHUD("線の位置：\(position.label)（すべての文字マーカー）")
    }

    /// 文字のない所でまっすぐ引くときの高さ（画像の文字の行の高さの真ん中。文字がなければ 18）
    private func typicalLineHeight(_ lines: [TextLineBoxes]) -> CGFloat {
        let heights = lines.map(\.box.height).sorted()
        return heights.isEmpty ? 18 : heights[heights.count / 2]
    }
}
