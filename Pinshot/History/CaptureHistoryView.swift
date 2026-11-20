import SwiftUI

/// 撮った画像の履歴の一覧。日付ごとに縮小画像を並べる（表示方法の切り替えは、ウィンドウの上の帯）
struct CaptureHistoryView: View {
    @ObservedObject var history: CaptureHistory
    @ObservedObject var model: CaptureHistoryViewModel
    @ObservedObject var settings = AppSettings.shared

    private var layout: HistoryLayout { settings.historyLayout }

    var body: some View {
        VStack(spacing: 0) {
            if history.entries.isEmpty {
                emptyState
            } else {
                ScrollView {
                    content
                        .padding(.horizontal, 18)
                        .padding(.bottom, 18)
                }
                // 何もないところを押したら、選択を解除する
                .background(Color.clear.contentShape(Rectangle()).onTapGesture { model.clearSelection() })
            }
            Divider()
            footer
        }
    }

    // MARK: - 表示方法ごとの並べ方

    private var groups: [(day: Date, entries: [CaptureHistoryEntry])] {
        CaptureHistoryRules.groupedByDay(history.entries)
    }

    @ViewBuilder
    private var content: some View {
        switch layout {
        case .largeGrid, .smallGrid:
            LazyVGrid(columns: layout.gridColumns, alignment: .leading, spacing: layout.gridSpacing, pinnedViews: [.sectionHeaders]) {
                ForEach(groups, id: \.day) { group in
                    Section {
                        ForEach(group.entries) { entry in
                            CaptureHistoryCell(entry: entry, model: model, compact: layout == .smallGrid)
                        }
                    } header: {
                        HistoryDayHeader(day: group.day, countText: "\(group.entries.count) 枚")
                    }
                }
            }
        case .list:
            LazyVStack(alignment: .leading, spacing: 2, pinnedViews: [.sectionHeaders]) {
                ForEach(groups, id: \.day) { group in
                    Section {
                        ForEach(group.entries) { entry in
                            CaptureHistoryRow(entry: entry, model: model)
                        }
                    } header: {
                        HistoryDayHeader(day: group.day, countText: "\(group.entries.count) 枚")
                    }
                }
            }
        }
    }

    // MARK: - 部品

    private var emptyState: some View {
        HistoryEmptyState(
            symbol: "photo.on.rectangle.angled",
            title: settings.historyEnabled ? "まだ撮った画像はありません" : "撮った画像を残さない設定になっています",
            message: settings.historyEnabled
                ? "撮った画像は、ここに日付ごとに並びます。\nダブルクリックで、もう一度浮かせられます。"
                : "設定の「履歴」で「撮った画像を履歴に残す」をオンにすると、撮った画像がここに並びます。",
            enable: settings.historyEnabled ? nil : { settings.historyEnabled = true }
        )
    }

    /// 下の帯。選んでいるときは選んだものへの操作、選んでいないときは枚数と説明
    private var footer: some View {
        let selected = model.selectedEntries
        return HistoryFooter(
            selectedCount: selected.count,
            unit: "枚",
            summary: history.entries.isEmpty ? nil : history.summaryText,
            hint: "ダブルクリックで浮かせる・⌘ / shift + クリックで複数選ぶ・ドラッグでほかのアプリへ",
            removeAll: CaptureHistoryWindowController.confirmRemoveAll,
            clearSelection: model.clearSelection
        ) {
            HistoryFooterButton(title: "浮かせる", symbol: "pin") { model.pin(selected) }
            if selected.count == 1, let first = selected.first {
                HistoryFooterButton(title: "コピー", symbol: "doc.on.doc") { model.copy(first) }
            }
            HistoryFooterButton(title: "保存…", symbol: "square.and.arrow.down") { model.save(selected) }
            HistoryFooterButton(title: "削除", symbol: "trash", role: .destructive) { model.remove(selected) }
        }
    }
}

/// 1 枚ぶんの共通の操作（乗せる・クリック・ダブルクリック・ドラッグ・右クリック）。どの表示方法でも同じにする
private struct HistoryItemInteractions: ViewModifier {
    let entry: CaptureHistoryEntry
    @ObservedObject var model: CaptureHistoryViewModel

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .trackingHover($model.hovered, id: entry.id)
            // ダブルクリックで浮かせる。1 回のクリックは、待たずにすぐ選ぶ（⌘・shift も見る）
            .onTapGesture(count: 2) { model.pin(model.targets(for: entry)) }
            .simultaneousGesture(TapGesture().onEnded { model.click(entry, modifiers: NSEvent.modifierFlags) })
            .onDrag {
                NSItemProvider(contentsOf: model.history.imageURL(for: entry)) ?? NSItemProvider()
            }
            .contextMenu { HistoryContextMenu(entry: entry, model: model) }
            .hoverRole()
    }
}

