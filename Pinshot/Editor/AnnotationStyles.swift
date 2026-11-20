import AppKit

// MARK: - 四角・楕円のスタイル

/// 四角の角の丸み
enum CornerStyle: Int, CaseIterable, Identifiable, Codable {
    case none
    case small
    case large

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .none: "なし"
        case .small: "小"
        case .large: "大"
        }
    }

    func radius(for rect: CGRect) -> CGFloat {
        let limit = min(rect.width, rect.height) / 2
        switch self {
        case .none: return 0
        case .small: return min(6, limit)
        case .large: return min(18, limit)
        }
    }
}

/// 四角・楕円の塗り
enum FillStyle: String, CaseIterable, Identifiable, Codable {
    case none
    case translucent
    case solid

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: "なし"
        case .translucent: "半透明"
        case .solid: "塗りつぶし"
        }
    }
}

struct ShapeStyle: Codable, Equatable {
    var corner: CornerStyle = .none
    var fill: FillStyle = .none
}

/// 文字の大きさの決まり
enum FontSizes {
    static let presets: [CGFloat] = [12, 14, 16, 20, 24, 32, 40, 48, 64, 80, 96]
    static let range: ClosedRange<CGFloat> = 8...200
    static let `default`: CGFloat = 20

    /// 表示用（整数ならそのまま、小数があれば 1 桁）
    static func format(_ size: CGFloat) -> String {
        size.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(size))" : String(format: "%.1f", size)
    }

    /// いまの大きさから、次に大きい（小さい）大きさ
    static func step(_ size: CGFloat, up: Bool) -> CGFloat {
        if up {
            return presets.first { $0 > size + 0.5 } ?? min(size + 16, range.upperBound)
        } else {
            return presets.last { $0 < size - 0.5 } ?? max(size - 2, range.lowerBound)
        }
    }
}

// MARK: - 矢印のスタイル

/// 矢じりの大きさ
enum ArrowHead: Int, CaseIterable, Identifiable, Codable {
    case small
    case medium
    case large
    case xlarge

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .small: "小"
        case .medium: "中"
        case .large: "大"
        case .xlarge: "特大"
        }
    }

    /// 矢じりの長さ（線の太さに対する倍率と、最小の長さ）
    func length(lineWidth: CGFloat) -> CGFloat {
        switch self {
        case .small: max(8, lineWidth * 3)
        case .medium: max(12, lineWidth * 4)
        case .large: max(18, lineWidth * 5.5)
        case .xlarge: max(26, lineWidth * 7.5)
        }
    }
}

/// 矢じりの形
enum ArrowHeadShape: String, CaseIterable, Identifiable, Codable {
    case filled
    case open

    var id: String { rawValue }

    var label: String {
        switch self {
        case .filled: "三角"
        case .open: "山形"
        }
    }

    var symbolName: String {
        switch self {
        case .filled: "arrowtriangle.right.fill"
        case .open: "chevron.right"
        }
    }
}

/// 矢印の見た目。始点・終点のそれぞれに、矢じりを付けるかどうかを選ぶ（どちらも付けなければ線）
struct ArrowStyle: Codable, Equatable {
    var head: ArrowHead = .medium
    var shape: ArrowHeadShape = .filled
    var startHead = false
    var endHead = true

    var hasHeads: Bool { startHead || endHead }

    init() {}

    private enum CodingKeys: String, CodingKey {
        case head, shape, startHead, endHead
        /// 前の版の「形」（三角・山形・両端・なし）
        case kind
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        head = try container.decodeIfPresent(ArrowHead.self, forKey: .head) ?? .medium
        if let shape = try container.decodeIfPresent(ArrowHeadShape.self, forKey: .shape) {
            self.shape = shape
            startHead = try container.decodeIfPresent(Bool.self, forKey: .startHead) ?? false
            endHead = try container.decodeIfPresent(Bool.self, forKey: .endHead) ?? true
        } else {
            // 前の版の設定を読み替える
            switch try container.decodeIfPresent(String.self, forKey: .kind) {
            case "open": shape = .open; startHead = false; endHead = true
            case "double": shape = .filled; startHead = true; endHead = true
            case "none": shape = .filled; startHead = false; endHead = false
            default: shape = .filled; startHead = false; endHead = true
            }
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(head, forKey: .head)
        try container.encode(shape, forKey: .shape)
        try container.encode(startHead, forKey: .startHead)
        try container.encode(endHead, forKey: .endHead)
    }
}

// MARK: - 番号のスタイル

/// 番号の大きさ
enum CounterSize: Int, CaseIterable, Identifiable, Codable {
    case small
    case medium
    case large
    case xlarge

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .small: "小"
        case .medium: "中"
        case .large: "大"
        case .xlarge: "特大"
        }
    }

    var radius: CGFloat {
        switch self {
        case .small: 10
        case .medium: 14
        case .large: 19
        case .xlarge: 26
        }
    }

    static func closest(toRadius radius: CGFloat) -> CounterSize {
        allCases.min { abs($0.radius - radius) < abs($1.radius - radius) } ?? .medium
    }
}

/// 番号のデザイン
enum CounterDesign: String, CaseIterable, Identifiable, Codable {
    case filledCircle
    case outlineCircle
    case filledSquare
    case plain

    var id: String { rawValue }

    var label: String {
        switch self {
        case .filledCircle: "丸"
        case .outlineCircle: "白抜き"
        case .filledSquare: "四角"
        case .plain: "数字だけ"
        }
    }

    var symbolName: String {
        switch self {
        case .filledCircle: "1.circle.fill"
        case .outlineCircle: "1.circle"
        case .filledSquare: "1.square.fill"
        case .plain: "textformat.123"
        }
    }
}

