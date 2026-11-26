import AppKit
import Combine
import os

@main
@MainActor
/// 起動と、グローバルショートカットの登録
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let logger = Logger(pinshot: "app")

    private let statusMenu = StatusMenuController()
    /// 更新の仕組み（公開鍵の入っていないビルドでは nil。状態は AppUpdates.shared から見る）
    private var updater: SparkleUpdater?
    private var hotKeys: [ShortcutAction: HotKey] = [:]
    /// メニューを開いている間もショートカットを効かせる（アクセシビリティを許可しているとき）
    private let keyTap = ShortcutKeyTap()
    /// 操作ごとの、最後にショートカットで行った時刻（HotKey とキーの見張りの両方から届いても 1 回にする）
    private var lastShortcutTimes: [ShortcutAction: Date] = [:]
    /// 終了の合図（killall など）を受けて、ふつうに終了する（浮かせている画像を保存してから止まる）
    private var terminateSignal: DispatchSourceSignal?
    private let settings = AppSettings.shared
    private var cancellables = Set<AnyCancellable>()

    private static let didShowWelcomeKey = "app.didShowWelcome"

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    /// Dock のアイコンを押したとき（設定・履歴を開いている間だけ Dock に出る）。開いているウィンドウを前に出す
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        DockIcon.bringWindowsToFront()
        return false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 使い方の画面などに出すアイコンを、アプリの中のアイコンにする（AppSupport.appIcon）
        if let icon = AppSupport.appIcon {
            NSApp.applicationIconImage = icon
        }
        AppSupport.installMainMenu()
        AppSupport.allowCursorChangesInBackground()
        OpenMenus.startObserving()
        statusMenu.install()
        // 録画を始めた・止めたら、メニューバーのアイコンと「画面を録画」の項目を変える
        RecordingController.shared.onStateChange = { [weak self] recording in self?.statusMenu.setRecording(recording) }
        // 上げている間は、メニューバーのアイコンを「上げている」印にする
        UploadCenter.shared.onActivityChange = { [weak self] uploading in self?.statusMenu.setUploading(uploading) }
        // 新しい版を確かめる仕組みを始める。見つけたら、入れるか飛ばすまで、メニューバーのアイコンに印を付ける
        AppUpdates.shared.onPendingVersionChange = { [weak self] _ in self?.statusMenu.pendingUpdateDidChange() }
        updater = SparkleUpdater.start(updates: .shared)
        keyTap.onShortcut = { [weak self] action in self?.performFromShortcut(action) }
        registerHotKeys()
        keyTap.start()
        // 撮った画像の履歴を読む（読むときに、期間を過ぎたものを消す）。録画も、期間・数から外れたものを削除する
        _ = CaptureHistory.shared
        _ = RecordingStore.shared
        // 保存先のフォルダ（初期設定は ~/Pictures/Pinshot）がなければ作る
        AppSettings.shared.prepareSaveFolder()
        // 前に浮かせていた画像を戻し、動いている間もときどき保存する
        PinManager.shared.restoreSession()
        PinManager.shared.startAutosave()
        handleTerminateSignal()
        // 戻さない設定にしたら、保存したものをすぐ消す
        settings.$restorePins
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { _ in PinManager.shared.saveSession() }
            .store(in: &cancellables)

        // 見た目（システム・ライト・ダーク）をアプリ全体に設定し、変えたらすぐ反映する
        settings.$appearance
            .sink { mode in NSApp.appearance = mode.nsAppearance }
            .store(in: &cancellables)

        // ショートカットを変えたら登録し直す。記録している間はすべて止めておく
        settings.$shortcuts.dropFirst().map { _ in () }
            .merge(with: settings.$recordingAction.dropFirst().map { _ in () })
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.registerHotKeys() }
            .store(in: &cancellables)

        // 初めての起動では使い方を案内する
        if !UserDefaults.standard.bool(forKey: Self.didShowWelcomeKey) {
            UserDefaults.standard.set(true, forKey: Self.didShowWelcomeKey)
            WelcomeWindowController.shared.show(firstLaunch: true)
        }
        logLaunch()
    }

    /// 起動したことを記録に残す（更新のあと、どの版が動いているか、画面収録・アクセシビリティの許可と
    /// 「ログイン時に起動」が引き継がれたかを、あとから確かめられるように。make update-test-log で書き出せる）
    private func logLaunch() {
        let version = Bundle.main.shortVersion ?? "?"
        let build = Bundle.main.buildNumber ?? "?"
        let screen = ScreenPermission.isGranted ? "許可済み" : "未許可"
        let accessibility = AccessibilityPermission.isGranted ? "許可済み" : "未許可"
        let loginItem = LoginItemModel.isEnabledNow ? "オン" : "オフ"
        Self.logger.notice("起動しました: 版 \(version, privacy: .public)（ビルド \(build, privacy: .public)）、画面収録: \(screen, privacy: .public)、アクセシビリティ: \(accessibility, privacy: .public)、ログイン時に起動: \(loginItem, privacy: .public)")
    }

    /// killall（make stop など）で送られる終了の合図でも、すぐには止まらず、ふつうに終了する
    private func handleTerminateSignal() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { NSApp.terminate(nil) }
        source.resume()
        terminateSignal = source
    }

    /// 終了するとき（再起動・ログアウトも）、浮かせている画像を書き終えるまで待って保存する
    func applicationWillTerminate(_ notification: Notification) {
        PinManager.shared.saveSession(wait: true)
    }

    // MARK: - グローバルショートカット

    private func registerHotKeys() {
        // 先に古い登録をすべて外す（同じキーのまま登録し直すこともあるため）
        hotKeys.removeAll()
        let recording = settings.isRecordingShortcut
        var unavailable: Set<ShortcutAction> = []

        for action in ShortcutAction.allCases {
            let shortcut = settings.shortcut(for: action)
            // 記録している間は登録しない（メニューの表示はそのまま）
            if let shortcut, !recording {
                hotKeys[action] = HotKey(keyCode: shortcut.keyCode, modifiers: shortcut.modifiers) { [weak self] in
                    self?.performFromShortcut(action)
                }
                if hotKeys[action] == nil { unavailable.insert(action) }
            }
            statusMenu.showShortcut(shortcut, registered: !unavailable.contains(action), for: action)
        }
        // メニューを開いている間の見張りにも、同じショートカットを渡す（記録中・ほかのアプリが使っているものは除く）
        keyTap.shortcuts = recording ? [:] : settings.shortcuts.filter { hotKeys[$0.key] != nil }
        // 登録できなかったものは、設定のショートカットの画面でも知らせる
        if !recording, settings.unavailableShortcuts != unavailable {
            settings.unavailableShortcuts = unavailable
        }
    }

    /// ショートカットで押されたとき。撮る操作はそのまま始める（開いているメニューは、画面を撮ったあとに閉じる）。
    /// ほかの操作は、メニュー（ツールバーの ▾ など）が開いていたら、先に閉じてから行う
    private func performFromShortcut(_ action: ShortcutAction) {
        // HotKey とキーの見張りの両方から届いたときは、1 回だけ行う
        let now = Date()
        if let last = lastShortcutTimes[action], now.timeIntervalSince(last) < 0.5 { return }
        lastShortcutTimes[action] = now
        // 撮る操作は、メニューを開いたまま画面を撮り、撮り終えてからメニューを閉じる（開いたメニューも写るように）
        guard OpenMenus.isAnyOpen, !ShortcutAction.screenActions.contains(action) else {
            AppActions.shared.perform(action)
            return
        }
        OpenMenus.closeAll()
        // メニューが閉じ終わってから始める
        DispatchQueue.main.async {
            AppActions.shared.perform(action)
        }
    }
}
