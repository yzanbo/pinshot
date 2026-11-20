import Foundation

// アップロードと共有リンクで使う型（画面やネットに関わらない。テストにも入れる）

/// 上げる保存先の種類（設定と、上げたものの履歴に残す）
enum UploadDestinationID: String, Codable, CaseIterable, Identifiable {
    case gyazo

    var id: String { rawValue }

    var label: String {
        switch self {
        case .gyazo: "Gyazo"
        }
    }
}

/// 保存先ごとにできること（できないことは、ボタンを押せなくしたり、別の形に落としたりする）
struct UploadCapabilities: Equatable {
    /// 動画（MP4）を上げられるか
    var uploadsMovies: Bool
    /// 上げたものを Pinshot から消せるか
    var canDelete: Bool
    /// 1 つのファイルの大きさの上限（バイト。分からなければ nil）
    var maxFileBytes: Int64?

    /// kind のファイル（bytes バイト）を上げられるか
    func accepts(_ kind: ExportKind, bytes: Int64) -> Bool {
        if kind == .movie, !uploadsMovies { return false }
        if let maxFileBytes, bytes > maxFileBytes { return false }
        return true
    }
}

/// 上げている途中の進み具合（送った割合 0〜1。裏の列から呼ぶ）
typealias UploadProgress = @Sendable (Double) -> Void

/// 上げるもの 1 つ（中身はメモリのまま渡す。録画などの大きいものを上げるときは、ファイルのまま送る形を足す）
struct UploadItem {
    var data: Data
    /// 保存先に付けるファイル名（拡張子付き）
    var fileName: String
    var kind: ExportKind

    /// 中身の大きさ（バイト）
    var byteCount: Int64 { Int64(data.count) }
}

/// 保存先に上げたファイル（あとで共有リンクを作る・消すときに使う）
struct RemoteFile: Codable, Equatable {
    var destination: UploadDestinationID
    /// 保存先での ID（Gyazo は image_id）
    var id: String
    /// 保存先ごとの追加の情報（Gyazo が返した URL など）
    var info: [String: String] = [:]
}

/// 共有リンク
struct SharedLink: Codable, Equatable {
    /// 開くとページ（プレビュー）が出る URL
    var pageURL: URL
    /// 画像そのものの URL（貼るとその場で画像が出る。出せない保存先では nil）
    var directURL: URL?
}

/// クリップボードに入れる形
enum ShareLinkFormat: String, CaseIterable, Identifiable {
    /// ページの URL
    case page
    /// 画像そのものの URL
    case direct
    /// Markdown の画像（![](画像の URL)）
    case markdown

    var id: String { rawValue }

    var label: String {
        switch self {
        case .page: "ページの URL"
        case .direct: "画像の URL"
        case .markdown: "Markdown（![](URL)）"
        }
    }
}

/// アップロードで起きる失敗（知らせる文は、利用者向けの日本語にする）
enum UploadError: LocalizedError, Equatable {
    /// ログインしていない・許可が切れた
    case notSignedIn(UploadDestinationID)
    /// この保存先では、この種類を上げられない（Gyazo の動画など）
    case unsupportedKind(UploadDestinationID, ExportKind)
    /// 大きすぎる
    case tooLarge(UploadDestinationID)
    /// 回数の上限に達した
    case rateLimited(UploadDestinationID)
    /// 保存先が断った（HTTP の番号と、保存先が返した文）
    case server(UploadDestinationID, status: Int, message: String?)
    /// 保存先の返事が読めなかった
    case invalidResponse(UploadDestinationID)
    /// ログインの戻り先の番号が、どれもほかのアプリに使われていた
    case loopbackUnavailable
    /// 利用者がやめた
    case cancelled

    var errorDescription: String? {
        switch self {
        case .notSignedIn(let destination):
            "\(destination.label) にログインしていません（許可が切れた可能性があります）。設定の「共有」からログインし直してください。"
        case .unsupportedKind(let destination, let kind):
            "\(destination.label) には\(kind.label)を上げられません。"
        case .tooLarge(let destination):
            "ファイルが大きすぎて、\(destination.label) に上げられません。"
        case .rateLimited(let destination):
            "\(destination.label) の回数の上限に達しました。しばらくしてから試してください。"
        case .server(let destination, let status, let message):
            "\(destination.label) に上げられませんでした（\(status)）。" + (message.map { "\n\($0)" } ?? "")
        case .invalidResponse(let destination):
            "\(destination.label) の返事を読めませんでした。"
        case .loopbackUnavailable:
            "ログインの受け口に使う番号が、ほかのアプリに使われていました。"
        case .cancelled:
            "やめました。"
        }
    }
}
