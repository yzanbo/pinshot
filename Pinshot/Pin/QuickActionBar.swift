import AppKit
import SwiftUI

/// 浮かせた画像の見た目（操作バーのスライダーと、⌥ + スクロールなどで変えた値を同じにする）
@MainActor
final class PinAppearance: ObservableObject {
    @Published var opacity: Double

    init(opacity: Double) {
        self.opacity = opacity
    }
}

/// 操作バーの形（画像の幅に合わせて、入りきる中でいちばん多いものを選ぶ）
enum QuickBarStyle: Int, CaseIterable {
    /// 編集（文字付き）・不透明度・コピー・保存・そのほか
    case full
    /// 編集（文字付き）・コピー・保存・そのほか（不透明度は「そのほか」のメニューから）
    case standard
    /// 編集（アイコン）・そのほか
    case compact
    /// 編集（アイコン）だけ。どんなに小さくても、これだけは出す
    case minimal

    /// 広いものから順に
    static let widestFirst: [QuickBarStyle] = [.full, .standard, .compact, .minimal]
}

/// 浮かせた画像の下側に出す、よく使う操作のバー（編集・不透明度・コピー・保存・そのほか）
struct QuickActionBar: View {
    @ObservedObject var appearance: PinAppearance
    var style: QuickBarStyle = .full
    var edit: () -> Void
    var setOpacity: (Double) -> Void
    var copy: () -> Void
    var save: () -> Void
    var more: () -> Void

    private static let editHelp = "編集する（ダブルクリック・⌘E でも入れる）"

    var body: some View {
        HStack(spacing: 2) {
            editButton

            if style == .full {
                divider
                // 画像の不透明度（ドラッグで変える）
                HStack(spacing: 4) {
                    Image(systemName: "circle.lefthalf.filled")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                    Slider(
                        value: Binding(get: { appearance.opacity }, set: { setOpacity($0) }),
                        in: 0.1...1
                    )
                    .controlSize(.mini)
                    .frame(width: 64)
                    .tint(.white)
                    Text("\(Int((appearance.opacity * 100).rounded()))%")
                        .font(.system(size: 10, weight: .medium).monospacedDigit())
                        .foregroundStyle(.white)
                        .frame(width: 30, alignment: .trailing)
                }
                .padding(.leading, 6)
                .help("画像の不透明度（⌘ か ⌥ を押しながらスクロールしても変えられる）")
                .hoverCursor(.arrow)
            }

            if style == .full || style == .standard {
                divider
                QuickActionButton(symbol: "doc.on.doc", help: "コピー（⌘C）", action: copy)
                QuickActionButton(symbol: "square.and.arrow.down", help: "保存（⌘S）", action: save)
            }

            if style != .minimal {
                QuickActionButton(symbol: "ellipsis", help: "そのほかの操作（不透明度・コピー・保存など）", action: more)
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.black.opacity(0.6)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.25)))
        .fixedSize()
    }

    /// 編集モードに入るボタン（左端に置き、広いときは文字も付ける。狭いときは丸いアイコンだけ）
    @ViewBuilder
    private var editButton: some View {
        Button(action: edit) {
            if style == .full || style == .standard {
                Label("編集", systemImage: "pencil")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .frame(height: 22)
                    .background(Capsule().fill(Color.accentColor))
                    .contentShape(Capsule())
            } else {
                Image(systemName: "pencil")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.accentColor))
                    .contentShape(Circle())
            }
        }
        .buttonStyle(.plain)
        .help(Self.editHelp)
        .hoverCursor()
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.25))
            .frame(width: 1, height: 14)
            .padding(.horizontal, 3)
    }
}

private struct QuickActionButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .hoverCursor()
    }
}

/// 選んだ書き込みのすぐ上に出す、よく使う操作のバー
struct SelectionActionBar: View {
    var duplicate: () -> Void
    var bringForward: () -> Void
    var sendBackward: () -> Void
    var delete: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            QuickActionButton(symbol: "plus.square.on.square", help: "複製（⌘D）", action: duplicate)
            QuickActionButton(symbol: "square.3.layers.3d.top.filled", help: "前面へ（⌘]）", action: bringForward)
            QuickActionButton(symbol: "square.3.layers.3d.bottom.filled", help: "背面へ（⌘[）", action: sendBackward)
            QuickActionButton(symbol: "trash", help: "削除（delete）", action: delete)
        }
        .padding(3)
        .background(Capsule().fill(Color.black.opacity(0.7)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.25)))
        .fixedSize()
    }
}
