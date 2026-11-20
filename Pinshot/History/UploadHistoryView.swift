import AppKit
import SwiftUI

/// 上げたものの一覧（履歴のウィンドウの「共有」）。
/// 1 件ごとに、縮小画像・リンク・日時と上げる先を出す。選び方と下の帯は、撮った画像・読み取った文字の一覧と同じ
struct UploadHistoryView: View {
    @ObservedObject var history: UploadHistory
    @ObservedObject var model: UploadHistoryViewModel
    @ObservedObject var settings = AppSettings.shared

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
                    LazyVStack(spacing: 4) {
                        ForEach(history.entries) { entry in
                            row(entry)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
                // 何もない所を押したら、選ぶのをやめる
                .background(Color.clear.contentShape(Rectangle()).onTapGesture { model.clearSelection() })
                Divider()
                footer
            }
        }
    }

    // MARK: - 1 行

    private func row(_ entry: UploadHistoryEntry) -> some View {
        let isSelected = model.selection.contains(entry.id)
        return HStack(spacing: 12) {
            HistoryThumbnail(image: history.thumbnail(for: entry), size: CGSize(width: 64, height: 48), placeholder: "photo")
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.link.pageURL.absoluteString)
                    .font(.callout.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(UploadHistoryRules.subtitle(for: entry))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            // 画像・文字の一覧と同じく、選んでいてもボタンを出す（この行を選んでいれば、選んでいるものすべてに効く）
            HistoryHoverButton(symbol: "doc.on.doc", help: "\(settings.shareLinkFormat.label)をコピー（形は設定の「共有」で変えられる）") {
                model.copyLinks(model.targets(for: entry), format: settings.shareLinkFormat)
            }
            HistoryHoverButton(symbol: "safari", help: "ブラウザで開く") { model.openInBrowser(model.targets(for: entry)) }
            HistoryHoverButton(symbol: "trash", help: "削除…") { model.remove(model.targets(for: entry)) }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .historyRowBackground(isSelected: isSelected, isHovered: model.hovered == entry.id)
        .contentShape(Rectangle())
        .trackingHover($model.hovered, id: entry.id)
        .onTapGesture(count: 2) { model.openInBrowser(model.targets(for: entry)) }
        .simultaneousGesture(TapGesture().onEnded { model.click(entry, modifiers: NSEvent.modifierFlags) })
        .contextMenu { menuItems(model.targets(for: entry)) }
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
