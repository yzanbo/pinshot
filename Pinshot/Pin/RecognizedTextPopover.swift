import AppKit
import Combine
import SwiftUI

/// 読み取り終えたときに、読み取った文字を画像の横に吹き出しで見せる。
/// クリップボードにはもう入っているので、見て確かめる・直してからもう一度コピーする・履歴で見る、ができる。
/// 時間では閉じない。初期設定では「閉じる」か esc でだけ閉じる（吹き出しのチェックボックスか設定で、外を押したら閉じるようにもできる）
@MainActor
final class RecognizedTextPopover: NSObject, NSPopoverDelegate {
    private let popover = NSPopover()
    private let model: RecognizedTextPopoverModel
    /// 閉じたとき（持ち主が手放す）
    var onClose: (() -> Void)?
    private var cancellables = Set<AnyCancellable>()

    init(text: String) {
        model = RecognizedTextPopoverModel(text: text)
        super.init()
        model.close = { [weak self] in self?.close() }
        // 外を押しても閉じない（applicationDefined）のが初期設定。外を押したら閉じる（transient）にもできる。
        // 吹き出しのチェックボックスで切り替えたら、出している吹き出しにもすぐ効かせる
        AppSettings.shared.$textPopoverClosesOnOutsideClick
            .sink { [weak self] closes in self?.popover.behavior = closes ? .transient : .applicationDefined }
            .store(in: &cancellables)
        popover.animates = true
        popover.delegate = self
        let hosting = NSHostingController(rootView: RecognizedTextPopoverView(model: model))
        // 吹き出しの大きさを中身の高さぴったりにする（大きく取られると中身が真ん中に置かれ、
        // 下に出したときに、画像と吹き出しの間が空いてしまう）
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting
    }

    var isShown: Bool { popover.isShown }

    /// rect（view の座標）の外の下に出す。下に場所がなければ、macOS が上などに向きを変える
    func show(relativeTo rect: NSRect, of view: NSView) {
        popover.show(relativeTo: rect, of: view, preferredEdge: view.isFlipped ? .maxY : .minY)
        // 直せるように、吹き出しに文字を打てるようにする
        popover.contentViewController?.view.window?.makeKey()
    }

    func close() {
        popover.performClose(nil)
    }

    func popoverDidClose(_ notification: Notification) {
        onClose?()
    }
}

/// 吹き出しの中の状態（直している文字・コピーしたか・更新したか）
@MainActor
final class RecognizedTextPopoverModel: ObservableObject {
    /// 押したあとに、ボタンで短く知らせること
    enum Feedback { case none, copied, updated }

    @Published var text: String
    @Published private(set) var feedback = Feedback.none
    /// 読み取ったときの文字（欄の高さを決める）
    let original: String
    /// いまクリップボードと履歴に入っている文字（直したかどうかは、これと比べる）
    @Published private(set) var savedText: String
    /// 読み取った文字の履歴（残さない設定のときは nil）
    private let entryID: UUID?
    var close: () -> Void = {}
    private var feedbackTask: Task<Void, Never>?

    init(text: String) {
        self.text = text
        original = text
        savedText = text
        entryID = TextHistory.shared.entry(withText: text)?.id
    }

    /// 直したまま、まだ更新していないか
    var isEdited: Bool { text != savedText }
    /// 一度でも直して更新したか
    var wasUpdated: Bool { savedText != original }
    /// 履歴に残っているか（残っていれば、直すと履歴も更新する）
    var hasHistoryEntry: Bool {
        entryID.map { id in TextHistory.shared.entries.contains { $0.id == id } } ?? false
    }

    /// 吹き出しの幅（文字が多いときは広げて、縦に長くなりすぎないようにする）
    var width: CGFloat { original.count > 240 ? 500 : 380 }
    /// 文字の欄の高さの上限（超えたらスクロール）
    private let maxEditorHeight: CGFloat = 300
    /// 文字の欄の余白（EditableText のまわりの padding）
    static let editorPadding: CGFloat = 6

    /// 文字を全部見せるのに要る、文字の欄の高さ（折り返しも含めて測る）
    private var fittingEditorHeight: CGFloat {
        let boxWidth = width - 14 * 2 - Self.editorPadding * 2
        return EditableText.fittingHeight(for: text, width: boxWidth) + Self.editorPadding * 2
    }

    /// 文字の欄の高さ（文字に合わせる。多いときは上限で止めてスクロール）
    var editorHeight: CGFloat { min(max(fittingEditorHeight, 56), maxEditorHeight) }
    /// 欄に収まらず、スクロールしないと全部見えないか
    var needsScroll: Bool { fittingEditorHeight > maxEditorHeight }

