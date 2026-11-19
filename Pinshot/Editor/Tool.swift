import AppKit

/// 編集ツール
enum Tool: String, CaseIterable, Identifiable, Codable {
    case select
    case rectangle
    case ellipse
    case arrow
    case pen
    case highlight
    case text
    case counter
    case spotlight
    case mosaic
    case blur
    case crop

    var id: String { rawValue }

    var label: String {
        switch self {
        case .select: "選択"
        case .rectangle: "四角"
        case .ellipse: "楕円"
        case .arrow: "矢印"
        case .pen: "ペン"
        case .highlight: "蛍光ペン"
        case .text: "文字"
        case .counter: "番号"
        case .spotlight: "スポットライト"
        case .mosaic: "モザイク"
        case .blur: "ぼかし"
        case .crop: "トリミング"
        }
    }

    var symbolName: String {
        switch self {
        case .select: "cursorarrow"
        case .rectangle: "rectangle"
        case .ellipse: "circle"
        case .arrow: "arrow.up.right"
        case .pen: "pencil.tip"
        case .highlight: "highlighter"
        case .text: "textformat"
        case .counter: "1.circle"
        case .spotlight: "flashlight.on.fill"
        case .mosaic: "squareshape.split.3x3"
        case .blur: "drop.halffull"
        case .crop: "crop"
        }
    }

    /// 編集モード中に押すと切り替わるキー
    var shortcut: String {
        switch self {
        case .select: "v"
        case .rectangle: "r"
        case .ellipse: "o"
        case .arrow: "a"
        case .pen: "p"
        case .highlight: "h"
        case .text: "t"
        case .counter: "n"
        case .spotlight: "s"
        case .mosaic: "m"
        case .blur: "b"
        case .crop: "c"
        }
    }

    /// ツールバーで説明に出す、使い方
    var usage: String {
        switch self {
        case .select: "書き込みをクリックで選び、ドラッグで動かす。何もない所をドラッグすると画像を移動"
        case .rectangle: "ドラッグで四角を描く。shift で正方形"
        case .ellipse: "ドラッグで楕円を描く。shift で正円"
        case .arrow: "ドラッグで矢印を描く。shift で 45° ごとにそろう"
        case .pen: "ドラッグで自由に描く"
        case .highlight: "ドラッグでなぞってマーカーを引く。shift でまっすぐ"
        case .text: "クリックして文字を入力（shift + return で改行、return で確定）。書いた文字はクリックで直せる"
        case .counter: "クリックするたびに 1, 2, 3… と番号を置く。消すと後ろの番号が詰まる"
        case .spotlight: "ドラッグした範囲だけを明るく残し、まわりを暗くして目立たせる"
        case .mosaic: "ドラッグした範囲をモザイクで隠す"
        case .blur: "ドラッグした範囲をぼかして隠す"
        case .crop: "ドラッグした範囲だけを残す（⌘Z で元に戻せる）"
        }
    }
}

/// 線の太さの決まり（ツールごとに太さを覚える）
enum LineWidths {
    /// 四角・楕円・矢印・ペンの太さ
    static let line: [CGFloat] = [1, 2, 3, 4, 6, 8, 12, 16]
    /// 蛍光ペンの太さ
    static let highlight: [CGFloat] = [6, 10, 14, 18, 24, 32, 40]

    /// 太さを選べるツール
    static let tools: Set<Tool> = [.rectangle, .ellipse, .arrow, .pen, .highlight]

    static func presets(for tool: Tool) -> [CGFloat] {
        tool == .highlight ? highlight : line
    }

    static func defaultWidth(for tool: Tool) -> CGFloat {
        tool == .highlight ? 18 : 4
    }
}
