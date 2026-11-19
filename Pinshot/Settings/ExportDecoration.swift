import AppKit

/// 書き出しの背景の色
enum ExportBackground: String, CaseIterable, Identifiable, Codable {
    case white
    case lightGray
    case dark
    case ocean
    case lavender
    case sunset

    var id: String { rawValue }

    var label: String {
        switch self {
        case .white: "白"
        case .lightGray: "明るいグレー"
        case .dark: "黒"
        case .ocean: "海（青）"
        case .lavender: "ラベンダー"
        case .sunset: "夕焼け"
        }
    }

    /// 1 色なら単色、2 色なら左上から右下へのグラデーション
    var colors: [RGBAColor] {
        switch self {
        case .white: [RGBAColor(r: 1, g: 1, b: 1, a: 1)]
        case .lightGray: [RGBAColor(r: 0.93, g: 0.94, b: 0.95, a: 1)]
        case .dark: [RGBAColor(r: 0.11, g: 0.11, b: 0.13, a: 1)]
        case .ocean: [RGBAColor(r: 0.31, g: 0.67, b: 0.996, a: 1), RGBAColor(r: 0, g: 0.95, b: 0.996, a: 1)]
        case .lavender: [RGBAColor(r: 0.63, g: 0.55, b: 0.82, a: 1), RGBAColor(r: 0.98, g: 0.76, b: 0.92, a: 1)]
        case .sunset: [RGBAColor(r: 0.965, g: 0.827, b: 0.396, a: 1), RGBAColor(r: 0.992, g: 0.627, b: 0.522, a: 1)]
        }
    }
}

/// 書き出しの背景の余白
enum ExportPadding: Int, CaseIterable, Identifiable, Codable {
    case small
    case medium
    case large

    var id: Int { rawValue }
    var label: String {
        switch self {
        case .small: "小"
        case .medium: "中"
        case .large: "大"
        }
    }
    var points: CGFloat {
        switch self {
        case .small: 24
        case .medium: 48
        case .large: 80
        }
    }
}

/// 書き出しの背景の上の、画像の角の丸み
enum ExportCorner: Int, CaseIterable, Identifiable, Codable {
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
    var points: CGFloat {
        switch self {
        case .none: 0
        case .small: 8
        case .large: 16
        }
    }
}

/// 書き出しの背景（余白・背景色・角丸・影）
struct ExportDecoration: Codable, Equatable {
    var isEnabled = false
    var background: ExportBackground = .ocean
    var padding: ExportPadding = .medium
    var corner: ExportCorner = .small
    var shadow = true
}
