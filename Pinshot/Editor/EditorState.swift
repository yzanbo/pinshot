import AppKit

/// 編集の状態（ツールバーと画像の両方から見る）。
/// ツール・色・太さ・各ツールのオプション・ツールバーの表示は、次に浮かせる画像にも引き継ぐ
@MainActor
final class EditorState: ObservableObject {
    private enum Key {
        static let tool = "editor.tool"
        static let color = "editor.color"
        static let lineWidths = "editor.lineWidths"
        static let rectangleStyle = "editor.rectangleStyle"
        static let ellipseStyle = "editor.ellipseStyle"
        static let fontSize = "editor.fontSize"
        static let arrowStyle = "editor.arrowStyle"
        static let counterSize = "editor.counterSize"
        static let counterStyle = "editor.counterStyle"
        static let textStyle = "editor.textStyle"
        static let textMarkStyle = "editor.textMarkStyle"
        static let customColors = "editor.customColors"
        static let opacity = "editor.opacity"
        static let isDetached = "toolbar.isDetached"
        static let showsHints = "toolbar.showsHints"
    }

    private let defaults = UserDefaults.standard

    @Published var isEditing = false
    @Published var tool: Tool {
        didSet {
            defaults.set(tool.rawValue, forKey: Key.tool)
            lastToolInGroup[ToolGroup.group(of: tool)] = tool
        }
    }
    @Published var color: RGBAColor {
        didSet { save(color, forKey: Key.color) }
    }
    /// ツールごとの線の太さ（キーはツールの rawValue）
    @Published var lineWidths: [String: Double] {
        didSet { save(lineWidths, forKey: Key.lineWidths) }
    }
    @Published var rectangleStyle: ShapeStyle {
        didSet { save(rectangleStyle, forKey: Key.rectangleStyle) }
    }
    @Published var ellipseStyle: ShapeStyle {
        didSet { save(ellipseStyle, forKey: Key.ellipseStyle) }
    }
    @Published var fontSize: CGFloat {
        didSet { defaults.set(Double(fontSize), forKey: Key.fontSize) }
    }
    @Published var arrowStyle: ArrowStyle {
        didSet { save(arrowStyle, forKey: Key.arrowStyle) }
    }
    @Published var counterSize: CounterSize {
        didSet { defaults.set(counterSize.rawValue, forKey: Key.counterSize) }
    }
    @Published var counterStyle: CounterStyle {
        didSet { save(counterStyle, forKey: Key.counterStyle) }
    }
    @Published var textStyle: TextStyle {
        didSet { save(textStyle, forKey: Key.textStyle) }
    }
    @Published var textMarkStyle: TextMarkStyle {
        didSet { save(textMarkStyle, forKey: Key.textMarkStyle) }
    }
    /// 書き込みの不透明度（0.1〜1）
    @Published var opacity: Double {
        didSet { defaults.set(opacity, forKey: Key.opacity) }
    }
    /// 自分で選んだオリジナルの色（新しい順に 3 色まで）
    @Published var customColors: [RGBAColor] {
        didSet { save(customColors, forKey: Key.customColors) }
    }

    // ツールバーの表示
    /// 画像から切り離して、好きな場所に置く
    @Published var isDetached: Bool {
        didSet { defaults.set(isDetached, forKey: Key.isDetached) }
    }
    /// ボタンにマウスを乗せたら、説明のポップアップを出す
    @Published var showsHints: Bool {
        didSet { defaults.set(showsHints, forKey: Key.showsHints) }
    }

    @Published var canUndo = false
    @Published var canRedo = false
    /// 選んでいる書き込みの種類（1 つだけ選んでいるとき。複数で種類がそろっていればその種類）
    @Published var selectionTool: Tool?
    /// 文字を入力しているところか
    @Published var isEditingText = false
    /// 次に置く番号（ツールバーに出す）
    @Published var nextCounterNumber = 1
    /// ツールバーのボタンにマウスを乗せているときの説明
    @Published var hoverHint: String?
    /// ツールバーの 2 行目（吹き出し）の先を向ける、1 行目のボタンの中心（横の位置）
    @Published var optionsAnchorX: CGFloat?
    /// ツールバーの 1 行目の幅（2 行目はこの幅で折り返す）
    @Published var toolbarRowWidth: CGFloat = EditorState.lastToolbarRowWidth {
        didSet { if toolbarRowWidth > 0 { EditorState.lastToolbarRowWidth = toolbarRowWidth } }
    }
    /// 前に測った 1 行目の幅（新しい画像のツールバーを、最初から正しい幅で並べるため）
    private static var lastToolbarRowWidth: CGFloat = 0

