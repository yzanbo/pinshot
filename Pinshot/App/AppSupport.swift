import AppKit

/// アプリの裏方の設定
@MainActor
enum AppSupport {
    /// アプリのアイコン。アプリの中のアイコンのファイル（AppIcon.icns）を直接読み込む。
    /// macOS が覚えているアイコンは、アイコンを変える前の古いもの・仮のもののことがあるため
    static let appIcon: NSImage? = Bundle.main.image(forResource: "AppIcon")

    /// 版の番号の表示（β 版なら「0.4.0 (β 版)」）。版は Info.plist の CFBundleShortVersionString、
    /// β 版かは PinshotIsBeta（どちらも project.yml で決める）
    static var versionText: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let number = info["CFBundleShortVersionString"] as? String ?? "—"
        return info["PinshotIsBeta"] as? Bool == true ? "\(number) (β 版)" : number
    }

    /// 文字の入力欄で ⌘C・⌘V・⌘A・⌘Z が効くよう、編集メニューを持つメインメニューを用意する
    /// （メニューバーに常駐するアプリはメニューが出ないが、キーの組み合わせはメニューを通して届く）
    static func installMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        // Dock に出ている間（設定・履歴を開いている間）は、上のメニューバーにこのメニューが出る
        let settings = appMenu.addItem(withTitle: "設定…", action: #selector(AppMenuActions.openSettings(_:)), keyEquivalent: ",")
        settings.target = AppMenuActions.shared
        appMenu.addItem(.separator())
        let quit = appMenu.addItem(withTitle: "Pinshot を終了", action: #selector(AppMenuActions.quit(_:)), keyEquivalent: "q")
        quit.target = AppMenuActions.shared
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "編集")
        editMenu.addItem(withTitle: "取り消す", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "やり直す", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "カット", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "コピー", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "ペースト", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "すべてを選択", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        NSApp.mainMenu = mainMenu
    }

    /// 裏にいるときも、浮かせた画像の上でカーソルの形を変えられるようにする。
    /// 画像を浮かせているだけのときはこのアプリが前に出ていないため、ふつうは macOS がカーソルの変更を受け付けない。
    /// 公開されていない CoreGraphics の設定（SetsCursorInBackground）を使う（App Store では使えない）
    static func allowCursorChangesInBackground() {
        let connection = _CGSDefaultConnection()
        _ = CGSSetConnectionProperty(connection, connection, "SetsCursorInBackground" as CFString, kCFBooleanTrue)
    }
}

/// アプリのメニューの操作（設定…・終了）。
/// ⌘Q で終了する。ただし浮かせた画像がキーのとき（撮った直後など）は終了しない。
/// メニューバーには前のアプリ（Safari など）が出ているので、そのアプリを終了するつもりで押すことが多く、
/// Pinshot が終了して、浮かせた画像が画面から消えてしまうため（戻す設定なら次の起動で戻るが、いま見ていたものは消える）
@MainActor
final class AppMenuActions: NSObject {
    static let shared = AppMenuActions()

    /// 設定のウィンドウを開く（⌘,）
    @objc func openSettings(_ sender: Any?) {
        SettingsWindowController.shared.show()
    }

    @objc func quit(_ sender: Any?) {
        if NSApp.keyWindow is PinPanel {
            NSSound.beep()
            return
        }
        NSApp.terminate(sender)
    }
}

// 公開されていない CoreGraphics の関数
@_silgen_name("_CGSDefaultConnection")
private func _CGSDefaultConnection() -> Int32

@_silgen_name("CGSSetConnectionProperty")
private func CGSSetConnectionProperty(_ connection: Int32, _ target: Int32, _ key: CFString, _ value: CFTypeRef) -> Int32
