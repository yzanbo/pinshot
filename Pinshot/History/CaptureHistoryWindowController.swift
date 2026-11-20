import AppKit
import SwiftUI

/// 履歴のウィンドウ（撮った画像・読み取った文字・上げたものの一覧）
@MainActor
final class CaptureHistoryWindowController: NSObject, NSWindowDelegate {
    static let shared = CaptureHistoryWindowController()

    private(set) var window: NSWindow?
    private let state = HistoryWindowState()
    private let notice = HistoryNotice()
    private lazy var imageModel = CaptureHistoryViewModel(history: .shared, notice: notice)
    private lazy var textModel = TextHistoryViewModel(history: .shared, notice: notice)
    private lazy var uploadModel = UploadHistoryViewModel(history: .shared, notice: notice)
    private var keyMonitor: Any?

    /// ウィンドウを開いて、tab の一覧を見せる（selecting を渡すと、文字の一覧でその 1 件を選ぶ）
    func show(tab: HistoryTab = .images, selecting id: UUID? = nil) {
        state.tab = tab
        if tab == .texts, let id { textModel.reveal(id) }
        if window == nil {
            let view = HistoryWindowView(state: state, notice: notice, imageModel: imageModel, textModel: textModel, uploadModel: uploadModel)
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "履歴"
            window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
            window.setContentSize(NSSize(width: 720, height: 520))
            window.contentMinSize = NSSize(width: 460, height: 340)
            window.isReleasedWhenClosed = false
            window.setFrameAutosaveName("CaptureHistoryWindow")
            window.delegate = self
            if window.frame.origin == .zero { window.center() }
            self.window = window
        }
        startKeyMonitor()
        // 開いている間に期間を過ぎたものは、開き直したときに消す
        CaptureHistory.shared.pruneExpired()
        TextHistory.shared.pruneExpired()
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        stopKeyMonitor()
        imageModel.clearSelection()
        textModel.clearSelection()
        uploadModel.clearSelection()
        textModel.discardDrafts()
    }

    /// 一覧のキー操作（delete・return・⌘C・⌘A・esc・矢印。一覧のウィンドウが前にあるときだけ）。
    /// 探す欄に打っている間は、欄に任せる
    private func startKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let window = self.window, event.window === window,
                  !(window.firstResponder is NSText) else { return event }
            let handled = switch self.state.tab {
            case .images: self.imageModel.handleKey(event)
            case .texts: self.textModel.handleKey(event)
            case .uploads: self.uploadModel.handleKey(event)
            }
            return handled ? nil : event
        }
    }

    private func stopKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    /// 撮った画像の履歴をすべて消す前に確かめる（前にあるウィンドウ（履歴・設定）のシートで出す）
    static func confirmRemoveAll() {
        let history = CaptureHistory.shared
        guard !history.entries.isEmpty else { return }
        AppAlert.confirm(
            "撮った画像の履歴をすべて削除しますか？",
            detail: "\(history.entries.count) 枚の画像を削除します。元に戻せません（浮かせている画像は削除されません）。",
            confirmTitle: "すべて削除"
        ) {
            history.removeAll()
        }
    }

    /// 読み取った文字の履歴をすべて消す前に確かめる
    static func confirmRemoveAllTexts() {
        let history = TextHistory.shared
        guard !history.entries.isEmpty else { return }
        AppAlert.confirm(
            "読み取った文字の履歴をすべて削除しますか？",
            detail: "\(history.entries.count) 件の文字を削除します。元に戻せません。",
            confirmTitle: "すべて削除"
        ) {
            history.removeAll()
        }
    }
}