    /// この画像に背景を付けるか・背景の見た目（画像ごと。初期値は設定の「保存」タブの背景）
    @Published var backdropShown: Bool
    /// ツールバーの 2 行目に、背景のオプション（付ける・外す・色・余白・角の丸み・影）を出しているか
    @Published var showsBackdropOptions = false
    @Published var backdropDecoration: ExportDecoration
    /// まだこの画像の背景を触っていなければ、設定の変更に追従する
    private(set) var backdropFollowsSettings = true
    /// 組のボタン（図形・描く・隠す など）に出すツール（その組で最後に使ったもの）
    @Published var lastToolInGroup: [ToolGroup: Tool] = [:]

    init() {
        tool = defaults.string(forKey: Key.tool).flatMap(Tool.init(rawValue:)) ?? .rectangle
        color = Self.load(RGBAColor.self, forKey: Key.color) ?? .red
        lineWidths = Self.load([String: Double].self, forKey: Key.lineWidths) ?? [:]
        rectangleStyle = Self.load(ShapeStyle.self, forKey: Key.rectangleStyle) ?? ShapeStyle()
        ellipseStyle = Self.load(ShapeStyle.self, forKey: Key.ellipseStyle) ?? ShapeStyle()
        fontSize = (defaults.object(forKey: Key.fontSize) as? Double).map { CGFloat($0) } ?? FontSizes.default
        arrowStyle = Self.load(ArrowStyle.self, forKey: Key.arrowStyle) ?? ArrowStyle()
        counterSize = (defaults.object(forKey: Key.counterSize) as? Int).flatMap(CounterSize.init(rawValue:)) ?? .medium
        counterStyle = Self.load(CounterStyle.self, forKey: Key.counterStyle) ?? CounterStyle()
        textStyle = Self.load(TextStyle.self, forKey: Key.textStyle) ?? TextStyle()
        textMarkStyle = Self.load(TextMarkStyle.self, forKey: Key.textMarkStyle) ?? TextMarkStyle()
        opacity = defaults.object(forKey: Key.opacity) as? Double ?? 1
        customColors = Self.load([RGBAColor].self, forKey: Key.customColors) ?? []
        isDetached = defaults.bool(forKey: Key.isDetached)
        showsHints = defaults.object(forKey: Key.showsHints) as? Bool ?? true
        let decoration = AppSettings.shared.exportDecoration
        backdropShown = decoration.isEnabled
        backdropDecoration = decoration
        lastToolInGroup[ToolGroup.group(of: tool)] = tool
    }

    // MARK: - 背景（画像ごと）

    /// この画像の背景の状態（閉じた画像を戻すとき・終了後に戻すときに引き継ぐ）
    var savedBackdrop: SavedBackdrop {
        SavedBackdrop(shown: backdropShown, decoration: backdropDecoration, followsSettings: backdropFollowsSettings)
    }

    /// 閉じる前の背景の状態に戻す（設定に追従していた画像は、いまの設定のまま）
    func restoreBackdrop(_ saved: SavedBackdrop) {
        backdropFollowsSettings = saved.followsSettings
        guard !saved.followsSettings else { return }
        backdropShown = saved.shown
        backdropDecoration = saved.decoration
    }

    func setBackdropShown(_ shown: Bool) {
        backdropFollowsSettings = false
        backdropShown = shown
    }

    /// 背景の見た目を変える（変えたら背景も付ける）
    func updateBackdrop(_ change: (inout ExportDecoration) -> Void) {
        backdropFollowsSettings = false
        var decoration = backdropDecoration
        change(&decoration)
        backdropDecoration = decoration
        if !backdropShown { backdropShown = true }
    }

