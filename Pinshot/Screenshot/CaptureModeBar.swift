import AppKit
import SwiftUI

/// 範囲選択の画面の下に出す、モードとタイマーを選ぶバー
struct CaptureModeBar: View {
    @ObservedObject var options: CaptureOptions
    let cancel: () -> Void

    /// ボタンからマウスが離れたときに戻すカーソル（いまのモードのキャプチャ用のカーソル）
    private var exitCursor: NSCursor { CaptureCursors.cursor(for: options.mode) }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                ForEach(CaptureMode.allCases) { mode in
                    // 録画は、キャプチャ（静止画）と分けて見せる
                    if mode == .record { separator }
                    BarButton(
                        symbol: mode.symbolName,
                        title: mode.label,
                        isSelected: options.mode == mode,
                        exitCursor: exitCursor
                    ) {
                        options.mode = mode
                    }
                }

                separator

                // メニューは全画面の膜の下に隠れてしまうので、押すたびに切り替える
                BarButton(
                    symbol: "timer",
                    title: options.timer == 0 ? "タイマーなし" : "\(options.timer) 秒後",
                    isSelected: options.timer > 0,
                    exitCursor: exitCursor
                ) {
                    options.cycleTimer()
                }
                .help("押すたびに なし → 3 秒 → 5 秒 → 10 秒")

                BarButton(symbol: "xmark", title: "キャンセル", isSelected: false, exitCursor: exitCursor, action: cancel)
            }

            // 案内の文は、ボタンの段の幅に収める（モードによって文の長さが違っても、バーの幅が変わらないように。
            // 1 行の高さだけを取り、文はその上に重ねる。入りきらないときは少し小さくする）
            Color.clear
                .frame(height: 14)
                .overlay {
                    Text(hintText)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.black.opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.white.opacity(0.15))
        )
        .fixedSize()
    }

    /// 下の案内（space で切り替えられないとき（録画）は、space の案内を出さない）
    private var hintText: String {
        options.togglesWithSpace
            ? "\(options.mode.hint)　・　space で範囲 ⇄ ウィンドウ　・　esc でキャンセル"
            : "\(options.mode.hint)　・　esc でキャンセル"
    }

    /// まとまりの間の縦の線
    private var separator: some View {
        Rectangle()
            .fill(Color.white.opacity(0.2))
            .frame(width: 1, height: 36)
            .padding(.horizontal, 4)
    }
}

private struct BarButton: View {
    let symbol: String
    let title: String
    let isSelected: Bool
    let exitCursor: NSCursor
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .medium))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(.white)
            .frame(width: 78, height: 50)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(isSelected ? Color.accentColor.opacity(0.75) : Color.white.opacity(0.001))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // 乗せている間は指、離れたらキャプチャ用のカーソル（矢印に戻すと、キャプチャ用のカーソルと取り合ってちらつく）
        .hoverRole(exit: exitCursor)
    }
}
