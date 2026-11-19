import AppKit

/// 書き込みの色。Windows 版と保存形式をそろえやすいよう、RGBA の数値で持つ
struct RGBAColor: Codable, Hashable {
    var r: CGFloat
    var g: CGFloat
    var b: CGFloat
    var a: CGFloat

    var nsColor: NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: a) }
    var cgColor: CGColor { nsColor.cgColor }

    /// 明るい色かどうか（上に載せる文字を黒にするか白にするかの判断に使う）
    var isLight: Bool { 0.299 * r + 0.587 * g + 0.114 * b > 0.65 }

    static let red = RGBAColor(r: 1.0, g: 0.231, b: 0.188, a: 1)
    static let yellow = RGBAColor(r: 1.0, g: 0.8, b: 0.0, a: 1)
    static let green = RGBAColor(r: 0.204, g: 0.78, b: 0.349, a: 1)
    static let blue = RGBAColor(r: 0.0, g: 0.478, b: 1.0, a: 1)
    static let black = RGBAColor(r: 0, g: 0, b: 0, a: 1)
    static let white = RGBAColor(r: 1, g: 1, b: 1, a: 1)

    static let palette: [RGBAColor] = [.red, .yellow, .green, .blue, .black, .white]

    init(r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    /// 透過度だけを変えた色
    func withAlpha(_ alpha: CGFloat) -> RGBAColor {
        RGBAColor(r: r, g: g, b: b, a: alpha)
    }

    /// カラーパネルで選んだ色から作る（sRGB にそろえる）
    init?(nsColor: NSColor) {
        guard let srgb = nsColor.usingColorSpace(.sRGB) else { return nil }
        // 小さな誤差で別の色にならないよう、1/1000 で丸める
        func round(_ v: CGFloat) -> CGFloat { (v * 1000).rounded() / 1000 }
        self.init(r: round(srgb.redComponent), g: round(srgb.greenComponent), b: round(srgb.blueComponent), a: 1)
    }

    var name: String {
        switch self {
        case .red: "赤"
        case .yellow: "黄"
        case .green: "緑"
        case .blue: "青"
        case .black: "黒"
        case .white: "白"
        default: String(format: "オリジナル #%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
        }
    }
}
