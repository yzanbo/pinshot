import AppKit

/// 履歴の一覧の選択と操作（浮かせる・コピー・保存・Finder・消す）。
/// 選んでいるものがあるときは、選んでいるものすべてに対して行う
@MainActor
final class CaptureHistoryViewModel: ObservableObject {
    let history: CaptureHistory
    /// 選んでいる履歴
    @Published private(set) var selection = ListSelection()
    /// マウスを乗せている 1 枚（乗せている間だけ、操作のボタンを出す）
    @Published var hovered: UUID?
    /// 操作したあとの短い知らせ（「コピーしました」など。文字の一覧と同じ所に出す）
    let notice: HistoryNotice
    /// 縮小画像（読み込んだものを覚えておく）
    private let thumbnails = NSCache<NSUUID, NSImage>()

    init(history: CaptureHistory, notice: HistoryNotice) {
        self.history = history
        self.notice = notice
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

    private var order: [UUID] { history.entries.map(\.id) }

    /// クリックで選ぶ（⌘ で足す・外す、shift で起点からの範囲）
    func click(_ entry: CaptureHistoryEntry, modifiers: NSEvent.ModifierFlags) {
        selection.click(entry.id, command: modifiers.contains(.command), shift: modifiers.contains(.shift), order: order)
    }

    func selectAll() {
        selection.selectAll(order)
    }

    func clearSelection() {
        selection.clear()
    }

    /// ← → で、となりの 1 枚を選ぶ（shift で範囲を広げる）
    func moveSelection(by step: Int, extending: Bool) {
        selection.move(by: step, extending: extending, order: order)
    }

    // MARK: - 操作

    /// 浮かせる（2 枚以上は、少しずつずらして重ねる）
    func pin(_ entries: [CaptureHistoryEntry]) {
        history.pin(entries)
    }

    func copy(_ entry: CaptureHistoryEntry) {
        if history.copy(entry) { show("コピーしました") }
    }

    /// 撮ったときの画像を上げて、共有リンクをコピーする（上げる先は設定の「共有」）
    func upload(_ entry: CaptureHistoryEntry) {
        guard let image = history.loadImage(for: entry) else { return NSSound.beep() }
        UploadCenter.shared.shareImage(image, pointSize: entry.pointSize) { [weak self] status in
            self?.notice.show(status.text, working: status.isWorking)
        }
    }

    /// 画像の文字を読み取ってコピーする
    func copyText(_ entry: CaptureHistoryEntry) {
        guard let image = history.loadImage(for: entry) else { return NSSound.beep() }
        show("文字を読み取っています…")
        Task { @MainActor [weak self] in
            let result = await TextRecognizer.copyText(in: image, pointSize: entry.pointSize)
            self?.show(TextRecognizer.resultMessage(copiedCount: result.text.count))
        }
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
            "選んだ \(entries.count) 枚を履歴から削除しますか？",
            detail: "元に戻せません（浮かせている画像は削除されません）。",
            confirmTitle: "\(entries.count) 枚を削除",
            in: CaptureHistoryWindowController.shared.window
        ) { [weak self] in
            self?.removeNow(entries)
        }
    }

    private func removeNow(_ entries: [CaptureHistoryEntry]) {
        let ids = Set(entries.map(\.id))
        selection.remove(ids)
        history.remove(ids: ids)
        show(entries.count == 1 ? "履歴から削除しました" : "\(entries.count) 枚を履歴から削除しました")
    }

    private func show(_ text: String) {
        notice.show(text)
    }

    // MARK: - キー

    /// 一覧のキー操作。扱ったら true（どのキーで何をするかは ListKeys。リストのときだけ ↑ ↓ でも動かす）
    func handleKey(_ event: NSEvent) -> Bool {
        let isList = AppSettings.shared.historyLayout == .list
        guard let action = ListKeys.action(for: event, horizontal: true, vertical: isList) else { return false }
        let selected = selectedEntries
        switch action {
        case .selectAll:
            selectAll()
        case .move(let step, let extending):
            moveSelection(by: step, extending: extending)
        case .clearSelection:
            guard !selection.isEmpty else { return false }
            clearSelection()
        case .remove:
            guard !selected.isEmpty else { return false }
            remove(selected)
        case .activate:
            guard !selected.isEmpty else { return false }
            pin(selected)
        case .copy:
            guard let first = selected.first else { return false }
            copy(first)
        }
        return true
    }
}
