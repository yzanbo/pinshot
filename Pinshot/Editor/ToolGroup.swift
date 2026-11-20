import Foundation

/// ツールバーで、1 つのボタンにまとめるツールの組
enum ToolGroup: String, CaseIterable, Identifiable {
    case select
    case shape
    case arrow
    case draw
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
        case .draw: [.pen, .highlight, .textMark]
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
        case .text: "文字"
        case .counter: "番号"
        case .hide: "隠す・目立たせる"
        case .crop: "トリミング"
        }
    }

    static func group(of tool: Tool) -> ToolGroup {
        allCases.first { $0.tools.contains(tool) } ?? .select
    }
}
