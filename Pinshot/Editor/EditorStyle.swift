import AppKit

/// 書き込みに反映する見た目の項目（変えた項目だけを反映するため）
struct StyleAspects: OptionSet {
    let rawValue: Int
    static let color = StyleAspects(rawValue: 1 << 0)
    static let opacity = StyleAspects(rawValue: 1 << 1)
    static let lineWidth = StyleAspects(rawValue: 1 << 2)
    static let rectangle = StyleAspects(rawValue: 1 << 3)
    static let ellipse = StyleAspects(rawValue: 1 << 4)
    static let arrow = StyleAspects(rawValue: 1 << 5)
    static let counter = StyleAspects(rawValue: 1 << 6)
    static let text = StyleAspects(rawValue: 1 << 7)
    static let textMark = StyleAspects(rawValue: 1 << 8)
    static let all: StyleAspects = [.color, .opacity, .lineWidth, .rectangle, .ellipse, .arrow, .counter, .text, .textMark]
}

/// ツールバーで選んでいる見た目の設定一式
struct EditorStyle: Equatable {
    var color: RGBAColor
    /// ツールごとの線の太さ
    var lineWidths: [Tool: CGFloat]
    var rectangle: ShapeStyle
    var ellipse: ShapeStyle
    var arrow: ArrowStyle
    var counterSize: CounterSize
    var counter: CounterStyle
    var text: TextStyle
    var textMark: TextMarkStyle
    /// 書き込みの不透明度（0.1〜1）
    var opacity: CGFloat

    func lineWidth(for tool: Tool) -> CGFloat {
        lineWidths[tool] ?? LineWidths.defaultWidth(for: tool)
    }
}
