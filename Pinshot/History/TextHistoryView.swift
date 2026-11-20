import SwiftUI

/// 読み取った文字の履歴の一覧。日付ごとに、読み取った文字を並べる（探す欄は、ウィンドウの上の帯）
struct TextHistoryView: View {
    @ObservedObject var history: TextHistory
    @ObservedObject var model: TextHistoryViewModel
    @ObservedObject var settings = AppSettings.shared

    var body: some View {
        VStack(spacing: 0) {
            if history.entries.isEmpty {
                emptyState
            } else if model.visibleEntries.isEmpty {
                HistoryEmptyState(
                    symbol: "magnifyingglass",
                    title: "見つかりませんでした",
                    message: "「\(model.query)」を含む文字はありません。"
                )
            } else {
                // 左に一覧、右に選んだ文字の全文（間の線はドラッグで動かせる）
                HSplitView {
                    list
                        .frame(minWidth: 260, idealWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
                    TextHistoryDetail(model: model)
                        .frame(minWidth: 220, idealWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            Divider()
            footer
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: rowSpacing, pinnedViews: [.sectionHeaders]) {
                ForEach(CaptureHistoryRules.groupedByDay(model.visibleEntries), id: \.day) { group in
                    Section {
                        ForEach(group.entries) { entry in
                            TextHistoryRow(entry: entry, model: model, layout: settings.textHistoryLayout)
                        }
                    } header: {
                        HistoryDayHeader(day: group.day, countText: "\(group.entries.count) 件")
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
        // 何もないところを押したら、選択を解除する
        .background(Color.clear.contentShape(Rectangle()).onTapGesture { model.clearSelection() })
    }

    /// 行の間（コンパクトは詰め、詳しくは広げる）
    private var rowSpacing: CGFloat {
        switch settings.textHistoryLayout {
        case .detailed: 8
        case .standard: 4
        case .compact: 1
        }
    }

    private var emptyState: some View {
        HistoryEmptyState(
            symbol: "text.viewfinder",
            title: settings.textHistoryEnabled ? "まだ読み取った文字はありません" : "読み取った文字を残さない設定になっています",
            message: settings.textHistoryEnabled
                ? "浮かせた画像で「文字をコピー」（⇧⌘T）を使うと、読み取った文字がここに並びます。\nダブルクリックで、もう一度コピーできます。"
                : "設定の「履歴」で「読み取った文字を履歴に残す」をオンにすると、読み取った文字がここに並びます。",
            enable: settings.textHistoryEnabled ? nil : { settings.textHistoryEnabled = true }
        )
    }

    /// 下の帯。選んでいるときは選んだ数と「選択を解除」、選んでいないときは件数と説明
    private var footer: some View {
        HistoryFooter(
            selectedCount: model.selectedEntries.count,
            unit: "件",
            summary: history.entries.isEmpty ? nil : history.summaryText,
            hint: "ダブルクリックでコピー・⌘ / shift + クリックで複数選ぶ",
            removeAll: CaptureHistoryWindowController.confirmRemoveAllTexts,
            clearSelection: model.clearSelection
        ) {
            // 選んだものへの操作（コピー・削除）は右の欄にあるので、ここには並べない（同じボタンが 2 か所に出ないように）
            EmptyView()
        }
    }
}

/// 読み取った文字の 1 件。表示方法で中身を変える（詳しく・標準・コンパクト）。
/// 選ぶ・ダブルクリック・ドラッグ・右クリック・右のボタンは、どの表示でも同じ
private struct TextHistoryRow: View {
    let entry: RecognizedTextEntry
    @ObservedObject var model: TextHistoryViewModel
    let layout: TextHistoryLayout

    private var isSelected: Bool { model.selection.contains(entry.id) }
    private var isHovered: Bool { model.hovered == entry.id }

    var body: some View {
        content
            .padding(.horizontal, 10)
            .padding(.vertical, layout == .compact ? 4 : 8)
        .historyRowBackground(isSelected: isSelected, isHovered: isHovered)
        .contentShape(Rectangle())
        .trackingHover($model.hovered, id: entry.id)
        // ダブルクリックでコピー。1 回のクリックは、待たずにすぐ選ぶ（⌘・shift も見る）
        .onTapGesture(count: 2) { model.copy(model.targets(for: entry)) }
        .simultaneousGesture(TapGesture().onEnded { model.click(entry, modifiers: NSEvent.modifierFlags) })
        .onDrag { NSItemProvider(object: entry.text as NSString) }
        .contextMenu { contextMenu }
        .hoverRole()
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }

    @ViewBuilder
    private var content: some View {
        switch layout {
        case .detailed:
            // 上に時刻などとボタン、下に大きめの画像と文字の最初の 5 行
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    info
                    Spacer(minLength: 8)
                    buttons
                }
                HStack(alignment: .top, spacing: 10) {
                    HistoryThumbnail(image: model.image(for: entry), size: CGSize(width: 120, height: 80), placeholder: "text.viewfinder")
                    preview(lines: 5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        case .standard:
            HStack(alignment: .center, spacing: 10) {
                HistoryThumbnail(image: model.image(for: entry), size: CGSize(width: 64, height: 44), placeholder: "text.viewfinder")
                VStack(alignment: .leading, spacing: 3) {
                    info
                    preview(lines: 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // マウスを乗せなくても、いつも出しておく（何ができるかが見て分かるように）
                buttons
            }
        case .compact:
            // 画像なしで 1 行（時刻・最初の行・編集中の印・ボタン）
            HStack(spacing: 10) {
                Text(CaptureHistoryRules.timeText(entry.date))
                    .font(.callout.monospacedDigit().weight(.medium))
                    .frame(width: 44, alignment: .leading)
                Text(TextHistoryRules.preview(entry.text, maxLength: 200))
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                pendingMark
                buttons
            }
        }
    }

    /// 時刻・文字数・編集中の印
    private var info: some View {
        HStack(spacing: 8) {
            Text(CaptureHistoryRules.timeText(entry.date))
                .font(.callout.monospacedDigit().weight(.medium))
            Text(TextHistoryRules.countText(entry.text))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            pendingMark
        }
    }

    /// 右の欄で直していて、まだ更新していないときの印
    @ViewBuilder
    private var pendingMark: some View {
        if model.hasPendingDraft(entry.id) {
            Label("編集中", systemImage: "pencil")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    /// 文字の最初の数行
    private func preview(lines: Int) -> some View {
        Text(entry.text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .lineLimit(lines)
            .truncationMode(.tail)
    }

    /// 行の右のコピー・削除のボタン
    private var buttons: some View {
        HStack(spacing: 4) {
            HistoryHoverButton(symbol: "doc.on.doc", help: "コピー") { model.copy(model.targets(for: entry)) }
            HistoryHoverButton(symbol: "trash", help: "履歴から削除") { model.remove(model.targets(for: entry)) }
        }
    }

    /// 右クリックのメニュー（選んでいる 1 件を右クリックしたときは、選んでいるものすべてが対象）
    @ViewBuilder
    private var contextMenu: some View {
        let targets = model.targets(for: entry)
        let suffix = targets.count > 1 ? "（\(targets.count) 件）" : ""
        Button(targets.count > 1 ? "つなげてコピー\(suffix)" : "コピー") { model.copy(targets) }
        if targets.count == 1, entry.imageFileName != nil {
            Button("読み取った画像を浮かせる") { model.pinImage(of: entry) }
            Button("読み取った画像をコピー") { model.copyImage(of: entry) }
        }
        Divider()
        Button("履歴から削除\(suffix)", role: .destructive) { model.remove(targets) }
    }
}

/// 右の欄。1 件を選んだときは、読み取った範囲の画像と、直せる全文を出す（打つのが止まると自動で保存）。
/// 画像と文字のそれぞれの見出しの横に、それに効くボタンを置く（どちらに効くかが分かるように）。
/// 2 件以上を選んだときは、「つなげてコピー」でコピーする文字をそのまま見せる
private struct TextHistoryDetail: View {
    @ObservedObject var model: TextHistoryViewModel

    var body: some View {
        let selected = model.selectedEntries
        VStack(spacing: 0) {
            if selected.isEmpty {
                HistoryEmptyState(
                    symbol: "text.alignleft",
                    title: "全文",
                    message: "一覧で選ぶと、読み取った文字の全文と、どの画像から読んだかがここに出ます。文字は直せます。"
                )
            } else if selected.count == 1, let entry = selected.first {
                header(title: CaptureHistoryRules.dateTimeText(entry.date)) {
                    smallButton("削除", symbol: "trash", help: "この 1 件を履歴から削除", role: .destructive) { model.remove([entry]) }
                }
                Divider()
                single(entry)
            } else {
                header(title: "\(selected.count) 件を選択中", subtitle: "空の行をはさんでつなげています") {
                    smallButton("つなげてコピー", symbol: "doc.on.doc", help: "選んだ文字を、空の行をはさんでつなげてコピー") { model.copy(selected) }
                    smallButton("削除", symbol: "trash", help: "選んだものを履歴から削除", role: .destructive) { model.remove(selected) }
                }
                Divider()
                ScrollView {
                    Text(TextHistoryRules.joined(selected))
                        .font(.body)
                        .lineSpacing(3)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(14)
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
    }

    /// 1 件のとき（読み取った画像とそのボタン・直せる全文とそのボタン・保存の知らせ）
    private func single(_ entry: RecognizedTextEntry) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if let image = model.image(for: entry) {
                VStack(alignment: .leading, spacing: 6) {
                    sectionTitle("読み取った画像") {
                        smallButton("浮かせる", symbol: "pin", help: "この画像を、もう一度画面に浮かせる") { model.pinImage(of: entry) }
                        smallButton("画像をコピー", symbol: "photo.on.rectangle", help: "この画像をクリップボードにコピー") { model.copyImage(of: entry) }
                    }
                    sourceImage(image, entry: entry)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                // 吹き出しと同じく、直したら「更新してコピー」で保存する（直しただけでは保存しない）
                sectionTitle("文字", detail: TextHistoryRules.countText(model.draft)) {
                    if model.isDraftEdited {
                        smallButton("更新してコピー", symbol: "arrow.triangle.2.circlepath", help: "履歴の文字を直した文字に更新して、コピーする（⌘↩）", prominent: true) { model.copyDraft() }
                            .keyboardShortcut(.return, modifiers: .command)
                    } else {
                        smallButton("コピー", symbol: "doc.on.doc", help: "文字をコピー") { model.copyDraft() }
                    }
                }
                EditableText(text: $model.draft, extraMenuItems: [
                    EditableTextMenuItem(title: model.isDraftEdited ? "更新してコピー" : "全文をコピー", symbol: "doc.on.doc") { model.copyDraft() },
                ])
                    .padding(6)
                    .framedBox(fill: Color(nsColor: .textBackgroundColor))
                saveStatus
            }
        }
        .padding(14)
    }

    /// どの画像から読んだか（押しても何もしない。浮かせる・コピーは見出しのボタンで。ドラッグでほかのアプリへ渡せる）
    private func sourceImage(_ image: NSImage, entry: RecognizedTextEntry) -> some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: 120)
            .padding(6)
            .framedBox()
            .onDrag {
                model.history.imageURL(for: entry).flatMap(NSItemProvider.init(contentsOf:)) ?? NSItemProvider()
            }
            .help("ドラッグで、ほかのアプリへ画像を渡せます")
    }

    /// いまの状態（直している途中・更新した・まだ直していない）
    private var saveStatus: some View {
        Group {
            if model.draftIsEmpty {
                EditStatusLine(text: "空のままでは更新できません（削除するときは上の「削除」）", symbol: "exclamationmark.circle.fill", tint: .orange)
            } else if model.isDraftEdited {
                EditStatusLine(text: "直しています。「更新してコピー」で、履歴とクリップボードを直した文字にします", symbol: "pencil.circle.fill", tint: .orange)
            } else if model.didUpdate {
                EditStatusLine(text: "履歴とクリップボードを、直した文字に更新しました", symbol: "checkmark.circle.fill", tint: .green)
            } else {
                EditStatusLine(text: "直すと、「更新してコピー」で履歴を更新できます", symbol: "pencil.circle", tint: .secondary)
            }
        }
    }

    // MARK: - 部品

    /// 上の帯（見出しと、この選択全体に効くボタン）
    private func header<Buttons: View>(title: String, subtitle: String? = nil, @ViewBuilder buttons: () -> Buttons) -> some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            buttons()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    /// 欄の見出しと、その欄に効くボタン（見出しの右に並べる）
    private func sectionTitle<Buttons: View>(_ title: String, detail: String? = nil, @ViewBuilder buttons: () -> Buttons) -> some View {
        HStack(alignment: .center, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            if let detail {
                Text(detail)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            buttons()
        }
    }

    /// アイコンと名前の付いた小さなボタン（何をするかが分かるよう、名前も出す）
    /// prominent: 目立たせる（いま押してほしいボタン。「更新してコピー」など）
    @ViewBuilder
    private func smallButton(_ title: String, symbol: String, help: String, role: ButtonRole? = nil, prominent: Bool = false, action: @escaping () -> Void) -> some View {
        let button = Button(role: role, action: action) {
            Label(title, systemImage: symbol)
        }
        .controlSize(.small)
        .help(help)
        .hoverRole()
        if prominent {
            button.buttonStyle(.borderedProminent)
        } else {
            button
        }
    }
}
