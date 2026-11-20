import AppKit

/// 読み取った文字の一覧の選択と操作（コピー・消す・探す・直す）。
/// 選んでいるものがあるときは、選んでいるものすべてに対して行う。1 件だけ選んでいるときは、右の欄で直せる
@MainActor
final class TextHistoryViewModel: ObservableObject {
    let history: TextHistory
    /// 選んでいる履歴
    @Published private(set) var selection = ListSelection() {
        didSet { syncDraft() }
    }
    /// 右の欄で直している文字（1 件だけ選んでいるとき）。直しただけでは保存せず、「更新してコピー」で保存する
    @Published var draft = "" {
        didSet { draftDidChange() }
    }
    /// 「更新してコピー」で、直した文字に更新したあとか（直し直すまで「更新しました」を出す）
    @Published private(set) var didUpdate = false
    /// まだ更新していない、直している途中の文字（履歴ごと）。ほかを選んで戻っても続きから直せるよう、ウィンドウを閉じるまで覚える
    @Published private(set) var pendingDrafts: [UUID: String] = [:]
    /// マウスを乗せている 1 件（乗せている間だけ、操作のボタンを出す）
    @Published var hovered: UUID?
    /// 探す文字（空なら全部）
    @Published var query = ""
    /// 操作したあとの短い知らせ（画像の一覧と同じ所に出す）
    let notice: HistoryNotice

    /// 右の欄で直している履歴
    private(set) var editingID: UUID?
    /// 履歴の文字を draft に読み込んでいる間（直している途中の文字として覚えない）
    private var isLoadingDraft = false
    /// 読み取った範囲の画像（読み込んだものを覚えておく）
    private let images = NSCache<NSUUID, NSImage>()

    init(history: TextHistory, notice: HistoryNotice) {
        self.history = history
        self.notice = notice
    }

    /// 一覧に出す履歴（探す文字で絞ったもの。新しい順）
    var visibleEntries: [RecognizedTextEntry] {
        TextHistoryRules.filtered(history.entries, query: query)
    }

    /// 選んでいる履歴（新しい順。絞って見えなくなったものは除く）
    var selectedEntries: [RecognizedTextEntry] {
        visibleEntries.filter { selection.contains($0.id) }
    }

    /// entry に対する操作の対象（entry を選んでいれば、選んでいるものすべて。そうでなければ entry だけ）
    func targets(for entry: RecognizedTextEntry) -> [RecognizedTextEntry] {
        selection.contains(entry.id) ? selectedEntries : [entry]
    }

    // MARK: - 選ぶ

    private var order: [UUID] { visibleEntries.map(\.id) }

    /// クリックで選ぶ（⌘ で足す・外す、shift で起点からの範囲）
    func click(_ entry: RecognizedTextEntry, modifiers: NSEvent.ModifierFlags) {
        selection.click(entry.id, command: modifiers.contains(.command), shift: modifiers.contains(.shift), order: order)
    }

    func selectAll() {
        selection.selectAll(order)
    }

    func clearSelection() {
        selection.clear()
    }

    /// 探す文字を空にして、その 1 件だけを選ぶ（吹き出しの「履歴で見る」から）
    func reveal(_ id: UUID) {
        query = ""
        selection.clear()
        selection.click(id, command: false, shift: false, order: order)
    }

    // MARK: - 直す（吹き出しと同じく、「更新してコピー」で保存する）

    /// 1 件だけ選んだら、その文字を右の欄に読み込む（直している途中のものがあれば、その続きから）
    private func syncDraft() {
        let id = selection.selected.count == 1 ? selection.selected.first : nil
        guard id != editingID else { return }
        editingID = id
        isLoadingDraft = true
        draft = id.flatMap { pendingDrafts[$0] ?? savedText(of: $0) } ?? ""
        isLoadingDraft = false
        didUpdate = false
    }

