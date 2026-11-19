import SwiftUI

/// アイコンの枠と ▾ の枠を並べたボタン。アイコンを押すと primaryAction（なければメニュー）、▾ でメニュー。
/// アイコンは固定の幅の枠の真ん中に置くので、アイコンが変わっても ▾ の位置は変わらない
private struct SplitMenuButton<Icon: View>: View {
    @ObservedObject var state: EditorState
    let hint: String
    var isSelected = false
    var primaryAction: (@MainActor () -> Void)?
    let menu: @MainActor () -> [MenuEntry]
    @ViewBuilder var icon: Icon

    var body: some View {
        HStack(spacing: 0) {
            Button {
                if let primaryAction {
                    primaryAction()
                } else {
                    PopupMenu.popUp(menu())
                }
            } label: {
                icon
                    .frame(width: ToolbarMetrics.iconWidth, height: ToolbarMetrics.cell.height)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                PopupMenu.popUp(menu())
            } label: {
                Image(systemName: "chevron.down")
                    .font(ToolbarMetrics.chevronFont)
                    .foregroundStyle(isSelected ? ToolbarMetrics.selectedForeground.opacity(0.85) : Color.secondary)
                    .frame(width: ToolbarMetrics.chevronWidth, height: ToolbarMetrics.cell.height)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(width: ToolbarMetrics.groupCellWidth, height: ToolbarMetrics.cell.height)
        .background(
            RoundedRectangle(cornerRadius: ToolbarMetrics.cellCorner)
                .fill(isSelected ? ToolbarMetrics.selectedFill : .clear)
        )
        .hint(hint, state: state)
    }
}

/// 似たツールをまとめたボタン（押すと最後に使ったツール、▾ でほかのツール）
struct ToolGroupButton: View {
    @ObservedObject var state: EditorState
    let group: ToolGroup

    private var current: Tool { state.lastToolInGroup[group] ?? group.tools[0] }
    private var isSelected: Bool { group.tools.contains(state.tool) }

    var body: some View {
        if group.tools.count == 1 {
            ToolButton(state: state, tool: group.tools[0])
        } else {
            SplitMenuButton(
                state: state,
                hint: "\(group.label)：押すと「\(current.label)（\(current.shortcut.uppercased())）」、▾ で \(group.tools.map { "\($0.label)（\($0.shortcut.uppercased())）" }.joined(separator: "・")) から選ぶ",
                isSelected: isSelected,
                primaryAction: { state.tool = current },
                menu: {
                    group.tools.map { tool in
                        .item(
                            title: "\(tool.label)（\(tool.shortcut.uppercased())）",
                            image: NSImage(systemSymbolName: tool.symbolName, accessibilityDescription: tool.label),
                            isChecked: state.tool == tool
                        ) { state.tool = tool }
                    }
                }
            ) {
                Image(systemName: current.symbolName)
                    .font(ToolbarMetrics.iconFont)
                    .foregroundStyle(isSelected ? ToolbarMetrics.selectedForeground : Color.primary)
            }
        }
    }
}

/// 色のボタン（押すと色の一覧）
struct ColorMenuButton: View {
    @ObservedObject var state: EditorState

    var body: some View {
        SplitMenuButton(
            state: state,
            hint: "色：\(state.color.name)（押すと色の一覧。1〜6 キーでも選べる）",
            menu: {
                var entries: [MenuEntry] = (RGBAColor.palette + state.customColors).map { color in
                    .item(title: color.name, image: color.swatchImage(diameter: 12), isChecked: state.color == color) {
                        state.color = color
                    }
                }
                entries.append(.separator)
                entries.append(.item(title: "オリジナルの色…") { ColorPanelController.shared.open(for: state) })
                return entries
            }
        ) {
            Circle()
                .fill(Color(nsColor: state.color.nsColor))
                .frame(width: ToolbarMetrics.swatchSize, height: ToolbarMetrics.swatchSize)
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.25), lineWidth: 1))
        }
    }
}

/// 背景のボタン（押すと付ける・外す、▾ で色・余白・角の丸み・影。書き出しも同じ見た目）
struct BackdropMenuButton: View {
    @ObservedObject var state: EditorState

