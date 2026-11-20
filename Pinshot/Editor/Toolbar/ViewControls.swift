import SwiftUI

/// 浮かせた画像の見た目（不透明度と表示の拡大率）を、いつでも見て変えられる部品。
/// 操作バー（編集していないとき）と編集モードのツールバーの両方に、同じ形・同じ位置（コピー・保存の左）で置く
struct ViewControls: View {
    enum Style {
        /// 操作バー（黒い半透明の台に白い文字）
        case onDark
        /// 編集モードのツールバー（ふつうの文字の色）
        case toolbar
    }

    @ObservedObject var appearance: PinAppearance
    let style: Style
    /// ツールバーのときは、ボタンに乗せたときの説明をツールバーの説明の欄に出す（操作バーはヘルプのタグ）
    var editorState: EditorState?
    var setOpacity: (Double) -> Void
    var setZoom: (Double) -> Void

    /// 拡大率の一覧
    static let zoomPresets: [Double] = [0.25, 0.5, 0.75, 1, 1.5, 2, 3, 4]

    private var foreground: Color { style == .onDark ? .white : .primary }

    var body: some View {
        HStack(spacing: 6) {
            opacityControl
            zoomControl
        }
    }

    /// 不透明度（◑ スライダー 数字）
    private var opacityControl: some View {
        HStack(spacing: 4) {
            Image(systemName: "circle.lefthalf.filled")
                .font(.system(size: 11, weight: .semibold))
            Slider(
                value: Binding(get: { appearance.opacity }, set: { setOpacity($0) }),
                in: 0.1...1
            )
            .controlSize(.mini)
            .frame(width: 48)
            .tint(style == .onDark ? .white : .accentColor)
            Text(Self.percent(appearance.opacity))
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .frame(width: 30, alignment: .trailing)
        }
        .foregroundStyle(foreground)
        .padding(.leading, 4)
        .describe("画像の不透明度（⌘ か ⌥ を押しながらスクロールしても変えられる）", state: editorState)
    }

    /// 表示の拡大率（🔍 数字 ▾。押すと一覧）
    private var zoomControl: some View {
        Button {
            PopupMenu.popUp(
                [.item(title: "実寸に戻す（100%）") { setZoom(1) }, .separator]
                    + Self.zoomPresets.map { value in
                        .item(title: Self.percent(value), isChecked: abs(appearance.zoom - value) < 0.005) { setZoom(value) }
                    }
            )
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .semibold))
                Text(Self.percent(appearance.zoom))
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .frame(minWidth: 30, alignment: .trailing)
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .bold))
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 6)
            .frame(height: 22)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .describe("表示の拡大率（押すと一覧。画像の上でスクロール・ピンチ、端のドラッグでも変えられる）", state: editorState)
    }

    static func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}

private extension View {
    /// ツールバーではツールバーの説明の欄に、操作バーではヘルプのタグに説明を出す
    @ViewBuilder
    func describe(_ text: String, state: EditorState?) -> some View {
        if let state {
            hint(text, state: state)
        } else {
            help(text).hoverRole()
        }
    }
}
