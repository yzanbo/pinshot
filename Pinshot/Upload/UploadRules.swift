import Foundation

/// アップロードの決まり（画面やネットに関わらない部分。テストで確かめる）
enum UploadRules {
    // MARK: - クリップボードに入れる文

    /// format の形で、クリップボードに入れる文を作る。
    /// 画像そのものの URL がない保存先では、ページの URL に落とす（Markdown も、ページの URL で作る）
    static func clipboardText(for link: SharedLink, format: ShareLinkFormat) -> String {
        let direct = link.directURL ?? link.pageURL
        switch format {
        case .page: return link.pageURL.absoluteString
        case .direct: return direct.absoluteString
        case .markdown: return "![](\(direct.absoluteString))"
        }
    }

    // MARK: - 許可証

    /// アクセストークンらしい文字列か（クリップボードから貼るよう勧めるかを決める）。
    /// 1 行で、20〜200 文字の英数字と「- _ . ~」だけ
    static func looksLikeAccessToken(_ text: String) -> Bool {
        let token = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (20...200).contains(token.count) else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.~")
        return token.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    // MARK: - GIF を上げるときの大きさ

    /// 録画を GIF にして上げるときの、Pinshot で決める大きさの上限（バイト）。
    /// 上げる先の上限は資料に数字が書かれていないので、貼った先で重くなりすぎない大きさを Pinshot で決める。
    /// これを超えたら、小さい作り方（RecordingRules.gifUploadSteps）で作り直す
    static let gifMaxBytes = 10_000_000

    /// 作った GIF（bytes バイト）を、このまま上げてよいか
    static func fitsGIFUpload(bytes: Int) -> Bool {
        bytes <= gifMaxBytes
    }

    // MARK: - ファイル名

    /// 保存先に付けるファイル名（例: 「Pinshot-2026-11-20-154012.png」）。
    /// 共有リンクの URL に入るので、空白を使わない。日時は、並べたときに古い順になる書き方にする
    static func fileName(kind: ExportKind, date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return "Pinshot-\(formatter.string(from: date)).\(kind.fileExtension)"
    }

}

/// multipart/form-data の本文を組み立てる（Gyazo へ画像を上げるときに使う）
struct MultipartForm {
    let boundary: String
    private var body = Data()

    init(boundary: String = "Pinshot-\(UUID().uuidString)") {
        self.boundary = boundary
    }

    /// Content-Type の値
    var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    /// 文字の項目を足す
    mutating func addField(name: String, value: String) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        append("\(value)\r\n")
    }

    /// ファイルの項目を足す
    mutating func addFile(name: String, fileName: String, mimeType: String, data: Data) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(fileName)\"\r\n")
        append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(data)
        append("\r\n")
    }

    /// 終わりの印を付けた本文
    func finalized() -> Data {
        var data = body
        data.append(Data("--\(boundary)--\r\n".utf8))
        return data
    }

    private mutating func append(_ text: String) {
        body.append(Data(text.utf8))
    }
}

extension ExportKind {
    /// 上げるときの種類（MIME）
    var mimeType: String {
        switch self {
        case .image: "image/png"
        case .gif: "image/gif"
        case .movie: "video/mp4"
        }
    }
}
