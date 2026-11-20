import AppKit
import SwiftUI

/// 浮かせた画像の下側に出す、よく使う操作のバー（不透明度・拡大率・コピー・保存・保存先を開く・文字・履歴・そのほか・編集）。
/// 左端に動かすつまみ ✙ を置く。編集モードでも、ツールバーの上のバーとしてこのバーをそのまま出し（isEditing）、
/// 違うのは「編集」が「完了」になることだけ（編集に入る前と後で、同じ場所に同じ見た目・同じ役割のボタンがある）。
/// 閉じるボタン（×）は、画像の左上の外側に別に出す
/// 画像を隠さないよう、いつも画像の外（下）に出す（PinCanvasView+Outside.swift）
struct QuickActionBar: View {
    @ObservedObject var appearance: PinAppearance
    var edit: () -> Void
    var setOpacity: (Double) -> Void
    var setZoom: (Double) -> Void
    var copy: () -> Void
    var save: () -> Void
    /// 画像の文字を読み取ってコピーする（範囲を選ぶときは「…」から）
    var copyText: () -> Void
    var more: () -> Void
    /// 撮った画像の履歴を開く
    var history: () -> Void
    /// 編集中の形にする（「編集」の代わりに「完了」。edit は編集を終える）
    var isEditing = false
    /// ✙ のドラッグで動かす
    var move: () -> Void
    var endMove: () -> Void
    var moveHelp = "ドラッグで画像を移動"

    private static let editHelp = "編集する（ダブルクリック・⌘E でも入れる）"

    var body: some View {
        HStack(spacing: 2) {
            moveHandle
            divider
            // 画像の不透明度と表示の拡大率（編集モードのツールバーにも、同じ位置に同じ形で出す）
            ViewControls(appearance: appearance, setOpacity: setOpacity, setZoom: setZoom)
                .padding(.leading, 2)

            divider
            QuickActionButton(symbol: "doc.on.doc", help: "コピー（⌘C）", action: copy)
            QuickActionButton(symbol: "square.and.arrow.down", help: "保存（⌘S）", action: save)
            // 保存した画像を見に行けるよう、保存先のフォルダを開く（どの画像からでも同じフォルダ）
            QuickActionButton(symbol: "folder", help: "保存先のフォルダを Finder で開く", action: { ImageSaver.openSaveFolder() })
            QuickActionButton(symbol: "text.viewfinder", help: "文字をコピー（⇧⌘T）：画像の文字を読み取る。範囲を選ぶときは「…」から", action: copyText)
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

    /// ドラッグで画像（ツールバーを切り離しているときはツールバー）を動かすつまみ
    private var moveHandle: some View {
        Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white.opacity(0.85))
            .frame(width: 22, height: 22)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onChanged { _ in move() }
                    .onEnded { _ in endMove() }
            )
            .help(moveHelp)
            .hoverRole(.movable)
    }

    /// 編集モードに入るボタン（文字も付けて分かりやすくする）。編集中は、同じ位置・形の「完了」
    private var editButton: some View {
        Button(action: edit) {
            Label(isEditing ? "完了" : "編集", systemImage: isEditing ? "checkmark" : "pencil")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .frame(height: 22)
                .background(Capsule().fill(Color.accentColor))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(isEditing ? "編集を終える（esc・⌘E）" : Self.editHelp)
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
