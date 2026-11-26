import AppKit

/// Dock のアイコンを、ふつうのウィンドウ（設定・履歴・使い方と許可・Gyazo につなぐ・更新の画面）を開いている間だけ出す。
/// ふだんはメニューバーだけに常駐する（Info.plist の LSUIElement）。ウィンドウを開いている間は、
/// Dock と ⌘Tab からそのウィンドウに戻れるようにする。すべて閉じたら、また Dock から消す。
/// 浮かせた画像・ツールバーなどの重ねて出す部品では出さない
@MainActor
enum DockIcon {
    /// 開いているウィンドウと、閉じたことを受け取る印
    private static var observers: [ObjectIdentifier: (window: NSWindow, token: NSObjectProtocol)] = [:]
    /// 自分のものでないウィンドウ（Sparkle の更新の画面）を出している間、Dock に出しておく印
    private static var holds: Set<String> = []

    /// window を開いている間、Dock にアイコンを出す（ウィンドウを前に出す前に呼ぶ）
    static func show(for window: NSWindow) {
        let key = ObjectIdentifier(window)
        if observers[key] == nil {
            let token = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { _ in
                MainActor.assumeIsolated { windowWillClose(key) }
            }
            observers[key] = (window, token)
        }
        enterDock()
    }

    /// name の用が済むまで（release するまで）、Dock にアイコンを出しておく。
    /// 開け閉めを自分で知れないウィンドウ（Sparkle の更新の画面）を出す間に使う
    static func hold(_ name: String) {
        holds.insert(name)
        enterDock()
    }

    /// name の用が済んだ。ほかに出しておく理由がなければ、メニューバーだけに戻る
    static func release(_ name: String) {
        guard holds.remove(name) != nil else { return }
        leaveDockIfUnused()
    }

    /// Dock のアイコンを押したとき：開いているウィンドウを前に出す（しまっていれば戻す）
    static func bringWindowsToFront() {
        for (window, _) in observers.values {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate()
    }

    private static func windowWillClose(_ key: ObjectIdentifier) {
        guard let entry = observers.removeValue(forKey: key) else { return }
        NotificationCenter.default.removeObserver(entry.token)
        leaveDockIfUnused()
    }

    private static func enterDock() {
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
    }

    /// 開いているウィンドウも、出しておく印もなければ、メニューバーだけに戻る
    private static func leaveDockIfUnused() {
        if observers.isEmpty, holds.isEmpty, NSApp.activationPolicy() != .accessory {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
