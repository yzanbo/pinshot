import AppKit

/// アプリの起動し直し（画面収録を許可したあとなど）
enum AppRelauncher {
    /// 新しい Pinshot を起動してから、いまの Pinshot を終了する
    @MainActor
    static func relaunch() {
        let process = Process()
        // いまの Pinshot が終わる（ショートカットを手放す）のを少し待ってから開く
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", Bundle.main.bundlePath]
        try? process.run()
        NSApp.terminate(nil)
    }
}
