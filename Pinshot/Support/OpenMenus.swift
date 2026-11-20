import AppKit

/// いま開いているメニュー（ツールバーの ▾・右クリック・メニューバーなど）を覚えておき、閉じられるようにする。
/// メニューを開いている間は、macOS がメニューの操作だけを受け付けるので、ショートカットで撮り始めても範囲を選べない。
/// そのため、撮るときは画面を撮ったあとで（開いたメニューも写るように）、ほかの操作は先に、開いているメニューを閉じる
@MainActor
enum OpenMenus {
    private static var menus: [NSMenu] = []
    private static var observers: [Any] = []

    /// メニューが開いた・閉じたのを見始める（起動したときに一度だけ）
    static func startObserving() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { note in
            guard let menu = note.object as? NSMenu else { return }
            MainActor.assumeIsolated { menus.append(menu) }
        })
        observers.append(center.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { note in
            guard let menu = note.object as? NSMenu else { return }
            MainActor.assumeIsolated { menus.removeAll { $0 === menu } }
        })
    }

    /// 開いているメニューがあるか
    static var isAnyOpen: Bool { !menus.isEmpty }

    /// 開いているメニューをすべて閉じる
    static func closeAll() {
        for menu in menus.reversed() {
            menu.cancelTrackingWithoutAnimation()
        }
    }
}
