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

/// 録画をアプリの中に残す数の上限
enum RecordingLimit: Int, CaseIterable, Identifiable {
    case ten = 10
    case twenty = 20
    case fifty = 50
    case hundred = 100

    var id: Int { rawValue }
    var label: String { "\(rawValue) 本" }
}