/// 番号の表記
enum CounterFormat: String, CaseIterable, Identifiable, Codable {
    case number
    case letter

    var id: String { rawValue }

    var label: String {
        switch self {
        case .number: "1 2 3"
        case .letter: "A B C"
        }
    }

    /// 番号を表記に直す（A…Z の次は AA, AB…）
    func text(for number: Int) -> String {
        switch self {
        case .number:
            return "\(number)"
        case .letter:
            var n = max(number, 1)
            var result = ""
            while n > 0 {
                let remainder = (n - 1) % 26
                result = String(UnicodeScalar(UInt8(65 + remainder))) + result
                n = (n - 1) / 26
            }
            return result
        }
    }
}

struct CounterStyle: Codable, Equatable {
    var design: CounterDesign = .filledCircle
    var format: CounterFormat = .number
    /// 数字のフォント（フォントのファミリー名）。nil なら標準（システムのフォント）
    var fontFamily: String?
}

// MARK: - 文字のスタイル

/// 文字の枠線
enum TextDecoration: String, CaseIterable, Identifiable, Codable {
    case none
    case whiteOutline
    case blackOutline
    case label

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: "なし"
        case .whiteOutline: "白い縁"
        case .blackOutline: "黒い縁"
        case .label: "ラベル"
        }
    }
}

/// 文字の枠線の太さ
enum OutlineWeight: Int, CaseIterable, Identifiable, Codable {
    case thin
    case medium
    case thick

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .thin: "小"
        case .medium: "中"
        case .thick: "大"
        }
    }

    /// NSAttributedString の strokeWidth（文字の大きさに対する %。線は文字の輪郭の両側に描かれる）
    var strokePercent: CGFloat {
        switch self {
        case .thin: 12
        case .medium: 22
        case .thick: 36
        }
    }

    /// 枠線が文字の外にはみ出す量（文字の大きさに対する割合）
    var overflow: CGFloat { strokePercent / 200 }
}

struct TextStyle: Codable, Equatable {
    var decoration: TextDecoration = .none
    var outline: OutlineWeight = .medium
    /// フォント（フォントのファミリー名）。nil なら標準（システムのフォント）
    var fontFamily: String?
}

/// 文字の一部分（1 つの文字の中で、部分ごとに大きさを変えられる）
struct TextRun: Codable, Equatable {
    var text: String
    var fontSize: CGFloat
}

// MARK: - 文字マーカー

/// 文字マーカーの種類（文字の位置に合わせて引く）
enum TextMarkKind: String, CaseIterable, Identifiable, Codable {
    /// 文字の高さに合わせた蛍光ペン
    case highlight
    /// 文字の下に線
    case underline
    /// 文字の真ん中に線
    case strikethrough
    /// 文字を四角で囲む
    case box

    var id: String { rawValue }

    var label: String {
        switch self {
        case .highlight: "蛍光ペン"
        case .underline: "下線"
        case .strikethrough: "取り消し線"
        case .box: "囲み"
        }
    }

    var symbolName: String {
        switch self {
        case .highlight: "highlighter"
        case .underline: "underline"
        case .strikethrough: "strikethrough"
        case .box: "rectangle"
        }
    }

    /// 線の太さを使うか（蛍光ペンは文字の高さで塗るので使わない）
    var usesLineWidth: Bool { self != .highlight }
}

/// 蛍光ペン・囲みの、文字からの余白（中が標準）
enum TextMarkPadding: String, CaseIterable, Identifiable, Codable {
    case none
    case small
    case medium
    case large

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: "なし"
        case .small: "小"
        case .medium: "中"
        case .large: "大"
        }
    }

    /// 標準（中）の余白に掛ける倍率
    var scale: CGFloat {
        switch self {
        case .none: 0
        case .small: 0.5
        case .medium: 1
        case .large: 2
        }
    }
}

/// 下線・取り消し線の位置（標準から、1 段ずつ文字の高さの 6% 上げ下げする）
enum TextMarkLinePosition: Int, CaseIterable, Identifiable, Codable {
    case higher = -2
    case high = -1
    case standard = 0
    case low = 1
    case lower = 2

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .higher: "高め"
        case .high: "やや高め"
        case .standard: "標準"
        case .low: "やや低め"
        case .lower: "低め"
        }
    }

    /// 標準からずらす量（文字の高さ height に対して。下が正）
    func offset(height: CGFloat) -> CGFloat {
        CGFloat(rawValue) * height * 0.06
    }
}

struct TextMarkStyle: Codable, Equatable {
    var kind: TextMarkKind = .highlight
    /// 蛍光ペン・囲みの、文字からの余白
    var padding: TextMarkPadding = .medium
    /// 下線・取り消し線の位置（画像の中のすべての文字マーカーで、そろえて使う）
    var linePosition: TextMarkLinePosition = .standard

    init(kind: TextMarkKind = .highlight, padding: TextMarkPadding = .medium, linePosition: TextMarkLinePosition = .standard) {
        self.kind = kind
        self.padding = padding
        self.linePosition = linePosition
    }

    // 余白と線の位置を足す前に残したもの（浮かせていた画像・ツールバーの設定）も読めるよう、ないときは標準にする
    private enum CodingKeys: String, CodingKey {
        case kind, padding, linePosition
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decodeIfPresent(TextMarkKind.self, forKey: .kind) ?? .highlight
        padding = try container.decodeIfPresent(TextMarkPadding.self, forKey: .padding) ?? .medium
        linePosition = try container.decodeIfPresent(TextMarkLinePosition.self, forKey: .linePosition) ?? .standard
    }
}
