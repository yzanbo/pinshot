import SwiftUI

/// 撮った画像の履歴の一覧。日付ごとに縮小画像を並べる
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
                topBar
                Divider()
                ScrollView {
                    content
                        .padding(.horizontal, 18)
                        .padding(.bottom, 18)
                }
                // 何もないところを押したら、選ぶのをやめる
                .background(Color.clear.contentShape(Rectangle()).onTapGesture { model.clearSelection() })
            }
            Divider()
            footer
        }
        .overlay(alignment: .bottom) { noticeView }
        .animation(.easeOut(duration: 0.15), value: model.notice)
        .frame(minWidth: 460, minHeight: 340)
    }

    // MARK: - 表示方法ごとの並べ方

    private var groups: [(day: Date, entries: [CaptureHistoryEntry])] {
        CaptureHistoryRules.groupedByDay(history.entries)
    }

    @ViewBuilder
    private var content: some View {
        switch layout {
        case .largeGrid, .smallGrid:
            let large = layout == .largeGrid
            let columns = [GridItem(.adaptive(minimum: large ? 170 : 110, maximum: large ? 260 : 150), spacing: large ? 16 : 10)]
            LazyVGrid(columns: columns, alignment: .leading, spacing: large ? 16 : 10, pinnedViews: [.sectionHeaders]) {
                ForEach(groups, id: \.day) { group in
                    Section {
                        ForEach(group.entries) { entry in
                            CaptureHistoryCell(entry: entry, model: model, compact: !large)
                        }
                    } header: {
                        dayHeader(group.day, count: group.entries.count)
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
                        dayHeader(group.day, count: group.entries.count)
                    }
                }
            }
        }
    }

    /// 上の帯（表示方法の切り替え）
    private var topBar: some View {
        HStack(spacing: 10) {
            Text("表示")
                .font(.callout)
                .foregroundStyle(.secondary)
            Picker("表示", selection: $settings.historyLayout) {
                ForEach(HistoryLayout.allCases) { layout in
                    Image(systemName: layout.symbolName)
                        .help(layout.label)
                        .tag(layout)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .hoverRole()
            Text(layout.label)
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: - 部品

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
            Text(settings.historyEnabled ? "まだ履歴はありません" : "履歴を残さない設定になっています")
                .font(.title3.weight(.semibold))
            Text(settings.historyEnabled
                 ? "撮った画像は、ここに日付ごとに並びます。\nダブルクリックで、もう一度浮かせられます。"
                 : "設定の「履歴」で「撮った画像を履歴に残す」をオンにすると、撮った画像がここに並びます。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if !settings.historyEnabled {
                Button("履歴を残す") { settings.historyEnabled = true }
                    .buttonStyle(.borderedProminent)
                    .hoverRole()
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func dayHeader(_ day: Date, count: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(CaptureHistoryRules.dayTitle(day))
                .font(.headline)
            Text("\(count) 枚")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.top, 14)
        .padding(.bottom, 6)
        .background(.bar)
    }

    /// 下の帯。選んでいるときは選んだものへの操作、選んでいないときは枚数と説明
    @ViewBuilder
    private var footer: some View {
        let selected = model.selectedEntries
        HStack(spacing: 10) {
            if selected.isEmpty {
                Text(history.entries.isEmpty ? "履歴なし" : history.summaryText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("ダブルクリックで浮かせる・⌘ / shift + クリックで複数選ぶ・ドラッグでほかのアプリへ")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                Button("すべて消す…") { CaptureHistoryWindowController.confirmRemoveAll() }
                    .disabled(history.entries.isEmpty)
                    .hoverRole(history.entries.isEmpty ? .inactive : .pressable)
            } else {
                Text("\(selected.count) 枚を選択中")
                    .font(.callout.weight(.semibold))
                Button("選ぶのをやめる") { model.clearSelection() }
                    .buttonStyle(.link)
                    .hoverRole()
                Spacer(minLength: 8)
                footerButton("浮かせる", symbol: "pin") { model.pin(selected) }
                if selected.count == 1, let first = selected.first {
                    footerButton("コピー", symbol: "doc.on.doc") { model.copy(first) }
                }
                footerButton("保存…", symbol: "square.and.arrow.down") { model.save(selected) }
                footerButton("消す", symbol: "trash", role: .destructive) { model.remove(selected) }
            }
        }
        .controlSize(.regular)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private func footerButton(_ title: String, symbol: String, role: ButtonRole? = nil, action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) {
            Label(title, systemImage: symbol)
        }
        .hoverRole()
    }

    /// 「コピーしました」などの短い知らせ
    @ViewBuilder
    private var noticeView: some View {
        if let notice = model.notice {
            Label(notice, systemImage: "checkmark.circle.fill")
                .font(.callout.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1)))
                .padding(.bottom, 60)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .allowsHitTesting(false)
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
            .onHover { inside in
                if inside {
                    model.hovered = entry.id
                } else if model.hovered == entry.id {
                    model.hovered = nil
                }
            }
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
        }
        Button("保存…\(suffix)") { model.save(targets) }
        Button("Finder で表示\(suffix)") { model.revealInFinder(targets) }
        Divider()
        Button("履歴から消す\(suffix)", role: .destructive) { model.remove(targets) }
    }
}

/// 乗せている間に出す、浮かせる・コピー・消すのボタン
private struct HistoryItemButtons: View {
    let entry: CaptureHistoryEntry
    @ObservedObject var model: CaptureHistoryViewModel

    var body: some View {
        HStack(spacing: 4) {
            button("pin", help: "浮かせる") { model.pin(model.targets(for: entry)) }
            button("doc.on.doc", help: "コピー") { model.copy(entry) }
            button("trash", help: "履歴から消す") { model.remove(model.targets(for: entry)) }
        }
    }

    private func button(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.black.opacity(0.6)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .hoverRole()
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
        ZStack {
            RoundedRectangle(cornerRadius: compact ? 7 : 10)
                .fill(Color.primary.opacity(isHovered ? 0.09 : 0.05))
            if let image = model.thumbnail(for: entry) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .padding(compact ? 5 : 8)
            } else {
                Image(systemName: "photo")
                    .font(compact ? .body : .title2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(height: compact ? 76 : 130)
        .overlay(
            RoundedRectangle(cornerRadius: compact ? 7 : 10)
                .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(isHovered ? 0.25 : 0.12), lineWidth: isSelected ? 3 : 1)
        )
        .overlay(alignment: .topLeading) {
            // 選んでいることが分かる印
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: compact ? 14 : 18))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color.accentColor)
                    .padding(compact ? 4 : 7)
            }
        }
        .overlay(alignment: compact ? .bottomTrailing : .topTrailing) {
            if isHovered {
                HistoryItemButtons(entry: entry, model: model)
                    .padding(compact ? 4 : 6)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.12), value: isHovered)
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
            ZStack {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.primary.opacity(0.05))
                if let image = model.thumbnail(for: entry) {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .padding(3)
                }
            }
            .frame(width: 72, height: 46)
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.primary.opacity(0.12)))
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
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(isSelected ? Color.accentColor.opacity(0.22) : (isHovered ? Color.primary.opacity(0.06) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.7) : Color.clear, lineWidth: 1)
        )
        .modifier(HistoryItemInteractions(entry: entry, model: model))
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}
