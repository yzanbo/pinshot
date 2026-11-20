import AppKit
import SwiftUI

/// 上げたものの一覧（履歴のウィンドウの「共有」）。日付ごとに並べる。
/// 表示方法は、撮った画像の一覧と同じ 3 つ（大きいサムネイル・小さいサムネイル・リスト。切り替えはウィンドウの上の帯）。
/// 選び方と下の帯は、撮った画像・読み取った文字の一覧と同じ
struct UploadHistoryView: View {
    @ObservedObject var history: UploadHistory
    @ObservedObject var model: UploadHistoryViewModel
    @ObservedObject var settings = AppSettings.shared

    private var layout: HistoryLayout { settings.uploadHistoryLayout }

    var body: some View {
        if history.entries.isEmpty {
            HistoryEmptyState(
                symbol: "link",
                title: "まだ上げたものはありません",
                message: "浮かせた画像の右クリック（か操作バーの「…」）の「アップロードしてリンクをコピー」（⌘U）で上げると、ここに並びます。上げる先は、設定の「共有」で選びます。"
            )
        } else {
            VStack(spacing: 0) {
                ScrollView {
                    content
                        .padding(.horizontal, 18)
                        .padding(.bottom, 18)
                }
                // 何もない所を押したら、選ぶのをやめる
                .background(Color.clear.contentShape(Rectangle()).onTapGesture { model.clearSelection() })
                Divider()
                footer
            }
        }
    }

    // MARK: - 表示方法ごとの並べ方

    private var groups: [(day: Date, entries: [UploadHistoryEntry])] {
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
                            UploadHistoryCell(entry: entry, model: model, compact: layout == .smallGrid)
                        }
                    } header: {
                        HistoryDayHeader(day: group.day, countText: "\(group.entries.count) 件")
                    }
                }
            }
        case .list:
            LazyVStack(alignment: .leading, spacing: 2, pinnedViews: [.sectionHeaders]) {
                ForEach(groups, id: \.day) { group in
                    Section {
                        ForEach(group.entries) { entry in
                            UploadHistoryRow(entry: entry, model: model)
                        }
                    } header: {
                        HistoryDayHeader(day: group.day, countText: "\(group.entries.count) 件")
                    }
                }
            }
        }
    }

    // MARK: - 下の帯

    private var footer: some View {
        let selected = model.selectedEntries
        return HistoryFooter(
            selectedCount: selected.count,
            unit: "件",
            summary: "\(history.entries.count) 件",
            hint: "クリックで選ぶ（⌘・shift で複数）・ダブルクリックでブラウザで開く",
            removeAll: { model.remove(history.entries) },
            clearSelection: { model.clearSelection() }
        ) {
            HistoryFooterButton(title: "コピー", symbol: "doc.on.doc") {
                model.copyLinks(selected, format: settings.shareLinkFormat)
            }
            .help("\(settings.shareLinkFormat.label)をコピー（2 件以上は 1 行に 1 つずつ）")
            HistoryFooterButton(title: "ブラウザで開く", symbol: "safari") { model.openInBrowser(selected) }
            HistoryFooterButton(title: "削除…", symbol: "trash", role: .destructive) { model.remove(selected) }
        }
    }
}

// MARK: - 1 件

/// サムネイルで並べるときの 1 件。compact は小さいサムネイル（リンクの表示を省く）
private struct UploadHistoryCell: View {
    let entry: UploadHistoryEntry
    @ObservedObject var model: UploadHistoryViewModel
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
                Text(entry.destination.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 2)
            if !compact {
                Text(UploadHistoryRules.shortLink(entry.link.pageURL))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 2)
            }
        }
        .modifier(UploadItemInteractions(entry: entry, model: model))
        .help("\(entry.link.pageURL.absoluteString)・ダブルクリックでブラウザで開く")
    }

    private var thumbnail: some View {
        // 撮った画像の一覧と同じく、乗せている間だけ縮小画像の上にボタンを出す
        HistoryGridThumbnail(image: model.thumbnail(for: entry), compact: compact, isSelected: isSelected, isHovered: isHovered) {
            UploadItemButtons(entry: entry, model: model, onImage: true)
        }
    }
}

/// リストで並べるときの 1 行（小さい縮小画像・時刻・リンク・上げる先・ボタン）
private struct UploadHistoryRow: View {
    let entry: UploadHistoryEntry
    @ObservedObject var model: UploadHistoryViewModel

    private var isSelected: Bool { model.selection.contains(entry.id) }
    private var isHovered: Bool { model.hovered == entry.id }

    var body: some View {
        HStack(spacing: 12) {
            HistoryThumbnail(image: model.thumbnail(for: entry), size: CGSize(width: 72, height: 46), placeholder: "photo")
            Text(CaptureHistoryRules.timeText(entry.date))
                .font(.body.monospacedDigit())
                .frame(width: 48, alignment: .leading)
            Text(entry.link.pageURL.absoluteString)
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            Text(entry.destination.label)
                .font(.caption)
                .foregroundStyle(.secondary)
            // 選んでいてもいつも出す（この行を選んでいれば、選んでいるものすべてに効く）
            UploadItemButtons(entry: entry, model: model)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .historyRowBackground(isSelected: isSelected, isHovered: isHovered)
        .modifier(UploadItemInteractions(entry: entry, model: model))
    }
}

/// 1 件の、コピー・ブラウザで開く・削除のボタン（この 1 件を選んでいれば、選んでいるものすべてに効く）
private struct UploadItemButtons: View {
    let entry: UploadHistoryEntry
    @ObservedObject var model: UploadHistoryViewModel
    @ObservedObject var settings = AppSettings.shared
    var onImage = false

    var body: some View {
        HStack(spacing: 4) {
            HistoryHoverButton(symbol: "doc.on.doc", help: "\(settings.shareLinkFormat.label)をコピー（形は設定の「共有」で変えられる）", onImage: onImage) {
                model.copyLinks(model.targets(for: entry), format: settings.shareLinkFormat)
            }
            HistoryHoverButton(symbol: "safari", help: "ブラウザで開く", onImage: onImage) { model.openInBrowser(model.targets(for: entry)) }
            HistoryHoverButton(symbol: "trash", help: "削除…", onImage: onImage) { model.remove(model.targets(for: entry)) }
        }
    }
}

/// 1 件ぶんの共通の操作（乗せる・クリック・ダブルクリック・右クリック）。どの表示方法でも同じにする
private struct UploadItemInteractions: ViewModifier {
    let entry: UploadHistoryEntry
    @ObservedObject var model: UploadHistoryViewModel

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .trackingHover($model.hovered, id: entry.id)
            .onTapGesture(count: 2) { model.openInBrowser(model.targets(for: entry)) }
            .simultaneousGesture(TapGesture().onEnded { model.click(entry, modifiers: NSEvent.modifierFlags) })
            .contextMenu { menuItems(model.targets(for: entry)) }
            .hoverRole()
    }

    /// 右クリック（選んでいれば、選んでいるものすべてに）
    @ViewBuilder
    private func menuItems(_ targets: [UploadHistoryEntry]) -> some View {
        let suffix = targets.count > 1 ? "（\(targets.count) 件）" : ""
        ForEach(ShareLinkFormat.allCases) { format in
            Button("\(format.label)をコピー\(suffix)") { model.copyLinks(targets, format: format) }
                .disabled(format != .page && targets.allSatisfy { $0.link.directURL == nil })
        }
        Divider()
        Button("ブラウザで開く\(suffix)") { model.openInBrowser(targets) }
        Divider()
        Button("削除…\(suffix)", role: .destructive) { model.remove(targets) }
    }
}
