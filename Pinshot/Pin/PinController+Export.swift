import AppKit

extension PinController {
    // MARK: - コピー・保存

    /// 書き出す画像（書き込み・トリミングを反映し、背景を付けている画像は背景も付ける）
    func exportImage() -> (image: CGImage, pointSize: CGSize)? {
        canvas.commitPendingText()
        guard let image = canvas.renderedImage() else { return nil }
        var decoration = state.backdropDecoration
        decoration.isEnabled = showsBackdrop
        if decoration.isEnabled, let decorated = ImageExporter.decorate(image, pointSize: canvas.contentSize, with: decoration) {
            return decorated
        }
        return (image, canvas.contentSize)
    }

    func copyToPasteboard() {
        guard let output = exportImage() else { return }
        ImageExporter.writeToPasteboard(output.image, pointSize: output.pointSize)
        canvas.showHUD("コピーしました")
    }

    // MARK: - 文字の読み取り

    /// 画像の文字を読み取ってコピーする。region（画像のポイント座標）を渡すと、その中だけを読む。
    /// 書き込みは読ませず、元の画像で読む。トリミングしているときは、見えている範囲だけを読む
    func copyRecognizedText(in region: CGRect? = nil) {
        canvas.commitPendingText()
        let visible = canvas.cropRect
        let target = (region ?? visible).intersection(visible)
        guard !target.isNull, let image = canvas.baseImagePixels(in: target) else {
            canvas.showHUD("読み取る範囲がありません")
            return
        }
        canvas.showHUD("文字を読み取っています…")
        canvas.showTextScan(in: target)
        Task { @MainActor [weak self] in
            let result = await TextRecognizer.copyText(in: image, pointSize: target.size)
            guard let self else { return }
            let boxes = result.boxes.map { RecognizedTextLayout.imageRect(for: $0, in: target) }
            self.canvas.finishTextScan(foundBoxes: boxes)
            // 読み取れたら吹き出しで見せる（コピーしたことも吹き出しで知らせる）。見つからなければ短い知らせだけ
            if result.text.isEmpty {
                self.canvas.showHUD(TextRecognizer.resultMessage(copiedCount: 0))
            } else {
                self.canvas.showRecognizedText(result.text, textBoxes: boxes)
            }
        }
    }

    func copyAndClose() {
        guard let output = exportImage() else { return }
        ImageExporter.writeToPasteboard(output.image, pointSize: output.pointSize)
        close()
    }

    /// いまの見た目（書き込み・背景を反映）を上げて、共有リンクをコピーする（上げる先は設定の「共有」）
    func uploadAndCopyLink() {
        guard let output = exportImage() else { return }
        UploadCenter.shared.shareImage(output.image, pointSize: output.pointSize) { [weak self] status in
            self?.canvas.showUploadStatus(status)
        }
    }

    func save() {
        guard let output = exportImage() else { return }
        guard let data = ImageExporter.pngData(output.image, pointSize: output.pointSize) else { return }
        ImageSaver.save(data) { [weak self] in
            self?.canvas.showHUD("保存しました")
        }
    }
}
