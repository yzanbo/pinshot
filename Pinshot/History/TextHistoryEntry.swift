import Foundation

/// 読み取った文字の履歴の 1 件
struct RecognizedTextEntry: Codable, HistoryItem, Equatable {
    var id: UUID
    /// 読み取った日時
    var date: Date
    /// 読み取った文字（行ごとに改行でつなぐ。一覧で直せる）
    var text: String
    /// 読み取った範囲の画像のファイル名（履歴のフォルダの中。前の版の履歴にはない）
    var imageFileName: String? = nil
    /// 読み取った範囲の大きさ（ポイント。画像を浮かせるときの大きさ）
    var pointSize: CGSize? = nil

    /// 読み取った範囲の画像を置くときのファイル名
    static func imageFileName(for id: UUID) -> String { "\(id.uuidString).text.png" }
}

/// 読み取った文字の履歴の一覧の表示方法
enum TextHistoryLayout: String, HistoryLayoutOption {
    /// 大きめの読み取った画像と、文字の最初の 5 行
    case detailed
    /// 小さな画像・時刻・文字数と、文字の最初の 2 行
    case standard
    /// 画像なしで 1 行（時刻と最初の行）。たくさんの中から探すとき
    case compact

    var id: String { rawValue }

    var label: String {
        switch self {
        case .detailed: "詳しく"
        case .standard: "標準"
        case .compact: "コンパクト"
        }
    }

    var symbolName: String {
        switch self {
        case .detailed: "text.below.photo"
        case .standard: "list.bullet.below.rectangle"
        case .compact: "list.dash"
        }
    }
}

/// 読み取った文字の履歴の決まり（画面やファイルに関係ない部分。テストで確かめる）
enum TextHistoryRules {
    /// 履歴に足したあとの一覧（新しい順）。同じ文字がすでにあれば、古いほうを消して先頭に置く
    static func adding(_ entry: RecognizedTextEntry, to entries: [RecognizedTextEntry]) -> [RecognizedTextEntry] {
        [entry] + entries.filter { $0.text != entry.text }
    }

    /// 文字を探す（大文字と小文字・ひらがなとカタカナの違いは見ない）。query が空なら全部
    static func filtered(_ entries: [RecognizedTextEntry], query: String) -> [RecognizedTextEntry] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return entries }
        return entries.filter {
            $0.text.range(of: query, options: [.caseInsensitive, .widthInsensitive, .diacriticInsensitive]) != nil
                || $0.text.applyingTransform(.hiraganaToKatakana, reverse: false)?
                    .range(of: query.applyingTransform(.hiraganaToKatakana, reverse: false) ?? query, options: .caseInsensitive) != nil
        }
    }

    /// メニューなどに出す 1 行の見出し（空の行を飛ばした最初の行。長ければ「…」で切る）
    static func preview(_ text: String, maxLength: Int = 40) -> String {
        let firstLine = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        guard firstLine.count > maxLength else { return firstLine }
        return String(firstLine.prefix(maxLength)) + "…"
    }

    /// 文字数と行数（例: 「120 文字・4 行」。1 行なら文字数だけ）
    static func countText(_ text: String) -> String {
        let lines = text.split(whereSeparator: \.isNewline).count
        return lines > 1 ? "\(text.count) 文字・\(lines) 行" : "\(text.count) 文字"
    }

    /// 件数（例: 「12 件」。なければ「なし」）
    static func summaryText(count: Int) -> String {
        count == 0 ? "なし" : "\(count) 件"
    }

    /// 選んだものをまとめてコピーするときの文字（新しい順のまま、空の行をはさんでつなぐ）
    static func joined(_ entries: [RecognizedTextEntry]) -> String {
        entries.map(\.text).joined(separator: "\n\n")
    }
}
