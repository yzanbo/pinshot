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
        let settings = AppSettings.shared

        // 決めたフォルダにすぐ保存する設定のとき
        if settings.saveMode == .folder {
            let url = ImageExporter.uniqueURL(in: settings.saveFolder, fileName: ImageExporter.defaultFileName())
            write(data, to: url)
            return
        }

        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.png]
        savePanel.nameFieldStringValue = ImageExporter.defaultFileName()
        savePanel.directoryURL = settings.saveFolder
        savePanel.level = .modalPanel
        NSApp.activate()
        savePanel.begin { [weak self] response in
            guard response == .OK, let url = savePanel.url else { return }
            self?.write(data, to: url)
        }
    }

    private func write(_ data: Data, to url: URL) {
        do {
            try data.write(to: url)
            canvas.showHUD("保存しました")
        } catch {
            NSApp.activate()
            NSAlert(error: error).runModal()
        }
    }
}
