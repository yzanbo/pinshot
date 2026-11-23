import CoreGraphics
import Foundation

/// 画面の録画の決まり（画面やファイルに関係ない部分。テストで確かめる）
enum RecordingRules {
    /// 録画の長さの上限（秒）。来たら自動で止める
    static let maxDuration: TimeInterval = 10 * 60
    /// 録画のコマの数（1 秒あたり）
    static let framesPerSecond: Int32 = 30

    /// 録画の大きさ（ピクセル）。H.264 は幅と高さが偶数でないと書けないので、偶数に切り下げる（最低 2）
    static func pixelSize(points: CGSize, scale: CGFloat) -> (width: Int, height: Int) {
        func even(_ value: CGFloat) -> Int { max(2, Int(value) / 2 * 2) }
        return (even(points.width * scale), even(points.height * scale))
    }

    /// スクリーン座標（AppKit。左下が原点）の rect を、画面の左上を原点にした範囲（ポイント）にする（ScreenCaptureKit の sourceRect）
    static func localRect(_ rect: CGRect, inScreenFrame frame: CGRect) -> CGRect {
        CGRect(x: rect.minX - frame.minX, y: frame.maxY - rect.maxY, width: rect.width, height: rect.height)
    }

    /// 経過時間の表示（例: 「0:07」「12:30」）
    static func elapsedText(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// 録画のファイル名（例: 「Pinshot 録画 2026-11-20 15.40.12.mp4」）
    static func fileName(for date: Date, extension ext: String) -> String {
        SaveLocation.fileName(prefix: "Pinshot 録画", date: date, extension: ext)
    }

    /// GIF の 1 秒あたりのコマの数。長い録画は、コマが maxFrames を超えないよう下げる（最低 2）
    static func gifFramesPerSecond(duration: TimeInterval, preferred: Double = 10, maxFrames: Int = 600) -> Double {
        guard duration > 0 else { return preferred }
        return max(2, min(preferred, Double(maxFrames) / duration))
    }

    /// GIF にするコマの時刻（秒）
    static func gifFrameTimes(duration: TimeInterval, framesPerSecond: Double) -> [TimeInterval] {
        guard duration > 0, framesPerSecond > 0 else { return [0] }
        let count = max(1, Int((duration * framesPerSecond).rounded(.down)))
        return (0..<count).map { Double($0) / framesPerSecond }
    }

    /// GIF の長い辺の上限（ピクセル。GIF は大きいと重いため）
    static let gifMaxSide: CGFloat = 800

    /// GIF を上げるときに試す作り方（上から順に。大きすぎたら、次の小さい作り方で作り直す）。
    /// いちばん上は「GIF で保存」と同じ。下へ行くほど、長い辺・1 秒あたりのコマ・コマの数の上限を小さくする
    static let gifUploadSteps: [GIFSettings] = [
        .standard,
        GIFSettings(maxSide: 640, framesPerSecond: 8, maxFrames: 400),
        GIFSettings(maxSide: 480, framesPerSecond: 6, maxFrames: 300),
        GIFSettings(maxSide: 360, framesPerSecond: 5, maxFrames: 200),
    ]

    /// 残す決まりから外れた録画（期間を過ぎたもの・数を超えた古いもの）。期間を過ぎたものは、数に数えない
    static func expired(_ files: [(url: URL, date: Date)], now: Date, period: TimeInterval?, keep: Int) -> [URL] {
        var kept = 0
        return files.sorted { $0.date > $1.date }.compactMap { file in
            if let period, now.timeIntervalSince(file.date) > period { return file.url }
            kept += 1
            return kept > keep ? file.url : nil
        }
    }

    /// 本数と容量（例: 「12 本・340 MB」。なければ「なし」）
    static func summaryText(count: Int, bytes: Int64) -> String {
        count == 0 ? "なし" : "\(count) 本・\(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))"
    }
}

/// 録画に入れる音（範囲を選ぶ画面の下のバー・メニューバーの「録画の音」で選ぶ。選んだものは次の録画でも使う）
enum RecordingAudio: String, CaseIterable, Identifiable {
    /// 音を録らない
    case none
    /// Mac の音（アプリ・動画などの音。Pinshot 自身の音は入れない）
    case system
    /// マイクの音（声など）
    case microphone
    /// Mac の音とマイクの音（1 本の音に混ぜる）
    case systemAndMicrophone

    var id: String { rawValue }

    /// 名前（選択肢・メニューバー・知らせに出す）
    var label: String {
        switch self {
        case .none: "音なし"
        case .system: "Mac の音"
        case .microphone: "マイクの音"
        case .systemAndMicrophone: "Mac の音＋マイクの音"
        }
    }

    /// 範囲を選ぶ画面の下のバーのボタン・メニューバーの「録画の音（…）」に出す短い名前（ボタンの幅に収める）
    var shortLabel: String {
        switch self {
        case .none: "音なし"
        case .system: "Mac の音"
        case .microphone: "マイク"
        case .systemAndMicrophone: "Mac＋マイク"
        }
    }

    /// 選択肢の名前の下に出す説明（何の音が入るか）
    var detail: String {
        switch self {
        case .none: "映像だけを録画する"
        case .system: "アプリや動画など、Mac から出る音"
        case .microphone: "自分の声など、マイクが拾う音"
        case .systemAndMicrophone: "Mac から出る音と、自分の声の両方"
        }
    }

    var symbolName: String {
        switch self {
        case .none: "speaker.slash"
        case .system: "speaker.wave.2"
        case .microphone: "mic"
        case .systemAndMicrophone: "waveform.and.mic"
        }
    }

    var capturesSystemAudio: Bool { self == .system || self == .systemAndMicrophone }
    var capturesMicrophone: Bool { self == .microphone || self == .systemAndMicrophone }

    /// マイクを除いたもの（マイクを使えないときに、マイクなしで録画する）
    var withoutMicrophone: RecordingAudio { capturesSystemAudio ? .system : .none }
}

/// GIF の作り方（長い辺の上限・1 秒あたりのコマの数・コマの数の上限）
struct GIFSettings: Equatable {
    /// 長い辺の上限（ピクセル。元より大きくはしない）
    var maxSide: CGFloat
    /// 1 秒あたりのコマの数（長い録画は、コマが maxFrames を超えないよう下げる）
    var framesPerSecond: Double
    var maxFrames: Int

    /// 「GIF で保存」の作り方（長い辺 800・1 秒 10 コマ・600 コマまで）
    static let standard = GIFSettings(maxSide: RecordingRules.gifMaxSide, framesPerSecond: 10, maxFrames: 600)

    /// duration 秒の録画で使う、1 秒あたりのコマの数
    func framesPerSecond(duration: TimeInterval) -> Double {
        RecordingRules.gifFramesPerSecond(duration: duration, preferred: framesPerSecond, maxFrames: maxFrames)
    }
}

/// 録画をアプリの中に残す数の上限
enum RecordingLimit: Int, CaseIterable, Identifiable {
    case ten = 10
    case twenty = 20
    case fifty = 50
    case hundred = 100

    var id: Int { rawValue }
    var label: String { "\(rawValue) 本" }
}
