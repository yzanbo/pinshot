import AppKit

/// アプリの操作の入口（撮る・録る・浮かせる・履歴を開くなど）。
/// グローバルショートカットとメニューバーのメニューは、どちらもここを呼ぶ
/// （あとでショートカット App・URL スキームから呼ぶときも、ここを通せば同じ動きになる）
@MainActor
final class AppActions {
    static let shared = AppActions()

    /// 撮る流れ（選ぶ → タイマー → 浮かせる）
    private let captureController = CaptureController()

    private init() {}

    /// 操作を行う（録画中に撮ろうとした・クリップボードに画像がないなど、できないときは音で知らせる）
    func perform(_ action: ShortcutAction) {
        switch action {
        case .captureRegion: captureController.start(mode: .region)
        case .captureWindow: captureController.start(mode: .window)
        case .captureScreen: captureController.start(mode: .screen)
        case .captureTimer: captureController.start(mode: .region, timer: CaptureOptions.shortcutTimerSeconds)
        case .recordScreen:
            // 録画中なら止める（メニュー・ショートカットのどちらからも）
            if RecordingController.shared.isRecording {
                RecordingController.shared.stop()
            } else {
                captureController.start(mode: .record)
            }
        case .recordWindow: captureController.start(mode: .record, recordsWindowOnly: true)
        case .recordFullScreen: captureController.recordScreenUnderMouse()
        case .recordTimer: captureController.start(mode: .record, timer: CaptureOptions.shortcutTimerSeconds)
        case .pinClipboard:
            if !PinManager.shared.pinClipboardImage() { NSSound.beep() }
        case .openHistory: CaptureHistoryWindowController.shared.show()
        case .restoreClosed: PinManager.shared.restoreLastClosed()
        case .bringAllToFront: PinManager.shared.bringAllToFront()
        case .closeAll: PinManager.shared.closeAll()
        }
    }

    /// seconds 秒後に、範囲を選んで撮る（メニューの「タイマーでキャプチャ」）
    func captureWithTimer(_ seconds: Int) {
        captureController.start(mode: .region, timer: seconds)
    }

    /// 一覧から選んだウィンドウを、範囲を選ぶ画面を出さずに撮る（メニューの「ウィンドウを選んでキャプチャ」）
    func captureWindow(id: CGWindowID) {
        captureController.captureWindow(id: id)
    }

    /// seconds 秒後に、範囲を選んで録画する（メニューの「タイマーで録画」）
    func recordWithTimer(_ seconds: Int) {
        captureController.start(mode: .record, timer: seconds)
    }

    /// 一覧から選んだウィンドウの範囲を、範囲を選ぶ画面を出さずに録画する（メニューの「ウィンドウを選んで録画」）
    func recordWindow(id: CGWindowID) {
        captureController.recordWindow(id: id)
    }
}
