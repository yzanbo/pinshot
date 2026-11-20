import AppKit

/// キャプチャの種類
enum CaptureMode: String, CaseIterable, Identifiable {
    case region
    case window
    case screen
    case scroll

    var id: String { rawValue }

    var label: String {
        switch self {
        case .region: "範囲"
        case .window: "ウィンドウ"
        case .screen: "画面全体"
        case .scroll: "スクロール"
        }
    }

    var symbolName: String {
        switch self {
        case .region: "rectangle.dashed"
        case .window: "macwindow"
        case .screen: "display"
        case .scroll: "arrow.down.doc"
        }
    }

    /// 範囲選択の画面に出す案内
    var hint: String {
        switch self {
        case .region: "ドラッグで範囲を選択"
        case .window: "撮りたいウィンドウをクリック"
        case .screen: "撮りたい画面をクリック"
        case .scroll: "撮りたいウィンドウのスクロールする部分をクリック（ドラッグで範囲を選ぶこともできる）"
        }
    }

    /// ドラッグで範囲を選ぶモードか
    var selectsRegion: Bool { self == .region || self == .scroll }
}

/// 範囲選択の画面で選んでいるキャプチャの種類とタイマー
@MainActor
final class CaptureOptions: ObservableObject {
    @Published var mode: CaptureMode
    /// 撮るまでの秒数（0 ならすぐ撮る）
    @Published var timer: Int

    static let timerChoices = [0, 3, 5, 10]
    /// ショートカット（「タイマーでキャプチャ」）で撮るときの秒数
    static let shortcutTimerSeconds = 5

    init(mode: CaptureMode, timer: Int) {
        self.mode = mode
        self.timer = timer
    }

    /// タイマーを なし → 3 → 5 → 10 → なし の順に切り替える
    func cycleTimer() {
        let choices = Self.timerChoices
        let index = choices.firstIndex(of: timer) ?? 0
        timer = choices[(index + 1) % choices.count]
    }
}

/// 画面に出ているウィンドウ
struct WindowInfo {
    let id: CGWindowID
    /// スクリーン座標（AppKit、左下が原点）
    let frame: NSRect
    let appName: String
    let title: String
    let ownerPID: pid_t

    var displayName: String {
        title.isEmpty ? appName : "\(appName) — \(title)"
    }
}

/// 範囲選択の画面で選んだもの
enum CaptureTarget {
    /// 範囲（スクリーン座標）
    case region(screen: NSScreen, rect: NSRect)
    case window(WindowInfo)
    case screen(NSScreen)
    /// スクロールしながら撮る範囲（スクリーン座標）。
    /// window と point があるときは、クリックしたウィンドウの、その場所のスクロール領域を撮る（rect は見つからなかったときの範囲）
    case scroll(screen: NSScreen, rect: NSRect, window: WindowInfo?, point: NSPoint?)
}
