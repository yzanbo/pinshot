import AppKit

/// 確かめる・知らせるダイアログ（アプリのすべてのダイアログで使う）。
/// - アイコンは、アプリの中のアイコンをはっきり渡す（macOS が覚えている古いアイコン・仮のアイコンが出ないように）
/// - ウィンドウがあれば、そのウィンドウのシートで出す。アプリ全体を止めないので、出している間もショートカットで撮れる（ダイアログごと撮れる）
@MainActor
enum AppAlert {
    /// 確かめる。confirmTitle を押したら onConfirm を呼ぶ（esc・キャンセルでは何もしない）
    static func confirm(
        _ message: String,
        detail: String,
        confirmTitle: String,
        in window: NSWindow? = nil,
        onConfirm: @escaping () -> Void
    ) {
        let alert = make(message, detail: detail)
        // 押すボタンは、見やすいふつうの決定ボタン（青地に白）にする。キャンセルは esc でも押せる
        alert.addButton(withTitle: confirmTitle)
        let cancel = alert.addButton(withTitle: "キャンセル")
        cancel.keyEquivalent = "\u{1b}"
        present(alert, in: window) { response in
            if response == .alertFirstButtonReturn { onConfirm() }
        }
    }

    /// 知らせる（OK だけ）
    static func inform(_ message: String, detail: String = "", in window: NSWindow? = nil) {
        let alert = make(message, detail: detail)
        alert.addButton(withTitle: "OK")
        present(alert, in: window) { _ in }
    }

    /// エラーを知らせる
    static func inform(_ error: Error, in window: NSWindow? = nil) {
        inform(error.localizedDescription, in: window)
    }

    private static func make(_ message: String, detail: String) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.alertStyle = .informational
        if let icon = AppSupport.appIcon {
            alert.icon = icon
        }
        return alert
    }

    private static func present(_ alert: NSAlert, in window: NSWindow?, completion: @escaping (NSApplication.ModalResponse) -> Void) {
        // window を渡さないときは、前にあるウィンドウ（設定・履歴など）を使う
        let window = window ?? NSApp.keyWindow
        NSApp.activate()
        // 見えている、ふつうのウィンドウがあれば、そのシートにする
        if let window, window.isVisible, !(window is NSPanel) {
            window.makeKeyAndOrderFront(nil)
            alert.beginSheetModal(for: window, completionHandler: completion)
        } else {
            completion(alert.runModal())
        }
    }
}
