import Foundation

/// ツールバーで、1 つのボタンにまとめるツールの組
enum ToolGroup: String, CaseIterable, Identifiable {
    case select
    case shape
    case arrow
    case draw
    /// 文字マーカー（自由に描くペンとは使い方が違うので、組に入れず 1 つのボタンにする）
    case textMark
    case text
    case counter
    case hide
    case crop

    var id: String { rawValue }

    var tools: [Tool] {
        switch self {
        case .select: [.select]
        case .shape: [.rectangle, .ellipse]
        case .arrow: [.arrow]
        case .draw: [.pen, .highlight]
        case .textMark: [.textMark]
        case .text: [.text]
        case .counter: [.counter]
        case .hide: [.spotlight, .mosaic, .blur]
        case .crop: [.crop]
        }
    }

    var label: String {
        switch self {
        case .select: "選択"
        case .shape: "図形"
        case .arrow: "矢印"
        case .draw: "描く"
        case .textMark: "文字マーカー"
        case .text: "文字"
        case .counter: "番号"
        case .hide: "隠す・目立たせる"
        case .crop: "トリミング"
        }
    }

    /// tool が入る組（ツールを足したら、ここに書かないとコンパイルエラーになる。tools にも並べる。テストで確かめる）
    static func group(of tool: Tool) -> ToolGroup {
        switch tool {
        case .select: .select
        case .rectangle, .ellipse: .shape
        case .arrow: .arrow
        case .pen, .highlight: .draw
        case .textMark: .textMark
        case .text: .text
        case .counter: .counter
        case .spotlight, .mosaic, .blur: .hide
        case .crop: .crop
        }
    }
}
