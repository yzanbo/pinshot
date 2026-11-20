import Foundation

/// 上げたものの履歴の 1 件（画面やネットに関わらない。テストにも入れる）。
/// 一覧（uploads.json）と、小さな縮小画像（id の名前の PNG）を、アプリ用のフォルダに置く
struct UploadHistoryEntry: Codable, Identifiable, Equatable {
    var id: UUID
    /// 上げた日時
    var date: Date
    /// 保存先に上げたファイル（消すときに使う）
    var remote: RemoteFile
    /// 共有リンク
    var link: SharedLink
    var kind: ExportKind
    /// 保存先に付けたファイル名
    var fileName: String

    var destination: UploadDestinationID { remote.destination }

    /// 一覧に出す縮小画像のファイル名
    var thumbnailFileName: String { "\(id.uuidString).thumb.png" }
}

extension ExportKind: Codable {}

/// 上げたものの履歴の決まり
enum UploadHistoryRules {
    /// 新しいものを先頭に足す（同じ ID のものがあれば置き換える）
    static func adding(_ entry: UploadHistoryEntry, to entries: [UploadHistoryEntry]) -> [UploadHistoryEntry] {
        [entry] + entries.filter { $0.id != entry.id }
    }

    /// 一覧に出す、日時と保存先（例: 「11月20日 15:40・Gyazo」）
    static func subtitle(for entry: UploadHistoryEntry, now: Date = Date(), calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        if calendar.isDate(entry.date, inSameDayAs: now) {
            formatter.dateFormat = "'今日' H:mm"
        } else if calendar.isDate(entry.date, equalTo: now, toGranularity: .year) {
            formatter.dateFormat = "M月d日 H:mm"
        } else {
            formatter.dateFormat = "yyyy年M月d日 H:mm"
        }
        return "\(formatter.string(from: entry.date))・\(entry.destination.label)"
    }
}