    /// 直したら、更新するまで覚えておく（元に戻したら、直している途中ではなくなる）
    private func draftDidChange() {
        guard !isLoadingDraft, let id = editingID else { return }
        didUpdate = false
        if draft == savedText(of: id) {
            pendingDrafts.removeValue(forKey: id)
        } else {
            pendingDrafts[id] = draft
        }
    }

    private func savedText(of id: UUID) -> String? {
        history.entries.first { $0.id == id }?.text
    }

    /// 右の欄の文字を直していて、まだ更新していないか
    var isDraftEdited: Bool {
        editingID.map { pendingDrafts[$0] != nil } ?? false
    }

    /// 直している途中の履歴か（一覧に「編集中」と出す）
    func hasPendingDraft(_ id: UUID) -> Bool {
        pendingDrafts[id] != nil
    }

    /// 直している文字が空か（空のままでは更新できないことを知らせる）
    var draftIsEmpty: Bool {
        editingID != nil && draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 右の欄の「コピー」。直していれば、履歴の文字を直したものに更新してからコピーする（「更新してコピー」）
    func copyDraft() {
        guard let id = editingID else { return }
        guard !draftIsEmpty else { return NSSound.beep() }
        let edited = isDraftEdited
        if edited {
            history.replaceText(of: id, with: draft)
            pendingDrafts.removeValue(forKey: id)
        }
        history.copy(draft)
        didUpdate = edited || didUpdate
        notice.show(edited ? "更新してコピーしました" : "コピーしました")
    }

    /// 直している途中の文字を捨てる（ウィンドウを閉じたとき）
    func discardDrafts() {
        pendingDrafts.removeAll()
    }

    // MARK: - 読み取った範囲の画像

    func image(for entry: RecognizedTextEntry) -> NSImage? {
        if let cached = images.object(forKey: entry.id as NSUUID) { return cached }
        // 書き終える前は nil（覚えずに、次に描くときにもう一度読む）
        guard let image = history.image(for: entry) else { return nil }
        images.setObject(image, forKey: entry.id as NSUUID)
        return image
    }

    /// 読み取った範囲の画像を、もう一度浮かせる
    func pinImage(of entry: RecognizedTextEntry) {
        history.pinImage(of: entry)
    }

    /// 読み取った範囲の画像を、クリップボードにコピーする
    func copyImage(of entry: RecognizedTextEntry) {
        if history.copyImage(of: entry) { notice.show("画像をコピーしました") }
    }

    // MARK: - 操作

    /// 履歴の文字をコピーする（2 件以上は、空の行をはさんでつなぐ。直している途中の文字ではなく、保存してある文字）
    func copy(_ entries: [RecognizedTextEntry]) {
        let ids = Set(entries.map(\.id))
        let entries = history.entries.filter { ids.contains($0.id) }
        guard !entries.isEmpty else { return }
        history.copy(TextHistoryRules.joined(entries))
        notice.show(entries.count == 1 ? "コピーしました" : "\(entries.count) 件をつなげてコピーしました")
    }

    /// 履歴から消す（2 件以上のときは確かめる）
    func remove(_ entries: [RecognizedTextEntry]) {
        guard !entries.isEmpty else { return }
        guard entries.count > 1 else { return removeNow(entries) }
        AppAlert.confirm(
            "選んだ \(entries.count) 件を履歴から削除しますか？",
            detail: "元に戻せません。",
            confirmTitle: "\(entries.count) 件を削除",
            in: CaptureHistoryWindowController.shared.window
        ) { [weak self] in
            self?.removeNow(entries)
        }
    }

    private func removeNow(_ entries: [RecognizedTextEntry]) {
        let ids = Set(entries.map(\.id))
        selection.remove(ids)
        ids.forEach { pendingDrafts.removeValue(forKey: $0) }
        history.remove(ids: ids)
        notice.show(entries.count == 1 ? "履歴から削除しました" : "\(entries.count) 件を履歴から削除しました")
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
        case KeyCode.downArrow, KeyCode.upArrow:
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
            copy(selected)
            return true
        default:
            if flags == .command, key == "c" {
                copy(selected)
                return true
            }
            return false
        }
    }
}
