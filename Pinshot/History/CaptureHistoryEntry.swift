import Foundation

/// 撮った画像の履歴の 1 枚（画像そのものは、履歴のフォルダに id の名前の PNG で置く）
struct CaptureHistoryEntry: Codable, Identifiable, Equatable {
    var id: UUID
    /// 撮った日時
    var date: Date
    /// 画像の大きさ（ポイント。浮かせるときの大きさ）
    var pointSize: CGSize
    /// 画像の大きさ（ピクセル）
    var pixelSize: CGSize
    /// 画像と縮小画像のファイルの大きさの合計（バイト）
    var byteCount: Int

    /// 画像のファイル名
    var imageFileName: String { "\(id.uuidString).png" }
    /// 一覧に出す縮小画像のファイル名
    var thumbnailFileName: String { "\(id.uuidString).thumb.png" }
}

/// 履歴の一覧の表示方法
enum HistoryLayout: String, CaseIterable, Identifiable {
    /// 大きい縮小画像を並べる
    case largeGrid
    /// 小さい縮小画像をたくさん並べる
    case smallGrid
    /// 1 行に 1 枚（小さい縮小画像と、日時・大きさ・容量）
    case list

    var id: String { rawValue }

    var label: String {
        switch self {
        case .largeGrid: "大きいサムネイル"
        case .smallGrid: "小さいサムネイル"
        case .list: "リスト"
        }
    }

    var symbolName: String {
        switch self {
        case .largeGrid: "square.grid.2x2"
        case .smallGrid: "square.grid.3x3"
        case .list: "list.bullet"
        }
    }
}

/// 履歴を残す期間
enum HistoryPeriod: Int, CaseIterable, Identifiable {
    case day = 1
    case week = 7
    case month = 30
    case forever = 0

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .day: "1 日"
        case .week: "1 週間"
        case .month: "30 日"
        case .forever: "ずっと"
        }
    }

    /// 残す長さ（秒）。nil なら期限なし
    var duration: TimeInterval? {
        self == .forever ? nil : TimeInterval(rawValue) * 24 * 60 * 60
    }
}

/// 履歴に残す枚数の上限
enum HistoryLimit: Int, CaseIterable, Identifiable {
    case fifty = 50
    case hundred = 100
    case threeHundred = 300
    case thousand = 1000

    var id: Int { rawValue }
    var label: String { "\(rawValue) 枚" }
}

/// 履歴の決まり（画面やファイルに関係ない部分。テストで確かめる）
enum CaptureHistoryRules {
    /// 残す決まりから外れた履歴（期間を過ぎたもの・枚数を超えた古いもの）。entries は新しい順
    static func expired(
        _ entries: [CaptureHistoryEntry],
        now: Date,
        period: HistoryPeriod,
        limit: HistoryLimit
    ) -> [CaptureHistoryEntry] {
        var kept = 0
        return entries.filter { entry in
            if let duration = period.duration, now.timeIntervalSince(entry.date) > duration {
                return true
            }
            kept += 1
            return kept > limit.rawValue
        }
    }

    /// 縮小画像の大きさ（ピクセル）。長い辺を maxSide に収め、元より大きくはしない
    static func thumbnailSize(for pixelSize: CGSize, maxSide: CGFloat = 480) -> CGSize {
        let longest = max(pixelSize.width, pixelSize.height, 1)
        let scale = min(1, maxSide / longest)
        return CGSize(
            width: max(1, (pixelSize.width * scale).rounded()),
            height: max(1, (pixelSize.height * scale).rounded())
        )
    }

    /// 一覧で日付ごとにまとめる（新しい日から。日の中も新しい順）
    static func groupedByDay(
        _ entries: [CaptureHistoryEntry],
        calendar: Calendar = .current
    ) -> [(day: Date, entries: [CaptureHistoryEntry])] {
        var groups: [(day: Date, entries: [CaptureHistoryEntry])] = []
        for entry in entries.sorted(by: { $0.date > $1.date }) {
            let day = calendar.startOfDay(for: entry.date)
            if let last = groups.indices.last, groups[last].day == day {
                groups[last].entries.append(entry)
            } else {
                groups.append((day, [entry]))
            }
        }
        return groups
    }

    // MARK: - 表示の文字

    /// 撮った時刻（例: 「14:32」）
    static func timeText(_ date: Date, calendar: Calendar = .current) -> String {
        formatter("H:mm", calendar: calendar).string(from: date)
    }

    /// 画像の大きさ（ポイント。例: 「1280×720」）
    static func sizeText(_ entry: CaptureHistoryEntry) -> String {
        "\(Int(entry.pointSize.width))×\(Int(entry.pointSize.height))"
    }

    /// ファイルの大きさ（例: 「1.2 MB」）
    static func byteText(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    /// 枚数と容量（例: 「12 枚・3.4 MB」。なければ「なし」）
    static func summaryText(count: Int, bytes: Int) -> String {
        count == 0 ? "なし" : "\(count) 枚・\(byteText(bytes))"
    }

    /// メニューなどに出す短い名前（例: 「今日 14:32・1280×720」）
    static func shortTitle(_ entry: CaptureHistoryEntry, now: Date = Date(), calendar: Calendar = .current) -> String {
        let day = dayTitle(calendar.startOfDay(for: entry.date), now: now, calendar: calendar)
        return "\(day) \(timeText(entry.date, calendar: calendar))・\(sizeText(entry))"
    }

    /// 日付の見出し（今日・昨日・それより前は日付）
    static func dayTitle(_ day: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        if calendar.isDate(day, inSameDayAs: now) { return "今日" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(day, inSameDayAs: yesterday) {
            return "昨日"
        }
        let format = calendar.isDate(day, equalTo: now, toGranularity: .year) ? "M月d日（E）" : "yyyy年M月d日（E）"
        return formatter(format, calendar: calendar).string(from: day)
    }

    /// 日時の書き方（一覧を描くたびに作り直さないよう、書き方と暦ごとに覚えておく）
    private static var formatters: [String: DateFormatter] = [:]

    private static func formatter(_ format: String, calendar: Calendar) -> DateFormatter {
        let key = "\(format)|\(calendar.identifier)|\(calendar.timeZone.identifier)"
        if let cached = formatters[key] { return cached }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = format
        formatters[key] = formatter
        return formatter
    }
}
