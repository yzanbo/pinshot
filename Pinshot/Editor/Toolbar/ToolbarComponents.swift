import SwiftUI

// MARK: - 大きさ・色の決まり

/// ツールバーの部品の大きさ・形・色（すべての部品でそろえる）
enum ToolbarMetrics {
    /// 1 行目の部品の枠
    static let cell = CGSize(width: 30, height: 26)
    /// ▾ 付きボタンの、アイコンの枠と ▾ の枠（アイコンが変わっても ▾ の位置は変わらない）
    static let iconWidth: CGFloat = 26
    static let chevronWidth: CGFloat = 12
    static var groupCellWidth: CGFloat { iconWidth + chevronWidth }
    static let chevronFont = Font.system(size: 8, weight: .bold)
    /// 部品どうしの間隔と、区切り線の左右の余白
    static let itemSpacing: CGFloat = 3
    static let dividerPadding: CGFloat = 6
    /// ツールバーの外側の余白
    static let toolbarPadding = EdgeInsets(top: 6, leading: 10, bottom: 7, trailing: 10)
    /// 2 行目（オプション）の吹き出し：内側の余白・先の三角・色。
    /// 色を付けると中の文字や選択肢が読みにくくなるので、台は無彩色で少しだけ明るさを変える（ライト・ダークどちらでも）
    static let trayPadding = EdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 8)
    static let trayNotch = CGSize(width: 16, height: 7)
    static let trayCorner: CGFloat = 8
    static let trayFill = Color.primary.opacity(0.07)
    static let trayBorder = Color.primary.opacity(0.16)
    /// 1 行目と 2 行目をまとめた座標（吹き出しの先の位置を測る）
    static let rowsSpace = "toolbarRows"
    static let cellCorner: CGFloat = 6
    static let iconFont = Font.system(size: 13, weight: .medium)
    static let swatchSize: CGFloat = 16
    /// 2 行目の選択肢（セグメント）
    static let segmentHeight: CGFloat = 20
    static let groupCorner: CGFloat = 7
    static let segmentCorner: CGFloat = 5
    static let labelFont = Font.system(size: 11)
    /// 選んでいるもの：濃いアクセントカラーの背景に白（macOS のセグメントボタンと同じ。薄い青に青だと読みにくいため）
    static let selectedFill = Color.accentColor
    static let selectedForeground = Color.white
    static let groupFill = Color.primary.opacity(0.07)
}

// MARK: - 並べ方

/// 2 行目の吹き出しの先を向ける、1 行目のボタンの中心（横の位置）
struct OptionsAnchorKey: PreferenceKey {
    static let defaultValue: CGFloat? = nil
    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
        value = nextValue() ?? value
    }
}

extension View {
    /// isActive のとき、このボタンの中心を、2 行目の吹き出しの先の位置として伝える
    func optionsAnchor(isActive: Bool) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: OptionsAnchorKey.self,
                    value: isActive ? proxy.frame(in: .named(ToolbarMetrics.rowsSpace)).midX : nil
                )
            }
        )
    }
}

/// 上に三角の先が出た角丸の四角（吹き出し）。notchX が nil なら先を出さない
struct CalloutShape: Shape {
    var notchX: CGFloat?
    var notch: CGSize
    var corner: CGFloat

    func path(in rect: CGRect) -> Path {
        let body = CGRect(x: rect.minX, y: rect.minY + notch.height, width: rect.width, height: rect.height - notch.height)
        let r = min(corner, body.height / 2, body.width / 2)
        var path = Path()
        path.move(to: CGPoint(x: body.minX + r, y: body.minY))
        if let notchX {
            // 角の丸みにかからない範囲に収める
            let half = notch.width / 2
            let x = min(max(rect.minX + notchX, body.minX + r + half), body.maxX - r - half)
            path.addLine(to: CGPoint(x: x - half, y: body.minY))
            path.addLine(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x + half, y: body.minY))
        }
        path.addArc(tangent1End: CGPoint(x: body.maxX, y: body.minY), tangent2End: CGPoint(x: body.maxX, y: body.maxY), radius: r)
        path.addArc(tangent1End: CGPoint(x: body.maxX, y: body.maxY), tangent2End: CGPoint(x: body.minX, y: body.maxY), radius: r)
        path.addArc(tangent1End: CGPoint(x: body.minX, y: body.maxY), tangent2End: CGPoint(x: body.minX, y: body.minY), radius: r)
        path.addArc(tangent1End: CGPoint(x: body.minX, y: body.minY), tangent2End: CGPoint(x: body.maxX, y: body.minY), radius: r)
        path.closeSubpath()
        return path
    }
}

