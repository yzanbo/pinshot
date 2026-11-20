import Foundation

/// アプリのデータを置くフォルダ（~/Library/Application Support/Pinshot）
enum AppFolders {
    static var root: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Pinshot", isDirectory: true)
    }

    /// 撮った画像の履歴（読み取った文字の履歴も、ここに texts.json で置く）
    static var history: URL { root.appendingPathComponent("History", isDirectory: true) }

    /// 浮かせていた画像（終了・再起動のあとに戻す）
    static var pins: URL { root.appendingPathComponent("Pins", isDirectory: true) }

    /// 画面の録画（残す期間と数は、設定の「履歴」で決める。RecordingStore）
    static var recordings: URL { root.appendingPathComponent("Recordings", isDirectory: true) }

    /// 上げたものの履歴（共有リンクの一覧と、小さな縮小画像）
    static var uploads: URL { root.appendingPathComponent("Uploads", isDirectory: true) }
}