    /// 設定の背景が変わったとき（この画像の背景をまだ触っていなければ合わせる）
    func followBackdropSettings(_ decoration: ExportDecoration) {
        guard backdropFollowsSettings else { return }
        if backdropDecoration != decoration { backdropDecoration = decoration }
        if backdropShown != decoration.isEnabled { backdropShown = decoration.isEnabled }
    }

    private func save<T: Encodable>(_ value: T, forKey key: String) {
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        }
    }

    private static func load<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(type, from: $0) }
    }

    // MARK: - 色

    /// 書き込みに使う色（選んだ色に不透明度をかけたもの）
    var drawColor: RGBAColor { color.withAlpha(CGFloat(opacity)) }

    /// オリジナルの色を、最近使った色の先頭に入れる（replacingFirst: カラーパネルで動かしている間は先頭を差し替える）
    func rememberCustomColor(_ color: RGBAColor, replacingFirst: Bool) {
        guard !RGBAColor.palette.contains(color) else { return }
        var colors = customColors
        if replacingFirst, !colors.isEmpty { colors.removeFirst() }
        colors.removeAll { $0 == color }
        colors.insert(color, at: 0)
        customColors = Array(colors.prefix(3))
    }

    // MARK: - 太さ・文字の大きさ

    func lineWidth(for tool: Tool) -> CGFloat {
        lineWidths[tool.rawValue].map { CGFloat($0) } ?? LineWidths.defaultWidth(for: tool)
    }

    func setLineWidth(_ width: CGFloat, for tool: Tool) {
        guard LineWidths.tools.contains(tool), abs(lineWidth(for: tool) - width) > 0.01 else { return }
        lineWidths[tool.rawValue] = Double(width)
    }

    func stepFontSize(up: Bool) {
        fontSize = FontSizes.step(fontSize, up: up)
    }

    /// [ ] キー：いまのツール（文字なら文字の大きさ）の太さを、1 段階変える
    func stepLineWidth(up: Bool) {
        let target = optionsTool
        if target == .text {
            stepFontSize(up: up)
            return
        }
        guard LineWidths.tools.contains(target) else { return }
        let presets = LineWidths.presets(for: target)
        let current = lineWidth(for: target)
        let next = up
            ? presets.first { $0 > current + 0.01 } ?? presets.last
            : presets.last { $0 < current - 0.01 } ?? presets.first
        if let next { setLineWidth(next, for: target) }
    }

    // MARK: - スタイルの保存

    /// いまの色・不透明度・太さ・各ツールのオプションを、名前を付けたスタイルにする
    func makePreset(name: String) -> StylePreset {
        StylePreset(
            name: name,
            color: color,
            opacity: opacity,
            lineWidths: lineWidths,
            rectangle: rectangleStyle,
            ellipse: ellipseStyle,
            arrow: arrowStyle,
            counterSize: counterSize,
            counter: counterStyle,
            text: textStyle,
            fontSize: fontSize,
            textMark: textMarkStyle
        )
    }

    /// 保存したスタイルを呼び出す
    func apply(_ preset: StylePreset) {
        color = preset.color
        opacity = preset.opacity
        lineWidths = preset.lineWidths
        rectangleStyle = preset.rectangle
        ellipseStyle = preset.ellipse
        arrowStyle = preset.arrow
        counterSize = preset.counterSize
        counterStyle = preset.counter
        textStyle = preset.text
        fontSize = preset.fontSize
        // 文字マーカーを足す前に保存したスタイルには入っていないので、いまのままにする
        if let textMark = preset.textMark { textMarkStyle = textMark }
    }

    // MARK: - まとめ

    /// ツールバーで選んでいる見た目の設定一式
    var style: EditorStyle {
        var widths: [Tool: CGFloat] = [:]
        for tool in LineWidths.tools {
            widths[tool] = lineWidth(for: tool)
        }
        return EditorStyle(
            color: color,
            lineWidths: widths,
            rectangle: rectangleStyle,
            ellipse: ellipseStyle,
            arrow: arrowStyle,
            counterSize: counterSize,
            counter: counterStyle,
            text: textStyle,
            textMark: textMarkStyle,
            opacity: CGFloat(opacity)
        )
    }

    /// オプションの行に出すツール（入力中の文字 → 選んだ書き込み → いまのツール の順）
    var optionsTool: Tool {
        if isEditingText { return .text }
        return selectionTool ?? tool
    }
}
