import AppKit
import SwiftUI

/// 範囲選択の画面の下に出す、モード・録画の音・タイマーを選ぶバー
struct CaptureModeBar: View {
    /// バーの中の場所を測る座標（左上が原点。バーのホスティングビューと同じ）
    static let space = "CaptureModeBar"

    @ObservedObject var options: CaptureOptions
    @ObservedObject var audioPicker: RecordingAudioPicker
    /// 録画の音は、次の録画でも使うので、設定に置く
    @ObservedObject var settings = AppSettings.shared
    let cancel: () -> Void

    /// ボタンからマウスが離れたときに戻すカーソル（いまのモードのキャプチャ用のカーソル）
    private var exitCursor: NSCursor { CaptureCursors.cursor(for: options) }

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
                        audioPicker.isOpen = false
                        options.mode = mode
                        // 「録画」を押したら、ウィンドウだけでなく、ドラッグで範囲も選べる録画にする
                        if mode == .record { options.recordsWindowOnly = false }
                    }
                    if mode == .record { audioButton }
                }

                separator

                // メニューは全画面の膜の下に隠れてしまうので、押すたびに切り替える
                BarButton(
                    symbol: "timer",
                    title: options.timer == 0 ? "タイマーなし" : "\(options.timer) 秒後",
                    isSelected: options.timer > 0,
                    exitCursor: exitCursor
                ) {
                    audioPicker.isOpen = false
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
        .coordinateSpace(name: Self.space)
        .onPreferenceChange(AudioButtonFrameKey.self) { audioPicker.buttonFrame = $0 }
    }

    /// 録画の音（「録画」のすぐ右。押すと、上に 4 つの選択肢を出す。録画のときだけ押せる。
    /// バーの幅が変わらないよう、静止画を撮るときも薄くして出しておく）
    private var audioButton: some View {
        BarButton(
            symbol: settings.recordingAudio.symbolName,
            title: settings.recordingAudio.shortLabel,
            isSelected: audioPicker.isOpen || (options.mode == .record && settings.recordingAudio != .none),
            isEnabled: options.mode == .record,
            exitCursor: exitCursor
        ) {
            audioPicker.isOpen.toggle()
        }
        .help(options.mode == .record ? "録画の音を選ぶ（次の録画でも使う）" : "録画の音（録画のときに選べる）")
        // 選択肢を、このボタンの上に出すため、バーの中の場所を知らせる
        .background(GeometryReader { proxy in
            Color.clear.preference(key: AudioButtonFrameKey.self, value: proxy.frame(in: .named(Self.space)))
        })
    }

    /// 下の案内（space で切り替えられないとき（録画）は、space の案内を出さない）
    private var hintText: String {
        options.togglesWithSpace
            ? "\(options.hint)　・　space で範囲 ⇄ ウィンドウ　・　esc でキャンセル"
            : "\(options.hint)　・　esc でキャンセル"
    }

    /// まとまりの間の縦の線
    private var separator: some View {
        Rectangle()
            .fill(Color.white.opacity(0.2))
            .frame(width: 1, height: 36)
            .padding(.horizontal, 4)
    }
}

/// 「録画の音」のボタンの、バーの中の場所
private struct AudioButtonFrameKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

/// 範囲を選ぶ画面の「録画の音」の選択肢を出しているか。macOS のメニューは全画面の膜の下に隠れてしまうので、
/// 選択肢は膜の上に描く（出す・片付けるのは SelectionController）
@MainActor
final class RecordingAudioPicker: ObservableObject {
    @Published var isOpen = false
    /// 選択肢の上でマウスを乗せている項目
    @Published var hovered: RecordingAudio?
    /// 下のバーの中の「録画の音」のボタンの場所（バーの左上が原点）
    var buttonFrame: CGRect = .zero
}

/// 「録画の音」の選択肢（ボタンの上に出す。いま選んでいるものにチェック。選んだら閉じる）
struct RecordingAudioMenu: View {
    @ObservedObject var picker: RecordingAudioPicker
    @ObservedObject var settings = AppSettings.shared
    /// 項目からマウスが離れたときに戻すカーソル（キャプチャ用のカーソル）
    let exitCursor: NSCursor
    let choose: (RecordingAudio) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("録画の音")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
                .padding(.horizontal, 10)
                .padding(.vertical, 2)
            ForEach(RecordingAudio.allCases) { audio in
                Button { choose(audio) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: audio.symbolName)
                            .font(.system(size: 13, weight: .medium))
                            .frame(width: 20)
                        // 名前と、何の音が入るかの説明（どちらも省略せず、選択肢の幅を中身に合わせる）
                        VStack(alignment: .leading, spacing: 1) {
                            Text(audio.label)
                                .font(.system(size: 13, weight: .medium))
                            Text(audio.detail)
                                .font(.system(size: 10.5))
                                .foregroundStyle(.white.opacity(0.65))
                        }
                        .fixedSize()
                        Spacer(minLength: 16)
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .opacity(settings.recordingAudio == audio ? 1 : 0)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(picker.hovered == audio ? Color.accentColor.opacity(0.75) : Color.white.opacity(0.001))
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { inside in
                    if inside { picker.hovered = audio } else if picker.hovered == audio { picker.hovered = nil }
                }
                .hoverRole(exit: exitCursor)
            }
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.82)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(0.15)))
        .fixedSize()
    }
}

private struct BarButton: View {
    let symbol: String
    let title: String
    let isSelected: Bool
    /// 押せないときは薄くする
    var isEnabled = true
    let exitCursor: NSCursor
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .medium))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    // ボタンの幅に入りきらないときは、省略せずに少し小さくする
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
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
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
        // 乗せている間は指（押せないときは矢印）、離れたらキャプチャ用のカーソル（矢印に戻すと、キャプチャ用のカーソルと取り合ってちらつく）
        .hoverRole(isEnabled ? .pressable : .inactive, exit: exitCursor)
    }
}
