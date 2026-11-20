import AppKit

extension PinController {
    // MARK: - コピー・保存

    /// 書き出す画像（書き込み・トリミングを反映し、設定によっては背景を付ける）
    func exportImage(forceBackground: Bool = false) -> (image: CGImage, pointSize: CGSize)? {
        canvas.commitPendingText()
        guard let image = canvas.renderedImage() else { return nil }
        var decoration = state.backdropDecoration
        decoration.isEnabled = showsBackdrop || forceBackground
        if decoration.isEnabled, let decorated = ImageExporter.decorate(image, pointSize: canvas.contentSize, with: decoration) {
            return decorated
        }
        return (image, canvas.contentSize)
    }

    func copyToPasteboard(withBackground: Bool = false) {
        guard let output = exportImage(forceBackground: withBackground) else { return }
        ImageExporter.writeToPasteboard(output.image, pointSize: output.pointSize)
        canvas.showHUD(withBackground ? "背景付きでコピーしました" : "コピーしました")
    }

    func copyAndClose() {
        guard let output = exportImage() else { return }
        ImageExporter.writeToPasteboard(output.image, pointSize: output.pointSize)
        close()
    }

    func save() {
        guard let output = exportImage() else { return }
        guard let data = ImageExporter.pngData(output.image, pointSize: output.pointSize) else { return }
        ImageSaver.save(data) { [weak self] in
            self?.canvas.showHUD("保存しました")
        }
    }
}
