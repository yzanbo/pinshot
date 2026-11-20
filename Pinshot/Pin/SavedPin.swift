import Foundation

/// 浮かせた画像 1 枚ぶんの、終了・再起動のあとも残す状態（画像そのものは id の名前の PNG で別に置く）
struct SavedPin: Codable, Equatable {
    var id: UUID
    /// 元の画像の大きさ（ポイント）
    var imageSize: CGSize
    /// 画像（背景の余白を除く）の画面上の位置と大きさ（AppKit のスクリーン座標）
    var frame: CGRect
    var zoom: CGFloat
    var opacity: CGFloat
    /// 書き込みとトリミング
    var snapshot: EditSnapshot
    var backdrop: SavedBackdrop
    /// この画像だけ最前面の設定を変えているとき（nil なら設定に従う）
    var onTopOverride: Bool?
    /// どの履歴の画像か（履歴から同じ画像を浮かせたときに、増やさず前に出すため。前の版の状態にはない）
    var origin: PinOrigin? = nil

    var imageFileName: String { "\(id.uuidString).png" }
}

/// 浮かせた画像が、どの履歴の画像か
enum PinOrigin: Codable, Equatable {
    /// 撮った画像の履歴の 1 枚（撮った直後に浮かせた画像も、この印を持つ）
    case captureHistory(UUID)
    /// 読み取った文字の履歴の、読み取った範囲の画像
    case textHistory(UUID)
}

/// 浮かせた画像に付けている背景
struct SavedBackdrop: Codable, Equatable {
    var shown: Bool
    var decoration: ExportDecoration
    /// 設定の背景に合わせているか（合わせているときは、戻すときにいまの設定を使う）
    var followsSettings: Bool
}

/// 浮かせていた画像と、閉じた画像（「閉じた画像を戻す」で戻せるもの）
struct SavedPinSession: Codable, Equatable {
    /// いまの版が書く形の番号（書き込みの種類を足すなど、前の版で読めない形にしたら増やす）
    static let currentVersion = 1

    /// 書いた版の形の番号（いまより新しければ、新しい版が書いたもの）
    var version = SavedPinSession.currentVersion
    /// 浮かせていた画像（浮かせた順）
    var pins: [SavedPin] = []
    /// 閉じた画像（新しい順）
    var closed: [SavedPin] = []

    /// 使っている画像のファイル名（これ以外の PNG は、もう使わないので消してよい）
    var imageFileNames: Set<String> {
        Set((pins + closed).map(\.imageFileName))
    }

    /// 読んだ状態と、そのまま上書きすると中身を失うか
    struct Decoded: Equatable {
        var session: SavedPinSession
        /// 読めずに飛ばした画像の数（新しい版で足した書き込みの種類を含むものなど）
        var skipped: Int
        /// 新しい版が書いたもの（読めても、この版が知らない項目は、書き直すと消える）
        var isNewer: Bool

        /// このまま上書きすると、中身を失うか（そのときは元のファイルを残してから書く）
        var losesData: Bool { skipped > 0 || isNewer }
    }

    /// 保存した状態を読む。画像は 1 枚ずつ読み、読めないものだけ飛ばす（1 枚のせいで全部を失わない）。
    /// 全体として読めなければ nil
    static func decode(from data: Data) -> Decoded? {
        guard let raw = try? JSONDecoder().decode(LossySession.self, from: data) else { return nil }
        let rawPins = raw.pins ?? []
        let rawClosed = raw.closed ?? []
        let pins = rawPins.compactMap(\.value)
        let closed = rawClosed.compactMap(\.value)
        return Decoded(
            session: SavedPinSession(version: currentVersion, pins: pins, closed: closed),
            skipped: (rawPins.count - pins.count) + (rawClosed.count - closed.count),
            isNewer: (raw.version ?? currentVersion) > currentVersion
        )
    }

    /// 1 枚ずつ読むための形
    private struct LossySession: Decodable {
        var version: Int?
        var pins: [Lossy<SavedPin>]?
        var closed: [Lossy<SavedPin>]?
    }
}
