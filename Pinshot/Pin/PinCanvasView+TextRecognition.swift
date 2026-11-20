import AppKit

extension PinCanvasView {
    // MARK: - 文字の読み取り（範囲を選ぶ・読み取っている間の見た目・読み取った文字の吹き出し）

    /// 文字を読み取る範囲を、ドラッグで選んでもらう（esc でやめる。クリックだけなら見えている範囲すべて）
    func beginPickingTextRegion() {
        commitPendingText()
        isPickingTextRegion = true
        // esc でやめられるよう、キーを受けるようにする
        window?.makeKey()
        window?.makeFirstResponder(self)
        showHUD("文字を読み取る範囲をドラッグ（esc でやめる）")
        updateCursor()
    }

    /// 範囲を選ぶのをやめる（選び終えたとき・esc）
    func endPickingTextRegion() {
        isPickingTextRegion = false
        textRegionDraft = nil
        dragStart = nil
        needsDisplay = true
        updateCursor()
    }

    /// 読み取りを始めた（imageRect は読む範囲。画像のポイント座標）
    func showTextScan(in imageRect: CGRect) {
        textScanOverlay?.removeFromSuperview()
        let overlay = TextScanOverlay(frame: bounds)
        addSubview(overlay, positioned: .below, relativeTo: selectionBar)
        overlay.startScanning(in: viewRect(imageRect))
        textScanOverlay = overlay
    }

    /// 読み取り終えた（boxes は読み取った文字の場所。画像のポイント座標。空なら見つからなかった）
    func finishTextScan(foundBoxes boxes: [CGRect]) {
        guard let overlay = textScanOverlay else { return }
        let done: () -> Void = { [weak self, weak overlay] in
            overlay?.removeFromSuperview()
            if self?.textScanOverlay === overlay { self?.textScanOverlay = nil }
        }
        if boxes.isEmpty {
            overlay.finishNotFound(onDone: done)
        } else {
            overlay.finish(found: boxes.map(viewRect), onDone: done)
        }
    }

    /// 読み取った文字を吹き出しで見せる。textBoxes（画像のポイント座標）は文字のあった場所
    func showRecognizedText(_ text: String, textBoxes: [CGRect]) {
        textResultPopover?.close()
        let popover = RecognizedTextPopover(text: text)
        popover.onClose = { [weak self, weak popover] in
            if self?.textResultPopover === popover { self?.textResultPopover = nil }
        }
        popover.show(relativeTo: textResultAnchor(for: textBoxes), of: self)
        textResultPopover = popover
    }

    /// 吹き出しが指す四角（view の座標）。縦は画像の見えている部分の高さいっぱい、横は文字のあった所。
    /// 吹き出しはこの四角の外（下、場所がなければ上）に出るので、画像に重ならず、矢印は文字の真下か真上を指す
    private func textResultAnchor(for boxes: [CGRect]) -> NSRect {
        let image = viewRect(cropRect).intersection(visibleRect)
        guard !image.isNull else { return bounds }
        let text = boxes.map(viewRect).reduce(NSRect.null) { $0.union($1) }
        let minX = text.isNull ? image.minX : max(image.minX, text.minX)
        let maxX = text.isNull ? image.maxX : min(image.maxX, text.maxX)
        guard maxX > minX else { return image }
        return NSRect(x: minX, y: image.minY, width: maxX - minX, height: image.height)
    }
}
