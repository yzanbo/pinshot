import AppKit
import Carbon.HIToolbox

/// ショートカットを割り当てられる操作
enum ShortcutAction: String, CaseIterable, Identifiable {
    case captureRegion
    case captureWindow
    case captureScreen
    case captureTimer
    /// 範囲を選んで録画する（クリックでウィンドウ・画面全体も選べる。録画中は、止める）。
    /// 名前は前の版の設定（割り当てたショートカット）を引き継ぐため、そのままにする
    case recordScreen
    /// ウィンドウをクリックで選んで録画する
    case recordWindow
    /// マウスのある画面全体を、範囲を選ばずに録画する
    case recordFullScreen
    /// タイマー（5 秒）で、範囲を選んで録画する
    case recordTimer
    case pinClipboard
    case openHistory
    case restoreClosed
    case bringAllToFront
    case closeAll

    var id: String { rawValue }

    var label: String {
        switch self {
        case .captureRegion: "範囲をキャプチャ"
        case .captureWindow: "ウィンドウをキャプチャ"
        case .captureScreen: "画面全体をキャプチャ"
        case .captureTimer: "タイマーでキャプチャ（5 秒）"
        case .recordScreen: "範囲を録画"
        case .recordWindow: "ウィンドウを録画"
        case .recordFullScreen: "画面全体を録画"
        case .recordTimer: "タイマーで録画（5 秒）"
        case .pinClipboard: "クリップボードの画像を浮かせる"
        case .openHistory: "撮った画像の履歴…"
        case .restoreClosed: "閉じた画像を戻す"
        case .bringAllToFront: "すべての画像を前に出す"
        case .closeAll: "すべての画像を閉じる"
        }
    }

    /// メニュー・設定で、まとめて見せる組
    static let captureActions: [ShortcutAction] = [.captureRegion, .captureWindow, .captureScreen, .captureTimer]
    /// 録画（キャプチャとは分けて見せる）
    static let recordActions: [ShortcutAction] = [.recordScreen, .recordWindow, .recordFullScreen, .recordTimer]
    /// 画面を撮る・録る操作（メニューを開いたまま押したときは、メニューを閉じずに始める。開いたメニューも写るように。
    /// ほかの操作は、メニューを閉じてから行う）
    static var screenActions: [ShortcutAction] { captureActions + recordActions }
    static let pinActions: [ShortcutAction] = [.pinClipboard, .restoreClosed, .bringAllToFront, .closeAll]
    static let historyActions: [ShortcutAction] = [.openHistory]

    /// メニュー・設定に出すアイコン（キャプチャの種類は、範囲選択の画面のモードバーと同じもの）
    var symbolName: String {
        switch self {
        case .captureRegion: CaptureMode.region.symbolName
        case .captureWindow: CaptureMode.window.symbolName
        case .captureScreen: CaptureMode.screen.symbolName
        case .captureTimer: "timer"
        case .recordScreen: CaptureMode.record.symbolName
        case .recordWindow: CaptureMode.window.symbolName
        case .recordFullScreen: CaptureMode.screen.symbolName
        case .recordTimer: "timer"
        case .pinClipboard: "doc.on.clipboard"
        case .openHistory: "clock.arrow.circlepath"
        case .restoreClosed: "arrow.uturn.backward"
        case .bringAllToFront: "square.3.layers.3d.top.filled"
        case .closeAll: "xmark.circle"
        }
    }

    /// 初期設定のショートカット（範囲だけ ⌘⇧2）
    var defaultShortcut: Shortcut? {
        self == .captureRegion ? .default : nil
    }
}

/// キーボードショートカット（Carbon のキーコードと修飾キー）
struct Shortcut: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    /// 表示用のキーの名前（例: "2"）
    var key: String

    static let `default` = Shortcut(keyCode: UInt32(kVK_ANSI_2), modifiers: UInt32(cmdKey | shiftKey), key: "2")

    /// 修飾キーの対応（Carbon の値・AppKit の値・表示の記号）。並びは表示の順（⌃⌥⇧⌘）
    private static let modifierTable: [(carbon: UInt32, flag: NSEvent.ModifierFlags, symbol: String)] = [
        (UInt32(controlKey), .control, "⌃"),
        (UInt32(optionKey), .option, "⌥"),
        (UInt32(shiftKey), .shift, "⇧"),
        (UInt32(cmdKey), .command, "⌘"),
    ]

    /// AppKit の修飾キーを、Carbon の値にする
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        modifierTable.reduce(0) { flags.contains($1.flag) ? $0 | $1.carbon : $0 }
    }

    /// 例: "⇧⌘2"
    var displayString: String {
        Self.modifierTable.filter { modifiers & $0.carbon != 0 }.map(\.symbol).joined() + key
    }

    /// メニューに表示するための修飾キー
    var menuModifierMask: NSEvent.ModifierFlags {
        Self.modifierTable.reduce(into: []) { flags, entry in
            if modifiers & entry.carbon != 0 { flags.insert(entry.flag) }
        }
    }

    /// キーを押したイベントからショートカットを作る。⌘・⌥・⌃ のどれも押していなければ nil
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard !flags.intersection([.command, .option, .control]).isEmpty else { return nil }
        self.init(
            keyCode: UInt32(event.keyCode),
            modifiers: Shortcut.carbonModifiers(from: flags),
            key: Shortcut.keyName(for: event.keyCode)
        )
    }

    init(keyCode: UInt32, modifiers: UInt32, key: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.key = key
    }

    private static let specialKeys: [UInt16: String] = [
        UInt16(kVK_Space): "Space", UInt16(kVK_Return): "↩", UInt16(kVK_Tab): "⇥",
        UInt16(kVK_Delete): "⌫", UInt16(kVK_ForwardDelete): "⌦", UInt16(kVK_Escape): "⎋",
        UInt16(kVK_LeftArrow): "←", UInt16(kVK_RightArrow): "→",
        UInt16(kVK_DownArrow): "↓", UInt16(kVK_UpArrow): "↑",
        UInt16(kVK_F1): "F1", UInt16(kVK_F2): "F2", UInt16(kVK_F3): "F3", UInt16(kVK_F4): "F4",
        UInt16(kVK_F5): "F5", UInt16(kVK_F6): "F6", UInt16(kVK_F7): "F7", UInt16(kVK_F8): "F8",
        UInt16(kVK_F9): "F9", UInt16(kVK_F10): "F10", UInt16(kVK_F11): "F11", UInt16(kVK_F12): "F12",
    ]

    /// キーコードから、いまのキーボード配列でのキーの名前を得る（shift などを押していない状態の文字）
    static func keyName(for keyCode: UInt16) -> String {
        if let name = specialKeys[keyCode] { return name }
        guard
            let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
            let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return "?" }

        let layoutData = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var characters = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = layoutData.withUnsafeBytes { raw -> OSStatus in
            guard let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return OSStatus(paramErr) }
            return UCKeyTranslate(
                layout,
                keyCode,
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                characters.count,
                &length,
                &characters
            )
        }
        guard status == noErr, length > 0 else { return "?" }
        return String(utf16CodeUnits: characters, count: length).uppercased()
    }
}
