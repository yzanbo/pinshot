import SwiftUI

/// 一覧の日付の見出し（「今日　3 枚」など）
struct HistoryDayHeader: View {
    let day: Date
    /// 件数の文字（「3 枚」「3 件」）
    let countText: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(CaptureHistoryRules.dayTitle(day))
                .font(.headline)
            Text(countText)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.top, 14)
        .padding(.bottom, 6)
        .background(.bar)
    }
}

/// 履歴が空のときの案内
struct HistoryEmptyState: View {
    let symbol: String
    let title: String
    let message: String
    /// 残さない設定のときに出す「残す」ボタン（nil なら出さない）
    var enable: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title3.weight(.semibold))
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let enable {
                Button("履歴を残す", action: enable)
                    .buttonStyle(.borderedProminent)
                    .hoverRole()
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 一覧の小さな画像（画像がないときは placeholder の印。nil なら何も出さない）
struct HistoryThumbnail: View {
    let image: NSImage?
    let size: CGSize
    var placeholder: String?

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .padding(3)
            } else if let placeholder {
                Image(systemName: placeholder)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: size.width, height: size.height)
        .framedBox(cornerRadius: 5)
    }
}

/// サムネイルで並べるときの 1 件の縮小画像（枠・選んでいる印・乗せている間のボタン）。
/// 撮った画像の一覧と、上げたものの一覧で同じ見た目にする。compact は小さいサムネイル
struct HistoryGridThumbnail<Buttons: View>: View {
    let image: NSImage?
    let compact: Bool
    let isSelected: Bool
    let isHovered: Bool
    /// 乗せている間だけ、縮小画像の上に出すボタン
    @ViewBuilder let buttons: () -> Buttons

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color.primary.opacity(isHovered ? 0.09 : 0.05))
            if let image {
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
            RoundedRectangle(cornerRadius: cornerRadius)
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
                buttons()
                    .padding(compact ? 4 : 6)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }

    private var cornerRadius: CGFloat { compact ? 7 : 10 }
}

/// 日付ごとに並べる一覧の中身（表示方法に合わせて、サムネイルかリスト）。
/// 撮った画像の一覧と、上げたものの一覧で同じ並べ方にする（見出しはスクロールしても上に残す）。
/// unit は見出しの数の単位（「枚」「件」）。cell の 2 つ目は小さいサムネイルか
struct HistoryDayGroupedList<Entry: HistoryItem, Cell: View, Row: View>: View {
    let groups: [(day: Date, entries: [Entry])]
    let layout: HistoryLayout
    let unit: String
    @ViewBuilder let cell: (Entry, Bool) -> Cell
    @ViewBuilder let row: (Entry) -> Row

    var body: some View {
        switch layout {
        case .largeGrid, .smallGrid:
            LazyVGrid(columns: layout.gridColumns, alignment: .leading, spacing: layout.gridSpacing, pinnedViews: [.sectionHeaders]) {
                sections { cell($0, layout == .smallGrid) }
            }
        case .list:
            LazyVStack(alignment: .leading, spacing: 2, pinnedViews: [.sectionHeaders]) {
                sections(row)
            }
        }
    }

    private func sections<Item: View>(@ViewBuilder _ item: @escaping (Entry) -> Item) -> some View {
        ForEach(groups, id: \.day) { group in
            Section {
                ForEach(group.entries) { entry in item(entry) }
            } header: {
                HistoryDayHeader(day: group.day, countText: "\(group.entries.count) \(unit)")
            }
        }
    }
}

extension HistoryLayout {
    /// サムネイルで並べるときの列（大きい・小さいサムネイル）
    var gridColumns: [GridItem] {
        let large = self == .largeGrid
        return [GridItem(.adaptive(minimum: large ? 170 : 110, maximum: large ? 260 : 150), spacing: gridSpacing)]
    }

    /// サムネイルの間
    var gridSpacing: CGFloat { self == .largeGrid ? 16 : 10 }
}

/// 一覧の下の帯。選んでいないときは数と操作の説明と「すべて消す…」、選んでいるときは選んだ数と、選んだものへの操作
struct HistoryFooter<Actions: View>: View {
    /// 選んでいる数（0 なら選んでいない）
    let selectedCount: Int
    /// 数の単位（「枚」「件」）
    let unit: String
    /// 選んでいないときの数（「12 枚・3.4 MB」など。空なら「履歴なし」）
    let summary: String?
    /// 選んでいないときの操作の説明
    let hint: String
    let removeAll: () -> Void
    let clearSelection: () -> Void
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        HStack(spacing: 10) {
            if selectedCount == 0 {
                Text(summary ?? "履歴なし")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                Button("すべて削除…", action: removeAll)
                    .disabled(summary == nil)
                    .hoverRole(summary == nil ? .inactive : .pressable)
            } else {
                Text("\(selectedCount) \(unit)を選択中")
                    .font(.callout.weight(.semibold))
                Button("選択を解除", action: clearSelection)
                    .buttonStyle(.link)
                    .hoverRole()
                Spacer(minLength: 8)
                actions()
            }
        }
        .controlSize(.regular)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
}

/// マウスを乗せている間に出す、丸い小さなボタン。onImage は縮小画像の上に重ねるとき（白い印に黒い丸）
struct HistoryHoverButton: View {
    let symbol: String
    let help: String
    var onImage = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(onImage ? Color.white : Color.primary)
                .frame(width: 24, height: 24)
                .background(Circle().fill(onImage ? Color.black.opacity(0.6) : Color.primary.opacity(0.08)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .hoverRole()
    }
}

/// 下の帯の、アイコン付きのボタン。prominent なら目立たせる（いま押してほしいボタン。文字の「更新してコピー」など）
struct HistoryFooterButton: View {
    let title: String
    let symbol: String
    var role: ButtonRole?
    var prominent = false
    let action: () -> Void

    var body: some View {
        if prominent {
            button.buttonStyle(.borderedProminent)
        } else {
            button
        }
    }

    private var button: some View {
        Button(role: role, action: action) {
            Label(title, systemImage: symbol)
        }
        .hoverRole()
    }
}

extension View {
    /// 一覧の 1 行の背景（選んでいればアクセントカラー、乗せていれば薄い色）
    func historyRowBackground(isSelected: Bool, isHovered: Bool) -> some View {
        background(
            RoundedRectangle(cornerRadius: 7)
                .fill(isSelected ? Color.accentColor.opacity(0.22) : (isHovered ? Color.primary.opacity(0.06) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.7) : Color.clear, lineWidth: 1)
        )
    }

    /// マウスを乗せている 1 件を hovered に入れる（外れたら、ほかへ移っていなければ nil に戻す）
    func trackingHover(_ hovered: Binding<UUID?>, id: UUID) -> some View {
        onHover { inside in
            if inside {
                hovered.wrappedValue = id
            } else if hovered.wrappedValue == id {
                hovered.wrappedValue = nil
            }
        }
    }
}
