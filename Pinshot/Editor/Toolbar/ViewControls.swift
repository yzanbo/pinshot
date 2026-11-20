import SwiftUI

/// 浮かせた画像の見た目（不透明度と表示の拡大率）を、いつでも見て変えられる部品。
/// 操作バー（黒い半透明の台に白い文字）の、コピー・保存の左に置く。編集中もツールバーの上のバーとして同じ操作バーを出す
struct ViewControls: View {
    @ObservedObject var appearance: PinAppearance
    var setOpacity: (Double) -> Void
    var setZoom: (Double) -> Void

    /// 拡大率の一覧
    static let zoomPresets: [Double] = [0.25, 0.5, 0.75, 1, 1.5, 2, 3, 4]

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
            .tint(.white)
            Text(appearance.opacity.percentText)
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .frame(width: 30, alignment: .trailing)
        }
        .foregroundStyle(.white)
        .padding(.leading, 4)
        .help("画像の不透明度（⌘ か ⌥ を押しながらスクロールしても変えられる）")
        .hoverRole()
    }

    /// 表示の拡大率（🔍 数字 ▾。押すと一覧）
    private var zoomControl: some View {
        Button {
            PopupMenu.popUp(
                [.item(title: "実寸に戻す（100%）") { setZoom(1) }, .separator]
                    + Self.zoomPresets.map { value in
                        .item(title: value.percentText, isChecked: abs(appearance.zoom - value) < 0.005) { setZoom(value) }
                    }
            )
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .semibold))
                Text(appearance.zoom.percentText)
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .frame(minWidth: 30, alignment: .trailing)
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .frame(height: 22)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("表示の拡大率（押すと一覧。画像の上でスクロール・ピンチ、端のドラッグでも変えられる）")
        .hoverRole()
    }
}
