import AppKit
import Carbon.HIToolbox

/// メニューを開いている間（Pinshot のメニュー・ほかのアプリのメニューバーのメニュー）も、ショートカットを効かせる。
///
/// Carbon のショートカット（HotKey）は、どこかでメニューを開いている間は macOS から届かないことがある。
/// アクセシビリティを許可しているときだけ、キーの入力を横で見て、割り当てたショートカットと同じなら知らせる。
/// 見るのは「ショートカットかどうか」だけで、キーを記録・送信はしない。キーはそのまま元の行き先へ渡す
@MainActor
final class ShortcutKeyTap {
    /// 押されたショートカットを知らせる
    var onShortcut: ((ShortcutAction) -> Void)?
    /// 割り当てたショートカット（AppDelegate が登録し直すたびに入れ替える）
    var shortcuts: [ShortcutAction: Shortcut] = [:]

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var retryTimer: Timer?

    /// アクセシビリティを許可していれば、キーを見始める。まだなら、許可されるまで数秒ごとに試す
    func start() {
        guard tap == nil else { return }
        if install() { return }
        guard retryTimer == nil else { return }
        retryTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.install() else { return }
                self.retryTimer?.invalidate()
                self.retryTimer = nil
            }
        }
    }

    private func install() -> Bool {
        guard AXIsProcessTrusted() else { return false }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                if let userInfo {
                    let keyTap = Unmanaged<ShortcutKeyTap>.fromOpaque(userInfo).takeUnretainedValue()
                    keyTap.received(type: type, event: event)
                }
                // キーは変えずに、そのまま渡す
                return Unmanaged.passUnretained(event)
            },
            userInfo: userInfo
        ) else { return false }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        // メニューを開いている間（イベントを追っているモード）も動くよう、共通のモードに入れる
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        return true
    }

    /// キーが押された（メインスレッドで呼ばれる）
    nonisolated private func received(type: CGEventType, event: CGEvent) {
        let keyCode = UInt32(event.getIntegerValueField(.keyboardEventKeycode))
        let modifiers = Self.carbonModifiers(event.flags)
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        MainActor.assumeIsolated {
            // 長く止まると macOS が止めるので、また動かす
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
                return
            }
            guard type == .keyDown, !isRepeat, modifiers != 0 else { return }
            guard let action = shortcuts.first(where: { $0.value.keyCode == keyCode && $0.value.modifiers == modifiers })?.key else { return }
            onShortcut?(action)
        }
    }

    /// CGEvent の修飾キーを、Shortcut と同じ Carbon の形にする
    nonisolated private static func carbonModifiers(_ flags: CGEventFlags) -> UInt32 {
        var carbon: UInt32 = 0
        if flags.contains(.maskCommand) { carbon |= UInt32(cmdKey) }
        if flags.contains(.maskAlternate) { carbon |= UInt32(optionKey) }
        if flags.contains(.maskControl) { carbon |= UInt32(controlKey) }
        if flags.contains(.maskShift) { carbon |= UInt32(shiftKey) }
        return carbon
    }
}
