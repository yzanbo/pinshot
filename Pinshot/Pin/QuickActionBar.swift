import AppKit
import SwiftUI

/// 浮かせた画像の見た目（操作バーのスライダーと、⌥ + スクロールなどで変えた値を同じにする）
@MainActor
final class PinAppearance: ObservableObject {
    @Published var opacity: Double
    /// 表示の拡大率（1 が実寸）
    @Published var zoom: Double

    init(opacity: Double, zoom: Double = 1) {
        self.opacity = opacity
        self.zoom = zoom
    }
}

/// 浮かせた画像の下側に出す、よく使う操作のバー（不透明度・拡大率・コピー・保存・履歴・そのほか・編集）。
/// 並びは編集モードのツールバー（… 不透明度・拡大率 | コピー・保存 | 履歴 表示 完了）とそろえ、
/// 「…」を表示のメニュー、「編集」を「完了」と同じ位置に置く（編集に入る前と後で、同じ場所に同じ役割のボタンがある）。
/// 閉じるボタン（×）は、画像の左上の外側に別に出す
/// 画像を隠さないよう、いつも画像の外（下）に出す（PinCanvasView+Outside.swift）
struct QuickActionBar: View {
    @ObservedObject var appearance: PinAppearance
    var edit: () -> Void
    var setOpacity: (Double) -> Void
    var setZoom: (Double) -> Void
    var copy: () -> Void
    var save: () -> Void
    var more: () -> Void
    /// 撮った画像の履歴を開く
    var history: () -> Void

    private static let editHelp = "編集する（ダブルクリック・⌘E でも入れる）"

    var body: some View {
        HStack(spacing: 2) {
            // 画像の不透明度と表示の拡大率（編集モードのツールバーにも、同じ位置に同じ形で出す）
            ViewControls(appearance: appearance, style: .onDark, setOpacity: setOpacity, setZoom: setZoom)
                .padding(.leading, 2)

            divider
            QuickActionButton(symbol: "doc.on.doc", help: "コピー（⌘C）", action: copy)
            QuickActionButton(symbol: "square.and.arrow.down", help: "保存（⌘S）", action: save)
            divider
            QuickActionButton(symbol: "clock.arrow.circlepath", help: "撮った画像の履歴", action: history)
            QuickActionButton(symbol: "ellipsis", help: "そのほかの操作", action: more)
            editButton
        }
        .padding(3)
        .background(Capsule().fill(Color.black.opacity(0.6)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.25)))
        .fixedSize()
    }

    /// 編集モードに入るボタン（文字も付けて分かりやすくする。編集モードの「完了」と同じ位置・形）
    private var editButton: some View {
        Button(action: edit) {
            Label("編集", systemImage: "pencil")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .frame(height: 22)
                .background(Capsule().fill(Color.accentColor))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(Self.editHelp)
        .hoverRole()
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
        .hoverRole()
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
