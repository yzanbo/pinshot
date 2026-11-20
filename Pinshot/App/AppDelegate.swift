import AppKit
import Combine

@main
@MainActor
/// 起動と、グローバルショートカットの登録
final class AppDelegate: NSObject, NSApplicationDelegate {
    private lazy var statusMenu = StatusMenuController(actions: .init(
        perform: { [weak self] in self?.perform($0) },
        captureWithTimer: { [weak self] in self?.captureController.start(mode: .region, timer: $0) },
        captureWindow: { [weak self] in self?.captureController.captureWindow(id: $0) }
    ))
    private var hotKeys: [ShortcutAction: HotKey] = [:]
    /// メニューを開いている間もショートカットを効かせる（アクセシビリティを許可しているとき）
    private let keyTap = ShortcutKeyTap()
    /// 操作ごとの、最後にショートカットで行った時刻（HotKey とキーの見張りの両方から届いても 1 回にする）
    private var lastShortcutTimes: [ShortcutAction: Date] = [:]
    /// 終了の合図（killall など）を受けて、ふつうに終了する（浮かせている画像を保存してから止まる）
    private var terminateSignal: DispatchSourceSignal?
    private let captureController = CaptureController()
    private let settings = AppSettings.shared
    private var cancellables = Set<AnyCancellable>()

    private static let didShowWelcomeKey = "app.didShowWelcome"

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
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
        keyTap.onShortcut = { [weak self] action in self?.performFromShortcut(action) }
        registerHotKeys()
        keyTap.start()
        // 撮った画像の履歴を読み、期間を過ぎたものを消す
        CaptureHistory.shared.pruneExpired()
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
        settings.$shortcuts
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.registerHotKeys() }
            .store(in: &cancellables)
        settings.$recordingAction
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.registerHotKeys() }
            .store(in: &cancellables)

        // 初めての起動では使い方を案内する
        if !UserDefaults.standard.bool(forKey: Self.didShowWelcomeKey) {
            UserDefaults.standard.set(true, forKey: Self.didShowWelcomeKey)
            WelcomeWindowController.shared.show(firstLaunch: true)
        }
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
            guard let shortcut = settings.shortcut(for: action) else {
                statusMenu.showShortcut(nil, registered: true, for: action)
                continue
            }
            if recording {
                statusMenu.showShortcut(shortcut, registered: true, for: action)
                continue
            }
            let hotKey = HotKey(keyCode: shortcut.keyCode, modifiers: shortcut.modifiers) { [weak self] in
                self?.performFromShortcut(action)
            }
            hotKeys[action] = hotKey
            if hotKey == nil { unavailable.insert(action) }
            statusMenu.showShortcut(shortcut, registered: hotKey != nil, for: action)
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
        guard OpenMenus.isAnyOpen, !ShortcutAction.captureActions.contains(action) else {
            perform(action)
            return
        }
        OpenMenus.closeAll()
        // メニューが閉じ終わってから始める
        DispatchQueue.main.async { [weak self] in
            self?.perform(action)
        }
    }

    private func perform(_ action: ShortcutAction) {
        switch action {
        case .captureRegion: captureController.start(mode: .region)
        case .captureWindow: captureController.start(mode: .window)
        case .captureScreen: captureController.start(mode: .screen)
        case .captureScroll:
            captureController.start(mode: .scroll)
        case .captureTimer: captureController.start(mode: .region, timer: 5)
        case .pinClipboard:
            if !PinManager.shared.pinClipboardImage() { NSSound.beep() }
        case .openHistory: CaptureHistoryWindowController.shared.show()
        case .restoreClosed: PinManager.shared.restoreLastClosed()
        case .bringAllToFront: PinManager.shared.bringAllToFront()
        case .closeAll: PinManager.shared.closeAll()
        }
    }
}
