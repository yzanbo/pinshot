import AppKit
import SwiftUI

/// 撮った画像の履歴のウィンドウ（縮小画像の一覧）
@MainActor
final class CaptureHistoryWindowController: NSObject, NSWindowDelegate {
    static let shared = CaptureHistoryWindowController()

    private(set) var window: NSWindow?
    private let model = CaptureHistoryViewModel(history: .shared)
    private var keyMonitor: Any?

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: CaptureHistoryView(history: .shared, model: model))
            let window = NSWindow(contentViewController: hosting)
            window.title = "撮った画像の履歴"
            window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
            window.setContentSize(NSSize(width: 720, height: 520))
            window.contentMinSize = NSSize(width: 420, height: 320)
            window.isReleasedWhenClosed = false
            window.setFrameAutosaveName("CaptureHistoryWindow")
            window.delegate = self
            if window.frame.origin == .zero { window.center() }
            self.window = window
        }
        startKeyMonitor()
        // 開いている間に期間を過ぎたものは、開き直したときに消す
        CaptureHistory.shared.pruneExpired()
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        stopKeyMonitor()
        model.clearSelection()
    }

    /// 一覧のキー操作（delete・return・⌘C・⌘A・esc・← →。一覧のウィンドウが前にあるときだけ）
    private func startKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let window = self.window, event.window === window else { return event }
            return self.model.handleKey(event) ? nil : event
        }
    }

    private func stopKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    /// すべての履歴を消す前に確かめる（前にあるウィンドウ（履歴・設定）のシートで出す）
    static func confirmRemoveAll() {
        let history = CaptureHistory.shared
        guard !history.entries.isEmpty else { return }
        AppAlert.confirm(
            "撮った画像の履歴をすべて消しますか？",
            detail: "\(history.entries.count) 枚の画像を消します。元に戻せません（浮かせている画像は消えません）。",
            confirmTitle: "すべて消す"
        ) {
            history.removeAll()
        }
    }
}

