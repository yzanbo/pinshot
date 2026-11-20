import AppKit

/// 上げたものの一覧の選択と操作（リンクをコピー・ブラウザで開く・削除）。
/// 選び方は、撮った画像・読み取った文字の一覧と同じ（クリック・⌘ + クリック・shift + クリック・⌘A・矢印キー）。
/// 選んでいるものがあるときは、選んでいるものすべてに対して行う
@MainActor
final class UploadHistoryViewModel: ObservableObject {
    let history: UploadHistory
    @Published private(set) var selection = ListSelection()
    /// マウスを乗せている 1 件
    @Published var hovered: UUID?
    let notice: HistoryNotice
    /// 縮小画像（読み込んだものを覚えておく）
    private let thumbnails = NSCache<NSUUID, NSImage>()

    init(history: UploadHistory, notice: HistoryNotice) {
        self.history = history
        self.notice = notice
    }

    /// 選んでいるもの（新しい順）
    var selectedEntries: [UploadHistoryEntry] {
        history.entries.filter { selection.contains($0.id) }
    }

    /// entry に対する操作の対象（entry を選んでいれば、選んでいるものすべて。そうでなければ entry だけ）
    func targets(for entry: UploadHistoryEntry) -> [UploadHistoryEntry] {
        selection.contains(entry.id) ? selectedEntries : [entry]
    }

    func thumbnail(for entry: UploadHistoryEntry) -> NSImage? {
        if let cached = thumbnails.object(forKey: entry.id as NSUUID) { return cached }
        guard let image = history.thumbnail(for: entry) else { return nil }
        thumbnails.setObject(image, forKey: entry.id as NSUUID)
        return image
    }

    // MARK: - 選ぶ

    private var order: [UUID] { history.entries.map(\.id) }

    func click(_ entry: UploadHistoryEntry, modifiers: NSEvent.ModifierFlags) {
        selection.click(entry.id, command: modifiers.contains(.command), shift: modifiers.contains(.shift), order: order)
    }

    func selectAll() {
        selection.selectAll(order)
    }

    func clearSelection() {
        selection.clear()
    }

    // MARK: - 操作

    /// リンクを format の形でコピーする（2 件以上は、1 行に 1 つずつ並べる）
    func copyLinks(_ entries: [UploadHistoryEntry], format: ShareLinkFormat) {
        guard !entries.isEmpty else { return }
        history.copyLinks(of: entries, format: format)
        notice.show(entries.count == 1 ? "コピーしました" : "\(entries.count) 件のリンクをコピーしました")
    }

    /// ブラウザで開く（たくさん開きすぎないよう、10 件まで）
    func openInBrowser(_ entries: [UploadHistoryEntry]) {
        entries.prefix(10).forEach(history.openInBrowser)
    }

    /// 削除する。上げる先からも消すか、一覧から外すだけかを選んでもらう
    func remove(_ entries: [UploadHistoryEntry]) {
        guard !entries.isEmpty else { return }
        let labels = Array(Set(entries.map(\.destination.label))).sorted().joined(separator: "・")
        let deletable = entries.filter { UploadDestinations.destination(for: $0.destination)?.capabilities.canDelete ?? false }
        let count = entries.count == 1 ? "このリンク" : "\(entries.count) 件のリンク"

        // ほかのダイアログと同じ見た目にする（AppAlert。最初の選択肢が青い決定ボタン、キャンセルは esc）
        let detail = deletable.isEmpty
            ? "この一覧から外します（\(labels) の画像は、そのまま残ります）。"
            : "「\(labels) からも削除」を選ぶと、\(labels) の画像も消え、リンクを開いても見られなくなります。元に戻せません。\n「一覧から外すだけ」なら、\(labels) の画像は残ります。"
        let choices = deletable.isEmpty ? ["一覧から外す"] : ["\(labels) からも削除", "一覧から外すだけ"]
        AppAlert.choose(
            "\(count)を削除しますか？",
            detail: detail,
            choices: choices,
            in: CaptureHistoryWindowController.shared.window
        ) { [weak self] index in
            let fromDestination = !deletable.isEmpty && index == 0
            self?.removeNow(entries, fromDestination: fromDestination, labels: labels)
        }
    }

    private func removeNow(_ entries: [UploadHistoryEntry], fromDestination: Bool, labels: String) {
        if fromDestination { notice.show("\(labels) から削除しています…") }
        Task {
            do {
                try await history.remove(entries, fromDestination: fromDestination)
                selection.remove(Set(entries.map(\.id)))
                notice.show(fromDestination ? "\(labels) からも削除しました" : "一覧から外しました")
            } catch {
                // 消せたものは一覧から外れ、消せなかったものは残る
                selection.remove(Set(entries.map(\.id)).subtracting(history.entries.map(\.id)))
                AppAlert.inform("\(labels) から削除できなかったものがあります", detail: error.localizedDescription)
            }
        }
    }

    // MARK: - キー

    /// 一覧のキー操作。扱ったら true
    func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let key = event.charactersIgnoringModifiers?.lowercased()
        if flags == .command, key == "a" {
            selectAll()
            return true
        }
        switch event.keyCode {
        case KeyCode.leftArrow, KeyCode.rightArrow:
            selection.move(by: event.keyCode == KeyCode.rightArrow ? 1 : -1, extending: flags.contains(.shift), order: order)
            return true
        case KeyCode.downArrow, KeyCode.upArrow where AppSettings.shared.uploadHistoryLayout == .list: // リストのときは ↓ ↑ でも動かす
            selection.move(by: event.keyCode == KeyCode.downArrow ? 1 : -1, extending: flags.contains(.shift), order: order)
            return true
        case KeyCode.escape:
            guard !selection.isEmpty else { return false }
            clearSelection()
            return true
        default:
            break
        }
        let selected = selectedEntries
        guard !selected.isEmpty else { return false }
        switch event.keyCode {
        case KeyCode.delete, KeyCode.forwardDelete:
            remove(selected)
            return true
        case KeyCode.return, KeyCode.keypadEnter:
            openInBrowser(selected)
            return true
        default:
            if flags == .command, key == "c" {
                copyLinks(selected, format: AppSettings.shared.shareLinkFormat)
                return true
            }
            return false
        }
    }
}