    var body: some View {
        SplitMenuButton(
            state: state,
            hint: "背景：押すと付ける・外す（書き出しも同じ見た目）、▾ で色・余白・角の丸み・影を選ぶ",
            isSelected: state.backdropShown,
            primaryAction: { state.setBackdropShown(!state.backdropShown) },
            menu: {
                let decoration = state.backdropDecoration
                let shown = state.backdropShown
                var entries: [MenuEntry] = [
                    .item(title: shown ? "背景を外す" : "背景を付ける") { state.setBackdropShown(!shown) },
                    .separator,
                ]
                entries += ExportBackground.allCases.map { background in
                    .item(title: background.label, image: background.swatchImage(diameter: 12), isChecked: shown && decoration.background == background) {
                        state.updateBackdrop { $0.background = background }
                    }
                }
                entries.append(.separator)
                entries += ExportPadding.allCases.map { padding in
                    .item(title: "余白：\(padding.label)", isChecked: shown && decoration.padding == padding) {
                        state.updateBackdrop { $0.padding = padding }
                    }
                }
                entries.append(.separator)
                entries += ExportCorner.allCases.map { corner in
                    .item(title: "角の丸み：\(corner.label)", isChecked: shown && decoration.corner == corner) {
                        state.updateBackdrop { $0.corner = corner }
                    }
                }
                entries.append(.separator)
                entries.append(.item(title: "影を付ける", isChecked: shown && decoration.shadow) {
                    state.updateBackdrop { $0.shadow.toggle() }
                })
                return entries
            }
        ) {
            Image(systemName: "photo.artframe")
                .font(ToolbarMetrics.iconFont)
                .foregroundStyle(state.backdropShown ? ToolbarMetrics.selectedForeground : Color.primary)
        }
    }
}

extension ExportBackground {
    /// メニューに出す、背景の丸い見本（グラデーションは左上から右下へ）
    func swatchImage(diameter: CGFloat) -> NSImage {
        let size = NSSize(width: diameter + 2, height: diameter + 2)
        let colors = self.colors.map(\.nsColor)
        return NSImage(size: size, flipped: false) { rect in
            let circle = NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1))
            if colors.count >= 2, let gradient = NSGradient(colors: colors) {
                gradient.draw(in: circle, angle: -45)
            } else {
                (colors.first ?? .white).setFill()
                circle.fill()
            }
            NSColor.black.withAlphaComponent(0.25).setStroke()
            circle.lineWidth = 1
            circle.stroke()
            return true
        }
    }
}

/// スタイルのボタン（保存したスタイルを名前で呼び出す・保存する・名前を変える・上書き・消す）
struct PresetMenuButton: View {
    @ObservedObject var state: EditorState
    @ObservedObject var store = StylePresetStore.shared

    var body: some View {
        ToolbarIconButton(state: state, symbol: "paintpalette", hint: "スタイル：保存した色・太さ・オプションを名前で呼び出す・保存する") {
            PopupMenu.popUp(entries)
        }
    }

    private var entries: [MenuEntry] {
        let presets = store.presets
        var entries: [MenuEntry] = presets.map { preset in
            .item(title: preset.name, image: preset.color.withAlpha(CGFloat(preset.opacity)).swatchImage(diameter: 12)) {
                state.apply(preset)
            }
        }
        if presets.isEmpty {
            entries.append(.disabled(title: "保存したスタイルはありません"))
        }
        entries.append(.separator)
        entries.append(.item(title: "いまのスタイルを保存…") {
            TextInputController.shared.show(initial: store.suggestedName, width: 220, placeholder: "スタイルの名前") { text in
                let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return false }
                store.add(state.makePreset(name: name))
                return true
            }
        })
        if !presets.isEmpty {
            entries.append(.submenu(title: "名前を変える", entries: presets.map { preset in
                .item(title: preset.name) {
                    TextInputController.shared.show(initial: preset.name, width: 220, placeholder: "スタイルの名前") { text in
                        let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !name.isEmpty else { return false }
                        store.rename(preset.id, to: name)
                        return true
                    }
                }
            }))
            entries.append(.submenu(title: "いまのスタイルで上書き", entries: presets.map { preset in
                .item(title: preset.name) { store.overwrite(preset.id, with: state.makePreset(name: preset.name)) }
            }))
            entries.append(.submenu(title: "消す", entries: presets.map { preset in
                .item(title: preset.name) { store.remove(preset.id) }
            }))
        }
        return entries
    }
}
