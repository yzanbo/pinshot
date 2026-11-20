import Foundation

/// アプリのデータを置くフォルダ（~/Library/Application Support/Pinshot）
enum AppFolders {
    static var root: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Pinshot", isDirectory: true)
    }

    /// 撮った画像の履歴
    static var history: URL { root.appendingPathComponent("History", isDirectory: true) }

    /// 浮かせていた画像（終了・再起動のあとに戻す）
    static var pins: URL { root.appendingPathComponent("Pins", isDirectory: true) }
}
