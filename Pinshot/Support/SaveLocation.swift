import Foundation
import UniformTypeIdentifiers

/// 書き出すものの種類（保存するとき、種類ごとにフォルダを分けられる）
enum ExportKind: String, CaseIterable, Identifiable {
    case image
    case gif
    case movie

    var id: String { rawValue }

    var label: String {
        switch self {
        case .image: "画像（PNG）"
        case .gif: "GIF"
        case .movie: "動画（MP4）"
        }
    }

    /// 種類ごとに分けるときのフォルダ名（画面の言葉にそろえる）
    var folderName: String {
        switch self {
        case .image: "画像"
        case .gif: "GIF"
        case .movie: "動画"
        }
    }

    /// 保存するときの種類（保存先を聞く画面で使う）
    var contentType: UTType {
        switch self {
        case .image: .png
        case .gif: .gif
        case .movie: .mpeg4Movie
        }
    }

    /// 保存するときのファイル名の拡張子
    var fileExtension: String {
        switch self {
        case .image: "png"
        case .gif: "gif"
        case .movie: "mp4"
        }
    }
}

/// 保存したもの（利用者が「保存」したもの）を置く場所の決まり（テストで確かめる）。
/// 保存先（親）は 1 つで、その中を種類ごと・月ごとに分けられる（どちらも選べる。初期設定は分けない）
enum SaveLocation {
    /// 保存先のフォルダ。base が親、byKind で「画像 / GIF / 動画」、byMonth で「2026-11」のフォルダに分ける
    static func folder(base: URL, kind: ExportKind, byKind: Bool, byMonth: Bool, date: Date = Date(), calendar: Calendar = .current) -> URL {
        var folder = base
        if byKind { folder.appendPathComponent(kind.folderName, isDirectory: true) }
        if byMonth { folder.appendPathComponent(monthName(for: date, calendar: calendar), isDirectory: true) }
        return folder
    }

    /// 保存するファイルの名前（例: 「Pinshot 2026-11-20 15.40.12.png」「Pinshot 録画 2026-11-20 15.40.12.mp4」）。
    /// 日時は、並べたときに古い順になる書き方にする
    static func fileName(prefix: String, date: Date, extension ext: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return "\(prefix) \(formatter.string(from: date)).\(ext)"
    }

    /// 月ごとに分けるときのフォルダ名（例: 「2026-11」。並べたときに古い順になる）
    static func monthName(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", parts.year ?? 0, parts.month ?? 0)
    }
}
