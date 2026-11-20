import AppKit
import UniformTypeIdentifiers

/// 保存したもの（画像・GIF・動画）を、設定に合わせて保存する（決めたフォルダにすぐ保存する・毎回保存先を聞く）。
/// 保存先（親）の中を、設定に合わせて種類ごと・月ごとに分ける（SaveLocation）。浮かせた画像・撮った画像の履歴・録画から使う
@MainActor
enum ImageSaver {
    /// kind を保存するフォルダを Finder で開く（まだ保存していなくても開けるよう、なければ作る）
    static func openSaveFolder(for kind: ExportKind = .image) {
        NSWorkspace.shared.open(AppSettings.shared.prepareSaveFolder(for: kind))
    }

    /// 保存できたら onSaved を呼ぶ。保存できなかったときは、理由を知らせる
    static func save(_ data: Data, suggestedName: String = ImageExporter.defaultFileName(), onSaved: (() -> Void)? = nil) {
        chooseDestination(for: .image, suggestedName: suggestedName) { url in
            guard let url else { return }
            do {
                try data.write(to: url)
                onSaved?()
            } catch {
                AppAlert.inform(error)
            }
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
            writeAll(preparedFolder(for: .image))
            return
        }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "ここに保存"
        panel.message = "\(files.count) 枚の画像を保存するフォルダを選んでください"
        panel.directoryURL = preparedFolder(for: .image)
        panel.level = .modalPanel
        NSApp.activate()
        panel.begin { response in
            guard response == .OK, let folder = panel.url else { return }
            writeAll(folder)
        }
    }

    /// ファイル（録画・GIF）を、設定に合わせて、その種類の保存先へ保存する（元のファイルをコピーする）。
    /// onFinish は、保存したか・やめたかにかかわらず、終わったときに呼ぶ（一時ファイルを片付けるため）
    static func saveFile(copying source: URL, suggestedName: String, kind: ExportKind, onSaved: (() -> Void)? = nil, onFinish: (() -> Void)? = nil) {
        chooseDestination(for: kind, suggestedName: suggestedName) { url in
            defer { onFinish?() }
            guard let url else { return }
            do {
                // 保存先で「置き換える」を選んだときは、前のファイルを外してからコピーする
                if FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.removeItem(at: url)
                }
                try FileManager.default.copyItem(at: source, to: url)
                onSaved?()
            } catch {
                AppAlert.inform(error)
            }
        }
    }

    /// 保存する場所を決めて then に渡す（やめたときは nil）。
    /// 決めたフォルダにすぐ保存する設定ならその種類のフォルダの重ならない名前、そうでなければ保存先を聞く
    private static func chooseDestination(for kind: ExportKind, suggestedName: String, then: @escaping (URL?) -> Void) {
        let folder = preparedFolder(for: kind)
        if AppSettings.shared.saveMode == .folder {
            then(ImageExporter.uniqueURL(in: folder, fileName: suggestedName))
            return
        }
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [kind.contentType]
        savePanel.nameFieldStringValue = suggestedName
        savePanel.directoryURL = folder
        savePanel.level = .modalPanel
        NSApp.activate()
        savePanel.begin { response in
            then(response == .OK ? savePanel.url : nil)
        }
    }

    /// kind を保存するフォルダ（保存先・種類ごと・月ごとのフォルダがなければ作る）
    private static func preparedFolder(for kind: ExportKind) -> URL {
        AppSettings.shared.prepareSaveFolder(for: kind)
    }
}