    /// コピーする。直していれば、履歴の文字も直したものに更新してからコピーする
    func copy() {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return NSSound.beep() }
        let edited = isEdited
        let history = TextHistory.shared
        if edited, let entryID, hasHistoryEntry {
            history.replaceText(of: entryID, with: text)
        }
        history.copy(text)
        savedText = text
        feedback = edited ? .updated : .copied
        feedbackTask?.cancel()
        feedbackTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled else { return }
            self?.feedback = .none
        }
    }

    /// 履歴のウィンドウで、この文字を選んで見せる
    func showInHistory() {
        close()
        CaptureHistoryWindowController.shared.show(tab: .texts, selecting: entryID)
    }
}

private struct RecognizedTextPopoverView: View {
    @ObservedObject var model: RecognizedTextPopoverModel
    @ObservedObject var settings = AppSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label("読み取った文字", systemImage: "text.viewfinder")
                    .font(.headline)
                // 多いときは、スクロールで続きがあることも出す
                Text(TextHistoryRules.countText(model.text) + (model.needsScroll ? "・スクロールで続き" : ""))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                // すぐ閉じるか（外を押したら閉じるか）を、吹き出しからも切り替えられるようにする（設定の「画像」と同じもの）
                Toggle("外を押したら閉じる", isOn: $settings.textPopoverClosesOnOutsideClick)
                    .toggleStyle(.checkbox)
                    .controlSize(.small)
                    .font(.caption)
                    .fixedSize()
                    .hoverHint("オンにすると、吹き出しの外を押したときに閉じる。オフなら「閉じる」か esc で閉じるまで出したまま（設定の「画像」と同じ）")
                    .hoverRole()
            }
            // 背景は透けない色にする（吹き出しは半透明なので、そのままだと後ろの画像が透けて読みにくい）
            EditableText(text: $model.text, extraMenuItems: [
                EditableTextMenuItem(title: "全文をコピー", symbol: "doc.on.doc") { model.copy() },
            ])
                .padding(RecognizedTextPopoverModel.editorPadding)
                .frame(height: model.editorHeight)
                .framedBox(fill: Color(nsColor: .textBackgroundColor))
            status
            HStack(spacing: 8) {
                if model.hasHistoryEntry {
                    // リンクの形（青い細い文字）は、半透明の吹き出しの上では読みにくいので、ふつうのボタンにする
                    Button { model.showInHistory() } label: {
                        Label("履歴で見る", systemImage: "clock.arrow.circlepath")
                    }
                    .hoverHint("文字の履歴を開いて、この文字を選ぶ")
                    .hoverRole()
                }
                Spacer(minLength: 8)
                Button("閉じる") { model.close() }
                    .keyboardShortcut(.cancelAction)
                    .hoverRole()
                Button { model.copy() } label: {
                    Label(copyTitle, systemImage: copySymbol)
                        .frame(minWidth: 120)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .hoverHint(model.isEdited && model.hasHistoryEntry ? "履歴の文字を直した文字に更新して、コピーする（⌘↩）" : "コピー（⌘↩）")
                .hoverRole()
            }
        }
        .padding(14)
        .frame(width: model.width)
        .fixedSize(horizontal: false, vertical: true)
        .animation(.easeOut(duration: 0.15), value: model.feedback)
        .animation(.easeOut(duration: 0.15), value: model.isEdited)
    }

    /// ボタンの名前（直したら「更新してコピー」。押した直後は、したことを出す）
    private var copyTitle: String {
        switch model.feedback {
        case .updated: return "更新しました"
        case .copied: return "コピーしました"
        case .none:
            guard model.isEdited else { return "コピー" }
            return model.hasHistoryEntry ? "更新してコピー" : "直してコピー"
        }
    }

    private var copySymbol: String {
        if model.feedback != .none { return "checkmark" }
        return model.isEdited ? "arrow.triangle.2.circlepath" : "doc.on.doc"
    }

    /// いまの状態（コピー済み・直している途中・更新済み）
    @ViewBuilder
    private var status: some View {
        let history = model.hasHistoryEntry
        if model.isEdited {
            EditStatusLine(
                text: history ? "直しています。「更新してコピー」で、履歴とクリップボードを直した文字にします" : "直しています。「直してコピー」で、直した文字をクリップボードに入れます",
                symbol: "pencil.circle.fill",
                tint: .orange
            )
        } else if model.wasUpdated {
            EditStatusLine(text: history ? "履歴とクリップボードを、直した文字に更新しました" : "直した文字をクリップボードに入れました", symbol: "checkmark.circle.fill", tint: .green)
        } else {
            EditStatusLine(text: history ? "クリップボードにコピーしました。直すと、履歴も更新できます" : "クリップボードにコピーしました。直してからコピーし直せます", symbol: "checkmark.circle.fill", tint: .green)
        }
    }
}
