import AppKit

/// 履歴の一覧の選択と操作（浮かせる・コピー・保存・Finder・消す）。
/// 選んでいるものがあるときは、選んでいるものすべてに対して行う
@MainActor
final class CaptureHistoryViewModel: ObservableObject {
    let history: CaptureHistory
    /// 選んでいる履歴
    @Published private(set) var selection: Set<UUID> = []
    /// マウスを乗せている 1 枚（乗せている間だけ、操作のボタンを出す）
    @Published var hovered: UUID?
    /// 操作したあとの短い知らせ（「コピーしました」など）
    @Published private(set) var notice: String?

    /// shift + クリックで範囲を選ぶときの、起点の 1 枚
    private var anchor: UUID?
    private var noticeTask: Task<Void, Never>?
    /// 縮小画像（読み込んだものを覚えておく）
    private let thumbnails = NSCache<NSUUID, NSImage>()

    init(history: CaptureHistory) {
        self.history = history
    }

    /// 選んでいる履歴（新しい順）
    var selectedEntries: [CaptureHistoryEntry] {
        history.entries.filter { selection.contains($0.id) }
    }

    /// entry に対する操作の対象（entry を選んでいれば、選んでいるものすべて。そうでなければ entry だけ）
    func targets(for entry: CaptureHistoryEntry) -> [CaptureHistoryEntry] {
        selection.contains(entry.id) ? selectedEntries : [entry]
    }

    func thumbnail(for entry: CaptureHistoryEntry) -> NSImage? {
        if let cached = thumbnails.object(forKey: entry.id as NSUUID) { return cached }
        guard let image = history.thumbnailImage(for: entry) else { return nil }
        thumbnails.setObject(image, forKey: entry.id as NSUUID)
        return image
    }

    // MARK: - 選ぶ

    /// クリックで選ぶ（⌘ で足す・外す、shift で起点からの範囲）
    func click(_ entry: CaptureHistoryEntry, modifiers: NSEvent.ModifierFlags) {
        if modifiers.contains(.shift), let anchor, let range = range(from: anchor, to: entry.id) {
            selection = modifiers.contains(.command) ? selection.union(range) : range
            return
        }
        if modifiers.contains(.command) {
            if selection.contains(entry.id) { selection.remove(entry.id) } else { selection.insert(entry.id) }
        } else {
            selection = [entry.id]
        }
        anchor = entry.id
    }

    func selectAll() {
        selection = Set(history.entries.map(\.id))
    }

    func clearSelection() {
        selection = []
        anchor = nil
    }

    /// ← → で、となりの 1 枚を選ぶ（shift で範囲を広げる）
    func moveSelection(by step: Int, extending: Bool) {
        let ids = history.entries.map(\.id)
        guard !ids.isEmpty else { return }
        let current = anchor.flatMap { ids.firstIndex(of: $0) }
        let next = current.map { min(max($0 + step, 0), ids.count - 1) } ?? (step > 0 ? 0 : ids.count - 1)
        if extending, let start = current {
            let lower = min(start, next), upper = max(start, next)
            selection.formUnion(ids[lower...upper])
        } else {
            selection = [ids[next]]
        }
        anchor = ids[next]
    }

    private func range(from start: UUID, to end: UUID) -> Set<UUID>? {
        let ids = history.entries.map(\.id)
        guard let a = ids.firstIndex(of: start), let b = ids.firstIndex(of: end) else { return nil }
        return Set(ids[min(a, b)...max(a, b)])
    }

    // MARK: - 操作

    /// 浮かせる（2 枚以上は、少しずつずらして重ねる）
    func pin(_ entries: [CaptureHistoryEntry]) {
        history.pin(entries)
    }

    func copy(_ entry: CaptureHistoryEntry) {
        if history.copy(entry) { show("コピーしました") }
    }

    /// 保存する（1 枚は保存の設定に合わせる。2 枚以上は、保存先のフォルダにまとめて書く）
    func save(_ entries: [CaptureHistoryEntry]) {
        let files = entries.compactMap { entry -> (data: Data, name: String)? in
            guard let data = try? Data(contentsOf: history.imageURL(for: entry)) else { return nil }
            return (data, ImageExporter.fileName(for: entry.date))
        }
        guard !files.isEmpty else { return NSSound.beep() }
        if files.count == 1 {
            ImageSaver.save(files[0].data, suggestedName: files[0].name) { [weak self] in self?.show("保存しました") }
        } else {
            ImageSaver.saveAll(files) { [weak self] count in self?.show("\(count) 枚を保存しました") }
        }
    }

    func revealInFinder(_ entries: [CaptureHistoryEntry]) {
        NSWorkspace.shared.activateFileViewerSelecting(entries.map { history.imageURL(for: $0) })
    }

    /// 履歴から消す（2 枚以上のときは確かめる）
    func remove(_ entries: [CaptureHistoryEntry]) {
        guard !entries.isEmpty else { return }
        guard entries.count > 1 else { return removeNow(entries) }
        AppAlert.confirm(
            "選んだ \(entries.count) 枚を履歴から消しますか？",
            detail: "元に戻せません（浮かせている画像は消えません）。",
            confirmTitle: "\(entries.count) 枚を消す",
            in: CaptureHistoryWindowController.shared.window
        ) { [weak self] in
            self?.removeNow(entries)
        }
    }

    private func removeNow(_ entries: [CaptureHistoryEntry]) {
        let ids = Set(entries.map(\.id))
        selection.subtract(ids)
        if let anchor, ids.contains(anchor) { self.anchor = nil }
        history.remove(ids: ids)
        show(entries.count == 1 ? "履歴から消しました" : "\(entries.count) 枚を履歴から消しました")
    }

    /// 短い知らせを出す（少したつと消える）
    private func show(_ text: String) {
        notice = text
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled else { return }
            self?.notice = nil
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
        case KeyCode.leftArrow:
            moveSelection(by: -1, extending: flags.contains(.shift))
            return true
        case KeyCode.rightArrow:
            moveSelection(by: 1, extending: flags.contains(.shift))
            return true
        case KeyCode.downArrow, KeyCode.upArrow where AppSettings.shared.historyLayout == .list: // リストのときは ↓ ↑ でも動かす
            moveSelection(by: event.keyCode == KeyCode.downArrow ? 1 : -1, extending: flags.contains(.shift))
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
            pin(selected)
            return true
        default:
            if flags == .command, key == "c", let first = selected.first {
                copy(first)
                return true
            }
            return false
        }
    }
}