/// 1 行目の幅を、2 行目に伝える
struct ToolbarRowWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// 左から順に並べ、幅に入りきらなければ次の行に送る
struct FlowLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, maxWidth: proposal.width ?? .infinity)
        let widest = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(rows.count - 1, 0))
        // 幅を決められているときは、その幅いっぱいを使う（並べるときに同じ幅で行を分けるため）
        return CGSize(width: proposal.width ?? widest, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        // 測ったときと同じ幅で行を分ける（違う幅で分けると、行の数が変わってはみ出すことがある）
        for row in arrange(subviews, maxWidth: proposal.width ?? bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                // 行の中では、上下の真ん中にそろえる
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let added = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if !current.indices.isEmpty, added > maxWidth {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

/// ボタンの並び
struct ToolbarSection<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: ToolbarMetrics.itemSpacing) {
            content
        }
    }
}

struct ToolbarDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.15))
            .frame(width: 1, height: 18)
            .padding(.horizontal, ToolbarMetrics.dividerPadding)
    }
}

/// オプションの 1 まとまり（見出しと選択肢）
struct OptionSection<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(ToolbarMetrics.labelFont)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
            content
        }
        // 項目ごとに必要な幅を必ず使う（狭いときは折り返しで下の行へ送り、文字は切らない）
        .fixedSize()
    }
}

/// 選択肢を 1 つの角丸の台に並べる（macOS のセグメントボタンと同じ形）
struct SegmentedGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 1) {
            content
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: ToolbarMetrics.groupCorner).fill(ToolbarMetrics.groupFill))
    }
}

/// セグメントの 1 つ（選んでいるものだけ色を付ける）
struct SegmentButton<Label: View>: View {
    @ObservedObject var state: EditorState
    let hint: String
    let isSelected: Bool
    let action: @MainActor () -> Void
    @ViewBuilder var label: Label

    var body: some View {
        Button {
            action()
        } label: {
            label
                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? ToolbarMetrics.selectedForeground : Color.primary)
                .padding(.horizontal, 7)
                .frame(minWidth: 22)
                .frame(height: ToolbarMetrics.segmentHeight)
                .background(
                    RoundedRectangle(cornerRadius: ToolbarMetrics.segmentCorner)
                        .fill(isSelected ? ToolbarMetrics.selectedFill : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hint(hint, state: state)
    }
}

extension SegmentButton where Label == SegmentTextLabel {
    /// 文字（とアイコン）のセグメント
    init(
        state: EditorState,
        symbol: String? = nil,
        text: String,
        hint: String,
        isSelected: Bool,
        action: @escaping @MainActor () -> Void
    ) {
        self.init(state: state, hint: hint, isSelected: isSelected, action: action) {
            SegmentTextLabel(symbol: symbol, text: text)
        }
    }
}

struct SegmentTextLabel: View {
    let symbol: String?
    let text: String

    var body: some View {
        HStack(spacing: 3) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .medium))
            }
            Text(text)
                .lineLimit(1)
                .fixedSize()
        }
    }
}

// MARK: - 1 行目のボタン

/// 1 行目の部品の枠（すべて同じ大きさ。選んでいるものは同じ色の背景）
private struct ToolbarCell<Content: View>: View {
    var isSelected = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(width: ToolbarMetrics.cell.width, height: ToolbarMetrics.cell.height)
            .background(
                RoundedRectangle(cornerRadius: ToolbarMetrics.cellCorner)
                    .fill(isSelected ? ToolbarMetrics.selectedFill : .clear)
            )
            .contentShape(Rectangle())
    }
}

struct ToolbarIconButton: View {
    @ObservedObject var state: EditorState
    let symbol: String
    let hint: String
    var isSelected = false
    var isEnabled = true
    let action: @MainActor () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            ToolbarCell(isSelected: isSelected) {
                Image(systemName: symbol)
                    .font(ToolbarMetrics.iconFont)
                    .foregroundStyle(isSelected ? ToolbarMetrics.selectedForeground : Color.primary)
            }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
        .hint(hint, state: state, role: isEnabled ? .pressable : .inactive)
    }
}

struct ToolButton: View {
    @ObservedObject var state: EditorState
    let tool: Tool

    var body: some View {
        ToolbarIconButton(
            state: state,
            symbol: tool.symbolName,
            hint: "\(tool.labelWithShortcut)：\(tool.usage)",
            isSelected: state.tool == tool
        ) {
            state.tool = tool
        }
    }
}

// MARK: - 説明とカーソル

extension View {
    /// マウスを乗せている間、説明のポップアップの中身を差し替え、部品の種類（role）に合ったカーソルにする
    func hint(_ text: String, state: EditorState, role: HoverRole = .pressable) -> some View {
        self
            .onHover { hovering in
                if hovering {
                    state.hoverHint = text
                } else if state.hoverHint == text {
                    state.hoverHint = nil
                }
            }
            .hoverRole(role)
    }
}
