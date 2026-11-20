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

    var imageFileName: String { "\(id.uuidString).png" }
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
    var version = 1
    /// 浮かせていた画像（浮かせた順）
    var pins: [SavedPin] = []
    /// 閉じた画像（新しい順）
    var closed: [SavedPin] = []

    /// 使っている画像のファイル名（これ以外の PNG は、もう使わないので消してよい）
    var imageFileNames: Set<String> {
        Set((pins + closed).map(\.imageFileName))
    }
}
