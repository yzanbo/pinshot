import AppKit

/// 保存しておくスタイル（名前・色・不透明度・太さ・各ツールのオプション）
struct StylePreset: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var color: RGBAColor
    var opacity: Double
    var lineWidths: [String: Double]
    var rectangle: ShapeStyle
    var ellipse: ShapeStyle
    var arrow: ArrowStyle
    var counterSize: CounterSize
    var counter: CounterStyle
    var text: TextStyle
    var fontSize: CGFloat
    /// 文字マーカー（これを足す前に保存したスタイルには入っていない）
    var textMark: TextMarkStyle? = nil
}

/// 前の版（3 つの枠・名前なし）のスタイル。引き継ぎのためだけに使う
private struct LegacyStylePreset: Codable {
    var color: RGBAColor
    var opacity: Double
    var lineWidths: [String: Double]
    var rectangle: ShapeStyle
    var ellipse: ShapeStyle
    var arrow: ArrowStyle
    var counterSize: CounterSize
    var counter: CounterStyle
    var text: TextStyle
    var fontSize: CGFloat
}

/// 保存したスタイルの一覧（数の制限なし。どの画像のツールバーからも同じ一覧を使う）
@MainActor
final class StylePresetStore: ObservableObject {
    static let shared = StylePresetStore()

    private let key = "editor.stylePresets.v2"
    private let legacyKey = "editor.stylePresets"

    @Published private(set) var presets: [StylePreset] {
        didSet {
            if let data = try? JSONEncoder().encode(presets) {
                UserDefaults.standard.set(data, forKey: key)
            }
        }
    }

    private init() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: key),
           let saved = try? JSONDecoder().decode([StylePreset].self, from: data) {
            presets = saved
        } else if let data = defaults.data(forKey: legacyKey),
                  let legacy = try? JSONDecoder().decode([LegacyStylePreset?].self, from: data) {
            // 前の版の 3 つの枠を「スタイル 1」… の名前で引き継ぐ
            presets = legacy.enumerated().compactMap { index, item in
                guard let item else { return nil }
                return StylePreset(
                    name: "スタイル \(index + 1)",
                    color: item.color,
                    opacity: item.opacity,
                    lineWidths: item.lineWidths,
                    rectangle: item.rectangle,
                    ellipse: item.ellipse,
                    arrow: item.arrow,
                    counterSize: item.counterSize,
                    counter: item.counter,
                    text: item.text,
                    fontSize: item.fontSize
                )
            }
        } else {
            presets = []
        }
    }

    /// 新しく保存するときの名前の初期値（「スタイル 4」など、ほかと重ならない名前）
    var suggestedName: String {
        var number = presets.count + 1
        while presets.contains(where: { $0.name == "スタイル \(number)" }) { number += 1 }
        return "スタイル \(number)"
    }

    func add(_ preset: StylePreset) {
        presets.append(preset)
    }

    func rename(_ id: UUID, to name: String) {
        guard let index = presets.firstIndex(where: { $0.id == id }) else { return }
        presets[index].name = name
    }

    /// 名前はそのままで、中身をいまのスタイルにする
    func overwrite(_ id: UUID, with preset: StylePreset) {
        guard let index = presets.firstIndex(where: { $0.id == id }) else { return }
        var updated = preset
        updated.id = id
        updated.name = presets[index].name
        presets[index] = updated
    }

    func remove(_ id: UUID) {
        presets.removeAll { $0.id == id }
    }
}
