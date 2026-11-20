import AppKit

/// PNG を、設定に合わせて保存する（決めたフォルダにすぐ保存する・毎回保存先を聞く）。
/// 浮かせた画像と、撮った画像の履歴の両方から使う
@MainActor
enum ImageSaver {
    /// 保存できたら onSaved を呼ぶ。保存できなかったときは、理由を知らせる
    static func save(_ data: Data, suggestedName: String = ImageExporter.defaultFileName(), onSaved: (() -> Void)? = nil) {
        let settings = AppSettings.shared

        // 決めたフォルダにすぐ保存する設定のとき
        if settings.saveMode == .folder {
            let url = ImageExporter.uniqueURL(in: settings.saveFolder, fileName: suggestedName)
            write(data, to: url, onSaved: onSaved)
            return
        }

        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.png]
        savePanel.nameFieldStringValue = suggestedName
        savePanel.directoryURL = settings.saveFolder
        savePanel.level = .modalPanel
        NSApp.activate()
        savePanel.begin { response in
            guard response == .OK, let url = savePanel.url else { return }
            write(data, to: url, onSaved: onSaved)
        }
    }

    /// いくつかの PNG をまとめて保存する。決めたフォルダにすぐ保存する設定ならそこへ、そうでなければ保存先のフォルダを聞く。
    /// 同じ名前があれば「名前 2.png」のようにする。保存できた数を onSaved に渡す
    static func saveAll(_ files: [(data: Data, name: String)], onSaved: ((Int) -> Void)? = nil) {
        let settings = AppSettings.shared
        let writeAll: (URL) -> Void = { folder in
            var saved = 0
            for file in files {
                let url = ImageExporter.uniqueURL(in: folder, fileName: file.name)
                if (try? file.data.write(to: url)) != nil { saved += 1 }
            }
            if saved < files.count {
                AppAlert.inform("\(files.count - saved) 枚を保存できませんでした")
            }
            if saved > 0 { onSaved?(saved) }
        }
        if settings.saveMode == .folder {
            writeAll(settings.saveFolder)
            return
        }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "ここに保存"
        panel.message = "\(files.count) 枚の画像を保存するフォルダを選んでください"
        panel.directoryURL = settings.saveFolder
        panel.level = .modalPanel
        NSApp.activate()
        panel.begin { response in
            guard response == .OK, let folder = panel.url else { return }
            writeAll(folder)
        }
    }

    private static func write(_ data: Data, to url: URL, onSaved: (() -> Void)?) {
        do {
            try data.write(to: url)
            onSaved?()
        } catch {
            AppAlert.inform(error)
        }
    }
}