/// 右クリックのメニュー（選んでいる 1 枚を右クリックしたときは、選んでいるものすべてが対象）
private struct HistoryContextMenu: View {
    let entry: CaptureHistoryEntry
    @ObservedObject var model: CaptureHistoryViewModel

    var body: some View {
        let targets = model.targets(for: entry)
        let suffix = targets.count > 1 ? "（\(targets.count) 枚）" : ""
        Button("浮かせる\(suffix)") { model.pin(targets) }
        if targets.count == 1 {
            Button("コピー") { model.copy(entry) }
            Button("文字をコピー") { model.copyText(entry) }
            Button("アップロードしてリンクをコピー") { model.upload(entry) }
        }
        Button("保存…\(suffix)") { model.save(targets) }
        Button("Finder で表示\(suffix)") { model.revealInFinder(targets) }
        Divider()
        Button("履歴から削除\(suffix)", role: .destructive) { model.remove(targets) }
    }
}

/// 乗せている間に出す、浮かせる・コピー・消すのボタン
private struct HistoryItemButtons: View {
    let entry: CaptureHistoryEntry
    @ObservedObject var model: CaptureHistoryViewModel

    var body: some View {
        HStack(spacing: 4) {
            HistoryHoverButton(symbol: "pin", help: "浮かせる", onImage: true) { model.pin(model.targets(for: entry)) }
            HistoryHoverButton(symbol: "doc.on.doc", help: "コピー", onImage: true) { model.copy(entry) }
            HistoryHoverButton(symbol: "trash", help: "履歴から削除", onImage: true) { model.remove(model.targets(for: entry)) }
        }
    }
}

/// サムネイルで並べるときの 1 枚。compact は小さいサムネイル（大きさの表示を省く）
private struct CaptureHistoryCell: View {
    let entry: CaptureHistoryEntry
    @ObservedObject var model: CaptureHistoryViewModel
    var compact = false

    private var isSelected: Bool { model.selection.contains(entry.id) }
    private var isHovered: Bool { model.hovered == entry.id }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 6) {
            thumbnail
            HStack(spacing: 6) {
                Text(CaptureHistoryRules.timeText(entry.date))
                    .font((compact ? Font.caption : Font.callout).monospacedDigit())
                Spacer(minLength: 4)
                if !compact {
                    Text(CaptureHistoryRules.sizeText(entry))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 2)
        }
        .modifier(HistoryItemInteractions(entry: entry, model: model))
        .help("\(CaptureHistoryRules.shortTitle(entry))・ダブルクリックで浮かせる")
    }

    private var thumbnail: some View {
        HistoryGridThumbnail(image: model.thumbnail(for: entry), compact: compact, isSelected: isSelected, isHovered: isHovered) {
            HistoryItemButtons(entry: entry, model: model)
        }
    }
}

/// リストで並べるときの 1 行（小さい縮小画像・時刻・大きさ・容量）
private struct CaptureHistoryRow: View {
    let entry: CaptureHistoryEntry
    @ObservedObject var model: CaptureHistoryViewModel

    private var isSelected: Bool { model.selection.contains(entry.id) }
    private var isHovered: Bool { model.hovered == entry.id }

    var body: some View {
        HStack(spacing: 12) {
            HistoryThumbnail(image: model.thumbnail(for: entry), size: CGSize(width: 72, height: 46))
            Text(CaptureHistoryRules.timeText(entry.date))
                .font(.body.monospacedDigit())
                .frame(width: 48, alignment: .leading)
            Text(CaptureHistoryRules.sizeText(entry))
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            if isHovered {
                HistoryItemButtons(entry: entry, model: model)
                    .transition(.opacity)
            }
            Text(CaptureHistoryRules.byteText(entry.byteCount))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .historyRowBackground(isSelected: isSelected, isHovered: isHovered)
        .modifier(HistoryItemInteractions(entry: entry, model: model))
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}
