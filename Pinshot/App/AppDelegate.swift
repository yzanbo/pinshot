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
        AppSupport.installMainMenu()
        AppSupport.allowCursorChangesInBackground()
        statusMenu.install()
        registerHotKeys()

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
            WelcomeWindowController.shared.show()
        }
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
                self?.perform(action)
            }
            hotKeys[action] = hotKey
            if hotKey == nil { unavailable.insert(action) }
            statusMenu.showShortcut(shortcut, registered: hotKey != nil, for: action)
        }
        // 登録できなかったものは、設定のショートカットの画面でも知らせる
        if !recording, settings.unavailableShortcuts != unavailable {
            settings.unavailableShortcuts = unavailable
        }
    }

    private func perform(_ action: ShortcutAction) {
        switch action {
        case .captureRegion: captureController.start(mode: .region)
        case .captureWindow: captureController.start(mode: .window)
        case .captureScreen: captureController.start(mode: .screen)
        case .captureScroll:
            captureController.startScrollCapture()
        case .captureTimer: captureController.start(mode: .region, timer: 5)
        case .pinClipboard:
            if !PinManager.shared.pinClipboardImage() { NSSound.beep() }
        case .restoreClosed: PinManager.shared.restoreLastClosed()
        case .bringAllToFront: PinManager.shared.bringAllToFront()
        case .closeAll: PinManager.shared.closeAll()
        }
    }
}
